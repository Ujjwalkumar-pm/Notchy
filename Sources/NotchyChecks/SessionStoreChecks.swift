import Foundation
import NotchyCore

private func ev(_ name: String, sid: String = "s1", cwd: String = "/Users/me/projects/demo",
                tool: String? = nil, title: String? = nil, notif: String? = nil) -> HookEvent {
    var o: [String: Any] = ["session_id": sid, "cwd": cwd, "hook_event_name": name]
    if let tool { o["tool_name"] = tool }
    if let title { o["session_title"] = title }
    if let notif { o["notification_type"] = notif }
    let data = try! JSONSerialization.data(withJSONObject: o)
    return try! JSONDecoder().decode(HookEvent.self, from: data)
}

func runSessionStoreChecks() {
    let t0 = Date(timeIntervalSince1970: 1000)

    var s = SessionStore()
    _ = s.apply(ev("SessionStart"), now: t0)
    check("startIsIdle", s.sessions.first?.phase == .idle)
    _ = s.apply(ev("UserPromptSubmit"), now: t0)
    check("startThenPrompt", s.sessions.first?.phase == .working(tool: nil))

    s = SessionStore()
    _ = s.apply(ev("PreToolUse", tool: "Bash"), now: t0)
    check("preToolSetsTool", s.sessions.first?.phase == .working(tool: "Bash"))
    _ = s.apply(ev("PostToolUse", tool: "Bash"), now: t0)
    check("postToolClearsTool", s.sessions.first?.phase == .working(tool: nil))

    s = SessionStore()
    let w = s.apply(ev("PermissionRequest", tool: "Bash"), now: t0)
    check("permissionWaits", w == .becameWaiting(id: "s1") && s.sessions.first?.phase == .waitingApproval)

    s.markApprovalResolved(sessionId: "s1", now: t0)
    check("resolvedReturnsToWorking", s.sessions.first?.phase == .working(tool: nil))
    _ = s.apply(ev("Stop"), now: t0)
    s.markApprovalResolved(sessionId: "s1", now: t0)
    s.markApprovalResolved(sessionId: "nope", now: t0)
    check("resolvedNoOpOtherwise", s.sessions.count == 1 && s.sessions.first?.phase == .done)

    s = SessionStore()
    _ = s.apply(ev("UserPromptSubmit"), now: t0)
    let f = s.apply(ev("Stop"), now: t0)
    check("stopFinishes", f == .finished(id: "s1") && s.sessions.first?.phase == .done)

    s = SessionStore()
    _ = s.apply(ev("SessionStart"), now: t0)
    _ = s.apply(ev("SessionEnd"), now: t0)
    check("endRemoves", s.sessions.isEmpty)

    s = SessionStore()
    _ = s.apply(ev("UserPromptSubmit"), now: t0)
    _ = s.apply(ev("Notification", notif: "idle_prompt"), now: t0)
    check("idlePromptIdles", s.sessions.first?.phase == .idle)
    _ = s.apply(ev("UserPromptSubmit"), now: t0)
    _ = s.apply(ev("Notification", notif: "other"), now: t0)
    check("otherNotificationIgnored", s.sessions.first?.phase == .working(tool: nil))

    s = SessionStore()
    _ = s.apply(ev("SessionStart"), now: t0)
    check("labelFromCwd", s.sessions.first?.label == "demo")
    s = SessionStore()
    _ = s.apply(ev("SessionStart", title: "Fix bug"), now: t0)
    check("labelPrefersTitle", s.sessions.first?.label == "Fix bug")

    s = SessionStore()
    _ = s.apply(ev("SessionStart", sid: "a"), now: t0)
    _ = s.apply(ev("SessionStart", sid: "b"), now: t0.addingTimeInterval(5))
    check("orderNewestFirst", s.sessions.map(\.id) == ["b", "a"])
    _ = s.apply(ev("UserPromptSubmit", sid: "a"), now: t0.addingTimeInterval(10))
    check("orderUpdatesOnEvent", s.sessions.map(\.id) == ["a", "b"])

    // Urgency order: waiting, working, done, idle; newest first within a group.
    s = SessionStore()
    _ = s.apply(ev("SessionStart", sid: "idleNew"), now: t0.addingTimeInterval(50))
    _ = s.apply(ev("Stop", sid: "done"), now: t0.addingTimeInterval(1))
    _ = s.apply(ev("UserPromptSubmit", sid: "workOld"), now: t0.addingTimeInterval(2))
    _ = s.apply(ev("UserPromptSubmit", sid: "workNew"), now: t0.addingTimeInterval(3))
    _ = s.apply(ev("PermissionRequest", sid: "wait"), now: t0.addingTimeInterval(0))
    check("orderByUrgency", s.sessions.map(\.id) == ["wait", "workNew", "workOld", "done", "idleNew"])
    check("phaseLabels", SessionPhase.working(tool: "Bash").label == "Working"
          && SessionPhase.waitingApproval.label == "Waiting for you"
          && SessionPhase.idle.label == "Idle" && SessionPhase.done.label == "Done")

    s = SessionStore()
    let u = s.apply(ev("SomethingNew"), now: t0)
    check("unknownEventIgnored", u == nil && s.sessions.isEmpty)
    _ = s.apply(ev("PreToolUse", tool: "Read"), now: t0)
    check("unseenSessionCreated", s.sessions.count == 1)

    s = SessionStore()
    _ = s.apply(ev("PermissionRequest", tool: "Bash"), now: t0)
    _ = s.apply(ev("PreToolUse", tool: "Read"), now: t0.addingTimeInterval(1))
    let waitAfterPre = s.sessions.first?.phase
    _ = s.apply(ev("PostToolUse", tool: "Read"), now: t0.addingTimeInterval(2))
    check("waitingSurvivesToolEvents",
          waitAfterPre == .waitingApproval && s.sessions.first?.phase == .waitingApproval
          && s.sessions.first?.updatedAt == t0.addingTimeInterval(2))
    _ = s.apply(ev("UserPromptSubmit"), now: t0)
    check("promptClearsWaiting", s.sessions.first?.phase == .working(tool: nil))

    s = SessionStore()
    _ = s.apply(ev("PermissionRequest"), now: t0)
    check("noRepeatWaitingChime", s.apply(ev("PermissionRequest"), now: t0) == nil)
    s = SessionStore()
    _ = s.apply(ev("Stop"), now: t0)
    check("noRepeatFinishedChime", s.apply(ev("Stop"), now: t0) == nil)

    do { // prune (injectable clock: `now` is passed in)
        var p = SessionStore()
        _ = p.apply(ev("SessionStart", sid: "idleOld"), now: t0)
        _ = p.apply(ev("Stop", sid: "doneOld"), now: t0)
        _ = p.apply(ev("UserPromptSubmit", sid: "workingOld"), now: t0)
        _ = p.apply(ev("PermissionRequest", sid: "waitingOld"), now: t0)
        _ = p.apply(ev("Stop", sid: "doneFresh"), now: t0.addingTimeInterval(40 * 60))
        _ = p.apply(ev("Stop", sid: "donePending"), now: t0)
        let at44 = p
        var q = at44
        check("pruneKeepsUnder45", q.prune(now: t0.addingTimeInterval(45 * 60)) == 0 && q.sessions.count == 6)
        let n = p.prune(now: t0.addingTimeInterval(45 * 60 + 1), pendingSessionIds: ["donePending"])
        let ids = Set(p.sessions.map(\.id))
        check("pruneDropsIdleDoneOld", n == 2 && !ids.contains("idleOld") && !ids.contains("doneOld"))
        check("pruneKeepsWorking", ids.contains("workingOld"))
        check("pruneKeepsWaiting", ids.contains("waitingOld"))
        check("pruneKeepsFresh", ids.contains("doneFresh"))
        check("pruneKeepsPending", ids.contains("donePending"))
        check("pruneDefault45Min", SessionStore.staleAfter == 2700)
    }
}
