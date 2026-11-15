import Foundation

/// "m:ss", or "h:mm:ss" when `hours` is set (AUDIT M7). Callers pass `hours: duration >= 3600`
/// so both clocks of one track use the same shape.
public func formatClock(_ seconds: Double, hours: Bool = false) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    if hours || s >= 3600 {
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// How the shuffle control is drawn (AUDIT M3): `unsupported` (the player reports no shuffle
/// mode) hides the button and keeps a spacer so the row stays symmetric.
public enum ShuffleAppearance: Equatable, Sendable {
    case on, off, unsupported
    public init(_ shuffle: Bool?) {
        switch shuffle {
        case true?: self = .on
        case false?: self = .off
        case nil: self = .unsupported
        }
    }
}

/// Copy for the shared empty state (AUDIT M4, C2).
public struct EmptyStateCopy: Equatable, Sendable {
    public let symbol: String
    public let title: String
    public let hint: String

    public static let nothingPlaying = EmptyStateCopy(
        symbol: "music.note", title: "Nothing playing",
        hint: "Play something in Music, Spotify or your browser")
    public static let noSessions = EmptyStateCopy(
        symbol: "sparkle", title: "No Claude sessions",
        hint: "Start Claude Code in a terminal \u{2014} sessions and approvals appear here")
    public static let noAlerts = EmptyStateCopy(
        symbol: "bell", title: "You\u{2019}re all caught up",
        hint: "Teams & Outlook banners and device events land here")
    public static let noOtherSessions = EmptyStateCopy(
        symbol: "sparkle", title: "No other sessions",
        hint: "Other Claude Code sessions appear here")

    /// Calendar tab with nothing today or tomorrow (AUDIT K4); `hint` names the calendars shown.
    public static func noMeetings(hint: String) -> EmptyStateCopy {
        EmptyStateCopy(symbol: "calendar", title: "No meetings today or tomorrow", hint: hint)
    }

    /// Claude tab: the approval card already shows its own session.
    public static func claude(hasPendingCard: Bool) -> EmptyStateCopy {
        hasPendingCard ? noOtherSessions : noSessions
    }
}

/// Calendar tab when it can't read calendars (AUDIT K5): the button says what it will do.
public struct CalendarAccessCopy: Equatable, Sendable {
    public let message: String
    public let button: String

    public static func make(denied: Bool) -> CalendarAccessCopy {
        denied ? CalendarAccessCopy(message: "Calendar access is off", button: "Open Settings\u{2026}")
               : CalendarAccessCopy(message: "See your next meeting here", button: "Allow\u{2026}")
    }
}
