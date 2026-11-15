import Foundation
import CoreGraphics

/// A short notice that drops under the closed notch for `bannerDuration` seconds.
public struct Banner: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case alert(app: String), device(DeviceBadge), meeting, claudeFinished
    }
    /// Stable identity used for de-duplication (same id within 10 min is not shown again).
    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    /// Optional white action pill ("Join", "Eject"); the action itself is supplied by the producer.
    public let actionLabel: String?
    /// The tab the panel opens on when the banner is hovered or clicked.
    public let tab: TabID
    /// Meeting banners: `meetingService`'s result, i.e. exactly "Teams" / "Zoom" / "Meet", or the
    /// calendar's name for anything else (only the exact three tint the icon tile).
    public let service: String

    public init(id: String, kind: Kind, title: String, subtitle: String,
                actionLabel: String? = nil, tab: TabID, service: String = "") {
        self.service = service
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.tab = tab
    }
}

/// Which symbol a device banner shows.
public enum DeviceIcon: String, Equatable, Sendable {
    case headphones, bluetooth, charger, battery, drive, usb
}

/// How a device banner's icon and trailing badge look (views 8–10 of the mockup).
public struct DeviceBadge: Equatable, Sendable {
    public var icon: DeviceIcon
    /// Battery ring (0...100) on the trailing edge, Bluetooth devices.
    public var ring: Int?
    /// Mac battery "46%" on the trailing edge (charger / low battery).
    public var battery: Int?
    public var charging: Bool
    /// Earbuds' per-bud and case levels (AirPods): shown as the compact trio in place of the ring.
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    /// Disconnected: only the tile symbol is dimmed.
    public var dimmed: Bool
    /// Low battery: the card is drawn red.
    public var warning: Bool

    public init(icon: DeviceIcon, ring: Int? = nil, battery: Int? = nil, charging: Bool = false,
                dimmed: Bool = false, warning: Bool = false,
                left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.icon = icon
        self.ring = ring
        self.battery = battery
        self.charging = charging
        self.dimmed = dimmed
        self.warning = warning
    }
}

extension DeviceBadge {
    /// "L 80 · R 78 · Case 45" (only the reported parts); nil when none is reported.
    public var levelsText: String? {
        var parts: [String] = []
        if let left { parts.append("L \(left)") }
        if let right { parts.append("R \(right)") }
        if let caseLevel { parts.append("Case \(caseLevel)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What the panel looks like when a banner is offered.
public struct BannerContext: Sendable {
    public var panelOpen: Bool
    public var approvalPending: Bool
    public var popupShowing: Bool
    /// Quiet rules (presenting / Focus / full screen) apply: banners are dropped.
    public var quiet: Bool

    public init(panelOpen: Bool = false, approvalPending: Bool = false,
                popupShowing: Bool = false, quiet: Bool = false) {
        self.panelOpen = panelOpen
        self.approvalPending = approvalPending
        self.popupShowing = popupShowing
        self.quiet = quiet
    }
}

public enum BannerDecision: Equatable, Sendable {
    case show(Banner), queued, dropped
}

/// How long a banner stays up.
public let bannerDuration: TimeInterval = 4
/// Banner width (centred under the notch).
public let bannerWidth: CGFloat = 340
/// Height a banner adds below the notch.
public let bannerExtraHeight: CGFloat = 56
/// A banner id already shown within this window is not shown again.
public let bannerDedupeWindow: TimeInterval = 10 * 60

/// Decides which banner (if any) shows. One at a time, newest wins; queued only behind the
/// volume/brightness pop-up (newest queued kept); dropped while the panel is open, an approval
/// is pending, or quiet rules apply.
public struct BannerArbiter {
    private var shown: Banner?
    private var shownAt: Date?
    private var queued: Banner?
    /// id → when it was last actually shown (pruned past the dedupe window). Dropped banners
    /// and queued ones that were replaced or dismissed are not recorded.
    private var seen: [String: Date] = [:]

    public init() {}

    public mutating func offer(_ b: Banner, ctx: BannerContext, now: Date) -> BannerDecision {
        seen = seen.filter { now.timeIntervalSince($0.value) < bannerDedupeWindow }
        if seen[b.id] != nil { return .dropped }
        if ctx.panelOpen || ctx.approvalPending || ctx.quiet { return .dropped }
        if ctx.popupShowing {
            queued = b
            return .queued
        }
        queued = nil
        shown = b
        shownAt = now
        seen[b.id] = now
        return .show(b)
    }

    /// The pop-up went away: the newest queued banner (if any) shows now.
    public mutating func popupEnded(now: Date) -> Banner? {
        guard let q = queued else { return nil }
        queued = nil
        shown = q
        shownAt = now
        seen[q.id] = now
        return q
    }

    /// The banner showing at `now` (nil once `bannerDuration` has passed).
    public func current(now: Date) -> Banner? {
        guard let shown, let shownAt, now.timeIntervalSince(shownAt) < bannerDuration else { return nil }
        return shown
    }

    /// Hides the current banner and forgets any queued one.
    public mutating func dismiss() {
        shown = nil
        shownAt = nil
        queued = nil
    }
}

/// The closed panel while a banner shows: 340 wide, centred on the notch, top flush with it.
public func bannerFrame(notch: CGRect, height: CGFloat) -> CGRect {
    CGRect(x: notch.midX - bannerWidth / 2, y: notch.maxY - height, width: bannerWidth, height: height)
}
