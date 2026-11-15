import Foundation
import CoreGraphics
import NotchyCore

func runClickThroughChecks() {
    let p0 = CGPoint(x: 100, y: 900), p1 = CGPoint(x: 103, y: 900)

    do { // closed → never interactive
        var g = ContentGate()
        check("contentClosedNotInteractive", !g.update(expanded: false, settled: true, pointer: p0))
    }
    do { // still pointer through and after the open: never interactive
        var g = ContentGate()
        g.update(expanded: true, settled: false, pointer: p0)
        g.update(expanded: true, settled: true, pointer: p0)
        check("contentStillPointerBlocked", !g.update(expanded: true, settled: true, pointer: p0))
    }
    do { // movement during the animation doesn't count; only after settling
        var g = ContentGate()
        g.update(expanded: true, settled: false, pointer: p0)
        check("contentMoveWhileAnimatingBlocked", !g.update(expanded: true, settled: false, pointer: p1))
        check("contentFirstSettledIsReference", !g.update(expanded: true, settled: true, pointer: p1))
        check("contentMovedAfterSettle", g.update(expanded: true, settled: true, pointer: p0))
    }
    do { // sub-threshold jitter doesn't count
        var g = ContentGate()
        g.update(expanded: true, settled: true, pointer: p0)
        check("contentJitterBlocked",
              !g.update(expanded: true, settled: true, pointer: CGPoint(x: 100.4, y: 900.3)))
    }
    do { // stays interactive; closing resets; reopening needs a new move
        var g = ContentGate()
        g.update(expanded: true, settled: true, pointer: p0)
        g.update(expanded: true, settled: true, pointer: p1)
        check("contentStaysInteractive", g.update(expanded: true, settled: false, pointer: p1))
        check("contentCloseResets", !g.update(expanded: false, settled: false, pointer: p1))
        g.update(expanded: true, settled: true, pointer: p1)
        check("contentReopenBlocked", !g.update(expanded: true, settled: true, pointer: p1) && !g.interactive)
    }
    do { // reset while open (approval card appeared): needs a new move from the new reference
        var g = ContentGate()
        g.update(expanded: true, settled: true, pointer: p0)
        g.update(expanded: true, settled: true, pointer: p1)
        g.reset()
        check("contentResetBlocks", !g.update(expanded: true, settled: true, pointer: p1))
        check("contentResetThenMove", g.update(expanded: true, settled: true, pointer: p0))
    }

    let t0 = Date(timeIntervalSince1970: 9000)
    check("bannerActionNotShownYet", !bannerActionAllowed(fullyShownAt: nil, now: t0, growGateArmed: false))
    check("bannerActionTooSoon",
          !bannerActionAllowed(fullyShownAt: t0, now: t0.addingTimeInterval(0.3), growGateArmed: false))
    check("bannerActionAfterDelay",
          bannerActionAllowed(fullyShownAt: t0, now: t0.addingTimeInterval(0.5), growGateArmed: false))
    check("bannerActionPointerNotMoved",
          !bannerActionAllowed(fullyShownAt: t0, now: t0.addingTimeInterval(5), growGateArmed: true))
}

func runContentGateResetChecks() {
    let a = CGRect(x: 10, y: 40, width: 300, height: 80)
    check("gateResetOnCardAppear", contentGateNeedsReset(oldCard: nil, newCard: a))
    check("gateResetOnCardDisappear", contentGateNeedsReset(oldCard: a, newCard: nil))
    check("gateResetOnCardHeightChange",
          contentGateNeedsReset(oldCard: a, newCard: CGRect(x: 10, y: 40, width: 300, height: 120)))
    check("gateResetOnCardMinYChange",
          contentGateNeedsReset(oldCard: a, newCard: CGRect(x: 10, y: 52, width: 300, height: 80)))
    check("gateNoResetSameCard", !contentGateNeedsReset(oldCard: a, newCard: a))
    check("gateNoResetSubThresholdJitter",
          !contentGateNeedsReset(oldCard: a, newCard: CGRect(x: 10, y: 40.3, width: 300, height: 80.4)))
    check("gateNoResetBothNil", !contentGateNeedsReset(oldCard: nil, newCard: nil))
}
