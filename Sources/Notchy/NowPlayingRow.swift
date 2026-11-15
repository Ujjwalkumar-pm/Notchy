import SwiftUI
import AppKit
import NotchyCore

/// Last decoded artwork, keyed on the bytes themselves (not a hash, which can collide and
/// show stale art) so redraws don't re-decode the image.
@MainActor
private enum ArtworkCache {
    private static var key: Data?
    private static var image: NSImage?
    static func image(for data: Data) -> NSImage? {
        if key == data { return image }
        key = data
        image = NSImage(data: data)
        return image
    }
}

/// Five accent bars. Animated only in the live copy while playing; otherwise a static frame, so
/// the hidden measuring copy and a paused track never wake the CPU.
/// Sits inline after the title (AUDIT M6), 14 x 12 pt. Paused: 3 pt bars in secondary at 50 %
/// (M1), eased between the two looks over 0.25 s.
private struct SoundBars: View {
    let animated: Bool
    let playing: Bool
    @Environment(\.notchReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
                    bars(t: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(t: nil)
            }
        }
        .frame(width: 14, height: 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: playing)
        .accessibilityHidden(true)
    }

    private func bars(t: Double?) -> some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let f: Double = t.map { 0.5 + 0.5 * sin($0 * (3.1 + Double(i) * 0.9) + Double(i) * 1.7) } ?? 0.4
                Capsule()
                    .fill(playing ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.panelSecondary.opacity(0.5)))
                    .frame(width: 2, height: playing ? 3 + 9 * f : 3)
            }
        }
    }
}

/// Large white glyph with a white 10 % circle behind it only while pressed (AUDIT M2).
private struct GlyphPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0)))
    }
}

/// Clock column width: "-0:00:00" measured in the monospaced-digit clock font (AUDIT M7), so
/// an hour-long track never truncates or shifts the bar.
@MainActor
private let clockColumnWidth: CGFloat = {
    let f = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    return ceil(("-0:00:00" as NSString).size(withAttributes: [.font: f]).width)
}()

/// The Music tab's player: artwork, title/artist, sound bars, progress, controls.
struct NowPlayingRow: View {
    let info: NowPlayingInfo
    /// False in the hidden measuring copy: buttons are inert and nothing animates or ticks.
    let live: Bool
    let onCommand: (MediaCommand) -> Void
    let onSeek: (Double) -> Void
    /// Bar fraction while the pointer is down on the scrubber; nil otherwise.
    private let dragState = State<Double?>(initialValue: nil)
    private let hoverState = State(initialValue: false)
#if NOTCHY_CAPTURE
    @ObservedObject private var capture = CaptureState.shared
#endif

    var body: some View {
        VStack(spacing: Palette.Space.sectionGap) {
            HStack(spacing: 12) {
                art
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(info.title)
                            .font(Palette.TypeScale.title)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        SoundBars(animated: live && info.isPlaying, playing: info.isPlaying)
                            .layoutPriority(1)
                    }
                    // AUDIT M5 (13 pt regular) supersedes Task 2's 12 pt token here.
                    Text(info.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
            }
            progress
            controls
        }
        .padding(.vertical, 8)
    }

    /// One stable structure: the TimelineView is always present (only its period changes: 1 s vs effectively idle), so
    /// the drag gesture's host never changes identity mid-drag. It ticks only while live and
    /// playing; while dragging, the bar shows the drag position and ignores ticks.
    @ViewBuilder private var progress: some View {
        if let duration = info.duration, duration > 0 {
            let ticking = live && info.isPlaying
            TimelineView(.periodic(from: .now, by: ticking ? 1 : 3600)) { ctx in
                progressBar(duration: duration, now: ticking ? ctx.date : Date())
            }
            .onDisappear { dragState.wrappedValue = nil; hoverState.wrappedValue = false }
        }
    }

