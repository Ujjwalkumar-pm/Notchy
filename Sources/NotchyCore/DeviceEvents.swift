import Foundation

/// Something a device did after launch (devices present at launch are never reported).
public enum DeviceEvent: Equatable, Sendable {
    /// Battery values are 0...100 when macOS reports them, nil otherwise.
    case bluetooth(name: String, connected: Bool, battery: Int?, left: Int?, right: Int?, case: Int?)
    /// `ejected`: Notchy (or a clean unmount) ejected it — safe to remove.
    case drive(name: String, mounted: Bool, freeBytes: Int64?, ejected: Bool)
    /// The Eject pill was refused (a volume is in use).
    case ejectFailed(name: String)
    /// Non-storage USB device; name only.
    case usb(name: String, connected: Bool)
    /// Charger connected (`charging`) or removed. Minutes: to full when charging, to empty otherwise.
    case power(charging: Bool, percent: Int, minutesToFullOrEmpty: Int?)
    case lowBattery(percent: Int)

    /// Short kind name for logs (never the device name).
    public var logKind: String {
        switch self {
        case .bluetooth(_, let c, _, _, _, _): return c ? "bluetooth.connected" : "bluetooth.disconnected"
        case .drive(_, let m, _, let e): return m ? "drive.mounted" : (e ? "drive.ejected" : "drive.removed")
        case .ejectFailed: return "drive.ejectFailed"
        case .usb(_, let c): return c ? "usb.connected" : "usb.disconnected"
        case .power(let c, _, _): return c ? "power.charger" : "power.battery"
        case .lowBattery: return "power.low"
        }
    }
}

/// Fires once when the battery reaches ≤ 10 % while discharging; re-arms after charging.
public struct LowBatteryGate: Sendable {
    public static let threshold = 10
    private var armed = true

    public init() {}

    public mutating func update(percent: Int, charging: Bool) -> Bool {
        if charging {
            armed = true
            return false
        }
        guard armed, percent <= Self.threshold else { return false }
        armed = false
        return true
    }
}

/// The banner for a device event. Ids are stable per device + state (so the arbiter's
/// 10-minute de-duplication stops a flapping device from re-showing the same banner), except
/// "Couldn't eject", whose id carries the attempt time (`now`) so every retry gives feedback.
public func bannerFor(_ e: DeviceEvent, now: Date = Date()) -> Banner {
    switch e {
    case let .bluetooth(name, connected, battery, left, right, caseLevel):
        // The per-bud levels live in the badge (compact trio); the subtitle stays short.
        let hasLevels = connected && (left != nil || right != nil || caseLevel != nil)
        let ring = connected ? (battery ?? [left, right].compactMap { $0 }.min()) : nil
        let icon: DeviceIcon = looksLikeHeadphones(name) ? .headphones : .bluetooth
        return Banner(id: "bt:\(name):\(connected ? "on" : "off")",
                      kind: .device(DeviceBadge(icon: icon, ring: ring, dimmed: !connected,
                                                left: hasLevels ? left : nil, right: hasLevels ? right : nil,
                                                caseLevel: hasLevels ? caseLevel : nil)),
                      title: name, subtitle: connected ? "Connected" : "Disconnected", tab: .alerts)
    case let .drive(name, mounted, freeBytes, ejected):
        let subtitle: String
        if mounted {
            subtitle = freeBytes.map { "Mounted · \(formatBytes($0)) free" } ?? "Mounted"
        } else {
            subtitle = ejected ? "Ejected — safe to remove" : "Disconnected"
        }
        let state = mounted ? "mounted" : (ejected ? "ejected" : "removed")
        return Banner(id: "drive:\(name):\(state)",
                      kind: .device(DeviceBadge(icon: .drive, dimmed: !mounted && !ejected)),
                      title: name, subtitle: subtitle,
                      actionLabel: mounted ? "Eject" : nil, tab: .alerts)
    case let .ejectFailed(name):
        return Banner(id: "drive:\(name):ejectFailed:\(Int(now.timeIntervalSince1970 * 1000))", kind: .device(DeviceBadge(icon: .drive)),
                      title: "Couldn't eject — \(name)", subtitle: "In use by another app", tab: .alerts)
    case let .usb(name, connected):
        return Banner(id: "usb:\(name):\(connected ? "on" : "off")",
                      kind: .device(DeviceBadge(icon: .usb, dimmed: !connected)),
                      title: name, subtitle: connected ? "Connected" : "Disconnected", tab: .alerts)
    case let .power(charging, percent, minutes):
        let title: String, subtitle: String
        if charging {
            title = percent >= 100 ? "Charged" : "Charging"
            if let m = minutes, m > 0, percent < 100 { subtitle = "Full in \(formatMinutes(m))" }
            else { subtitle = "Connected to power" }
        } else {
            title = "On battery"
            if let m = minutes, m > 0 { subtitle = "\(formatMinutes(m)) left" }
            else { subtitle = "Charger removed" }
        }
        return Banner(id: "power:\(charging ? "ac" : "battery")",
                      kind: .device(DeviceBadge(icon: charging ? .charger : .battery,
                                                battery: percent, charging: charging)),
                      title: title, subtitle: subtitle, tab: .alerts)
    case let .lowBattery(percent):
        return Banner(id: "power:low",
                      kind: .device(DeviceBadge(icon: .battery, battery: percent, warning: true)),
                      title: "Low battery", subtitle: "\(percent)% left · plug in a charger", tab: .alerts)
    }
}

func looksLikeHeadphones(_ name: String) -> Bool {
    let n = name.lowercased()
    return ["airpods", "headphone", "beats", "buds", "earbud", "headset"].contains { n.contains($0) }
}

/// "412 GB", "3.4 GB", "800 MB" (decimal units, like Finder).
public func formatBytes(_ b: Int64) -> String {
    let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
    var v = Double(max(b, 0)), i = 0
    while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
    if i == 0 { return "\(Int(v)) bytes" }
    return v >= 10 ? "\(Int(v.rounded())) \(units[i])" : String(format: "%.1f %@", v, units[i])
}

/// "1 h 20 m", "45 m".
public func formatMinutes(_ m: Int) -> String {
    m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
}
