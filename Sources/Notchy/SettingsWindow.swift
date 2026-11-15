import AppKit
import SwiftUI
import NotchyCore

/// The Settings window (right-click → Settings…): one instance, a normal-level dark window
/// with standard traffic lights. Closing it only hides it (Notchy is an accessory app; closing
/// the last window never quits). Opening it touches nothing on the notch panel.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let calendar: CalendarService
    private let quiet: QuietMonitor
    private weak var panel: NotchPanel?

    init(settings: SettingsStore, calendar: CalendarService, quiet: QuietMonitor, panel: NotchPanel?) {
        self.settings = settings
        self.calendar = calendar
        self.quiet = quiet
        self.panel = panel
    }

    func show() {
        let w = window ?? makeWindow()
        if !w.isVisible { center(w) }
        // Plain cooperative activate() is refused here (the click came through a
        // non-activating panel while another app was active), leaving the window unfocused.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = SettingsNSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Notchy Settings"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(white: 0.11, alpha: 1)
        w.isReleasedWhenClosed = false
        w.level = .normal
        w.delegate = self
        let host = NSHostingView(rootView: SettingsRoot(settings: settings, calendar: calendar, quiet: quiet, panel: panel))
        host.sizingOptions = []
        w.contentView = host
        window = w
        return w
    }

#if NOTCHY_CAPTURE
    /// Capture build: the window (created on first use) for the harness to place and capture.
    func captureWindow() -> NSWindow { window ?? makeWindow() }
#endif

    /// Centred on the screen with the pointer (the active screen).
    private func center(_ w: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { w.center(); return }
        let s = w.frame.size
        w.setFrameOrigin(CGPoint(x: vf.midX - s.width / 2, y: vf.midY - s.height / 2))
    }
}

/// Closes with Esc (cancelOperation) and Cmd-W (no main menu in an accessory app, so the
/// standard File ▸ Close key equivalent doesn't exist).
final class SettingsNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", notch = "Notch", tabs = "Tabs", alerts = "Alerts", calendar = "Calendar", appearance = "Appearance", about = "About"
    var id: String { rawValue }
    /// 13 pt sidebar glyph (AUDIT S2).
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .notch: return "rectangle.topthird.inset.filled"
        case .tabs: return "square.grid.2x2"
        case .alerts: return "bell"
        case .calendar: return "calendar"
        case .appearance: return "paintpalette"
        case .about: return "info.circle"
        }
    }
    /// Page title (13 pt semibold): the section name, except Calendar's "Calendars".
    var pageTitle: String { self == .calendar ? "Calendars" : rawValue }
}

/// Settings colours: sidebar and grouped rows on a dark window.
private enum SettingsLook {
    static let window = Color(white: 0.11)
    static let sidebar = Color(white: 0.085)
    static let group = Color(hex: 0x1F1F21)
    static let rowSeparator = Color(white: 0.17)
    static let sidebarRowHeight: CGFloat = 28
    static let sidebarRadius: CGFloat = 6
    static let rowHeight: CGFloat = 36
    static let radius = Palette.Radius.s
}

struct SettingsRoot: View {
    @ObservedObject var settings: SettingsStore
    let calendar: CalendarService
    let quiet: QuietMonitor
    weak var panel: NotchPanel?
    @ObservedObject var display = DisplayOptions.shared
#if NOTCHY_CAPTURE
    @ObservedObject var capture = CaptureState.shared
#endif

