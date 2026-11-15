import SwiftUI
import NotchyCore

/// The 56 pt strip of a banner below the notch: icon tile, title + subtitle, optional white
/// action pill. Tapping the pill runs the action; tapping anywhere else opens the panel.
struct BannerView: View {
    let banner: Banner
    let onAction: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BannerIcon(kind: banner.kind, service: banner.service)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(Palette.TypeScale.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !banner.subtitle.isEmpty {
                    Text(banner.subtitle)
                        .font(Palette.TypeScale.secondary)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .device(let badge) = banner.kind {
                DeviceTrailing(badge: badge)
            }
            if let label = banner.actionLabel {
                Button(action: onAction) {
                    Text(label).whitePill()
                }
                .buttonStyle(.plain)
                .background(GeometryReader { g in
                    // Hosting-view coordinates (top-left origin); the panel keeps hover from
                    // opening the panel around the pill so it stays clickable.
                    Color.clear.preference(key: BannerActionRectKey.self, value: g.frame(in: .global))
                })
                .accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .center) {
            if isWarning {
                // Low battery: the card turns red (fades out under the notch's black top),
                // clipped to the banner's own rounded bottom corners (AUDIT B1).
                LinearGradient(colors: [Palette.warning.opacity(0.0), Palette.warning.opacity(0.28)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(NotchShape(topCornerRadius: 0, bottomCornerRadius: Palette.Radius.banner))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        // AUDIT Y2: VoiceOver reads title + subtitle and can open the panel (the pill stays
        // its own element inside).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(bannerAccessibilityText(title: banner.title, subtitle: banner.subtitle))
        .accessibilityAction(named: "Open", onOpen)
    }

    private var isWarning: Bool {
        if case .device(let b) = banner.kind { return b.warning }
        return false
    }
}

/// Trailing badge of a device banner: AirPods' compact "L 80 · R 78 · Case 45" trio, a battery
/// ring (other Bluetooth devices), or the Mac's "46%" (the tile already shows the battery glyph).
struct DeviceTrailing: View {
    let badge: DeviceBadge

    var body: some View {
        if let levels = badge.levelsText {
            Text(levels)
                .font(Palette.TypeScale.meta.monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(accessibilityLevels)
        } else if let ring = badge.ring {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(ring, 0), 100)) / 100)
                    .stroke(ringColor(ring), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Never scaled down: 9 pt is the smallest size in the app (Palette.TypeScale).
                Text(ring >= 100 ? "100" : "\(ring)%")
                    .font(.system(size: Palette.TypeScale.minimumSize, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 28, height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery \(ring) percent")
        } else if let pct = badge.battery {
            Text("\(pct)%")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(badge.warning ? Palette.warning : .white)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Battery \(pct) percent")
        }
    }

    private var accessibilityLevels: String {
        var parts: [String] = []
        if let l = badge.left { parts.append("left \(l) percent") }
        if let r = badge.right { parts.append("right \(r) percent") }
        if let c = badge.caseLevel { parts.append("case \(c) percent") }
        return parts.joined(separator: ", ")
    }

    private func ringColor(_ v: Int) -> Color {
        v <= 10 ? Palette.warning : (v <= 20 ? Color.orange : Palette.switchOn)
    }
}

/// 36 pt rounded tile (10 pt continuous): an alert's installed app icon (letter tile as the
/// fallback), a symbol otherwise.
struct BannerIcon: View {
    let kind: Banner.Kind
    var service: String = ""

    var body: some View {
        if case .alert(let app) = kind, let icon = AppIcons.icon(forApp: app) {
            // The app's own icon, no extra tile (AUDIT B5).
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        } else {
            tileView
        }
    }

    private var tileView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Palette.Radius.bannerTile, style: .continuous).fill(tile)
            switch kind {
            case .alert(let app):
                Text(String(app.replacingOccurrences(of: "Microsoft ", with: "").prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            default:
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var tile: Color {
        switch kind {
        case .alert(let app):
            if app.localizedCaseInsensitiveContains("teams") { return Color(hex: 0x5B5FC7) }
            if app.localizedCaseInsensitiveContains("outlook") { return Color(hex: 0x0F6CBD) }
            return Palette.pill
        case .meeting:
            return meetingTintHex(service: service).map { Color(hex: $0) } ?? Palette.pill
        case .device(let b): return b.warning ? Palette.warning.opacity(0.35) : Palette.pill
        case .claudeFinished: return Palette.pill
        }
    }

    private var symbolColor: Color {
        switch kind {
        case .claudeFinished: return Palette.switchOn
        case .device(let b) where b.warning: return Palette.warning
        case .device(let b) where b.dimmed: return Color.white.opacity(0.4)
        case .device(let b) where b.icon == .charger: return Color(hex: 0xFFD60A)
        default: return .white
        }
    }

    private var symbol: String {
        switch kind {
        case .meeting: return "video.fill"
        case .claudeFinished: return "checkmark"
        case .alert: return "bell.fill"
        case .device(let b):
            switch b.icon {
            case .headphones: return "headphones"
            case .bluetooth: return "dot.radiowaves.left.and.right"
            case .charger: return "bolt.fill"
            case .battery: return b.warning ? "battery.25percent" : "battery.75percent"
            case .drive: return "externaldrive.fill"
            case .usb: return "cable.connector"
            }
        }
    }
}

/// The banner's action pill frame in the hosting view (nil when the banner has no action).
struct BannerActionRectKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}
