import AppKit
import ApplicationServices
import Combine
import CoreBluetooth
import EventKit
import Intents
import SwiftUI
import NotchyCore

/// The first-run welcome (AUDIT R1): a normal-level, single-instance window like Settings that
/// drops from the notch (top centre of the notch screen, below the menu bar) in the open
/// panel's black style. Three steps: hover the notch, a live permissions checklist, pick your
/// tabs. Shown once on a fresh install, never over a pending approval card; reopened from
/// Settings → General → Welcome & permissions. Closing it only hides it.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let approvals: ApprovalQueue
    private weak var panel: NotchPanel?
    let permissions = PermissionStatus()
    private let flow = WelcomeFlow()
    private var waitSink: AnyCancellable?

    static let size = CGSize(width: 460, height: 460)

    init(settings: SettingsStore, approvals: ApprovalQueue, panel: NotchPanel?) {
        self.settings = settings
        self.approvals = approvals
        self.panel = panel
        super.init()
        flow.onStepShown = { [weak self] step in
            if step == .hover { self?.panel?.flashOutline() }
        }
    }

    /// Fresh install only (no saved settings). Waits for a pending approval card to go first.
    func showIfFirstRun() {
        switch welcomeLaunchAction(settings.value, approvalPending: approvals.current != nil) {
        case .skip: return
        case .show, .waitForApproval: showWhenClear(step: .hover)
        }
    }

    /// Settings → General → Welcome & permissions. Also waits out a pending approval.
    func show(step: WelcomeStep = .hover) { showWhenClear(step: step) }

    private func showWhenClear(step: WelcomeStep) {
        waitSink = nil
        guard approvals.current == nil else {
            waitSink = approvals.$current
                .filter { $0 == nil }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.present(step: step) }
                }
            notchyLog.notice("Welcome: waiting for the approval card to go")
            return
        }
        present(step: step)
    }

    private func present(step: WelcomeStep) {
        waitSink = nil
        // Shown once: marked seen as soon as it appears, so quitting midway doesn't repeat it.
        settings.update { $0.hasSeenWelcome = true }
        let w = window ?? makeWindow()
        flow.step = step
        flow.visible = true
        permissions.active = true
        if !w.isVisible { place(w) }
        permissions.refresh()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        flow.onStepShown?(step)
        notchyLog.notice("Welcome: shown at step \(step.rawValue)")
    }

    private func makeWindow() -> NSWindow {
        let w = SettingsNSWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                                 styleMask: [.titled, .closable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        w.title = "Welcome to Notchy"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.level = .normal
        w.delegate = self
        let root = WelcomeRoot(settings: settings, permissions: permissions, flow: flow,
                               close: { [weak w] in w?.performClose(nil) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        w.contentView = host
        window = w
        return w
    }

    /// Top centre under the notch on the notch screen, 12 pt below the menu bar.
    private func place(_ w: NSWindow) {
        let screen = NotchGeometry.targetScreen() ?? NSScreen.main
        guard let screen else { w.center(); return }
        let vf = screen.visibleFrame
        let midX = NotchGeometry.notchRect(for: screen).midX
        let s = w.frame.size
        let x = min(max(midX - s.width / 2, vf.minX), vf.maxX - s.width)
        w.setFrameOrigin(CGPoint(x: x.rounded(), y: (vf.maxY - s.height - 12).rounded()))
    }

    func windowDidBecomeKey(_ notification: Notification) { permissions.refresh() }

#if NOTCHY_CAPTURE
    /// Capture build: the window and a step change as Continue makes it.
    var captureWindow: NSWindow? { window }
    func captureGo(_ s: WelcomeStep) {
        flow.step = s
        if s == .permissions { permissions.refresh() }
        flow.onStepShown?(s)
    }
#endif

    func windowWillClose(_ notification: Notification) {
        permissions.stopRecheck()
        permissions.active = false
        // Drops the looping hint so nothing animates in the hidden window.
        flow.visible = false
        notchyLog.notice("Welcome: closed at step \(self.flow.step.rawValue)")
    }
}

/// The step being shown (shared between the controller and the view).
@MainActor
final class WelcomeFlow: ObservableObject {
    @Published var step: WelcomeStep = .hover
    /// False while the window is closed: the step views (and the looping hint) are removed.
    @Published var visible = false
    var onStepShown: ((WelcomeStep) -> Void)?
}

/// Live state of the permissions Notchy uses. Read on demand (window shown or key, Notchy
/// activated) and during a bounded re-check after "Allow…" (≤ 30 × 2 s, stops once granted
/// or when the window closes). Never requests or changes a permission itself: "Allow…" only
/// opens the System Settings pane.
@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var states: [Permission: PermissionState] = [:]
    /// Called when a permission's state changes (e.g. Accessibility granted → start media keys).
    var onChange: ((Permission, PermissionState) -> Void)?
    private var recheckTimer: Timer?
    private var rechecksLeft = 0
    private var waitingFor: Permission?
    private var activeObserver: NSObjectProtocol?
    /// Only while the welcome is open: Notchy becoming active re-reads the states.
    var active = false

    init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.active == true { self?.refresh() } }
        }
    }

    func state(_ p: Permission) -> PermissionState { states[p] ?? Self.read(p) }

    func refresh() {
        for p in Permission.allCases {
            let s = Self.read(p)
            guard states[p] != s else { continue }
            let first = states[p] == nil
            states[p] = s
            if !first {
                notchyLog.notice("Welcome: \(p.rawValue, privacy: .public) now \(String(describing: s), privacy: .public)")
                onChange?(p, s)
            }
        }
    }

    /// "Allow…": opens the pane, then re-reads every 2 s for up to a minute.
    func openSettings(for p: Permission) {
        if let url = URL(string: p.settingsURL) { NSWorkspace.shared.open(url) }
        waitingFor = p
        rechecksLeft = PermissionRecheck.limit
        scheduleRecheck()
    }

    func stopRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        rechecksLeft = 0
        waitingFor = nil
    }

    private func scheduleRecheck() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        guard rechecksLeft > 0, let p = waitingFor, state(p) != .granted else { stopRecheck(); return }
        rechecksLeft -= 1
        let t = Timer(timeInterval: PermissionRecheck.interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recheckTimer = nil
                self.refresh()
                self.scheduleRecheck()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        recheckTimer = t
    }

    /// Status reads only; none of these prompts.
    private static func read(_ p: Permission) -> PermissionState {
#if NOTCHY_CAPTURE
        return CaptureState.shared.permissions[p] ?? .notDetermined
#endif
        switch p {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .focus:
            switch INFocusStatusCenter.default.authorizationStatus {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }
}

// MARK: - SwiftUI

private struct WelcomeRoot: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionStatus
    @ObservedObject var flow: WelcomeFlow
    @ObservedObject var display = DisplayOptions.shared
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the traffic lights (full-size content view).
            Color.clear.frame(height: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(flow.step.rawValue + 1) of \(WelcomeStep.allCases.count)".uppercased())
                    .font(Palette.TypeScale.caption).tracking(0.5)
                    .foregroundStyle(Palette.secondaryText)
                Text(flow.step.title).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(flow.step.hint).font(Palette.TypeScale.secondary).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            Group {
                if flow.visible {
                    switch flow.step {
                    case .hover: HoverStep(reduceMotion: display.reduceMotion)
                    case .permissions: PermissionsStep(settings: settings, permissions: permissions)
                    case .tabs: TabsStep(settings: settings)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: WelcomeWindowController.size.width, height: WelcomeWindowController.size.height)
        .background(Palette.panel)
        .preferredColorScheme(.dark)
        .environment(\.notchReduceMotion, display.reduceMotion)
        .environment(\.notchIncreaseContrast, display.increaseContrast)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // Page dots: where you are in the three steps.
            HStack(spacing: 6) {
                ForEach(WelcomeStep.allCases, id: \.rawValue) { s in
                    Circle().fill(s == flow.step ? Color.white : Color(white: 0.35)).frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(flow.step.rawValue + 1) of \(WelcomeStep.allCases.count)")
            Spacer()
            if let prev = flow.step.previous {
                Button { go(prev) } label: {
                    Text("Back").font(Palette.TypeScale.body).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(Palette.pill)).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if let next = flow.step.next {
                Button { go(next) } label: { Text("Continue").whitePill() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { close() } label: { Text("Done").whitePill() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func go(_ s: WelcomeStep) {
        flow.step = s
        if s == .permissions { permissions.refresh() }
        flow.onStepShown?(s)
    }
}

/// Step 1: a looping sketch of the pointer moving onto the notch, which opens; static under
/// Reduce Motion. The real closed notch flashes its outline once when this step shows.
private struct HoverStep: View {
    let reduceMotion: Bool
    private let phaseState = State(initialValue: false)
    private var phase: Bool {
        get { phaseState.wrappedValue }
        nonmutating set { phaseState.wrappedValue = newValue }
    }

    var body: some View {
        let on = reduceMotion ? true : phase
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Palette.Radius.m, style: .continuous)
                    .fill(Color(white: 0.11))
                    .overlay(RoundedRectangle(cornerRadius: Palette.Radius.m, style: .continuous)
                        .strokeBorder(Palette.hairlineStroke, lineWidth: 1))
                // The notch: closed 54 × 12, open 150 × 44 when the pointer arrives.
                NotchShape(topCornerRadius: 0, bottomCornerRadius: on ? 12 : 5)
                    .fill(Color.black)
                    .overlay(NotchShape(topCornerRadius: 0, bottomCornerRadius: on ? 12 : 5)
                        .stroke(Palette.accent.opacity(on ? 0 : 0.9), lineWidth: 1.5))
                    .frame(width: on ? 150 : 54, height: on ? 44 : 12)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .offset(x: 18, y: on ? 30 : 92)
            }
            .frame(width: 280, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.m, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                tip("cursorarrow.rays", "Hover to open, move away to close")
                tip("command", "Or press \u{2325}\u{2318}N from anywhere")
                tip("contextualmenu.and.cursorarrow", "Right-click the notch for Settings and Quit")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.secondaryText)
                .frame(width: 20).accessibilityHidden(true)
            Text(text).font(Palette.TypeScale.secondary).foregroundColor(.white)
        }
    }
}

/// Step 2: live checklist. Granted rows show a green check; others a white `Allow…` pill that
/// opens the System Settings pane.
private struct PermissionsStep: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: PermissionStatus

    var body: some View {
        VStack(spacing: 1) {
            ForEach(welcomePermissions(settings.value), id: \.rawValue) { p in
                PermissionRow(permission: p, state: permissions.state(p)) { permissions.openSettings(for: p) }
            }
        }
        .background(Color(white: 0.17))
        .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous))
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let state: PermissionState
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous).fill(Palette.pill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title).font(Palette.TypeScale.body).foregroundColor(.white)
                Text(state == .denied ? "Off in System Settings \u{00B7} \(permission.purpose)" : permission.purpose)
                    .font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if state == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Palette.switchOn)
                    .frame(minWidth: 28, minHeight: 28)
                    .accessibilityLabel("Allowed")
            } else {
                Button(action: allow) { Text("Allow\u{2026}").whitePill() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Allow \(permission.title) in System Settings")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color(hex: 0x1F1F21))
        .accessibilityElement(children: .contain)
    }
}

/// Step 3: the four tab switches (at least one stays on) and the optional menu-bar icon.
private struct TabsStep: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let s = settings.value
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 1) {
                ForEach(s.tabOrder, id: \.self) { tab in
                    let enabled = s.enabledTabs.contains(tab)
                    toggleRow(symbol: TabBar.symbol(tab), title: TabBar.name(tab), subtitle: nil,
                              isOn: Binding(get: { enabled },
                                            set: { on in settings.update { $0 = settingTab($0, tab, enabled: on) } }),
                              disabled: enabled && s.enabledTabs.count == 1)
                }
            }
            .background(Color(white: 0.17))
            .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous))
            VStack(spacing: 1) {
                toggleRow(symbol: "menubar.rectangle", title: "Menu bar icon",
                          subtitle: "A second way into Settings",
                          isOn: Binding(get: { settings.value.menuBarIcon },
                                        set: { on in settings.update { $0.menuBarIcon = on } }),
                          disabled: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous))
        }
    }

    private func toggleRow(symbol: String, title: String, subtitle: String?, isOn: Binding<Bool>,
                           disabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(Palette.TypeScale.meta).foregroundColor(.white).frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).foregroundColor(.white)
                if let subtitle {
                    Text(subtitle).font(Palette.TypeScale.meta).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Palette.switchOn).disabled(disabled)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Color(hex: 0x1F1F21))
    }
}
