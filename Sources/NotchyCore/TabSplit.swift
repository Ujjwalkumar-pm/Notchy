import Foundation

// MARK: - Tabs in the notch strip

/// Split layout (B): the first half of the visible tabs left of the camera notch, the rest
/// right of it. Odd counts put the extra tab on the left.
public func splitTabs(_ tabs: [TabID]) -> (left: [TabID], right: [TabID]) {
    let n = (tabs.count + 1) / 2
    return (Array(tabs.prefix(n)), Array(tabs.dropFirst(n)))
}

/// The usable space either side of the hardware notch in the open panel's notch-height strip,
/// in panel coordinates (x from the panel's left edge). Each wing runs from the panel edge
/// (minus `edgePad`) to the notch edge (minus `gap`); widths are never negative.
public struct NotchWings: Equatable, Sendable {
    public var leftX: Double
    public var leftWidth: Double
    public var rightX: Double
    public var rightWidth: Double
}

public let wingEdgePad: Double = 18
public let wingNotchGap: Double = 8

/// `notchMinX` is the notch's left edge measured from the panel's left edge (computed from the
/// panel frame and the notch rect, so a panel not centred on the notch still works).
public func notchWings(panelWidth: Double, notchMinX: Double, notchWidth: Double,
                       edgePad: Double = wingEdgePad, gap: Double = wingNotchGap) -> NotchWings {
    let leftX = edgePad
    let rightX = notchMinX + notchWidth + gap
    return NotchWings(leftX: leftX,
                      leftWidth: max(0, notchMinX - gap - edgePad),
                      rightX: rightX,
                      rightWidth: max(0, panelWidth - edgePad - rightX))
}

/// Where the tab slots sit in the strip: `centers` (panel x, in visible-tab order; the first
/// `leftCount` are left of the notch), all `slot` wide.
public struct StripLayout: Equatable, Sendable {
    public var centers: [Double]
    public var slot: Double
    public var leftCount: Int
}

public let stripMaxSlot: Double = 40
/// Layout A packs all tabs in one wing beside the status cluster: 26 pt slots (AUDIT T2).
public let stripMaxSlotTabsAndStatus: Double = 26
/// Narrower than this and the tabs don't fit beside the notch (the caller falls back to a
/// tab row under the strip).
public let stripMinSlot: Double = 18

/// The widest slot for `layout`: 40 pt split, 26 pt tabs + status.
public func stripSlotLimit(for layout: TabLayout) -> Double {
    layout == .tabsAndStatus ? stripMaxSlotTabsAndStatus : stripMaxSlot
}

/// Slot positions for `count` tabs. Split: each wing's tab group is centred within its wing
/// (AUDIT T5; mirror-symmetric about the notch when the panel is centred on it), same slot
/// width both sides. Tabs + status: all tabs packed in the left wing from its outer edge
/// (the status cluster owns the right wing). When that doesn't fit (e.g. the panel opens from
/// the notch's left or right edge, leaving one wing tiny), all tabs go in the larger wing
/// (`leftCount` = count or 0; layout A then has no room for status). Nil when there are no
/// tabs or they don't fit even so. `maxSlot` nil → `stripSlotLimit(for: layout)`.
public func stripLayout(count: Int, layout: TabLayout, wings: NotchWings,
                        maxSlot: Double? = nil, minSlot: Double = stripMinSlot) -> StripLayout? {
    guard count > 0 else { return nil }
    let maxSlot = maxSlot ?? stripSlotLimit(for: layout)
    let centred = layout == .split
    let preferredLeft = layout == .split ? (count + 1) / 2 : count
    if let l = packedStrip(count: count, leftCount: preferredLeft, wings: wings, maxSlot: maxSlot,
                           minSlot: minSlot, centred: centred) {
        return l
    }
    // One wing for all tabs: the larger one.
    let allLeft = wings.leftWidth >= wings.rightWidth ? count : 0
    guard allLeft != preferredLeft else { return nil }
    return packedStrip(count: count, leftCount: allLeft, wings: wings, maxSlot: maxSlot,
                       minSlot: minSlot, centred: centred)
}

