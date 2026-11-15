import SwiftUI
import NotchyCore

/// Fallback tab row under the notch strip, used only when a narrow custom open width leaves no
/// room beside the notch (normally the tabs sit in the strip: `NotchStrip`).
/// Icon-only tabs, centred; the selected one sits on a dark pill.
/// Click selects. Dragging a tab sideways past a neighbour's midpoint reorders (persisted).
/// One DragGesture on the whole bar: a press that moves < `tabClickSlop` is a click.
struct TabBar: View {
    let tabs: [TabID]
    let selected: TabID
    /// False in the hidden measuring copy: no gestures.
    var live: Bool = true
    let onSelect: (TabID) -> Void
    /// Move `tab` to the visible index given.
    let onMove: (TabID, Int) -> Void

    // `@State` macro is unavailable with the Command Line Tools: declare State directly.
    private let draggingState = State<TabID?>(initialValue: nil)
    private var dragging: TabID? {
        get { draggingState.wrappedValue }
        nonmutating set { draggingState.wrappedValue = newValue }
    }

    private static let space = "notchy.tabbar"
    /// Reduce Motion: reordered tabs jump instead of sliding (AUDIT N1).
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                TabIcon(tab: tab, selected: tab == selected, slot: Palette.tabSlot)
                .opacity(dragging == tab ? 0.6 : 1)
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel(Self.name(tab))
                .accessibilityAddTraits(tab == selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { if live { onSelect(tab) } }
            }
        }
        .coordinateSpace(name: Self.space)
        .gesture(drag, including: live ? .all : .subviews)
        .animation(live && !reduceMotion ? .easeInOut(duration: 0.15) : nil, value: tabs)
        .frame(maxWidth: .infinity)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard hypot(v.translation.width, v.translation.height) >= tabClickSlop else { return }
                if dragging == nil { dragging = tab(at: v.startLocation.x) }
                guard let d = dragging, let i = tabs.firstIndex(of: d) else { return }
                let t = tabDragTarget(from: i, pointerX: Double(v.location.x),
                                      slot: Double(Palette.tabSlot), count: tabs.count)
                if t != i { onMove(d, t) }
            }
            .onEnded { v in
                defer { dragging = nil }
                if dragging == nil, hypot(v.translation.width, v.translation.height) < tabClickSlop,
                   let t = tab(at: v.startLocation.x) {
                    onSelect(t)
                }
            }
    }

    private func tab(at x: CGFloat) -> TabID? {
        let i = Int((x / Palette.tabSlot).rounded(.down))
        return tabs.indices.contains(i) ? tabs[i] : nil
    }

    /// One symbol family (AUDIT T1): outline when unselected, filled when selected (music
    /// note and sparkle have no filled form and stay as they are).
    static func symbol(_ t: TabID, selected: Bool = false) -> String {
        switch t {
        case .music: return "music.note"
        case .claude: return "sparkle"
        case .alerts: return selected ? "bell.fill" : "bell"
        case .calendar: return selected ? "calendar.circle.fill" : "calendar"
        }
    }

    static func name(_ t: TabID) -> String {
        switch t {
        case .music: return "Music"
        case .claude: return "Claude"
        case .alerts: return "Alerts"
        case .calendar: return "Calendar"
        }
    }
}

/// One tab icon in a slot `slot` wide; the selected one sits on a pill. `compact` (layout A's
/// 26 pt slots): 11 pt glyph on a 24 × 22 pill. The pill only narrows when the slot itself is
/// narrower than it (the gap beside it goes first).
struct TabIcon: View {
    let tab: TabID
    let selected: Bool
    let slot: CGFloat
    var compact: Bool = false

    var body: some View {
        let pill = compact ? Palette.tabPillSizeCompact : Palette.tabPillSize
        ZStack {
            if selected {
                Capsule().fill(Palette.panelPill)
                    .frame(width: min(pill.width, slot), height: pill.height)
            }
            Image(systemName: TabBar.symbol(tab, selected: selected))
                .font(.system(size: compact ? Palette.tabIconSizeCompact : Palette.tabIconSize, weight: .medium))
                .foregroundStyle(selected ? ThemedColor(.white) : Palette.panelSecondary)
        }
        .frame(width: slot, height: pill.height + 4)
    }
}

