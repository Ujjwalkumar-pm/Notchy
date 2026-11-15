import Foundation
import NotchyCore

private final class Replies: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [PermissionDecision] = []
    func record(_ d: PermissionDecision) { lock.lock(); items.append(d); lock.unlock() }
    var all: [PermissionDecision] { lock.lock(); defer { lock.unlock() }; return items }
}

@MainActor
private func req(_ sid: String = "s1", at: Date = Date()) -> ApprovalRequest {
    ApprovalRequest(id: UUID(), sessionId: sid, label: "proj", toolName: "Bash", summary: "ls", receivedAt: at)
}

@MainActor
private func approvalChecks() {
    do { // fifo
        let q = ApprovalQueue(); let r = Replies()
        let a = req(), b = req()
        q.enqueue(a) { r.record($0) }
        q.enqueue(b) { r.record($0) }
        check("fifoFirst", q.current?.id == a.id)
        check("fifoCount", q.pendingCount == 2)
        q.resolve(a.id, .allow)
        check("fifoSecond", q.current?.id == b.id)
        q.resolve(b.id, .deny(message: "no"))
        check("fifoEmpty", q.current == nil && q.pendingCount == 0)
        check("fifoReplies", r.all == [.allow, .deny(message: "no")])
    }
    do { // replyOnce
        let q = ApprovalQueue(); let r = Replies()
        let a = req()
        q.enqueue(a) { r.record($0) }
        q.resolve(a.id, .allow)
        q.resolve(a.id, .deny(message: "x"))
        q.resolve(UUID(), .allow)
        check("replyOnce", r.all == [.allow])
    }
    do { // non-head resolve keeps current
        let q = ApprovalQueue(); let r = Replies()
        let a = req(), b = req()
        q.enqueue(a) { r.record($0) }
        q.enqueue(b) { r.record($0) }
        q.resolve(b.id, .allow)
        check("nonHeadKeepsCurrent", q.current?.id == a.id && q.pendingCount == 1 && r.all == [.allow])
    }
    do { // timeout
        let now = Date()
        let q = ApprovalQueue(); let r = Replies()
        q.enqueue(req(at: now.addingTimeInterval(-121))) { r.record($0) }
        q.expire(now: now)
        check("timeoutGivesNone", r.all == [.none] && q.current == nil)
        q.expire(now: now)
        check("timeoutOnce", r.all == [.none])
    }
    do { // not expired at 119
        let now = Date()
        let q = ApprovalQueue(); let r = Replies()
        q.enqueue(req(at: now.addingTimeInterval(-119))) { r.record($0) }
        q.expire(now: now)
        check("notExpiredAt119", r.all.isEmpty && q.pendingCount == 1 && q.current != nil)
    }
    do { // expire head advances current
        let now = Date()
        let q = ApprovalQueue(); let r = Replies()
        let old = req(at: now.addingTimeInterval(-200)), fresh = req(at: now)
        q.enqueue(old) { r.record($0) }
        q.enqueue(fresh) { r.record($0) }
        q.expire(now: now)
        check("expireAdvances", q.current?.id == fresh.id && r.all == [.none])
    }
    do { // dropSession
        let q = ApprovalQueue(); let r = Replies()
        let a = req("dead"), b = req("live"), c = req("dead")
        q.enqueue(a) { r.record($0) }
        q.enqueue(b) { r.record($0) }
        q.enqueue(c) { r.record($0) }
        q.dropSession("dead")
        check("staleDroppedOnSessionEnd", q.current?.id == b.id && q.pendingCount == 1 && r.all == [.none, .none])
    }
    do { // shutdown
        let q = ApprovalQueue(); let r = Replies()
        for _ in 0..<3 { q.enqueue(req()) { r.record($0) } }
        q.resolveAllForShutdown()
        check("pendingResolvedOnShutdown", r.all == [.none, .none, .none] && q.pendingCount == 0 && q.current == nil)
    }
}

func runApprovalQueueChecks() {
    MainActor.assumeIsolated { approvalChecks() }
}
