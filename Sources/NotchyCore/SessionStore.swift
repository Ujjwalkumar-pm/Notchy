import Foundation

public enum SessionPhase: Equatable, Sendable {
    case working(tool: String?)
    case waitingApproval
    case idle
    case done
}

extension SessionPhase {
    /// Lower = more urgent: waiting for you, working, done, idle.
    public var urgencyRank: Int {
        switch self {
        case .waitingApproval: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        }
    }

    /// Title-case phase label shown in the Claude tab (AUDIT C3).
    public var label: String {
        switch self {
        case .working: return "Working"
        case .waitingApproval: return "Waiting for you"
        case .idle: return "Idle"
        case .done: return "Done"
        }
    }
}

public struct SessionInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var phase: SessionPhase
    public var updatedAt: Date
}

public enum SessionTransition: Equatable, Sendable {
    case becameWaiting(id: String)
    case finished(id: String)
}

public struct SessionStore: Sendable {
    private var byId: [String: SessionInfo] = [:]

    public init() {}

    /// By urgency (waiting, working, done, idle), then most recently updated first (AUDIT C1).
    public var sessions: [SessionInfo] {
        byId.values.sorted {
            let a = $0.phase.urgencyRank, b = $1.phase.urgencyRank
            if a != b { return a < b }
            return $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
        }
    }

    @discardableResult
    public mutating func apply(_ e: HookEvent, now: Date) -> SessionTransition? {
        let prior = byId[e.sessionId]?.phase
        let phase: SessionPhase
        var transition: SessionTransition?
        switch e.eventName {
        case "SessionStart": phase = .idle
        case "UserPromptSubmit": phase = .working(tool: nil)
        case "PostToolUse": phase = prior == .waitingApproval ? .waitingApproval : .working(tool: nil)
        case "PreToolUse": phase = prior == .waitingApproval ? .waitingApproval : .working(tool: e.toolName)
        case "PermissionRequest":
            phase = .waitingApproval
            if prior != .waitingApproval { transition = .becameWaiting(id: e.sessionId) }
        case "Notification":
            guard e.notificationType == "idle_prompt" else { return nil }
            phase = .idle
        case "Stop":
            phase = .done
            if prior != .done { transition = .finished(id: e.sessionId) }
        case "SessionEnd":
            byId[e.sessionId] = nil
            return nil
        default:
            return nil
        }
        byId[e.sessionId] = SessionInfo(id: e.sessionId, label: Self.label(for: e),
                                        phase: phase, updatedAt: now)
        return transition
    }

    /// Idle/done sessions untouched for this long are dropped by `prune`.
    public static let staleAfter: TimeInterval = 45 * 60

    /// Drops idle/done sessions last updated more than `maxAge` ago. Sessions in
    /// `pendingSessionIds` (an approval is still queued) are always kept.
    @discardableResult
    public mutating func prune(now: Date, maxAge: TimeInterval = staleAfter,
                               pendingSessionIds: Set<String> = []) -> Int {
        let before = byId.count
        byId = byId.filter { id, info in
            guard info.phase == .idle || info.phase == .done, !pendingSessionIds.contains(id) else { return true }
            return now.timeIntervalSince(info.updatedAt) <= maxAge
        }
        return before - byId.count
    }

    public mutating func markApprovalResolved(sessionId: String, now: Date) {
        guard var info = byId[sessionId], info.phase == .waitingApproval else { return }
        info.phase = .working(tool: nil)
        info.updatedAt = now
        byId[sessionId] = info
    }

    private static func label(for e: HookEvent) -> String {
        if let t = e.sessionTitle, !t.isEmpty { return t }
        let last = (e.cwd as NSString).lastPathComponent
        return last.isEmpty ? e.cwd : last
    }
}