/// `count` tabs, the first `leftCount` in the left wing, the rest in the right wing, one slot
/// width for all. Packed from each wing's outer edge, or centred in each wing. Nil when the
/// slot is below `minSlot`.
private func packedStrip(count: Int, leftCount: Int, wings: NotchWings,
                         maxSlot: Double, minSlot: Double, centred: Bool) -> StripLayout? {
    let rightCount = count - leftCount
    var slot = maxSlot
    if leftCount > 0 { slot = min(slot, wings.leftWidth / Double(leftCount)) }
    if rightCount > 0 { slot = min(slot, wings.rightWidth / Double(rightCount)) }
    guard slot >= minSlot else { return nil }
    let leftStart = wings.leftX + (centred ? (wings.leftWidth - Double(leftCount) * slot) / 2 : 0)
    let rightEnd = wings.rightX + wings.rightWidth
        - (centred ? (wings.rightWidth - Double(rightCount) * slot) / 2 : 0)
    var centers: [Double] = []
    for i in 0..<leftCount { centers.append(leftStart + (Double(i) + 0.5) * slot) }
    for i in 0..<rightCount { centers.append(rightEnd - (Double(rightCount - i) - 0.5) * slot) }
    return StripLayout(centers: centers, slot: slot, leftCount: leftCount)
}

/// Room kept for the strip's status cluster (working count, unread badge, calendar glyph +
/// next-meeting time: at most about 108 pt) when the level control shares the right wing.
public let stripStatusReserve: Double = 112

/// Where the open panel's level control (12 pt icon, 6 pt gap, 64 pt bar = 82 pt) sits in the
/// notch-height strip: in the wing opposite the selected tab's wing, hugging the notch, and
/// clear of the tab slots that wing may hold (wherever they sit in it). `width` shrinks to the
/// free room; nil when less than 48 pt is free (the bar is then skipped).
public func levelIndicatorSlot(wings: NotchWings, layout: StripLayout?, selected: Int?,
                               statusInRight: Bool = false, statusReserve: Double = stripStatusReserve,
                               full: Double = 82, minimum: Double = 48) -> (x: Double, width: Double)? {
    let leftCount = layout?.leftCount ?? 0
    let centers = layout?.centers ?? []
    let slot = layout?.slot ?? 0
    let selectedLeft = selected.map { $0 < leftCount } ?? false
    if selectedLeft {
        // Right wing: from the notch edge to its first tab (or its outer edge). Layout A: the
        // status cluster sits at the wing's outer edge; keep clear of it.
        let wingEnd = wings.rightX + wings.rightWidth - (statusInRight ? statusReserve : 0)
        let firstTab = centers.count > leftCount ? centers[leftCount] - slot / 2 : wingEnd
        let free = min(firstTab, wingEnd) - wings.rightX
        guard free >= minimum else { return nil }
        return (wings.rightX, min(full, free))
    }
    // Left wing: from its last tab (or its outer edge) to the notch edge.
    let lastTab = leftCount > 0 ? centers[leftCount - 1] + slot / 2 : wings.leftX
    let free = wings.leftX + wings.leftWidth - lastTab
    guard free >= minimum else { return nil }
    let w = min(full, free)
    return (wings.leftX + wings.leftWidth - w, w)
}

/// The slot under `x` (within half a slot of its centre), nil over a gap or the notch.
public func stripSlot(at x: Double, _ l: StripLayout) -> Int? {
    l.centers.firstIndex { abs(x - $0) <= l.slot / 2 }
}

