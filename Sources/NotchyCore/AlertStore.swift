import Foundation

/// One row in the Alerts tab: a watched app's notification banner or a device event.
/// Kept in memory only (never persisted or logged).
public struct AlertItem: Equatable, Sendable, Identifiable {
    public let id: String
    /// App name as shown in the banner ("Microsoft Teams"); for device rows the `DeviceIcon`
    /// raw value ("headphones", "drive", …) so the row can pick its symbol.
    public let app: String
    public let title: String
    public let body: String
    public let at: Date
    public let device: Bool

    public init(id: String, app: String, title: String, body: String, at: Date, device: Bool) {
        self.id = id
        self.app = app
        self.title = title
        self.body = body
        self.at = at
        self.device = device
    }
}

/// Newest first, at most `cap` items, items older than `maxAge` dropped, the same
/// app + title + body within `duplicateWindow` ignored.
public struct AlertStore: Sendable {
    /// The list keeps the ten newest items.
    public static let cap = 10
    /// Rows the Alerts tab shows before the list scrolls.
    public static let visibleRowLimit = 5
    public static let maxAge: TimeInterval = 24 * 60 * 60
    public static let duplicateWindow: TimeInterval = 60
    /// Notification ids remembered after they were first offered (oldest dropped first), so a
    /// banner the watcher re-reports after its row was evicted is not re-added as newest.
    public static let seenIDCap = 100

    public private(set) var items: [AlertItem] = []
    /// Ids only (never banner text), oldest first, at most `seenIDCap`.
    public private(set) var seenIDs: [String] = []

    public init() {}

    /// Returns false (and stores nothing) for a duplicate, and false when the item is older
    /// than the ten kept and so trimmed straight away.
    @discardableResult
    public mutating func add(_ i: AlertItem, now: Date) -> Bool {
        prune(now: now)
        let dup = items.contains {
            $0.app == i.app && $0.title == i.title && $0.body == i.body
                && abs(i.at.timeIntervalSince($0.at)) < Self.duplicateWindow
        }
        if dup { return false }
        let at = items.firstIndex { $0.at <= i.at } ?? items.count
        items.insert(i, at: at)
        if items.count > Self.cap { items.removeLast(items.count - Self.cap) }
        return items.contains { $0.id == i.id }
    }

    /// What `admitNotification` did.
    public enum Admit: Equatable, Sendable { case added, upgraded, ignored, duplicate }

    /// A Notification Center banner: its row's body is filled in when the row is still here;
    /// an id offered before (kept, evicted, a duplicate or cleared) is ignored; otherwise the
    /// id is remembered and the item added (`duplicate` when `add` refused it: same text
    /// within a minute, or older than the ten kept).
    public mutating func admitNotification(_ i: AlertItem, now: Date) -> Admit {
        if contains(id: i.id) { return upgradeBody(id: i.id, body: i.body) ? .upgraded : .ignored }
        if seenIDs.contains(i.id) { return .ignored }
        seenIDs.append(i.id)
        if seenIDs.count > Self.seenIDCap { seenIDs.removeFirst(seenIDs.count - Self.seenIDCap) }
        return add(i, now: now) ? .added : .duplicate
    }

    public mutating func prune(now: Date) {
        items.removeAll { now.timeIntervalSince($0.at) > Self.maxAge }
    }

    public mutating func clear() { items.removeAll() }

    /// A row first stored without a body (the banner's body text was not filled in yet) gets
    /// its body. False when there is no such row or it already has a body.
    @discardableResult
    public mutating func upgradeBody(id: String, body: String) -> Bool {
        guard !body.isEmpty, let i = items.firstIndex(where: { $0.id == id }), items[i].body.isEmpty else { return false }
        let o = items[i]
        items[i] = AlertItem(id: o.id, app: o.app, title: o.title, body: body, at: o.at, device: o.device)
        return true
    }

    public func contains(id: String) -> Bool { items.contains { $0.id == id } }
}

/// Alerts tab list: rows shown (at most 5) and whether the list scrolls (6 or more items).
public func alertListLayout(count: Int) -> (visibleRows: Int, scrolls: Bool) {
    let n = max(0, count)
    return (min(n, AlertStore.visibleRowLimit), n > AlertStore.visibleRowLimit)
}

