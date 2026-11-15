import AppKit
import EventKit
import NotchyCore

/// Today's and tomorrow's events from the Mac's calendars (EventKit), the 1-minute meeting
/// reminder, and the calendar list for Settings. Event-driven: reloads on
/// `.EKEventStoreChanged`, day/time-zone change and when the Calendar tab opens. Timers: one
/// one-shot for the next reminder, and a minute-boundary one-shot only while the Calendar tab
/// is visible (countdown). Event data stays in memory; logs carry counts only.
@MainActor
final class CalendarService: ObservableObject {
    enum Access: Equatable { case notDetermined, denied, granted }

    struct CalendarEntry: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String
        let source: String
    }

    @Published private(set) var access: Access = CalendarService.currentAccess()
    /// Events overlapping today and tomorrow in the selected calendars, sorted by start.
    @Published private(set) var meetings: [MeetingInfo] = []
    /// Every event calendar (for Settings), sorted by source then title.
    @Published private(set) var calendars: [CalendarEntry] = []
    /// The Calendar tab's clock; advanced on minute boundaries while the tab is visible.
    @Published private(set) var now = Date()

    /// Fired when a meeting's reminder is due (only while reminders are on).
    var onReminder: ((MeetingInfo) -> Void)?

    private let store = EKEventStore()
    private var active = false
    private var selectedIDs: [String]?
    private var reminderOn = false
    private var requesting = false
    private var planner = ReminderPlanner()
    private var reminderTimer: Timer?
    private var tickTimer: Timer?
    private var tabVisible = false
    private var observers: [NSObjectProtocol] = []

    // MARK: Settings

    /// Called on launch and whenever settings change. `active` = Calendar tab on or reminder on.
    func apply(active: Bool, selectedIDs: [String]?, reminderOn: Bool) {
#if NOTCHY_CAPTURE
        return
#endif
        let selectionChanged = selectedIDs != self.selectedIDs
        self.selectedIDs = selectedIDs
        self.reminderOn = reminderOn
        if active != self.active {
            self.active = active
            if active { start() } else { stop() }
        } else if active && selectionChanged {
            reload()
        } else {
            scheduleReminder()
        }
    }

    private func start() {
        let nc = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
                     NSLocale.currentLocaleDidChangeNotification] {
            let obj: AnyObject? = name == .EKEventStoreChanged ? store : nil
            let formatChange = name == .NSSystemTimeZoneDidChange || name == NSLocale.currentLocaleDidChangeNotification
            observers.append(nc.addObserver(forName: name, object: obj, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if formatChange { TimeText.reset() }
                    self?.reload()
                }
            })
        }
        // Wake from sleep: the reminder timer may be stale; recompute.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        refreshAccess(request: true)
    }

    func stop() {
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        reminderTimer?.invalidate()
        reminderTimer = nil
        tickTimer?.invalidate()
        tickTimer = nil
        active = false
        meetings = []
    }

    // MARK: Access

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied // denied, restricted, write-only
        }
    }

    /// Re-reads the authorization status (the user may have changed it in System Settings),
    /// asks once when it was never asked, and reloads.
    private func refreshAccess(request: Bool) {
        let a = Self.currentAccess()
        if a != access {
            access = a
            notchyLog.notice("Calendar: access \(String(describing: a), privacy: .public)")
        }
        if a == .notDetermined && request { requestAccess(); return }
        reload()
    }

    /// Shows macOS's "Notchy would like to access your calendars" prompt (only when never asked).
    func requestAccess() {
#if NOTCHY_CAPTURE
        return
#endif
        guard Self.currentAccess() == .notDetermined, !requesting else { refreshAccess(request: false); return }
        requesting = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.requesting = false
                    notchyLog.notice("Calendar: access request answered: \(granted)")
                    if granted { self.store.reset() }
                    self.refreshAccess(request: false)
                }
            }
        }
    }

    /// Names of the calendars the tab shows (for the empty state's hint). Names only, never logged.
    var selectedCalendarTitles: [String] {
        calendars.filter { calendarIsOn(selectedIDs, id: $0.id) }.map(\.title)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Calendar tab became visible (live copy): re-check access, reload, tick the countdown.
    func tabOpened() {
#if NOTCHY_CAPTURE
        tabVisible = true
        return // the harness owns the demo clock
#endif
        tabVisible = true
        now = Date()
        if active { refreshAccess(request: false) }
        scheduleTick()
    }

    func tabClosed() {
        tabVisible = false
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: Loading

    func reload() {
        guard active else { return }
        now = Date()
        // Access can be revoked in System Settings while Notchy runs.
        let a = Self.currentAccess()
        if a != access {
            access = a
            notchyLog.notice("Calendar: access \(String(describing: a), privacy: .public)")
        }
        guard access == .granted else {
            if !meetings.isEmpty { meetings = [] }
            if !calendars.isEmpty { calendars = [] }
            scheduleReminder()
            return
        }
        let all = store.calendars(for: .event)
        let entries = all.map {
            CalendarEntry(id: $0.calendarIdentifier, title: $0.title,
                          colorHex: hexString($0.cgColor), source: $0.source?.title ?? "Other")
        }
        .sorted { ($0.source.localizedLowercase, $0.title.localizedLowercase)
                < ($1.source.localizedLowercase, $1.title.localizedLowercase) }
        if entries != calendars {
            calendars = entries
            // Counts per account type only (no names): helps when a calendar seems missing.
            let kinds = Dictionary(grouping: all, by: { sourceKind($0.source?.sourceType) })
                .map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
            notchyLog.notice("Calendar: calendars by account type: \(kinds, privacy: .public)")
        }

        let chosen = all.filter { calendarIsOn(selectedIDs, id: $0.calendarIdentifier) }
        var out: [MeetingInfo] = []
        if !chosen.isEmpty {
            let cal = Calendar.current
            let d0 = cal.startOfDay(for: now)
            let d2 = cal.date(byAdding: .day, value: 2, to: d0)!
            let pred = store.predicateForEvents(withStart: d0, end: d2, calendars: chosen)
            out = store.events(matching: pred)
                .filter { $0.status != .canceled }
                .map(meetingInfo)
                .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }
        if out != meetings { meetings = out }
        notchyLog.notice("Calendar: \(out.count) events in \(chosen.count)/\(all.count) calendars")
        scheduleReminder()
    }

    private func meetingInfo(_ e: EKEvent) -> MeetingInfo {
        let attendees = (e.attendees ?? [])
            .filter { !$0.isCurrentUser && $0.participantType != .room && $0.participantType != .resource }
            .compactMap { p -> String? in
                if let n = p.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
                let s = p.url.absoluteString
                return s.hasPrefix("mailto:") ? String(s.dropFirst(7)) : nil
            }
        let title = e.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let start = e.startDate ?? Date.distantPast
        return MeetingInfo(
            id: "\(e.calendar?.calendarIdentifier ?? "")|\(e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString)|\(start.timeIntervalSince1970)",
            title: title.isEmpty ? "No title" : title,
            start: start,
            end: max(e.endDate ?? start, start),
            allDay: e.isAllDay,
            calendarColorHex: hexString(e.calendar?.cgColor),
            joinURL: joinLink(url: e.url?.absoluteString, notes: e.notes, location: e.location),
            attendees: attendees,
            calendarTitle: e.calendar?.title ?? "")
    }

    // MARK: Timers

    /// The one reminder timer: fires at the next due reminder (rescheduled on every reload).
    private func scheduleReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        guard active, reminderOn, access == .granted,
              let next = planner.next(meetings, now: Date()) else { return }
        let t = Timer(fire: next.at, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reminderFired() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        reminderTimer = t
    }

    private func reminderFired() {
        reminderTimer = nil
        let due = planner.due(meetings, now: Date())
        for m in due { planner.markFired(m) }
        notchyLog.notice("Calendar: \(due.count) meeting reminder(s) due")
        // Newest banner wins anyway: show the soonest meeting last so it stays up.
        if reminderOn { for m in due.reversed() { onReminder?(m) } }
        scheduleReminder()
    }

    /// Minute-boundary one-shot, only while the Calendar tab is visible.
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard tabVisible else { return }
        let t = Timer(fire: nextMinuteBoundary(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tabVisible else { return }
                self.now = Date()
                self.scheduleTick()
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }
}

private func sourceKind(_ t: EKSourceType?) -> String {
    switch t {
    case .local?: return "local"
    case .exchange?: return "exchange"
    case .calDAV?: return "caldav"
    case .mobileMe?: return "icloud"
    case .subscribed?: return "subscribed"
    case .birthdays?: return "birthdays"
    default: return "other"
    }
}

/// "#RRGGBB" for a calendar colour (blue when unknown).
private func hexString(_ c: CGColor?) -> String {
    guard let c, let ns = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return "#0A84FF" }
    let r = Int((ns.redComponent * 255).rounded()), g = Int((ns.greenComponent * 255).rounded())
    let b = Int((ns.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}

#if NOTCHY_CAPTURE
/// Capture build only: demo meetings and calendars (EventKit is never read).
extension CalendarService {
    func captureSet(meetings: [MeetingInfo], now: Date, calendars: [CalendarEntry]) {
        access = .granted
        self.meetings = meetings
        self.calendars = calendars
        self.now = now
    }
}
#endif