/// The open panel's notch-height strip. Split layout (B, default): tabs half left, half right
/// of the camera notch. Tabs + status (A): all tabs left, status cluster right. Nothing is ever
/// drawn behind the notch: positions come from `NotchWings` (panel edge − 18 pt to notch
/// edge − 8 pt). Drag a tab sideways to reorder; across the notch gap it moves to the other
/// side (the order is one list, the split is computed). A press moving < 4 pt is a click.
struct NotchStrip: View {
    @ObservedObject var app: AppModel
    @ObservedObject var ui: NotchViewModel
    @ObservedObject var calendar: CalendarService

    var body: some View {
        GeometryReader { g in
            let wings = ui.wings(width: g.size.width)
            let tabs = app.visibleTabList
            let layoutKind = app.settings.value.tabLayout
            let strip = tabs.count > 1 && ui.tabsFitInStrip(count: tabs.count, layout: layoutKind)
                ? stripLayout(count: tabs.count, layout: layoutKind, wings: wings) : nil
            // Tabs moved into the right wing (no room on the left): no room for status.
            let tabsInRight = strip.map { $0.leftCount < tabs.count } ?? false
            ZStack(alignment: .topLeading) {
                if let l = strip {
                    StripTabs(tabs: tabs, selected: app.currentTab, layout: l,
                              compact: layoutKind == .tabsAndStatus, height: g.size.height, width: g.size.width,
                              onSelect: { app.selectTab($0) },
                              onMove: { app.moveTab($0, toVisibleIndex: $1) })
                }
                if layoutKind == .tabsAndStatus && !tabsInRight && wings.rightWidth >= 24 {
                    let st = stripStatus(phases: app.sessions.map(\.phase), dockCounts: app.dockCounts,
                                         meetings: calendar.meetings, now: Date())
                    StatusCluster(status: st, available: wings.rightWidth)
                        .frame(width: CGFloat(wings.rightWidth), height: g.size.height, alignment: .trailing)
                        .clipped()
                        .offset(x: CGFloat(wings.rightX))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
    }
}

/// The tab icons at their strip slots, with one drag gesture over the whole strip.
struct StripTabs: View {
    let tabs: [TabID]
    let selected: TabID
    let layout: StripLayout
    /// Layout A (tabs + status): compact icons (AUDIT T2).
    var compact: Bool = false
    let height: CGFloat
    /// The strip's (panel's) width: the widened hit margins stop at its edges.
    var width: CGFloat = .infinity
    let onSelect: (TabID) -> Void
    let onMove: (TabID, Int) -> Void

    private let draggingState = State<TabID?>(initialValue: nil)
    private var dragging: TabID? {
        get { draggingState.wrappedValue }
        nonmutating set { draggingState.wrappedValue = newValue }
    }

    private static let space = "notchy.strip"
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(tabs.enumerated()), id: \.element) { i, tab in
                TabIcon(tab: tab, selected: tab == selected, slot: CGFloat(layout.slot), compact: compact)
                    .opacity(dragging == tab ? 0.6 : 1)
                    // The whole slot is the VoiceOver frame, not just the glyph.
                    .contentShape(Rectangle())
                    .position(x: CGFloat(layout.centers[i]), y: height / 2)
                    .accessibilityElement()
                    .accessibilityLabel(TabBar.name(tab))
                    .accessibilityAddTraits(tab == selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onSelect(tab) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.space)
        .gesture(drag)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: tabs)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard hypot(v.translation.width, v.translation.height) >= tabClickSlop else { return }
                if dragging == nil {
                    guard let i = stripHitSlot(at: Double(v.startLocation.x), layout, panelWidth: Double(width)) else { return }
                    dragging = tabs[i]
                }
                guard let d = dragging, let i = tabs.firstIndex(of: d) else { return }
                let t = tabDragTarget(from: i, pointerX: Double(v.location.x), centers: layout.centers)
                if t != i { onMove(d, t) }
            }
            .onEnded { v in
                defer { dragging = nil }
                if dragging == nil, hypot(v.translation.width, v.translation.height) < tabClickSlop,
                   let i = stripHitSlot(at: Double(v.startLocation.x), layout, panelWidth: Double(width)) {
                    onSelect(tabs[i])
                }
            }
    }
}

