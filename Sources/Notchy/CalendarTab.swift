import SwiftUI
import NotchyCore

/// Calendar tab (mockup view 5): the next meeting as a hero card (countdown ring, title chip,
/// "<service> · N min" chip, attendee initials, white Join), then "Later today" and "Tomorrow"
/// rows with small Join pills. No access → one "Allow calendar access" row.
struct CalendarTab: View {
    @ObservedObject var service: CalendarService
    let live: Bool

    /// Rows shown before the lists scroll (keeps the panel height bounded).
    private static let visibleRows = 6
    private static let rowHeight = Palette.Space.calendarRow
    /// Section header: 22 pt block + 4 pt below (AUDIT K2).
    private static let headerBlock: CGFloat = 26

    var body: some View {
        content
            .onAppear { if live { service.tabOpened() } }
            .onDisappear { if live { service.tabClosed() } }
    }

    @ViewBuilder private var content: some View {
        switch service.access {
        case .granted:
            let s = calendarSections(service.meetings, now: service.now, calendar: .current)
            VStack(alignment: .leading, spacing: 0) {
                if let hero = s.hero {
                    HeroCard(meeting: hero, now: service.now, live: live) { if live { open(hero.joinURL) } }
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                let rowCount = s.today.count + s.tomorrow.count
                if s.hero == nil && rowCount == 0 {
                    EmptyState(copy: .noMeetings(hint: calendarScopeHint(titles: service.selectedCalendarTitles)),
                               live: live)
                } else if rowCount > Self.visibleRows {
                    ScrollView(.vertical, showsIndicators: false) { lists(s) }
                        .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight + 2 * Self.headerBlock)
                } else {
                    lists(s)
                }
            }
        case .denied, .notDetermined:
            AllowCalendarRow(denied: service.access == .denied) {
                guard live else { return }
                if service.access == .denied { service.openPrivacySettings() } else { service.requestAccess() }
            }
        }
    }