    private func progressBar(duration: Double, now: Date) -> some View {
#if NOTCHY_CAPTURE
        var dragging = dragState.wrappedValue
        var hovering = hoverState.wrappedValue
        if live, let s = capture.scrub { dragging = s }
        if live, capture.scrubHover { hovering = true }
#else
        let dragging = dragState.wrappedValue
        let hovering = hoverState.wrappedValue
#endif
        let e = dragging.map { min(max($0, 0), 1) * duration } ?? (elapsedNow(info, now: now) ?? 0)
        let frac = CGFloat(min(1, e / duration))
        let showKnob = live && (dragging != nil || hovering)
        let hours = duration >= 3600
        return HStack(spacing: 8) {
            Text(formatClock(e, hours: hours)).frame(width: clockColumnWidth, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.panelPill).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: g.size.width * frac, height: 4)
                    if showKnob {
                        Circle().fill(Color.white).frame(width: 10, height: 10)
                            .offset(x: min(max(g.size.width * frac - 5, 0), max(0, g.size.width - 10)))
                    }
                }
                .frame(maxHeight: .infinity)
#if NOTCHY_CAPTURE
                .background(GeometryReader { bar in
                    Color.clear
                        .onAppear { if live { CaptureState.shared.scrubberRect = bar.frame(in: .global) } }
                        .onChange(of: bar.frame(in: .global)) { _, r in if live { CaptureState.shared.scrubberRect = r } }
                })
#endif
                .contentShape(Rectangle())
                .gesture(live ? DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        dragState.wrappedValue = scrubFraction(x: Double(v.location.x), width: Double(g.size.width))
                    }
                    .onEnded { v in
                        let f = scrubFraction(x: Double(v.location.x), width: Double(g.size.width))
                        dragState.wrappedValue = nil
                        if let t = seekPosition(fraction: f, duration: duration) { onSeek(t) }
                    } : nil)
                .onHover { if live { hoverState.wrappedValue = $0 } }
            }
            .frame(height: 18)
            Text("-" + formatClock(duration - e, hours: hours)).frame(width: clockColumnWidth, alignment: .trailing)
        }
        .font(Palette.TypeScale.meta.monospacedDigit())
        .foregroundStyle(Palette.panelSecondary)
        // AUDIT Y2: an adjustable element; VoiceOver steps it ±10 s.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatClock(e, hours: hours)) of \(formatClock(duration, hours: hours))")
        .accessibilityAdjustableAction { direction in
            guard live else { return }
            switch direction {
            case .increment: onSeek(scrubberAdjusted(elapsed: e, duration: duration, increment: true))
            case .decrement: onSeek(scrubberAdjusted(elapsed: e, duration: duration, increment: false))
            @unknown default: break
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            shuffleButton
            button("backward.fill", label: "Previous track", size: 18, .previous)
            Button { if live { onCommand(.togglePlayPause) } } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(GlyphPressStyle())
            .disabled(!live)
            .accessibilityLabel(info.isPlaying ? "Pause" : "Play")
            button("forward.fill", label: "Next track", size: 18, .next)
            Button {
                guard live, let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.panelSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!live)
            .accessibilityLabel("Sound output")
        }
        .frame(maxWidth: .infinity)
    }

    /// On: accent + 3 pt dot. Off: white 60 %. Unsupported: hidden, 32 pt spacer (AUDIT M3).
    @ViewBuilder private var shuffleButton: some View {
        switch ShuffleAppearance(info.shuffle) {
        case .unsupported:
            Color.clear.frame(width: 32, height: 32)
        case let a:
            let on = a == .on
            Button { if live { onCommand(.toggleShuffle) } } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 14))
                    .foregroundColor(on ? Palette.accent : Color.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .overlay(alignment: .bottom) {
                        if on { Circle().fill(Palette.accent).frame(width: 3, height: 3).offset(y: -1) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!live)
            .accessibilityLabel("Shuffle")
            .accessibilityValue(on ? "On" : "Off")
        }
    }

    @ViewBuilder private var art: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.Radius.m, style: .continuous)
        if let data = info.artwork, let img = ArtworkCache.image(for: data) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 58, height: 58)
                .clipShape(shape)
        } else {
            shape.fill(ThemedColor(black: Color(white: 0.16), glass: Color.white.opacity(0.12)))
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.panelSecondary))
        }
    }

    private func button(_ symbol: String, label: String, size: CGFloat,
                        _ cmd: MediaCommand) -> some View {
        Button { if live { onCommand(cmd) } } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!live)
        .accessibilityLabel(label)
    }
}