/// The Alerts row for a device event (same words as its banner).
public func alertItemFor(_ e: DeviceEvent, now: Date) -> AlertItem {
    let b = bannerFor(e, now: now)
    var icon = "bolt.fill"
    if case .device(let badge) = b.kind { icon = badge.icon.rawValue }
    return AlertItem(id: "device:\(b.id):\(now.timeIntervalSince1970)", app: icon,
                     title: b.title, body: b.subtitle, at: now, device: true)
}

// MARK: - App names

private func normalizedApp(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.hasPrefix("microsoft ") { t.removeFirst("microsoft ".count) }
    return t
}

/// The entry of `list` that names the same app as `name` (case-insensitive; "Teams" matches
/// "Microsoft Teams"), or nil.
public func matchApp(_ name: String, in list: [String]) -> String? {
    let n = normalizedApp(name)
    guard !n.isEmpty else { return nil }
    return list.first { normalizedApp($0) == n }
}

/// Apple system sources that post banners (a Privacy & Security prompt, a Software Update
/// notice). The banner text carries only the display name, not the bundle ID, so these are
/// matched by name. They are never offered as watch candidates (AUDIT S4).
public let systemNoticeSources: Set<String> = [
    "privacy & security", "system settings", "system preferences", "software update",
    "screen time", "control centre", "control center", "notification centre", "notification center",
    "siri", "spotlight", "battery", "time machine", "apple account", "icloud", "passwords", "focus",
]

