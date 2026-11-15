// Notchy - a personal macOS notch app.
//
// Derived from Atoll (DynamicIsland), itself derived from boring.notch.
// Original: reference/atoll/stage1/DynamicIslandWindow.swift
// Modified for Notchy, 2026-11-13.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program (LICENSE at the repository root).
// If not, see <https://www.gnu.org/licenses/>.
import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import NotchyCore

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var expanded = false
    @Published var notchSize: CGSize = .zero
    /// Volume/brightness pop-up showing (closed: 28 pt strip; open: thin bar).
    @Published var popup = false
    /// Welcome step 1 (AUDIT R1): the closed notch's accent outline is showing (once, 1.2 s).
    @Published var outlineFlash = false
    /// Banner showing under the closed notch (nil = none). Never set while expanded.
    @Published var banner: Banner?
    /// The banner's action pill in hosting-view coordinates (top-left origin), nil if none.
    var bannerActionRect: CGRect?
    var onBannerAction: (() -> Void)?
    var onBannerOpen: (() -> Void)?
    /// Height of the expanded content below the notch, measured by SwiftUI.
    var onContentHeight: ((CGFloat) -> Void)?
    /// The approval request whose buttons may take clicks (set by the panel's ArmingGate).
    @Published var armedId: UUID?
    /// The ArmingGate's dwell progress for the showing card, 0…1 (read-only mirror; 1 only
    /// while `armedId` is set). Drives the card's progress line, never the buttons.
    @Published var armProgress: Double = 0
    /// The request whose command box the user expanded with "Show all" (nil = collapsed).
    /// Shared so the hidden measuring copy lays out the same height.
    @Published var commandExpandedId: UUID?
    /// The open panel's tab content (below the approval card, and the strip's tabs) takes
    /// clicks only once the open has settled and the pointer has moved since (ContentGate).
    @Published var contentInteractive = false
    /// Page dots show only during a swipe gesture and 1 s after it (AUDIT T4). An overlay:
    /// never part of the measured content height.
    @Published var swipeDots = false
    /// Duration of the current open/close frame change (effective: Speed and Reduce Motion
    /// applied; 0 = instant). Set before `expanded` flips; the content fade follows it (N2).
    @Published var openCloseDuration: TimeInterval = 0.35
    /// Live approval card frame in hosting-view coordinates (top-left origin), nil if none.
    var cardRect: CGRect? {
        didSet { if oldValue != cardRect { onCardRectChange?(oldValue, cardRect) } }
    }
    var onCardRectChange: ((CGRect?, CGRect?) -> Void)?
    var onDisarm: (() -> Void)?
    /// The hardware notch's left edge measured from the open panel's left edge, and the open
    /// panel's width, both from its open (target) frame. The tab-row fallback is decided from
    /// these so it doesn't flicker while the frame animates.
    @Published var openNotchMinX: CGFloat = 0
    @Published var openWidth: CGFloat = NotchPanel.expandedWidth
    /// The notch's left edge measured from the panel's LIVE left edge (read at layout time), so
    /// the strip's tabs follow the frame mid-animation and never sit under the notch when the
    /// panel opens from the left or right. Nil → `openNotchMinX`.
    var liveNotchMinX: (@MainActor () -> CGFloat)?

    /// The wings beside the notch in the live view, `width` wide.
    func wings(width: CGFloat) -> NotchWings {
        notchWings(panelWidth: Double(width), notchMinX: Double(liveNotchMinX?() ?? openNotchMinX),
                   notchWidth: Double(notchSize.width))
    }

    /// True when `count` tabs fit beside the notch in the open (target) frame.
    func tabsFitInStrip(count: Int, layout: TabLayout) -> Bool {
        let w = notchWings(panelWidth: Double(openWidth), notchMinX: Double(openNotchMinX),
                           notchWidth: Double(notchSize.width))
        return stripLayout(count: count, layout: layout, wings: w) != nil
    }

    func disarm() {
        armedId = nil
        armProgress = 0
        onDisarm?()
    }

    /// "Show all" on the card: expands its command box, and disarms like a decision does
    /// (the card's layout shifts under the pointer, so it must leave and re-enter before
    /// Allow / Deny take clicks again).
    func expandCommand(_ id: UUID) {
        guard commandExpandedId != id else { return }
        disarm()
        commandExpandedId = id
    }
}

/// Lets the first click on a button work while Notchy is not the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Hand right-clicks to the container, which shows Notchy's menu.
    override func rightMouseDown(with event: NSEvent) {
        if let container = superview as? HoverHostingView, container.onRightClick != nil {
            container.rightMouseDown(with: event)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Container view that reports hover via an NSTrackingArea.
final class HoverHostingView: NSView {
    /// Inside/outside, plus the pointer position in screen coordinates at that event.
    var onHover: ((Bool, CGPoint) -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    /// Also report pointer moves inside the view (only while the pop-up grew under a resting
    /// pointer, so a real move can be told apart from our own frame change).
    var reportsMoves = false {
        didSet { if reportsMoves != oldValue { updateTrackingAreas() } }
    }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if reportsMoves { options.insert(.mouseMoved) }
        let a = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true, screenPoint(event)) }
    override func mouseExited(with event: NSEvent) { onHover?(false, screenPoint(event)) }
    override func mouseMoved(with event: NSEvent) {
        if reportsMoves { onHover?(true, screenPoint(event)) } else { super.mouseMoved(with: event) }
    }
    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick(event, self) } else { super.rightMouseDown(with: event) }
    }
    // Resize zones shrink on tiny panels, so re-lay them out on every size change.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        for case let h as ResizeHandle in subviews { h.relayout() }
    }
}

