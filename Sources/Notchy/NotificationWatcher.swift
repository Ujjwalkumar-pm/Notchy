import AppKit
import ApplicationServices
import NotchyCore

/// Shared AX setup: a short messaging timeout for every element (the default is ~6 s, which
/// would stall the main thread if Notification Center or the Dock hangs).
enum AXTimeouts {
    static let seconds: Float = 0.25

    @MainActor static func applyGlobal() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }
}

/// Reads new Notification Center banners through Accessibility (event-driven, no polling).
///
/// Observes `AXWindowCreated` + `AXCreated` on the Notification Center process
/// (`com.apple.notificationcenterui`; its localized name differs per language, so it is found
/// by bundle id). Each notification queues its element; a coalesced one-shot 0.3 s later (the
/// banner's texts are filled in after creation) the windows of the queued elements are walked
/// once each, with one shared node budget. Verified 15 Nov (macOS 27.2): banner = `AXGroup`,
/// subrole `AXNotificationCenterBanner`, AXDescription "<App>, <title>, <body>", identifier =
/// the notification's UUID, child `AXStaticText`s identified `title` and `body`.
/// Which groups count as new banners is decided by `bannerGroupsToReport` (NotchyCore).
///
/// Banner text is handed to `onBanner` and never logged.
@MainActor
final class NotificationWatcher {
    struct Seen {
        let notificationID: String?
        let parsed: ParsedBanner
    }

    /// Called per new banner (an id is re-reported until its body text has been read).
    var onBanner: ((Seen) -> Void)?
    /// App names the parser should recognise (watched + seen apps).
    var knownApps: () -> [String] = { [] }

    private(set) var isRunning = false
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var pid: pid_t = 0
    /// Queued elements; `layout`: from AXLayoutChanged (only banner windows are walked).
    private var queued: [(element: AXUIElement, layout: Bool)] = []
    private var flushScheduled = false
    /// Notification ids fully reported (body read), newest last, capped. Ids only, no text.
    private var reportedIDs: [String] = []
    /// Banners without an id: hashes of app + title + body already reported (no text kept).
    private var reportedKeys: [Int] = []
    /// Set by an AX read that timed out / could not complete: the flush stops at once.
    private var aborted = false
    /// Diagnostics (debug log only): flushes, flushes that walked something, nodes visited.
    private var flushCount = 0
    private var walkedFlushes = 0
    private var nodesVisited = 0
    private var launchObserver: NSObjectProtocol?

    nonisolated static let bundleID = "com.apple.notificationcenterui"
    /// Created = a new banner window / group. LayoutChanged = a newer banner replacing the one
    /// on screen (verified 15 Nov: no AXCreated fires for it, only AXLayoutChanged).
    private static let observed = [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification]
    private static let maxQueued = 20
    private static let maxDepth = 9
    /// Shared by every walk in one flush.
    private static let maxNodes = 400

    func start() {
#if NOTCHY_CAPTURE
        return
#endif
        guard !isRunning else { return }
        isRunning = true
        AXTimeouts.applyGlobal()
        // Re-attach if Notification Center restarts (new pid).
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bid == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        detach()
        queued.removeAll()
    }