/// Click / drag-start hit test (AUDIT Y1). A point inside a real slot always picks that
/// slot's own tab (`stripSlot`). When slots are narrower than `minHit` (layout A's ~23.6 pt in a
/// 420 pt panel), each wing's group also takes the margin just outside its OUTER edge (away
/// from the notch, never towards it) for its outermost tab, up to the group's total shortfall
/// (count × (minHit − slot)) and never past the panel edge (`panelWidth`). Nil over the notch,
/// a gap, or beyond that margin.
public func stripHitSlot(at x: Double, _ l: StripLayout, panelWidth: Double = .infinity,
                         minHit: Double = minimumHitSize) -> Int? {
    if let i = stripSlot(at: x, l) { return i }
    guard l.slot < minHit, !l.centers.isEmpty else { return nil }
    let count = l.centers.count
    if l.leftCount > 0 {
        let outer = l.centers[0] - l.slot / 2
        let extra = Double(l.leftCount) * (minHit - l.slot)
        if x < outer && x >= max(0, outer - extra) { return 0 }
    }
    if l.leftCount < count {
        let outer = l.centers[count - 1] + l.slot / 2
        let extra = Double(count - l.leftCount) * (minHit - l.slot)
        if x > outer && x <= min(panelWidth, outer + extra) { return count - 1 }
    }
    return nil
}

/// `tabDragTarget` for slots at arbitrary centres (e.g. split around the notch): the dragged
/// tab moves one place each time the pointer crosses a neighbour's centre, so dragging across
/// the notch gap moves it to the other side.
public func tabDragTarget(from index: Int, pointerX: Double, centers: [Double]) -> Int {
    guard !centers.isEmpty else { return index }
    var t = min(max(index, 0), centers.count - 1)
    while t + 1 < centers.count && pointerX > centers[t + 1] { t += 1 }
    while t - 1 >= 0 && pointerX < centers[t - 1] { t -= 1 }
    return t
}

// MARK: - Swipe to change tabs

/// One trackpad scroll gesture's phase, as far as swiping cares.
public enum SwipePhase: Sendable { case began, changed, ended, cancelled, other }

/// Two-finger horizontal swipe → one tab step per gesture. Only events between a `began` and
/// its `ended`/`cancelled` count; momentum events never do. Fires once the accumulated
/// horizontal travel reaches `threshold` and dominates the vertical travel.
public struct SwipeTracker: Sendable {
    public static let threshold: Double = 40
    /// Horizontal travel after which the gesture counts as a swipe for the page dots.
    public static let indicatorThreshold: Double = 8
    private var active = false
    /// True while a live gesture is a swipe: horizontal-dominant travel of at least
    /// `indicatorThreshold`, or it already stepped (AUDIT T4: page dots show only then).
    /// False again at the gesture's end, when it is dropped, and for vertical scrolls.
    public private(set) var indicating = false
    private var fired = false
    private var dx: Double = 0
    private var dy: Double = 0

    public init() {}

    /// Returns -1 (previous tab: fingers moved right), +1 (next tab: fingers moved left) or 0.
    /// `natural`: the event's deltas follow the fingers (`isDirectionInvertedFromDevice`).
    /// `blocked`: the pointer is over the approval card — the whole gesture is dropped.
    public mutating func feed(_ phase: SwipePhase, momentum: Bool, dx deltaX: Double, dy deltaY: Double,
                              natural: Bool, blocked: Bool = false) -> Int {
        if momentum { return 0 }
        switch phase {
        case .began:
            active = !blocked
            fired = false
            indicating = false
            dx = 0; dy = 0
            return 0
        case .ended, .cancelled:
            active = false
            indicating = false
            return 0
        case .other:
            return 0
        case .changed:
            guard active else { return 0 }
            if blocked { active = false; indicating = false; return 0 }
            guard !fired else { return 0 }
            let fingerX = natural ? deltaX : -deltaX
            dx += fingerX
            dy += abs(deltaY)
            if abs(dx) >= Self.indicatorThreshold && abs(dx) > dy { indicating = true }
            guard abs(dx) >= Self.threshold, abs(dx) > dy else { return 0 }
            fired = true
            return dx > 0 ? -1 : 1
        }
    }
}

