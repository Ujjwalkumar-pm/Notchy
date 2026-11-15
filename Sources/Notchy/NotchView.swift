import SwiftUI
import NotchyCore

/// Root view inside the panel. Collapsed: exactly the notch, nearly transparent, nothing drawn
/// (see notchFillOpacity). Expanded: the notch strip (tabs beside the camera notch), then the
/// approval card (if any), then the selected tab's content (page dots float over the bottom
/// inset during a swipe only).
struct NotchView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var ui: NotchViewModel
    @ObservedObject var display = DisplayOptions.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Frosted Glass (AUDIT G1): the open panel's themed colours switch with it; Reduce
        // Transparency and Increase Contrast show solid black, so they stay on the Black values.
        let glass = app.settings.value.theme == .glass && !reduceTransparency && !display.increaseContrast
        ZStack(alignment: .top) {
            let banner = ui.expanded ? nil : ui.banner
            let shape = NotchShape(topCornerRadius: ui.expanded ? 6 : 0,
                                   bottomCornerRadius: ui.expanded ? Palette.Radius.panel
                                       : (banner != nil ? Palette.Radius.banner : (ui.popup ? Palette.Radius.popup : 6)))
            if ui.expanded && app.settings.value.theme == .glass {
                // Glass theme: open panel only. Closed states (notch, pop-up, banners) are always
                // black because they merge with the hardware notch (AUDIT G2 a).
                GlassBackground().clipShape(shape)
            } else {
                // The pop-up and banners are the only closed states drawn solid.
                shape.fill(Color.black.opacity(notchFillOpacity(expanded: ui.expanded || ui.popup || banner != nil)))
            }
            if ui.expanded {
                VStack(spacing: 0) {
                    // The notch-height strip: tabs (and in layout A the status cluster) either
                    // side of the camera notch, and the in-panel level control in the wing
                    // opposite the selected tab. Overlays only, so the content (and the approval card's rect) never
                    // moves.
                    Color.clear.frame(height: ui.notchSize.height)
                        .overlay {
                            // Strip tabs: no clicks until the open settled and the pointer moved.
                            NotchStrip(app: app, ui: ui, calendar: app.calendar)
                                .allowsHitTesting(ui.contentInteractive)
                        }
                    ExpandedContent(app: app, ui: ui)
                }
                // A custom open size can be smaller or larger than the content: pin it to the
                // top and let the panel clip the rest.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // After the full-size frame: the bottom fallback bar sits on the panel's real
                // bottom inside edge whatever the custom size.
                .overlay {
                    if ui.popup {
                        InPanelLevelBar(app: app, ui: ui)
                            .transition(.opacity)
                    }
                }
                // AUDIT T4: page dots only during a swipe and 1 s after, fading 0.2 s, over the
                // content's bottom inset. An overlay, so the panel height never changes for them.
                // The fade is scoped to the dots so it never animates the tab switch itself.
                .overlay(alignment: .bottom) {
                    let tabs = app.visibleTabList
                    ZStack {
                        if ui.swipeDots && app.settings.value.swipeTabs && tabs.count > 1 {
                            PageDots(tabs: tabs, current: app.currentTab)
                                .padding(.bottom, Palette.Space.pageDots)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: ui.swipeDots)
                    .allowsHitTesting(false)
                }
                .environment(\.notchGlass, glass)
                // AUDIT N2: fades in rising 4 pt into place (static under Reduce Motion), fades
                // out in place; timing from `contentAnimation`.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: CGFloat(contentRiseOffset(reduceMotion: display.reduceMotion)))),
                    removal: .opacity))
            } else if let banner {
                VStack(spacing: 0) {
                    Color.clear.frame(height: ui.notchSize.height)
                    BannerView(banner: banner,
                               onAction: { ui.onBannerAction?() },
                               onOpen: { ui.onBannerOpen?() })
                        .frame(height: bannerExtraHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                .id(banner.id) // a newer banner replaces the older one (cross-fade)
            } else if ui.popup {
                VStack(spacing: 0) {
                    Color.clear.frame(height: ui.notchSize.height)
                    LevelPopup(hud: app.hud).frame(height: popupExtraHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            } else if ui.outlineFlash {
                // Welcome step 1 (AUDIT R1): a 2 pt accent outline in the 3 pt ring around the
                // camera notch (the stroke's inner half lies over the notch, which has no pixels).
                shape.stroke(Palette.accent, lineWidth: 4)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            // Hidden measurement of the expanded content at the expanded width. Not live: it
            // must never animate (an invisible repeatForever pulse would wake the CPU each frame).
            ExpandedContent(app: app, ui: ui, live: false)
                .environment(\.notchGlass, glass)
                .frame(width: NotchPanel.expandedWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                })
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onPreferenceChange(ContentHeightKey.self) { h in
            MainActor.assumeIsolated { ui.onContentHeight?(h) }
        }
        .onPreferenceChange(CardRectKey.self) { r in
            MainActor.assumeIsolated { ui.cardRect = r }
        }
        .onPreferenceChange(BannerActionRectKey.self) { r in
            MainActor.assumeIsolated { ui.bannerActionRect = r }
        }
        .animation(contentAnimation, value: ui.expanded)
        .animation(.easeInOut(duration: 0.15), value: ui.popup)
        .animation(.easeInOut(duration: 0.25), value: ui.outlineFlash)
        .animation(.easeInOut(duration: 0.2), value: ui.banner)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .environment(\.notchReduceMotion, display.reduceMotion)
        .environment(\.notchIncreaseContrast, display.increaseContrast)
    }

    /// AUDIT N2: the content fade follows the open/close frame animation (duration set by the
    /// panel before `expanded` flips, Speed and Reduce Motion included). Open: easeOut over
    /// 0.6 × duration after 0.08 s; close: easeIn over 0.4 × duration. Instant: none.
    private var contentAnimation: Animation? {
        guard let t = contentFadeTiming(duration: ui.openCloseDuration, opening: ui.expanded) else { return nil }
        return ui.expanded ? .easeOut(duration: t.duration).delay(t.delay) : .easeIn(duration: t.duration)
    }
}

/// The open panel's level control (AUDIT P4). Preferred: a 12 pt icon and a 64 x 4 pt bar,
/// vertically centred in the notch-height strip, in the wing opposite the selected tab (hugging
/// the notch, clear of any tabs there). When that wing has no room (a narrow panel in the split
/// layout), the fallback: a 3 pt bar at the panel's bottom inside edge, inset 30 pt so it clears
/// the 30 pt corner radius. Never takes clicks.
struct InPanelLevelBar: View {
    @ObservedObject var app: AppModel
    @ObservedObject var ui: NotchViewModel

    var body: some View {
        GeometryReader { g in
            let wings = ui.wings(width: g.size.width)
            let tabs = app.visibleTabList
            let kind = app.settings.value.tabLayout
            let layout = tabs.count > 1 && ui.tabsFitInStrip(count: tabs.count, layout: kind)
                ? stripLayout(count: tabs.count, layout: kind, wings: wings) : nil
            let muted = isLevelMuted(app.hud)
            let tabsInRight = layout.map { $0.leftCount < tabs.count } ?? false
            let statusInRight = kind == .tabsAndStatus && !tabsInRight && wings.rightWidth >= 24
            if let s = levelIndicatorSlot(wings: wings, layout: layout,
                                          selected: tabs.firstIndex(of: app.currentTab),
                                          statusInRight: statusInRight) {
                HStack(spacing: 6) {
                    Image(systemName: levelIcon(app.hud))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(muted ? Palette.panelSecondary : ThemedColor(.white))
                        .frame(width: 12)
                    LevelBar(fraction: levelFraction(app.hud), height: 4, fill: levelFill(app.hud))
                }
                .frame(width: CGFloat(s.width), height: ui.notchSize.height)
                .offset(x: CGFloat(s.x))
            } else {
                LevelBar(fraction: levelFraction(app.hud), height: 3, fill: levelFill(app.hud))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 6)
                    .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ExpandedContent: View {
    @ObservedObject var app: AppModel
    @ObservedObject var ui: NotchViewModel
    var live: Bool = true

    private var contentTakesClicks: Bool { live && ui.contentInteractive }

    var body: some View {
        let current = app.approvals.current
        let tabs = app.visibleTabList
        let tab = app.currentTab
        VStack(alignment: .leading, spacing: 0) {
            // The card is always first, above the tab bar, on any tab: switching tabs never
            // moves it (its rect feeds the ArmingGate).
            if let current {
                ApprovalCard(request: current, pendingCount: app.approvals.pendingCount,
                             otherLabels: app.otherWaitingLabels(excluding: current),
                             armedId: ui.armedId, armProgress: ui.armProgress,
                             commandExpanded: ui.commandExpandedId == current.id,
                             onShowAll: { id in if live { ui.expandCommand(id) } },
                             live: live) { id, d in
                    guard live else { return }
                    ui.disarm() // block a double click landing on the next card
                    app.decide(id, d)
                }
                .padding(.bottom, Palette.Space.sectionGap)
            }
            // Tabs live in the notch strip (NotchStrip). Only when a narrow custom open width
            // leaves no room beside the notch do they fall back to a row here. Decided from
            // the open frame, so the live view and the measuring copy agree.
            if tabs.count > 1 && !ui.tabsFitInStrip(count: tabs.count, layout: app.settings.value.tabLayout) {
                TabBar(tabs: tabs, selected: tab, live: live,
                       onSelect: { t in if live { app.selectTab(t) } },
                       onMove: { t, i in if live { app.moveTab(t, toVisibleIndex: i) } })
                    .padding(.bottom, 4)
                    .allowsHitTesting(contentTakesClicks)
            }
            // The hidden measuring copy renders the same tab, so the panel height follows it.
            // Everything below the card ignores clicks until the open settled and the pointer
            // moved (ContentGate): the panel may have grown over a resting or mid-click pointer.
            Group {
                switch tab {
                case .music: MusicTab(app: app, live: live)
                case .claude: ClaudeTab(app: app, current: current, live: live)
                case .alerts: AlertsTab(app: app, live: live)
                case .calendar: CalendarTab(service: app.calendar, live: live)
                }
            }
            .allowsHitTesting(contentTakesClicks)
            // Page dots are no longer part of the content (AUDIT T4): an overlay in NotchView
            // shows them during a swipe only, so live and measuring copies stay identical.
        }
        .padding(.horizontal, Palette.sideInset)
        .padding(.top, Palette.Space.contentTop)
        .padding(.bottom, Palette.Space.contentBottom)
    }
}

struct MusicTab: View {
    @ObservedObject var app: AppModel
    let live: Bool

    var body: some View {
        let state = app.nowPlaying.state
        if state.visible(now: Date()), let info = state.info {
            NowPlayingRow(info: info, live: live, onCommand: { cmd in
                guard live else { return }
                app.nowPlaying.send(cmd)
            }, onSeek: { seconds in
                guard live else { return }
                app.nowPlaying.seek(to: seconds)
            })
        } else {
            EmptyState(copy: .nothingPlaying, live: live, action: ("Open Music", {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }))
        }
    }
}

struct ClaudeTab: View {
    @ObservedObject var app: AppModel
    let current: ApprovalRequest?
    let live: Bool

    var body: some View {
        // The pending card's own session is already shown by the card.
        let rows = app.sessions.filter { $0.id != current?.sessionId }
        if rows.isEmpty {
            EmptyState(copy: .claude(hasPendingCard: current != nil), live: live)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Rectangle().fill(Palette.separator).frame(height: 1) }
                    SessionRow(session: s, animated: live)
                        .frame(height: Palette.Space.sessionRow - (i > 0 ? 1 : 0))
                }
            }
        }
    }
}

/// Shared empty state (AUDIT M4): 20 pt symbol, 13 pt title, 11 pt hint, optional dark pill.
struct EmptyState: View {
    let copy: EmptyStateCopy
    var live: Bool = true
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: copy.symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.panelSecondary.opacity(0.7))
                .accessibilityHidden(true) // decorative; the title says it
            Text(copy.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Text(copy.hint)
                .font(Palette.TypeScale.meta)
                .foregroundStyle(Palette.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button { if live { action.run() } } label: {
                    Text(action.title)
                        .font(Palette.TypeScale.meta.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Capsule().fill(Palette.panelPill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!live)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }
}

struct PlaceholderText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Palette.TypeScale.secondary)
            .foregroundStyle(Palette.panelSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}

struct SessionRow: View {
    let session: SessionInfo
    @Environment(\.notchIncreaseContrast) private var increaseContrast
    /// False in the hidden measuring copy: dots stay static.
    var animated: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: color, pulsing: animated && isWorking, size: 7)
            Text(session.label)
                .font(Palette.TypeScale.body)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if case .working(let tool?) = session.phase {
                Text(tool)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.85))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.10)))
            }
            HStack(spacing: 3) {
                Text(session.phase.label)
                    .font(Palette.TypeScale.secondary)
                if session.phase == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(session.phase == .waitingApproval ? ThemedColor(NotchColors.waiting) : Palette.panelSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var isWorking: Bool {
        if case .working = session.phase { return true } else { return false }
    }

    private var color: Color {
        switch session.phase {
        case .working: return NotchColors.working
        case .waitingApproval: return NotchColors.waiting
        case .idle, .done: return increaseContrast ? NotchColors.quietContrast : NotchColors.quiet
        }
    }
}

struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    var size: CGFloat = 7
    // `@State` is a macro in this SDK and the Command Line Tools ship no SwiftUIMacros
    // plugin, so the State property is declared without the attribute.
    @Environment(\.notchReduceMotion) private var reduceMotion
    private let dimState = State(initialValue: false)
    private var dim: Bool {
        get { dimState.wrappedValue }
        nonmutating set { dimState.wrappedValue = newValue }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing && dim ? 0.55 : 1) // AUDIT C4: 100 % to 55 %
            .animation(pulsing && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: dim)
            .onAppear { dim = pulsing && !reduceMotion }
            .onChange(of: pulsing) { _, p in dim = p && !reduceMotion }
            // Reduce Motion switched while showing: stop (or restart) the pulse at once.
            .onChange(of: reduceMotion) { _, rm in dim = pulsing && !rm }
            .accessibilityHidden(true)
    }
}

/// Frosted panel background for the Glass theme: `.hudWindow` material under a black tint at
/// 0.60. AUDIT G1 asked for 0.55; measured over a plain white backdrop the material + 0.55
/// sits at #5C5C5C, where white-72 % secondary text is 4.39:1 (below AA). 0.60 gives #545454
/// and 4.87:1 (0.35 was 2.93:1). With Reduce Transparency on, plain black at 0.85; with
/// Increase Contrast on, solid black.
struct GlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.notchIncreaseContrast) private var increaseContrast

    var body: some View {
        if increaseContrast {
            Color.black
        } else if reduceTransparency {
            Color.black.opacity(0.85)
        } else {
            VisualEffectBackground(material: .hudWindow)
                .overlay(Color.black.opacity(0.60))
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
