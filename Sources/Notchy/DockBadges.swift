import AppKit
import ApplicationServices
import NotchyCore

/// Unread counts from Dock badges (`AXStatusLabel` of `AXApplicationDockItem`s, e.g.
/// "Microsoft Outlook" = "1"). Re-read when the Dock reports an AX change (coalesced, one-shot
/// 0.3 s), when an app launches/quits, and on `refresh()` (Alerts tab opened / banner seen).
/// No timer polling. No badge (app not running / not in Dock) → no count.
@MainActor
final class DockBadges {
    /// Watched app name → count (only apps with a numeric badge).
    var onChange: (([String: Int]) -> Void)?
    var watchedApps: () -> [String] = { [] }

    private(set) var isRunning = false
    private(set) var counts: [String: Int] = [:]
    private var observer: AXObserver?
    private var dockElement: AXUIElement?
    /// The Dock's item list as observed; a different list element means the Dock rebuilt it.
    private var listElement: AXUIElement?
    /// (element, notification) pairs registered, removed again in `detach`.
    private var registered: [(AXUIElement, String)] = []
    private var readScheduled = false
    private var workspaceObservers: [NSObjectProtocol] = []

    nonisolated static let bundleID = "com.apple.dock"
    private static let notifications = [
        kAXValueChangedNotification, kAXTitleChangedNotification, kAXCreatedNotification,
        kAXUIElementDestroyedNotification, kAXLayoutChangedNotification,
    ]

    func start() {
#if NOTCHY_CAPTURE
        return
#endif
        guard !isRunning else { return }
        isRunning = true
        AXTimeouts.applyGlobal()
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if bid == Self.bundleID, name == NSWorkspace.didLaunchApplicationNotification { self.attach() }
                    self.scheduleRead(after: 1)
                }
            })
        }
        attach()
        read()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObservers.removeAll()
        detach()
        if !counts.isEmpty {
            counts = [:]
            onChange?(counts)
        }
    }

    /// Re-read now (Alerts tab opened, settings changed).
    func refresh() {
        guard isRunning else { return }
        if dockElement == nil { attach() }
        read()
    }

    /// Re-read after `delay` (coalesced).
    func scheduleRead(after delay: TimeInterval = 0.3) {
        guard isRunning, !readScheduled else { return }
        readScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.readScheduled = false
                self?.read()
            }
        }
    }

    private func attach() {
        detach()
        guard isRunning, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return }
        let pid = dock.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXTimeouts.seconds)
        dockElement = app
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<DockBadges>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.scheduleRead() }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Observe the Dock app and its item list (badge changes are reported on items/list).
        let list = children(app).first
        listElement = list
        var targets = [app]
        if let list { targets.append(list) }
        for t in targets {
            for n in Self.notifications where AXObserverAddNotification(obs, t, n as CFString, refcon) == .success {
                registered.append((t, n))
            }
        }
        let ok = registered.count
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        notchyLog.notice("Alerts: observing Dock (\(ok) notifications registered)")
    }

    private func detach() {
        if let observer {
            for (e, n) in registered { AXObserverRemoveNotification(observer, e, n as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        registered.removeAll()
        observer = nil
        dockElement = nil
        listElement = nil
    }

    private func read() {
        guard isRunning, AXIsProcessTrusted(), var dock = dockElement else { return }
        // The Dock recreated its item list (or the observer never got one): re-register.
        let list = children(dock).first
        if let list, listElement.map({ !CFEqual($0, list) }) ?? true {
            attach()
            guard let d = dockElement else { return }
            dock = d
        }
        let watched = watchedApps()
        var out: [String: Int] = [:]
        for list in children(dock) {
            for item in children(list) {
                guard let title = string(item, kAXTitleAttribute),
                      let app = matchApp(title, in: watched),
                      let n = parseBadgeCount(string(item, "AXStatusLabel")) else { continue }
                out[app] = n
            }
        }
        guard out != counts else { return }
        counts = out
        notchyLog.notice("Alerts: Dock badges \(out.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "), privacy: .public)")
        onChange?(out)
    }

    private func string(_ e: AXUIElement, _ a: String) -> String? {
        AXUIElementSetMessagingTimeout(e, AXTimeouts.seconds)
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func children(_ e: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(e, AXTimeouts.seconds)
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }
}
