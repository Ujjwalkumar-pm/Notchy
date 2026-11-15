import Foundation
import CoreGraphics
import NotchyCore

/// AUDIT §12 (motion) and §13 (accessibility) decision helpers.
func runMotionChecks() {
    // N1: Reduce Motion → Fade at 0.15 s for every animated style and speed; None stays instant.
    let animated: [PanelAnimation] = [.spring, .smooth, .snappy, .fade]
    check("motion.reduceFade", animated.allSatisfy { a in AnimationSpeed.allCases.allSatisfy { s in
        let m = effectiveOpenClose(a, s, reduceMotion: true)
        return m.style == .fade && m.duration == 0.15 } })
    check("motion.reduceNone", AnimationSpeed.allCases.allSatisfy {
        let m = effectiveOpenClose(.none, $0, reduceMotion: true); return m.style == .none && m.duration == 0 })
    check("motion.offUnchanged", PanelAnimation.allCases.allSatisfy { a in AnimationSpeed.allCases.allSatisfy { s in
        let m = effectiveOpenClose(a, s, reduceMotion: false)
        return m.style == a && m.duration == animationDuration(a, s) } })
    check("motion.caption", showsReduceMotionCaption(.spring, reduceMotion: true)
          && !showsReduceMotionCaption(.none, reduceMotion: true)
          && !showsReduceMotionCaption(.spring, reduceMotion: false))
    // N1: banners / pop-up cross-fade only under Reduce Motion.
    check("motion.closedGrow", closedFrameStyle(reduceMotion: false, fromBare: true, toBare: false) == .grow
          && closedFrameStyle(reduceMotion: false, fromBare: false, toBare: true) == .grow)
    check("motion.closedFades", closedFrameStyle(reduceMotion: true, fromBare: true, toBare: false) == .fadeIn
          && closedFrameStyle(reduceMotion: true, fromBare: false, toBare: true) == .fadeOut
          && closedFrameStyle(reduceMotion: true, fromBare: false, toBare: false) == .instant
          && closedFrameStyle(reduceMotion: true, fromBare: true, toBare: true) == .instant)
    // N2: content fade timing follows the frame duration.
    let open = contentFadeTiming(duration: 0.35, opening: true)
    let close = contentFadeTiming(duration: 0.35, opening: false)
    check("motion.contentOpen", open.map { abs($0.delay - 0.08) < 1e-9 && abs($0.duration - 0.21) < 1e-9 } == true)
    check("motion.contentClose", close.map { $0.delay == 0 && abs($0.duration - 0.14) < 1e-9 } == true)
    check("motion.contentInstant", contentFadeTiming(duration: 0, opening: true) == nil
          && contentFadeTiming(duration: 0, opening: false) == nil)
    check("motion.contentSlow", contentFadeTiming(duration: animationDuration(.spring, .slow), opening: true)
          .map { abs($0.duration - 0.6 * 0.525) < 1e-9 } == true)
    check("motion.rise", contentRiseOffset(reduceMotion: false) == 4 && contentRiseOffset(reduceMotion: true) == 0)
    // N3: one gentler spring curve at every speed.
    check("motion.springCurve", animationCurve(.spring).map { $0 == (0.32, 1.1, 0.6, 1) } == true)
    // Y3: one 1.04 pulse, static under Reduce Motion.
    check("motion.nowPulse", nowRingPulsePeak(reduceMotion: false) == 1.04 && nowRingPulsePeak(reduceMotion: true) == 1)

    // Y2: scrubber steps ±10 s, clamped.
    check("a11y.scrubStep", scrubberAdjusted(elapsed: 101, duration: 326, increment: true) == 111
          && scrubberAdjusted(elapsed: 101, duration: 326, increment: false) == 91)
    check("a11y.scrubClamp", scrubberAdjusted(elapsed: 4, duration: 326, increment: false) == 0
          && scrubberAdjusted(elapsed: 320, duration: 326, increment: true) == 326
          && scrubberAdjusted(elapsed: .nan, duration: 326, increment: true) == 10)
    check("a11y.bannerText", bannerAccessibilityText(title: "AirPods Pro", subtitle: "Connected") == "AirPods Pro, Connected"
          && bannerAccessibilityText(title: "Claude finished", subtitle: "") == "Claude finished")

    // Y1: layout A in the default 420 pt panel packs 4 tabs into ~23.6 pt slots. Inside a slot
    // the icon's own tab always wins; the outermost tab also takes the margin just outside the
    // group's outer edge (never towards the notch).
    let w = notchWings(panelWidth: 420, notchMinX: (420 - 179) / 2, notchWidth: 179)
    if let a = stripLayout(count: 4, layout: .tabsAndStatus, wings: w) {
        check("a11y.layoutANarrow", a.slot < 24 && a.leftCount == 4)
        let outer = a.centers[0] - a.slot / 2, innerEnd = a.centers[3] + a.slot / 2
        let extra = 4 * (24 - a.slot)
        check("a11y.layoutAOuterMargin", stripHitSlot(at: outer - 0.5, a, panelWidth: 420) == 0
              && stripHitSlot(at: outer - extra + 0.1, a, panelWidth: 420) == 0
              && stripHitSlot(at: outer - extra - 0.5, a, panelWidth: 420) == nil)
        check("a11y.layoutAOuterTab24", (a.slot + min(extra, outer)) >= 24)
        check("a11y.layoutANotInward", stripHitSlot(at: innerEnd + 0.5, a, panelWidth: 420) == nil)
    } else {
        check("a11y.layoutANarrow", false)
    }
    // Wide slots: same as the plain hit test.
    if let b = stripLayout(count: 4, layout: .split, wings: w) {
        check("a11y.splitUnchanged", stride(from: 0.0, through: 420, by: 3).allSatisfy {
            stripHitSlot(at: $0, b, panelWidth: 420) == stripSlot(at: $0, b) })
    } else {
        check("a11y.splitUnchanged", false)
    }
    // Sweep every open width 240…1200, both layouts, centred and both anchor sides, 1-4 tabs:
    // every icon centre (and its slot edges) hits its own tab; no hit inside the notch; no hit
    // outside the panel.
    var ownOK = true, notchOK = true, panelOK = true
    let notchW = 179.0
    for width in 240...1200 {
        let W = Double(width)
        for notchMinX in [(W - notchW) / 2, 0, W - notchW] {
            let wings = notchWings(panelWidth: W, notchMinX: notchMinX, notchWidth: notchW)
            for kind in [TabLayout.split, .tabsAndStatus] {
                for n in 1...4 {
                    guard let l = stripLayout(count: n, layout: kind, wings: wings) else { continue }
                    for (i, c) in l.centers.enumerated() {
                        for x in [c, c - l.slot / 2 + 0.01, c + l.slot / 2 - 0.01]
                            where stripHitSlot(at: x, l, panelWidth: W) != i { ownOK = false }
                    }
                    var x = notchMinX
                    while x <= notchMinX + notchW {
                        if stripHitSlot(at: x, l, panelWidth: W) != nil { notchOK = false }
                        x += 0.5
                    }
                    if stripHitSlot(at: -0.5, l, panelWidth: W) != nil
                        || stripHitSlot(at: W + 0.5, l, panelWidth: W) != nil { panelOK = false }
                }
            }
        }
    }
    check("a11y.sweepOwnIcon", ownOK)
    check("a11y.sweepNeverNotch", notchOK)
    check("a11y.sweepInsidePanel", panelOK)
    // Right-wing group (panel opened from the notch's left edge): margin outward to the right.
    let lw = notchWings(panelWidth: 300, notchMinX: 0, notchWidth: 179)
    if let r = stripLayout(count: 4, layout: .tabsAndStatus, wings: lw, maxSlot: 26), r.slot < 24 {
        let innerStart = r.centers[0] - r.slot / 2, outer = r.centers[3] + r.slot / 2
        check("a11y.rightWingHit", stripHitSlot(at: outer + 0.5, r, panelWidth: 300) == 3
              && stripHitSlot(at: innerStart - 0.5, r, panelWidth: 300) == nil
              && stripHitSlot(at: r.centers[0], r, panelWidth: 300) == 0)
    } else {
        check("a11y.rightWingHit", false)
    }
}
