import Foundation

/// One calendar event as the Calendar tab and the meeting reminder see it. Memory only:
/// titles and attendees are never logged or written to disk.
public struct MeetingInfo: Equatable, Sendable {
    /// Unique per occurrence (the service joins the event id and the start time).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var calendarColorHex: String
    public var joinURL: URL?
    /// Other attendees' display names (the current user is skipped).
    public var attendees: [String]
    /// The event's calendar name, used as the chip label when there is no meeting link.
    public var calendarTitle: String

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool,
                calendarColorHex: String, joinURL: URL?, attendees: [String], calendarTitle: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendarColorHex = calendarColorHex
        self.joinURL = joinURL
        self.attendees = attendees
        self.calendarTitle = calendarTitle
    }
}

// MARK: - Join link

private let joinPattern: NSRegularExpression = {
    let body = #"[^\s"'<>]+"#
    let p = [
        #"https://teams\.microsoft\.com/"# + body,
        #"https://teams\.live\.com/"# + body,
        #"https://(?:[a-z0-9-]+\.)*zoom\.us/j/"# + body,
        #"https://meet\.google\.com/"# + body,
    ].joined(separator: "|")
    return try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
}()

private let safeLinkPattern = try! NSRegularExpression(
    pattern: #"https://[a-z0-9.-]*safelinks\.protection\.outlook\.com/[^\s"'<>]*"#, options: [.caseInsensitive])

/// Replaces Outlook Safe Links (`…safelinks.protection.outlook.com/?url=<encoded>&…`) with the
/// link they wrap, so the meeting link inside can be matched.
func unwrappingSafeLinks(_ text: String) -> String {
    let ns = text as NSString
    var out = text
    for m in safeLinkPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
        let wrapped = ns.substring(with: m.range)
        guard let inner = URLComponents(string: wrapped)?.queryItems?.first(where: { $0.name.lowercased() == "url" })?.value,
              !inner.isEmpty, let r = Range(m.range, in: out) else { continue }
        out.replaceSubrange(r, with: inner)
    }
    return out
}

/// The first Teams / Zoom / Google Meet link, looking at the event's URL field, then its
/// location, then its notes (the first field with a link wins). Outlook Safe Links are
/// unwrapped first.
public func joinLink(url: String?, notes: String?, location: String?) -> URL? {
    for field in [url, location, notes] {
        guard let raw = field, !raw.isEmpty else { continue }
        let text = raw.localizedCaseInsensitiveContains("safelinks.protection.outlook.com") ? unwrappingSafeLinks(raw) : raw
        let range = NSRange(text.startIndex..., in: text)
        guard let m = joinPattern.firstMatch(in: text, range: range),
              let r = Range(m.range, in: text) else { continue }
        var s = String(text[r])
        while let last = s.last, ".,;:!?)]}".contains(last) { s.removeLast() }
        if let u = URL(string: s) { return u }
    }
    return nil
}

/// "Teams" / "Zoom" / "Meet" from the link's host, else the calendar's name.
public func meetingService(_ url: URL?, calendarTitle: String) -> String {
    let host = url?.host?.lowercased() ?? ""
    if host.hasSuffix("teams.microsoft.com") || host.hasSuffix("teams.live.com") { return "Teams" }
    if host == "zoom.us" || host.hasSuffix(".zoom.us") { return "Zoom" }
    if host == "meet.google.com" { return "Meet" }
    return calendarTitle
}

/// Icon-tile colour (RGB hex) of a meeting banner: Teams, Zoom or Meet only when `service` is
/// exactly what `meetingService` returns for them; a calendar that merely contains the word
/// ("Meetings", "Zoom Room bookings") and anything else gets nil (neutral tile).
public func meetingTintHex(service: String) -> UInt32? {
    switch service {
    case "Teams": return 0x5B5FC7
    case "Zoom": return 0x2D8CFF
    case "Meet": return 0x00897B
    default: return nil
    }
}

/// The hero card's second chip: "Teams · 30 min" (just "30 min" with no service name).
public func meetingChip(_ m: MeetingInfo, calendarTitle: String) -> String {
    let minutes = max(0, Int((m.end.timeIntervalSince(m.start) / 60).rounded()))
    let service = meetingService(m.joinURL, calendarTitle: calendarTitle)
    return service.isEmpty ? "\(minutes) min" : "\(service) · \(minutes) min"
}

// MARK: - Next meeting / countdown

/// How far ahead the hero card looks.
public let nextMeetingWindow: TimeInterval = 12 * 3600

/// The first timed (not all-day) meeting that hasn't ended and starts within 12 h.
public func nextMeeting(_ ms: [MeetingInfo], now: Date) -> MeetingInfo? {
    ms.filter { !$0.allDay && $0.end > now && $0.start.timeIntervalSince(now) <= nextMeetingWindow }
        .min { ($0.start, $0.id) < ($1.start, $1.id) }
}

