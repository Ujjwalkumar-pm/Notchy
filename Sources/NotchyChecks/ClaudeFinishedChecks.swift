import Foundation
import NotchyCore

func runClaudeFinishedChecks() {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let working = SessionPhase.working(tool: nil)

    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        _ = w.phaseChanged(sessionId: "a", to: .working(tool: "Bash"), now: t0.addingTimeInterval(30))
        let d = w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(252))
        check("work.longFinish", d == 252 && w.trackedCount == 0)
    }
    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        let d = w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(59))
        let b = claudeFinishedBanner(sessionId: "a", label: "web-app", worked: d, enabled: true, now: t0)
        check("work.shortNil", d == 59 && b == nil)
        let at60 = claudeFinishedBanner(sessionId: "a", label: "web-app", worked: 60, enabled: true, now: t0)
        check("work.threshold60", at60 != nil)
        let off = claudeFinishedBanner(sessionId: "a", label: "web-app", worked: 252, enabled: false, now: t0)
        check("work.settingOff", off == nil)
    }
    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        _ = w.phaseChanged(sessionId: "a", to: .waitingApproval, now: t0.addingTimeInterval(20))
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0.addingTimeInterval(80))
        let d = w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(100))
        check("work.approvalCounts", d == 100)
        var w2 = WorkTimer()
        _ = w2.phaseChanged(sessionId: "b", to: .waitingApproval, now: t0)
        check("work.approvalStarts", w2.phaseChanged(sessionId: "b", to: .done, now: t0.addingTimeInterval(70)) == 70)
    }
    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        _ = w.phaseChanged(sessionId: "a", to: .idle, now: t0.addingTimeInterval(100))
        check("work.idleResets", w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(200)) == nil)
    }
    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        _ = w.phaseChanged(sessionId: "b", to: working, now: t0.addingTimeInterval(10))
        let a = w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(90))
        let again = w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(95))
        let b = w.phaseChanged(sessionId: "b", to: .done, now: t0.addingTimeInterval(130))
        check("work.perSession", a == 90 && again == nil && b == 120)
        // A new prompt after done starts a fresh stretch.
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0.addingTimeInterval(200))
        check("work.freshStretch", w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(230)) == 30)
    }
    do {
        var w = WorkTimer()
        _ = w.phaseChanged(sessionId: "a", to: working, now: t0)
        _ = w.phaseChanged(sessionId: "b", to: working, now: t0)
        w.forget(sessionId: "a")
        w.retain(sessionIds: ["c"])
        check("work.forgetRetain", w.trackedCount == 0
              && w.phaseChanged(sessionId: "a", to: .done, now: t0.addingTimeInterval(100)) == nil)
    }
    do {
        let b = claudeFinishedBanner(sessionId: "s1", label: "web-app", worked: 252, enabled: true, now: t0)
        check("work.bannerText", b?.title == "web-app finished" && b?.subtitle == "Claude · 4 min 12 s"
              && b?.tab == .claude && b?.kind == .claudeFinished)
        let e = claudeFinishedBanner(sessionId: "s1", label: "", worked: 61, enabled: true, now: t0)
        check("work.bannerEmptyLabel", e?.title == "Claude finished")
        let later = claudeFinishedBanner(sessionId: "s1", label: "x", worked: 61, enabled: true,
                                         now: t0.addingTimeInterval(120))
        check("work.bannerIdPerFinish", b?.id != later?.id)
        check("work.durationText", workDurationText(45) == "45 s" && workDurationText(120) == "2 min"
              && workDurationText(3900) == "1 h 5 min" && workDurationText(3600) == "1 h"
              && workDurationText(252.9) == "4 min 12 s")
    }

    // Quiet rules
    let on = NotchySettings.defaults
    var off = on
    off.quietWhilePresenting = false
    off.respectFocus = false
    off.hideInFullScreen = false
    check("quiet.none", !bannersQuiet(on, QuietInputs()))
    check("quiet.call", bannersQuiet(on, QuietInputs(inCall: true)) && !bannersQuiet(off, QuietInputs(inCall: true)))
    var noHide = on
    noHide.hideInFullScreen = false
    check("quiet.fullScreenVideo", bannersQuiet(noHide, QuietInputs(fullScreenFront: true, mediaPlaying: true))
          && !bannersQuiet(noHide, QuietInputs(fullScreenFront: true, mediaPlaying: false))
          && !bannersQuiet(noHide, QuietInputs(fullScreenFront: false, mediaPlaying: true)))
    check("quiet.focus", bannersQuiet(on, QuietInputs(focusOn: true)) && !bannersQuiet(on, QuietInputs(focusOn: nil))
          && !bannersQuiet(off, QuietInputs(focusOn: true)))
    check("quiet.hideFullScreen", bannersQuiet(on, QuietInputs(fullScreenFront: true))
          && hideForFullScreen(on, QuietInputs(fullScreenFront: true))
          && !hideForFullScreen(noHide, QuietInputs(fullScreenFront: true))
          && !hideForFullScreen(on, QuietInputs()))

    // Keyboard tab switching
    let tabs: [TabID] = [.music, .claude, .alerts]
    check("tabs.nextRight", nextTab(tabs, current: .music, step: 1) == .claude)
    check("tabs.nextLeft", nextTab(tabs, current: .alerts, step: -1) == .claude)
    check("tabs.nextClamps", nextTab(tabs, current: .alerts, step: 1) == .alerts
          && nextTab(tabs, current: .music, step: -1) == .music)
    check("tabs.nextMissing", nextTab(tabs, current: .calendar, step: 1) == .claude
          && nextTab([], current: .calendar, step: 1) == .calendar)
}

func runMicCallChecks() {
    check("mic.wisprOnly", !micInCall(inputBundleIDs: ["com.electron.wispr-flow.accessibility-mac-app"]))
    check("mic.teams", micInCall(inputBundleIDs: ["com.microsoft.teams2"]))
    check("mic.braveHelper", micInCall(inputBundleIDs: ["com.brave.Browser.helper"]))
    check("mic.unknown", micInCall(inputBundleIDs: [nil]) && micInCall(inputBundleIDs: [""]))
    check("mic.empty", !micInCall(inputBundleIDs: []))
    check("mic.ignoredPlusCall", micInCall(inputBundleIDs: ["com.electron.wispr-flow", "us.zoom.xos"]))
    check("mic.dictationSiriNotchy", !micInCall(inputBundleIDs: ["com.apple.SpeechRecognitionCore.speechrecognitiond",
                                                                "com.apple.Siri", "in.ujjwalkumar.notchy"]))
}