@MainActor
final class NotchPanel: NSPanel {
    static let expandedWidth: CGFloat = 420
    /// Keep the panel open this long after the last approval request leaves.
    static let lingerAfterApproval: TimeInterval = 1.5
    static let pinnedCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
    ]

    let model = NotchViewModel()
    let app: AppModel
    /// Right-click anywhere on the panel (collapsed or expanded).
    var onRightClick: ((NSEvent, NSView) -> Void)? {
        get { (contentView as? HoverHostingView)?.onRightClick }
        set { (contentView as? HoverHostingView)?.onRightClick = newValue }
    }
    private(set) var notchRect: CGRect
    /// Frame of the screen the notch is on; the panel's top is flush with its maxY.
    private(set) var screenFrame: CGRect
    /// The screen has a camera notch: the closed size never goes below it (AUDIT R2).
    private(set) var hasHardwareNotch: Bool
    private(set) var isExpanded = false
    /// User-chosen sizes (nil = default). Persisted under UserDefaults `panelSize`.
    private(set) var sizes: PanelSize
    private let sizeStore = PanelSizeStore()
    /// True while a resize zone is being dragged: hover changes don't collapse/expand.
    private var resizing = false
    private var handles: [ResizeHandle] = []
    /// Last pointer position seen by a hover event (screen coordinates).
    private var pointer: CGPoint = .zero
    private var contentHeight: CGFloat = 60
    private var hovered = false
    private var approvalPending = false
    private var lingering = false
    private var lingerWork: DispatchWorkItem?
    private var currentSink: AnyCancellable?
    private var hudSink: AnyCancellable?
    /// One-shot: hides the pop-up at `hud.hideAt`; replaced on every key press.
    private var hudHideWork: DispatchWorkItem?
    /// Click-through guard for the approval card; polled while an approval is pending.
    private var gate = ArmingGate()
    /// Pointer position at the previous gate tick: an entry into the card counts only if the
    /// pointer itself moved (the card growing over a still pointer is not an entry).
    private var lastGatePointer: CGPoint?
    private var gateTimer: Timer?
    /// Click-through guard for the tab content of a freshly opened panel.
    private var contentGate = ContentGate()
    /// When the showing banner finished growing (nil while growing / none): its action pill
    /// takes clicks only `bannerActionDelay` after this, and after the pointer moved.
    private var bannerShownAt: Date?
    /// Which banner shows; the panel supplies the context (open, pending, pop-up).
    private var arbiter = BannerArbiter()
    /// Action of the showing banner, and of the one queued behind the pop-up.
    private var bannerAction: (@MainActor () -> Void)?
    private var queuedBannerAction: (@MainActor () -> Void)?
    /// One-shot: hides the banner `bannerDuration` after it shows.
    private var bannerHideWork: DispatchWorkItem?
    /// ⌥⌘N toggles the panel (Carbon hot key; no Accessibility needed).
    private let hotKey = HotKey()
    /// Opened with ⌥⌘N: stays open without hover until ⌥⌘N, Esc, a click elsewhere, or the
    /// pointer entering and then leaving the panel. Meanwhile the panel is key and a local
    /// monitor takes ← → / Esc (other keys pass on).
    private var keyboardOpen = false
    private var keyboardHovered = false
    private var keyMonitor: Any?
    /// False when macOS refused ⌥⌘N (another app holds it); Settings says so.
    private(set) var hotKeyAvailable = true
    private var outsideClickMonitor: Any?
    /// Hide in full screen: the closed notch is hidden (alpha 0, clicks pass through) while
    /// the front app is full screen. The pop-up and approvals still show.
    private var fullScreenHide = false
    private var hideSink: AnyCancellable?
    /// Two-finger horizontal swipe over the open panel → one tab step per gesture.
    private var swipe = SwipeTracker()
    private var scrollMonitor: Any?
    /// One-shot: hides the page dots 1 s after a swipe gesture ends (no idle timer).
    private var swipeDotsHideWork: DispatchWorkItem?
    /// The frame the panel opened from (closed / pop-up / banner, live at open time); hover
    /// counts the union of it and the open frame while open (see `hoverContains`). Nil closed.
    private var openedFrom: CGRect?
    /// Global mouse-moved monitor, only while the pointer is in `openedFrom` but outside the
    /// panel's own window (no tracking events reach us there).
    private var openedFromMonitor: Any?
    /// Settings → Notch → Open from (applies to the open panel only).
    private var openFrom: OpenAnchor
    private var openFromSink: AnyCancellable?

    init(notchRect: CGRect, screenFrame: CGRect, hasHardwareNotch: Bool, app: AppModel) {
        self.notchRect = notchRect
        self.screenFrame = screenFrame
        self.hasHardwareNotch = hasHardwareNotch
        self.app = app
        self.sizes = sizeStore.load()
        self.openFrom = app.settings.value.openFrom
        super.init(contentRect: notchRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        // Approval cards stay clickable while an app-modal alert (e.g. "hooks removed") is up.
        worksWhenModal = true
        level = .mainMenu + 3
        collectionBehavior = Self.pinnedCollectionBehavior

        model.notchSize = notchRect.size
        model.liveNotchMinX = { [weak self] in self?.liveNotchMinX() ?? 0 }
        model.onContentHeight = { [weak self] h in self?.contentHeightChanged(h) }
        model.onDisarm = { [weak self] in self?.gate.disarm() }
        model.onCardRectChange = { [weak self] old, new in self?.cardRectChanged(old: old, new: new) }
        model.onBannerAction = { [weak self] in self?.bannerActionClicked() }
        model.onBannerOpen = { [weak self] in self?.bannerClicked() }
        app.bannerHandler = { [weak self] b, action in self?.offerBanner(b, action: action) }

        let container = HoverHostingView(frame: CGRect(origin: .zero, size: notchRect.size))
        container.autoresizingMask = [.width, .height]
        let host = FirstMouseHostingView(rootView: NotchView(app: app, ui: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        // The panel's size is set by Notchy, never by the SwiftUI content.
        host.sizingOptions = []
        container.addSubview(host)
        // Bottom first so the side zones win at the corners.
        for edge in [ResizeHandle.Edge.bottom, .left, .right] {
            let handle = ResizeHandle(edge: edge)
            handle.onBegin = { [weak self] in self?.frame.size ?? .zero }
            handle.onDrag = { [weak self] size in self?.liveResize(size) }
            handle.onEnd = { [weak self] size in self?.endResize(size) }
            // Centred panels grow both sides (2 × the drag); one anchored on a notch edge
            // grows on one side only.
            handle.widthFactor = { [weak self] in
                guard let self, self.isExpanded, self.openFrom != .centre else { return 2 }
                return 1
            }
            handle.onHoverChange = { [weak self] p in
                self?.pointer = p
                self?.updateExpansion()
            }
            handle.install(in: container)
            handles.append(handle)
        }
        // Don't trust the event's entered/exited flag: rebuilding the tracking area while the
        // frame changes fires a spurious "exited" with the pointer still inside, which made
        // the panel close and reopen in a loop. Decide from the real pointer position.
        container.onHover = { [weak self] _, _ in self?.resyncHover() }
        contentView = container
        clampClosedSize("launch")
        setFrame(targetFrame(), display: true)
        logFrame("launch")
        // The strip's wings follow the open frame (custom size, anchor, screen change).
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncStrip() }
            }
        }
        syncStrip()

        currentSink = app.approvals.$current
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                MainActor.assumeIsolated { self?.approvalPendingChanged(pending) }
            }
        hudSink = app.$hud
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hud in
                MainActor.assumeIsolated { self?.hudChanged(hud) }
            }
        hideSink = Publishers.CombineLatest(app.settings.$value.map(\.hideInFullScreen).removeDuplicates(),
                                            app.quiet.$fullScreenFront.removeDuplicates())
            .map { $0 && $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hide in
                MainActor.assumeIsolated { self?.fullScreenHideChanged(hide) }
            }
        openFromSink = app.settings.$value.map(\.openFrom)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] anchor in
                MainActor.assumeIsolated { self?.openFromChanged(anchor) }
            }
        hotKey.onPress = { [weak self] in self?.toggleFromHotKey() }
#if NOTCHY_CAPTURE
        // Not registered (the real app may hold it); shown as available, as in a normal run.
        hotKeyAvailable = true
#else
        hotKeyAvailable = hotKey.register()