/// "in 18m", "in 2h 28m", "in 2h"; "now" once the meeting has started.
public func countdownLabel(_ m: MeetingInfo, now: Date) -> String {
    let secs = m.start.timeIntervalSince(now)
    guard secs > 0 else { return "now" }
    let mins = Int((secs / 60).rounded(.up))
    if mins < 60 { return "in \(mins)m" }
    let h = mins / 60, r = mins % 60
    return r == 0 ? "in \(h)h" : "in \(h)h \(r)m"
}

/// The countdown ring's fill (0...1): fills over the last hour before the start, full once started.
public func countdownFraction(_ m: MeetingInfo, now: Date) -> Double {
    let secs = m.start.timeIntervalSince(now)
    if secs <= 0 { return 1 }
    return max(0, min(1, 1 - secs / 3600))
}

/// The next wall-clock minute after `d` (the Calendar tab re-renders then, while visible).
public func nextMinuteBoundary(after d: Date) -> Date {
    let t = d.timeIntervalSince1970
    return Date(timeIntervalSince1970: (t / 60).rounded(.down) * 60 + 60)
}

// MARK: - Sections

public struct CalendarSections: Equatable, Sendable {
    public var hero: MeetingInfo?
    /// The rest of today (not ended), all-day first.
    public var today: [MeetingInfo]
    public var tomorrow: [MeetingInfo]
}

/// Hero = `nextMeeting`; "Later today" and "Tomorrow" hold every other event overlapping that
/// day (a multi-day event shows in both), skipping ones already over and the hero itself.
public func calendarSections(_ ms: [MeetingInfo], now: Date, calendar: Calendar) -> CalendarSections {
    let hero = nextMeeting(ms, now: now)
    let d0 = calendar.startOfDay(for: now)
    let d1 = calendar.date(byAdding: .day, value: 1, to: d0)!
    let d2 = calendar.date(byAdding: .day, value: 1, to: d1)!
    func on(_ from: Date, _ to: Date) -> [MeetingInfo] {
        ms.filter { m in
            m.id != hero?.id && m.end > now && m.start < to && max(m.end, m.start.addingTimeInterval(1)) > from
        }
        .sorted { a, b in
            if a.allDay != b.allDay { return a.allDay }
            return (a.start, a.title, a.id) < (b.start, b.title, b.id)
        }
    }
    return CalendarSections(hero: hero, today: on(d0, d1), tomorrow: on(d1, d2))
}

// MARK: - Reminder

/// One minute before a meeting that has a join link (never for all-day events).
public func reminderTime(_ m: MeetingInfo) -> Date? {
    guard m.joinURL != nil, !m.allDay else { return nil }
    return m.start.addingTimeInterval(-60)
}

/// Decides when the one-shot reminder timer fires and which meetings are due, so each
/// occurrence is reminded once. A moved meeting (new start) is reminded again; a meeting that
/// already started is never reminded (e.g. after wake from sleep).
public struct ReminderPlanner: Sendable {
    private var fired: [String: Date] = [:]

    public init() {}

    private func key(_ m: MeetingInfo) -> String { "\(m.id)|\(m.start.timeIntervalSince1970)" }

    private func candidates(_ ms: [MeetingInfo], now: Date) -> [(meeting: MeetingInfo, at: Date)] {
        ms.compactMap { m in
            guard let r = reminderTime(m), m.start > now, fired[key(m)] == nil else { return nil }
            return (m, max(r, now))
        }
    }

    /// When the timer should fire next (now, if a reminder is already late but the meeting
    /// hasn't started), or nil when nothing needs a reminder.
    public func next(_ ms: [MeetingInfo], now: Date) -> (meeting: MeetingInfo, at: Date)? {
        candidates(ms, now: now).min { ($0.at, $0.meeting.start) < ($1.at, $1.meeting.start) }
    }

    /// Meetings whose reminder is due at `now` (soonest start first).
    public func due(_ ms: [MeetingInfo], now: Date) -> [MeetingInfo] {
        candidates(ms, now: now).filter { $0.at <= now.addingTimeInterval(0.5) }
            .map(\.meeting).sorted { $0.start < $1.start }
    }

    public mutating func markFired(_ m: MeetingInfo) {
        fired[key(m)] = m.start
        // Forget occurrences that ended long ago.
        let cutoff = m.start.addingTimeInterval(-2 * 86400)
        fired = fired.filter { $0.value > cutoff }
    }
}

// MARK: - Attendees

/// "Priya Sharma" → "PS", "Rahul" → "R", "" → "?". E-mail addresses use the part before "@"
/// ("priya.sharma@…" → "PS"); "Sharma, Priya" → "SP".
public func initials(_ name: String) -> String {
    var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let at = s.firstIndex(of: "@") { s = String(s[..<at]) }
    let words = s.components(separatedBy: CharacterSet(charactersIn: " \t\n,._-"))
        .compactMap { w in w.first(where: \.isLetter) }
    guard let first = words.first else { return "?" }
    let out = words.count > 1 ? String([first, words.last!]) : String(first)
    return out.uppercased()
}

