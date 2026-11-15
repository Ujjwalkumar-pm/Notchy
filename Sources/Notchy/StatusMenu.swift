import AppKit
import NotchyCore

/// The right-click menu on the notch panel: "Settings…" and "Quit Notchy" (plus the
/// Enable item while media keys are off). Everything else lives in Settings → General.
/// The same menu hangs off the optional menu-bar icon (AUDIT R1, off by default).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    /// Result of the launch-time hook install; `.unreadable` adds a warning item.
    var installResult: InstallResult?
    /// "Settings…" chosen.
    var onOpenSettings: (() -> Void)?

    /// Called just before the menu is built (re-checks Accessibility, may start the tap).
    var onWillOpen: (() -> Void)?
    /// Whether the media key tap is running; when false the Enable item is shown.
    var mediaKeysActive: () -> Bool = { true }
    /// Called after "Enable volume/brightness pop-up…" opened System Settings.
    var onEnableMediaKeys: (() -> Void)?

    static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    func popUp(with event: NSEvent, in view: NSView) {
        onWillOpen?()
        let menu = NSMenu()
        fill(menu)
        let point = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private var statusItem: NSStatusItem?

    /// Settings → General → Menu bar icon (and the welcome's step 3): a second way into
    /// Settings. Its menu is rebuilt each time it opens.
    func setMenuBarIcon(_ on: Bool) {
        if on, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchy")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = "Notchy"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !on, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        onWillOpen?()
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if installResult == .unreadable {
            let warn = NSMenuItem(title: "Couldn't read Claude settings", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        if !mediaKeysActive() {
            menu.addItem(item("Enable volume/brightness pop-up…", #selector(enableMediaKeys)))
        }
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Notchy", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func enableMediaKeys() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
        onEnableMediaKeys?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Actions from Settings → General that show an alert (formerly right-click menu items).
@MainActor
enum NotchActions {
    /// Settings → General → Claude Code integration, switched off: a confirmation sheet on the
    /// Settings window, then the hooks are removed and the choice is remembered so launch
    /// doesn't add them back. `completion(true)` when the switch should now read off.
    static func removeClaudeHooks(settings: SettingsStore, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Turn off Claude Code integration?"
        alert.informativeText = "Notchy removes its hooks from \(Lifecycle.claudeSettingsDisplayPath). Claude sessions and approvals stop appearing in the notch until you turn it back on."
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { completion(false); return }
            let installer = Lifecycle.installer
            // uninstall() is false when there was nothing to remove; that still counts as removed.
            let ok = installer.uninstall(now: Date()) || !installer.isInstalled()
            notchyLog.notice("Remove Claude hooks: \(ok)")
            if ok { settings.update { $0.claudeIntegration = false }; onInstallResultChange?(nil) }
            else {
                let fail = NSAlert()
                fail.messageText = "Couldn't remove Claude hooks."
                fail.informativeText = "Notchy couldn't update \(Lifecycle.claudeSettingsDisplayPath)."
                fail.addButton(withTitle: "OK")
                fail.runModal()
            }
            completion(ok)
        }
        NSApp.activate()
        if let w = NSApp.keyWindow { alert.beginSheetModal(for: w, completionHandler: finish) }
        else { finish(alert.runModal()) }
    }

    /// Switched on: add the hooks again and remember the choice. False if Claude's settings
    /// couldn't be read.
    @discardableResult
    static func installClaudeHooks(settings: SettingsStore) -> Bool {
        let result = Lifecycle.installHooks()
        onInstallResultChange?(result)
        guard result != .unreadable else {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Couldn't turn on Claude Code integration."
            alert.informativeText = "Notchy couldn't read \(Lifecycle.claudeSettingsDisplayPath)."
            alert.addButton(withTitle: "OK")
            if let w = NSApp.keyWindow { alert.beginSheetModal(for: w) } else { alert.runModal() }
            return false
        }
        settings.update { $0.claudeIntegration = true }
        return true
    }

    /// Lets the right-click menu follow Settings' install/remove (its warning must not go stale).
    static var onInstallResultChange: ((InstallResult?) -> Void)?

    /// Settings → General → Show Welcome… (AUDIT R1).
    static var onShowWelcome: (() -> Void)?

    /// NSAlert with a Closed | Open switch and W / H fields (points), prefilled with the
    /// size currently in effect for the chosen state. No upper limit; bad or ≤ 0 input → 1.
    static func setSize(panel: NotchPanel) {
        let editor = SizeEditor(panel: panel, expanded: panel.isExpanded)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Set notch size"
        alert.informativeText = "Width and height in points. Pick Closed or Open to choose which size to change."
        alert.accessoryView = editor.view
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        // Above the notch panel (.mainMenu + 3), which may be open and large.
        alert.window.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        alert.window.initialFirstResponder = editor.widthField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let size = editor.enteredSize
        // OK with the prefilled default left as is: keep using the default, save nothing.
        if panel.customSize(expanded: editor.expanded) == nil && size == editor.prefilled { return }
        notchyLog.notice("Set size: \(editor.expanded ? "open" : "closed", privacy: .public) \(size.width) x \(size.height)")
        panel.setCustomSize(size, expanded: editor.expanded)
    }
}

/// Accessory view for "Set size…": a Closed | Open switch and W / H fields.
@MainActor
private final class SizeEditor: NSObject {
    let view: NSView
    let widthField = NSTextField()
    let heightField = NSTextField()
    private let segment: NSSegmentedControl
    private let panel: NotchPanel

    var expanded: Bool { segment.selectedSegment == 1 }
    /// What the fields were last filled with (parsed the same way as the user's input).
    private(set) var prefilled: CGSize = .zero

    /// Non-numeric or ≤ 0 → 1; whole points; no cap.
    var enteredSize: CGSize {
        func value(_ f: NSTextField) -> CGFloat {
            let v = Double(f.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
            return v.isFinite ? max(1, CGFloat(v).rounded()) : 1
        }
        return CGSize(width: value(widthField), height: value(heightField))
    }

    init(panel: NotchPanel, expanded: Bool) {
        self.panel = panel
        segment = NSSegmentedControl(labels: ["Closed", "Open"], trackingMode: .selectOne,
                                     target: nil, action: nil)
        view = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: 64))
        super.init()
        segment.selectedSegment = expanded ? 1 : 0
        segment.target = self
        segment.action = #selector(segmentChanged)
        segment.frame = CGRect(x: 0, y: 36, width: 160, height: 24)
        view.addSubview(segment)

        let wLabel = NSTextField(labelWithString: "W")
        wLabel.frame = CGRect(x: 0, y: 3, width: 16, height: 20)
        widthField.frame = CGRect(x: 18, y: 0, width: 80, height: 24)
        let hLabel = NSTextField(labelWithString: "H")
        hLabel.frame = CGRect(x: 110, y: 3, width: 16, height: 20)
        heightField.frame = CGRect(x: 128, y: 0, width: 80, height: 24)
        let unit = NSTextField(labelWithString: "pt")
        unit.frame = CGRect(x: 214, y: 3, width: 30, height: 20)
        for v in [wLabel, widthField, hLabel, heightField, unit] { view.addSubview(v) }
        widthField.nextKeyView = heightField
        fill()
    }

    @objc private func segmentChanged() { fill() }

    private func fill() {
        let s = panel.effectiveSize(expanded: expanded)
        widthField.stringValue = Self.format(s.width)
        heightField.stringValue = Self.format(s.height)
        prefilled = enteredSize
    }

    /// No Int conversion: "no cap" allows values beyond Int's range.
    private static func format(_ v: CGFloat) -> String {
        String(format: "%.0f", Double(v))
    }
}
