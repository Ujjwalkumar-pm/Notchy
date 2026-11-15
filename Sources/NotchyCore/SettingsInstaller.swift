import Foundation

public enum InstallResult: Equatable, Sendable {
    case alreadyInstalled
    case installed(backup: URL?)
    case unreadable
}

/// Adds / removes Notchy's hook entries in a Claude Code settings.json,
/// never touching entries that belong to anyone else.
///
/// Status events use a `command` hook (curl, output discarded, always exit 0) so a
/// quit Notchy produces no hook errors; PermissionRequest stays an `http` hook.
/// An entry is Notchy's when its `url` or `command` contains `127.0.0.1:7850/`.
public struct SettingsInstaller: Sendable {
    public let settingsURL: URL

    public init(settingsURL: URL) { self.settingsURL = settingsURL }

    static let marker = "127.0.0.1:7850/"
    static let urlPrefix = "http://127.0.0.1:7850/"
    public static let eventCommand = "/usr/bin/curl -s -m 2 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:7850/hooks/event >/dev/null 2>&1; exit 0"
    static let eventNames = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                             "Notification", "Stop", "SessionEnd"]
    static let permissionEvent = "PermissionRequest"
    static var allEvents: [String] { eventNames + [permissionEvent] }

    private static func hook(for event: String) -> [String: Any] {
        if event == permissionEvent {
            return ["type": "http", "url": urlPrefix + "hooks/permission", "timeout": 150]
        }
        return ["type": "command", "command": eventCommand, "timeout": 5]
    }

    private static func group(for event: String) -> [String: Any] {
        if event == permissionEvent { return ["matcher": "*", "hooks": [hook(for: event)]] }
        return ["hooks": [hook(for: event)]]
    }

    private static func isNotchyHook(_ h: Any) -> Bool {
        guard let d = h as? [String: Any] else { return false }
        if let u = d["url"] as? String, u.contains(marker) { return true }
        if let c = d["command"] as? String, c.contains(marker) { return true }
        return false
    }

    private static func hasNotchy(_ groups: [Any]) -> Bool {
        groups.contains { g in
            ((g as? [String: Any])?["hooks"] as? [Any])?.contains(where: isNotchyHook) ?? false
        }
    }

    /// True when the event has exactly one Notchy hook and it is the current form
    /// (in a group of its own shape, i.e. what `group(for:)` produces).
    private static func isCurrent(_ groups: [Any], event: String) -> Bool {
        var found = 0
        var exact = false
        for g in groups {
            guard let d = g as? [String: Any], let hs = d["hooks"] as? [Any] else { continue }
            for h in hs where isNotchyHook(h) {
                found += 1
                exact = (d as NSDictionary).isEqual(to: group(for: event))
            }
        }
        return found == 1 && exact
    }

    /// Removes every Notchy hook from `groups`, keeping foreign hooks (and their groups).
    private static func strippingNotchy(_ groups: [Any]) -> [Any] {
        var kept: [Any] = []
        for g in groups {
            guard var d = g as? [String: Any], let hs = d["hooks"] as? [Any],
                  hs.contains(where: isNotchyHook) else { kept.append(g); continue }
            let rest = hs.filter { !isNotchyHook($0) }
            if !rest.isEmpty { d["hooks"] = rest; kept.append(d) }
        }
        return kept
    }

    private enum Loaded {
        case missing
        case unreadable
        case ok(raw: Data, root: [String: Any])
    }

    private func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .missing }
        guard let raw = try? Data(contentsOf: settingsURL),
              let any = try? JSONSerialization.jsonObject(with: raw),
              let root = any as? [String: Any] else { return .unreadable }
        if let h = root["hooks"], !(h is [String: Any]) { return .unreadable }
        return .ok(raw: raw, root: root)
    }

    public func isInstalled() -> Bool {
        guard case .ok(_, let root) = load(),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.allEvents.allSatisfy { ev in
            (hooks[ev] as? [Any]).map { Self.isCurrent($0, event: ev) } ?? false
        }
    }

    private func write(_ root: [String: Any], original: Data?, now: Date) -> (ok: Bool, backup: URL?) {
        guard let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return (false, nil) }
        var backup: URL?
        if let original {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("\(settingsURL.lastPathComponent).notchy-bak-\(f.string(from: now))")
            guard (try? original.write(to: b, options: .atomic)) != nil else { return (false, nil) }
            backup = b
        } else {
            try? FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard (try? out.write(to: settingsURL, options: .atomic)) != nil else { return (false, backup) }
        return (true, backup)
    }

    public func install(now: Date) -> InstallResult {
        var root: [String: Any] = [:]
        var original: Data?
        switch load() {
        case .unreadable: return .unreadable
        case .missing: break
        case .ok(let raw, let r): root = r; original = raw
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for ev in Self.allEvents {
            var groups = hooks[ev] as? [Any] ?? []
            if Self.isCurrent(groups, event: ev) { continue }
            // Missing, duplicated or an older form (e.g. http status hooks): replace.
            groups = Self.strippingNotchy(groups)
            groups.append(Self.group(for: ev))
            hooks[ev] = groups
            changed = true
        }
        if !changed { return .alreadyInstalled }
        root["hooks"] = hooks
        let r = write(root, original: original, now: now)
        return r.ok ? .installed(backup: r.backup) : .unreadable
    }

    @discardableResult
    public func uninstall(now: Date) -> Bool {
        guard case .ok(let raw, var root) = load(),
              var hooks = root["hooks"] as? [String: Any] else { return false }
        var changed = false
        for (ev, value) in hooks {
            guard let groups = value as? [Any], Self.hasNotchy(groups) else { continue }
            let kept = Self.strippingNotchy(groups)
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = kept }
        }
        if !changed { return false }
        root["hooks"] = hooks
        return write(root, original: raw, now: now).ok
    }
}
