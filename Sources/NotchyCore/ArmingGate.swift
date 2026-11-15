import Foundation
import CoreGraphics

/// Decides when an approval card's Allow / Deny buttons may take clicks (defence against
/// click-through: a click aimed at something else landing on a card that just appeared).
///
/// The buttons arm only when all of these hold:
/// - at least `appearDelay` (0.5 s) has passed since the card for this request appeared, and
/// - the pointer *entered* the card after it appeared and has stayed inside for `dwell` (0.4 s).
///
/// If the pointer is already inside the card when it appears, it must leave and re-enter.
/// Leaving the card, or a new request id, disarms.
///
/// An entry counts only if the pointer itself moved since the previous update (`pointerMoved`).
/// When the card grows, moves or is re-laid out under a still pointer (outside → inside with
/// no movement), that is not an entry: the pointer must leave and re-enter, even if it then
/// moves around inside the card (the stricter rule: only a real crossing of the edge arms).
public struct ArmingGate: Equatable, Sendable {
    public static let appearDelay: TimeInterval = 0.5
    public static let dwell: TimeInterval = 0.4

    public private(set) var requestId: UUID?
    private var appearedAt: Date?
    /// Pointer was inside when the card appeared and hasn't left yet.
    private var mustLeaveFirst = false
    /// When the pointer last entered the card (nil while outside, or not yet a valid entry).
    private var enteredAt: Date?
    private var inside = false

    public init() {}

    /// A card for `id` is showing (call on every tick; a changed id resets the gate).
    /// `pointerInside` is where the pointer is at that moment.
    /// `pointerMoved`: the real pointer position changed since the previous update.
    public mutating func show(_ id: UUID?, pointerInside: Bool, pointerMoved: Bool, now: Date) {
        guard id != requestId else {
            pointer(inside: pointerInside, moved: pointerMoved, now: now)
            return
        }
        requestId = id
        appearedAt = id == nil ? nil : now
        mustLeaveFirst = pointerInside
        enteredAt = nil
        inside = pointerInside
    }

    /// Pointer position update for the current card. `moved`: the pointer itself moved since
    /// the previous update (an outside → inside change without it is the card moving, not an
    /// entry, and forces leave-and-re-enter).
    public mutating func pointer(inside isInside: Bool, moved: Bool, now: Date) {
        defer { inside = isInside }
        guard requestId != nil else { return }
        if !isInside {
            mustLeaveFirst = false
            enteredAt = nil
            return
        }
        guard !inside, !mustLeaveFirst else { return }
        if moved {
            enteredAt = now
        } else {
            mustLeaveFirst = true
            enteredAt = nil
        }
    }

    /// The request id whose buttons are armed at `now`, or nil.
    public func armed(now: Date) -> UUID? {
        guard let requestId, let appearedAt, let enteredAt, inside, !mustLeaveFirst else { return nil }
        // 1 ms slack absorbs floating-point error in the date arithmetic.
        guard now.timeIntervalSince(appearedAt) >= Self.appearDelay - 0.001,
              now.timeIntervalSince(enteredAt) >= Self.dwell - 0.001 else { return nil }
        return requestId
    }

    /// Read-only arming progress for the card's dwell line, 0…1. Exactly 1 only when
    /// `armed(now:)` returns the request id; until then it is capped at `progressCapBeforeArmed`,
    /// so the line can never look complete before the buttons take clicks. 0 without a valid
    /// entry (outside, must-leave-first, no card). The slower of the two clocks (appear delay,
    /// dwell) drives it, since arming needs both.
    public func progress(now: Date) -> Double {
        if armed(now: now) != nil { return 1 }
        guard requestId != nil, let appearedAt, let enteredAt, inside, !mustLeaveFirst else { return 0 }
        let dwell = now.timeIntervalSince(enteredAt) / Self.dwell
        let appear = now.timeIntervalSince(appearedAt) / Self.appearDelay
        return min(max(0, min(dwell, appear)), Self.progressCapBeforeArmed)
    }

    /// Highest progress shown while not yet armed (the last stretch fills only on arming).
    public static let progressCapBeforeArmed: Double = 0.95

    /// After a decision: nothing is armed until the pointer leaves and re-enters.
    public mutating func disarm() {
        enteredAt = nil
        mustLeaveFirst = inside
    }
}

/// Whether the approval card counts as shown for the gate. Only the final, fully laid-out card
/// on a settled open panel "appears": not while the panel is closed or its open/close frame
/// animation runs (the card is clipped and the frame grows under a resting pointer, which
/// would otherwise count as an entry), and not while the card's clipped rect is null or empty.
/// A pointer already inside when it does appear must leave and re-enter (`mustLeaveFirst`).
public func cardVisibleForGate(frameAnimating: Bool, expanded: Bool, rect: CGRect?) -> Bool {
    guard expanded, !frameAnimating, let rect else { return false }
    return !rect.isNull && !rect.isEmpty
}