    // `@State` macro is unavailable with the Command Line Tools: declare State directly.
    private let sectionState = State(initialValue: SettingsSection.general)
    private var section: SettingsSection {
        get {
#if NOTCHY_CAPTURE
            if let s = capture.settingsSection { return s }
#endif
            return sectionState.wrappedValue
        }
        nonmutating set { sectionState.wrappedValue = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(section.pageTitle)
                    VStack(alignment: .leading, spacing: 22) {
                        switch section {
                        case .general: GeneralSection(settings: settings, quiet: quiet, panel: panel)
                        case .notch: NotchSection(settings: settings, panel: panel)
                        case .tabs: TabsSection(settings: settings)
                        case .alerts: AlertsSection(settings: settings)
                        case .calendar: CalendarSection(settings: settings, calendar: calendar)
                        case .appearance: AppearanceSection(settings: settings)
                        case .about: AboutSection()
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SettingsLook.window)
        }
        .frame(minWidth: 560, minHeight: 400)
        .preferredColorScheme(.dark)
        .environment(\.notchReduceMotion, display.reduceMotion)
        .environment(\.notchIncreaseContrast, display.increaseContrast)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { s in
                let selected = section == s
                Button { section = s } label: {
                    HStack(spacing: 8) {
                        // 13 pt glyph in a 20 pt rounded tile.
                        Image(systemName: s.symbol)
                            .font(.system(size: 13))
                            .foregroundColor(selected ? Palette.selectionLabel : .white)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected ? Palette.selectionLabel.opacity(0.18) : Palette.pill))
                            .accessibilityHidden(true)
                        Text(s.rawValue)
                            .font(.system(size: 13))
                            .foregroundColor(selected ? Palette.selectionLabel : .white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: SettingsLook.sidebarRowHeight)
                    // The current accent at 85 % with white text (AUDIT S2).
                    .background(RoundedRectangle(cornerRadius: SettingsLook.sidebarRadius, style: .continuous)
                        .fill(selected ? Palette.accent.opacity(0.85) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            sidebarFooter
        }
        .padding(.horizontal, 10)
        .padding(.top, 14) // the safe area already clears the traffic lights
        .padding(.bottom, 12)
        .frame(width: 170)
        .frame(maxHeight: .infinity)
        .background(SettingsLook.sidebar)
    }

    /// App identity and housekeeping (AUDIT S1): icon, name, version, Quit.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppIconTile(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Notchy").font(Palette.TypeScale.body).foregroundColor(.white)
                    Text(AppInfo.versionLine).font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .accessibilityElement(children: .combine)
            Button { NSApp.terminate(nil) } label: {
                Text("Quit Notchy").font(Palette.TypeScale.secondary).foregroundStyle(Palette.secondaryText)
                    .frame(minHeight: CGFloat(minimumHitSize)) // AUDIT Y1
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }
}

/// Version and build from the bundle (Info.plist); unbundled dev runs have neither.
enum AppInfo {
    static var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    static var build: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }
    static var versionLine: String {
        guard let v = version else { return "Development build" }
        return build.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }
}

/// Placeholder app icon (no real icon exists yet): the closed-notch glyph in the accent on a
/// black rounded tile. Task 11 may replace it with the real icon.
private struct AppIconTile: View {
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color.black)
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Palette.hairlineStroke, lineWidth: 1))
            .overlay(Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(Palette.accent))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: Building blocks

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Palette.TypeScale.body).foregroundColor(.white)
    }
}

/// Group label (AUDIT S3): 11 pt semibold secondary, uppercase, 0.5 tracking; an optional
/// trailing action sits at the right.
private struct GroupLabel<Trailing: View>: View {
    let text: String
    @ViewBuilder let trailing: Trailing
    init(_ text: String, @ViewBuilder trailing: () -> Trailing) { self.text = text; self.trailing = trailing() }
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Palette.TypeScale.meta.weight(.semibold)).tracking(0.5)
                .foregroundStyle(Palette.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}
extension GroupLabel where Trailing == EmptyView {
    fileprivate init(_ text: String) { self.init(text) { EmptyView() } }
}

/// A text-only button: accent, 12 pt.
private struct TextButton: View {
    let title: String
    var label: String? = nil
    let action: () -> Void
    init(_ title: String, label: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.label = label; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(Palette.TypeScale.secondary).foregroundColor(Palette.accent)
                .frame(minHeight: CGFloat(minimumHitSize)) // AUDIT Y1
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
    }
}

/// Rows on a rounded dark group. Rows paint the group colour themselves; the 1 pt gaps
/// between them show the separator colour underneath, giving hairlines between rows only.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 1) { content }
            .background(SettingsLook.rowSeparator)
            .clipShape(RoundedRectangle(cornerRadius: SettingsLook.radius, style: .continuous))
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// Optional colour dot before the title (calendar colour).
    var dot: Color? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).foregroundColor(.white)
                if let subtitle {
                    Text(subtitle).font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(minHeight: SettingsLook.rowHeight)
        .background(SettingsLook.group)
    }
}

private struct SwitchRow: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Binding<Bool>
    var dot: Color? = nil
    var body: some View {
        Row(title: title, subtitle: subtitle, dot: dot) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.switchOn)
        }
    }
}

