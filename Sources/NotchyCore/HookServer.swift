import Foundation
import Network

public enum HookServerError: Error, Equatable {
    case portInUse
    case failed(String)
}

/// Minimal localhost HTTP/1.1 server for Claude Code `type: "http"` hooks.
/// All mutable state is touched only on `queue`.
///
/// Callbacks run on the server's private serial queue and must return quickly
/// (hop to another actor/queue for real work). Do not set a callback property
/// from inside a callback (it syncs on that queue).
public final class HookServer: @unchecked Sendable {
    public typealias PermissionHandler = @Sendable (HookEvent, @escaping @Sendable (PermissionDecision) -> Void) -> Void

    private var _onEvent: (@Sendable (HookEvent) -> Void)?
    private var _onPermission: PermissionHandler?
    private var _onPermissionCancelled: (@Sendable (HookEvent) -> Void)?

    public var onEvent: (@Sendable (HookEvent) -> Void)? {
        get { queue.sync { _onEvent } }
        set { queue.sync { _onEvent = newValue } }
    }
    public var onPermission: PermissionHandler? {
        get { queue.sync { _onPermission } }
        set { queue.sync { _onPermission = newValue } }
    }
    /// Fired when a held permission connection closes (client gone) or times out
    /// before a reply; receives the event that was given to `onPermission`.
    public var onPermissionCancelled: (@Sendable (HookEvent) -> Void)? {
        get { queue.sync { _onPermissionCancelled } }
        set { queue.sync { _onPermissionCancelled = newValue } }
    }

    private let port: UInt16
    private let readTimeout: TimeInterval
    private let holdTimeout: TimeInterval
    private var readTimers: [ObjectIdentifier: DispatchWorkItem] = [:]
    private let queue = DispatchQueue(label: "notchy.hookserver")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private static let maxBody = 1_048_576
    /// Most permission connections held open at once; beyond this, reply `{}` at once (fail open).
    public static let maxHeld = 32
    private var heldCount = 0

    public init(port: UInt16 = 7850, readTimeout: TimeInterval = 10, holdTimeout: TimeInterval = 160) {
        self.port = port
        self.readTimeout = readTimeout
        self.holdTimeout = holdTimeout
    }

    public func start() throws {
        dispatchPrecondition(condition: .notOnQueue(queue))
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw HookServerError.failed("bad port") }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        let l: NWListener
        do { l = try NWListener(using: params) } catch { throw Self.map(error) }

