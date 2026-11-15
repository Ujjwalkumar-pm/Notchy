import SwiftUI
import NotchyCore

/// Alerts tab (mockup view 4): unread count chips + Clear, then newest-first rows (app tile,
/// title, one-line body, relative time). Clicking an app row opens its app; device rows are
/// plain (full colour, nothing to open). At most 5 rows show; 6-10 scroll in place.
struct AlertsTab: View {
    @ObservedObject var app: AppModel
    let live: Bool

    private static let rowHeight = Palette.Space.alertRow
    /// Bottom fade over a scrolling list (AUDIT L4).
    private static let fadeHeight: CGFloat = 16
    private static let footerHeight: CGFloat = 20

    var body: some View {
        let s = app.settings.value
        let items = app.alerts.items
        let chips = s.watchedApps.compactMap { a in app.dockCounts[a].map { (a, $0) } }
        let now = Date()
        let layout = alertListLayout(count: items.count)
        VStack(alignment: .leading, spacing: 0) {
            if !app.axTrusted && !s.watchedApps.isEmpty {
                AccessibilityRow { if live { app.openAccessibilitySettings() } }
            }
            if !chips.isEmpty || !items.isEmpty || app.focusMoon {
                HStack(spacing: 8) {
                    if app.focusMoon { FocusChip() }
                    ForEach(chips, id: \.0) { name, n in CountChip(name: shortAppName(name), count: n) }
                    Spacer(minLength: 8)
                    if !items.isEmpty {
                        Button { if live { app.clearAlerts() } } label: {
                            // No trailing padding: the text's right edge is the time column's (L3).
                            Text("Clear")
                                .font(Palette.TypeScale.meta.weight(.medium))
                                .foregroundStyle(Palette.panelSecondary)
                                .padding(.leading, 8)
                                .frame(height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear alerts")
                    }
                }
                .padding(.vertical, 8)
            }
            if items.isEmpty {
                EmptyState(copy: .noAlerts, live: live)
            } else if layout.scrolls {
                // The frame is fixed so the hidden measuring copy (which cannot draw a
                // ScrollView) sizes to exactly five rows. The 16 pt spacer after the last row
                // keeps the fade from covering it once scrolled to the end.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        rows(items, now: now)
                        Color.clear.frame(height: Self.fadeHeight)
                    }
                }
                .frame(height: CGFloat(layout.visibleRows) * Self.rowHeight)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fadeHeight)
                    }
                }
                Text("+\(items.count - layout.visibleRows) earlier")
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(Palette.panelSecondary)
                    .frame(maxWidth: .infinity, minHeight: Self.footerHeight)
                    .accessibilityLabel("\(items.count - layout.visibleRows) earlier alerts, scroll to see")
            } else {
                rows(items, now: now)
            }
        }
        .onAppear { if live { app.alertsTabOpened() } }
    }

    private func rows(_ items: [AlertItem], now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Rectangle().fill(Palette.separator).frame(height: 1) }
                AlertRow(item: item, now: now) { if live { app.openAlertApp(item) } }
                    .frame(height: Self.rowHeight - (i > 0 ? 1 : 0))
            }
        }
    }
}

/// Needs-Accessibility prompt (AUDIT L2): lock tile, two lines, `Allow…` pill.
private struct AccessibilityRow: View {
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous).fill(Palette.panelPill)
                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Palette.panelSecondary)
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Show Teams & Outlook messages")
                    .font(Palette.TypeScale.secondary.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Needs Accessibility permission")
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(Palette.panelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: onAllow) { Text("Allow\u{2026}").whitePill() }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

/// Focus is on (AUDIT L6): a chip like the counts, purple moon.
private struct FocusChip: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: 0xA78BFA))
            Text("Focus").font(Palette.TypeScale.meta.weight(.medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.panelPill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus on, banners paused")
    }
}

/// Count chip (AUDIT L7): neutral in-panel chip, no red.
private struct CountChip: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(name).font(Palette.TypeScale.meta.weight(.medium)).foregroundColor(.white)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.85))
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(Capsule().fill(Palette.panelPill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(count) unread")
    }
}

private struct AlertRow: View {
    let item: AlertItem
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        // Device rows are not buttons (L1): full colour, no dimming, nothing to open.
        if item.device {
            content.accessibilityElement(children: .combine)
        } else {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            AlertTile(item: item)
            VStack(alignment: .leading, spacing: 2) {
                // The time shares the title's baseline (L8).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(Palette.TypeScale.body)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(relativeTime(item.at, now: now))
                        .font(Palette.TypeScale.meta.monospacedDigit())
                        .foregroundStyle(Palette.panelSecondary)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(Palette.TypeScale.meta)
                        .foregroundStyle(Palette.panelSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 26 pt tile: app initial on its colour (Outlook blue, Teams purple) or a device symbol.
private struct AlertTile: View {
    let item: AlertItem

    var body: some View {
        if !item.device, let icon = AppIcons.icon(forApp: item.app) {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        } else { letterTile }
    }

    private var letterTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous).fill(tile)
            if item.device {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(symbolColor)
            } else {
                Text(String(shortAppName(item.app).prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private var tile: ThemedColor {
        if item.device { return Palette.panelPill }
        if item.app.localizedCaseInsensitiveContains("teams") { return ThemedColor(Color(hex: 0x5B5FC7)) }
        if item.app.localizedCaseInsensitiveContains("outlook") { return ThemedColor(Color(hex: 0x0F6CBD)) }
        return Palette.panelPill
    }

    private var symbolColor: Color {
        DeviceIcon(rawValue: item.app) == .charger ? Color(hex: 0xFFD60A) : .white
    }

    private var symbol: String {
        switch DeviceIcon(rawValue: item.app) {
        case .headphones?: return "headphones"
        case .bluetooth?: return "dot.radiowaves.left.and.right"
        case .charger?: return "bolt.fill"
        case .battery?: return "battery.75percent"
        case .drive?: return "externaldrive.fill"
        case .usb?: return "cable.connector"
        case nil: return "bell.fill"
        }
    }
}
