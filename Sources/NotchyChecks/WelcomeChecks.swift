import Foundation
import NotchyCore

func runWelcomeChecks() {
    let d = NotchySettings.defaults
    check("welcome.threeSteps", WelcomeStep.allCases.map(\.title) == ["Hover the notch", "Allow what you use", "Pick your tabs"]
          && WelcomeStep.hover.next == .permissions && WelcomeStep.tabs.next == nil && WelcomeStep.hover.previous == nil)
    check("welcome.allByDefault", welcomePermissions(d) == [.calendar, .accessibility, .focus, .bluetooth])
    var off = d
    off.enabledTabs = [.music]
    off.meetingReminder = false
    off.respectFocus = false
    off.deviceEvents = false
    check("welcome.onlyApplicable", welcomePermissions(off) == [.accessibility])
    var remindOnly = off
    remindOnly.meetingReminder = true
    check("welcome.calendarForReminder", welcomePermissions(remindOnly) == [.calendar, .accessibility])
    check("welcome.panesArePrivacy", Permission.allCases.allSatisfy {
        $0.settingsURL.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_")
    })
    check("welcome.recheckBounded", PermissionRecheck.limit == 30 && PermissionRecheck.interval == 2)
    var seen = d
    seen.hasSeenWelcome = true
    check("welcome.launchRule", welcomeShowsAtLaunch(d, approvalPending: false)
          && !welcomeShowsAtLaunch(d, approvalPending: true)
          && !welcomeShowsAtLaunch(seen, approvalPending: false))
    check("welcome.launchAction", welcomeLaunchAction(d, approvalPending: false) == .show
          && welcomeLaunchAction(d, approvalPending: true) == .waitForApproval
          && welcomeLaunchAction(seen, approvalPending: true) == .skip
          && welcomeLaunchAction(seen, approvalPending: false) == .skip)
    check("welcome.freshNoKeys", !launchSettings(nil, presentKeys: []).hasSeenWelcome
          && !launchSettings(nil, presentKeys: ["somethingElse"]).hasSeenWelcome)
    check("welcome.existingUserByKey", ["didQuitDynamicNotch", "panelSize", "userDisabledStartAtLogin"].allSatisfy {
        launchSettings(nil, presentKeys: [$0]).hasSeenWelcome
    })
    let blob = try? JSONEncoder().encode(d)
    check("welcome.blobWins", !launchSettings(blob, presentKeys: ["didQuitDynamicNotch"]).hasSeenWelcome
          && launchSettings(try? JSONEncoder().encode(seen), presentKeys: []).hasSeenWelcome)
}

func runReopenPolicyChecks() {
    check("reopen.quietAfterLaunch", !ReopenPolicy.opensSettings(sinceLaunch: 0, launchedAsLoginItem: false)
          && !ReopenPolicy.opensSettings(sinceLaunch: 9.9, launchedAsLoginItem: false)
          && ReopenPolicy.opensSettings(sinceLaunch: 10, launchedAsLoginItem: false))
    check("reopen.quietAfterLogin", !ReopenPolicy.opensSettings(sinceLaunch: 30, launchedAsLoginItem: true)
          && ReopenPolicy.opensSettings(sinceLaunch: 60, launchedAsLoginItem: true))
}
