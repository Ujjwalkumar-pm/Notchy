import Foundation
import NotchyCore

func runDeviceEventChecks() {
    do {
        var g = LowBatteryGate()
        let at11 = g.update(percent: 11, charging: false)
        let at10 = g.update(percent: 10, charging: false)
        let at9 = g.update(percent: 9, charging: false)
        check("low.firesOnce", !at11 && at10 && !at9)
    }
    do {
        var g = LowBatteryGate()
        let first = g.update(percent: 8, charging: false)
        let whileCharging = g.update(percent: 8, charging: true)
        let again = g.update(percent: 9, charging: false)
        let notTwice = g.update(percent: 7, charging: false)
        check("low.rearmsAfterCharge", first && !whileCharging && again && !notTwice)
    }
    do {
        let a = bannerFor(.bluetooth(name: "AirPods Pro", connected: true, battery: 80, left: nil, right: nil, case: nil))
        let b = bannerFor(.bluetooth(name: "AirPods Pro", connected: true, battery: 40, left: 40, right: 41, case: 9))
        let off = bannerFor(.bluetooth(name: "AirPods Pro", connected: false, battery: nil, left: nil, right: nil, case: nil))
        let other = bannerFor(.bluetooth(name: "Keyboard", connected: true, battery: nil, left: nil, right: nil, case: nil))
        let d1 = bannerFor(.drive(name: "BACKUP", mounted: true, freeBytes: 1, ejected: false))
        let d2 = bannerFor(.drive(name: "BACKUP", mounted: true, freeBytes: 2, ejected: false))
        let dEj = bannerFor(.drive(name: "BACKUP", mounted: false, freeBytes: nil, ejected: true))
        let p1 = bannerFor(.power(charging: true, percent: 40, minutesToFullOrEmpty: 80))
        let p2 = bannerFor(.power(charging: true, percent: 41, minutesToFullOrEmpty: nil))
        let p3 = bannerFor(.power(charging: false, percent: 41, minutesToFullOrEmpty: 100))
        let low1 = bannerFor(.lowBattery(percent: 10)), low2 = bannerFor(.lowBattery(percent: 9))
        let u1 = bannerFor(.usb(name: "Mouse", connected: true)), u2 = bannerFor(.usb(name: "Mouse", connected: false))
        let ids = [a.id, off.id, other.id, d1.id, dEj.id, p1.id, p3.id, low1.id, u1.id, u2.id]
        check("device.bannerIDsStable", a.id == b.id && d1.id == d2.id && p1.id == p2.id && low1.id == low2.id
              && Set(ids).count == ids.count)
    }
    do {
        let m = bannerFor(.drive(name: "BACKUP", mounted: true, freeBytes: 412_000_000_000, ejected: false))
        let e = bannerFor(.drive(name: "BACKUP", mounted: false, freeBytes: nil, ejected: true))
        let u = bannerFor(.usb(name: "Mouse", connected: true))
        check("device.ejectActionOnMount", m.actionLabel == "Eject" && m.subtitle == "Mounted · 412 GB free"
              && e.actionLabel == nil && e.subtitle == "Ejected — safe to remove" && u.actionLabel == nil)
    }
    do {
        let b = bannerFor(.bluetooth(name: "AirPods Pro", connected: true, battery: nil, left: 80, right: 78, case: 45))
        var ok = b.subtitle == "Connected" && bannerExtraHeight == 56
        if case .device(let badge) = b.kind {
            ok = ok && badge.ring == 78 && badge.icon == .headphones && !badge.dimmed
                && badge.levelsText == "L 80 · R 78 · Case 45"
        }
        else { ok = false }
        let off = bannerFor(.bluetooth(name: "AirPods Pro", connected: false, battery: 50, left: nil, right: nil, case: nil))
        if case .device(let badge) = off.kind { ok = ok && badge.dimmed && badge.ring == nil && off.subtitle == "Disconnected" && badge.levelsText == nil }
        else { ok = false }
        check("device.bluetoothBadge", ok)
        check("banner.meetingTintExact", meetingTintHex(service: "Teams") == 0x5B5FC7
              && meetingTintHex(service: "Zoom") == 0x2D8CFF && meetingTintHex(service: "Meet") == 0x00897B
              && meetingTintHex(service: "Meetings") == nil && meetingTintHex(service: "Zoom Room bookings") == nil
              && meetingTintHex(service: "teams") == nil && meetingTintHex(service: "") == nil)
        let ml = Banner(id: "m", kind: .meeting, title: "t", subtitle: "s", tab: .calendar)
        check("banner.meetingServiceDefault", ml.service.isEmpty
              && Banner(id: "m", kind: .meeting, title: "t", subtitle: "s", tab: .calendar, service: "Zoom").service == "Zoom")
    }
    do {
        let c = bannerFor(.power(charging: true, percent: 46, minutesToFullOrEmpty: 80))
        let u = bannerFor(.power(charging: false, percent: 46, minutesToFullOrEmpty: nil))
        let low = bannerFor(.lowBattery(percent: 10))
        var ok = c.title == "Charging" && c.subtitle == "Full in 1 h 20 m" && u.subtitle == "Charger removed"
        if case .device(let b) = low.kind { ok = ok && b.warning && b.battery == 10 } else { ok = false }
        if case .device(let b) = c.kind { ok = ok && !b.warning && b.charging && b.battery == 46 } else { ok = false }
        check("device.powerBanner", ok)
    }
    do {
        let f = bannerFor(.ejectFailed(name: "BACKUP"))
        var ok = f.title == "Couldn't eject — BACKUP" && f.subtitle == "In use by another app" && f.actionLabel == nil
            && f.id != bannerFor(.drive(name: "BACKUP", mounted: true, freeBytes: nil, ejected: false)).id
        if case .device(let b) = f.kind { ok = ok && b.icon == .drive && !b.warning } else { ok = false }
        check("device.ejectFailedBanner", ok)
    }
    check("device.formatBytes", formatBytes(412_000_000_000) == "412 GB" && formatBytes(3_400_000_000) == "3.4 GB"
          && formatBytes(0) == "0 bytes")
}