    private func attach() {
        detach()
        guard isRunning, AXIsProcessTrusted(),
              let nc = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else {
            notchyLog.notice("Alerts: Notification Center not observed (untrusted or not running)")
            return
        }
        let pid = nc.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, note, refcon in
            guard let refcon else { return }
            let me = Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue()
            let layout = CFEqual(note, kAXLayoutChangedNotification as CFString)
            MainActor.assumeIsolated { me.enqueue(element, layout: layout) }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else {
            notchyLog.error("Alerts: AXObserverCreate failed for Notification Center")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXTimeouts.seconds)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var ok = 0
        for n in Self.observed {
            if AXObserverAddNotification(obs, app, n as CFString, refcon) == .success { ok += 1 }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        appElement = app
        self.pid = pid
        notchyLog.notice("Alerts: observing Notification Center (\(ok)/\(Self.observed.count) notifications registered)")
    }

    private func detach() {
        if let observer {
            if let appElement {
                for n in Self.observed {
                    AXObserverRemoveNotification(observer, appElement, n as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        appElement = nil
        pid = 0
    }

    private func enqueue(_ element: AXUIElement, layout: Bool) {
        guard isRunning else { return }
        if queued.count < Self.maxQueued { queued.append((element, layout)) }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        let entries = queued
        queued.removeAll()
        guard isRunning else { return }
        flushCount += 1
        aborted = false
        var budget = Self.maxNodes
        let roots = rootsToWalk(entries, budget: &budget)
        guard !aborted else { return logAbort() }
        if !roots.isEmpty { walkedFlushes += 1 }
        let before = budget
        var found: [(element: AXUIElement, info: BannerGroupInfo)] = []
        for r in roots where budget > 0 {
            guard let groups = walkNotificationGroups(r, budget: &budget, maxDepth: Self.maxDepth, read: readNode)
            else { return logAbort() }
            found += groups
        }
        nodesVisited += before - budget
        notchyLog.debug("Alerts: flush \(self.flushCount), walked \(self.walkedFlushes), nodes \(before - budget) (total \(self.nodesVisited))")
        guard !found.isEmpty else { return }
        let picks = bannerGroupsToReport(found.map(\.info), reported: Set(reportedIDs))
        if found.count > 1 || picks.count != found.count {
            notchyLog.notice("Alerts: \(found.count) notification groups, \(picks.count) new")
        }
        for i in picks {
            report(found[i].element, id: found[i].info.id)
            if aborted { return logAbort() }
        }
    }

    private func logAbort() {
        notchyLog.notice("Alerts: Accessibility timed out reading Notification Center; flush skipped")
    }

    /// Distinct windows to walk. Created events: the element's window (or the app's windows).
    /// Layout events: only banner-hosting windows (subrole `AXSystemDialog`, as observed for the
    /// banner window) — desktop widget windows are never walked for layout changes.
    private func rootsToWalk(_ entries: [(element: AXUIElement, layout: Bool)], budget: inout Int) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        for (e, layout) in entries {
            if aborted { return [] }
            var candidates: [AXUIElement]
            if string(e, kAXRoleAttribute) == (kAXApplicationRole as String) {
                candidates = windows(of: e)
            } else {
                candidates = [window(of: e, budget: &budget) ?? e]
            }
            if layout { candidates = candidates.filter(isBannerWindow) }
            for root in candidates where !roots.contains(where: { CFEqual($0, root) }) { roots.append(root) }
        }
        // Banner windows first.
        let dialogs = roots.filter(isBannerWindow)
        return dialogs + roots.filter { r in !dialogs.contains { CFEqual($0, r) } }
    }

    private func isBannerWindow(_ w: AXUIElement) -> Bool {
        string(w, kAXSubroleAttribute) == "AXSystemDialog"
    }

    /// Reads (role, subrole, identifier, children); nil when an AX call timed out.
    private func readNode(_ e: AXUIElement) -> (node: WalkNode, children: [AXUIElement])? {
        let role = string(e, kAXRoleAttribute) ?? ""
        let subrole = string(e, kAXSubroleAttribute)
        let ident = string(e, kAXIdentifierAttribute)
        let kids = children(e)
        return aborted ? nil : (WalkNode(role: role, subrole: subrole, identifier: ident), kids)
    }

    private func report(_ group: AXUIElement, id: String?) {
        guard let parsed = parse(group) else { return }
        if let id {
            // Only once the body is in: a title-only read is reported again (and upgraded) later.
            if !parsed.body.isEmpty { remember(id: id) }
        } else {
            let key = Self.key(parsed)
            if reportedKeys.contains(key) { return }
            if !parsed.body.isEmpty { remember(key: key) }
        }
        onBanner?(Seen(notificationID: id, parsed: parsed))
    }

    private func parse(_ group: AXUIElement) -> ParsedBanner? {
        let desc = string(group, kAXDescriptionAttribute)
        var title: String?, body: String?, others: [String] = []
        for c in children(group) where string(c, kAXRoleAttribute) == (kAXStaticTextRole as String) {
            guard let v = string(c, kAXValueAttribute) ?? string(c, kAXDescriptionAttribute) else { continue }
            switch string(c, kAXIdentifierAttribute) {
            case "title": title = v
            case "body": body = v
            default: others.append(v)
            }
        }
        if aborted { return nil }
        return parseBannerGroup(description: desc, title: title, body: body, others: others, knownApps: knownApps())
    }

    private static func key(_ p: ParsedBanner) -> Int {
        var h = Hasher()
        h.combine(p.app)
        h.combine(p.title)
        h.combine(p.body)
        return h.finalize()
    }

    private func remember(id: String) {
        guard !reportedIDs.contains(id) else { return }
        reportedIDs.append(id)
        if reportedIDs.count > 100 { reportedIDs.removeFirst(reportedIDs.count - 100) }
    }

    private func remember(key: Int) {
        guard !reportedKeys.contains(key) else { return }
        reportedKeys.append(key)
        if reportedKeys.count > 100 { reportedKeys.removeFirst(reportedKeys.count - 100) }
    }

    /// The user cleared the Alerts list: every notification group on screen now counts as
    /// reported, so a later layout walk does not add it back.
    func markOnScreenReported() {
        guard isRunning, let app = appElement else { return }
        aborted = false
        var budget = Self.maxNodes
        for w in windows(of: app).filter(isBannerWindow) where budget > 0 {
            guard let groups = walkNotificationGroups(w, budget: &budget, maxDepth: Self.maxDepth, read: readNode)
            else { return }
            for g in groups {
                if let id = g.info.id { remember(id: id) } else if let p = parse(g.element) { remember(key: Self.key(p)) }
            }
        }
    }

    // MARK: AX helpers

    /// The element's window: AXWindow attribute, else climb parents (max 10).
    private func window(of e: AXUIElement, budget: inout Int) -> AXUIElement? {
        if let w = element(e, kAXWindowAttribute) { return w }
        var cur: AXUIElement? = e
        for _ in 0..<10 {
            guard let c = cur, budget > 0, !aborted else { return nil }
            budget -= 1
            if string(c, kAXRoleAttribute) == (kAXWindowRole as String) { return c }
            cur = element(c, kAXParentAttribute)
        }
        return nil
    }

    /// Every read goes through here: 0.25 s timeout; a timeout / cannot-complete aborts the flush.
    private func copy(_ e: AXUIElement, _ a: String) -> AnyObject? {
        guard !aborted else { return nil }
        AXUIElementSetMessagingTimeout(e, AXTimeouts.seconds)
        var v: AnyObject?
        let err = AXUIElementCopyAttributeValue(e, a as CFString, &v)
        if err == .cannotComplete { aborted = true }
        return err == .success ? v : nil
    }

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        (copy(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    private func string(_ e: AXUIElement, _ a: String) -> String? {
        copy(e, a) as? String
    }

    private func element(_ e: AXUIElement, _ a: String) -> AXUIElement? {
        guard let v = copy(e, a), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func children(_ e: AXUIElement) -> [AXUIElement] {
        (copy(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
