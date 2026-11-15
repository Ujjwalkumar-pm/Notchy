import Foundation
import Network
import NotchyCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

private func post(_ path: String, _ body: Data, port: UInt16 = 17850, timeout: TimeInterval = 5) -> (status: Int, body: Data)? {
    var r = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    r.httpMethod = "POST"
    r.httpBody = body
    r.timeoutInterval = timeout
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let sem = DispatchSemaphore(value: 0)
    let out = Box<(Int, Data)?>(nil)
    URLSession.shared.dataTask(with: r) { data, resp, _ in
        if let h = resp as? HTTPURLResponse { out.value = (h.statusCode, data ?? Data()) }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 1)
    return out.value.map { (status: $0.0, body: $0.1) }
}

private func eventJSON(_ name: String, extra: String = "") -> Data {
    Data(#"{"session_id":"s1","cwd":"/tmp/p","hook_event_name":"\#(name)","tool_name":"Bash","tool_input":{"command":"ls"\#(extra)}}"#.utf8)
}

private func parsed(_ d: Data) -> NSDictionary? {
    (try? JSONSerialization.jsonObject(with: d)) as? NSDictionary
}

/// Raw TCP exchange. Returns the response text ("" if none before the wait elapsed or peer closed).
/// If `closeAfterSend`, the connection is cancelled right after the send.
private func raw(_ text: String, port: UInt16, closeAfterSend: Bool = false, wait: TimeInterval = 3) -> String {
    let q = DispatchQueue(label: "check.raw")
    let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let sem = DispatchSemaphore(value: 0)
    let got = Box<Data>(Data())
    c.stateUpdateHandler = { st in
        if case .ready = st {
            c.send(content: Data(text.utf8), completion: .contentProcessed { _ in
                if closeAfterSend { c.cancel(); sem.signal() }
            })
            if !closeAfterSend {
                @Sendable func loop() {
                    c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, done, err in
                        if let d { got.value.append(d) }
                        if done || err != nil { sem.signal() } else { loop() }
                    }
                }
                loop()
            }
        }
    }
    c.start(queue: q)
    _ = sem.wait(timeout: .now() + wait)
    c.cancel()
    return String(decoding: got.value, as: UTF8.self)
}

/// Standard headers a real hook client sends (Claude Code's axios / the curl command hook).
private func hdrs(_ port: UInt16) -> String {
    "Host: 127.0.0.1:\(port)\r\nContent-Type: application/json\r\n"
}

/// Opens a connection, sends `text`, and leaves it open (caller cancels).
private func openAndSend(_ text: String, port: UInt16) -> NWConnection {
    let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let sem = DispatchSemaphore(value: 0)
    c.stateUpdateHandler = { st in
        if case .ready = st {
            c.send(content: Data(text.utf8), completion: .contentProcessed { _ in sem.signal() })
        }
    }
    c.start(queue: DispatchQueue(label: "check.held"))
    _ = sem.wait(timeout: .now() + 2)
    return c
}

private func runHookServerOriginChecks() {
    let s = HookServer(port: 17854)
    let seen = Box<Int>(0)
    s.onEvent = { _ in seen.value += 1 }
    do { try s.start() } catch { check("originStart", false); return }
    let body = String(decoding: eventJSON("PreToolUse"), as: UTF8.self)
    func req(_ headers: String) -> String {
        raw("POST /hooks/event HTTP/1.1\r\n\(headers)Content-Length: \(body.utf8.count)\r\n\r\n\(body)", port: 17854)
    }
    let ct = "Content-Type: application/json\r\n"
    check("okWithHostAndType", req("Host: 127.0.0.1:17854\r\n" + ct).hasPrefix("HTTP/1.1 200"))
    check("okLocalhostCharset", req("Host: localhost:17854\r\nContent-Type: application/json; charset=utf-8\r\n")
          .hasPrefix("HTTP/1.1 200"))
    check("forbiddenOrigin", req("Host: 127.0.0.1:17854\r\n" + ct + "Origin: http://evil.example\r\n")
          .hasPrefix("HTTP/1.1 403"))
    check("forbiddenOriginNull", req("Host: 127.0.0.1:17854\r\n" + ct + "Origin: null\r\n").hasPrefix("HTTP/1.1 403"))
    check("forbiddenBadHost", req("Host: evil.example:17854\r\n" + ct).hasPrefix("HTTP/1.1 403"))
    check("forbiddenWrongPort", req("Host: 127.0.0.1:80\r\n" + ct).hasPrefix("HTTP/1.1 403"))
    check("forbiddenNoHost", req(ct).hasPrefix("HTTP/1.1 403"))
    check("forbiddenTextPlain", req("Host: 127.0.0.1:17854\r\nContent-Type: text/plain\r\n").hasPrefix("HTTP/1.1 403"))
    check("forbiddenNoType", req("Host: 127.0.0.1:17854\r\n").hasPrefix("HTTP/1.1 403"))
    check("forbiddenFormType", req("Host: 127.0.0.1:17854\r\nContent-Type: application/x-www-form-urlencoded\r\n")
          .hasPrefix("HTTP/1.1 403"))
    let permBody = String(decoding: eventJSON("PermissionRequest"), as: UTF8.self)
    check("forbiddenPermissionOrigin", raw("POST /hooks/permission HTTP/1.1\r\nHost: 127.0.0.1:17854\r\n" + ct
          + "Origin: http://evil.example\r\nContent-Length: \(permBody.utf8.count)\r\n\r\n\(permBody)", port: 17854)
          .hasPrefix("HTTP/1.1 403"))
    check("forbiddenNoCallback", seen.value == 2)
    s.stop()
}

