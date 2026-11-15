import AppKit
import ApplicationServices
import Combine
import NotchyCore

/// Glue between the hook server and the UI. All state lives on the main actor.
@MainActor
final class AppModel: ObservableObject {
    @Published var store = SessionStore()
    /// Volume/brightness pop-up state, set by media keys Notchy handles.
    @Published var hud = HUDState()
    let approvals = ApprovalQueue()
    let nowPlaying = NowPlayingService()
    let settings = SettingsStore()
    /// Bluetooth / drives / USB / power watcher; runs only while device events are on.
    let devices = DeviceMonitor()
    /// Outlook/Teams (watched apps) Notification Center banners, via Accessibility.
    let notificationWatcher = NotificationWatcher()
    /// Unread counts from Dock badges of watched apps.
    let dockBadges = DockBadges()
    /// Calendar tab events + meeting reminder (EventKit; memory only).
    let calendar = CalendarService()
    /// Calls (mic/camera), front app full screen, Focus — for the quiet rules.
    let quiet = QuietMonitor()
    /// Times Claude sessions' working stretches for the "finished" banner.
    private var workTimer = WorkTimer()
    /// Alerts list (memory only: max 50, nothing older than 24 h).
    @Published private(set) var alerts = AlertStore()
    /// Watched app → Dock badge count (apps without a badge are absent).
    @Published private(set) var dockCounts: [String: Int] = [:]
    /// Accessibility granted (re-read when the Alerts tab opens / Notchy becomes active).
    @Published private(set) var axTrusted = AXIsProcessTrusted()
    /// The tab the user picked last (see `currentTab` for the one actually shown).
    @Published var selectedTab: TabID
    /// How long a request may wait before it is answered with `{}` (default 120 s).
    let approvalTimeout: TimeInterval

    /// Mirror of the queue's entries (oldest first), so we can match by session/tool/summary
    /// and publish `pendingCount` changes (the queue only publishes `current`).
    @Published private(set) var pending: [ApprovalRequest] = []

    /// Recently ended session ids (SessionEnd), oldest first, capped.
    private var endedSessions: [String] = []
    private static let endedCap = 256

    private var expiryTimer: Timer?
    /// Light timer that prunes stale idle/done sessions when no events arrive.
    private var pruneTimer: Timer?
    /// Set once quitting starts; new permission requests are then answered `{}` at once.
    private(set) var isShuttingDown = false
    private var approvalsSink: AnyCancellable?
    private var nowPlayingSink: AnyCancellable?
    private var settingsSink: AnyCancellable?
    private var devicesSink: AnyCancellable?
    private var alertsSink: AnyCancellable?
    private var calendarSink: AnyCancellable?
    private var quietSink: AnyCancellable?
    private var quietGateSink: AnyCancellable?
    private var activeObserver: NSObjectProtocol?