public func isSystemNoticeSource(_ name: String) -> Bool {
    systemNoticeSources.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

/// `seenApps` after a banner from `app`: watched apps and repeats change nothing; new names
/// are appended (oldest dropped past `cap`). Only the name is kept, never the banner text.
public func notingSeenApp(_ seen: [String], app: String, watched: [String], cap: Int = 30) -> [String] {
    let name = app.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !isSystemNoticeSource(name), matchApp(name, in: watched) == nil, matchApp(name, in: seen) == nil else { return seen }
    var out = seen + [name]
    if out.count > cap { out.removeFirst(out.count - cap) }
    return out
}

// MARK: - Banner text

/// App, title and body from the texts read out of one Notification Center banner.
///
/// Verified layout on macOS 27.2 (15 Nov): an `AXGroup` with subrole
/// `AXNotificationCenterBanner` whose AXDescription is "<App>, <title>, <body>", with child
/// `AXStaticText`s identified `title` and `body`. Callers pass the description first, then the
/// static texts. Also handles: no combined description (app as its own text, else the first
/// text), a combined description alone, unknown apps.
public func parseBannerTexts(_ texts: [String], knownApps: [String]) -> (app: String, title: String, body: String)? {
    var clean: [String] = []
    for t in texts {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty && !clean.contains(s) { clean.append(s) }
    }
    guard !clean.isEmpty else { return nil }

    func result(_ app: String, _ rest: [String]) -> (app: String, title: String, body: String)? {
        let a = app.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, let title = rest.first, !title.isEmpty else { return nil }
        return (a, title, rest.dropFirst().joined(separator: " "))
    }

    // 1. A combined "<App>, <title>, <body>" description.
    if let ci = clean.firstIndex(where: { $0.contains(", ") }) {
        let combined = clean[ci]
        var others = clean
        others.remove(at: ci)
        // Texts already part of the combined one (title/body) give the split points.
        let parts = others.filter { combined.contains($0) }
        var app: String?
        if let known = knownApps.first(where: { combined.lowercased().hasPrefix($0.lowercased() + ", ") }) {
            app = String(combined.prefix(known.count))
        } else if let first = parts.first, let r = combined.range(of: ", " + first) {
            app = String(combined[..<r.lowerBound])
        } else if parts.isEmpty, combined.hasPrefix(", ") == false {
            app = combined.components(separatedBy: ", ").first
        }
        if let app {
            if !parts.isEmpty { return result(app, parts) }
            var rest = String(combined.dropFirst(app.count))
            if rest.hasPrefix(", ") { rest.removeFirst(2) }
            if let r = rest.range(of: ", ") {
                return result(app, [String(rest[..<r.lowerBound]), String(rest[r.upperBound...])])
            }
            return result(app, [rest])
        }
    }
    // 2. The app name as its own text.
    if let ai = clean.firstIndex(where: { matchApp($0, in: knownApps) != nil }) {
        var rest = clean
        let app = rest.remove(at: ai)
        return result(app, rest)
    }
    // 3. Unknown layout: first text is the app.
    return result(clean[0], Array(clean.dropFirst()))
}

/// A parsed banner. `confirmed`: the app name is known to be the app's, not banner text —
/// it is a known app at the start of the description, or the description splits as
/// "<app>, <title>[, …]" with the `title` text as its second segment.
public struct ParsedBanner: Equatable, Sendable {
    public let app: String
    public let title: String
    public let body: String
    public let confirmed: Bool

    public init(app: String, title: String, body: String, confirmed: Bool) {
        self.app = app
        self.title = title
        self.body = body
        self.confirmed = confirmed
    }
}

/// Parses one banner group: its AXDescription and its `title` / `body` static texts.
public func parseBannerGroup(description: String?, title: String?, body: String?, others: [String] = [],
                             knownApps: [String]) -> ParsedBanner? {
    let d = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let texts = [d, t, body].compactMap { $0 } + others
    guard let p = parseBannerTexts(texts, knownApps: knownApps) else { return nil }
    var confirmed = false
    if let d, !d.isEmpty {
        let lower = d.lowercased()
        if knownApps.contains(where: { lower.hasPrefix($0.lowercased() + ", ") && $0.lowercased() == p.app.lowercased() }) {
            confirmed = true
        } else if let t, !t.isEmpty {
            let head = p.app + ", " + t
            confirmed = d == head || d.hasPrefix(head + ", ")
        }
    }
    return ParsedBanner(app: p.app, title: p.title, body: p.body, confirmed: confirmed)
}

/// What to do with a parsed banner.
public enum BannerRoute: Equatable, Sendable {
    /// A watched app (the watched list's spelling): Alerts row (+ banner).
    case watched(app: String)
    /// A new other app, confirmed: the new `seenApps` (name only).
    case seen([String])
    /// Already-seen app, or the app name is not confirmed: nothing kept, nothing logged.
    case drop
}

public func routeBanner(_ p: ParsedBanner, watched: [String], seen: [String]) -> BannerRoute {
    if let app = matchApp(p.app, in: watched) { return .watched(app: app) }
    guard p.confirmed else { return .drop }
    let next = notingSeenApp(seen, app: p.app, watched: watched)
    return next == seen ? .drop : .seen(next)
}

// MARK: - Which banner groups to report

/// The subrole of a Notification Center banner (verified macOS 27.2).
public let notificationBannerSubrole = "AXNotificationCenterBanner"
/// Persistent "Alerts"-style notifications (stay until dismissed).
public let notificationAlertSubrole = "AXNotificationCenterAlert"
/// Group subroles that count as a new notification.
public let notificationGroupSubroles: Set<String> = [notificationBannerSubrole, notificationAlertSubrole]

/// One notification group found in a Notification Center walk.
public struct BannerGroupInfo: Equatable, Sendable {
    /// The group's AXIdentifier (a per-notification UUID), when present.
    public var id: String?
    public var subrole: String?
    /// Inside the Notification Center list (its container also holds non-banner content such
    /// as headings, buttons, text or widgets) — old notifications, not a new banner.
    public var inList: Bool

    public init(id: String?, subrole: String?, inList: Bool) {
        self.id = id
        self.subrole = subrole
        self.inList = inList
    }
}

/// Indices (in walk order) of the groups to report: banner or alert subrole exactly, not in the list,
/// not already reported, each id once; at most `cap`.
public func bannerGroupsToReport(_ groups: [BannerGroupInfo], reported: Set<String>, cap: Int = 10) -> [Int] {
    var out: [Int] = []
    var ids: Set<String> = []
    for (i, g) in groups.enumerated() where out.count < cap {
        guard let sr = g.subrole, notificationGroupSubroles.contains(sr), !g.inList else { continue }
        if let id = g.id {
            guard !reported.contains(id), ids.insert(id).inserted else { continue }
        }
        out.append(i)
    }
    return out
}

// MARK: - Dock badges and time

/// Count from a Dock item's `AXStatusLabel` ("3" → 3, "99+" → 99); nil when there is no
/// numeric badge.
public func parseBadgeCount(_ label: String?) -> Int? {
    guard let label else { return nil }
    let digits = label.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
    guard let n = Int(digits), n > 0 else { return nil }
    return n
}

/// "now", "5m", "3h", "2d".
public func relativeTime(_ at: Date, now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(at)))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// "Microsoft Teams" → "Teams" (chips and tiles).
public func shortAppName(_ app: String) -> String {
    app.hasPrefix("Microsoft ") ? String(app.dropFirst("Microsoft ".count)) : app
}
