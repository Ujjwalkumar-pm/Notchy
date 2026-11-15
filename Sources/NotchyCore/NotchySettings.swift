import Foundation

public enum TabID: String, Codable, CaseIterable, Sendable { case music, claude, alerts, calendar }

public enum Theme: String, Codable, Sendable { case black, glass }

/// Where the tab icons sit in the notch-height strip of the open panel.
/// `split` (B, default): half left of the camera notch, half right (extra on the left).
/// `tabsAndStatus` (A): all tabs left, live status (Claude working, unread, next meeting) right.
public enum TabLayout: String, Codable, Sendable { case split, tabsAndStatus }

/// Where the open panel is anchored on the notch: its centre (default), left edge (the panel
/// grows to the right) or right edge (grows to the left). Never off-screen.
public enum OpenAnchor: String, Codable, CaseIterable, Sendable { case centre, left, right }

/// How the panel opens and closes. `fade` = no size animation, an alpha fade around an instant
/// frame change; `none` = instant.
public enum PanelAnimation: String, Codable, CaseIterable, Sendable { case spring, smooth, snappy, fade, none }

/// Multiplies the animation's duration.
public enum AnimationSpeed: String, Codable, CaseIterable, Sendable { case slow, normal, fast }

public struct NotchySettings: Codable, Equatable, Sendable {
    public var tabOrder: [TabID]
    public var enabledTabs: Set<TabID>
    public var lastTab: TabID?
    public var watchedApps: [String]
    public var seenApps: [String]
    public var alertBanners: Bool
    public var deviceEvents: Bool
    public var deviceBanners: Bool
    public var selectedCalendarIDs: [String]?
    public var meetingReminder: Bool
    public var claudeFinishedBanner: Bool
    public var quietWhilePresenting: Bool
    public var respectFocus: Bool
    public var hideInFullScreen: Bool
    public var theme: Theme
    public var accentHex: String
    public var tabLayout: TabLayout
    /// Two-finger horizontal trackpad swipe over the open panel changes tabs.
    public var swipeTabs: Bool
    public var openFrom: OpenAnchor
    public var animation: PanelAnimation
    public var animationSpeed: AnimationSpeed
    /// Claude Code integration: Notchy adds its hooks to ~/.claude/settings.json at launch.
    /// Off = the user removed them in Settings; launch then leaves Claude's settings alone.
    public var claudeIntegration: Bool
    /// The first-run welcome (AUDIT R1) was shown. False only for a fresh install (no saved
    /// settings at all); a saved blob without the key is an existing user, who never gets the
    /// welcome forced on them. Settings → General → Welcome & permissions reopens it.
    public var hasSeenWelcome: Bool
    /// AUDIT R1: optional menu-bar icon, a second way into Settings. Off by default.
    public var menuBarIcon: Bool

    public init(tabOrder: [TabID] = TabID.allCases,
                enabledTabs: Set<TabID> = Set(TabID.allCases),
                lastTab: TabID? = nil,
                watchedApps: [String] = ["Microsoft Outlook", "Microsoft Teams"],
                seenApps: [String] = [],
                alertBanners: Bool = true,
                deviceEvents: Bool = true,
                deviceBanners: Bool = true,
                selectedCalendarIDs: [String]? = nil,
                meetingReminder: Bool = true,
                claudeFinishedBanner: Bool = true,
                quietWhilePresenting: Bool = true,
                respectFocus: Bool = true,
                hideInFullScreen: Bool = true,
                theme: Theme = .black,
                accentHex: String = "#7AA7FF",
                tabLayout: TabLayout = .split,
                swipeTabs: Bool = true,
                openFrom: OpenAnchor = .centre,
                animation: PanelAnimation = .spring,
                animationSpeed: AnimationSpeed = .normal,
                claudeIntegration: Bool = true,
                hasSeenWelcome: Bool = false,
                menuBarIcon: Bool = false) {
        self.tabOrder = tabOrder
        self.enabledTabs = enabledTabs
        self.lastTab = lastTab
        self.watchedApps = watchedApps
        self.seenApps = seenApps
        self.alertBanners = alertBanners
        self.deviceEvents = deviceEvents
        self.deviceBanners = deviceBanners
        self.selectedCalendarIDs = selectedCalendarIDs
        self.meetingReminder = meetingReminder
        self.claudeFinishedBanner = claudeFinishedBanner
        self.quietWhilePresenting = quietWhilePresenting
        self.respectFocus = respectFocus
        self.hideInFullScreen = hideInFullScreen
        self.theme = theme
        self.accentHex = accentHex
        self.tabLayout = tabLayout
        self.swipeTabs = swipeTabs
        self.openFrom = openFrom
        self.animation = animation
        self.animationSpeed = animationSpeed
        self.claudeIntegration = claudeIntegration
        self.hasSeenWelcome = hasSeenWelcome
        self.menuBarIcon = menuBarIcon
    }