/// Up to `max` initials bubbles plus the "+N" count of the rest.
public func attendeeBubbles(_ names: [String], max: Int = 3) -> (initials: [String], extra: Int) {
    (names.prefix(max).map(initials), Swift.max(0, names.count - max))
}

// MARK: - Calendar selection (Settings)

/// `selected == nil` means every calendar.
public func calendarIsOn(_ selected: [String]?, id: String) -> Bool {
    selected?.contains(id) ?? true
}

/// Settings switch for one calendar. Turning one off writes the explicit list; turning the
/// last missing one back on returns to nil (all, so new calendars show too). Ids no longer
/// in `all` are dropped.
public func togglingCalendar(_ selected: [String]?, all: [String], id: String, on: Bool) -> [String]? {
    var set = Set(selected ?? all)
    if on { set.insert(id) } else { set.remove(id) }
    let out = all.filter { set.contains($0) }
    return out.count == all.count && !all.isEmpty ? nil : out
}

// MARK: - Deferred reminder

/// What happened to an offered meeting reminder.
public enum ReminderOfferOutcome: Equatable, Sendable {
    /// On screen, queued behind the pop-up, or the panel is open on the Calendar tab.
    case shown
    /// Blocked by the open panel (another tab) or a pending approval: hold and re-offer later.
    case deferred
    /// Quiet rules or already shown (de-duplicated): gone.
    case dropped
}

/// `openTab` = the tab shown while the panel is open (nil when closed).
public func reminderOfferOutcome(_ d: BannerDecision, ctx: BannerContext, openTab: TabID?) -> ReminderOfferOutcome {
    switch d {
    case .show, .queued: return .shown
    case .dropped:
        if ctx.quiet { return .dropped }
        if ctx.panelOpen && openTab == .calendar { return .shown }
        if ctx.panelOpen || ctx.approvalPending { return .deferred }
        return .dropped
    }
}

/// The single meeting reminder waiting for the panel to close / the approval to resolve.
public struct DeferredReminder: Sendable {
    public private(set) var held: MeetingInfo?
    public init() {}

    /// Keeps `m` (a newer reminder replaces an older held one).
    public mutating func hold(_ m: MeetingInfo) { held = m }

    /// The held reminder if its meeting hasn't started yet; clears it either way.
    public mutating func take(now: Date) -> MeetingInfo? {
        defer { held = nil }
        guard let m = held, m.start > now else { return nil }
        return m
    }
}

// MARK: - Calendar tab polish (AUDIT K1, K3, K7)

/// "30 min", "1 h", "1 h 30 min": the row's trailing meta when there's no Join pill (K1).
public func durationText(_ m: MeetingInfo) -> String {
    let mins = max(0, Int((m.end.timeIntervalSince(m.start) / 60).rounded()))
    if mins < 60 { return "\(mins) min" }
    let h = mins / 60, r = mins % 60
    return r == 0 ? "\(h) h" : "\(h) h \(r) min"
}

/// What sits under the countdown ring's time (K7).
public enum RingCaption: Equatable, Sendable {
    /// The meeting has started.
    case now
    /// "in 17m"; "in 2h" in 24-hour locales when more than an hour away.
    case countdown(String)
    /// More than an hour away in a 12-hour locale: the AM/PM marker, which the ring's time lacks.
    case meridiem(String)
}

public func ringCaption(_ m: MeetingInfo, now: Date, meridiem: String?) -> RingCaption {
    let secs = m.start.timeIntervalSince(now)
    guard secs > 0 else { return .now }
    let mins = Int((secs / 60).rounded(.up))
    if mins < 60 { return .countdown("in \(mins)m") }
    if let mer = meridiem, !mer.isEmpty { return .meridiem(mer) }
    return .countdown("in \(mins / 60)h")
}

/// Stable palette slot (0..<count) for an attendee's initials: the same person keeps the same
/// ring colour in every row and after every relaunch (no `hashValue`, it is randomised).
public func attendeeHueIndex(_ initials: String, count: Int = 6) -> Int {
    var h: UInt32 = 5381
    for u in initials.unicodeScalars { h = h &* 33 &+ u.value }
    return Int(h % UInt32(max(1, count)))
}

/// Empty-state hint (K4): "Showing: Work, Personal · change in Settings". `titles` are the
/// selected calendars' names; more than three collapse to "Work, Personal +2".
public func calendarScopeHint(titles: [String]) -> String {
    var seen = Set<String>()
    let names = titles.filter { !$0.isEmpty && seen.insert($0).inserted }
    if names.isEmpty { return "No calendars selected \u{00B7} change in Settings" }
    let shown = names.prefix(3).joined(separator: ", ")
    let extra = names.count > 3 ? " +\(names.count - 3)" : ""
    return "Showing: \(shown)\(extra) \u{00B7} change in Settings"
}
