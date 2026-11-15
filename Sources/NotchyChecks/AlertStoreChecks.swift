import Foundation
import NotchyCore

func runAlertStoreChecks() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ n: Int, at: Date, app: String = "Microsoft Teams", title: String? = nil, body: String = "b") -> AlertItem {
        AlertItem(id: "i\(n)-\(at.timeIntervalSince1970)", app: app, title: title ?? "t\(n)", body: body, at: at, device: false)
    }
    do {
        var s = AlertStore()
        s.add(item(1, at: t0), now: t0)
        s.add(item(2, at: t0.addingTimeInterval(10)), now: t0.addingTimeInterval(10))
        s.add(item(3, at: t0.addingTimeInterval(5)), now: t0.addingTimeInterval(10)) // late arrival
        check("alerts.newestFirst", s.items.map(\.title) == ["t2", "t3", "t1"])
    }
    do {
        var s = AlertStore()
        for n in 0..<60 { s.add(item(n, at: t0.addingTimeInterval(Double(n))), now: t0.addingTimeInterval(Double(n))) }
        check("alerts.cap10", s.items.count == 10 && s.items.first?.title == "t59" && s.items.last?.title == "t50")
    }
    do {
        let l = [0, 5, 6, 10, 30].map { alertListLayout(count: $0) }
        check("alerts.visibleRows", l[0] == (0, false) && l[1] == (5, false) && l[2] == (5, true)
              && l[3] == (5, true) && l[4] == (5, true) && alertListLayout(count: -1) == (0, false))
        check("alerts.emptyCopy", EmptyStateCopy.noAlerts.symbol == "bell"
              && EmptyStateCopy.noAlerts.title == "You\u{2019}re all caught up")
    }
    do {
        var s = AlertStore()
        s.add(item(1, at: t0), now: t0)
        s.add(item(2, at: t0.addingTimeInterval(3600)), now: t0.addingTimeInterval(3600))
        s.prune(now: t0.addingTimeInterval(24 * 3600 + 1))
        let afterPrune = s.items.map(\.title)
        // add() prunes too
        s.add(item(3, at: t0.addingTimeInterval(26 * 3600)), now: t0.addingTimeInterval(26 * 3600))
        check("alerts.drop24h", afterPrune == ["t2"] && s.items.map(\.title) == ["t3"])
    }
    do {
        var s = AlertStore()
        let a = s.add(item(1, at: t0, title: "Priya S", body: "hi"), now: t0)
        let dup = s.add(item(2, at: t0.addingTimeInterval(30), title: "Priya S", body: "hi"), now: t0.addingTimeInterval(30))
        let otherBody = s.add(item(3, at: t0.addingTimeInterval(31), title: "Priya S", body: "hi again"), now: t0.addingTimeInterval(31))
        let otherApp = s.add(item(4, at: t0.addingTimeInterval(32), app: "Microsoft Outlook", title: "Priya S", body: "hi"),
                             now: t0.addingTimeInterval(32))
        let later = s.add(item(5, at: t0.addingTimeInterval(61), title: "Priya S", body: "hi"), now: t0.addingTimeInterval(61))
        check("alerts.duplicate60s", a && !dup && otherBody && otherApp && later && s.items.count == 4)
    }
    do {
        var s = AlertStore()
        s.add(item(1, at: t0), now: t0)
        s.add(item(2, at: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        s.clear()
        let again = s.add(item(1, at: t0.addingTimeInterval(2)), now: t0.addingTimeInterval(2))
        check("alerts.clear", s.items.count == 1 && again)
    }

    do {
        // An id evicted past the cap and re-reported (a title-only banner the watcher keeps
        // reporting) is not re-added as newest.
        var s = AlertStore()
        func nc(_ id: String, _ t: Date, body: String = "") -> AlertItem {
            AlertItem(id: "nc:\(id)", app: "Microsoft Teams", title: "T \(id)", body: body, at: t, device: false)
        }
        let first = s.admitNotification(nc("old", t0), now: t0)
        for n in 1...10 {
            let t = t0.addingTimeInterval(Double(n))
            _ = s.admitNotification(nc("n\(n)", t, body: "b"), now: t)
        }
        let evicted = !s.contains(id: "nc:old")
        let later = t0.addingTimeInterval(11 * 60)
        let again = s.admitNotification(nc("old", later), now: later)
        check("alerts.evictedNotReadded", first == .added && evicted && again == .ignored
              && !s.contains(id: "nc:old") && s.items.first?.id == "nc:n10")
    }
    do {
        var s = AlertStore()
        _ = s.admitNotification(AlertItem(id: "nc:a", app: "Microsoft Teams", title: "Priya", body: "", at: t0, device: false), now: t0)
        let t1 = t0.addingTimeInterval(2)
        let up = s.admitNotification(AlertItem(id: "nc:a", app: "Microsoft Teams", title: "Priya", body: "hi", at: t1, device: false), now: t1)
        let twice = s.admitNotification(AlertItem(id: "nc:a", app: "Microsoft Teams", title: "Priya", body: "hi", at: t1, device: false), now: t1)
        check("alerts.upgradeBodyViaAdmit", up == .upgraded && twice == .ignored && s.items.map(\.body) == ["hi"])
        let dupText = s.admitNotification(AlertItem(id: "nc:b", app: "Microsoft Teams", title: "Priya", body: "hi", at: t1, device: false), now: t1)
        check("alerts.admitDuplicateText", dupText == .duplicate && s.items.count == 1)
    }
    do {
        var s = AlertStore()
        for n in 0..<150 {
            let t = t0.addingTimeInterval(Double(n))
            _ = s.admitNotification(AlertItem(id: "nc:\(n)", app: "Microsoft Teams", title: "t\(n)", body: "b", at: t, device: false), now: t)
        }
        check("alerts.seenIDsBounded", s.seenIDs.count == AlertStore.seenIDCap && s.seenIDs.first == "nc:50"
              && s.seenIDs.last == "nc:149")
    }
    do {
        // add() is false for an item older than the ten kept (trimmed straight away).
        var s = AlertStore()
        for n in 1...10 { s.add(item(n, at: t0.addingTimeInterval(Double(n))), now: t0.addingTimeInterval(10)) }
        let old = s.add(item(99, at: t0), now: t0.addingTimeInterval(10))
        let new = s.add(item(11, at: t0.addingTimeInterval(11)), now: t0.addingTimeInterval(11))
        check("alerts.addFalseWhenTrimmed", !old && new && s.items.count == 10 && !s.items.contains { $0.title == "t99" })
    }

    // Banner text parsing
    let known = ["Microsoft Outlook", "Microsoft Teams"]
    do {
        // Real layout captured 15 Nov (macOS 27.2): description, then title/body static texts.
        let r = parseBannerTexts(["Script Editor, test title, test body", "test title", "test body"], knownApps: known)
        check("alerts.parse.realLayout", r?.app == "Script Editor" && r?.title == "test title" && r?.body == "test body")
    }
    do {
        let r = parseBannerTexts(["Microsoft Teams", "Priya S", "Can we move the review to 4 pm today?"], knownApps: known)
        check("alerts.parse.separateTexts", r?.app == "Microsoft Teams" && r?.title == "Priya S"
              && r?.body == "Can we move the review to 4 pm today?")
    }
    do {
        let r = parseBannerTexts(["Microsoft Teams, Priya S, Can we move, maybe 4 pm?"], knownApps: known)
        check("alerts.parse.combinedOnly", r?.app == "Microsoft Teams" && r?.title == "Priya S"
              && r?.body == "Can we move, maybe 4 pm?")
    }
    do {
        let r = parseBannerTexts(["Microsoft Outlook, Rahul M, Re: Q4, roadmap", "Rahul M", "Re: Q4, roadmap"], knownApps: known)
        check("alerts.parse.commaInBody", r?.app == "Microsoft Outlook" && r?.title == "Rahul M" && r?.body == "Re: Q4, roadmap")
    }
    do {
        let r = parseBannerTexts(["Slack", "Bob", "lunch?"], knownApps: known)
        let r2 = parseBannerTexts(["Slack, Bob, lunch?"], knownApps: known)
        check("alerts.parse.unknownApp", r?.app == "Slack" && r?.title == "Bob" && r?.body == "lunch?"
              && r2?.app == "Slack" && r2?.title == "Bob" && r2?.body == "lunch?")
    }
    do {
        let titleOnly = parseBannerTexts(["Microsoft Teams, Priya S", "Priya S"], knownApps: known)
        check("alerts.parse.edges", parseBannerTexts([], knownApps: known) == nil
              && parseBannerTexts(["  ", "lonely"], knownApps: known) == nil
              && titleOnly?.app == "Microsoft Teams" && titleOnly?.title == "Priya S" && titleOnly?.body == "")
    }

    // App names, seen apps
    check("alerts.matchApp", matchApp("teams", in: known) == "Microsoft Teams"
          && matchApp("Microsoft Outlook", in: known) == "Microsoft Outlook"
          && matchApp("Slack", in: known) == nil && matchApp("", in: known) == nil)
    do {
        var seen: [String] = []
        seen = notingSeenApp(seen, app: "Microsoft Teams", watched: known)
        seen = notingSeenApp(seen, app: "Slack", watched: known)
        seen = notingSeenApp(seen, app: "slack", watched: known)
        let one = seen
        for n in 0..<40 { seen = notingSeenApp(seen, app: "App \(n)", watched: known) }
        let sys = notingSeenApp([], app: "Privacy & Security", watched: known)
        check("alerts.seenApps.noSystemSources", sys.isEmpty && isSystemNoticeSource(" Software Update ")
              && !isSystemNoticeSource("Slack") && notingSeenApp([], app: "Slack", watched: known) == ["Slack"])
        check("alerts.seenApps", one == ["Slack"] && seen.count == 30 && seen.last == "App 39" && seen.first == "App 10")
    }

    // Dock badge, time, device rows
    check("alerts.badgeParse", parseBadgeCount("3") == 3 && parseBadgeCount("99+") == 99 && parseBadgeCount("•") == nil
          && parseBadgeCount(nil) == nil && parseBadgeCount("0") == nil && parseBadgeCount("") == nil)
    check("alerts.relativeTime", relativeTime(t0, now: t0.addingTimeInterval(20)) == "now"
          && relativeTime(t0, now: t0.addingTimeInterval(125)) == "2m"
          && relativeTime(t0, now: t0.addingTimeInterval(3 * 3600 + 5)) == "3h"
          && relativeTime(t0, now: t0.addingTimeInterval(-5)) == "now")
    do {
        let d = alertItemFor(.bluetooth(name: "AirPods Pro", connected: true, battery: 80, left: nil, right: nil, case: nil), now: t0)
        check("alerts.deviceItem", d.device && d.app == "headphones" && d.title == "AirPods Pro"
              && d.body == "Connected" && d.at == t0)
    }
    do {
        let a = bannerFor(.ejectFailed(name: "BACKUP"), now: t0)
        let b = bannerFor(.ejectFailed(name: "BACKUP"), now: t0.addingTimeInterval(2))
        check("device.ejectFailedPerAttempt", a.id != b.id && a.id.hasPrefix("drive:BACKUP:ejectFailed"))
    }

    // Fix round 1: only confirmed app names reach seenApps
    do {
        let real = parseBannerGroup(description: "Script Editor, test title, test body", title: "test title",
                                    body: "test body", knownApps: known)
        let knownPrefix = parseBannerGroup(description: "Microsoft Teams, Priya S, hi", title: nil, body: nil, knownApps: known)
        check("alerts.confirmed.realLayout", real?.confirmed == true && real?.app == "Script Editor"
              && knownPrefix?.confirmed == true && knownPrefix?.app == "Microsoft Teams")
    }
    do {
        // No description yet; the body has a comma: "Hi" must never become a seen app.
        let p = parseBannerGroup(description: nil, title: "Priya S", body: "Hi, are you free?", knownApps: known)
        let route = p.map { routeBanner($0, watched: known, seen: []) }
        check("alerts.noDescription.noSeenApp", p?.confirmed == false && route == .drop)
    }
    do {
        // Branch-3 style (first text taken as the app): the sender must not become a seen app.
        let p = parseBannerGroup(description: nil, title: "Priya S", body: "lunch?", knownApps: known)
        let wrongSplit = parseBannerGroup(description: "Bob, lunch, now?", title: "Priya S", body: nil, knownApps: known)
        check("alerts.branch3.noSeenApp", p.map { routeBanner($0, watched: known, seen: []) } == .drop
              && wrongSplit.map { routeBanner($0, watched: known, seen: []) } == .drop)
    }
    do {
        let slack = ParsedBanner(app: "Slack", title: "Bob", body: "x", confirmed: true)
        let teams = ParsedBanner(app: "Microsoft Teams", title: "Priya", body: "x", confirmed: false)
        check("alerts.route", routeBanner(slack, watched: known, seen: []) == .seen(["Slack"])
              && routeBanner(slack, watched: known, seen: ["Slack"]) == .drop
              && routeBanner(teams, watched: known, seen: []) == .watched(app: "Microsoft Teams"))
    }
    do {
        let b = notificationBannerSubrole
        let burst = (0..<5).map { BannerGroupInfo(id: "n\($0)", subrole: b, inList: false) }
        let one = bannerGroupsToReport(burst, reported: ["n0", "n1", "n2", "n3"])
        let all = bannerGroupsToReport(burst, reported: [])
        check("alerts.groups.burst", one == [4] && all == [0, 1, 2, 3, 4])
        let list = (0..<2).map { BannerGroupInfo(id: "l\($0)", subrole: b, inList: true) }
        check("alerts.groups.listIgnored", bannerGroupsToReport(list, reported: []).isEmpty)
        let dups = [BannerGroupInfo(id: "x", subrole: b, inList: false), BannerGroupInfo(id: "x", subrole: b, inList: false),
                    BannerGroupInfo(id: "y", subrole: b, inList: false)]
        check("alerts.groups.duplicateOnce", bannerGroupsToReport(dups, reported: []) == [0, 2])
        let other = [BannerGroupInfo(id: "s", subrole: "AXNotificationCenterBannerStack", inList: false),
                     BannerGroupInfo(id: "g", subrole: "AXNotificationCenterGroup", inList: false),
                     BannerGroupInfo(id: nil, subrole: b, inList: false)]
        check("alerts.groups.exactSubrole", bannerGroupsToReport(other, reported: []) == [2])
        let alerts = [BannerGroupInfo(id: "a", subrole: "AXNotificationCenterAlert", inList: false),
                      BannerGroupInfo(id: "a2", subrole: "AXNotificationCenterAlert", inList: true),
                      BannerGroupInfo(id: "b", subrole: b, inList: false)]
        check("alerts.groups.alertSubrole", bannerGroupsToReport(alerts, reported: []) == [0, 2]
              && bannerGroupsToReport(alerts, reported: ["a"]) == [2])
    }
    do {
        var s = AlertStore()
        s.add(AlertItem(id: "nc:1", app: "Microsoft Teams", title: "Priya", body: "", at: t0, device: false), now: t0)
        let up = s.upgradeBody(id: "nc:1", body: "hello")
        let again = s.upgradeBody(id: "nc:1", body: "other")
        check("alerts.upgradeBody", up && !again && s.items.first?.body == "hello" && s.items.count == 1
              && !s.upgradeBody(id: "nc:2", body: "x"))
    }
}
