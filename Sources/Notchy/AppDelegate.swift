import AppKit
import ApplicationServices
import Combine
import NotchyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let hookPort: UInt16 = 7850
    /// How long Quit waits for `{}` replies to held requests to reach curl / Claude Code.
    static let shutdownFlush: TimeInterval = 0.5

    private var panel: NotchPanel?
    private var model: AppModel?
    private var server: HookServer?
    private let statusMenu = StatusMenu()
    private var terminating = false
    private var sigtermSource: DispatchSourceSignal?
    private var mediaKeyTap: MediaKeyTap?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var menuBarIconSink: AnyCancellable?
    /// Bounded Accessibility re-check after "Enable volume/brightness pop-up…": one-shot 2 s
    /// timers, at most `trustRecheckLimit` of them (≈1 min). Never a permanent poll.
    private var trustRecheckTimer: Timer?
    private var trustRechecksLeft = 0
    private static let trustRecheckInterval: TimeInterval = 2
    private static let trustRecheckLimit = 30
    /// When launching finished and whether it was a login-item launch (`ReopenPolicy`).
    private var launchedAt = ProcessInfo.processInfo.systemUptime
    private var launchedAsLoginItem = false

    func applicationDidFinishLaunching(_ notification: Notification) {
#if NOTCHY_CAPTURE
        // Capture build: demo data only; no hook server, Claude hooks, login item, media keys.
        captureLaunch()
        return
#endif
        launchedAt = ProcessInfo.processInfo.systemUptime
        // The launch Apple event says whether loginwindow started Notchy as a login item.
        if let e = NSAppleEventManager.shared().currentAppleEvent, e.eventID == kAEOpenApplication,
           e.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedAsLoginItem = true
        }
        notchyLog.notice("Launch: as login item \(self.launchedAsLoginItem, privacy: .public)")
        // SIGTERM (e.g. `kill`, launchd) goes through the normal quit path so held
        // requests get their `{}` reply. Ignore the default action, handle on main.
        signal(SIGTERM, SIG_IGN)
        let sig = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sig.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        sig.resume()
        sigtermSource = sig

        // Debug/testing knob: NOTCHY_HOLD_TIMEOUT=<seconds> (1...120) shortens the 120 s approval timeout.
        let timeout = ProcessInfo.processInfo.environment["NOTCHY_HOLD_TIMEOUT"]
            .flatMap(TimeInterval.init).map { min(max($0, 1), 120) } ?? 120
        let model = AppModel(approvalTimeout: timeout)
        self.model = model

        // 1. Hook server. If it can't listen, another Notchy (or something else) owns the port: quit.
        guard startServer(model: model, approvalTimeout: timeout) else {
            NSApp.terminate(nil)
            return
        }
        // 2. Claude hooks.
        // Skipped when the user turned the integration off in Settings.
        statusMenu.installResult = model.settings.value.claudeIntegration ? Lifecycle.installHooks() : nil
        // 3. Start at login.
        Lifecycle.autoEnableStartAtLogin()

        model.nowPlaying.start()

        // 5. Media keys. No prompt: without Accessibility the tap is not started and the
        // menu offers "Enable volume/brightness pop-up…"; keys stay native meanwhile.
        mediaKeyTap = MediaKeyTap { [weak model] key, fine in
            model?.handleMediaKey(key, fine: fine) ?? false
        }
        let trusted = AXIsProcessTrusted()
        notchyLog.notice("Media keys: trusted: \(trusted)")
        refreshMediaKeys()
        // Active only while the tap runs AND Accessibility is still granted: a tap created
        // before a revoke keeps its port but gets no events, so the Enable item must show.
        statusMenu.mediaKeysActive = { [weak self] in
            (self?.mediaKeyTap?.isRunning ?? false) && AXIsProcessTrusted()
        }
        statusMenu.onWillOpen = { [weak self] in self?.refreshMediaKeys() }
        statusMenu.onEnableMediaKeys = { [weak self] in self?.beginTrustRecheck() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMediaKeys() }
        }

        guard let screen = NotchGeometry.targetScreen() else { return }
        let panel = NotchPanel(notchRect: NotchGeometry.notchRect(for: screen),
                               screenFrame: screen.frame, hasHardwareNotch: NotchGeometry.hasNotch(screen), app: model)
        let settingsWindow = SettingsWindowController(settings: model.settings, calendar: model.calendar,
                                                        quiet: model.quiet, panel: panel)
        self.settingsWindow = settingsWindow
        NotchActions.onInstallResultChange = { [weak self] r in self?.statusMenu.installResult = r }
        statusMenu.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        panel.onRightClick = { [weak self] event, view in self?.statusMenu.popUp(with: event, in: view) }
        panel.orderFrontRegardless()
        self.panel = panel

        // AUDIT R1: first-run welcome (fresh install only, never over an approval card),
        // reopenable from Settings; optional menu-bar icon as a second way into Settings.
        let welcome = WelcomeWindowController(settings: model.settings, approvals: model.approvals, panel: panel)
        welcome.permissions.onChange = { [weak self] p, _ in
            if p == .accessibility { self?.refreshMediaKeys() }
        }
        self.welcomeWindow = welcome
        NotchActions.onShowWelcome = { [weak welcome] in welcome?.show() }
        menuBarIconSink = model.settings.$value.map(\.menuBarIcon).removeDuplicates()
            .sink { [weak self] on in
                MainActor.assumeIsolated { self?.statusMenu.setMenuBarIcon(on) }
            }
        welcome.showIfFirstRun()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
    }

    /// Opening Notchy again (Finder, Spotlight, Launchpad) while it runs opens Settings: with
    /// the menu-bar icon off this is the way in that needs no right-click (AUDIT R1). A reopen
    /// right after launch (login) is ignored (`ReopenPolicy`).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let since = ProcessInfo.processInfo.systemUptime - launchedAt
        guard ReopenPolicy.opensSettings(sinceLaunch: since, launchedAsLoginItem: launchedAsLoginItem) else {
            notchyLog.notice("Reopen ignored: \(Int(since), privacy: .public) s after launch")
            return false
        }
        settingsWindow?.show()
        return false
    }

    /// Covers Quit, logout, restart and shutdown.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        trustRecheckTimer?.invalidate()
        trustRecheckTimer = nil
        mediaKeyTap?.stop()
        model?.nowPlaying.stop()
        let hadPending = model?.beginShutdown() ?? false
        guard hadPending else {
            server?.stop()
            return .terminateNow
        }
        // The `{}` replies are sent on the server queue; give them a moment to flush.
        // .common includes the modal-panel mode AppKit runs in while termination is pending.
        let timer = Timer(timeInterval: Self.shutdownFlush, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.server?.stop()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return .terminateLater
    }

    /// Returns false if the listener could not start (the reason is logged).
    private func startServer(model: AppModel, approvalTimeout: TimeInterval) -> Bool {
        // The server's own hold timeout is a backstop; the app answers `{}` at approvalTimeout.
        let server = HookServer(port: Self.hookPort, holdTimeout: approvalTimeout + 40)
        // Callbacks run on the server queue. DispatchQueue.main keeps them in arrival order.
        server.onEvent = { [weak model] e in
            DispatchQueue.main.async { MainActor.assumeIsolated { model?.handle(e) } }
        }
        server.onPermission = { [weak model] e, reply in
            // Off the main actor: tool inputs can be ~1 MB.
            let summary = toolSummary(toolName: e.toolName ?? "Tool", input: e.toolInput)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let model else { reply(.none); return }
                    model.handlePermission(e, summary: summary, reply: reply)
                }
            }
        }
        server.onPermissionCancelled = { [weak model] e in
            let summary = toolSummary(toolName: e.toolName ?? "Tool", input: e.toolInput)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { model?.handlePermissionCancelled(e, summary: summary) }
            }
        }
        do {
            try server.start()
            notchyLog.notice("Hook server listening on 127.0.0.1:\(Self.hookPort)")
        } catch {
            // NWListener may surface EADDRINUSE as a start timeout rather than .portInUse,
            // so any failure here is treated as "another Notchy or port busy".
            notchyLog.error("Hook server failed to start on port \(Self.hookPort): \(String(describing: error), privacy: .public); quitting")
            return false
        }
        self.server = server
        return true
    }

    /// Matches the tap to the current Accessibility state. Trusted and not running → start.
    /// Running but no longer trusted (revoked while running) → stop, so a later grant builds
    /// a fresh tap (the old one stays dead after a revoke). Keys pass through meanwhile:
    /// handleMediaKey checks AXIsProcessTrusted per key.
    private func refreshMediaKeys() {
        guard !terminating, let tap = mediaKeyTap else { return }
        let trusted = AXIsProcessTrusted()
        if tap.isRunning {
            if !trusted {
                notchyLog.notice("Media keys: Accessibility revoked; stopping tap")
                tap.stop()
            }
            return
        }
        guard trusted else { return }
        if tap.start() {
            trustRecheckTimer?.invalidate()
            trustRecheckTimer = nil
            trustRechecksLeft = 0
        }
    }

    private func beginTrustRecheck() {
        trustRechecksLeft = Self.trustRecheckLimit
        scheduleTrustRecheck()
    }

    private func scheduleTrustRecheck() {
        trustRecheckTimer?.invalidate()
        trustRecheckTimer = nil
        guard trustRechecksLeft > 0, mediaKeyTap?.isRunning == false else { return }
        trustRechecksLeft -= 1
        let timer = Timer(timeInterval: Self.trustRecheckInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.trustRecheckTimer = nil
                self.refreshMediaKeys()
                self.scheduleTrustRecheck()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustRecheckTimer = timer
    }

    private func screenChanged() {
        guard let screen = NotchGeometry.targetScreen(), let panel else { return }
        panel.reposition(notchRect: NotchGeometry.notchRect(for: screen), screenFrame: screen.frame,
                         hasHardwareNotch: NotchGeometry.hasNotch(screen))
    }
}