private extension SettingsStore {
    /// Binding to one settings field; writes go through `update`.
    func binding<T>(_ key: WritableKeyPath<NotchySettings, T>) -> Binding<T> {
        Binding(get: { self.value[keyPath: key] },
                set: { v in self.update { $0[keyPath: key] = v } })
    }
}

private struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Palette.TypeScale.secondary.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: CGFloat(minimumHitSize)) // AUDIT Y1: was ~22
                .background(Capsule().fill(Palette.pill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: General

private struct GeneralSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var quiet: QuietMonitor
    weak var panel: NotchPanel?

    // SMAppService status isn't observable: re-read on appear and after every change.
    private let loginState = State(initialValue: Lifecycle.startsAtLogin)
    private var startsAtLogin: Bool {
        get { loginState.wrappedValue }
        nonmutating set { loginState.wrappedValue = newValue }
    }

    // Whether Notchy's hooks are in ~/.claude/settings.json; re-read on appear and after changes.
    private let hooksState = State(initialValue: Lifecycle.installer.isInstalled())
    private var hooksOn: Bool {
        get { hooksState.wrappedValue }
        nonmutating set { hooksState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroup {
                SwitchRow(title: "Start at login", isOn: Binding(
                    get: { startsAtLogin },
                    set: { on in
                        if on { Lifecycle.userEnableStartAtLogin() } else { Lifecycle.userDisableStartAtLogin() }
                        startsAtLogin = Lifecycle.startsAtLogin
                    }))
                // AUDIT S6: on = installed; turning it off asks first and sticks across launches.
                SwitchRow(title: "Claude Code integration",
                          subtitle: hooksOn ? "Installed in ~/.claude/settings.json"
                                            : "Not installed. Claude sessions won't show in the notch.",
                          isOn: Binding(
                    get: { hooksOn },
                    set: { on in
                        if on {
                            NotchActions.installClaudeHooks(settings: settings)
                            hooksOn = Lifecycle.installer.isInstalled()
                        } else {
                            // The switch stays on until the sheet is confirmed.
                            NotchActions.removeClaudeHooks(settings: settings) { _ in
                                hooksOn = Lifecycle.installer.isInstalled()
                            }
                        }
                    }))
            }
        }
        .onAppear {
            startsAtLogin = Lifecycle.startsAtLogin
            hooksOn = Lifecycle.installer.isInstalled()
        }

        // AUDIT R1: the welcome is reopenable here; the menu-bar icon is a second way in.
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Getting started")
            SettingsGroup {
                Row(title: "Welcome & permissions", subtitle: "The 3-step tour and what Notchy can access") {
                    SecondaryButton("Show Welcome\u{2026}") { NotchActions.onShowWelcome?() }
                }
                SwitchRow(title: "Menu bar icon", subtitle: "A second way into Settings",
                          isOn: settings.binding(\.menuBarIcon))
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Banners & shortcuts")
            SettingsGroup {
                SwitchRow(title: "Quiet while presenting / in calls",
                          subtitle: "Calls (mic or camera) and full-screen video", isOn: settings.binding(\.quietWhilePresenting))
                SwitchRow(title: "Respect Focus / Do Not Disturb",
                          subtitle: settings.value.respectFocus ? quiet.focusUnavailableText : nil, isOn: settings.binding(\.respectFocus))
                SwitchRow(title: "Hide in full-screen apps", subtitle: "Volume pop-up still shows",
                          isOn: settings.binding(\.hideInFullScreen))
                SwitchRow(title: "Meeting reminders", subtitle: "1 minute before meetings with a join link",
                          isOn: settings.binding(\.meetingReminder))
                SwitchRow(title: "Claude finished", subtitle: "For tasks longer than 1 minute",
                          isOn: settings.binding(\.claudeFinishedBanner))
                Row(title: "Open notch",
                    subtitle: (panel?.hotKeyAvailable ?? true) ? nil : "Shortcut unavailable (in use by another app)") {
                    Text("⌥⌘N")
                        .font(Palette.TypeScale.meta.weight(.medium))
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Palette.Radius.xs, style: .continuous).fill(Palette.pill))
                        .accessibilityLabel("Option Command N")
                }
            }
        }
    }
}

// MARK: Notch

/// Sizes (sliders write the panel's custom sizes, the same store as Set size…), where the
/// open panel is anchored, how it animates, swipe and tab layout.
private struct NotchSection: View {
    @ObservedObject var settings: SettingsStore
    weak var panel: NotchPanel?
    @ObservedObject var display = DisplayOptions.shared

