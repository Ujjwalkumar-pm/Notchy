import Foundation

/// The first-run welcome (AUDIT R1): three steps, shown once on a fresh install and reopenable
/// from Settings → General.
public enum WelcomeStep: Int, CaseIterable, Sendable {
    case hover, permissions, tabs

    public var title: String {
        switch self {
        case .hover: return "Hover the notch"
        case .permissions: return "Allow what you use"
        case .tabs: return "Pick your tabs"
        }
    }

    public var hint: String {
        switch self {
        case .hover: return "Notchy lives in the notch. Move the pointer onto it to open it, and right-click it for Settings."
        case .permissions: return "Each switch is yours to turn on in System Settings. Notchy works without them; the matching features stay off."
        case .tabs: return "Choose what the open notch shows. You can change this any time in Settings."
        }
    }

    public var next: WelcomeStep? { WelcomeStep(rawValue: rawValue + 1) }
    public var previous: WelcomeStep? { WelcomeStep(rawValue: rawValue - 1) }
}

/// A macOS permission a Notchy feature needs.
public enum Permission: String, CaseIterable, Sendable {
    case calendar, accessibility, focus, bluetooth

    public var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .accessibility: return "Accessibility"
        case .focus: return "Focus"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// What the permission is for, in the row's subtitle.
    public var purpose: String {
        switch self {
        case .calendar: return "Your next meeting and the 1-minute reminder"
        case .accessibility: return "Teams & Outlook alerts, volume and brightness keys"
        case .focus: return "Pause banners while a Focus is on"
        case .bluetooth: return "Banners when AirPods and other devices connect"
        }
    }

    public var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .accessibility: return "accessibility"
        case .focus: return "moon.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }

    /// The System Settings pane (Privacy & Security) the row's button opens.
    public var settingsURL: String {
        let anchor: String
        switch self {
        case .calendar: anchor = "Privacy_Calendars"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .focus: anchor = "Privacy_Focus"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }
}

public enum PermissionState: Equatable, Sendable { case granted, notDetermined, denied }

/// The checklist, in the AUDIT's order (Calendar, Accessibility, Focus, then Bluetooth), only
/// for features that are on: Accessibility always (media keys); Calendar with the Calendar tab
/// or meeting reminders; Focus with Respect Focus; Bluetooth with device events.
public func welcomePermissions(_ s: NotchySettings) -> [Permission] {
    var out: [Permission] = []
    if s.enabledTabs.contains(.calendar) || s.meetingReminder { out.append(.calendar) }
    out.append(.accessibility)
    if s.respectFocus { out.append(.focus) }
    if s.deviceEvents { out.append(.bluetooth) }
    return out
}

/// Bounded re-check after "Allow…" opened System Settings (like the media-keys pattern):
/// one-shot 2 s timers, at most 30 (≈ 1 min), stopping early once granted. Never a poll.
public enum PermissionRecheck {
    public static let interval: TimeInterval = 2
    public static let limit = 30
}

/// What the welcome does at launch.
public enum WelcomeLaunch: Equatable, Sendable {
    case skip, show
    /// A fresh install with an approval card up: shown once the card goes.
    case waitForApproval
}

/// The welcome shows by itself only on a fresh install, and never over a pending approval
/// (it waits for the card to go).
public func welcomeLaunchAction(_ s: NotchySettings, approvalPending: Bool) -> WelcomeLaunch {
    if s.hasSeenWelcome { return .skip }
    return approvalPending ? .waitForApproval : .show
}

public func welcomeShowsAtLaunch(_ s: NotchySettings, approvalPending: Bool) -> Bool {
    welcomeLaunchAction(s, approvalPending: approvalPending) == .show
}

/// UserDefaults keys only an earlier Notchy run writes: `didQuitDynamicNotch` (older versions, first launch),
/// `panelSize` (a resize), `userDisabledStartAtLogin` (Start at login turned off).
public let existingUserMarkerKeys: Set<String> = ["didQuitDynamicNotch", PanelSizeStore.key, "userDisabledStartAtLogin"]

/// Settings at launch: the saved `notchySettings` blob decoded, and with no blob but a key an
/// earlier run wrote (`presentKeys` ∩ `existingUserMarkerKeys`), an existing user: defaults
/// with the welcome already seen.
public func launchSettings(_ data: Data?, presentKeys: Set<String>) -> NotchySettings {
    var s = decodeSettings(data)
    if data == nil, !presentKeys.isDisjoint(with: existingUserMarkerKeys) { s.hasSeenWelcome = true }
    return s
}

/// Opening Notchy again (Finder, Spotlight) opens Settings (AUDIT R1), except for the reopen
/// LaunchServices can send right after a launch: none within `quietWindow` of launch, and
/// none within `loginQuietWindow` of a launch as a login item (login can be slow and
/// loginwindow may reopen its items), so Settings never pops up at login.
public enum ReopenPolicy {
    public static let quietWindow: TimeInterval = 10
    public static let loginQuietWindow: TimeInterval = 60

    public static func opensSettings(sinceLaunch: TimeInterval, launchedAsLoginItem: Bool) -> Bool {
        sinceLaunch >= (launchedAsLoginItem ? loginQuietWindow : quietWindow)
    }
}