#if NOTCHY_CAPTURE
extension AppDelegate {
    /// The capture build's launch: the same panel, Settings, welcome and menu as a normal
    /// launch, without any real input, then hands over to the demo harness.
    fileprivate func captureLaunch() {
        let model = AppModel(approvalTimeout: 120)
        self.model = model
        guard let screen = NotchGeometry.targetScreen() else { NSApp.terminate(nil); return }
        let panel = NotchPanel(notchRect: NotchGeometry.notchRect(for: screen),
                               screenFrame: screen.frame, hasHardwareNotch: NotchGeometry.hasNotch(screen), app: model)
        let settingsWindow = SettingsWindowController(settings: model.settings, calendar: model.calendar,
                                                        quiet: model.quiet, panel: panel)
        self.settingsWindow = settingsWindow
        statusMenu.installResult = .alreadyInstalled
        statusMenu.mediaKeysActive = { true }
        statusMenu.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        panel.onRightClick = { [weak self] event, view in self?.statusMenu.popUp(with: event, in: view) }
        panel.orderFrontRegardless()
        self.panel = panel
        let welcome = WelcomeWindowController(settings: model.settings, approvals: model.approvals, panel: panel)
        self.welcomeWindow = welcome
        NotchActions.onShowWelcome = { [weak welcome] in welcome?.show() }
        menuBarIconSink = model.settings.$value.map(\.menuBarIcon).removeDuplicates()
            .sink { [weak self] on in
                MainActor.assumeIsolated { self?.statusMenu.setMenuBarIcon(on) }
            }
        CaptureHarness.start(CaptureContext(app: model, panel: panel, settings: settingsWindow,
                                            welcome: welcome, statusMenu: statusMenu, screen: screen))
    }
}
#endif