    /// Bumped after every size change so the sliders re-read the panel (not observable).
    private let sizeTickState = State(initialValue: 0)
    private var sizeTick: Int {
        get { sizeTickState.wrappedValue }
        nonmutating set { sizeTickState.wrappedValue = newValue }
    }

    // Slider ranges. Larger sizes stay possible through Set size… (no cap); closed sizes never
    // go below the camera notch (AUDIT R2).
    private static let closedWidth: ClosedRange<Double> = 60...800
    private static let closedHeight: ClosedRange<Double> = 20...200
    private static let openWidth: ClosedRange<Double> = 240...1200
    private static let openHeight: ClosedRange<Double> = 80...900
    /// The open-height slider runs one notch past its range: that end is "Auto".
    private static let autoStep: Double = 40

    var body: some View {
        let _ = sizeTick
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Size") {
                TextButton("Set size…") {
                    guard let panel else { return }
                    NotchActions.setSize(panel: panel)
                    sizeTick += 1
                }
            }
            SettingsGroup {
                // AUDIT R2: on a notched Mac the closed sliders start at the notch.
                sizeRow("Closed width", value: closedSize.map { Double($0.width) },
                        range: closedSliderRange(base: Self.closedWidth, minimum: panel?.closedMinimum?.width)) { v in
                    guard let panel, let s = closedSize else { return }
                    panel.setCustomSize(CGSize(width: v, height: s.height), expanded: false)
                }
                sizeRow("Closed height", value: closedSize.map { Double($0.height) },
                        range: closedSliderRange(base: Self.closedHeight, minimum: panel?.closedMinimum?.height)) { v in
                    guard let panel, let s = closedSize else { return }
                    panel.setCustomSize(CGSize(width: s.width, height: v), expanded: false)
                }
                sizeRow("Open width", value: openSize.map { Double($0.width) }, range: Self.openWidth) { v in
                    guard let panel else { return }
                    panel.setOpenSize(width: v, height: openHeightAuto ? nil : openSize.map(\.height))
                }
                openHeightRow
            }
            TextButton("Reset", label: "Reset to notch size") {
                panel?.resetSizes()
                sizeTick += 1
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Opening")
            SettingsGroup {
                Row(title: "Open from") {
                    Picker("Open from", selection: settings.binding(\.openFrom)) {
                        Text("Centre").tag(OpenAnchor.centre)
                        Text("Left").tag(OpenAnchor.left)
                        Text("Right").tag(OpenAnchor.right)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                }
                // AUDIT N1: under Reduce Motion the panel fades whatever is picked here.
                Row(title: "Animation",
                    subtitle: showsReduceMotionCaption(settings.value.animation, reduceMotion: display.reduceMotion)
                        ? "Reduce Motion is on: using Fade" : nil) {
                    Picker("Animation", selection: settings.binding(\.animation)) {
                        Text("Spring").tag(PanelAnimation.spring)
                        Text("Smooth").tag(PanelAnimation.smooth)
                        Text("Snappy").tag(PanelAnimation.snappy)
                        Text("Fade").tag(PanelAnimation.fade)
                        Text("None").tag(PanelAnimation.none)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 280)
                }
                Row(title: "Speed") {
                    Picker("Speed", selection: settings.binding(\.animationSpeed)) {
                        Text("Slow").tag(AnimationSpeed.slow)
                        Text("Normal").tag(AnimationSpeed.normal)
                        Text("Fast").tag(AnimationSpeed.fast)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    // Reduce Motion fixes the fade at 0.15 s, so Speed has no effect then.
                    .disabled(settings.value.animation == .none || display.reduceMotion)
                }
                SwitchRow(title: "Swipe to change tabs", subtitle: "Two fingers left or right over the open notch",
                          isOn: settings.binding(\.swipeTabs))
                // AUDIT S5: two 120 x 40 thumbnails (B split, A tabs + status) and a caption.
                Row(title: "Tab layout",
                    subtitle: settings.value.tabLayout == .split ? "Tabs around the notch"
                                                                 : "Tabs left, status right") {
                    HStack(spacing: 8) {
                        LayoutThumbnail(layout: .split, selected: settings.value.tabLayout == .split) {
                            settings.update { $0.tabLayout = .split }
                        }
                        LayoutThumbnail(layout: .tabsAndStatus, selected: settings.value.tabLayout == .tabsAndStatus) {
                            settings.update { $0.tabLayout = .tabsAndStatus }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var closedSize: CGSize? { panel?.effectiveSize(expanded: false) }
    /// The open size shown: the custom size (Auto height = content height) or the default.
    private var openSize: CGSize? {
        guard let panel else { return nil }
        return panel.customSize(expanded: true) ?? panel.defaultSize(expanded: true)
    }
    private var openHeightAuto: Bool { panel?.openHeightIsAuto ?? true }

    private var openHeightRow: some View {
        let top = Self.openHeight.upperBound + Self.autoStep
        let value = openHeightAuto ? top : min(max(Double(openSize?.height ?? 0), Self.openHeight.lowerBound),
                                               Self.openHeight.upperBound)
        return Row(title: "Open height") {
            SizeSlider(label: openHeightAuto ? "Auto" : "\(Int(openSize?.height ?? 0)) pt",
                       value: value, range: Self.openHeight.lowerBound...top) { v in
                guard let panel, let s = openSize else { return }
                // The last step is "Auto" (fits the content).
                let auto = v > Self.openHeight.upperBound + Self.autoStep / 2
                panel.setOpenSize(width: s.width, height: auto ? nil : min(v, Self.openHeight.upperBound))
                sizeTick += 1
            }
            .accessibilityValue(openHeightAuto ? "Auto" : "\(Int(openSize?.height ?? 0)) points")
        }
    }

    private func sizeRow(_ title: String, value: Double?, range: ClosedRange<Double>,
                         set: @escaping (Double) -> Void) -> some View {
        Row(title: title) {
            SizeSlider(label: value.map { "\(Int($0)) pt" } ?? "—",
                       value: min(max(value ?? range.lowerBound, range.lowerBound), range.upperBound),
                       range: range) { v in
                set(v)
                sizeTick += 1
            }
        }
    }
}

/// 120 x 40 sketch of the tab strip in one layout, with its name below; the selected one has
/// an accent ring.
private struct LayoutThumbnail: View {
    let layout: TabLayout
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous)
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    Color.black
                    HStack(spacing: 0) {
                        switch layout {
                        case .split:
                            dots(2)
                            Spacer(minLength: 0)
                            Capsule().fill(Color.white.opacity(0.10)).frame(width: 28, height: 8) // camera notch
                            Spacer(minLength: 0)
                            dots(2)
                        case .tabsAndStatus:
                            dots(4)
                            Spacer(minLength: 0)
                            Capsule().fill(Palette.secondary).frame(width: 28, height: 6) // live status
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(width: 120, height: 40)
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? ThemedColor(Palette.accent) : Palette.hairlineStroke,
                                            lineWidth: selected ? 2 : 1))
                Text(layout == .split ? "Split" : "Tabs + status")
                    .font(Palette.TypeScale.meta).lineLimit(1).fixedSize()
                    .foregroundStyle(selected ? ThemedColor(.white) : Palette.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .split ? "Split layout" : "Tabs and status layout")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func dots(_ n: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { i in
                Circle().fill(i == 0 && selected ? Palette.accent : Palette.secondary).frame(width: 8, height: 8)
            }
        }
    }
}

/// Value label + slider (whole points). Writes on every change, like dragging the panel edge.
private struct SizeSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Palette.TypeScale.secondary.monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 56, alignment: .trailing)
            Slider(value: Binding(get: { value },
                                  set: { v in
                                      let r = v.rounded()
                                      if r != value.rounded() { onChange(r) }
                                  }),
                   in: range)
                .controlSize(.small)
                .frame(width: 140)
                .labelsHidden()
        }
    }
}

// MARK: Tabs

private struct TabsSection: View {
    @ObservedObject var settings: SettingsStore

