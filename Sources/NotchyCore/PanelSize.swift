import Foundation
import CoreGraphics

/// User-chosen panel sizes in points. `nil` means "use the default" (collapsed: exactly the
/// notch; expanded: 420 × content height). There is deliberately no upper limit.
/// `expandedHeightAuto`: the open panel keeps the custom width but its height fits the content
/// (Settings → Notch → Open height "Auto"); the stored height is kept so moving the slider off
/// Auto starts from it. Meaningless (always false) without an `expanded` size.
public struct PanelSize: Codable, Equatable, Sendable {
    public var collapsed: CGSize?
    public var expanded: CGSize?
    public var expandedHeightAuto: Bool

    public init(collapsed: CGSize? = nil, expanded: CGSize? = nil, expandedHeightAuto: Bool = false) {
        self.collapsed = collapsed
        self.expanded = expanded
        self.expandedHeightAuto = expandedHeightAuto
    }

    enum CodingKeys: String, CodingKey { case collapsed, expanded, expandedHeightAuto }

    /// Older saved values have no `expandedHeightAuto` key: it defaults to false.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collapsed = try c.decodeIfPresent(CGSize.self, forKey: .collapsed)
        expanded = try c.decodeIfPresent(CGSize.self, forKey: .expanded)
        expandedHeightAuto = (try? c.decodeIfPresent(Bool.self, forKey: .expandedHeightAuto)) ?? false
    }

    /// The flag is written only when set, so a value without it reads exactly as before.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(collapsed, forKey: .collapsed)
        try c.encodeIfPresent(expanded, forKey: .expanded)
        if expandedHeightAuto { try c.encode(true, forKey: .expandedHeightAuto) }
    }

    /// Whole points, at least 1 × 1. No cap.
    public static func floor(_ s: CGSize) -> CGSize {
        CGSize(width: floorOne(s.width), height: floorOne(s.height))
    }

    public func floored() -> PanelSize {
        PanelSize(collapsed: collapsed.map(Self.floor), expanded: expanded.map(Self.floor),
                  expandedHeightAuto: expanded != nil && expandedHeightAuto)
    }
}

/// The custom open size to use: nil without one; with "Auto" height, the custom width and
/// `defaultHeight` (the content-fitting height).
public func customOpenSize(_ p: PanelSize, defaultHeight: CGFloat) -> CGSize? {
    guard let e = p.expanded else { return nil }
    return p.expandedHeightAuto ? CGSize(width: e.width, height: defaultHeight) : e
}

/// Rounds to a whole point and floors at 1; non-finite input becomes 1.
func floorOne(_ v: CGFloat) -> CGFloat {
    guard v.isFinite else { return 1 }
    return max(1, v.rounded())
}

/// The panel frame: top edge flush with `screen.maxY`, horizontally centred on `notch.midX`,
/// each side at least 1 pt, no upper clamp (may extend off-screen).
/// A custom `size` gets whole-point x/width/height. The default (`size == nil`) keeps its exact
/// geometry: the real notch has a half-point origin (e.g. x 645.5, width 179 on a 13" Air), and
/// rounding it would push the collapsed panel half a point off the notch.
public func resolvedFrame(screen: CGRect, notch: CGRect, size: CGSize?, defaultSize: CGSize) -> CGRect {
    if let size {
        let s = PanelSize.floor(size)
        let x = (notch.midX - s.width / 2).rounded()
        return CGRect(x: x, y: screen.maxY - s.height, width: s.width, height: s.height)
    }
    let w = max(1, defaultSize.width), h = max(1, defaultSize.height)
    return CGRect(x: notch.midX - w / 2, y: screen.maxY - h, width: w, height: h)
}

/// AUDIT R2: the closed hover target is never smaller than the camera notch. With a
/// hardware notch (`notch` non-nil) each side of a custom closed size is raised to at least the
/// notch's (whole points, rounded up); a result equal to the notch becomes nil, the default,
/// which keeps the notch's exact half-point geometry. Without a notch (`nil`) the size is
/// unchanged. Larger sizes are kept as they are.
public func clampedClosedSize(_ size: CGSize?, notch: CGSize?) -> CGSize? {
    guard let size, let notch else { return size }
    let s = PanelSize.floor(size)
    let minW = notch.width.rounded(.up), minH = notch.height.rounded(.up)
    let w = max(s.width, minW), h = max(s.height, minH)
    if w == minW && h == minH { return nil }
    return CGSize(width: w, height: h)
}

/// The closed-size slider ranges (Settings → Notch) start at the notch on a notched Mac.
public func closedSliderRange(base: ClosedRange<Double>, minimum: CGFloat?) -> ClosedRange<Double> {
    guard let minimum else { return base }
    let lo = min(max(base.lowerBound, Double(minimum.rounded(.up))), base.upperBound)
    return lo...base.upperBound
}

/// Persists `PanelSize` as JSON under the UserDefaults key `panelSize`.
public struct PanelSizeStore: @unchecked Sendable {
    public static let key = "panelSize"
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> PanelSize {
        guard let data = defaults.data(forKey: Self.key) ?? defaults.string(forKey: Self.key)?.data(using: .utf8),
              let v = try? JSONDecoder().decode(PanelSize.self, from: data) else { return PanelSize() }
        return v.floored()
    }

