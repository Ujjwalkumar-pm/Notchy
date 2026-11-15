import Foundation
import CoreGraphics

/// Click-through guard for the open panel's tab content (everything below the approval card,
/// and the tabs in the notch strip). When the panel opens (hover, an approval arriving, the
/// linger, ⌥⌘N) it grows over a pointer that may be resting or mid-click; a click aimed at
/// whatever was under it must not land on Join, Clear, play/pause and the like.
///
/// The content takes clicks only once the open has settled (no frame animation) AND the real
/// pointer has moved since it settled. The pointer position at the first settled update is the
/// reference; until then nothing counts. Once interactive it stays so until `reset()` (the
/// panel closes, or the content shifts under the pointer, e.g. an approval card appears).
public struct ContentGate: Equatable, Sendable {
    /// Pointer movement (pt, either axis) that counts as "moved".
    public static let moveThreshold: CGFloat = 0.5

    public private(set) var interactive = false
    private var settledPointer: CGPoint?

    public init() {}

    /// Back to not interactive; the next settled update records a new reference point.
    public mutating func reset() {
        interactive = false
        settledPointer = nil
    }

    /// Feeds the current state; returns whether the content may take clicks.
    /// `settled`: open and no open/close frame animation is running.
    @discardableResult
    public mutating func update(expanded: Bool, settled: Bool, pointer: CGPoint) -> Bool {
        guard expanded else { reset(); return false }
        if interactive { return true }
        guard settled else { settledPointer = nil; return false }
        guard let start = settledPointer else {
            settledPointer = pointer
            return false
        }
        if abs(pointer.x - start.x) > Self.moveThreshold || abs(pointer.y - start.y) > Self.moveThreshold {
            interactive = true
        }
        return interactive
    }
}

/// A banner's action pill (Join / Eject) must be shown this long before it takes a click.
public let bannerActionDelay: TimeInterval = 0.5

/// Whether a click on the banner's action pill counts. The banner must have finished growing
/// (`fullyShownAt`) at least `bannerActionDelay` ago, and the pointer-movement gate armed when
/// it grew must be cleared (the real pointer moved since), so a click aimed at whatever sat
/// below the notch can't trigger Join / Eject.
public func bannerActionAllowed(fullyShownAt: Date?, now: Date, growGateArmed: Bool) -> Bool {
    guard let fullyShownAt, !growGateArmed else { return false }
    // 1 ms slack absorbs floating-point error in the date arithmetic.
    return now.timeIntervalSince(fullyShownAt) >= bannerActionDelay - 0.001
}

/// Whether the open panel's tab content must be re-guarded because the approval card changed
/// under it: the card appeared or disappeared, or its top edge / height moved by more than
/// `ContentGate.moveThreshold`. Any of these slides the tab content under a pointer that just
/// clicked Allow/Deny/Dismiss, so a fast second click must not land on a tab control.
/// Rects are in any one consistent coordinate space (nil = no card).
public func contentGateNeedsReset(oldCard: CGRect?, newCard: CGRect?) -> Bool {
    switch (oldCard, newCard) {
    case (nil, nil): return false
    case (nil, _), (_, nil): return true
    case let (o?, n?):
        let t = ContentGate.moveThreshold
        return abs(o.height - n.height) > t || abs(o.minY - n.minY) > t
    }
}
