import Foundation

/// The media keys Notchy can intercept.
public enum MediaKey: Sendable, Equatable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
}

/// Maps an NX_KEYTYPE code from a system-defined media key event to a `MediaKey`.
public func mediaKey(nxKeyType: Int32) -> MediaKey? {
    switch nxKeyType {
    case 0: return .volumeUp
    case 1: return .volumeDown
    case 7: return .mute
    case 2: return .brightnessUp
    case 3: return .brightnessDown
    default: return nil
    }
}

/// Level change per key press: 1/16, or 1/64 for the fine (Option+Shift) step.
public func step(fine: Bool) -> Float {
    fine ? 1.0 / 64 : 1.0 / 16
}

/// System output volume as Notchy sees it.
public struct VolumeLevel: Sendable, Equatable {
    public var level: Float
    public var muted: Bool

    public init(level: Float, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}

/// Rounds a level to the nearest multiple of `step`, as macOS does before stepping.
private func snap(_ level: Float, to step: Float) -> Float {
    (level / step).rounded() * step
}

private func clampUnit(_ value: Float) -> Float {
    min(1, max(0, value))
}

/// Applies a volume-family key. Up/down snap, step, clamp and unmute; mute toggles the flag only.
/// Non-volume keys return `v` unchanged.
public func applyVolumeKey(_ key: MediaKey, to v: VolumeLevel, fine: Bool) -> VolumeLevel {
    let delta = step(fine: fine)
    switch key {
    case .volumeUp:
        let level = clampUnit(snap(v.level, to: delta) + delta)
        return VolumeLevel(level: level, muted: false)
    case .volumeDown:
        let level = clampUnit(snap(v.level, to: delta) - delta)
        return VolumeLevel(level: level, muted: false)
    case .mute:
        return VolumeLevel(level: v.level, muted: !v.muted)
    case .brightnessUp, .brightnessDown:
        return v
    }
}

/// Applies a brightness key: snap, step, clamp. Non-brightness keys return `level` unchanged.
public func applyBrightnessKey(_ key: MediaKey, to level: Float, fine: Bool) -> Float {
    let delta = step(fine: fine)
    switch key {
    case .brightnessUp:
        return clampUnit(snap(level, to: delta) + delta)
    case .brightnessDown:
        return clampUnit(snap(level, to: delta) - delta)
    case .volumeUp, .volumeDown, .mute:
        return level
    }
}

/// Whether Notchy should swallow the key event rather than let macOS handle it.
/// Anything not handled here falls back to normal macOS behaviour.
public func shouldConsume(_ key: MediaKey, volumeSettable: Bool, brightnessAvailable: Bool, trusted: Bool) -> Bool {
    guard trusted else { return false }
    switch key {
    case .volumeUp, .volumeDown, .mute:
        return volumeSettable
    case .brightnessUp, .brightnessDown:
        return brightnessAvailable
    }
}

/// Whether Notchy may consume a media key with these modifiers held: none (normal step) or
/// exactly Option+Shift (fine step). Any other combination is left to macOS (Option opens
/// Sound/Displays settings, Shift toggles feedback, Control/Command combos, ...).
public func consumableModifiers(option: Bool, shift: Bool, control: Bool, command: Bool) -> Bool {
    if control || command { return false }
    return option == shift
}
