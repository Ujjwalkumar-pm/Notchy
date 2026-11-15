import Foundation
import CoreGraphics
import NotchyCore

func runBannerChecks() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func b(_ id: String, tab: TabID = .alerts) -> Banner {
        Banner(id: id, kind: .alert(app: "Microsoft Teams"), title: "T \(id)", subtitle: "s", tab: tab)
    }
    let free = BannerContext()

    do {
        var a = BannerArbiter()
        check("banner.show", a.offer(b("1"), ctx: free, now: t0) == .show(b("1")) && a.current(now: t0) == b("1"))
    }
    do {
        var a = BannerArbiter()
        _ = a.offer(b("1"), ctx: free, now: t0)
        let d = a.offer(b("2"), ctx: free, now: t0.addingTimeInterval(1))
        check("banner.replaceNewer", d == .show(b("2")) && a.current(now: t0.addingTimeInterval(1.5)) == b("2"))
    }
    do {
        var a = BannerArbiter()
        _ = a.offer(b("x"), ctx: free, now: t0)
        let at5 = a.offer(b("x"), ctx: free, now: t0.addingTimeInterval(5 * 60))
        let at11 = a.offer(b("x"), ctx: free, now: t0.addingTimeInterval(11 * 60))
        check("banner.dedupe10min", at5 == .dropped && at11 == .show(b("x")))
    }
    do {
        var a = BannerArbiter()
        let d = a.offer(b("1"), ctx: BannerContext(panelOpen: true), now: t0)
        check("banner.droppedWhenOpen", d == .dropped && a.current(now: t0) == nil)
    }
    do {
        var a = BannerArbiter()
        let d = a.offer(b("1"), ctx: BannerContext(approvalPending: true), now: t0)
        check("banner.droppedWhenApproval", d == .dropped && a.current(now: t0) == nil
              && a.popupEnded(now: t0) == nil)
    }
    do {
        var a = BannerArbiter()
        let d = a.offer(b("1"), ctx: BannerContext(quiet: true), now: t0)
        check("banner.droppedWhenQuiet", d == .dropped && a.current(now: t0) == nil)
    }
    do {
        var a = BannerArbiter()
        let pop = BannerContext(popupShowing: true)
        let d1 = a.offer(b("1"), ctx: pop, now: t0)
        let d2 = a.offer(b("2"), ctx: pop, now: t0.addingTimeInterval(0.5))
        let nothingYet = a.current(now: t0.addingTimeInterval(0.6)) == nil
        let end = t0.addingTimeInterval(2)
        let shown = a.popupEnded(now: end)
        check("banner.queuedBehindPopup", d1 == .queued && d2 == .queued && nothingYet
              && shown == b("2") && a.current(now: end.addingTimeInterval(3.9)) == b("2")
              && a.popupEnded(now: end) == nil)
    }
    do {
        var a = BannerArbiter()
        _ = a.offer(b("1"), ctx: free, now: t0)
        check("banner.expires", a.current(now: t0.addingTimeInterval(3.9)) == b("1")
              && a.current(now: t0.addingTimeInterval(4.1)) == nil)
    }
    do {
        var a = BannerArbiter()
        for i in 0..<10 { _ = a.offer(b("m\(i)"), ctx: free, now: t0.addingTimeInterval(Double(i) * 0.5)) }
        check("banner.burst", a.current(now: t0.addingTimeInterval(5)) == b("m9"))
    }
    do {
        var a = BannerArbiter()
        _ = a.offer(b("1"), ctx: free, now: t0)
        a.dismiss()
        check("banner.dismiss", a.current(now: t0) == nil)
    }
    do {
        var a = BannerArbiter()
        let d1 = a.offer(b("1"), ctx: BannerContext(panelOpen: true), now: t0)
        let d2 = a.offer(b("1"), ctx: free, now: t0.addingTimeInterval(60))
        check("banner.droppedNotRecorded", d1 == .dropped && d2 == .show(b("1")))
    }
    do {
        var a = BannerArbiter()
        let pop = BannerContext(popupShowing: true)
        _ = a.offer(b("1"), ctx: pop, now: t0)
        _ = a.offer(b("2"), ctx: pop, now: t0.addingTimeInterval(0.5))
        let shown = a.popupEnded(now: t0.addingTimeInterval(1))
        let again1 = a.offer(b("1"), ctx: free, now: t0.addingTimeInterval(2))
        let again2 = a.offer(b("2"), ctx: free, now: t0.addingTimeInterval(3))
        check("banner.queuedReplacedNotRecorded", shown == b("2") && again1 == .show(b("1")) && again2 == .dropped)
    }
    do {
        var a = BannerArbiter()
        let d = a.offer(b("1"), ctx: BannerContext(popupShowing: true), now: t0)
        a.dismiss()
        let ended = a.popupEnded(now: t0.addingTimeInterval(1))
        let again = a.offer(b("1"), ctx: free, now: t0.addingTimeInterval(2))
        check("banner.dismissDuringPopupLosesQueued", d == .queued && ended == nil && again == .show(b("1")))
    }
    do {
        let notch = CGRect(x: 650, y: 950, width: 185, height: 32)
        let f = bannerFrame(notch: notch, height: 32 + bannerExtraHeight)
        check("banner.frame", f.width == 340 && f.midX == notch.midX && f.maxY == notch.maxY
              && f.height == 88 && bannerWidth == 340 && bannerDuration == 4)
    }
}
