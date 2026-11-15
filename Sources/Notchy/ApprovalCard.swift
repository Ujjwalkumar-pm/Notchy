import SwiftUI
import NotchyCore

enum NotchColors {
    static let working = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x84 / 255) // #3DDC84
    static let waiting = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255) // #FFB340
    static let quiet = Color(white: 0.45)
    /// `quiet` under Increase Contrast.
    static let quietContrast = Color(white: 0.70)
    static let denyText = Color(red: 1.0, green: 0.42, blue: 0.42)
}

/// Permission request card: project, tool, exact command, Deny / Allow once.
/// Buttons take clicks only when the panel's ArmingGate says so: ≥ 0.5 s after this request
/// appeared AND the pointer entered the card afterwards and stayed ≥ 0.4 s (see NotchPanel).
/// Until then they keep full colour with dimmed labels, and a thin line inside the Allow pill
/// shows the gate's own progress (AUDIT A1); it reads complete only once the gate has armed.
struct ApprovalCard: View {
    /// Increase Contrast: the orange outline at 90 % (45 % otherwise).
    @Environment(\.notchIncreaseContrast) private var increaseContrast
    let request: ApprovalRequest
    let pendingCount: Int
    /// Sessions owning the other queued cards, when they differ from this one's.
    var otherLabels: [String] = []
    /// The request id whose buttons are armed (from the panel), or nil.
    var armedId: UUID?
    /// The ArmingGate's progress for the showing card (0…1, 1 only when armed).
    var armProgress: Double = 0
    /// The command box shows up to 12 lines instead of 5 (after "Show all").
    var commandExpanded: Bool = false
    var onShowAll: (UUID) -> Void = { _ in }
    /// False for the hidden measuring copy: it must never arm or report its frame.
    var live: Bool = true
    let onDecision: (UUID, PermissionDecision) -> Void

    private var armed: Bool { live && armedId == request.id }
    /// Shown progress: the gate's value, but never "complete" unless this card is armed.
    private var shownProgress: Double {
        guard live else { return 0 }
        return armed ? 1 : min(armProgress, ArmingGate.progressCapBeforeArmed)
    }
    private var needsShowAll: Bool { commandNeedsShowAll(request.summary) }

    var body: some View {
        VStack(alignment: .leading, spacing: CommandMetrics.stackSpacing) {
            HStack(spacing: 8) {
                Circle().fill(NotchColors.waiting).frame(width: 7, height: 7)
                Text("Needs approval · \(request.toolName)")
                    .font(Palette.TypeScale.body)
                    .foregroundColor(NotchColors.waiting)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(request.label)
                    .font(Palette.TypeScale.body)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if pendingCount > 1 {
                    // AUDIT A5: the queue count lives in the header as a small pill.
                    Text("+\(pendingCount - 1)")
                        .font(Palette.TypeScale.caption.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(Palette.panelPill))
                        .help(moreWaitingText)
                        .accessibilityLabel(moreWaitingText)
                }
            }
            .accessibilityElement(children: .combine)

            commandBox
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Palette.Radius.s, style: .continuous).fill(Palette.cardWell))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Command: \(request.summary)")

            if needsShowAll && !commandExpanded {
                // Expands only (no collapse): a shrinking card could pull Allow up under the
                // pointer. Not an arming path: it disarms (see NotchViewModel.expandCommand).
                Button("Show all") { if live { onShowAll(request.id) } }
                    .buttonStyle(.plain)
                    .font(Palette.TypeScale.meta)
                    .foregroundStyle(Palette.panelSecondary)
                    .frame(minHeight: CommandMetrics.showAllRowHeight)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Show the whole command")
            }

            if commandNeedsTruncationNote(request.summary) {
                // Allow stays enabled (ruling): the terminal always shows the full command.
                Text("Truncated — check the full command in the terminal")
                    .font(Palette.TypeScale.meta.weight(.semibold))
                    .foregroundColor(NotchColors.waiting)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Deny") { decide(.deny(message: "Denied from Notchy")) }
                    .buttonStyle(CardButtonStyle(fill: Palette.panelPill, text: NotchColors.denyText, armed: armed))
                    .accessibilityLabel("Deny \(request.toolName) for \(request.label)")
                Button("Allow once") { decide(.allow) }
                    .buttonStyle(CardButtonStyle(fill: ThemedColor(.white), text: .black, armed: armed,
                                                 progress: shownProgress))
                    .accessibilityLabel("Allow \(request.toolName) once for \(request.label)")
            }
            .disabled(!armed)
            .help(armed ? "" : "Hold the pointer on the card to enable")