    private let dragState = State<(tab: TabID, dy: CGFloat)?>(initialValue: nil)
    private var drag: (tab: TabID, dy: CGFloat)? {
        get { dragState.wrappedValue }
        nonmutating set { dragState.wrappedValue = newValue }
    }
    private static let rowStride = SettingsLook.rowHeight + 1 // row + hairline
    private static let listSpace = "notchy.settings.tabsList"

    var body: some View {
        let s = settings.value
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroup {
                ForEach(Array(s.tabOrder.enumerated()), id: \.element) { i, tab in
                    row(tab, index: i, settings: s)
                        .offset(y: drag?.tab == tab ? drag!.dy : 0)
                        .zIndex(drag?.tab == tab ? 1 : 0)
                }
            }
            // The dragged row moves (offset); measure the drag in the list's space, not the
            // row's own, or the translation feeds back on itself.
            .coordinateSpace(name: Self.listSpace)
            Text("Drag to reorder. At least one tab stays on.")
                .font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
        }
    }

    private func row(_ tab: TabID, index: Int, settings s: NotchySettings) -> some View {
        let enabled = s.enabledTabs.contains(tab)
        let isLast = enabled && s.enabledTabs.count == 1
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(Palette.TypeScale.meta)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 18, height: SettingsLook.rowHeight)
                .contentShape(Rectangle())
                .gesture(reorder(tab, from: index, count: s.tabOrder.count))
                .accessibilityHidden(true)
            Image(systemName: TabBar.symbol(tab))
                .font(Palette.TypeScale.meta)
                .foregroundColor(.white)
                .frame(width: 16)
            Text(TabBar.name(tab)).font(.system(size: 13)).foregroundColor(.white)
            Spacer()
            Toggle(TabBar.name(tab), isOn: Binding(
                get: { enabled },
                set: { on in settings.update { $0 = settingTab($0, tab, enabled: on) } }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.switchOn)
                .disabled(isLast)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: SettingsLook.rowHeight)
        .background(drag?.tab == tab ? Palette.pill : SettingsLook.group)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up") { move(from: index, to: index - 1) }
        .accessibilityAction(named: "Move down") { move(from: index, to: index + 1) }
    }

    private func reorder(_ tab: TabID, from: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.listSpace))
            .onChanged { v in
                // Keep the dragged row within the list.
                let lo = -CGFloat(from) * Self.rowStride
                let hi = CGFloat(count - 1 - from) * Self.rowStride
                drag = (tab, min(max(v.translation.height, lo), hi))
            }
            .onEnded { v in
                drag = nil
                move(from: from, to: listDragTarget(from: from, translation: Double(v.translation.height),
                                                    stride: Double(Self.rowStride), count: count))
            }
    }

    private func move(from: Int, to: Int) {
        settings.update { $0 = movingTab($0, from: from, to: to) }
    }
}

