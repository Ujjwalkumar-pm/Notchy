import Foundation
import NotchyCore

func runMediaKeyChecks() {
    // Modifiers Notchy may consume: none or exactly Option+Shift.
    check("mods.none", consumableModifiers(option: false, shift: false, control: false, command: false))
    check("mods.optionShift", consumableModifiers(option: true, shift: true, control: false, command: false))
    check("mods.optionOnly", !consumableModifiers(option: true, shift: false, control: false, command: false))
    check("mods.shiftOnly", !consumableModifiers(option: false, shift: true, control: false, command: false))
    check("mods.control", !consumableModifiers(option: false, shift: false, control: true, command: false))
    check("mods.command", !consumableModifiers(option: false, shift: false, control: false, command: true))
    check("mods.optionShiftCommand", !consumableModifiers(option: true, shift: true, control: false, command: true))

    // Key mapping (NX_KEYTYPE codes).
    check("keys.map",
          mediaKey(nxKeyType: 0) == .volumeUp && mediaKey(nxKeyType: 1) == .volumeDown
          && mediaKey(nxKeyType: 7) == .mute && mediaKey(nxKeyType: 2) == .brightnessUp
          && mediaKey(nxKeyType: 3) == .brightnessDown && mediaKey(nxKeyType: 21) == nil)

    // Step size.
    check("vol.step", abs(step(fine: false) - 0.0625) < 1e-6 && abs(step(fine: true) - 1.0 / 64) < 1e-6)
    let up = applyVolumeKey(.volumeUp, to: VolumeLevel(level: 0.5, muted: false), fine: false)
    check("vol.stepUp", abs(up.level - 0.5625) < 1e-6 && up.muted == false)
    let fineUp = applyVolumeKey(.volumeUp, to: VolumeLevel(level: 0.5, muted: false), fine: true)
    check("vol.fineStep", abs(fineUp.level - 0.515625) < 1e-6)

    // Clamping.
    var top = VolumeLevel(level: 1.0, muted: false)
    for _ in 0..<3 { top = applyVolumeKey(.volumeUp, to: top, fine: false) }
    check("vol.clampTop", abs(top.level - 1.0) < 1e-6)
    let bottom = applyVolumeKey(.volumeDown, to: VolumeLevel(level: 0.0, muted: false), fine: false)
    check("vol.clampBottom", abs(bottom.level - 0.0) < 1e-6)

    // Snapping to the step grid before stepping.
    let snapped = applyVolumeKey(.volumeUp, to: VolumeLevel(level: 0.53, muted: false), fine: false)
    check("vol.snap", abs(snapped.level - 0.5625) < 1e-6)

    // Up/down unmute.
    let upMuted = applyVolumeKey(.volumeUp, to: VolumeLevel(level: 0.5, muted: true), fine: false)
    check("vol.upUnmutes", upMuted.muted == false && abs(upMuted.level - 0.5625) < 1e-6)
    let downMuted = applyVolumeKey(.volumeDown, to: VolumeLevel(level: 0.5, muted: true), fine: false)
    check("vol.downUnmutes", downMuted.muted == false && abs(downMuted.level - 0.4375) < 1e-6)

    // Mute toggles only the flag.
    let m1 = applyVolumeKey(.mute, to: VolumeLevel(level: 0.5, muted: false), fine: false)
    check("vol.muteToggles", m1.muted == true && abs(m1.level - 0.5) < 1e-6)
    let m2 = applyVolumeKey(.mute, to: m1, fine: false)
    check("vol.muteTogglesBack", m2.muted == false && abs(m2.level - 0.5) < 1e-6)

    // Wrong-family keys pass through unchanged.
    let passthrough = VolumeLevel(level: 0.37, muted: true)
    check("vol.brightnessKeyUnchanged", applyVolumeKey(.brightnessUp, to: passthrough, fine: false) == passthrough)

    // Brightness.
    check("bri.clamp",
          abs(applyBrightnessKey(.brightnessUp, to: 0.97, fine: false) - 1.0) < 1e-6
          && abs(applyBrightnessKey(.brightnessDown, to: 0.02, fine: false) - 0.0) < 1e-6)
    check("bri.step", abs(applyBrightnessKey(.brightnessDown, to: 0.5, fine: false) - 0.4375) < 1e-6
          && abs(applyBrightnessKey(.brightnessUp, to: 0.5, fine: true) - 0.515625) < 1e-6)
    check("bri.volumeKeyUnchanged", abs(applyBrightnessKey(.volumeUp, to: 0.42, fine: false) - 0.42) < 1e-6)

    // Consume decision.
    let allKeys: [MediaKey] = [.volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown]
    check("consume.untrusted",
          allKeys.allSatisfy { !shouldConsume($0, volumeSettable: true, brightnessAvailable: true, trusted: false) })
    check("consume.volumeUnsettable",
          [MediaKey.volumeUp, .volumeDown, .mute].allSatisfy {
              !shouldConsume($0, volumeSettable: false, brightnessAvailable: true, trusted: true)
          }
          && [MediaKey.brightnessUp, .brightnessDown].allSatisfy {
              shouldConsume($0, volumeSettable: false, brightnessAvailable: true, trusted: true)
          })
    check("consume.noBrightness",
          [MediaKey.brightnessUp, .brightnessDown].allSatisfy {
              !shouldConsume($0, volumeSettable: true, brightnessAvailable: false, trusted: true)
          }
          && [MediaKey.volumeUp, .volumeDown, .mute].allSatisfy {
              shouldConsume($0, volumeSettable: true, brightnessAvailable: false, trusted: true)
          })

    // HUD pop-up timing: visible until 1.5 s after the last show.
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    var hud = HUDState()
    check("hud.initiallyHidden", hud.kind == nil && hud.hideAt == nil && !hud.visible(now: t0))
    hud.show(.volume, level: 0.5, muted: false, now: t0)
    check("hud.hideAt", hud.hideAt == t0 + 1.5)
    hud.show(.volume, level: 0.55, muted: false, now: t0 + 1.0)
    check("hud.extends", hud.visible(now: t0 + 2.4) && !hud.visible(now: t0 + 2.6))
    check("hud.state", hud.kind == .volume && abs(hud.level - 0.55) < 1e-6 && hud.muted == false)
    hud.show(.brightness, level: 0.25, muted: true, now: t0 + 3)
    check("hud.kindAndMute", hud.kind == .brightness && hud.muted == true && abs(hud.level - 0.25) < 1e-6)

    // Auto-repeat: holding volume up never overshoots 1.0.
    var held = VolumeLevel(level: 0.0, muted: false)
    var overshoot = false
    for _ in 0..<20 {
        held = applyVolumeKey(.volumeUp, to: held, fine: false)
        if held.level > 1 { overshoot = true }
    }
    check("hud.autoRepeat", abs(held.level - 1.0) < 1e-6 && !overshoot)
}
