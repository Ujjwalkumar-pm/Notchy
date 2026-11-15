import Foundation
import NotchyCore

func runTabSplitChecks() {
    let four: [TabID] = [.music, .claude, .alerts, .calendar]

    // Split around the notch: extra on the left.
    let s4 = splitTabs(four)
    check("split.four", s4.left == [.music, .claude] && s4.right == [.alerts, .calendar])
    let s3 = splitTabs([.music, .claude, .alerts])
    check("split.three", s3.left == [.music, .claude] && s3.right == [.alerts])
    let s1 = splitTabs([.calendar])
    check("split.one", s1.left == [.calendar] && s1.right.isEmpty)
    check("split.empty", splitTabs([]).left.isEmpty && splitTabs([]).right.isEmpty)

    // Swipe/keyboard stepping (nextTab from Task 10): no wrap, clamps.
    check("next.forward", nextTab(four, current: .claude, step: 1) == .alerts)
    check("next.clampEnd", nextTab(four, current: .calendar, step: 1) == .calendar)
    check("next.back", nextTab(four, current: .alerts, step: -1) == .claude
          && nextTab(four, current: .music, step: -1) == .music)

    // Settings: the two new keys.
    let d = NotchySettings.defaults
    check("settings.tabLayoutDefaults", d.tabLayout == .split && d.swipeTabs == true
          && decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).tabLayout == .split
          && decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).swipeTabs == true)
    let custom = decodeSettings(Data(#"{"tabLayout":"tabsAndStatus","swipeTabs":false}"#.utf8))
    check("settings.tabLayoutDecode", custom.tabLayout == .tabsAndStatus && custom.swipeTabs == false)
    let bad = decodeSettings(Data(##"{"tabLayout":"diagonal","swipeTabs":"yes","accentHex":"#112233"}"##.utf8))
    check("settings.tabLayoutBad", bad.tabLayout == .split && bad.swipeTabs == true && bad.accentHex == "#112233")
    var round = d
    round.tabLayout = .tabsAndStatus
    round.swipeTabs = false
    check("settings.tabLayoutRoundTrip",
          (try? JSONEncoder().encode(round)).map { decodeSettings($0) } == round)

    // Wings: the space beside the hardware notch, 18 pt from the panel edge, 8 pt from the notch.
    let w = notchWings(panelWidth: 420, notchMinX: 120, notchWidth: 180)
    check("wings.centred", w.leftX == 18 && w.leftWidth == 94 && w.rightX == 308 && w.rightWidth == 94)
    let off = notchWings(panelWidth: 420, notchMinX: 40, notchWidth: 180)
    check("wings.offset", off.leftWidth == 14 && off.rightX == 228 && off.rightWidth == 174)
    let none = notchWings(panelWidth: 200, notchMinX: 10, notchWidth: 180)
    check("wings.noRoom", none.leftWidth == 0 && none.rightWidth == 0)

    // Slots in the strip.
    let b = stripLayout(count: 4, layout: .split, wings: w)
    // Split: each wing's group centred in its wing (AUDIT T5), mirror-symmetric about the notch.
    check("strip.split", b.map { $0.slot == 40 && $0.leftCount == 2 && $0.centers == [45, 85, 335, 375] } == true)
    check("strip.splitSymmetric", b.map { l in (0..<2).allSatisfy { l.centers[$0] + l.centers[3 - $0] == 420 } } == true)
    let a = stripLayout(count: 4, layout: .tabsAndStatus, wings: w)
    check("strip.tabsLeft", a.map { $0.leftCount == 4 && $0.slot == 23.5 && $0.centers.first == 29.75
                                    && $0.centers.allSatisfy { $0 < 120 } } == true)
    // Layout A: 26 pt slots when the wing has room (AUDIT T2); narrower wings shrink the slot.
    let wideA = stripLayout(count: 4, layout: .tabsAndStatus,
                            wings: notchWings(panelWidth: 640, notchMinX: 230, notchWidth: 180))
    check("strip.tabsAndStatusSlot26", wideA.map { $0.slot == 26 && $0.centers == [31, 57, 83, 109] } == true
          && stripSlotLimit(for: .split) == 40 && stripSlotLimit(for: .tabsAndStatus) == 26)
    // The open panel's level control: opposite wing, hugging the notch, clear of tabs.
    let ww = notchWings(panelWidth: 640, notchMinX: 230, notchWidth: 180)
    let sp = stripLayout(count: 4, layout: .split, wings: ww)
    let la = stripLayout(count: 4, layout: .tabsAndStatus, wings: ww)
    let r1 = levelIndicatorSlot(wings: ww, layout: sp, selected: 0)
    let l1 = levelIndicatorSlot(wings: ww, layout: sp, selected: 3)
    let a1 = levelIndicatorSlot(wings: ww, layout: la, selected: 2)
    // Split groups are centred (62 pt free between a group and the notch); layout A packs left.
    check("levelSlot.opposite", r1?.x == 418 && r1?.width == 62 && l1?.x == 160 && l1?.width == 62
          && a1?.x == 418 && a1?.width == 82)
    check("levelSlot.clearOfTabs", [r1, l1].allSatisfy { s in
        s.map { s in sp?.centers.allSatisfy { c in c + 20 <= s.x || c - 20 >= s.x + s.width } == true } == true })
    // Layout A: status cluster owns the right wing's outer edge; the control keeps clear of it.
    let a2 = levelIndicatorSlot(wings: ww, layout: la, selected: 2, statusInRight: true)
    let narrowA = notchWings(panelWidth: 520, notchMinX: 170, notchWidth: 180)  // wings 144
    let a3 = levelIndicatorSlot(wings: narrowA, layout: stripLayout(count: 4, layout: .tabsAndStatus, wings: narrowA),
                                selected: 0, statusInRight: true)
    check("levelSlot.clearOfStatus", a2.map { $0.x + $0.width <= ww.rightX + ww.rightWidth - stripStatusReserve } == true
          && a2?.width == 82 && a3 == nil)
    let tight = notchWings(panelWidth: 420, notchMinX: 120, notchWidth: 180)
    check("levelSlot.noRoomSkipped", levelIndicatorSlot(wings: tight, layout: stripLayout(count: 4, layout: .split, wings: tight),
                                                        selected: 0) == nil)
    check("strip.neverUnderNotch", [b, a].allSatisfy { l in
        l.map { l in l.centers.allSatisfy { c in c + l.slot / 2 <= 120 - 8 || c - l.slot / 2 >= 300 + 8 } } == true })
    check("strip.tooNarrow", stripLayout(count: 4, layout: .split, wings: none) == nil
          && stripLayout(count: 4, layout: .tabsAndStatus,
                         wings: notchWings(panelWidth: 300, notchMinX: 60, notchWidth: 180)) == nil)
    // Free wing: a panel opened from the notch's left edge (notch at x 0) has no left wing,
    // so all 4 tabs go in the right wing (both layouts), never under the notch.
    let leftAnchored = notchWings(panelWidth: 420, notchMinX: 0, notchWidth: 179)
    let fl = stripLayout(count: 4, layout: .split, wings: leftAnchored)
    check("strip.freeWingRight", fl.map { $0.leftCount == 0 && $0.slot == 40 && $0.centers.count == 4
                                          && $0.centers.allSatisfy { $0 - 20 >= 179 + 8 } } == true
          && stripLayout(count: 4, layout: .tabsAndStatus, wings: leftAnchored)?.leftCount == 0)
    let rightAnchored = notchWings(panelWidth: 420, notchMinX: 241, notchWidth: 179)
    let fr = stripLayout(count: 3, layout: .split, wings: rightAnchored)
    check("strip.freeWingLeft", fr.map { $0.leftCount == 3 && $0.centers.allSatisfy { $0 + 20 <= 241 - 8 } } == true)
    check("strip.preferredFirst", stripLayout(count: 4, layout: .split, wings: off).map { $0.leftCount == 0 } == true
          && stripLayout(count: 4, layout: .split, wings: w)?.leftCount == 2)
    check("strip.single", stripLayout(count: 1, layout: .split, wings: w).map { $0.centers == [65] } == true
          && stripLayout(count: 0, layout: .split, wings: w) == nil)
    if let b {
        // Hit test: a click on a slot picks it; the notch gap picks nothing.
        check("strip.hit", stripSlot(at: 40, b) == 0 && stripSlot(at: 80, b) == 1 && stripSlot(at: 210, b) == nil && stripSlot(at: 381, b) == 3)
        // Drag across the notch gap: the tab moves to the other side once past the next centre.
        check("strip.dragAcrossGap", tabDragTarget(from: 1, pointerX: 343, centers: b.centers) == 2
              && tabDragTarget(from: 1, pointerX: 300, centers: b.centers) == 1
              && tabDragTarget(from: 3, pointerX: 30, centers: b.centers) == 0)
    }
    // Same answers as the evenly spaced tab bar it generalises.
    check("strip.dragMatchesBar", (0..<4).allSatisfy { i in
        stride(from: -20.0, through: 200, by: 7).allSatisfy { x in
            tabDragTarget(from: i, pointerX: x, centers: [20, 60, 100, 140])
                == tabDragTarget(from: i, pointerX: x, slot: 40, count: 4) } })

    // Swipe: trackpad gesture, horizontal dominant, 40 pt, one step per gesture.
    var t = SwipeTracker()
    // Natural scrolling: deltaX follows the fingers. Fingers left → next tab.
    var steps: [Int] = []
    steps.append(t.feed(.began, momentum: false, dx: 0, dy: 0, natural: true))
    for _ in 0..<10 { steps.append(t.feed(.changed, momentum: false, dx: -10, dy: 1, natural: true)) }
    steps.append(t.feed(.ended, momentum: false, dx: 0, dy: 0, natural: true))
    check("swipe.leftIsNext", steps.filter { $0 != 0 } == [1])
    var r = SwipeTracker()
    _ = r.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    let right = (0..<5).map { _ in r.feed(.changed, momentum: false, dx: 10, dy: 0, natural: true) }
    check("swipe.rightIsPrevious", right.filter { $0 != 0 } == [-1])
    var inv = SwipeTracker()
    _ = inv.feed(.began, momentum: false, dx: 0, dy: 0, natural: false)
    let invSteps = (0..<5).map { _ in inv.feed(.changed, momentum: false, dx: -10, dy: 0, natural: false) }
    check("swipe.unnaturalScrolling", invSteps.filter { $0 != 0 } == [-1])
    var small = SwipeTracker()
    _ = small.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    let under = (0..<3).map { _ in small.feed(.changed, momentum: false, dx: -13, dy: 0, natural: true) }
    check("swipe.underThreshold", under.allSatisfy { $0 == 0 })
    var vert = SwipeTracker()
    _ = vert.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    let v = (0..<10).map { _ in vert.feed(.changed, momentum: false, dx: -6, dy: 12, natural: true) }
    check("swipe.verticalIgnored", v.allSatisfy { $0 == 0 })
    var mom = SwipeTracker()
    _ = mom.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    _ = mom.feed(.ended, momentum: false, dx: 0, dy: 0, natural: true)
    let m = (0..<10).map { _ in mom.feed(.other, momentum: true, dx: -30, dy: 0, natural: true) }
    check("swipe.momentumIgnored", m.allSatisfy { $0 == 0 })
    var noBegin = SwipeTracker()
    check("swipe.needsBegin", (0..<6).allSatisfy { _ in noBegin.feed(.changed, momentum: false, dx: -20, dy: 0, natural: true) == 0 })
    var two = SwipeTracker()
    var fired = 0
    for _ in 0..<2 {
        _ = two.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
        for _ in 0..<5 { fired += abs(two.feed(.changed, momentum: false, dx: -10, dy: 0, natural: true)) }
        _ = two.feed(.ended, momentum: false, dx: 0, dy: 0, natural: true)
    }
    check("swipe.onePerGesture", fired == 2)
    var card = SwipeTracker()
    _ = card.feed(.began, momentum: false, dx: 0, dy: 0, natural: true, blocked: true)
    let c1 = (0..<6).map { _ in card.feed(.changed, momentum: false, dx: -20, dy: 0, natural: true) }
    var card2 = SwipeTracker()
    _ = card2.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    _ = card2.feed(.changed, momentum: false, dx: -20, dy: 0, natural: true, blocked: true)
    let c2 = (0..<6).map { _ in card2.feed(.changed, momentum: false, dx: -20, dy: 0, natural: true) }
    check("swipe.cardBlocks", c1.allSatisfy { $0 == 0 } && c2.allSatisfy { $0 == 0 })

    // Page dots (AUDIT T4): only while a gesture is a horizontal swipe; never for vertical
    // scrolls, gestures over the card, or after the gesture ends.
    var ind = SwipeTracker()
    _ = ind.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    let indBefore = ind.indicating
    _ = ind.feed(.changed, momentum: false, dx: -10, dy: 1, natural: true)
    let indDuring = ind.indicating
    for _ in 0..<5 { _ = ind.feed(.changed, momentum: false, dx: -10, dy: 0, natural: true) }
    let indAfterStep = ind.indicating
    _ = ind.feed(.ended, momentum: false, dx: 0, dy: 0, natural: true)
    check("swipe.indicatorHorizontal", !indBefore && indDuring && indAfterStep && !ind.indicating)
    var indV = SwipeTracker()
    _ = indV.feed(.began, momentum: false, dx: 0, dy: 0, natural: true)
    for _ in 0..<10 { _ = indV.feed(.changed, momentum: false, dx: -6, dy: 12, natural: true) }
    var indC = SwipeTracker()
    _ = indC.feed(.began, momentum: false, dx: 0, dy: 0, natural: true, blocked: true)
    for _ in 0..<5 { _ = indC.feed(.changed, momentum: false, dx: -20, dy: 0, natural: true) }
    var indM = SwipeTracker()
    for _ in 0..<5 { _ = indM.feed(.other, momentum: true, dx: -30, dy: 0, natural: true) }
    check("swipe.indicatorNotForScrollCardMomentum", !indV.indicating && !indC.indicating && !indM.indicating)

    // Status cluster (layout A).
    // Graceful degradation (Task 8 fix 1). Worst case in the default 420 pt panel (notch 185 pt,
    // right wing 91.5 pt): working "12", badge "99+", a meeting. Widths ≈ 11 pt semibold / 10 bold.
    let wing420 = notchWings(panelWidth: 420, notchMinX: 117.5, notchWidth: 185).rightWidth
    let worstW = StripStatusWidths(working: 6 + 4 + 15, unread: 29, time: 32, calendarGlyph: 14, spacing: 6)
    let worst = StripStatus(working: 12, unread: 150, nextMeeting: Date())
    let wp = stripStatusParts(worst, widths: worstW, available: wing420)
    check("status.worst420", wing420 == 91.5 && wp.working && wp.unread && !wp.time && !wp.calendarGlyph
          && stripStatusWidth(wp, worstW) <= wing420)
    let full = stripStatusParts(worst, widths: worstW, available: 200)
    let noGlyph = stripStatusParts(worst, widths: worstW, available: 25 + 6 + 29 + 6 + 32)
    let noBadge = stripStatusParts(worst, widths: worstW, available: 40)
    let tiny = stripStatusParts(worst, widths: worstW, available: 10)
    check("status.degradeOrder", full == StripStatusParts(working: true, unread: true, time: true, calendarGlyph: true)
          && noGlyph == StripStatusParts(working: true, unread: true, time: true, calendarGlyph: false)
          && noBadge == StripStatusParts(working: true, unread: false, time: false, calendarGlyph: false)
          && tiny.working)
    // Every width: the working indicator is always kept, and what is kept fits whenever it can.
    check("status.workingNeverDropped", stride(from: 0.0, through: 200, by: 0.5).allSatisfy { a in
        let p = stripStatusParts(worst, widths: worstW, available: a)
        return p.working && (stripStatusWidth(p, worstW) <= a || a < worstW.working) })
    let emptyParts = stripStatusParts(StripStatus(working: 0, unread: 0, nextMeeting: Date()), widths: worstW, available: 40)
    check("status.emptyPartsAbsent", !emptyParts.working && !emptyParts.unread && emptyParts.time && !emptyParts.calendarGlyph)

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func meeting(_ id: String, _ startIn: TimeInterval, allDay: Bool = false) -> MeetingInfo {
        MeetingInfo(id: id, title: id, start: now.addingTimeInterval(startIn),
                    end: now.addingTimeInterval(startIn + 1800), allDay: allDay,
                    calendarColorHex: "#FFFFFF", joinURL: nil, attendees: [])
    }
    let phases: [SessionPhase] = [.working(tool: "Bash"), .working(tool: nil), .waitingApproval, .idle]
    let st = stripStatus(phases: phases, dockCounts: ["Microsoft Teams": 3, "Microsoft Outlook": 5],
                         meetings: [meeting("past", -600), meeting("allday", 3600, allDay: true),
                                    meeting("next", 7200), meeting("later", 9000)], now: now)
    check("status.counts", st.working == 2 && st.unread == 8 && st.nextMeeting == now.addingTimeInterval(7200))
    let far = stripStatus(phases: [], dockCounts: [:], meetings: [meeting("far", 13 * 3600)], now: now)
    check("status.empty", far.working == 0 && far.unread == 0 && far.nextMeeting == nil && far.isEmpty)
}
