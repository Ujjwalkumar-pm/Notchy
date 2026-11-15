import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var artwork: Data?
    public var isPlaying: Bool
    public var bundleId: String?
    /// Track length in seconds, when the player reports one.
    public var duration: Double?
    /// Elapsed seconds as of `elapsedAt`.
    public var elapsed: Double?
    public var elapsedAt: Date?
    public var rate: Double
    /// nil when the player doesn't report a shuffle mode.
    public var shuffle: Bool?

    public init(title: String, artist: String, artwork: Data? = nil,
                isPlaying: Bool, bundleId: String? = nil,
                duration: Double? = nil, elapsed: Double? = nil, elapsedAt: Date? = nil,
                rate: Double? = nil, shuffle: Bool? = nil) {
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedAt = elapsedAt
        self.rate = rate ?? (isPlaying ? 1 : 0)
        self.shuffle = shuffle
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.bundleId = bundleId
    }
}

public enum AdapterLine: Sendable {
    case data(NowPlayingInfo?)
    case ignored
}

private let maxArtworkBytes = 2 * 1024 * 1024

/// Parses one line of `mediaremote-adapter stream` output.
public func parseAdapterLine(_ line: Substring) -> AdapterLine {
    guard let raw = String(line).data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
          (obj["type"] as? String) == "data",
          let payload = obj["payload"] as? [String: Any] else { return .ignored }

    let title = payload["title"] as? String ?? ""
    let artist = payload["artist"] as? String ?? ""
    if title.isEmpty && artist.isEmpty { return .data(nil) }

    var artwork: Data?
    if let b64 = payload["artworkData"] as? String,
       let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
       !d.isEmpty, d.count <= maxArtworkBytes {
        artwork = d
    }
    let rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 0
    var at: Date?
    if let ts = payload["timestamp"] as? String { at = parseISO8601(ts) }
    let duration = (payload["duration"] as? NSNumber)?.doubleValue
    let shuffle = (payload["shuffleMode"] as? NSNumber).map { $0.intValue != 1 }
    return .data(NowPlayingInfo(title: title, artist: artist, artwork: artwork,
                                isPlaying: rate > 0,
                                bundleId: payload["bundleIdentifier"] as? String,
                                duration: (duration ?? 0) > 0 ? duration : nil,
                                elapsed: (payload["elapsedTime"] as? NSNumber)?.doubleValue,
                                elapsedAt: at, rate: rate, shuffle: shuffle))
}

private func parseISO8601(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s)
}

/// Elapsed seconds at `now`: the reported elapsed advanced by the time since it was reported
/// (while playing), clamped to [0, duration]. Without a usable timestamp, the reported value.
public func elapsedNow(_ info: NowPlayingInfo, now: Date) -> Double? {
    guard var e = info.elapsed else { return nil }
    if info.isPlaying, let at = info.elapsedAt {
        e += max(0, now.timeIntervalSince(at)) * info.rate
    }
    if let d = info.duration { e = min(e, d) }
    return max(0, e)
}

/// Seek target in seconds for a bar fraction, clamped to 0...duration; nil without a usable duration.
public func seekPosition(fraction: Double, duration: Double?) -> Double? {
    guard let duration, duration > 0 else { return nil }
    return min(max(fraction, 0), 1) * duration
}

/// Bar fraction (0...1) for a pointer x within a bar of `width`.
public func scrubFraction(x: Double, width: Double) -> Double {
    guard width > 0 else { return 0 }
    return min(max(x / width, 0), 1)
}

public struct NowPlayingState: Sendable {
    public init() {}
    public private(set) var info: NowPlayingInfo?
    public private(set) var lastPlayingAt: Date?
    /// After a local seek: the target, the local elapsedAt, and when stale stream positions stop being ignored.
    private var seekGuard: (target: Double, at: Date, until: Date)?

    public mutating func apply(_ info: NowPlayingInfo?, now: Date) {
        var info = info
        if let g = seekGuard {
            if now >= g.until { seekGuard = nil }
            else if var i = info, let e = i.elapsed, abs(e - g.target) > 2 {
                // Stale pre-seek position: keep the local one, take everything else.
                i.elapsed = g.target; i.elapsedAt = g.at; info = i
            } else { seekGuard = nil }
        }
        // The moment playback stops (playing -> paused) also counts as "last playing",
        // so the 10-minute window starts at the pause.
        if info?.isPlaying == true || self.info?.isPlaying == true { lastPlayingAt = now }
        self.info = info
    }

    /// Applies a seek locally (elapsed = target, elapsedAt = now) so the bar holds the new
    /// position until the next stream line confirms it.
    public mutating func applySeek(to seconds: Double, now: Date) {
        guard info != nil else { return }
        info?.elapsed = seconds
        info?.elapsedAt = now
        seekGuard = (seconds, now, now.addingTimeInterval(1.5))
    }

    public func visible(now: Date) -> Bool {
        guard let info else { return false }
        if info.isPlaying { return true }
        guard let last = lastPlayingAt else { return false }
        return now.timeIntervalSince(last) <= 600
    }
}

/// PIDs of orphaned adapter `stream` processes left by a previous Notchy that crashed or was
/// SIGKILLed: lines of `ps -axww -o pid=,ppid=,command=` whose parent is launchd (1) and whose
/// command is exactly `/usr/bin/perl <script> <anything> stream …` for THIS bundle's script.
/// Every other process (other apps' adapters, `send` runs, live children) is left alone.
public func orphanedAdapterPIDs(psOutput: String, script: String) -> [Int32] {
    let prefix = "/usr/bin/perl " + script + " "
    var pids: [Int32] = []
    for line in psOutput.split(separator: "\n") {
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count == 3, let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
              ppid == 1, pid > 1 else { continue }
        let command = String(fields[2])
        guard command.hasPrefix(prefix) else { continue }
        let args = command.dropFirst(prefix.count).split(separator: " ")
        // args: <framework> stream [--options…]
        guard args.count >= 2, args[1] == "stream" else { continue }
        pids.append(pid)
    }
    return pids
}