        let sem = DispatchSemaphore(value: 0)
        let result = Result()
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: if result.set(nil) { sem.signal() }
            case .failed(let e): if result.set(e) { sem.signal() }
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        if sem.wait(timeout: .now() + 2) == .timedOut {
            l.cancel()
            throw HookServerError.failed("listener start timed out")
        }
        if let e = result.error {
            l.cancel()
            throw Self.map(e)
        }
        l.stateUpdateHandler = nil
        queue.sync { listener = l }
    }

    public func stop() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.sync {
            listener?.cancel()
            listener = nil
            for c in connections.values { c.cancel() }
            connections.removeAll()
            for t in readTimers.values { t.cancel() }
            readTimers.removeAll()
        }
    }

    private final class ReplyFlag: @unchecked Sendable { var done = false; var expiry: DispatchWorkItem? }

    private final class Result: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private(set) var error: NWError?
        func set(_ e: NWError?) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true; error = e; return true
        }
    }

    private static func map(_ error: Error) -> HookServerError {
        if let e = error as? NWError, case .posix(let code) = e, code == .EADDRINUSE { return .portInUse }
        return .failed("\(error)")
    }

    // MARK: connection handling (queue)

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        connections[id] = c
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[id] = nil
                self?.readTimers.removeValue(forKey: id)?.cancel()
            default: break
            }
        }
        let timer = DispatchWorkItem { [weak self] in
            self?.connections[id] = nil
            self?.readTimers[id] = nil
            c.cancel()
        }
        readTimers[id] = timer
        queue.asyncAfter(deadline: .now() + readTimeout, execute: timer)
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil { c.cancel(); return }

            let sep = Data("\r\n\r\n".utf8)
            if let r = buf.range(of: sep) {
                let head = String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let parts = (lines.first ?? "").split(separator: " ")
                var length = 0
                var badLength = false
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    headers[name] = value
                    if name == "content-length" {
                        if let n = Int(value), n >= 0 {
                            length = n
                        } else {
                            badLength = true
                        }
                    }
                }
                if !self.isAllowed(headers) {
                    self.rejectEarly(c, status: 403)
                    return
                }
                if badLength {
                    self.endRead(c)
                    self.send(c, status: 400, body: Data("{}".utf8))
                    return
                }
                if length > Self.maxBody {
                    self.rejectTooLarge(c)
                    return
                }
                let bodyStart = r.upperBound
                if buf.count - buf.distance(from: buf.startIndex, to: bodyStart) >= length {
                    let body = Data(buf[bodyStart..<buf.index(bodyStart, offsetBy: length)])
                    let method = parts.count > 0 ? String(parts[0]) : ""
                    let path = parts.count > 1 ? String(parts[1]) : ""
                    self.route(c, method: method, path: path, body: body)
                    return
                }
            } else if buf.count > 65_536 {
                self.send(c, status: 413, body: Data("{}".utf8))
                return
            }
            if isComplete { c.cancel(); return }
            self.receive(c, buffer: buf)
        }
    }

    private func endRead(_ c: NWConnection) {
        readTimers.removeValue(forKey: ObjectIdentifier(c))?.cancel()
    }

    /// Browsers and other non-hook clients are refused: no `Origin`, `Host` must be
    /// this port on 127.0.0.1/localhost, and `Content-Type` must be application/json.
    private func isAllowed(_ headers: [String: String]) -> Bool {
        if headers["origin"] != nil { return false }
        let host = headers["host"]?.lowercased() ?? ""
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return false }
        let type = headers["content-type"]?.split(separator: ";", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return type == "application/json"
    }

    /// Reply 413, then keep draining what the client is still sending so it
    /// sees the response rather than a connection reset; hard-close after 2 s.
    private func rejectTooLarge(_ c: NWConnection) {
        rejectEarly(c, status: 413)
    }

    /// Reply `status` before the body has been read, drain, hard-close after 2 s.
    private func rejectEarly(_ c: NWConnection, status: Int) {
        endRead(c)
        let out = Data("HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".utf8)
        c.send(content: out, completion: .contentProcessed { _ in })
        queue.asyncAfter(deadline: .now() + 2) { c.cancel() }
        drain(c)
    }

    private func drain(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil { c.cancel(); return }
            self?.drain(c)
        }
    }

    private func route(_ c: NWConnection, method: String, path: String, body: Data) {
        endRead(c)
        let empty = Data("{}".utf8)
        switch (method, path) {
        case ("POST", "/hooks/event"):
            if let ev = try? JSONDecoder().decode(HookEvent.self, from: body) { _onEvent?(ev) }
            send(c, status: 200, body: empty)
        case ("POST", "/hooks/permission"):
            guard let ev = try? JSONDecoder().decode(HookEvent.self, from: body),
                  let handler = _onPermission, heldCount < Self.maxHeld else {
                send(c, status: 200, body: empty)
                return
            }
            heldCount += 1
            let flag = ReplyFlag() // only touched on queue
            let id = ObjectIdentifier(c)
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, !flag.done else { return }
                flag.done = true
                self.heldCount -= 1
                self.connections[id] = nil
                c.cancel()
                self._onPermissionCancelled?(ev)
            }
            flag.expiry = expiry
            queue.asyncAfter(deadline: .now() + holdTimeout, execute: expiry)
            armHeldReceive(c, flag: flag, event: ev)
            handler(ev) { [weak self] decision in
                guard let self else { return }
                self.queue.async {
                    if flag.done { return }
                    flag.done = true
                    self.heldCount -= 1
                    flag.expiry?.cancel()
                    self.send(c, status: 200, body: decision.responseBody())
                }
            }
        default:
            send(c, status: 404, body: empty)
        }
    }

    private func armHeldReceive(_ c: NWConnection, flag: ReplyFlag, event: HookEvent) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            guard let self, !flag.done else { return }
            if isComplete || error != nil {
                flag.done = true
                self.heldCount -= 1
                flag.expiry?.cancel()
                self.connections[ObjectIdentifier(c)] = nil
                c.cancel()
                self._onPermissionCancelled?(event)
            } else {
                self.armHeldReceive(c, flag: flag, event: event)
            }
        }
    }

    private func send(_ c: NWConnection, status: Int, body: Data) {
        var out = Data("HTTP/1.1 \(status) \(Self.reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            c.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Payload Too Large"
        }
    }
}
