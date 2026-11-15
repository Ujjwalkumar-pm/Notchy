import Foundation
import NotchyCore

func runCalendarChecks() {
    // Fixed clock and calendar so the checks don't depend on the Mac's time zone.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10, minute: 42))!
    func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: dayOffset, to: today)!
        return cal.date(bySettingHour: h, minute: m, second: 0, of: d)!
    }
    func meeting(_ id: String, _ start: Date, minutes: Double = 30, allDay: Bool = false,
                 link: Bool = true, attendees: [String] = []) -> MeetingInfo {
        MeetingInfo(id: id, title: "M \(id)", start: start, end: start.addingTimeInterval(minutes * 60),
                    allDay: allDay, calendarColorHex: "#0A84FF",
                    joinURL: link ? URL(string: "https://teams.microsoft.com/l/meetup-join/abc") : nil,
                    attendees: attendees)
    }

    // MARK: joinLink
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%7d"
    let zoom = "https://us02web.zoom.us/j/81234567890?pwd=abcDEF"
    let meet = "https://meet.google.com/abc-defg-hij"
    check("join.teams", joinLink(url: nil, notes: nil, location: teams)?.absoluteString == teams)
    check("join.zoom", joinLink(url: zoom, notes: nil, location: nil)?.absoluteString == zoom
          && joinLink(url: nil, notes: "Join: https://zoom.us/j/123456", location: nil)?.absoluteString
             == "https://zoom.us/j/123456")
    check("join.meet", joinLink(url: nil, notes: nil, location: "Google Meet: \(meet)")?.absoluteString == meet)
    check("join.notesOnly", joinLink(url: nil, notes: "Agenda\n\nJoin the meeting now <\(teams)>\nMeeting ID: 123",
                                     location: "Room 4")?.absoluteString == teams)
    check("join.none", joinLink(url: "https://example.com/doc", notes: "See https://zoom.us/pricing",
                                location: "Conference Room") == nil
          && joinLink(url: nil, notes: nil, location: nil) == nil
          && joinLink(url: "", notes: "", location: "") == nil)
    check("join.prefersURLField", joinLink(url: zoom, notes: "Join: \(teams)", location: meet)?.absoluteString == zoom
          && joinLink(url: nil, notes: "Join: \(teams)", location: meet)?.absoluteString == meet)
    check("join.trailingPunctuation", joinLink(url: nil, notes: "Link: \(meet).", location: nil)?.absoluteString == meet
          && joinLink(url: nil, notes: "(\(meet))", location: nil)?.absoluteString == meet)
    let safe = "https://nam12.safelinks.protection.outlook.com/?url=" + teams.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        + "&data=05%7C01%7Cx&reserved=0"
    check("join.safeLinks", joinLink(url: nil, notes: "Join here <\(safe)>", location: nil)?.absoluteString == teams
          && joinLink(url: nil, notes: "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2F&data=1",
                      location: nil) == nil)
    check("join.httpRejected", joinLink(url: "http://meet.google.com/abc-defg-hij", notes: nil, location: nil) == nil)

    // MARK: nextMeeting
    do {
        let ms = [meeting("allday", at(0), minutes: 24 * 60, allDay: true), meeting("a", at(11))]
        check("next.skipsAllDay", nextMeeting(ms, now: today)?.id == "a")
    }
    do {
        let ms = [meeting("past", at(9)), meeting("running", at(10, 30)), meeting("later", at(11))]
        check("next.inProgressCounts", nextMeeting(ms, now: today)?.id == "running")
    }
    do {
        let ms = [meeting("far", today.addingTimeInterval(12 * 3600 + 60))]
        check("next.nothingSoon", nextMeeting(ms, now: today) == nil && nextMeeting([], now: today) == nil)
    }
    do {
        // Unsorted input: earliest start wins.
        let ms = [meeting("b", at(15)), meeting("a", at(11))]
        check("next.unsorted", nextMeeting(ms, now: today)?.id == "a")
    }

    // MARK: reminderTime
    let m11 = meeting("a", at(11))
    check("reminder.oneMinute", reminderTime(m11) == at(11).addingTimeInterval(-60))
    check("reminder.noLinkNil", reminderTime(meeting("x", at(11), link: false)) == nil
          && reminderTime(meeting("d", at(0), minutes: 1440, allDay: true)) == nil)

    // MARK: ReminderPlanner
    do {
        var p = ReminderPlanner()
        let ms = [meeting("b", at(15)), m11, meeting("nolink", at(10, 50), link: false)]
        let first = p.next(ms, now: today)
        check("planner.nextFire", first?.meeting.id == "a" && first?.at == at(10, 59))
        // Fires once: at fire time it's due; after marking, the next one is the 15:00 meeting.
        let due = p.due(ms, now: at(10, 59))
        due.forEach { p.markFired($0) }
        check("planner.firesOnce", due.map(\.id) == ["a"] && p.due(ms, now: at(10, 59).addingTimeInterval(30)).isEmpty
              && p.next(ms, now: at(10, 59).addingTimeInterval(30))?.meeting.id == "b")
    }
    do {
        // Launched 30 s before the start: still reminds (at once); after the start: never.
        var p = ReminderPlanner()
        let late = today.addingTimeInterval(0)
        let m = meeting("soon", late.addingTimeInterval(30))
        check("planner.lateLaunch", p.next([m], now: late)?.at == late && p.due([m], now: late).map(\.id) == ["soon"])
        check("planner.startedNoReminder", p.next([m], now: late.addingTimeInterval(31)) == nil
              && p.due([m], now: late.addingTimeInterval(31)).isEmpty)
        p.markFired(m)
        check("planner.markedNoNext", p.next([m], now: late) == nil)
    }
    do {
        // Meeting moved to a new time: reminds again for the new time.
        var p = ReminderPlanner()
        p.markFired(m11)
        let moved = meeting("a", at(14))
        check("planner.movedRearms", p.next([moved], now: today)?.at == at(13, 59))
    }

    // MARK: deferred reminder
    do {
        let shownB = Banner(id: "meeting:a", kind: .meeting, title: "t", subtitle: "s", actionLabel: "Join", tab: .calendar)
        let open = BannerContext(panelOpen: true)
        check("defer.openOtherTab", reminderOfferOutcome(.dropped, ctx: open, openTab: .music) == .deferred)
        check("defer.approvalPending", reminderOfferOutcome(.dropped, ctx: BannerContext(approvalPending: true), openTab: nil) == .deferred)
        check("defer.openOnCalendar", reminderOfferOutcome(.dropped, ctx: open, openTab: .calendar) == .shown)
        check("defer.quietDropped", reminderOfferOutcome(.dropped, ctx: BannerContext(panelOpen: true, quiet: true), openTab: .music) == .dropped
              && reminderOfferOutcome(.dropped, ctx: BannerContext(), openTab: nil) == .dropped)
        check("defer.shownOrQueued", reminderOfferOutcome(.show(shownB), ctx: BannerContext(), openTab: nil) == .shown
              && reminderOfferOutcome(.queued, ctx: BannerContext(popupShowing: true), openTab: nil) == .shown)
        // Deferred while open, then the panel closes before the start → offered once.
        var d = DeferredReminder()
        d.hold(m11)
        check("defer.closedOffered", d.take(now: at(10, 59).addingTimeInterval(20))?.id == "a" && d.take(now: at(10, 59)) == nil)
        // The meeting started meanwhile → discarded.
        d.hold(m11)
        check("defer.startedDiscarded", d.take(now: at(11, 0).addingTimeInterval(5)) == nil && d.held == nil)
        // End to end with the arbiter: blocked while open, shown after close.
        var arb = BannerArbiter()
        let first = arb.offer(shownB, ctx: open, now: at(10, 59))
        var d2 = DeferredReminder()
        if reminderOfferOutcome(first, ctx: open, openTab: .claude) == .deferred { d2.hold(m11) }
        let again = d2.take(now: at(10, 59).addingTimeInterval(10)).map { _ in
            arb.offer(shownB, ctx: BannerContext(), now: at(10, 59).addingTimeInterval(10)) }
        check("defer.arbiterReoffer", first == .dropped && again == .show(shownB))
    }

    // MARK: initials
    check("initials.twoWords", initials("Priya Sharma") == "PS" && initials("priya k sharma") == "PS")
    check("initials.single", initials("Rahul") == "R")
    check("initials.empty", initials("") == "?" && initials("   ") == "?")
    check("initials.email", initials("priya.sharma@example.com") == "PS")
    check("initials.lastFirst", initials("Sharma, Priya") == "SP")

    // MARK: attendees / labels
    do {
        let b = attendeeBubbles(["Priya Sharma", "Rahul M", "Anil", "Bea", "Cy"])
        let b2 = attendeeBubbles(["Priya Sharma"])
        check("attendees.capThree", b.initials == ["PS", "RM", "A"] && b.extra == 2
              && b2.initials == ["PS"] && b2.extra == 0 && attendeeBubbles([]).initials.isEmpty)
    }
    check("service.fromHost",
          meetingService(URL(string: teams), calendarTitle: "Work") == "Teams"
          && meetingService(URL(string: zoom), calendarTitle: "Work") == "Zoom"
          && meetingService(URL(string: meet), calendarTitle: "Work") == "Meet"
          && meetingService(nil, calendarTitle: "Work") == "Work")
    check("service.chip", meetingChip(m11, calendarTitle: "Work") == "Teams · 30 min"
          && meetingChip(meeting("n", at(11), minutes: 90, link: false), calendarTitle: "") == "90 min")
    check("countdown.labels",
          countdownLabel(m11, now: today) == "in 18m"
          && countdownLabel(m11, now: at(10, 59).addingTimeInterval(1)) == "in 1m"
          && countdownLabel(m11, now: at(11, 5)) == "now"
          && countdownLabel(meeting("x", at(13, 10)), now: today) == "in 2h 28m"
          && countdownLabel(meeting("y", at(12, 42)), now: today) == "in 2h")

    // MARK: Calendar tab polish (K1, K3, K4, K5, K7)
    check("duration.text", durationText(m11) == "30 min"
          && durationText(meeting("d1", at(11), minutes: 60, link: false)) == "1 h"
          && durationText(meeting("d2", at(11), minutes: 90, link: false)) == "1 h 30 min")
    check("ring.captionNowAndMinutes", ringCaption(m11, now: at(11, 5), meridiem: "AM") == .now
          && ringCaption(m11, now: today, meridiem: "AM") == .countdown("in 18m"))
    check("ring.captionMeridiemOverAnHour", ringCaption(meeting("x", at(13, 10)), now: today, meridiem: "PM") == .meridiem("PM")
          && ringCaption(meeting("x", at(13, 10)), now: today, meridiem: nil) == .countdown("in 2h")
          && ringCaption(meeting("x", at(13, 10)), now: today, meridiem: "") == .countdown("in 2h"))
    check("attendee.hueStable", attendeeHueIndex("PS") == attendeeHueIndex("PS")
          && (0..<6).contains(attendeeHueIndex("RM")))
    check("scope.hint", calendarScopeHint(titles: ["Work", "Personal", "Work"]) == "Showing: Work, Personal \u{00B7} change in Settings"
          && calendarScopeHint(titles: ["A", "B", "C", "D", "E"]) == "Showing: A, B, C +2 \u{00B7} change in Settings"
          && calendarScopeHint(titles: []) == "No calendars selected \u{00B7} change in Settings")
    check("empty.noMeetings", EmptyStateCopy.noMeetings(hint: "h").symbol == "calendar"
          && EmptyStateCopy.noMeetings(hint: "h").title == "No meetings today or tomorrow")
    check("access.copy", CalendarAccessCopy.make(denied: true).message == "Calendar access is off"
          && CalendarAccessCopy.make(denied: true).button == "Open Settings\u{2026}"
          && CalendarAccessCopy.make(denied: false).message == "See your next meeting here"
          && CalendarAccessCopy.make(denied: false).button == "Allow\u{2026}")

    // MARK: sections
    do {
        let ms = [
            meeting("hol", at(0), minutes: 24 * 60, allDay: true),
            meeting("past", at(9)),
            m11,
            meeting("design", at(15), minutes: 60),
            meeting("t1", at(10, dayOffset: 1)),
            meeting("t-allday", at(0, dayOffset: 1), minutes: 24 * 60, allDay: true),
            meeting("dayafter", at(9, dayOffset: 2)),
        ]
        let s = calendarSections(ms, now: today, calendar: cal)
        check("sections.split", s.hero?.id == "a" && s.today.map(\.id) == ["hol", "design"]
              && s.tomorrow.map(\.id) == ["t-allday", "t1"])
        // Late evening: hero is tomorrow's first meeting and is not repeated in Tomorrow.
        let late = at(23)
        let s2 = calendarSections(ms, now: late, calendar: cal)
        check("sections.heroTomorrow", s2.hero?.id == "t1" && s2.today.map(\.id) == ["hol"]
              && s2.tomorrow.map(\.id) == ["t-allday"])
        let empty = calendarSections([], now: today, calendar: cal)
        check("sections.empty", empty.hero == nil && empty.today.isEmpty && empty.tomorrow.isEmpty)
        // Multi-day timed event (22:00 today → 02:00 tomorrow) shows in both days.
        let overnight = meeting("night", at(22), minutes: 240, link: false)
        let s3 = calendarSections([m11, overnight], now: today, calendar: cal)
        check("sections.multiDay", s3.today.map(\.id) == ["night"] && s3.tomorrow.map(\.id) == ["night"])
    }

    // MARK: calendar selection
    let all = ["a", "b", "c"]
    check("calsel.offWritesList", togglingCalendar(nil, all: all, id: "b", on: false) == ["a", "c"])
    check("calsel.allOnIsNil", togglingCalendar(["a", "c"], all: all, id: "b", on: true) == nil)
    check("calsel.dropsStale", togglingCalendar(["a", "gone"], all: all, id: "c", on: true) == ["a", "c"])
    check("calsel.isOn", calendarIsOn(nil, id: "x") && calendarIsOn(["a"], id: "a") && !calendarIsOn(["a"], id: "b"))

    // MARK: minute boundary
    let mid = Date(timeIntervalSince1970: 1_800_000_030.5)
    check("tick.nextMinute", nextMinuteBoundary(after: mid) == Date(timeIntervalSince1970: 1_800_000_060)
          && nextMinuteBoundary(after: Date(timeIntervalSince1970: 1_800_000_060)) == Date(timeIntervalSince1970: 1_800_000_120))
}