/// Layout A's right wing: green dot (6 pt) + Claude sessions working (11 pt semibold), red
/// unread badge (16 pt, 10 pt bold, AUDIT T3; this wins over the shared 10 pt semibold caption),
/// next meeting HH:mm within 12 h behind a 10 pt calendar glyph so it doesn't read as a clock.
/// Each part hidden when empty/zero. When the wing is too narrow it drops, in order, the
/// calendar glyph, the time, then the badge (`stripStatusParts`); the working indicator is
/// never dropped or clipped.
struct StatusCluster: View {
    let status: StripStatus
    /// The right wing's width.
    var available: Double = .infinity

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let spacing: CGFloat = 6
    private static let glyphGap: CGFloat = 2

    /// Text widths as drawn (AppKit metrics of the same system fonts), rounded up.
    private static func textWidth(_ t: String, size: CGFloat, weight: NSFont.Weight) -> Double {
        let f = NSFont.systemFont(ofSize: size, weight: weight)
        return Double(ceil((t as NSString).size(withAttributes: [.font: f]).width)) + 1
    }

    private static let glyphWidth: Double = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let w = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)?.size.width ?? 12
        return Double(ceil(w)) + Double(glyphGap)
    }()

    private var unreadText: String { status.unread > 99 ? "99+" : "\(status.unread)" }

    private var parts: StripStatusParts {
        let time = status.nextMeeting.map { Self.time.string(from: $0) } ?? ""
        let w = StripStatusWidths(
            working: 6 + 4 + Self.textWidth("\(status.working)", size: 11, weight: .semibold),
            unread: max(16, Self.textWidth(unreadText, size: 10, weight: .bold) + 10),
            time: Self.textWidth(time, size: 11, weight: .semibold),
            calendarGlyph: Self.glyphWidth,
            spacing: Double(Self.spacing))
        return stripStatusParts(status, widths: w, available: available)
    }

    var body: some View {
        let parts = parts
        HStack(spacing: Self.spacing) {
            if parts.working {
                HStack(spacing: 4) {
                    Circle().fill(NotchColors.working).frame(width: 6, height: 6)
                    Text("\(status.working)")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(status.working) Claude working")
            }
            if parts.unread {
                Text(unreadText)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Palette.warning))
                    .accessibilityLabel("\(status.unread) unread")
            }
            if parts.time, let next = status.nextMeeting {
                HStack(spacing: Self.glyphGap) {
                    if parts.calendarGlyph {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(Self.time.string(from: next))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Next meeting \(Self.time.string(from: next))")
            }
        }
        .font(Palette.TypeScale.meta.weight(.semibold))
        .foregroundColor(.white)
        .lineLimit(1)
        .fixedSize()
        // VoiceOver hears every part, including any dropped for room.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var p: [String] = []
        if status.working > 0 { p.append("\(status.working) Claude working") }
        if status.unread > 0 { p.append("\(status.unread) unread") }
        if let next = status.nextMeeting { p.append("Next meeting \(Self.time.string(from: next))") }
        return p.joined(separator: ", ")
    }
}

/// Swipe position over the panel's bottom inset: one dot per visible tab, the current one
/// white. Shown only during a swipe and 1 s after it (AUDIT T4), as an overlay that never
/// changes the panel's height.
struct PageDots: View {
    let tabs: [TabID]
    let current: TabID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { t in
                Circle()
                    .fill(t == current ? ThemedColor(.white) : Palette.panelDot)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