    public func save(_ size: PanelSize) {
        let v = size.floored()
        if v == PanelSize() { reset(); return }
        if let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: Self.key) }
    }

    public func reset() { defaults.removeObject(forKey: Self.key) }
}

/// The open-state size to use. `custom == nil` → nil (use the default, `content`).
/// While an approval is pending, a custom size is floored at `content` (420 × full content
/// height) so Allow / Deny are never clipped; with nothing pending the custom size is exact.
/// The floor itself never exceeds `screenHeight`, so it can't push the buttons off-screen
/// (a custom size the user made taller than the screen is still kept as is).
public func openPanelSize(custom: CGSize?, content: CGSize, approvalPending: Bool,
                          screenHeight: CGFloat = .infinity) -> CGSize? {
    guard let custom else { return nil }
    guard approvalPending else { return custom }
    let floorHeight = min(content.height, screenHeight)
    return CGSize(width: max(custom.width, content.width), height: max(custom.height, floorHeight))
}

/// Thickness of a resize zone along one axis: 6 pt, but at most a quarter of the panel's
/// dimension so a tiny panel keeps a hoverable middle.
public func resizeZoneThickness(dimension: CGFloat) -> CGFloat {
    max(0, min(6, dimension / 4))
}

/// Extra height of the volume/brightness pop-up below the notch.
public let popupExtraHeight: CGFloat = 28

/// The closed panel while the pop-up shows: same x, width and top as the notch, 28 pt taller,
/// so it grows downward only. Derived from the notch alone; custom sizes never apply.
public func popupFrame(notch: CGRect) -> CGRect {
    CGRect(x: notch.minX, y: notch.minY - popupExtraHeight,
           width: notch.width, height: notch.height + popupExtraHeight)
}

// MARK: - Open from / animation (Settings → Notch)

/// The open panel's frame for `anchor`: centre → midX on the notch's centre; left → minX on
/// the notch's left edge (grows right); right → maxX on the notch's right edge (grows left).
/// Then shifted sideways to stay fully on `screen` (wider than the screen → pinned to its left
/// edge). Top flush with `screen.maxY`. Centre isn't rounded (the default open panel keeps the
/// notch's half-point geometry, like `resolvedFrame`); left/right x are whole points.
public func anchoredFrame(notch: CGRect, screen: CGRect, size: CGSize, anchor: OpenAnchor) -> CGRect {
    var x: CGFloat
    switch anchor {
    case .centre: x = notch.midX - size.width / 2
    // Edge anchors land on whole points, rounded outward so the panel still covers the notch
    // edge (the window server would round a half point anyway; reconcile then sees no drift).
    case .left: x = notch.minX.rounded(.down)
    case .right: x = (notch.maxX - size.width).rounded(.up)
    }
    if size.width >= screen.width {
        x = screen.minX
    } else {
        x = min(max(x, screen.minX), screen.maxX - size.width)
    }
    return CGRect(x: x, y: screen.maxY - size.height, width: size.width, height: size.height)
}

/// Open/close duration: spring 0.35, smooth 0.25, snappy 0.18, fade 0.2 s; slow × 1.5,
/// fast × 0.6; none → 0 (instant).
public func animationDuration(_ a: PanelAnimation, _ s: AnimationSpeed) -> TimeInterval {
    let base: TimeInterval
    switch a {
    case .spring: base = 0.35
    case .smooth: base = 0.25
    case .snappy: base = 0.18
    case .fade: base = 0.2
    case .none: return 0
    }
    switch s {
    case .slow: return base * 1.5
    case .normal: return base
    case .fast: return base * 0.6
    }
}

/// Cubic-Bézier control points (x1, y1, x2, y2) for the frame animation, nil for fade/none
/// (no size animation).
/// - spring (0.32, 1.1, 0.6, 1) (AUDIT N3): springy ease-out with a slight overshoot; the 1.2
///   overshoot read as a "bounce past the notch" at Slow. One curve at every speed (Slow only
///   stretches it in time, never adds overshoot). Reduce Motion never uses it (`effectiveOpenClose`).
/// - smooth (0.4, 0, 0.2, 1): standard ease-in-out, gentle start and end.
/// - snappy (0.2, 0.9, 0.3, 1): fast start, quick settle, no overshoot.
public func animationCurve(_ a: PanelAnimation) -> (Float, Float, Float, Float)? {
    switch a {
    case .spring: return (0.32, 1.1, 0.6, 1)
    case .smooth: return (0.4, 0, 0.2, 1)
    case .snappy: return (0.2, 0.9, 0.3, 1)
    case .fade, .none: return nil
    }
}

/// Hover test for the open panel: the pointer is "in" when it is inside the open frame or the
/// frame the panel opened from (closed notch, pop-up or banner at open time). With Open from
/// Left/Right the open frame may not cover that frame (a centred 340 pt banner, a closed width
/// wider than the notch), so a pointer that opened the panel there must not close it at once.
/// Edges inclusive (the pointer can rest on the screen's top row).
public func hoverContains(_ p: CGPoint, frame: CGRect, openedFrom: CGRect?) -> Bool {
    func within(_ r: CGRect) -> Bool { p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY }
    return within(frame) || openedFrom.map(within) == true
}
