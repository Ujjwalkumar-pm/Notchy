import Foundation
import NotchyCore

/// Notchy's settings, persisted as JSON under UserDefaults `notchySettings`. Changes apply live.
@MainActor
final class SettingsStore: ObservableObject {
    static let key = "notchySettings"
    private let defaults: UserDefaults
    @Published private(set) var value: NotchySettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let present = existingUserMarkerKeys.filter { defaults.object(forKey: $0) != nil }
        value = launchSettings(defaults.data(forKey: Self.key), presentKeys: present)
        Palette.accentHex = value.accentHex
    }

    /// Applies `f` and saves (no write when nothing changed).
    func update(_ f: (inout NotchySettings) -> Void) {
        var copy = value
        f(&copy)
        guard copy != value else { return }
        Palette.accentHex = copy.accentHex
        value = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
