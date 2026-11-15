import Foundation

// MARK: - Reduce Motion (AUDIT N1) and content timing (N2)

/// Open/close duration under Reduce Motion: a 0.15 s fade whatever the style and speed.
public let reduceMotionFadeDuration: TimeInterval = 0.15

/// The open/close style and duration actually used. Reduce Motion on: Fade at 0.15 s
/// regardless of the chosen style and speed (AUDIT N1), except None, which stays instant
/// (no motion is already the least motion). Off: the chosen style at `animationDuration`.
public func effectiveOpenClose(_ a: PanelAnimation, _ s: AnimationSpeed,
                               reduceMotion: Bool) -> (style: PanelAnimation, duration: TimeInterval) {
    if a == .none { return (.none, 0) }
    if reduceMotion { return (.fade, reduceMotionFadeDuration) }
    return (a, animationDuration(a, s))
}

/// Whether Settings → Notch → Animation shows "Reduce Motion is on: using Fade".
public func showsReduceMotionCaption(_ a: PanelAnimation, reduceMotion: Bool) -> Bool {
    reduceMotion && a != .none
}

/// How the closed panel changes between the bare notch and a pop-up / banner.
public enum ClosedFrameStyle: Equatable, Sendable {
    /// Animate the frame (Reduce Motion off).
    case grow
    /// Jump to the new frame at alpha 0, then fade in (bare notch → pop-up / banner).
    case fadeIn
    /// Fade out, then jump to the new frame (pop-up / banner → bare notch).
    case fadeOut
    /// Jump at once (pop-up ↔ banner, banner → banner; the content cross-fades in SwiftUI).
    case instant
}

/// Reduce Motion on: banners and the pop-up cross-fade only, never grow (AUDIT N1). `fromBare` /
/// `toBare`: the frame before / after is the plain notch (no pop-up, no banner).
public func closedFrameStyle(reduceMotion: Bool, fromBare: Bool, toBare: Bool) -> ClosedFrameStyle {
    guard reduceMotion else { return .grow }
    if fromBare && toBare { return .instant }
    if fromBare { return .fadeIn }
    if toBare { return .fadeOut }
    return .instant
}

/// The open panel's content fade, tied to the frame animation (AUDIT N2). Opening: after a
/// 0.08 s delay, over 0.6 × duration (easeOut). Closing: over 0.4 × duration (easeIn), so it is
/// gone before the frame has shrunk. Nil for an instant change.
public func contentFadeTiming(duration: TimeInterval, opening: Bool) -> (delay: TimeInterval, duration: TimeInterval)? {
    guard duration > 0 else { return nil }
    return opening ? (0.08, 0.6 * duration) : (0, 0.4 * duration)
}

/// The open content rises this far into place while it fades in; 0 under Reduce Motion.
public func contentRiseOffset(reduceMotion: Bool) -> Double { reduceMotion ? 0 : 4 }

/// Calendar hero ring's one-off pulse when its meeting turns "now" (AUDIT Y3): 1.0 → 1.04 → 1.0;
/// static (1.0) under Reduce Motion.
public func nowRingPulsePeak(reduceMotion: Bool) -> Double { reduceMotion ? 1 : 1.04 }

// MARK: - VoiceOver (AUDIT Y2)

/// VoiceOver adjust on the scrubber: ±10 s, clamped to 0…duration.
public let scrubberAccessibilityStep: Double = 10

public func scrubberAdjusted(elapsed: Double, duration: Double, increment: Bool) -> Double {
    let e = elapsed.isFinite ? elapsed : 0
    let d = max(0, duration.isFinite ? duration : 0)
    return min(max(e + (increment ? scrubberAccessibilityStep : -scrubberAccessibilityStep), 0), d)
}

/// A banner's VoiceOver label and announcement: title, then subtitle when there is one.
public func bannerAccessibilityText(title: String, subtitle: String) -> String {
    subtitle.isEmpty ? title : "\(title), \(subtitle)"
}

// MARK: - Hit targets (AUDIT Y1)

/// The smallest hit target, in points (AUDIT Y1).
public let minimumHitSize: Double = 24
