import Foundation
import NotchyCore

func runTabCopyChecks() {
    check("clock.short", formatClock(0) == "0:00" && formatClock(49) == "0:49" && formatClock(277) == "4:37")
    check("clock.minutesNoHours", formatClock(3599) == "59:59")
    check("clock.hours", formatClock(3600) == "1:00:00" && formatClock(9130) == "2:32:10")
    check("clock.forcedHours", formatClock(49, hours: true) == "0:00:49" && formatClock(125, hours: true) == "0:02:05")
    check("clock.negativeClamped", formatClock(-5) == "0:00")
    check("shuffle.states", ShuffleAppearance(true) == .on && ShuffleAppearance(false) == .off
          && ShuffleAppearance(nil) == .unsupported)
    check("empty.music", EmptyStateCopy.nothingPlaying.title == "Nothing playing"
          && EmptyStateCopy.nothingPlaying.symbol == "music.note")
    check("empty.claude", EmptyStateCopy.claude(hasPendingCard: false) == .noSessions
          && EmptyStateCopy.claude(hasPendingCard: true) == .noOtherSessions
          && EmptyStateCopy.noSessions.symbol == "sparkle")
}
