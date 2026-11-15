import Foundation

/// A Claude session's working stretch must last at least this long for a "finished" banner.
public let claudeFinishedThreshold: TimeInterval = 60

/// Times each session's working stretch: it starts when the session first goes working (or
/// waiting for approval, which counts as working) and ends when it goes done. Going idle
/// (or the session ending) throws the stretch away.
public struct WorkTimer: Sendable {
    private var startedAt: [String: Date] = [:]

    public init() {}

    /// Returns the stretch length when the session goes working → done, else nil.
    public mutating func phaseChanged(sessionId: String, to phase: SessionPhase, now: Date) -> TimeInterval? {
        switch phase {
        case .working, .waitingApproval:
            if startedAt[sessionId] == nil { startedAt[sessionId] = now }
            return nil
        case .idle:
            startedAt[sessionId] = nil
            return nil
        case .done:
            guard let start = startedAt.removeValue(forKey: sessionId) else { return nil }
            return max(0, now.timeIntervalSince(start))
        }
    }

    /// The session ended (or was pruned): forget its stretch.
    public mutating func forget(sessionId: String) {
        startedAt[sessionId] = nil
    }

    /// Keeps only stretches of sessions still known (bounds the map).
    public mutating func retain(sessionIds: Set<String>) {
        startedAt = startedAt.filter { sessionIds.contains($0.key) }
    }

    public var trackedCount: Int { startedAt.count }
}

/// "4 min 12 s", "45 s", "1 h 5 min" (seconds dropped from an hour on; zero parts dropped).
public func workDurationText(_ t: TimeInterval) -> String {
    let total = max(0, Int(t.rounded(.down)))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
    if m > 0 { return s > 0 ? "\(m) min \(s) s" : "\(m) min" }
    return "\(s) s"
}

/// The "<label> finished" banner (opens the Claude tab), or nil when the setting is off or
/// the stretch was shorter than `claudeFinishedThreshold`.
public func claudeFinishedBanner(sessionId: String, label: String, worked: TimeInterval?,
                                 enabled: Bool, now: Date) -> Banner? {
    guard enabled, let worked, worked >= claudeFinishedThreshold else { return nil }
    let name = label.isEmpty ? "Claude" : label
    return Banner(id: "claude:\(sessionId):\(Int(now.timeIntervalSince1970))", kind: .claudeFinished,
                  title: "\(name) finished", subtitle: "Claude · \(workDurationText(worked))", tab: .claude)
}

// MARK: - Quiet rules

/// What the Mac is doing right now (from `QuietMonitor` + Now Playing).
public struct QuietInputs: Equatable, Sendable {
    /// Microphone (default input) or a camera is in use by any app.
    public var inCall: Bool
    /// The frontmost app's focused window is full screen.
    public var fullScreenFront: Bool
    /// Now Playing reports playback.
    public var mediaPlaying: Bool
    /// A Focus is on (nil = unknown / not available → treated as off).
    public var focusOn: Bool?

    public init(inCall: Bool = false, fullScreenFront: Bool = false, mediaPlaying: Bool = false,
                focusOn: Bool? = nil) {
        self.inCall = inCall
        self.fullScreenFront = fullScreenFront
        self.mediaPlaying = mediaPlaying
        self.focusOn = focusOn
    }
}

/// Presenting: a call (mic/camera) or a full-screen video (full-screen front app + playback).
public func isPresenting(_ i: QuietInputs) -> Bool {
    i.inCall || (i.fullScreenFront && i.mediaPlaying)
}

/// Banners are dropped (still listed in Alerts) when this is true.
public func bannersQuiet(_ s: NotchySettings, _ i: QuietInputs) -> Bool {
    (s.quietWhilePresenting && isPresenting(i))
        || (s.respectFocus && i.focusOn == true)
        || hideForFullScreen(s, i)
}

/// Hide in full screen: the closed notch hides and hover doesn't open it (the volume pop-up
/// and approvals still show).
public func hideForFullScreen(_ s: NotchySettings, _ i: QuietInputs) -> Bool {
    s.hideInFullScreen && i.fullScreenFront
}

// MARK: - Keyboard tab switching

/// The visible tab `step` places from `current` (no wrap; clamps at the ends). A `current`
/// not in `tabs` moves from the first tab.
public func nextTab(_ tabs: [TabID], current: TabID, step: Int) -> TabID {
    guard !tabs.isEmpty else { return current }
    let i = tabs.firstIndex(of: current) ?? 0
    return tabs[min(max(i + step, 0), tabs.count - 1)]
}

// MARK: - Microphone: which apps count as a call

/// Bundle-id prefixes whose microphone use is not a call: dictation (Wispr Flow, Apple
/// dictation), Siri, and Notchy itself. Compared case-insensitively.
public let micIgnoredBundlePrefixes: [String] = [
    "com.electron.wispr-flow",
    "com.apple.dictationim", "com.apple.speech", "com.apple.speechrecognitioncore",
    "com.apple.corespeech", "com.apple.assistant", "com.apple.siri",
    "in.ujjwalkumar.notchy",
]

/// The mic counts as "in a call" when any process running audio input is not ignored.
/// A process without a bundle id (nil / empty) is unknown and counts.
public func micInCall(inputBundleIDs: [String?]) -> Bool {
    inputBundleIDs.contains { id in
        guard let id = id?.lowercased(), !id.isEmpty else { return true }
        return !micIgnoredBundlePrefixes.contains { id.hasPrefix($0) }
    }
}