    public static let defaults = NotchySettings()

    enum CodingKeys: String, CodingKey {
        case tabOrder, enabledTabs, lastTab, watchedApps, seenApps, alertBanners, deviceEvents
        case deviceBanners, selectedCalendarIDs, meetingReminder, claudeFinishedBanner
        case quietWhilePresenting, respectFocus, hideInFullScreen, theme, accentHex
        case tabLayout, swipeTabs, openFrom, animation, animationSpeed
        case claudeIntegration, hasSeenWelcome, menuBarIcon
    }

    /// Tolerant: every key independently falls back to its default when missing or wrongly typed.
    public init(from decoder: Decoder) throws {
        let d = NotchySettings.defaults
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        // Tab IDs are decoded as raw strings so unknown ones can be dropped individually.
        let rawOrder: [String] = get(.tabOrder, d.tabOrder.map(\.rawValue))
        var order: [TabID] = []
        for tab in rawOrder.compactMap(TabID.init(rawValue:)) where !order.contains(tab) { order.append(tab) }
        for tab in TabID.allCases where !order.contains(tab) { order.append(tab) }
        let rawEnabled: [String] = get(.enabledTabs, d.enabledTabs.map(\.rawValue))
        let enabled = Set(rawEnabled.compactMap(TabID.init(rawValue:)))
        let rawLast: String? = get(.lastTab, nil)

        tabOrder = order
        enabledTabs = enabled.isEmpty ? Set(TabID.allCases) : enabled
        lastTab = rawLast.flatMap(TabID.init(rawValue:))
        watchedApps = get(.watchedApps, d.watchedApps)
        seenApps = get(.seenApps, d.seenApps)
        alertBanners = get(.alertBanners, d.alertBanners)
        deviceEvents = get(.deviceEvents, d.deviceEvents)
        deviceBanners = get(.deviceBanners, d.deviceBanners)
        selectedCalendarIDs = get(.selectedCalendarIDs, d.selectedCalendarIDs)
        meetingReminder = get(.meetingReminder, d.meetingReminder)
        claudeFinishedBanner = get(.claudeFinishedBanner, d.claudeFinishedBanner)
        quietWhilePresenting = get(.quietWhilePresenting, d.quietWhilePresenting)
        respectFocus = get(.respectFocus, d.respectFocus)
        hideInFullScreen = get(.hideInFullScreen, d.hideInFullScreen)
        theme = get(.theme, d.theme)
        accentHex = get(.accentHex, d.accentHex)
        tabLayout = get(.tabLayout, d.tabLayout)
        swipeTabs = get(.swipeTabs, d.swipeTabs)
        openFrom = get(.openFrom, d.openFrom)
        animation = get(.animation, d.animation)
        animationSpeed = get(.animationSpeed, d.animationSpeed)
        claudeIntegration = get(.claudeIntegration, d.claudeIntegration)
        // Missing from a saved blob = settings saved before the welcome existed: an existing user.
        hasSeenWelcome = get(.hasSeenWelcome, true)
        menuBarIcon = get(.menuBarIcon, d.menuBarIcon)
    }
}

/// No saved data = a fresh install (the welcome shows); unreadable data still means someone
/// used Notchy before, so the defaults come back with the welcome marked seen.
public func decodeSettings(_ data: Data?) -> NotchySettings {
    guard let data else { return .defaults }
    guard let s = try? JSONDecoder().decode(NotchySettings.self, from: data) else {
        var d = NotchySettings.defaults
        d.hasSeenWelcome = true
        return d
    }
    return s
}

public func visibleTabs(_ s: NotchySettings) -> [TabID] {
    s.tabOrder.filter { s.enabledTabs.contains($0) }
}

public func openingTab(_ s: NotchySettings) -> TabID {
    let visible = visibleTabs(s)
    if let last = s.lastTab, visible.contains(last) { return last }
    return visible.first ?? s.tabOrder.first ?? .music
}

public func movingTab(_ s: NotchySettings, from: Int, to: Int) -> NotchySettings {
    guard !s.tabOrder.isEmpty else { return s }
    let last = s.tabOrder.count - 1
    let f = min(max(from, 0), last), t = min(max(to, 0), last)
    guard f != t else { return s }
    var out = s
    let tab = out.tabOrder.remove(at: f)
    out.tabOrder.insert(tab, at: t)
    return out
}

public func settingTab(_ s: NotchySettings, _ id: TabID, enabled: Bool) -> NotchySettings {
    var out = s
    if enabled {
        out.enabledTabs.insert(id)
    } else {
        out.enabledTabs.remove(id)
        if out.enabledTabs.isEmpty { return s }
    }
    return out
}