// MARK: - Status cluster (layout A)

public struct StripStatus: Equatable, Sendable {
    /// Claude sessions working right now.
    public var working: Int
    /// Sum of the watched apps' Dock badge counts.
    public var unread: Int
    /// Start of the next (not all-day) meeting starting within the look-ahead, else nil.
    public var nextMeeting: Date?
    public var isEmpty: Bool { working == 0 && unread == 0 && nextMeeting == nil }
    public init(working: Int, unread: Int, nextMeeting: Date? = nil) {
        self.working = working; self.unread = unread; self.nextMeeting = nextMeeting
    }
}

public func stripStatus(phases: [SessionPhase], dockCounts: [String: Int], meetings: [MeetingInfo],
                        now: Date, lookAhead: TimeInterval = 12 * 3600) -> StripStatus {
    let working = phases.filter { if case .working = $0 { return true } else { return false } }.count
    let unread = dockCounts.values.reduce(0) { $0 + max(0, $1) }
    let next = meetings
        .filter { !$0.allDay && $0.start >= now && $0.start.timeIntervalSince(now) <= lookAhead }
        .map(\.start).min()
    return StripStatus(working: working, unread: unread, nextMeeting: next)
}

/// Which parts of layout A's status cluster are drawn.
public struct StripStatusParts: Equatable, Sendable {
    public var working: Bool
    public var unread: Bool
    public var time: Bool
    public var calendarGlyph: Bool
    public init(working: Bool, unread: Bool, time: Bool, calendarGlyph: Bool) {
        self.working = working; self.unread = unread; self.time = time; self.calendarGlyph = calendarGlyph
    }
}

/// Measured widths (pt) of the cluster's parts as they would be drawn.
public struct StripStatusWidths: Equatable, Sendable {
    /// Green dot + gap + count.
    public var working: Double
    /// Red badge (at least 16).
    public var unread: Double
    /// HH:mm text.
    public var time: Double
    /// Calendar glyph + its gap before the time.
    public var calendarGlyph: Double
    /// Gap between groups.
    public var spacing: Double
    public init(working: Double, unread: Double, time: Double, calendarGlyph: Double, spacing: Double) {
        self.working = working; self.unread = unread; self.time = time
        self.calendarGlyph = calendarGlyph; self.spacing = spacing
    }
}

/// Graceful degradation of the status cluster in `available` pt (Task 8 fix 1): full → no
/// calendar glyph → no time → no badge. The working indicator is never dropped or clipped
/// (if even it alone doesn't fit, it is still the only part kept). Empty parts are absent.
public func stripStatusParts(_ s: StripStatus, widths w: StripStatusWidths, available: Double) -> StripStatusParts {
    let hasTime = s.nextMeeting != nil
    let candidates = [
        StripStatusParts(working: s.working > 0, unread: s.unread > 0, time: hasTime, calendarGlyph: hasTime),
        StripStatusParts(working: s.working > 0, unread: s.unread > 0, time: hasTime, calendarGlyph: false),
        StripStatusParts(working: s.working > 0, unread: s.unread > 0, time: false, calendarGlyph: false),
        StripStatusParts(working: s.working > 0, unread: false, time: false, calendarGlyph: false),
    ]
    for c in candidates where stripStatusWidth(c, w) <= available { return c }
    return candidates[candidates.count - 1]
}

/// Total width of `parts` drawn with widths `w`.
public func stripStatusWidth(_ p: StripStatusParts, _ w: StripStatusWidths) -> Double {
    var groups: [Double] = []
    if p.working { groups.append(w.working) }
    if p.unread { groups.append(w.unread) }
    if p.time { groups.append(w.time + (p.calendarGlyph ? w.calendarGlyph : 0)) }
    guard !groups.isEmpty else { return 0 }
    return groups.reduce(0, +) + w.spacing * Double(groups.count - 1)
}
