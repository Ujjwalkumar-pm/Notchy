import AppKit

/// The icon of an app the user already has installed (AUDIT B5). Notchy ships no app icons: it
/// asks macOS for the one on disk. Looked up by the app's display name ("Microsoft Teams").
/// Views only read the cache (`icon`); the lookup (a few file-exists calls) runs in `prewarm`,
/// when an alert arrives, never during a render. Misses are retried after 10 minutes. Main
/// thread only; nil -> the caller keeps its letter tile.
@MainActor
enum AppIcons {
    private static var cache: [String: (image: NSImage?, at: Date)] = [:]
    private static let retryAfter: TimeInterval = 10 * 60

    /// Cached icon only; never searches.
    static func icon(forApp name: String) -> NSImage? { cache[name]?.image }

    /// Resolves and caches `name` (a miss is retried once 10 minutes old).
    static func prewarm(_ name: String, now: Date = Date()) {
#if NOTCHY_CAPTURE
        return
#endif
        if let e = cache[name], e.image != nil || now.timeIntervalSince(e.at) < retryAfter { return }
        cache[name] = (lookup(name), now)
    }

    private static func lookup(_ name: String) -> NSImage? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { return nil }
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var candidates = [trimmed]
        if trimmed.hasPrefix("Microsoft ") { candidates.append(String(trimmed.dropFirst("Microsoft ".count))) }
        for n in candidates {
            for d in dirs {
                let path = "\(d)/\(n).app"
                if fm.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
            }
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == trimmed }),
           let url = running.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
