import SwiftUI
import NotchyCore

/// The volume/brightness pop-up shown in the 28 pt strip below the closed notch:
/// icon on the left, a 6 pt level bar, and the level as a number on the right (AUDIT P1-P3).
struct LevelPopup: View {
    let hud: HUDState

    var body: some View {
        let muted = isLevelMuted(hud)
        HStack(spacing: 8) {
            Image(systemName: levelIcon(hud))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted ? Palette.secondaryText : ThemedColor(.white))
                .frame(width: 18)
            LevelBar(fraction: levelFraction(hud), height: 6, fill: levelFill(hud))
            Text("\(levelPercent(hud))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(ThemedColor(Color.white.opacity(0.7), contrast: .white))
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hud.kind == .brightness ? "Brightness" : "Volume")
        .accessibilityValue(muted ? "muted, \(levelPercent(hud)) percent" : "\(levelPercent(hud)) percent")
    }
}

/// A level bar on a 0.25-white track, fully rounded (height 6 → 3 pt radius).
struct LevelBar: View {
    let fraction: Double
    let height: CGFloat
    var fill: Color = .white

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(fill)
                    .frame(width: g.size.width * fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// True for a muted volume (brightness has no mute).
func isLevelMuted(_ hud: HUDState) -> Bool { hud.kind != .brightness && hud.muted }

/// `speaker.slash.fill` when muted or at 0, else `speaker.wave.2.fill`; brightness `sun.max.fill`.
func levelIcon(_ hud: HUDState) -> String {
    switch hud.kind {
    case .brightness: return "sun.max.fill"
    case .volume, nil: return hud.muted || hud.level <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }
}

/// Bar fill in 0...1: always the real level, so a muted volume still shows where it returns to.
func levelFraction(_ hud: HUDState) -> Double {
    Double(min(max(hud.level, 0), 1))
}

/// The level as 0...100.
func levelPercent(_ hud: HUDState) -> Int { Int((levelFraction(hud) * 100).rounded()) }

/// White; white at 30 % while muted.
func levelFill(_ hud: HUDState) -> Color {
    isLevelMuted(hud) ? Color.white.opacity(0.3) : .white
}