// MARK: Alerts

private struct AlertsSection: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let s = settings.value
        // System sources (Privacy & Security, Software Update...) are never candidates (AUDIT S4).
        let apps = s.watchedApps + s.seenApps.filter { !s.watchedApps.contains($0) && !isSystemNoticeSource($0) }
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Watched apps")
            SettingsGroup {
                ForEach(apps, id: \.self) { app in
                    SwitchRow(title: app, isOn: Binding(
                        get: { settings.value.watchedApps.contains(app) },
                        set: { on in
                            settings.update { v in
                                if on {
                                    if !v.watchedApps.contains(app) { v.watchedApps.append(app) }
                                } else {
                                    v.watchedApps.removeAll { $0 == app }
                                    // Stays listed so it can be turned back on.
                                    if !v.seenApps.contains(app) { v.seenApps.append(app) }
                                }
                            }
                        }))
                }
            }
            Text("Other apps appear here after they show a notification banner.")
                .font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
        }
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Banners & devices")
            SettingsGroup {
                SwitchRow(title: "Banners for watched apps", isOn: settings.binding(\.alertBanners))
                SwitchRow(title: "Device events", subtitle: "Bluetooth, USB drives, charger",
                          isOn: settings.binding(\.deviceEvents))
                SwitchRow(title: "Banners for device events", isOn: settings.binding(\.deviceBanners))
            }
        }
    }
}

// MARK: Calendar

private struct CalendarSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var calendar: CalendarService

    var body: some View {
        let groups = Dictionary(grouping: calendar.calendars, by: \.source)
        let sources = calendar.calendars.map(\.source).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let allIDs = calendar.calendars.map(\.id)
        VStack(alignment: .leading, spacing: 6) {
            if calendar.access != .granted {
                SettingsGroup {
                    Row(title: "Allow calendar access",
                        subtitle: calendar.access == .denied
                            ? "Turn on Notchy in System Settings → Privacy & Security → Calendars."
                            : "Your calendars appear here once Notchy can read them.") {
                        SecondaryButton(calendar.access == .denied ? "Open Settings" : "Allow") {
                            if calendar.access == .denied { calendar.openPrivacySettings() } else { calendar.requestAccess() }
                        }
                    }
                }
            } else if calendar.calendars.isEmpty {
                SettingsGroup { Row(title: "No calendars found") { EmptyView() } }
            }
        }
        ForEach(sources, id: \.self) { source in
            VStack(alignment: .leading, spacing: 6) {
                GroupLabel(source)
                SettingsGroup {
                    ForEach(groups[source] ?? []) { c in
                        SwitchRow(title: c.title, isOn: Binding(
                            get: { calendarIsOn(settings.value.selectedCalendarIDs, id: c.id) },
                            set: { on in
                                settings.update {
                                    $0.selectedCalendarIDs = togglingCalendar($0.selectedCalendarIDs, all: allIDs,
                                                                              id: c.id, on: on)
                                }
                            }),
                            dot: Color(hexString: c.colorHex))
                    }
                }
            }
        }
    }
}