private func runHookServerCapChecks() {
    let port: UInt16 = 17853
    let s = HookServer(port: port, holdTimeout: 20)
    let calls = Box<Int>(0)
    let cancelled = Box<Int>(0)
    s.onPermission = { _, _ in calls.value += 1 }
    s.onPermissionCancelled = { _ in cancelled.value += 1 }
    do { try s.start() } catch { check("capStart", false); return }
    let body = String(decoding: eventJSON("PermissionRequest"), as: UTF8.self)
    let text = "POST /hooks/permission HTTP/1.1\r\n\(hdrs(port))Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
    var held: [NWConnection] = []
    for _ in 0..<HookServer.maxHeld { held.append(openAndSend(text, port: port)) }
    var deadline = Date().addingTimeInterval(3)
    while calls.value < HookServer.maxHeld && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    check("capHolds32", calls.value == HookServer.maxHeld)
    let t0 = Date()
    let over = post("/hooks/permission", eventJSON("PermissionRequest"), port: port, timeout: 3)
    check("capOverflowFailsOpen", over?.status == 200 && over.flatMap { parsed($0.body) } == [:]
          && Date().timeIntervalSince(t0) < 1.5)
    check("capOverflowNoCallback", calls.value == HookServer.maxHeld)
    for c in held { c.cancel() }
    deadline = Date().addingTimeInterval(3)
    while cancelled.value < HookServer.maxHeld && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    check("capReleasedOnClose", cancelled.value == HookServer.maxHeld)
    let again = openAndSend(text, port: port)
    deadline = Date().addingTimeInterval(2)
    while calls.value < HookServer.maxHeld + 1 && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    check("capHoldsAgainAfterRelease", calls.value == HookServer.maxHeld + 1)
    again.cancel()
    s.stop()
}

private func runHookServerHardeningChecks() {
    let cancelled = Box<[String]>([])
    let late = Box<(@Sendable (PermissionDecision) -> Void)?>(nil)
    let s = HookServer(port: 17852, readTimeout: 0.5, holdTimeout: 1.0)
    s.onPermission = { _, reply in late.value = reply }
    s.onPermissionCancelled = { cancelled.value.append($0.sessionId) }
    do { try s.start() } catch { check("hardeningStart", false); return }

    do { // negativeContentLengthRejected
        let resp = raw("POST /hooks/event HTTP/1.1\r\n\(hdrs(17852))Content-Length: -5\r\n\r\n", port: 17852)
        check("negativeContentLengthRejected", resp.hasPrefix("HTTP/1.1 400"))
        let r = post("/hooks/event", eventJSON("PreToolUse"), port: 17852)
        check("servesAfterBadLength", r?.status == 200)
    }
    do { // silentClientTimesOut: server closes a silent connection (receive returns without our sending)
        let t0 = Date()
        let resp = raw("POST /hooks/event HTTP/1.1\r\n\(hdrs(17852))Content-Length: 10\r\n\r\n", port: 17852, wait: 4)
        let dt = Date().timeIntervalSince(t0)
        check("silentClientTimesOut", resp.isEmpty && dt < 3)
    }
    do { // heldClientCloseDetected
        let body = String(decoding: eventJSON("PermissionRequest"), as: UTF8.self)
        _ = raw("POST /hooks/permission HTTP/1.1\r\n\(hdrs(17852))Content-Length: \(body.utf8.count)\r\n\r\n\(body)", port: 17852, closeAfterSend: true)
        let deadline = Date().addingTimeInterval(0.8)
        while cancelled.value.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        check("heldClientCloseDetected", cancelled.value == ["s1"])
        late.value?(.allow) // must not crash
        Thread.sleep(forTimeInterval: 0.1)
        check("lateReplyAfterCloseSafe", post("/hooks/event", eventJSON("PreToolUse"), port: 17852)?.status == 200)
    }
    do { // heldTimeoutReleases
        cancelled.value = []
        let body = String(decoding: eventJSON("PermissionRequest"), as: UTF8.self)
        _ = raw("POST /hooks/permission HTTP/1.1\r\n\(hdrs(17852))Content-Length: \(body.utf8.count)\r\n\r\n\(body)", port: 17852, wait: 2.5)
        check("heldTimeoutReleases", cancelled.value == ["s1"])
    }
    s.stop()
}