#endif
        notchyLog.notice("Hot key ⌥⌘N registered: \(self.hotKeyAvailable)")
        installKeySwallow()
        installSwipe()
    }

    /// Key only while opened with ⌥⌘N (a non-activating panel takes keys without activating
    /// Notchy), so ← → / Esc reach the local key monitor. Never key otherwise.
    override var canBecomeKey: Bool { keyboardOpen }
    override var canBecomeMain: Bool { false }
    // No capping: a custom size may be larger than the screen (user decision).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Default size for a state: collapsed = exactly the notch; expanded = 420 × content height.
    func defaultSize(expanded: Bool) -> CGSize {
        // Open default never taller than the screen, so a long card can't push Allow off it.
        expanded
            ? CGSize(width: Self.expandedWidth,
                     height: min(notchRect.height + contentHeight, screenFrame.height))
            : notchRect.size
    }

    /// The size showing in a state: the user's custom size if set, else the default.
    func effectiveSize(expanded: Bool) -> CGSize {
        frame(expanded: expanded).size
    }

    /// The stored custom size for a state (nil = default). Open with "Auto" height: the custom
    /// width × the content-fitting height.
    func customSize(expanded: Bool) -> CGSize? {
        expanded ? customOpenSize(sizes, defaultHeight: defaultSize(expanded: true).height) : sizes.collapsed
    }

    /// True when the open height fits the content (no custom open size, or "Auto").
    var openHeightIsAuto: Bool { sizes.expanded == nil || sizes.expandedHeightAuto }

    /// Closed: centred on the notch (custom size or exactly the notch). Open: anchored on the
    /// notch per Settings → Notch → Open from (centre / left edge / right edge), on screen.
    func frame(expanded: Bool) -> CGRect {
        guard expanded else {
            return resolvedFrame(screen: screenFrame, notch: notchRect, size: sizes.collapsed,
                                 defaultSize: defaultSize(expanded: false))
        }
        // While an approval is pending the open frame never shrinks below its full content,
        // so Allow / Deny can't be clipped by a small custom open size.
        let size = openPanelSize(custom: customSize(expanded: true), content: defaultSize(expanded: true),
                                 approvalPending: approvalPending, screenHeight: screenFrame.height)
        let base = resolvedFrame(screen: screenFrame, notch: notchRect, size: size,
                                 defaultSize: defaultSize(expanded: true))
        return anchoredFrame(notch: notchRect, screen: screenFrame, size: base.size, anchor: openFrom)
    }

    /// The frame for the current state: open, closed with a banner, closed with the pop-up, or
    /// closed. The pop-up ignores custom sizes: notch width, 28 pt taller, downward only. A
    /// banner likewise: 340 wide, centred on the notch, 56 pt taller.
    func targetFrame() -> CGRect {
        if isExpanded { return frame(expanded: true) }
        if model.banner != nil {
            return bannerFrame(notch: notchRect, height: notchRect.height + bannerExtraHeight)
        }
        if model.popup { return popupFrame(notch: notchRect) }
        let closed = frame(expanded: false)
        // The outline needs real pixels around the camera notch: 3 pt each side and below.
        guard model.outlineFlash else { return closed }
        return CGRect(x: closed.minX - Self.outlineRing, y: closed.minY - Self.outlineRing,
                      width: closed.width + 2 * Self.outlineRing, height: closed.height + Self.outlineRing)
    }

    static let outlineRing: CGFloat = 3
    private var outlineWork: DispatchWorkItem?

    /// Welcome step 1 (AUDIT R1): flash the closed notch's outline once so a new user sees
    /// where Notchy is. Only on the bare closed notch (no banner, pop-up, open panel or
    /// full-screen hide); the frame grows 3 pt for 1.2 s, then returns.
    func flashOutline() {
        guard !isExpanded, model.banner == nil, !model.popup, !fullScreenHide, !frameAnimating,
              !model.outlineFlash else { return }
        model.outlineFlash = true
        setFrame(targetFrame(), display: true, animate: false)
        scheduleResync(after: 0.05)
        outlineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.outlineWork = nil
                self.model.outlineFlash = false
                // Shrink back after the 0.25 s fade-out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.model.outlineFlash, !self.isExpanded, !self.frameAnimating,
                              !self.resizing, self.frame != self.targetFrame() else { return }
                        self.setFrame(self.targetFrame(), display: true, animate: false)
                        self.scheduleResync(after: 0.05)
                    }
                }
            }
        }
        outlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        notchyLog.notice("Welcome: notch outline flash")
    }

    /// Re-applies the open frame (content height or pending state changed).
    private func reframeIfOpen() {
        // Mid open animation: its completion reconciles to the then-current target.
        guard isExpanded, !resizing, !frameAnimating else { return }
        let f = targetFrame()
        guard f != frame else { return }
        setFrame(f, display: true, animate: false)
        // Switching tabs changes the height under a resting pointer: re-read hover after.
        scheduleResync(after: 0.05)
    }

    /// Sets (or with nil clears) the custom size for one state, saves it and re-frames. An
    /// explicit open size (Set size…, resize drag) turns "Auto" height off.
    func setCustomSize(_ size: CGSize?, expanded: Bool) {
        if expanded {
            sizes.expanded = size
            sizes.expandedHeightAuto = false
        } else {
            sizes.collapsed = clampedClosedSize(size, notch: closedMinimum)
        }
        saveSizes("set \(expanded ? "open" : "closed") size")
    }

    /// Settings → Notch open sliders: `height == nil` = "Auto" (fits the content). Width 420
    /// with Auto height is the default, stored as no custom open size.
    func setOpenSize(width: CGFloat, height: CGFloat?) {
        if let height {
            sizes.expanded = CGSize(width: width, height: height)
            sizes.expandedHeightAuto = false
        } else if width.rounded() == Self.expandedWidth {
            sizes.expanded = nil
            sizes.expandedHeightAuto = false
        } else {
            // Keep the last fixed height so leaving Auto starts from it.
            let h = sizes.expanded?.height ?? defaultSize(expanded: true).height
            sizes.expanded = CGSize(width: width, height: h)
            sizes.expandedHeightAuto = true
        }
        saveSizes("set open size")
    }

    /// Smallest closed size: the camera notch on a notched screen, else none (AUDIT R2).
    var closedMinimum: CGSize? { hasHardwareNotch ? notchRect.size : nil }

    /// Raises a saved closed size that is smaller than the notch (e.g. an old 150 × 30) and
    /// saves the result, so the hover target always covers the visible notch.
    private func clampClosedSize(_ why: String) {
        let clamped = clampedClosedSize(sizes.collapsed, notch: closedMinimum)
        guard clamped != sizes.collapsed else { return }
        let old = sizes.collapsed ?? .zero
        sizes.collapsed = clamped
        sizeStore.save(sizes)
        sizes = sizeStore.load()
        notchyLog.notice("closed size \(old.width) x \(old.height) raised to the notch (\(why, privacy: .public)): \(clamped.map { "\($0.width) x \($0.height)" } ?? "default (exactly the notch)", privacy: .public)")
    }

    private func saveSizes(_ why: String) {
        sizeStore.save(sizes)
        sizes = sizeStore.load()
        // The card may move under an armed pointer: nothing stays armed.
        model.disarm()
        stopFrameAnimation()
        setFrame(targetFrame(), display: true, animate: false)
        syncVisibility()
        syncStrip()
        logFrame(why)
    }

    /// Clears both custom sizes: collapsed is exactly the notch again.
    func resetSizes() {
        sizeStore.reset()
        sizes = PanelSize()
        model.disarm()
        stopFrameAnimation()
        setFrame(targetFrame(), display: true, animate: false)
        syncVisibility()
        syncStrip()
        logFrame("reset size")
    }

    private func liveResize(_ size: CGSize) {
        resizing = true
        var size = size
        if !isExpanded, let m = closedMinimum {
            // A closed drag stops at the notch (AUDIT R2).
            size = CGSize(width: max(size.width, m.width.rounded(.up)), height: max(size.height, m.height.rounded(.up)))
        }
        var f = resolvedFrame(screen: screenFrame, notch: notchRect, size: size,
                              defaultSize: defaultSize(expanded: isExpanded))
        if isExpanded {
            f = anchoredFrame(notch: notchRect, screen: screenFrame, size: f.size, anchor: openFrom)
        }
        setFrame(f, display: true, animate: false)
    }

    private func endResize(_ size: CGSize?) {
        resizing = false
        if let size {
            setCustomSize(size, expanded: isExpanded)
        } else {
            // Cancelled drag: the pop-up may have flipped meanwhile; land on the right frame.
            setFrame(targetFrame(), display: true, animate: false)
        }
        // Hover events were ignored mid-drag; re-read where the mouse is now.
        resyncHover()
    }

    private func logFrame(_ why: String) {
        let f = frame, t = targetFrame(), n = notchRect
        notchyLog.notice("panel frame (\(why, privacy: .public)): x \(f.minX) y \(f.minY) w \(f.width) h \(f.height); target x \(t.minX) w \(t.width) h \(t.height); notch x \(n.minX) y \(n.minY) w \(n.width) h \(n.height); expanded \(self.isExpanded) pending \(self.approvalPending) banner \(self.model.banner != nil); zones \(self.handles.map { "\($0.frame.width)x\($0.frame.height)" }.joined(separator: " "), privacy: .public)")
    }

    func setExpanded(_ on: Bool, animated: Bool) {
        if on {
            // Hovering a banner opens the panel on its tab; any banner (or queued one) goes.
            if let b = model.banner { app.selectTab(b.tab) }
            clearBannerState()
        }
        let wasExpanded = isExpanded
        if on && !wasExpanded {
            openedFrom = frame
            contentGate.reset()
        }
        if !on { clearOpenedFrom(); hideSwipeDots() }
        // Reduce Motion: Fade at 0.15 s whatever the style and speed (AUDIT N1).
        let s = app.settings.value
        let motion = effectiveOpenClose(animated ? s.animation : .none, s.animationSpeed,
                                        reduceMotion: DisplayOptions.shared.reduceMotion)
        isExpanded = on
        syncStrip()
        // Before `expanded` flips: the content fade is timed from it (AUDIT N2).
        model.openCloseDuration = motion.duration
        model.expanded = on
        if on { clearPopupGrowPointer() }
        if on && !wasExpanded { app.panelOpened() }
        if !on { endKeyboardOpen() }
        stopFrameAnimation()
        let target = targetFrame()
        let style = motion.style
        let duration = motion.duration
        animateOpenClose(to: target, style: style, duration: duration, opening: on)
        // After the animation started: hidden in full screen, the closing panel stays visible
        // until its animation ends (the completion re-syncs visibility).
        syncVisibility()
        // An instant open is settled now (reference point = the pointer here); an animated
        // one when its completion runs.
        syncContentGate()
        // The tracking area is rebuilt while the frame changes; an exit (or entry) during
        // that time is never reported, which left the panel stuck open. Re-read the pointer
        // once the animation is over (instant change: at once, on the next run-loop turn).
        let delay = duration > 0 ? duration + 0.05 : (animated ? 0 : 0.05)
        scheduleResync(after: delay)
        if wasExpanded && !on {
            // Closed (which also means no approval is pending): a meeting reminder held back
            // while the panel was open may show now, once the shrink is over.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isExpanded else { return }
                    self.app.bannerSlotFreed()
                }
            }
        }
    }

    /// Open/close frame change in the chosen style (Settings → Notch → Animation, Speed).
    /// spring/smooth/snappy: the frame animates on that curve (`animationCurve`). fade: no size
    /// animation: opening jumps to the open frame and fades in; closing fades the open panel
    /// out, then jumps to the closed frame. none (or duration 0): instant. Runs as a frame
    /// animation (`frameAnimating` + generation) so `reconcileFrame` doesn't snap it midway.
    private func animateOpenClose(to target: CGRect, style: PanelAnimation, duration: TimeInterval,
                                  opening: Bool) {
        guard duration > 0, style != .none else {
            setFrame(target, display: true, animate: false)
            return
        }
        frameAnimating = true
        frameGeneration += 1
        let generation = frameGeneration
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, generation == self.frameGeneration else { return }
            self.frameAnimating = false
            self.fading = false
            self.reconcileFrame()
            self.syncVisibility()
            self.syncContentGate()
        }
        if let c = animationCurve(style) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
                animator().setFrame(target, display: true)
            }, completionHandler: { MainActor.assumeIsolated { finish() } })
            return
        }
        // Fade: alpha only; the frame changes instantly.
        fading = true
        if opening {
            alphaValue = 0
            setFrame(target, display: true, animate: false)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }, completionHandler: { MainActor.assumeIsolated { finish() } })
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, generation == self.frameGeneration else { return }
                    self.setFrame(self.targetFrame(), display: true, animate: false)
                    self.alphaValue = 1
                    finish()
                }
            })
        }
    }

    private func openFromChanged(_ anchor: OpenAnchor) {
        guard anchor != openFrom else { return }
        openFrom = anchor
        syncStrip()
        guard isExpanded, !resizing else { return }
        model.disarm()
        stopFrameAnimation()
        setFrame(targetFrame(), display: true, animate: false)
        syncVisibility()
        scheduleResync(after: 0.05)
        logFrame("open from \(anchor.rawValue)")
    }

    private func scheduleResync(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.resyncHover() }
        }
    }

    // MARK: Volume/brightness pop-up

    private static let popupAnimation: TimeInterval = 0.15
    /// True while one of our frame animator groups runs (pop-up / banner grow or shrink, or
    /// an open/close animation, including a fade).
    private var frameAnimating = false
    /// Bumped per frame animation (and on cancel) so a stale completion can't clear the flag.
    private var frameGeneration = 0
    /// True while an open/close fade owns `alphaValue` (syncVisibility leaves it alone).
    private var fading = false

    /// Cancels an in-flight frame animation: `setFrame(_:display:animate:)` doesn't reliably
    /// cancel the animator, which could finish last and leave an open panel clipped to 179×60.
    /// A cancelled fade lands at full alpha on its current frame.
    private func stopFrameAnimation() {
        guard frameAnimating else { return }
        frameAnimating = false
        frameGeneration += 1
        let current = frame
        let wasFading = fading
        fading = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            animator().setFrame(current, display: false)
            if wasFading { animator().alphaValue = 1 }
        }
        if wasFading { alphaValue = 1 }
        // No syncVisibility here: callers re-sync after their new frame (and any new animation)
        // is in place, so a hidden-in-full-screen close animates instead of vanishing.
    }

    /// Snaps to the frame for the current state if anything left it elsewhere.
    private func reconcileFrame() {
        guard !resizing, !frameAnimating else { return }
        let t = targetFrame(), f = frame
        if abs(f.minX - t.minX) > 0.5 || abs(f.minY - t.minY) > 0.5
            || abs(f.width - t.width) > 0.5 || abs(f.height - t.height) > 0.5 {
            setFrame(t, display: true, animate: false)
            logFrame("reconcile")
        }
    }

    private func hudChanged(_ hud: HUDState) {
        hudHideWork?.cancel()
        hudHideWork = nil
        let now = Date()
        let visible = hud.visible(now: now)
        if visible, let hideAt = hud.hideAt {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.setPopup(false) }
            }
            hudHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hideAt.timeIntervalSince(now), execute: work)
        }
        setPopup(visible)
    }

    /// Shows/hides the pop-up. Open panel: no resize (the view draws a thin bar). Closed: the
    /// height eases over 0.15 s; the width snaps first so only the height animates. A volume key
    /// during a banner replaces it (not re-queued); a banner queued behind the pop-up shows
    /// when it ends.
    private func setPopup(_ on: Bool) {
        guard on != model.popup else { return }
        let hadBanner = model.banner != nil
        if on { clearBannerState() }
        model.popup = on
        syncVisibility()
        var nextBanner = false
        if !on, let q = arbiter.popupEnded(now: Date()) {
            if isExpanded || resizing || approvalPending {
                arbiter.dismiss()
            } else {
                setBannerState(q, action: queuedBannerAction)
                nextBanner = true
            }
            queuedBannerAction = nil
        }
        if (on || nextBanner) && !isExpanded && !resizing {
            armGrowGate()
        } else if !on && (isExpanded || resizing) {
            clearPopupGrowPointer()
        }
        // On hide the gate stays until the shrink animation is over: the still-tall frame
        // must not count a resting pointer as hover mid-shrink.
        let banner = hadBanner || nextBanner
        animateClosedFrame(duration: banner ? Self.bannerAnimation : Self.popupAnimation,
                           snapWidth: !banner)
    }

    /// Animates the closed panel to `targetFrame()` (pop-up / banner grow or shrink) and
    /// re-reads hover from the real pointer afterwards. With `snapWidth` the width and x jump
    /// first so only the height animates (pop-up, same width as the notch).
    /// Reduce Motion (AUDIT N1): no grow. Bare notch → pop-up/banner jumps at alpha 0 and fades
    /// in; back to the bare notch fades out, then jumps; pop-up ↔ banner jumps (the SwiftUI
    /// content cross-fades). Fades run as frame animations (`frameAnimating` + generation +
    /// `fading`), so hover stays blocked and `reconcileFrame` waits exactly as for a grow.
    private func animateClosedFrame(duration: TimeInterval, snapWidth: Bool) {
        guard !isExpanded, !resizing else { return }
        // Any running frame animation (an open/close curve or fade, an earlier pop-up/banner
        // group) is cut short first, so it can't finish last.
        if frameAnimating { stopFrameAnimation() }
        let target = targetFrame()
        let style = closedFrameStyle(reduceMotion: DisplayOptions.shared.reduceMotion,
                                     fromBare: isBareNotch(frame), toBare: isBareNotch(target))
        if style == .instant {
            setFrame(target, display: true, animate: false)
            frameGeneration += 1
            let generation = frameGeneration
            // Instant: the tracking area is rebuilt now; re-read the pointer on the next turn.
            scheduleResync(after: 0)
            guard model.banner != nil else {
                closedFrameSettled(generation: generation)
                return
            }
            // A banner is still cross-fading in (SwiftUI, `bannerAnimation`): the change counts
            // as a frame animation until it is fully shown, so hover stays blocked and
            // `bannerShownAt` (the action pill's delay) starts only then.
            frameAnimating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerAnimation) { [weak self] in
                MainActor.assumeIsolated { self?.closedFrameSettled(generation: generation) }
            }
            syncVisibility()
            scheduleResync(after: Self.bannerAnimation + 0.05)
            return
        }
        if style == .grow && snapWidth && (frame.width != target.width || frame.minX != target.minX) {
            setFrame(CGRect(x: target.minX, y: frame.minY, width: target.width, height: frame.height),
                     display: true, animate: false)
        }
        frameAnimating = true
        frameGeneration += 1
        let generation = frameGeneration
        switch style {
        case .instant:
            assertionFailure("instant closed-frame changes return above")
            closedFrameSettled(generation: generation)
        case .grow:
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.closedFrameSettled(generation: generation) }
            })
        case .fadeIn:
            fading = true
            alphaValue = 0
            setFrame(target, display: true, animate: false)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if generation == self.frameGeneration { self.fading = false }
                    self.closedFrameSettled(generation: generation)
                }
            })
        case .fadeOut:
            fading = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // A newer change (or a cancel) owns the frame and alpha now.
                    if generation == self.frameGeneration {
                        self.setFrame(self.targetFrame(), display: true, animate: false)
                        self.alphaValue = 1
                        self.fading = false
                    }
                    self.closedFrameSettled(generation: generation)
                }
            })
        }
        // Now that the group runs (frameAnimating), a closed notch hidden in full screen stays
        // visible while it shrinks; the completion hides it.
        syncVisibility()
        // A frame change rebuilds the tracking area; decide hover from the real pointer after.
        scheduleResync(after: duration + 0.05)
    }

    /// The closed frame is the plain notch (no pop-up, no banner), within half a point.
    private func isBareNotch(_ r: CGRect) -> Bool {
        let bare = frame(expanded: false)
        return abs(r.height - bare.height) <= 0.5 && abs(r.width - bare.width) <= 0.5
    }

    /// End of a closed-frame change (grow, fade or instant): only the latest one clears the
    /// flag; then the shared settle steps.
    private func closedFrameSettled(generation: Int) {
        if generation == frameGeneration { frameAnimating = false }
        reconcileFrame()
        syncVisibility()
        if !frameAnimating && !isExpanded && model.banner != nil && bannerShownAt == nil {
            bannerShownAt = Date()
        }
        if !frameAnimating && !model.popup && model.banner == nil && popupGrowPointer != nil {
            clearPopupGrowPointer()
            resyncHover()
        }
    }

    // MARK: Banners

    private static let bannerAnimation: TimeInterval = 0.2

    /// Entry point for producers (via `AppModel.offerBanner`). Returns the arbiter's decision
    /// and the context it was made in (meeting reminders defer on some drops).
    @discardableResult
    func offerBanner(_ b: Banner, action: (@MainActor () -> Void)?) -> (decision: BannerDecision, ctx: BannerContext) {
        let ctx = BannerContext(panelOpen: isExpanded || resizing || lingering,
                                approvalPending: approvalPending,
                                popupShowing: model.popup,
                                quiet: app.evaluateQuiet())
        let decision = arbiter.offer(b, ctx: ctx, now: Date())
        // No banner text in logs (privacy): only the outcome.
        notchyLog.notice("banner offer: \(decision == .queued ? "queued" : decision == .dropped ? "dropped" : "show", privacy: .public)")
        switch decision {
        case .show(let shown):
            setBannerState(shown, action: action)
            // The banner grows (or a newer one replaces it) under a possibly resting pointer.
            armGrowGate()
            animateClosedFrame(duration: Self.bannerAnimation, snapWidth: false)
        case .queued:
            queuedBannerAction = action
        case .dropped:
            break
        }
        return (decision, ctx)
    }

    /// Shows `b` (no frame change) and starts its one-shot hide timer.
    private func setBannerState(_ b: Banner, action: (@MainActor () -> Void)?) {
        bannerHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideBanner() }
        }
        bannerHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + bannerDuration, execute: work)
        bannerAction = action
        let isNew = model.banner != b
        if isNew {
            model.bannerActionRect = nil
            bannerShownAt = nil
        }
        model.banner = b
        if isNew { announce(b) }
        syncHandles()
        updateMoveReporting()
        syncVisibility()
    }

    /// VoiceOver reads a banner as it shows (AUDIT Y2): title, then subtitle. No-op without an
    /// assistive app listening.
    private func announce(_ b: Banner) {
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: bannerAccessibilityText(title: b.title, subtitle: b.subtitle),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// Forgets the showing and any queued banner without touching the frame.
    private func clearBannerState() {
        bannerHideWork?.cancel()
        bannerHideWork = nil
        arbiter.dismiss()
        bannerAction = nil
        queuedBannerAction = nil
        bannerShownAt = nil
        if model.banner != nil {
            model.banner = nil
            model.bannerActionRect = nil
        }
        syncHandles()
        updateMoveReporting()
    }

    /// Timer expiry or action click: the banner shrinks back into the notch.
    private func hideBanner() {
        guard model.banner != nil else { clearBannerState(); return }
        clearBannerState()
        guard !isExpanded, !resizing else { return }
        // A pointer resting in the shrinking frame (e.g. on the action pill) must not open
        // the panel mid-shrink: gate it until the animation is over.
        armGrowGate()
        animateClosedFrame(duration: Self.bannerAnimation, snapWidth: false)
    }

    private func bannerActionClicked() {
        guard model.banner != nil, !isExpanded else { return }
        // Click-through guard: the pill must have been fully shown a while, and the pointer
        // must have moved since the banner grew under it.
        guard bannerActionAllowed(fullyShownAt: bannerShownAt, now: Date(),
                                  growGateArmed: popupGrowPointer != nil) else {
            notchyLog.notice("banner action ignored (click-through guard)")
            return
        }
        let action = bannerAction
        hideBanner()
        action?()
    }

    /// Click on the banner outside the action pill: open the panel on the banner's tab.
    private func bannerClicked() {
        guard model.banner != nil, !isExpanded else { return }
        // A click is a real user act: no pointer-movement gate.
        clearPopupGrowPointer()
        setExpanded(true, animated: true)
    }

    /// Resize zones are off while a banner shows (its edges must not resize the closed size).
    private func syncHandles() {
        let hide = model.banner != nil && !isExpanded
        for h in handles where h.isHidden != hide { h.isHidden = hide }
    }

    /// Hover may not open the panel over the action pill (and the strip from it to the right
    /// and bottom edges), so the pointer can reach the pill and click it.
    private func inBannerActionZone(_ p: CGPoint) -> Bool {
        guard model.banner != nil, !isExpanded, let r = model.bannerActionRect else { return false }
        let f = frame
        let left = f.minX + r.minX - 8
        let zone = CGRect(x: left, y: f.minY, width: f.maxX - left,
                          height: max(0, f.height - notchRect.height))
        return p.x >= zone.minX && p.x <= zone.maxX && p.y >= zone.minY && p.y <= zone.maxY
    }

    /// Where the pointer was when the closed notch grew into the pop-up (nil = no gate).
    /// A pointer resting just below the notch (e.g. on a browser tab bar) ends up inside the
    /// grown frame without moving; that must not open the panel. Hover may open it only once
    /// the real pointer has moved away from this spot. Tracking events and resyncs caused by
    /// our own frame change don't move the pointer, so they don't count.
    private var popupGrowPointer: CGPoint?

    /// Starts the pointer-movement gate at the current pointer position.
    private func armGrowGate() {
        popupGrowPointer = pointerLocation()
        (contentView as? HoverHostingView)?.reportsMoves = true
    }

    private func clearPopupGrowPointer() {
        popupGrowPointer = nil
        updateMoveReporting()
    }

    /// Pointer moves are reported while the gate is armed, and while a banner with an action
    /// pill shows (leaving the pill's no-hover zone must re-check hover).
    private func updateMoveReporting() {
        let on = popupGrowPointer != nil || (model.banner?.actionLabel != nil && !isExpanded)
            || (isExpanded && !contentGate.interactive)
        (contentView as? HoverHostingView)?.reportsMoves = on
    }

    /// True while hover must not open the panel because the pointer hasn't moved since the
    /// pop-up grew under it. Clears the gate (for good) once the pointer has moved.
    private func popupHoverBlocked() -> Bool {
        guard let start = popupGrowPointer else { return false }
        guard (model.popup || model.banner != nil || frameAnimating), !isExpanded else { clearPopupGrowPointer(); return false }
        let p = pointerLocation()
        if abs(p.x - start.x) < 1 && abs(p.y - start.y) < 1 { return true }
        clearPopupGrowPointer()
        return false
    }

    /// Sets `hovered` from the real pointer position, then opens/closes as needed (edges inclusive: the pointer can rest on
    /// the screen's top row, which `CGRect.contains` would count as outside).
    private func resyncHover() {
        reconcileFrame()
        let p = pointerLocation(), f = frame
        pointer = p
        hovered = hoverContains(p, frame: f, openedFrom: isExpanded ? openedFrom : nil)
        syncOpenedFromMonitor(pointerInWindow: hoverContains(p, frame: f, openedFrom: nil))
        syncContentGate()
        updateExpansion()
    }

    /// Watches pointer moves while it's only in `openedFrom` (outside our window), so leaving
    /// that area closes the panel. Removed as soon as the pointer is back in the window, gone,
    /// or the panel closes.
    private func syncOpenedFromMonitor(pointerInWindow: Bool) {
        let want = isExpanded && openedFrom != nil && hovered && !pointerInWindow
        if want, openedFromMonitor == nil {
            openedFromMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.resyncHover() }
            }
        } else if !want, let m = openedFromMonitor {
            NSEvent.removeMonitor(m)
            openedFromMonitor = nil
        }
    }

    /// Feeds the content gate from the real pointer and publishes the result. Moves are
    /// reported (tracking area) only while it waits for one, so this costs nothing at rest.
    private func syncContentGate() {
        let settled = isExpanded && !frameAnimating && !resizing
        let on = contentGate.update(expanded: isExpanded, settled: settled, pointer: pointerLocation())
        if model.contentInteractive != on { model.contentInteractive = on }
        updateMoveReporting()
    }

    private func clearOpenedFrom() {
        openedFrom = nil
        if let m = openedFromMonitor { NSEvent.removeMonitor(m) }
        openedFromMonitor = nil
    }

    /// Re-anchor to a (possibly changed) notch rect, keeping the current expansion state.
    func reposition(notchRect: CGRect, screenFrame: CGRect, hasHardwareNotch: Bool) {
        self.notchRect = notchRect
        self.screenFrame = screenFrame
        self.hasHardwareNotch = hasHardwareNotch
        clampClosedSize("screen change")
        model.notchSize = notchRect.size
        model.disarm()
        // The old closed frame is stale on the new screen: hover counts the new one.
        clearOpenedFrom()
        if isExpanded { openedFrom = frame(expanded: false) }
        stopFrameAnimation()
        setFrame(targetFrame(), display: true, animate: false)
        syncVisibility()
        syncStrip()
        scheduleResync(after: 0.05)
        logFrame("screen change")
    }

    private func approvalPendingChanged(_ pending: Bool) {
        let wasPending = approvalPending
        approvalPending = pending
        lingerWork?.cancel()
        lingerWork = nil
        lingering = false
        // An approval wins: the banner (and any queued one) goes at once; the panel opens below.
        if pending { clearBannerState() }
        // The card appearing on an open panel pushes the tab content down under the pointer:
        // it needs a fresh pointer move before it takes clicks again.
        // Likewise when it goes (Allow/Deny/Dismiss resolved): the content slides up under the
        // pointer that just clicked.
        if pending != wasPending && isExpanded { reguardContent() }
        if !pending && wasPending {
            lingering = true
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.lingering = false
                    self?.updateExpansion()
                }
            }
            lingerWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerAfterApproval, execute: work)
        }
        updateExpansion()
        // Already open (e.g. hovered): apply or drop the pending floor now.
        reframeIfOpen()
        syncContentGate()
        updateGateTimer()
    }

    // MARK: Click-through guard

    /// Content gate back to "wait for a pointer move" (reports moves until it opens again).
    private func reguardContent() {
        contentGate.reset()
        model.contentInteractive = false
        syncContentGate()
    }

    /// The approval card appeared, went, or changed height/top while the panel is open (the
    /// next approval is taller or shorter): the tab content shifted under the pointer.
    private func cardRectChanged(old: CGRect?, new: CGRect?) {
        guard isExpanded, contentGateNeedsReset(oldCard: old, newCard: new) else { return }
        reguardContent()
    }

    /// Polls the pointer (20 Hz) only while an approval is pending.
    private func updateGateTimer() {
        if approvalPending {
            guard gateTimer == nil else { return }
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.gateTick() }
            }
            t.tolerance = 0.02
            RunLoop.main.add(t, forMode: .common)
            gateTimer = t
            gateTick()
        } else {
            gateTimer?.invalidate()
            gateTimer = nil
            gate.show(nil, pointerInside: false, pointerMoved: false, now: Date())
            lastGatePointer = nil
            if model.armedId != nil { model.armedId = nil }
            if model.armProgress != 0 { model.armProgress = 0 }
            if model.commandExpandedId != nil { model.commandExpandedId = nil }
        }
    }

    /// The live card's frame in screen coordinates, clipped to the panel.
    private func cardScreenRect() -> CGRect? {
        guard let r = model.cardRect, isExpanded else { return nil }
        let f = frame
        return CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
            .intersection(f)
    }

    private func gateTick() {
        let now = Date()
        let rect = cardScreenRect()
        // The card "appears" only on a settled open panel with a real, laid-out card: while the
        // frame still grows over a resting pointer it doesn't count, so a pointer already
        // inside when it appears must leave and re-enter (never an entry without movement).
        let visible = cardVisibleForGate(frameAnimating: frameAnimating, expanded: isExpanded, rect: rect)
        let id = visible ? app.approvals.current?.id : nil
        let p = pointerLocation()
        let moved = lastGatePointer.map { abs(p.x - $0.x) > 0.5 || abs(p.y - $0.y) > 0.5 } ?? false
        lastGatePointer = p
        let inside = visible && rect.map { $0.contains(p) } == true
        gate.show(id, pointerInside: inside, pointerMoved: moved, now: now)
        let armed = gate.armed(now: now)
        if model.armedId != armed { model.armedId = armed }
        // Same tick, same gate state: the line reads 1 exactly when `armedId` is set.
        let progress = gate.progress(now: now)
        if model.armProgress != progress { model.armProgress = progress }
        if isExpanded && !contentGate.interactive { syncContentGate() }
    }

    private func updateExpansion() {
        guard !resizing else { return }
        // While collapsed, a pointer resting in a resize zone doesn't open the panel,
        // otherwise the collapsed size could never be dragged.
        // Hidden in full screen: hover never opens the closed notch (approvals still do).
        let hoverOpens = hovered && !popupHoverBlocked() && !inBannerActionZone(pointer)
            && (isExpanded || !handles.contains { $0.contains(screenPoint: pointer) })
            && (isExpanded || !fullScreenHide)
        if keyboardOpen && isExpanded {
            // Opened by ⌥⌘N: once the pointer has been in and left again, hover takes over.
            if hovered { keyboardHovered = true } else if keyboardHovered { endKeyboardOpen() }
        }
        let want = hoverOpens || approvalPending || lingering || keyboardOpen
        if want != isExpanded { setExpanded(want, animated: true) }
    }

    // MARK: Keyboard (⌥⌘N, ← →, Esc)

    /// ⌥⌘N: open on the opening tab, or close. Never arms or answers an approval: the card's
    /// buttons still need the pointer to enter the card and dwell (ArmingGate).
    func toggleFromHotKey() {
        guard !resizing else { return }
        if isExpanded {
            endKeyboardOpen()
            updateExpansion()
            notchyLog.notice("Hot key: close (still open: \(self.isExpanded))")
            return
        }
        if model.banner == nil { app.selectTab(openingTab(app.settings.value)) }
        keyboardOpen = true
        keyboardHovered = false
        startKeyboardKeys()
        clearPopupGrowPointer()
        setExpanded(true, animated: true)
        notchyLog.notice("Hot key: open on \(self.app.currentTab.rawValue, privacy: .public)")
    }

    /// Permanent: every key event aimed at the panel is swallowed, in any mode, so no key
    /// (Return, Space, Tab…) can ever reach the approval card's buttons. Only in keyboard mode
    /// do ← → / Esc (no modifiers) act — and they only switch tabs or close.
    private func installKeySwallow() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let code = Int(event.keyCode)
            let down = event.type == .keyDown
            let ours = event.windowNumber
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, ours == self.windowNumber else { return false }
                guard down, self.keyboardOpen, mods.isEmpty else { return true }
                switch code {
                case kVK_LeftArrow: self.stepTab(-1)
                case kVK_RightArrow: self.stepTab(1)
                case kVK_Escape:
                    self.endKeyboardOpen()
                    self.updateExpansion()
                default: break
                }
                return true
            }
            return swallow ? nil : event
        }
    }

    private func startKeyboardKeys() {
        makeKey()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.keyboardOpen else { return }
                self.endKeyboardOpen()
                self.updateExpansion()
            }
        }
        notchyLog.notice("Hot key: panel key \(self.isKeyWindow)")
    }

    /// Another window took the keyboard: keyboard mode ends (hover rules again).
    override func resignKey() {
        super.resignKey()
        guard keyboardOpen else { return }
        notchyLog.notice("Hot key: panel lost key (front \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public))")
        endKeyboardOpen()
        updateExpansion()
    }

    /// Leaves keyboard mode: ← → / Esc go back to the front app.
    private func endKeyboardOpen() {
        if keyboardOpen { notchyLog.notice("Hot key: keyboard mode ends") }
        keyboardOpen = false
        keyboardHovered = false
        // resignKey() is only a notification hook: re-ordering hands key back to the active app.
        if isKeyWindow {
            orderOut(nil)
            orderFrontRegardless()
        }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    /// ← / →: previous / next visible tab (no wrap). Only switches tabs.
    private func stepTab(_ step: Int) {
        guard isExpanded else { return }
        let next = nextTab(app.visibleTabList, current: app.currentTab, step: step)
        if next != app.currentTab { app.selectTab(next) }
        notchyLog.notice("Hot key: tab \(next.rawValue, privacy: .public)")
    }

    // MARK: Notch strip + swipe

    /// Publishes where the notch sits in the open panel (from the open target frame, or the
    /// live frame while the open panel is being resized). The strip's own positions come from
    /// the live frame (`liveNotchMinX`).
    private func syncStrip() {
        let f = (isExpanded && resizing) ? frame : frame(expanded: true)
        let minX = (notchRect.minX - f.minX).rounded()
        let width = f.width.rounded()
        if model.openNotchMinX != minX { model.openNotchMinX = minX }
        if model.openWidth != width { model.openWidth = width }
    }

    /// The notch's left edge from the live frame while open (the frame may be animating),
    /// else from the open target frame.
    private func liveNotchMinX() -> CGFloat {
        let f = isExpanded ? frame : frame(expanded: true)
        return (notchRect.minX - f.minX).rounded()
    }

    /// Trackpad scroll events aimed at this panel (local monitor; events always pass on).
    /// Only switches tabs: no hover re-read, nothing armed or answered.
    private func installSwipe() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let ours = event.windowNumber
            guard event.hasPreciseScrollingDeltas else { return event }
            let p = event.phase
            let phase: SwipePhase = p.contains(.began) ? .began : p.contains(.changed) ? .changed
                : p.contains(.ended) ? .ended : p.contains(.cancelled) ? .cancelled : .other
            let momentum = event.momentumPhase != []
            let dx = Double(event.scrollingDeltaX), dy = Double(event.scrollingDeltaY)
            let natural = event.isDirectionInvertedFromDevice
            MainActor.assumeIsolated {
                guard let self, ours == self.windowNumber else { return }
                self.handleSwipe(phase, momentum: momentum, dx: dx, dy: dy, natural: natural)
            }
            return event
        }
    }

    private func handleSwipe(_ phase: SwipePhase, momentum: Bool, dx: Double, dy: Double, natural: Bool) {
        guard isExpanded, !resizing, app.settings.value.swipeTabs else {
            swipe = SwipeTracker()
            hideSwipeDots()
            return
        }
        let overCard = cardScreenRect().map { !$0.isNull && $0.contains(pointerLocation()) } ?? false
        let step = swipe.feed(phase, momentum: momentum, dx: dx, dy: dy, natural: natural, blocked: overCard)
        syncSwipeDots()
        guard step != 0 else { return }
        let next = nextTab(app.visibleTabList, current: app.currentTab, step: step)
        if next != app.currentTab { app.selectTab(next) }
        notchyLog.notice("Swipe: tab \(next.rawValue, privacy: .public)")
    }

    /// Page dots follow the tracker: shown while the gesture is a swipe; once it isn't (ended,
    /// dropped over the card), one 1 s one-shot hides them. Only scroll events drive this.
    private func syncSwipeDots() {
        if swipe.indicating {
            swipeDotsHideWork?.cancel()
            swipeDotsHideWork = nil
            if !model.swipeDots { model.swipeDots = true }
        } else if model.swipeDots && swipeDotsHideWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.swipeDotsHideWork = nil
                    self?.model.swipeDots = false
                }
            }
            swipeDotsHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    private func hideSwipeDots() {
        swipeDotsHideWork?.cancel()
        swipeDotsHideWork = nil
        if model.swipeDots { model.swipeDots = false }
    }

    // MARK: Hide in full screen

    private func fullScreenHideChanged(_ hide: Bool) {
        fullScreenHide = hide
        notchyLog.notice("Full screen hide: \(hide)")
        syncVisibility()
        updateExpansion()
    }

    /// The closed notch (no pop-up, no banner) is invisible and click-through while hidden.
    private func syncVisibility() {
        let hide = fullScreenHide && !isExpanded && !model.popup && model.banner == nil && !frameAnimating
        let alpha: CGFloat = hide ? 0 : 1
        // An open/close fade owns the alpha until it ends (its completion calls this again).
        if !fading && alphaValue != alpha { alphaValue = alpha }
#if NOTCHY_CAPTURE
        // Capture build: the real pointer never drives the panel (the harness does).
        if !ignoresMouseEvents { ignoresMouseEvents = true }
#else
        if ignoresMouseEvents != hide { ignoresMouseEvents = hide }
#endif
    }

    /// The pointer position hover, the arming gate and the content gate read. Release builds:
    /// always the real pointer.
    private func pointerLocation() -> CGPoint {
#if NOTCHY_CAPTURE
        if let p = CaptureState.shared.pointer { return p }
#endif
        return NSEvent.mouseLocation
    }

    private func contentHeightChanged(_ h: CGFloat) {
        let h = h.rounded(.up)
        guard h > 0, abs(h - contentHeight) >= 0.5 else { return }
        contentHeight = h
        // Default open size follows the content; a custom one only changes if the pending floor applies.
        reframeIfOpen()
    }
}

#if NOTCHY_CAPTURE
/// Capture build only: the harness's virtual pointer moved (no tracking events in capture),
/// and a scripted two-finger swipe through the real swipe handler.
extension NotchPanel {
    func captureResync() { resyncHover() }
    func captureSwipe(_ phase: SwipePhase, dx: Double) {
        handleSwipe(phase, momentum: false, dx: dx, dy: 0, natural: true)
    }
}
#endif
