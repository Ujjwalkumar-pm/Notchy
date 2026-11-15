import SwiftUI
import NotchyCore

/// Colours and metrics of the open panel (NotchyCore's `Theme` is the Black/Glass setting).
enum Palette {
    static let panel = Color.black
    /// Selected tab pill and secondary (dark) buttons: #2C2C2E.
    static let pill = Color(hex: 0x2C2C2E)
    /// Secondary text: #A1A1A6.
    static let secondary = Color(hex: 0xA1A1A6)
    /// Accent colour from Settings → Appearance (default #7AA7FF). Set by `SettingsStore`;
    /// views re-render through AppModel's settings forwarding.
    @MainActor static var accent: Color { Color(hexString: accentHex) ?? Color(hex: 0x7AA7FF) }
    @MainActor static var accentHex = NotchySettings.defaults.accentHex
    /// Accent choices offered in Settings (name, hex). The first is the default.
    static let accentChoices: [(name: String, hex: String)] = [
        ("Blue", "#7AA7FF"), ("Purple", "#B18CFF"), ("Green", "#30D158"),
        ("Orange", "#FF9F0A"), ("Pink", "#FF6B9D"),
    ]
    /// Label colour for the selected sidebar row: accent at 85 % over the sidebar, black when
    /// white would be under 4.5:1.
    @MainActor static var selectionLabel: Color {
        let ns = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(white: 1, alpha: 1)
        return prefersBlackLabel(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                                 b: Double(ns.blueComponent), alpha: 0.85, backdrop: 0.085) ? .black : .white
    }
    /// Settings switches: #30D158.
    static let switchOn = Color(hex: 0x30D158)
    /// Low-battery red.
    static let warning = Color(hex: 0xFF453A)
    /// Hairline between rows: translucent so it adapts to Black and Glass alike (AUDIT X4);
    /// white 30 % under Increase Contrast.
    static let separator = ThemedColor(Color.white.opacity(0.10), contrast: Color.white.opacity(0.30))
    /// Secondary text under Increase Contrast (open panel, banners, pop-up, Settings): #D1D1D6,
    /// 13.9:1 on black (#A1A1A6 is 7.6:1, white 72 % on Glass ~4.9:1).
    static let secondaryContrast = Color(hex: 0xD1D1D6)
    /// 1 pt outline of Settings thumbnails and the app tile: white 15 %, 40 % under Increase Contrast.
    static let hairlineStroke = ThemedColor(Color.white.opacity(0.15), contrast: Color.white.opacity(0.40))
    /// `secondary` that follows Increase Contrast (banners, pop-up, Settings).
    static let secondaryText = ThemedColor(secondary, contrast: secondaryContrast)

    /// The 6-step type scale (AUDIT X1). Sizes always come from here; SF Symbol and tile-glyph
    /// sizes are iconography, not type, and stay local.
    enum TypeScale {
        /// 10 semibold: section caps, badges, counts.
        static let caption = Font.system(size: 10, weight: .semibold)
        /// 11 regular: times, hints, subtitles in rows.
        static let meta = Font.system(size: 11)
        /// 12 regular: subtitles.
        static let secondary = Font.system(size: 12)
        /// 13 semibold: row titles.
        static let body = Font.system(size: 13, weight: .semibold)
        /// 14 semibold: Now Playing title, banner title.
        static let title = Font.system(size: 14, weight: .semibold)
        /// 13 bold, monospaced digits: rings and percentages.
        static let numeral = Font.system(size: 13, weight: .bold).monospacedDigit()
        /// Nothing is set below this (attendee initials).
        static let minimumSize: CGFloat = 9
    }

    /// Corner radii (AUDIT X3). Always drawn `.continuous`; the countdown ring, capsules and
    /// circles are exempt.
    enum Radius {
        /// Tool chip, shortcut key.
        static let xs: CGFloat = 4
        /// Tiles in rows, command box, chips.
        static let s: CGFloat = 8
        /// Artwork.
        static let m: CGFloat = 12
        /// Banner icon tile (concentric with the banner's 22 pt curve).
        static let bannerTile: CGFloat = 10
        /// Approval card.
        static let l: CGFloat = 16
        /// Open panel's bottom corners.
        static let panel: CGFloat = 30
        /// Banner's bottom corners (closed notch with a banner under it).
        static let banner: CGFloat = 22
        /// Volume/brightness pop-up's bottom corners.
        static let popup: CGFloat = 14
    }