func runHookServerChecks() {
    runHookServerHardeningChecks()
    runHookServerOriginChecks()
    runHookServerCapChecks()
    let server = HookServer(port: 17850)
    let seen = Box<[String]>([])
    let held = Box<(@Sendable (PermissionDecision) -> Void)?>(nil)
    let permCalls = Box<Int>(0)
    server.onEvent = { seen.value.append($0.sessionId) }
    server.onPermission = { _, reply in
        permCalls.value += 1
        held.value = reply
    }
    do { try server.start() } catch { check("serverStarts", false); return }

    do { // eventRoundTrip
        let r = post("/hooks/event", eventJSON("PreToolUse"))
        check("eventStatus", r?.status == 200)
        check("eventBody", r.flatMap { parsed($0.body) } == [:])
        check("eventReceived", seen.value == ["s1"])
    }
    do { // permissionHeldThenAllowed
        let sem = DispatchSemaphore(value: 0)
        let out = Box<(Int, Data)?>(nil)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:17850/hooks/permission")!)
        req.httpMethod = "POST"; req.httpBody = eventJSON("PermissionRequest"); req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            if let h = resp as? HTTPURLResponse { out.value = (h.statusCode, d ?? Data()) }
            sem.signal()
        }.resume()
        let early = sem.wait(timeout: .now() + 0.3)
        check("permissionHeld", early == .timedOut && permCalls.value == 1)
        held.value?(.allow)
        held.value?(.deny(message: "late")) // ignored
        _ = sem.wait(timeout: .now() + 5)
        let expect = parsed(PermissionDecision.allow.responseBody())
        check("permissionAllowed", out.value?.0 == 200 && out.value.flatMap { parsed($0.1) } == expect)
    }
    do { // badJsonFailsOpen
        let r1 = post("/hooks/permission", Data("not json".utf8))
        check("badJsonPermission", r1?.status == 200 && r1.flatMap { parsed($0.body) } == [:])
        let r2 = post("/hooks/event", Data("{".utf8))
        check("badJsonEvent", r2?.status == 200 && r2.flatMap { parsed($0.body) } == [:])
        check("badJsonNoCallback", permCalls.value == 1 && seen.value == ["s1"])
    }
    do { // largeBodyAccepted
        let pad = String(repeating: "a", count: 900_000)
        let r = post("/hooks/event", eventJSON("PostToolUse", extra: #","pad":"\#(pad)""#))
        check("largeBodyAccepted", r?.status == 200)
        check("largeBodyDecoded", seen.value.count == 2)
    }
    do { // tooLarge + unknown path
        let r = post("/hooks/event", Data(repeating: 0x20, count: 1_048_577))
        check("tooLarge413", r?.status == 413)
        let n = post("/nope", Data("{}".utf8))
        check("unknownPath404", n?.status == 404)
    }
    do { // portInUseThrows
        let second = HookServer(port: 17850)
        var threw = false
        do { try second.start() } catch HookServerError.portInUse { threw = true } catch {}
        check("portInUseThrows", threw)
        second.stop()
    }
    do { // onPermission nil replies immediately
        let s = HookServer(port: 17851)
        do { try s.start() } catch { check("nilPermStart", false); return }
        let r = post("/hooks/permission", eventJSON("PermissionRequest"), port: 17851, timeout: 2)
        check("nilPermission", r?.status == 200 && r.flatMap { parsed($0.body) } == [:])
        s.stop(); s.stop()
    }
    server.stop()
    server.stop()
}
