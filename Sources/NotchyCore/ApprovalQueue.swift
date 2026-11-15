import Foundation
import Combine

public struct ApprovalRequest: Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let label: String
    public let toolName: String
    public let summary: String
    public let receivedAt: Date

    public init(id: UUID, sessionId: String, label: String, toolName: String,
                summary: String, receivedAt: Date) {
        self.id = id
        self.sessionId = sessionId
        self.label = label
        self.toolName = toolName
        self.summary = summary
        self.receivedAt = receivedAt
    }
}

@MainActor
public final class ApprovalQueue: ObservableObject {
    private struct Entry {
        let request: ApprovalRequest
        let reply: @Sendable (PermissionDecision) -> Void
    }

    private var entries: [Entry] = []

    /// Oldest pending request.
    @Published public private(set) var current: ApprovalRequest?

    public var pendingCount: Int { entries.count }

    public init() {}

    public func enqueue(_ r: ApprovalRequest, reply: @escaping @Sendable (PermissionDecision) -> Void) {
        entries.append(Entry(request: r, reply: reply))
        refreshCurrent()
    }

    public func resolve(_ id: UUID, _ d: PermissionDecision) {
        guard let i = entries.firstIndex(where: { $0.request.id == id }) else { return }
        let e = entries.remove(at: i)
        refreshCurrent()
        e.reply(d)
    }

    public func expire(now: Date, timeout: TimeInterval = 120) {
        removeAll(where: { now.timeIntervalSince($0.request.receivedAt) > timeout })
    }

    public func dropSession(_ sessionId: String) {
        removeAll(where: { $0.request.sessionId == sessionId })
    }

    public func resolveAllForShutdown() {
        removeAll(where: { _ in true })
    }

    private func removeAll(where match: (Entry) -> Bool) {
        let removed = entries.filter(match)
        guard !removed.isEmpty else { return }
        entries.removeAll(where: match)
        refreshCurrent()
        for e in removed { e.reply(.none) }
    }

    private func refreshCurrent() {
        let head = entries.first?.request
        if current?.id != head?.id { current = head }
    }
}