    init(approvalTimeout: TimeInterval = 120) {
        self.approvalTimeout = approvalTimeout
        selectedTab = openingTab(settings.value)
        approvalsSink = approvals.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        nowPlayingSink = nowPlaying.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        quietSink = quiet.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Each quiet watcher runs only while a switch that needs it is on (live on toggle).
        quietGateSink = settings.$value
            .map { QuietGate(calls: $0.quietWhilePresenting,
                             fullScreen: $0.quietWhilePresenting || $0.hideInFullScreen,
                             focus: $0.respectFocus) }
            .removeDuplicates()
            .sink { [weak self] g in
                MainActor.assumeIsolated {
                    guard let self, !self.isShuttingDown else { return }
                    self.quiet.apply(calls: g.calls, fullScreen: g.fullScreen, focus: g.focus)
                }
            }
        devices.onEvent = { [weak self] e, eject in self?.onDeviceEvent(e, eject: eject) }
        // Device events need the switch on and the Alerts tab enabled; off stops all observers.
        devicesSink = settings.$value
            .map { $0.deviceEvents && $0.enabledTabs.contains(.alerts) }
            .removeDuplicates()
            .sink { [weak self] on in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if on { self.devices.start() } else { self.devices.stop() }
                }
            }
        notificationWatcher.knownApps = { [weak self] in
            guard let s = self?.settings.value else { return [] }
            return s.watchedApps + s.seenApps
        }
        notificationWatcher.onBanner = { [weak self] seen in self?.onNotificationBanner(seen) }
        dockBadges.watchedApps = { [weak self] in self?.settings.value.watchedApps ?? [] }
        dockBadges.onChange = { [weak self] counts in self?.dockCounts = counts }
        // Alerts observation needs the Alerts tab on, at least one watched app and Accessibility.
        alertsSink = settings.$value
            .map { AlertsGate(on: $0.enabledTabs.contains(.alerts) && !$0.watchedApps.isEmpty,
                              watched: $0.watchedApps) }
            .removeDuplicates()
            .sink { [weak self] gate in
                MainActor.assumeIsolated { self?.updateAlertWatchers(gate.on, watchedChanged: true) }
            }
        calendar.onReminder = { [weak self] m in self?.offerMeetingReminder(m) }
        // Calendar reads run while the Calendar tab is on or the meeting reminder is on.
        calendarSink = settings.$value
            .map { CalendarGate(active: $0.enabledTabs.contains(.calendar) || $0.meetingReminder,
                                selected: $0.selectedCalendarIDs, reminder: $0.meetingReminder) }
            .removeDuplicates()
            .sink { [weak self] g in
                MainActor.assumeIsolated {
                    guard let self, !self.isShuttingDown else { return }
                    self.calendar.apply(active: g.active, selectedIDs: g.selected, reminderOn: g.reminder)
                }
            }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
        let prune = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pruneSessions(now: Date())
                self?.pruneAlerts(now: Date())
            }
        }
        prune.tolerance = 10
        RunLoop.main.add(prune, forMode: .common)
        pruneTimer = prune
    }

    var sessions: [SessionInfo] { store.sessions }

    // MARK: - Tabs

    /// Tabs shown in the bar, in the user's order.
    var visibleTabList: [TabID] { visibleTabs(settings.value) }

    /// The tab shown: the selected one if still visible, else the first enabled one.
    var currentTab: TabID {
        visibleTabList.contains(selectedTab) ? selectedTab : openingTab(settings.value)
    }

    func selectTab(_ tab: TabID) {
        if selectedTab != tab { selectedTab = tab }
        settings.update { $0.lastTab = tab }
    }

    /// Drag-reorder in the tab bar: `tab` takes the place of the visible tab at `index`.
    func moveTab(_ tab: TabID, toVisibleIndex index: Int) {
        settings.update { $0 = movingVisibleTab($0, tab, toVisibleIndex: index) }
    }

    // MARK: - Banners

    /// Set by the notch panel, which owns the `BannerArbiter` (it knows open / pop-up state).
    var bannerHandler: ((Banner, (@MainActor () -> Void)?) -> (decision: BannerDecision, ctx: BannerContext)?)?

    private struct QuietGate: Equatable {
        let calls: Bool
        let fullScreen: Bool
        let focus: Bool
    }

    /// What the quiet rules see right now.
    var quietInputs: QuietInputs {
        QuietInputs(inCall: quiet.inCall, fullScreenFront: quiet.fullScreenFront,
                    mediaPlaying: nowPlaying.state.info?.isPlaying == true, focusOn: quiet.focusOn)
    }

    /// Called when a banner is offered: re-reads Focus (apps get no Focus change notification),
    /// then returns whether the quiet rules (presenting / Focus / full screen) drop banners.
    func evaluateQuiet() -> Bool {
        quiet.refreshFocus()
        let q = bannersQuiet(settings.value, quietInputs)
        if q { notchyLog.notice("Quiet: banner dropped (call \(self.quiet.inCall), full screen \(self.quiet.fullScreenFront), focus \(self.quiet.focusOn == true))") }
        return q
    }

    /// The Alerts tab shows a moon while a Focus is on (and "Respect Focus" is on).
    var focusMoon: Bool { settings.value.respectFocus && quiet.focusOn == true }

    /// The panel opened: Focus may have changed since the last read.
    func panelOpened() {
        quiet.refreshFocus()
    }

    /// Producers call this; `action` runs when the banner's action pill is clicked.
    @discardableResult
    func offerBanner(_ banner: Banner, action: (@MainActor () -> Void)? = nil)
        -> (decision: BannerDecision, ctx: BannerContext)? {
        bannerHandler?(banner, action) ?? nil
    }

    // MARK: - Device events

    /// Every device event lands here: recorded in the Alerts list, plus a banner when on.
    /// `eject` is the Eject pill's action for mounted drives.
    func onDeviceEvent(_ e: DeviceEvent, eject: (@MainActor () -> Void)? = nil) {
        let s = settings.value
        guard s.deviceEvents, s.enabledTabs.contains(.alerts) else { return }
        let now = Date()
        alerts.add(alertItemFor(e, now: now), now: now)
        if s.deviceBanners { offerBanner(bannerFor(e, now: now), action: eject) }
    }

    // MARK: - Alerts (Outlook / Teams)

    private struct AlertsGate: Equatable {
        let on: Bool
        let watched: [String]
    }

    /// A banner read from Notification Center. Watched app → Alerts row (+ banner); any other
    /// app → only its name is noted in `seenApps` (its text is dropped here).
    private func onNotificationBanner(_ seen: NotificationWatcher.Seen) {
        let s = settings.value
        guard s.enabledTabs.contains(.alerts) else { return }
        let p = seen.parsed
        switch routeBanner(p, watched: s.watchedApps, seen: s.seenApps) {
        case .drop:
            return // unconfirmed or already-seen app: nothing kept, the name is not logged
        case .seen(let next):
            notchyLog.notice("Alerts: new app seen: \(next.last ?? "", privacy: .public)")
            settings.update { $0.seenApps = next }
        case .watched(let app):
            let now = Date()
            let key = seen.notificationID ?? UUID().uuidString
            let id = "nc:\(key)"
            let item = AlertItem(id: id, app: app, title: p.title, body: p.body, at: now, device: false)
            // Re-reads of a banner first seen without its body fill the body in; an id already
            // offered (even if its row was since evicted past the cap) is never re-added.
            switch alerts.admitNotification(item, now: now) {
            case .upgraded:
                notchyLog.notice("Alerts: banner from \(app, privacy: .public) body filled in")
                return
            case .ignored:
                return
            case .duplicate, .added:
                break
            }
            let added = alerts.contains(id: id)
            AppIcons.prewarm(app) // views read only the cache
            notchyLog.notice("Alerts: banner from \(app, privacy: .public) (new: \(added)); \(self.alerts.items.count) items")
            dockBadges.scheduleRead(after: 1)
            guard added, s.alertBanners else { return }
            offerBanner(Banner(id: "alert:\(key)", kind: .alert(app: app), title: p.title,
                               subtitle: p.body, tab: .alerts))
        }
    }

    func clearAlerts() {
        alerts.clear()
        // Banners still on screen must not be re-added by a later layout walk.
        notificationWatcher.markOnScreenReported()
    }

    /// Opens the app an Alerts row came from (device rows do nothing).
    func openAlertApp(_ item: AlertItem) {
        guard !item.device else { return }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName.map { matchApp($0, in: [item.app]) != nil } ?? false
        }), let url = running.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let ids = ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams"]
        var candidates = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .filter { matchApp($0.deletingPathExtension().lastPathComponent, in: [item.app]) != nil }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"] {
            candidates.append(URL(fileURLWithPath: dir).appendingPathComponent(item.app + ".app"))
        }
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The Alerts tab became visible: re-check Accessibility, drop old rows, re-read badges.
    func alertsTabOpened() {
        refreshAccessibility()
        pruneAlerts(now: Date())
        dockBadges.refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshAccessibility() {
#if NOTCHY_CAPTURE
        return
#endif
        let t = AXIsProcessTrusted()
        guard t != axTrusted else { return }
        axTrusted = t
        notchyLog.notice("Alerts: Accessibility trusted: \(t)")
        let s = settings.value
        updateAlertWatchers(s.enabledTabs.contains(.alerts) && !s.watchedApps.isEmpty, watchedChanged: false)
    }

    private func updateAlertWatchers(_ on: Bool, watchedChanged: Bool) {
        if on && axTrusted && !isShuttingDown {
            notificationWatcher.start()
            dockBadges.start()
            if watchedChanged { dockBadges.refresh() }
        } else {
            notificationWatcher.stop()
            dockBadges.stop()
        }
    }

    private func pruneAlerts(now: Date) {
        guard let oldest = alerts.items.last, now.timeIntervalSince(oldest.at) > AlertStore.maxAge else { return }
        alerts.prune(now: now)
    }

    // MARK: - Calendar

    private struct CalendarGate: Equatable {
        let active: Bool
        let selected: [String]?
        let reminder: Bool
    }

    /// The one meeting reminder held back by the open panel (another tab) or a pending approval.
    private var deferredReminder = DeferredReminder()

    /// 1-minute reminder banner; its Join pill opens the link (the panel stays closed).
    /// Blocked by the open panel on another tab or an approval → held and re-offered when the
    /// panel closes (only if the meeting hasn't started). Open on Calendar counts as shown.
    private func offerMeetingReminder(_ m: MeetingInfo) {
        guard settings.value.meetingReminder, let url = m.joinURL, !isShuttingDown else { return }
        let service = meetingService(url, calendarTitle: m.calendarTitle)
        let result = offerBanner(Banner(id: "meeting:\(m.id)", kind: .meeting, title: m.title,
                                        subtitle: service.isEmpty ? "Starts in 1 min" : "Starts in 1 min · \(service)",
                                        actionLabel: "Join", tab: .calendar, service: service),
                                 action: { NSWorkspace.shared.open(url) })
        guard let result else { return }
        let outcome = reminderOfferOutcome(result.decision, ctx: result.ctx,
                                           openTab: result.ctx.panelOpen ? currentTab : nil)
        if outcome == .deferred {
            deferredReminder.hold(m)
            notchyLog.notice("Calendar: meeting reminder held until the panel closes")
        }
    }

    /// The panel closed (no approval pending): re-offer a held meeting reminder.
    func bannerSlotFreed() {
        guard let m = deferredReminder.take(now: Date()) else { return }
        offerMeetingReminder(m)
    }

    // MARK: - Hook events

    func handle(_ e: HookEvent) {
        let now = Date()
        defer {
            trackWork(e, now: now)
            pruneSessions(now: now)
        }
        switch e.eventName {
        case "SessionEnd":
            store.apply(e, now: now)
            noteEnded(e.sessionId)
            approvals.dropSession(e.sessionId)
        case "PostToolUse":
            chime(store.apply(e, now: now))
            // The user answered in the terminal: the tool ran, so its card is stale.
            if let tool = e.toolName,
               let r = pending.first(where: { $0.sessionId == e.sessionId && $0.toolName == tool }) {
                approvals.resolve(r.id, .none)
            }
        case "Stop", "UserPromptSubmit":
            chime(store.apply(e, now: now))
            // Claude moved on (turn ended / new prompt): any card for this session is stale.
            approvals.dropSession(e.sessionId)
        default:
            if e.eventName == "SessionStart" { endedSessions.removeAll { $0 == e.sessionId } }
            chime(store.apply(e, now: now))
        }
    }

    /// `summary` should be computed off the main actor (tool inputs can be ~1 MB).
    func handlePermission(_ e: HookEvent, summary: String? = nil,
                          reply: @escaping @Sendable (PermissionDecision) -> Void) {
        if isShuttingDown { reply(.none); return }
        let known = store.sessions.contains { $0.id == e.sessionId }
        if !known && endedSessions.contains(e.sessionId) {
            reply(.none)
            return
        }
        let now = Date()
        chime(store.apply(e, now: now))
        trackWork(e, now: now)
        let tool = e.toolName ?? "Tool"
        let label = store.sessions.first(where: { $0.id == e.sessionId })?.label
            ?? (e.cwd as NSString).lastPathComponent
        let request = ApprovalRequest(id: UUID(), sessionId: e.sessionId, label: label, toolName: tool,
                                      summary: summary ?? toolSummary(toolName: tool, input: e.toolInput),
                                      receivedAt: now)
        pending.append(request)
        updateExpiryTimer()
        approvals.enqueue(request) { [weak self] decision in
            reply(decision)
            // ApprovalQueue is @MainActor, so this normally runs on main already.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.requestLeft(request) }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.requestLeft(request) } }
            }
        }
    }

    /// The held connection closed or timed out before we replied.
    func handlePermissionCancelled(_ e: HookEvent, summary: String) {
        if isShuttingDown { return }
        let tool = e.toolName ?? "Tool"
        guard let r = pending.first(where: {
            $0.sessionId == e.sessionId && $0.toolName == tool && $0.summary == summary
        }) else { return }
        approvals.resolve(r.id, .none)
    }

    /// Labels of the other queued requests' sessions (oldest first, unique), excluding `current`'s.
    func otherWaitingLabels(excluding current: ApprovalRequest) -> [String] {
        var seen: Set<String> = [current.label]
        return pending.compactMap { r in
            r.id == current.id || !seen.insert(r.label).inserted ? nil : r.label
        }
    }

    /// User clicked Allow/Deny/Dismiss on the card.
    func decide(_ id: UUID, _ decision: PermissionDecision) {
        approvals.resolve(id, decision)
    }

    /// Answers every held request with `{}` and refuses new ones.
    /// Returns true if any request was waiting (its reply still has to flush).
    @discardableResult
    func beginShutdown() -> Bool {
        isShuttingDown = true
        devices.stop()
        notificationWatcher.stop()
        dockBadges.stop()
        calendar.stop()
        quiet.stop()
        expiryTimer?.invalidate()
        expiryTimer = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
        let hadPending = approvals.pendingCount > 0
        approvals.resolveAllForShutdown()
        return hadPending
    }

    // MARK: - Media keys

    /// MediaKeyTap handler (key-downs, incl. auto-repeat). Returns true to consume the key.
    /// Anything Notchy can't do (not settable, no brightness, untrusted, write failed)
    /// returns false so macOS handles the key natively.
    func handleMediaKey(_ key: MediaKey, fine: Bool) -> Bool {
        guard shouldConsume(key, volumeSettable: VolumeControl.isSettable(),
                            brightnessAvailable: BrightnessControl.isAvailable,
                            trusted: AXIsProcessTrusted()) else { return false }
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard let cur = VolumeControl.current() else { return false }
            let next = applyVolumeKey(key, to: cur, fine: fine)
            guard VolumeControl.set(next) else { return false }
            hud.show(.volume, level: next.level, muted: next.muted, now: Date())
        case .brightnessUp, .brightnessDown:
            guard let cur = BrightnessControl.current() else { return false }
            let next = applyBrightnessKey(key, to: cur, fine: fine)
            guard BrightnessControl.set(next) else { return false }
            hud.show(.brightness, level: next, muted: false, now: Date())
        }
        return true
    }

    // MARK: - Private

    /// Feeds the session's phase after an event to the work timer; working → done for at
    /// least a minute offers the "<label> finished" banner (Claude tab).
    private func trackWork(_ e: HookEvent, now: Date) {
        guard let info = store.sessions.first(where: { $0.id == e.sessionId }) else {
            workTimer.forget(sessionId: e.sessionId)
            return
        }
        let worked = workTimer.phaseChanged(sessionId: info.id, to: info.phase, now: now)
        guard let worked else { return }
        notchyLog.notice("Claude: session finished after \(Int(worked)) s")
        guard !isShuttingDown,
              let b = claudeFinishedBanner(sessionId: info.id, label: info.label, worked: worked,
                                           enabled: settings.value.claudeFinishedBanner, now: now) else { return }
        offerBanner(b)
    }

    private func requestLeft(_ r: ApprovalRequest) {
        pending.removeAll { $0.id == r.id }
        updateExpiryTimer()
        if !pending.contains(where: { $0.sessionId == r.sessionId }) {
            store.markApprovalResolved(sessionId: r.sessionId, now: Date())
        }
    }

    /// Drops idle/done sessions older than 45 min (never ones with a queued approval).
    private func pruneSessions(now: Date) {
        var copy = store
        guard copy.prune(now: now, pendingSessionIds: Set(pending.map(\.sessionId))) > 0 else { return }
        store = copy
        workTimer.retain(sessionIds: Set(copy.sessions.map(\.id)))
    }

    /// The 1 s expiry timer runs only while an approval is pending.
    private func updateExpiryTimer() {
        if pending.isEmpty || isShuttingDown {
            expiryTimer?.invalidate()
            expiryTimer = nil
        } else if expiryTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.expireStale() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
        }
    }

    private func expireStale() {
        approvals.expire(now: Date(), timeout: approvalTimeout)
    }

    private func noteEnded(_ id: String) {
        endedSessions.removeAll { $0 == id }
        endedSessions.append(id)
        if endedSessions.count > Self.endedCap { endedSessions.removeFirst(endedSessions.count - Self.endedCap) }
    }

    private func chime(_ t: SessionTransition?) {
#if NOTCHY_CAPTURE
        return
#endif
        switch t {
        case .becameWaiting?: NSSound(named: "Glass")?.play()
        case .finished?: NSSound(named: "Tink")?.play()
        case nil: break
        }
    }
}

#if NOTCHY_CAPTURE
/// Capture build only: demo data in, through the same paths the real producers use.
extension AppModel {
    func captureAddAlert(_ item: AlertItem) { alerts.add(item, now: Date()) }
    func captureClearAlerts() { alerts.clear() }
    func captureSetDockCounts(_ c: [String: Int]) { dockCounts = c }
    func captureSetAXTrusted(_ t: Bool) { axTrusted = t }
    func captureMeetingReminder(_ m: MeetingInfo) { offerMeetingReminder(m) }
}
#endif