            // Answers `{}`: Claude Code falls back to its own terminal prompt. Can't approve,
            // so it needs no arming.
            Button { if live { onDecision(request.id, .none) } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "terminal").font(.system(size: 10))
                    Text("Answer in terminal")
                }
            }
            .buttonStyle(.plain)
            .font(Palette.TypeScale.meta.weight(.medium))
            .foregroundStyle(Palette.panelSecondary)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Dismiss this request and answer in the terminal")
        }
        .padding(Palette.Space.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Palette.Radius.l, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(RoundedRectangle(cornerRadius: Palette.Radius.l, style: .continuous)
                    .strokeBorder(NotchColors.waiting.opacity(increaseContrast ? 0.9 : 0.45), lineWidth: 1))
        )
        .background(GeometryReader { g in
            // Hosting-view coordinates (top-left origin); the panel turns them into screen ones.
            Color.clear.preference(key: CardRectKey.self, value: live ? g.frame(in: .global) : nil)
        })
    }

    /// AUDIT A2: up to 5 lines (80 pt) in a scroll view fading out over its last 8 pt; after
    /// "Show all", up to 12 lines in place.
    @ViewBuilder private var commandBox: some View {
        let text = Text(request.summary.isEmpty ? " " : request.summary)
            .font(Palette.TypeScale.secondary.monospaced())
            .foregroundColor(.white)
            .lineSpacing(CommandMetrics.lineSpacing)
            .lineLimit(cardCommandMaxLines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if needsShowAll && !commandExpanded {
            ScrollView(.vertical) { text }
                .frame(height: CommandMetrics.collapsedHeight)
                .mask(VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                })
        } else if needsShowAll {
            // Expanded: never shorter than collapsed box + the removed "Show all" row and its
            // spacing, so nothing below (Allow / Deny) moves up under the pointer.
            text.frame(minHeight: CommandMetrics.collapsedHeight + CommandMetrics.showAllRowHeight
                       + CommandMetrics.stackSpacing, alignment: .top)
        } else {
            text
        }
    }

    private var moreWaitingText: String {
        let base = "\(pendingCount - 1) more waiting"
        guard !otherLabels.isEmpty else { return "\(base) from \(request.label)" }
        return "\(base): \(otherLabels.joined(separator: ", "))"
    }

    private func decide(_ d: PermissionDecision) {
        guard armed else { return }
        onDecision(request.id, d)
    }
}

/// 12 pt monospaced command text on a 16 pt line height.
private enum CommandMetrics {
    /// Collapsed command area: 5 lines × 16 pt.
    static let collapsedHeight = CGFloat(cardCommandCollapsedLines) * CGFloat(cardCommandLineHeight)
    /// "Show all" row (24 pt hit area) and the card's VStack spacing above it.
    static let showAllRowHeight: CGFloat = 24
    static let stackSpacing: CGFloat = 8
    @MainActor static let lineSpacing: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        return max(0, CGFloat(cardCommandLineHeight) - natural)
    }()
}

/// The live approval card's frame in the hosting view (nil when no live card is showing).
struct CardRectKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct CardButtonStyle: ButtonStyle {
    let fill: ThemedColor
    let text: Color
    /// Disarmed: full-colour pill, label at 45 % (AUDIT A1). Armed: label at 100 %.
    let armed: Bool
    /// Dwell progress (0…1) drawn as a 2 pt line along the pill's bottom inside edge; nil = none.
    var progress: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Palette.TypeScale.body)
            .foregroundColor(text.opacity(armed ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(fill))
            .overlay {
                if let progress {
                    GeometryReader { g in
                        // Only the capsule's flat section (inset by its corner radius), raised
                        // 3 pt, so the unfilled gap before arming is always visible. Armed: the
                        // whole track turns solid black (unmistakably "complete").
                        let r = g.size.height / 2
                        let track = max(0, g.size.width - 2 * r)
                        Rectangle()
                            .fill(armed ? Color.black : Color.black.opacity(0.45))
                            .frame(width: armed ? track : track * min(max(progress, 0), 1), height: 2)
                            .position(x: r + (armed ? track : track * min(max(progress, 0), 1)) / 2,
                                      y: g.size.height - 3 - 1)
                    }
                    // Follows the gate's 20 Hz ticks; it only ever trails the real value.
                    .animation(.linear(duration: 0.05), value: progress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .clipShape(Capsule())
            .opacity(armed && configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}
