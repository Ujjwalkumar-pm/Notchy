import AppKit
import ServiceManagement
import os
import NotchyCore

let notchyLog = Logger(subsystem: "in.ujjwalkumar.notchy", category: "lifecycle")

/// Launch-time housekeeping: Claude hooks, start at login, DynamicNotch.
@MainActor
enum Lifecycle {
#if NOTCHY_CAPTURE
    /// Capture build: a scratch copy, never the user's Claude settings.
    static let claudeSettingsURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("notchy-capture-claude/settings.json")
    /// Shown in the "Turn off" alert instead of the scratch path.
    static let claudeSettingsDisplayPath = "/Users/demo/.claude/settings.json"
#else
    static let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    static var claudeSettingsDisplayPath: String { claudeSettingsURL.path }
#endif

    static var installer: SettingsInstaller { SettingsInstaller(settingsURL: claudeSettingsURL) }

    /// Adds Notchy's hook entries to ~/.claude/settings.json (the installer writes a backup first).
    static func installHooks() -> InstallResult {
#if NOTCHY_CAPTURE
        return .alreadyInstalled
#endif
        let result = installer.install(now: Date())
        switch result {
        case .alreadyInstalled:
            notchyLog.notice("Claude hooks already installed")
        case .installed(let backup):
            notchyLog.notice("Claude hooks installed; backup: \(backup?.path ?? "none", privacy: .public)")
        case .unreadable:
            notchyLog.error("Couldn't read \(claudeSettingsURL.path, privacy: .public); hooks not installed")
        }
        return result
    }

    // MARK: Start at login

#if NOTCHY_CAPTURE
    static var startsAtLogin: Bool { true }
#else
    static var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }
#endif
    /// Set when the user turns start at login off through Notchy; launch then leaves it off.
    static let userDisabledStartAtLoginKey = "userDisabledStartAtLogin"

    /// Launch-time: register unless the user turned it off (in Notchy or in System Settings).
    static func autoEnableStartAtLogin() {
#if NOTCHY_CAPTURE
        return
#endif
        let status = SMAppService.mainApp.status
        if UserDefaults.standard.bool(forKey: userDisabledStartAtLoginKey) {
            notchyLog.notice("Start at login left off (user turned it off in Notchy)")
            return
        }
        if status == .requiresApproval {
            notchyLog.notice("Start at login needs approval in System Settings; not re-registering")
            return
        }
        register()
    }

    /// User turned it on from the menu.
    static func userEnableStartAtLogin() {
#if NOTCHY_CAPTURE
        return
#endif
        UserDefaults.standard.removeObject(forKey: userDisabledStartAtLoginKey)
        register()
    }

    /// User turned it off from the menu or the "hooks removed" alert.
    static func userDisableStartAtLogin() {
#if NOTCHY_CAPTURE
        return
#endif
        UserDefaults.standard.set(true, forKey: userDisabledStartAtLoginKey)
        do {
            try SMAppService.mainApp.unregister()
            notchyLog.notice("Login item unregistered")
        } catch {
            notchyLog.error("Login item unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func register() {
#if NOTCHY_CAPTURE
        return
#endif
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
            notchyLog.notice("Login item registered; status \(service.status.rawValue)")
        } catch {
            notchyLog.error("Login item register failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