// MARK: Appearance

/// A 96 × 56 preview of the open panel in one theme (AUDIT G3): the surface (Glass: the live
/// frosted material under its tint), a selected-tab pill and two text lines. Name below;
/// the selected one gets an accent ring.
private struct ThemeThumbnail: View {
    let theme: Theme
    let selected: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let glass = theme == .glass
        let shape = RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous)
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if glass {
                        GlassBackground()
                    } else {
                        Color.black
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(Palette.panelPill).frame(width: 18, height: 10)
                        Capsule().fill(Color.white).frame(width: 48, height: 4)
                        Capsule().fill(Palette.panelSecondary).frame(width: 34, height: 4)
                    }
                    .padding(8)
                    .environment(\.notchGlass, glass && !reduceTransparency)
                }
                .frame(width: 96, height: 56)
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? ThemedColor(Palette.accent) : Palette.hairlineStroke,
                                            lineWidth: selected ? 2 : 1))
                Text(glass ? "Glass" : "Black")
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(selected ? ThemedColor(.white) : Palette.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(glass ? "Glass theme" : "Black theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct AppearanceSection: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let s = settings.value
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroup {
                // AUDIT G3: the picker is two previews; Reduce Transparency says what it does.
                Row(title: "Theme",
                    subtitle: reduceTransparency ? "Glass shows as black while Reduce Transparency is on" : nil) {
                    HStack(spacing: 10) {
                        ThemeThumbnail(theme: .black, selected: s.theme == .black) {
                            settings.update { $0.theme = .black }
                        }
                        ThemeThumbnail(theme: .glass, selected: s.theme == .glass) {
                            settings.update { $0.theme = .glass }
                        }
                    }
                    .padding(.vertical, 8)
                }
                Row(title: "Accent") {
                    HStack(spacing: 8) {
                        ForEach(Palette.accentChoices, id: \.hex) { choice in
                            let selected = s.accentHex.caseInsensitiveCompare(choice.hex) == .orderedSame
                            Button { settings.update { $0.accentHex = choice.hex } } label: {
                                // AUDIT S8: 18 pt swatch in a 28 pt hit area; selected = 2 pt white
                                // ring at 3 pt offset plus a 9 pt black checkmark.
                                Circle()
                                    .fill(Color(hexString: choice.hex) ?? .white)
                                    .frame(width: 18, height: 18)
                                    .overlay(Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                                        .opacity(selected ? 1 : 0))
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2)
                                        .padding(-5)
                                        .opacity(selected ? 1 : 0))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.name)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

// MARK: About

/// Identity, version, a link and the privacy / acknowledgement notes (AUDIT S1).
private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsGroup {
                HStack(spacing: 12) {
                    AppIconTile(size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notchy").font(Palette.TypeScale.body).foregroundColor(.white)
                        Text(AppInfo.versionLine).font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsLook.group)
                .accessibilityElement(children: .combine)
                Row(title: "Website", subtitle: "ujjwalkumar.co.in") {
                    if let url = URL(string: "https://www.ujjwalkumar.co.in") {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                                .foregroundColor(Palette.accent)
                        }
                        .accessibilityLabel("Open website")
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Privacy")
            SettingsGroup {
                Row(title: "Everything stays on this Mac",
                    subtitle: "Notchy reads notifications and Claude hook events locally. It never sends them anywhere.") { EmptyView() }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            GroupLabel("Acknowledgements")
            SettingsGroup {
                Row(title: "mediaremote-adapter",
                    subtitle: "Now Playing and seeking. BSD 3-Clause, Jonas van den Berg and contributors.") { EmptyView() }
            }
        }
    }
}
