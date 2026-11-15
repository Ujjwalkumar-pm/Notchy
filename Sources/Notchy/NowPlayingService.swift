import Foundation
import NotchyCore

enum MediaCommand: Int {
    case togglePlayPause = 2, next = 4, previous = 5
    /// Adapter `shuffle` function rather than `send`; the target mode comes from the current state.
    case toggleShuffle = -1
}

/// Shuffle modes accepted by the adapter's `shuffle` function (MRShuffleMode: 1 off, 3 on).
private let shuffleOff = 1, shuffleOn = 3

/// Runs the bundled mediaremote-adapter (`stream`) as the single long-lived helper process
/// and publishes what it reports.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var state = NowPlayingState()

    private var process: Process?
    private var generation = 0
    private var restart = RestartPolicy()
    private var restartWork: DispatchWorkItem?
    private var stopping = true
    private var gotData = false
    private var runStart = Date()
    private var loggedMissing = false

    private static let adapterDir = Bundle.main.resourceURL?.appendingPathComponent("mediaremote-adapter")
    private var script: String? { Self.adapterDir?.appendingPathComponent("mediaremote-adapter.pl").path }
    private var framework: String? { Self.adapterDir?.appendingPathComponent("MediaRemoteAdapter.framework").path }

    private func resourcesPresent() -> Bool {
        guard let script, let framework,
              FileManager.default.isReadableFile(atPath: script),
              FileManager.default.fileExists(atPath: framework) else {
            if !loggedMissing {
                loggedMissing = true
                notchyLog.error("Now Playing adapter not bundled; music disabled")
            }
            return false
        }
        return true
    }

    func start() {
#if NOTCHY_CAPTURE
        return
#endif
        guard stopping else { return }
        stopping = false
        restart.reset()
        reapOrphans()
        launch()
    }

    /// One-shot at start: a Notchy that crashed or was SIGKILLed leaves its `stream` child
    /// reparented to launchd. Terminate only this bundle's own adapter `stream` processes with
    /// parent 1 so there is never more than one long-lived helper.
    private func reapOrphans() {
        guard let script else { return }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axww", "-o", "pid=,ppid=,command="]
        let out = Pipe()
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        ps.standardInput = FileHandle.nullDevice
        do { try ps.run() } catch { return }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let pids = orphanedAdapterPIDs(psOutput: String(decoding: data, as: UTF8.self), script: script)
        for pid in pids {
            kill(pid, SIGTERM)
            notchyLog.notice("Now Playing: terminated orphaned adapter pid \(pid)")
        }
    }

    func stop() {
        stopping = true
        restartWork?.cancel()
        restartWork = nil
        generation += 1
        guard let p = process else { return }
        process = nil
        (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        guard p.isRunning else { return }
        p.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while p.isRunning && Date() < deadline { usleep(10_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    func send(_ command: MediaCommand) {
#if NOTCHY_CAPTURE
        captureSend(command)
        return
#endif
        guard resourcesPresent(), let script, let framework else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        if command == .toggleShuffle {
            let on = state.info?.shuffle ?? false
            p.arguments = [script, framework, "shuffle", String(on ? shuffleOff : shuffleOn)]
        } else {
            p.arguments = [script, framework, "send", String(command.rawValue)]
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { notchyLog.error("Now Playing send failed: \(String(describing: error), privacy: .public)") }
    }

    /// Seeks the current track and applies the target locally so the bar doesn't snap back
    /// before the next stream line.
    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        state.applySeek(to: seconds, now: Date())
#if NOTCHY_CAPTURE
        return
#endif
        guard resourcesPresent(), let script, let framework else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, "seek", String(Int(seconds * 1_000_000))]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let rounded = (seconds * 10).rounded() / 10
        p.terminationHandler = { proc in
            notchyLog.notice("seek \(String(format: "%.1f", rounded), privacy: .public) → exit \(proc.terminationStatus, privacy: .public)")
        }
        do { try p.run() } catch { notchyLog.error("Now Playing seek failed: \(String(describing: error), privacy: .public)") }
    }

    // MARK: - Private

    private func launch() {
        guard !stopping, process == nil, resourcesPresent(), let script, let framework else { return }
        generation += 1
        let gen = generation
        gotData = false
        runStart = Date()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, "stream", "--no-diff", "--debounce=100"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        // The handler runs on a serial background queue; the splitter is only touched there.
        let splitter = SplitterBox()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            let parsed = splitter.feed(chunk).map { parseAdapterLine($0) }
            if parsed.isEmpty { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(parsed, generation: gen) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.terminated(generation: gen) }
            }
        }
        do {
            try p.run()
            process = p
            notchyLog.info("Now Playing adapter started")
        } catch {
            notchyLog.error("Now Playing adapter failed to launch: \(String(describing: error), privacy: .public)")
            out.fileHandleForReading.readabilityHandler = nil
            scheduleRestart()
        }
    }

    private func handle(_ lines: [AdapterLine], generation gen: Int) {
        guard gen == generation else { return }
        let now = Date()
        for line in lines {
            if case .data(let info) = line {
                gotData = true
                state.apply(info, now: now)
            }
        }
    }

    private func terminated(generation gen: Int) {
        guard gen == generation, !stopping else { return }
        process = nil
        // Only a run that delivered data AND lasted a minute counts as healthy.
        if gotData && Date().timeIntervalSince(runStart) >= 60 { restart.reset() }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopping else { return }
        guard let delay = restart.nextDelay() else {
            notchyLog.error("Now Playing adapter gave up after repeated failures; hiding music row")
            state.apply(nil, now: Date())
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.launch() }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Reference holder so the readability handler can mutate the splitter safely
/// (the handler is serial per file handle).
private final class SplitterBox: @unchecked Sendable {
    private var splitter = LineSplitter()
    func feed(_ d: Data) -> [Substring] { splitter.feed(d) }
}

#if NOTCHY_CAPTURE
/// Capture build only: a demo track instead of the Now Playing stream; commands act on it
/// locally (nothing is ever sent to a real player).
extension NowPlayingService {
    func captureSet(_ info: NowPlayingInfo?) { state.apply(info, now: Date()) }

    fileprivate func captureSend(_ command: MediaCommand) {
        guard var i = state.info else { return }
        switch command {
        case .toggleShuffle: i.shuffle = !(i.shuffle ?? false)
        case .togglePlayPause:
            let now = Date()
            i.elapsed = elapsedNow(i, now: now); i.elapsedAt = now
            i.isPlaying.toggle(); i.rate = i.isPlaying ? 1 : 0
        default: return
        }
        state.apply(i, now: Date())
    }
}
#endif
