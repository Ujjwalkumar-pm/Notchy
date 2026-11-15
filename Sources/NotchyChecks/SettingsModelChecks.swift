import Foundation
import NotchyCore

func runSettingsModelChecks() {
    let all: [TabID] = [.music, .claude, .alerts, .calendar]
    let d = NotchySettings.defaults

    check("settings.defaultsOrder",
          d.tabOrder == all && d.enabledTabs == Set(all) && visibleTabs(d) == all
          && d.watchedApps == ["Microsoft Outlook", "Microsoft Teams"] && d.theme == .black
          && d.accentHex == "#7AA7FF" && d.selectedCalendarIDs == nil && d.lastTab == nil)

    // Unreadable data = someone used Notchy before: defaults, but the welcome counts as seen.
    var seen = d
    seen.hasSeenWelcome = true
    check("settings.corruptJSON", decodeSettings(Data("{".utf8)) == seen && decodeSettings(nil) == d)

    var glass = seen
    glass.theme = .glass
    check("settings.missingKeys", decodeSettings(Data(#"{"theme":"glass"}"#.utf8)) == glass)

    check("settings.wrongType",
          decodeSettings(Data(##"{"theme":5,"alertBanners":"x","accentHex":"#112233"}"##.utf8)).accentHex == "#112233"
          && decodeSettings(Data(#"{"theme":5}"#.utf8)).theme == .black)

    let unknown = decodeSettings(Data(#"{"tabOrder":["music","weather"]}"#.utf8))
    check("settings.unknownTab", unknown.tabOrder == all)

    check("settings.enabledEmptyIsAll",
          decodeSettings(Data(#"{"enabledTabs":[]}"#.utf8)).enabledTabs == Set(all)
          && decodeSettings(Data(#"{"enabledTabs":["weather"]}"#.utf8)).enabledTabs == Set(all))

    var s = d
    s.lastTab = .calendar
    s.enabledTabs = [.claude, .calendar]
    check("settings.lastTabVisible", openingTab(s) == .calendar)
    s.enabledTabs = [.claude, .alerts]
    check("settings.lastTabDisabled", openingTab(s) == .claude)
    s.lastTab = nil
    check("settings.noLastTab", openingTab(s) == .claude)

    var only = d
    only.enabledTabs = [.music]
    check("settings.cannotDisableLast", settingTab(only, .music, enabled: false) == only)
    let off = settingTab(d, .alerts, enabled: false)
    check("settings.disableOne", visibleTabs(off) == [.music, .claude, .calendar])
    check("settings.enableOne", settingTab(off, .alerts, enabled: true) == d)

    check("settings.move", movingTab(d, from: 0, to: 3).tabOrder == [.claude, .alerts, .calendar, .music])
    check("settings.moveSame", movingTab(d, from: 2, to: 2) == d)
    check("settings.moveClamp",
          movingTab(d, from: 0, to: 99).tabOrder == [.claude, .alerts, .calendar, .music]
          && movingTab(d, from: -5, to: 2).tabOrder == [.claude, .alerts, .music, .calendar])

    var custom = d
    custom.tabOrder = [.calendar, .music, .claude, .alerts]
    custom.enabledTabs = [.music, .calendar]
    custom.lastTab = .music
    custom.theme = .glass
    custom.selectedCalendarIDs = ["a", "b"]
    custom.seenApps = ["Slack"]
    custom.quietWhilePresenting = false
    let data = try? JSONEncoder().encode(custom)
    check("settings.roundTrip", decodeSettings(data) == custom)
    check("settings.roundTripDefaults", decodeSettings(try? JSONEncoder().encode(d)) == d)

    check("settings.partialOrderAppended",
          decodeSettings(Data(#"{"tabOrder":["calendar","music","music"]}"#.utf8)).tabOrder == [.calendar, .music, .claude, .alerts])

    // Task 9 (S6): Claude Code integration defaults on; an old settings blob keeps it on.
    var noClaude = d
    noClaude.claudeIntegration = false
    check("settings.claudeIntegration",
          d.claudeIntegration && decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).claudeIntegration
          && decodeSettings(try? JSONEncoder().encode(noClaude)).claudeIntegration == false)

    // Task 11 (R1): only a fresh install (no saved settings) sees the welcome; a blob saved
    // before the key existed is an existing user. The menu-bar icon is off by default.
    do {
        var shown = d
        shown.hasSeenWelcome = true
        shown.menuBarIcon = true
        check("settings.welcome.fresh", !decodeSettings(nil).hasSeenWelcome && !d.hasSeenWelcome)
        check("settings.welcome.existingBlob",
              decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).hasSeenWelcome
              && decodeSettings(Data("{}".utf8)).hasSeenWelcome)
        check("settings.welcome.savedFalseStays",
              !decodeSettings(try? JSONEncoder().encode(d)).hasSeenWelcome)
        check("settings.welcome.roundTrip", decodeSettings(try? JSONEncoder().encode(shown)) == shown)
        check("settings.menuBarIcon.defaultOff",
              !d.menuBarIcon && !decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).menuBarIcon
              && !decodeSettings(Data(#"{"menuBarIcon":"yes"}"#.utf8)).menuBarIcon)
    }

    // Fix round 1: selected sidebar label picks black/white for >= 4.5:1 on every accent.
    do {
        let accents: [(Double, Double, Double)] = [(0x7A, 0xA7, 0xFF), (0xB1, 0x8C, 0xFF), (0x30, 0xD1, 0x58),
                                                    (0xFF, 0x9F, 0x0A), (0xFF, 0x6B, 0x9D)].map { ($0.0 / 255, $0.1 / 255, $0.2 / 255) }
        var ok = true
        for a in accents {
            let black = prefersBlackLabel(r: a.0, g: a.1, b: a.2, alpha: 0.85, backdrop: 0.085)
            func mix(_ c: Double) -> Double { c * 0.85 + 0.085 * 0.15 }
            let lum = relativeLuminance(r: mix(a.0), g: mix(a.1), b: mix(a.2))
            if contrastRatio(black ? 0 : 1, lum) < 4.5 { ok = false }
        }
        check("settings.selectionLabelContrast", ok
              && prefersBlackLabel(r: 0.48, g: 0.65, b: 1, alpha: 0.85, backdrop: 0.085)
              && !prefersBlackLabel(r: 0, g: 0.2, b: 0.8, alpha: 0.85, backdrop: 0.085))
    }

    // Notch section (Task 13): open-from, animation style and speed.
    check("settings.notchDefaults", d.openFrom == .centre && d.animation == .spring && d.animationSpeed == .normal)
    check("settings.notchMissingKeys",
          decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).openFrom == .centre
          && decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).animation == .spring
          && decodeSettings(Data(#"{"theme":"glass"}"#.utf8)).animationSpeed == .normal)
    let notchSet = decodeSettings(Data(#"{"openFrom":"right","animation":"fade","animationSpeed":"fast"}"#.utf8))
    check("settings.notchDecoded", notchSet.openFrom == .right && notchSet.animation == .fade && notchSet.animationSpeed == .fast)
    let notchBad = decodeSettings(Data(#"{"openFrom":"top","animation":7,"animationSpeed":"warp","theme":"glass"}"#.utf8))
    check("settings.notchBadValues", notchBad.openFrom == .centre && notchBad.animation == .spring
          && notchBad.animationSpeed == .normal && notchBad.theme == .glass)
    var notchCustom = d
    notchCustom.openFrom = .left
    notchCustom.animation = .none
    notchCustom.animationSpeed = .slow
    check("settings.notchRoundTrip", decodeSettings(try? JSONEncoder().encode(notchCustom)) == notchCustom)
}
