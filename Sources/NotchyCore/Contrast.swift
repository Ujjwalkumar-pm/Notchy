import Foundation

/// WCAG relative luminance of an sRGB colour (components 0...1).
public func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// WCAG contrast ratio between two luminances.
public func contrastRatio(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// Whether text on `colour` drawn at `alpha` over a grey of `backdrop` (0...1) should be black:
/// true when white would reach less than 4.5:1 on the blended colour (AUDIT S2 selection row).
public func prefersBlackLabel(r: Double, g: Double, b: Double, alpha: Double, backdrop: Double) -> Bool {
    let lum = relativeLuminance(r: r * alpha + backdrop * (1 - alpha),
                                g: g * alpha + backdrop * (1 - alpha),
                                b: b * alpha + backdrop * (1 - alpha))
    return contrastRatio(1, lum) < 4.5
}
