import Foundation
import CoreGraphics
import NotchyCore

func runArmingGateChecks() {
    let t0 = Date(timeIntervalSince1970: 5000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    let a = UUID(), b = UUID()

    do { // armsAfterEnterAndDwell: enter at 0.2 s, armed once both 0.5 s and 0.4 s dwell passed
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0.2))
        check("gateNotArmedEarly", g.armed(now: at(0.55)) == nil)
        check("gateArmedAfterDwell", g.armed(now: at(0.6)) == a)
    }
    do { // appearDelayStillApplies: enter at once, dwell met at 0.4 but appear delay not until 0.5
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0.0))
        check("gateAppearDelay", g.armed(now: at(0.45)) == nil && g.armed(now: at(0.5)) == a)
    }
    do { // neverEnteredNeverArms
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        check("gateNeedsEnter", g.armed(now: at(10)) == nil)
    }
    do { // insideAtAppearMustLeaveAndReenter
        var g = ArmingGate()
        g.show(a, pointerInside: true, pointerMoved: true, now: at(0))
        g.show(a, pointerInside: true, pointerMoved: true, now: at(2))
        check("gateInsideAtAppearNotArmed", g.armed(now: at(5)) == nil)
        g.pointer(inside: false, moved: true, now: at(5))
        g.pointer(inside: true, moved: true, now: at(6))
        check("gateReenterDwell", g.armed(now: at(6.3)) == nil && g.armed(now: at(6.4)) == a)
    }
    do { // leavingDisarms
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0.1))
        check("gateArmedBeforeLeave", g.armed(now: at(1)) == a)
        g.pointer(inside: false, moved: true, now: at(1.1))
        check("gateLeaveDisarms", g.armed(now: at(2)) == nil)
    }
    do { // newIdDisarms (pointer still on the card → must leave and re-enter)
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0.1))
        g.show(b, pointerInside: true, pointerMoved: true, now: at(1))
        check("gateNewIdDisarms", g.armed(now: at(3)) == nil && g.requestId == b)
    }
    do { // disarmAfterDecision
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0.1))
        g.disarm()
        g.show(a, pointerInside: true, pointerMoved: true, now: at(2))
        check("gateDisarmHolds", g.armed(now: at(3)) == nil)
    }
    do { // noCard
        var g = ArmingGate()
        g.show(nil, pointerInside: true, pointerMoved: true, now: at(0))
        check("gateNoCard", g.armed(now: at(5)) == nil)
    }

    // The card counts as shown only on a settled open panel with a real rect.
    let cardR = CGRect(x: 0, y: 0, width: 100, height: 80)
    check("gate.cardVisibleSettled", cardVisibleForGate(frameAnimating: false, expanded: true, rect: cardR))
    check("gate.cardHiddenWhileAnimating", !cardVisibleForGate(frameAnimating: true, expanded: true, rect: cardR))
    check("gate.cardHiddenWhenClosed", !cardVisibleForGate(frameAnimating: false, expanded: false, rect: cardR))
    check("gate.cardHiddenNullOrEmpty", !cardVisibleForGate(frameAnimating: false, expanded: true, rect: .null)
          && !cardVisibleForGate(frameAnimating: false, expanded: true, rect: CGRect(x: 5, y: 5, width: 0, height: 10))
          && !cardVisibleForGate(frameAnimating: false, expanded: true, rect: nil))
    // Growing frame under a resting pointer: hidden while animating, then appears with the
    // pointer inside → must leave first, never armed without movement.
    do {
        var g = ArmingGate()
        let id = UUID()
        for t in stride(from: 0.0, to: 0.4, by: 0.05) {
            let shown = cardVisibleForGate(frameAnimating: true, expanded: true, rect: t < 0.2 ? .null : cardR)
            g.show(shown ? id : nil, pointerInside: t >= 0.2, pointerMoved: false, now: at(t))
        }
        g.show(cardVisibleForGate(frameAnimating: false, expanded: true, rect: cardR) ? id : nil,
               pointerInside: true, pointerMoved: false, now: at(0.4))
        g.pointer(inside: true, moved: false, now: at(3))
        check("gate.growUnderRestingPointer", g.armed(now: at(5)) == nil)
    }

    // Entries need real pointer movement (the card can grow over a still pointer without any
    // frame animation, e.g. a content-height change re-framing the open panel instantly).
    do { // still pointer, card grows over it → never arms
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: false, now: at(0))
        g.show(a, pointerInside: true, pointerMoved: false, now: at(0.1))
        for t in stride(from: 0.15, to: 5, by: 0.05) { g.show(a, pointerInside: true, pointerMoved: false, now: at(t)) }
        check("gate.stillGrowNeverArms", g.armed(now: at(5)) == nil)
        // Stricter rule: moving around inside afterwards still doesn't arm; leave + re-enter does.
        g.show(a, pointerInside: true, pointerMoved: true, now: at(5.1))
        check("gate.stillThenMoveInsideMustLeave", g.armed(now: at(7)) == nil)
        g.show(a, pointerInside: false, pointerMoved: true, now: at(7.1))
        g.show(a, pointerInside: true, pointerMoved: true, now: at(7.2))
        check("gate.realReentryArms", g.armed(now: at(7.55)) == nil && g.armed(now: at(7.6)) == a)
    }
    do { // moved in → arms after dwell
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: false, now: at(0))
        g.show(a, pointerInside: true, pointerMoved: true, now: at(0.3))
        check("gate.movedInArms", g.armed(now: at(0.65)) == nil && g.armed(now: at(0.7)) == a)
    }
    do { // card moves away from a still pointer, then back over it → still not an entry
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.show(a, pointerInside: false, pointerMoved: false, now: at(1))
        g.show(a, pointerInside: true, pointerMoved: false, now: at(1.05))
        check("gate.cardBackUnderStillPointer", g.armed(now: at(4)) == nil)
    }
    do { // progress (dwell line): 0 until a real entry, < 1 until armed, exactly 1 when armed
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        check("gate.progressZeroOutside", g.progress(now: at(1)) == 0)
        g.pointer(inside: true, moved: true, now: at(1))
        let mid = g.progress(now: at(1.2))
        check("gate.progressHalfway", abs(mid - 0.5) < 0.01)
        var everCompleteEarly = false
        for t in stride(from: 1.0, to: 1.4, by: 0.01) {
            let armed = g.armed(now: at(t)) != nil
            if !armed && g.progress(now: at(t)) >= 1 { everCompleteEarly = true }
            if armed && g.progress(now: at(t)) != 1 { everCompleteEarly = true }
        }
        check("gate.progressNeverCompleteBeforeArmed", !everCompleteEarly)
        check("gate.progressCapped", g.armed(now: at(1.39)) == nil && g.progress(now: at(1.39)) == ArmingGate.progressCapBeforeArmed)
        check("gate.progressOneWhenArmed", g.armed(now: at(1.4)) == a && g.progress(now: at(1.4)) == 1)
        g.pointer(inside: false, moved: true, now: at(2))
        check("gate.progressResetsOnLeave", g.progress(now: at(2)) == 0)
    }
    do { // progress follows the slower clock (appear delay) and stays 0 when must-leave-first
        var g = ArmingGate()
        g.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        g.pointer(inside: true, moved: true, now: at(0))
        check("gate.progressAppearClock", abs(g.progress(now: at(0.25)) - 0.5) < 0.01
              && g.progress(now: at(0.45)) < 1 && g.armed(now: at(0.45)) == nil)
        var h = ArmingGate()
        h.show(a, pointerInside: true, pointerMoved: true, now: at(0))
        check("gate.progressMustLeaveFirst", h.progress(now: at(3)) == 0)
        // Card grows under a still pointer: no progress either.
        var k = ArmingGate()
        k.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        k.show(a, pointerInside: true, pointerMoved: false, now: at(1))
        check("gate.progressStillGrowZero", k.progress(now: at(3)) == 0)
        // After a decision / Show all (disarm) with the pointer inside: back to 0.
        var d = ArmingGate()
        d.show(a, pointerInside: false, pointerMoved: true, now: at(0))
        d.pointer(inside: true, moved: true, now: at(0.6))
        _ = d.armed(now: at(1.1))
        d.disarm()
        d.show(a, pointerInside: true, pointerMoved: true, now: at(1.2))
        check("gate.progressZeroAfterDisarm", d.progress(now: at(3)) == 0 && d.armed(now: at(3)) == nil)
    }
}