    @ViewBuilder private func lists(_ s: CalendarSections) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !s.today.isEmpty { section(s.hero == nil ? "TODAY" : "LATER TODAY", s.today) }
            if !s.tomorrow.isEmpty { section("TOMORROW", s.tomorrow) }
        }
    }

    private func section(_ title: String, _ items: [MeetingInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Palette.TypeScale.caption)
                .tracking(0.6)
                .foregroundStyle(Palette.panelSecondary)
                .frame(height: 22, alignment: .bottom)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Rectangle().fill(Palette.separator).frame(height: 1) }
                EventRow(meeting: m) { if live { open(m.joinURL) } }
                    .frame(height: Self.rowHeight - (i > 0 ? 1 : 0))
            }
        }
    }

    private func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    let meeting: MeetingInfo
    let now: Date
    var live: Bool = true
    let onJoin: () -> Void

    var body: some View {
        let bubbles = attendeeBubbles(meeting.attendees)
        HStack(spacing: 12) {
            CountdownRing(meeting: meeting, now: now, live: live)
            VStack(alignment: .leading, spacing: 4) {
                titleChip(meeting.title)
                // K6: plain secondary text, no second filled bar.
                Text(meetingChip(meeting, calendarTitle: meeting.calendarTitle))
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(Palette.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 22 + 4 + 28 = 54: the same height as the ring.
            VStack(alignment: .trailing, spacing: 4) {
                if !bubbles.initials.isEmpty {
                    AttendeeBubbles(initials: bubbles.initials, extra: bubbles.extra)
                }
                if meeting.joinURL != nil {
                    Button(action: onJoin) {
                        Text("Join").whitePill()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Join \(meeting.title)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func titleChip(_ text: String) -> some View {
        Text(text)
            .font(Palette.TypeScale.body)
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous).fill(Palette.heroBox))
    }
}

private struct CountdownRing: View {
    let meeting: MeetingInfo
    let now: Date
    /// False in the hidden measuring copy: never pulses.
    var live: Bool = true
    @Environment(\.notchReduceMotion) private var reduceMotion
    /// AUDIT Y3: the ring pulses 1.0 → 1.04 → 1.0 once when its meeting turns "now" (or the
    /// tab opens on a "now" meeting); static under Reduce Motion. `@State` macro unavailable.
    private let scaleState = State(initialValue: CGFloat(1))

    var body: some View {
        let caption = ringCaption(meeting, now: now, meridiem: TimeText.meridiem(meeting.start))
        let isNow = caption == .now
        ring(caption: caption, isNow: isNow)
            .scaleEffect(scaleState.wrappedValue)
            .onAppear { if isNow { pulseOnce() } }
            .onChange(of: isNow) { _, n in if n { pulseOnce() } }
    }

    private func pulseOnce() {
        let peak = CGFloat(nowRingPulsePeak(reduceMotion: reduceMotion))
        guard live, peak != 1 else { return }
        withAnimation(.easeOut(duration: 0.2)) { scaleState.wrappedValue = peak }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeIn(duration: 0.2)) { scaleState.wrappedValue = 1 }
        }
    }

    private func ring(caption: RingCaption, isNow: Bool) -> some View {
        ZStack {
            Circle().stroke(Palette.panelPill, lineWidth: 3)
            Circle()
                .trim(from: 0, to: countdownFraction(meeting, now: now))
                .stroke(isNow ? Palette.switchOn : Palette.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(TimeText.ring(meeting.start))
                    .font(Palette.TypeScale.numeral)
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7) // 13 pt x 0.7 = 9.1 pt: stays above the 9 pt floor
                    .lineLimit(1)
                captionView(caption)
            }
            .padding(.horizontal, 5)
        }
        .frame(width: 54, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starts \(TimeText.row(meeting.start)), \(countdownLabel(meeting, now: now))")
    }

    /// Never below 9 pt (`minimumScaleFactor` 0.9 of 10 pt). "now" is also carried by a filled
    /// dot and heavier weight, not only by the green ring (AUDIT K7 + colour-only review note).
    @ViewBuilder private func captionView(_ c: RingCaption) -> some View {
        switch c {
        case .now:
            HStack(spacing: 3) {
                Circle().fill(Palette.switchOn).frame(width: 5, height: 5)
                Text("now").font(.system(size: 10, weight: .bold)).foregroundColor(Palette.switchOn)
                    .lineLimit(1).minimumScaleFactor(0.9)
            }
        case .countdown(let t):
            Text(t).font(Palette.TypeScale.caption).foregroundStyle(Palette.panelSecondary)
                .lineLimit(1).minimumScaleFactor(0.9)
        case .meridiem(let t):
            // The audit asks for 8 pt; the 9 pt floor (X1) wins.
            Text(t).font(.system(size: Palette.TypeScale.minimumSize, weight: .semibold))
                .foregroundStyle(Palette.panelSecondary).lineLimit(1)
        }
    }
}

private struct AttendeeBubbles: View {
    let initials: [String]
    let extra: Int
    /// Ring colours (hash of the initials picks one), drawn at 60 % over a white 18 % fill.
    private static let rings: [Color] = [Color(hex: 0xFFD60A), Color(hex: 0x30D158), Color(hex: 0x64D2FF),
                                         Color(hex: 0xFF9F0A), Color(hex: 0xBF5AF2), Color(hex: 0xFF6482)]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(initials.enumerated()), id: \.offset) { i, s in
                bubble(s, ring: Self.rings[attendeeHueIndex(s, count: Self.rings.count)],
                       covered: i < initials.count - 1 || extra > 0)
            }
            if extra > 0 { bubble("+\(extra)", ring: nil, covered: false) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(initials.count + extra) attendees")
    }

    /// 22 pt, 9 pt semibold initials, 2 pt black stroke (separates the overlap). The next bubble
    /// covers the right 6 pt of a `covered` one, so its initials sit 3 pt left to stay clear.
    private func bubble(_ t: String, ring: Color?, covered: Bool) -> some View {
        Text(t).font(.system(size: Palette.TypeScale.minimumSize, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .offset(x: covered ? -3 : 0)
            .frame(width: 22, height: 22)
            .background(
                ZStack {
                    Circle().fill(Palette.avatarBase)
                    Circle().fill(Color.white.opacity(ring == nil ? 0.12 : 0.18))
                    if let ring { Circle().inset(by: 2).stroke(ring.opacity(0.6), lineWidth: 1) }
                }
            )
            .overlay(Circle().strokeBorder(Palette.avatarBase, lineWidth: 2))
    }
}

// MARK: - Rows

private struct EventRow: View {
    let meeting: MeetingInfo
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // K1: start time only in a 64 pt column; the duration moves to the trailing meta.
            Text(meeting.allDay ? "All day" : TimeText.row(meeting.start))
                .font(Palette.TypeScale.meta.monospacedDigit())
                .foregroundStyle(Palette.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82) // 11 pt x 0.82 = 9 pt floor
                .frame(width: 64, alignment: .leading)
                .accessibilityLabel(meeting.allDay ? "All day"
                                    : "\(TimeText.row(meeting.start)) to \(TimeText.row(meeting.end))")
            Circle()
                .fill(Color(hexString: meeting.calendarColorHex) ?? Palette.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(meeting.title)
                .font(Palette.TypeScale.body)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if meeting.joinURL == nil && !meeting.allDay {
                Text(durationText(meeting))
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(Palette.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if meeting.joinURL != nil {
                Button(action: onJoin) {
                    // AUDIT Y1: a 22 pt pill inside a 28 pt hit area.
                    Text("Join")
                        .font(Palette.TypeScale.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(Palette.panelPill))
                        .frame(minWidth: CGFloat(minimumHitSize), minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(meeting.title)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AllowCalendarRow: View {
    let denied: Bool
    let onAllow: () -> Void

    var body: some View {
        let copy = CalendarAccessCopy.make(denied: denied)
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(Palette.TypeScale.meta).foregroundStyle(Palette.panelSecondary)
            Text(copy.message)
                .font(Palette.TypeScale.secondary).foregroundStyle(Palette.panelSecondary).lineLimit(1)
            Spacer(minLength: 6)
            Button(action: onAllow) {
                Text(copy.button).whitePill()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

/// Times in the user's 12/24-hour preference; the ring drops the AM/PM marker to fit.
@MainActor
enum TimeText {
    private static var rowFormatter = makeRow()
    private static var ringFormatter = makeRing()
    private static var meridiemFormatter = makeMeridiem()

    private static func makeMeridiem() -> DateFormatter {
        let f = makeRow()
        f.dateFormat = "a"
        return f
    }

    private static func makeRow() -> DateFormatter {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("jjmm")
        return f
    }

    private static func makeRing() -> DateFormatter {
        let f = makeRow()
        f.dateFormat = f.dateFormat.replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        return f
    }

    /// Locale (12/24-hour) or time zone changed: rebuild the formats.
    static func reset() {
        rowFormatter = makeRow()
        ringFormatter = makeRing()
        meridiemFormatter = makeMeridiem()
    }

    static func row(_ d: Date) -> String { rowFormatter.string(from: d) }
    static func ring(_ d: Date) -> String { ringFormatter.string(from: d) }
    /// "AM"/"PM" in 12-hour locales, nil in 24-hour ones (the ring shows it under the time).
    static func meridiem(_ d: Date) -> String? {
        rowFormatter.dateFormat.contains("a") ? meridiemFormatter.string(from: d) : nil
    }
}
