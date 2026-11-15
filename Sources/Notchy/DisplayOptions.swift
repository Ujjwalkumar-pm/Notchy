import AppKit
import SwiftUI
import Combine

/// System accessibility display options Notchy follows (AUDIT N1, Increase Contrast): read
/// once and again on `accessibilityDisplayOptionsDidChangeNotification` (no polling). The
/// panel reads `reduceMotion` for its window animations; SwiftUI views get both through the
/// `notchReduceMotion` / `notchIncreaseContrast` environment values set at each root view.
@MainActor
final class DisplayOptions: ObservableObject {
    static let shared = DisplayOptions()

    @Published private(set) var reduceMotion: Bool
    @Published private(set) var increaseContrast: Bool
    private var observer: NSObjectProtocol?

    private init() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
        observer = ws.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let ws = NSWorkspace.shared
        let rm = ws.accessibilityDisplayShouldReduceMotion
        let ic = ws.accessibilityDisplayShouldIncreaseContrast
        if rm != reduceMotion { reduceMotion = rm }
        if ic != increaseContrast { increaseContrast = ic }
        notchyLog.notice("display options: reduce motion \(rm), increase contrast \(ic)")
    }
}

private struct NotchReduceMotionKey: EnvironmentKey { static let defaultValue = false }
private struct NotchIncreaseContrastKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// System Reduce Motion (via `DisplayOptions`): fades and static versions only.
    var notchReduceMotion: Bool {
        get { self[NotchReduceMotionKey.self] }
        set { self[NotchReduceMotionKey.self] = newValue }
    }
    /// System Increase Contrast (via `DisplayOptions`): stronger secondary text and lines,
    /// Glass drawn solid.
    var notchIncreaseContrast: Bool {
        get { self[NotchIncreaseContrastKey.self] }
        set { self[NotchIncreaseContrastKey.self] = newValue }
    }
}