    /// Spacing on a 4 pt grid (AUDIT X2).
    enum Space {
        static let grid: CGFloat = 4
        /// Content inset from the panel's sides (the one off-grid constant, kept on purpose).
        static let sideInset: CGFloat = 18
        /// Padding inside cards.
        static let cardPadding: CGFloat = 12
        /// Gap between sections (card → tab content, player rows).
        static let sectionGap: CGFloat = 12
        /// Content top inset below the notch strip.
        static let contentTop: CGFloat = 8
        /// Content bottom inset.
        static let contentBottom: CGFloat = 16
        /// Page dots' gap above the panel's bottom inside edge (they float over the content's
        /// bottom inset during a swipe only, AUDIT T4; 8 pt per AUDIT X2).
        static let pageDots: CGFloat = 8
        /// Row heights, separator included.
        static let alertRow: CGFloat = 44
        static let calendarRow: CGFloat = 32
        static let sessionRow: CGFloat = 36
    }

    /// Content inset from the panel's sides.
    static let sideInset: CGFloat = Space.sideInset

    // Tab bar (AUDIT T1, T2): one symbol family at 13 pt medium on a 32 × 22 pill (radius
    // 11); layout A's narrower 26 pt slots use an 11 pt glyph on a 24 × 22 pill. The pill gives
    // up its side gap before it shrinks below its width.
    static let tabSlot: CGFloat = 40
    static let tabPillSize = CGSize(width: 32, height: 22)
    static let tabIconSize: CGFloat = 13
    static let tabPillSizeCompact = CGSize(width: 24, height: 22)
    static let tabIconSizeCompact: CGFloat = 11

    // Open-panel colours that follow the theme (AUDIT G1). Glass (frosted, Reduce
    // Transparency off): secondary text white 72 %, pills white 12 %, so nothing reads as an
    // opaque hole; Black: #A1A1A6 and #2C2C2E. Banners, the pop-up and Settings keep the
    // fixed `secondary` / `pill`.
    /// Increase Contrast (Glass then draws solid, see `NotchView`): #D1D1D6 text, #3A3A3C pills,
    /// white 60 % inactive dots.
    static let panelSecondary = ThemedColor(black: secondary, glass: Color.white.opacity(0.72),
                                            contrast: secondaryContrast)
    static let panelPill = ThemedColor(black: pill, glass: Color.white.opacity(0.12), contrast: Color(hex: 0x3A3A3C))
    /// Inactive page dot.
    static let panelDot = ThemedColor(black: Color(white: 0.35), glass: Color.white.opacity(0.35),
                                      contrast: Color.white.opacity(0.6))
    /// Approval card surface (AUDIT G2 a): Black #121212; Glass white 6 % (+ the orange
    /// 45 % stroke on both).
    static let cardFill = ThemedColor(black: Color(white: 0.07), glass: Color.white.opacity(0.06))
    /// The card's command well and the calendar hero's title boxes: recessed on Glass.
    static let cardWell = ThemedColor(black: Color.black, glass: Color.black.opacity(0.35))
    static let heroBox = ThemedColor(black: Color(white: 0.12), glass: Color.white.opacity(0.08))
    /// Attendee avatars' opaque base and cut-out ring (overlapping avatars must hide the one
    /// behind): the panel's own tone, black on Black, the tinted material's mid grey on Glass.
    static let avatarBase = ThemedColor(black: Color.black, glass: Color(white: 0.23))
}

/// True inside the open panel while the Glass theme shows frosted (theme Glass and Reduce
/// Transparency off). Set once on the panel's content by `NotchView`.
private struct NotchGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var notchGlass: Bool {
        get { self[NotchGlassKey.self] }
        set { self[NotchGlassKey.self] = newValue }
    }
}

/// A colour with a Black-theme and a Glass-theme value, picked from `\.notchGlass` when drawn.
/// `contrast` (optional) wins on both themes while Increase Contrast is on.
struct ThemedColor: ShapeStyle {
    let black: Color
    let glass: Color
    var contrast: Color? = nil

    init(black: Color, glass: Color, contrast: Color? = nil) {
        self.black = black
        self.glass = glass
        self.contrast = contrast
    }

    /// The same colour on both themes.
    init(_ both: Color, contrast: Color? = nil) { self.init(black: both, glass: both, contrast: contrast) }

    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.notchIncreaseContrast, let contrast { return contrast }
        return environment.notchGlass ? glass : black
    }
}

extension View {
    /// The one white primary pill (AUDIT B7): 28 pt tall, 14 pt side padding, 13 pt semibold black.
    func whitePill() -> some View {
        font(Palette.TypeScale.body)
            .foregroundColor(.black)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(Color.white))
            .contentShape(Capsule())
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// "#RRGGBB" (or "RRGGBB"); nil when malformed.
    init?(hexString: String) {
        var t = hexString.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
