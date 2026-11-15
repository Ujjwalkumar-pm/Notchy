import Foundation
import CoreGraphics
import NotchyCore

func runPanelSizeChecks() {
    // Built-in display of a 13" Air: 1470×956 pt, notch 185×32 centred.
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let notch = CGRect(x: 642.5, y: 924, width: 185, height: 32)

    // defaultIsExactNotch: no custom size → exactly the notch rect.
    let d = resolvedFrame(screen: screen, notch: notch, size: nil, defaultSize: notch.size)
    check("defaultIsExactNotch", d == notch)
    // Real 13" Air numbers: half-point notch origin must survive untouched.
    let real = CGRect(x: 645.5, y: 924, width: 179, height: 32)
    check("defaultIsExactNotch.real",
          resolvedFrame(screen: screen, notch: real, size: nil, defaultSize: real.size) == real)

    // customWidthCentred: width 900 stays centred on the notch, top flush with the screen.
    let c = resolvedFrame(screen: screen, notch: notch, size: CGSize(width: 900, height: 60),
                          defaultSize: notch.size)
    check("customWidthCentred.midX", c.midX == notch.midX)
    check("customWidthCentred.top", c.maxY == screen.maxY)
    check("customWidthCentred.size", c.width == 900 && c.height == 60)
    check("customWidthCentred.wholePoints", c.minX == c.minX.rounded())

    // noUpperCap: bigger than the screen is kept as given.
    let big = resolvedFrame(screen: screen, notch: notch, size: CGSize(width: 5000, height: 3000),
                            defaultSize: notch.size)
    check("noUpperCap", big.width == 5000 && big.height == 3000 && big.maxY == screen.maxY)

    // floorIsOne: zero or negative → 1.
    let z = resolvedFrame(screen: screen, notch: notch, size: CGSize(width: 0, height: -40),
                          defaultSize: notch.size)
    check("floorIsOne", z.width == 1 && z.height == 1 && z.maxY == screen.maxY)
    let n = PanelSize(collapsed: CGSize(width: -5, height: 0), expanded: nil).floored()
    check("floorIsOne.store", n.collapsed == CGSize(width: 1, height: 1))

    // roundTripsDefaults: save → load gives the same value; reset → empty.
    let suite = "notchy-checks-\(UUID().uuidString)"
    let ud = UserDefaults(suiteName: suite)!
    let store = PanelSizeStore(defaults: ud)
    check("roundTripsDefaults.emptyFirst", store.load() == PanelSize())
    let v = PanelSize(collapsed: CGSize(width: 400, height: 60), expanded: CGSize(width: 5000, height: 3000))
    store.save(v)
    check("roundTripsDefaults.saved", store.load() == v)
    check("roundTripsDefaults.fresh", PanelSizeStore(defaults: UserDefaults(suiteName: suite)!).load() == v)
    store.reset()
    check("roundTripsDefaults.reset", store.load() == PanelSize() && ud.data(forKey: PanelSizeStore.key) == nil)
    ud.removePersistentDomain(forName: suite)

    // pendingFloorCheck: a pending approval floors a custom open size at the content size.
    let content = CGSize(width: 420, height: 200)
    check("pendingFloorCheck.defaultStaysNil",
          openPanelSize(custom: nil, content: content, approvalPending: true) == nil)
    check("pendingFloorCheck.smallGrows",
          openPanelSize(custom: CGSize(width: 300, height: 50), content: content, approvalPending: true)
            == CGSize(width: 420, height: 200))
    check("pendingFloorCheck.bigKept",
          openPanelSize(custom: CGSize(width: 900, height: 600), content: content, approvalPending: true)
            == CGSize(width: 900, height: 600))
    check("pendingFloorCheck.mixed",
          openPanelSize(custom: CGSize(width: 900, height: 50), content: content, approvalPending: true)
            == CGSize(width: 900, height: 200))
    check("pendingFloorCheck.notPendingExact",
          openPanelSize(custom: CGSize(width: 300, height: 50), content: content, approvalPending: false)
            == CGSize(width: 300, height: 50))

    // pendingFloorCappedAtScreen: the floor never exceeds the screen height.
    let tall = CGSize(width: 420, height: 2000)
    check("pendingFloorCappedAtScreen",
          openPanelSize(custom: CGSize(width: 300, height: 50), content: tall, approvalPending: true,
                        screenHeight: 956) == CGSize(width: 420, height: 956))
    check("pendingFloorCappedAtScreen.customKept",
          openPanelSize(custom: CGSize(width: 300, height: 3000), content: tall, approvalPending: true,
                        screenHeight: 956) == CGSize(width: 420, height: 3000))

    // zoneThickness: 6 pt normally, ≤ a quarter of the dimension on tiny panels.
    check("zoneThickness.normal", resizeZoneThickness(dimension: 179) == 6 && resizeZoneThickness(dimension: 32) == 6)
    check("zoneThickness.small", resizeZoneThickness(dimension: 12) == 3 && resizeZoneThickness(dimension: 1) == 0.25)
    check("zoneThickness.leavesMiddle", 12 - 2 * resizeZoneThickness(dimension: 12) > 0)

    // popup: notch width, grows downward only, derived from the notch alone (no size parameter
    // exists, so a custom collapsed size can't affect it).
    let pop = popupFrame(notch: real)
    check("popup.notchWidth", pop.width == real.width && pop.minX == real.minX)
    check("popup.downOnly", pop.maxY == real.maxY && pop.height == 32 + 28 && popupExtraHeight == 28)

    // anchor: the open panel anchored on the notch's centre, left edge or right edge; top flush.
    let open = CGSize(width: 420, height: 200)
    let ac = anchoredFrame(notch: real, screen: screen, size: open, anchor: .centre)
    check("anchor.centre", ac.midX == real.midX && ac.maxY == screen.maxY && ac.size == open)
    let al = anchoredFrame(notch: real, screen: screen, size: open, anchor: .left)
    check("anchor.left", al.minX == real.minX.rounded(.down) && al.minX <= real.minX && al.maxY == screen.maxY && al.size == open)
    let ar = anchoredFrame(notch: real, screen: screen, size: open, anchor: .right)
    check("anchor.right", ar.minX == ar.minX.rounded() && ar.maxX >= real.maxX && ar.maxX - real.maxX < 1 && ar.maxY == screen.maxY && ar.size == open)
    // A notch near the right edge (external layout / tiny screen): right anchor fits, left
    // anchor is shifted back on screen; wider than the screen pins to the left edge.
    let edgeNotch = CGRect(x: 1300, y: 924, width: 150, height: 32)
    let wide = CGSize(width: 900, height: 200)
    let el = anchoredFrame(notch: edgeNotch, screen: screen, size: wide, anchor: .left)
    let er = anchoredFrame(notch: edgeNotch, screen: screen, size: wide, anchor: .right)
    let ec = anchoredFrame(notch: edgeNotch, screen: screen, size: wide, anchor: .centre)
    check("anchor.clampedOnScreen",
          el.maxX == screen.maxX && el.minX >= screen.minX
          && er.maxX == edgeNotch.maxX && er.minX >= screen.minX && el.minX == el.minX.rounded()
          && ec.maxX <= screen.maxX && ec.minX >= screen.minX && ec.width == 900)
    let huge = anchoredFrame(notch: real, screen: screen, size: CGSize(width: 2000, height: 200), anchor: .right)
    check("anchor.widerThanScreen", huge.minX == screen.minX && huge.width == 2000)
    let offsetScreen = CGRect(x: 1470, y: 0, width: 1512, height: 982)
    let offNotch = CGRect(x: 1470 + 666, y: 950, width: 180, height: 32)
    let oo = anchoredFrame(notch: offNotch, screen: offsetScreen, size: open, anchor: .left)
    check("anchor.secondScreen", oo.minX == offNotch.minX.rounded(.down) && oo.maxY == offsetScreen.maxY)

    // hover: with Open from Left, a pointer on the left part of the centred banner it opened
    // from stays "in" (no open-then-close flash); beyond both frames it's out.
    let bannerFrom = CGRect(x: real.midX - 170, y: real.minY - bannerExtraHeight, width: 340, height: real.height + bannerExtraHeight)
    let openLeft = anchoredFrame(notch: real, screen: screen, size: open, anchor: .left)
    let bannerLeftPoint = CGPoint(x: bannerFrom.minX + 10, y: bannerFrom.minY + 10)
    check("hover.openedFromKept", !openLeft.contains(bannerLeftPoint)
          && hoverContains(bannerLeftPoint, frame: openLeft, openedFrom: bannerFrom))
    check("hover.outsideBoth", !hoverContains(CGPoint(x: 100, y: 500), frame: openLeft, openedFrom: bannerFrom)
          && !hoverContains(bannerLeftPoint, frame: openLeft, openedFrom: nil))
    check("hover.edgesInclusive", hoverContains(CGPoint(x: openLeft.minX, y: openLeft.maxY), frame: openLeft, openedFrom: nil))

    // anim: base durations × speed; none is always 0.
    let bases: [(PanelAnimation, Double)] = [(.spring, 0.35), (.smooth, 0.25), (.snappy, 0.18), (.fade, 0.2)]
    var durationsOK = true
    for (a, base) in bases {
        if abs(animationDuration(a, .normal) - base) > 1e-9 { durationsOK = false }
        if abs(animationDuration(a, .slow) - base * 1.5) > 1e-9 { durationsOK = false }
        if abs(animationDuration(a, .fast) - base * 0.6) > 1e-9 { durationsOK = false }
    }
    check("anim.durations", durationsOK)
    check("anim.noneZero", AnimationSpeed.allCases.allSatisfy { animationDuration(.none, $0) == 0 })
    check("anim.curves", animationCurve(.spring) != nil && animationCurve(.smooth) != nil
          && animationCurve(.snappy) != nil && animationCurve(.fade) == nil && animationCurve(.none) == nil)

    // openAuto: an open size with "Auto" height takes the content height, keeps its width.
    let autoP = PanelSize(collapsed: nil, expanded: CGSize(width: 500, height: 300), expandedHeightAuto: true)
    check("openAuto.contentHeight", customOpenSize(autoP, defaultHeight: 180) == CGSize(width: 500, height: 180))
    check("openAuto.fixed", customOpenSize(PanelSize(expanded: CGSize(width: 500, height: 300)), defaultHeight: 180)
            == CGSize(width: 500, height: 300))
    check("openAuto.none", customOpenSize(PanelSize(), defaultHeight: 180) == nil)
    let autoSuite = "notchy-checks-\(UUID().uuidString)"
    let autoUD = UserDefaults(suiteName: autoSuite)!
    let autoStore = PanelSizeStore(defaults: autoUD)
    autoStore.save(autoP)
    check("openAuto.roundTrip", autoStore.load() == autoP)
    // An older saved value (no flag) still loads.
    autoUD.set(Data(#"{"expanded":[400,200]}"#.utf8), forKey: PanelSizeStore.key)
    check("openAuto.oldFormat", autoStore.load() == PanelSize(expanded: CGSize(width: 400, height: 200)))
    // Auto without an open size is dropped; the flag is only written when set.
    check("openAuto.flagNeedsSize", PanelSize(expandedHeightAuto: true).floored() == PanelSize())
    let plain = String(data: try! JSONEncoder().encode(PanelSize(expanded: CGSize(width: 400, height: 200))), encoding: .utf8)!
    check("openAuto.oldFormatWritten", !plain.contains("expandedHeightAuto"))
    autoUD.removePersistentDomain(forName: autoSuite)

    // Task 11 (AUDIT R2): the closed size is never smaller than the hardware notch.
    let hw = CGSize(width: 179, height: 32)
    check("r2.ownerSavedSizeClampsToDefault", clampedClosedSize(CGSize(width: 150, height: 30), notch: hw) == nil)
    check("r2.narrowWidthOnly", clampedClosedSize(CGSize(width: 60, height: 40), notch: hw) == CGSize(width: 179, height: 40))
    check("r2.lowHeightOnly", clampedClosedSize(CGSize(width: 300, height: 20), notch: hw) == CGSize(width: 300, height: 32))
    check("r2.largerKept", clampedClosedSize(CGSize(width: 400, height: 60), notch: hw) == CGSize(width: 400, height: 60))
    check("r2.defaultStaysNil", clampedClosedSize(nil, notch: hw) == nil)
    check("r2.noNotchUnchanged", clampedClosedSize(CGSize(width: 60, height: 20), notch: nil) == CGSize(width: 60, height: 20))
    check("r2.halfPointNotchRoundsUp",
          clampedClosedSize(CGSize(width: 100, height: 31), notch: CGSize(width: 184.5, height: 31.5)) == nil
          && clampedClosedSize(CGSize(width: 190, height: 10), notch: CGSize(width: 184.5, height: 31.5)) == CGSize(width: 190, height: 32))
    check("r2.closedFrameCoversNotch", {
        let f = resolvedFrame(screen: screen, notch: real, size: clampedClosedSize(CGSize(width: 150, height: 30), notch: real.size),
                              defaultSize: real.size)
        return f.width >= real.width && f.height >= real.height
    }())
    check("r2.sliderStartsAtNotch",
          closedSliderRange(base: 60...800, minimum: 179) == 179...800
          && closedSliderRange(base: 20...200, minimum: 31.5) == 32...200
          && closedSliderRange(base: 60...800, minimum: nil) == 60...800
          && closedSliderRange(base: 60...800, minimum: 900) == 800...800)
}
