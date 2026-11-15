import Foundation
import NotchyCore

private let allEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "Notification", "Stop", "SessionEnd", "PermissionRequest"]

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("notchy-si-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private let fixture = """
{
  "model": "x",
  "hooks": {
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "orca-hook pre" } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/bin/start.sh" } ] }
    ]
  }
}
"""

private func obj(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func groups(_ data: Data, _ event: String) -> [[String: Any]] {
    ((obj(data)?["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
}

private func isNotchy(_ g: [String: Any]) -> Bool {
    let hs = g["hooks"] as? [[String: Any]] ?? []
    return hs.contains {
        ($0["url"] as? String)?.contains("127.0.0.1:7850/") == true
            || ($0["command"] as? String)?.contains("127.0.0.1:7850/") == true
    }
}

private let statusEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                            "Notification", "Stop", "SessionEnd"]
private let expectedCommand = "/usr/bin/curl -s -m 2 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:7850/hooks/event >/dev/null 2>&1; exit 0"

/// The single Notchy hook dict for `event`, or nil if there isn't exactly one.
private func notchyHook(_ data: Data, _ event: String) -> [String: Any]? {
    let all = groups(data, event).flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
        .filter { isNotchy(["hooks": [$0]]) }
    return all.count == 1 ? all[0] : nil
}

private func isCommandForm(_ h: [String: Any]?) -> Bool {
    h?["type"] as? String == "command" && h?["command"] as? String == expectedCommand
        && h?["timeout"] as? Int == 5 && h?["url"] == nil
}

/// Old (pre-14 Nov) settings: http status hooks, plus foreign hooks.
private let oldHttpFixture = """
{
  "model": "x",
  "hooks": {
    "PreToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "orca-hook pre" } ] },
      { "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }
    ],
    "SessionStart": [{ "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }],
    "UserPromptSubmit": [{ "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }],
    "PostToolUse": [{ "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }],
    "Notification": [{ "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "keep-me" },
                   { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }
    ],
    "SessionEnd": [{ "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/event", "timeout": 5 } ] }],
    "PermissionRequest": [{ "matcher": "*", "hooks": [ { "type": "http", "url": "http://127.0.0.1:7850/hooks/permission", "timeout": 150 } ] }],
    "SubagentStop": [{ "hooks": [ { "type": "command", "command": "foreign-sub" } ] }]
  }
}
"""

private func backups(in dir: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("settings.json.notchy-bak-") }
}

func runSettingsInstallerChecks() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    do { // appendsKeepsOthers
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(fixture.utf8).write(to: url)
        let r = SettingsInstaller(settingsURL: url).install(now: now)
        let out = (try? Data(contentsOf: url)) ?? Data()
        let o = obj(out)
        let pre = groups(out, "PreToolUse")
        check("appendsInstalled", { if case .installed = r { return true } else { return false } }())
        check("appendsKeepsModel", o?["model"] as? String == "x")
        check("appendsKeepsOriginal", pre.count == 2 && pre[0]["matcher"] as? String == "*"
              && ((pre[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "orca-hook pre")
        check("appendsNotchyGroup", pre.count == 2 && isNotchy(pre[1]))
        check("appendsAllEvents", allEvents.allSatisfy { groups(out, $0).contains(where: isNotchy) })
        let perm = groups(out, "PermissionRequest").first
        let ph = (perm?["hooks"] as? [[String: Any]])?.first
        check("appendsPermissionShape", perm?["matcher"] as? String == "*"
              && ph?["url"] as? String == "http://127.0.0.1:7850/hooks/permission"
              && ph?["timeout"] as? Int == 150)
        check("appendsSlashesUnescaped", !(String(data: out, encoding: .utf8) ?? "").contains("\\/"))
        check("appendsIsInstalled", SettingsInstaller(settingsURL: url).isInstalled())
    }
    do { // idempotent
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(fixture.utf8).write(to: url)
        let s = SettingsInstaller(settingsURL: url)
        _ = s.install(now: now)
        let first = (try? Data(contentsOf: url)) ?? Data()
        let nb = backups(in: dir).count
        let r = s.install(now: now.addingTimeInterval(60))
        let second = (try? Data(contentsOf: url)) ?? Data()
        check("idempotentResult", r == .alreadyInstalled)
        check("idempotentBytes", first == second)
        check("idempotentNoNewBackup", backups(in: dir).count == nb)
    }
    do { // backupWritten
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        let original = Data(fixture.utf8)
        try? original.write(to: url)
        let r = SettingsInstaller(settingsURL: url).install(now: now)
        var bak: URL?
        if case .installed(let b) = r { bak = b }
        check("backupReturned", bak != nil)
        check("backupEqualsOriginal", bak.flatMap { try? Data(contentsOf: $0) } == original)
        check("backupInSameDir", bak?.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        check("backupName", bak?.lastPathComponent == "settings.json.notchy-bak-\(f.string(from: now))")
    }
    do { // missingFileCreated
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        let r = SettingsInstaller(settingsURL: url).install(now: now)
        check("missingResult", r == .installed(backup: nil))
        check("missingCreated", SettingsInstaller(settingsURL: url).isInstalled())
        check("missingNoBackup", backups(in: dir).isEmpty)
    }
    do { // invalidJsonUntouched
        let bad: [String] = ["{oops", "[1,2]", "{\"hooks\": 5}"]
        for (i, text) in bad.enumerated() {
            let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
            let original = Data(text.utf8)
            try? original.write(to: url)
            let s = SettingsInstaller(settingsURL: url)
            let r = s.install(now: now)
            check("invalidResult\(i)", r == .unreadable)
            check("invalidBytes\(i)", (try? Data(contentsOf: url)) == original)
            check("invalidNoBackup\(i)", backups(in: dir).isEmpty)
            check("invalidUninstallNoop\(i)", s.uninstall(now: now) == false
                  && (try? Data(contentsOf: url)) == original && backups(in: dir).isEmpty)
        }
    }
    do { // partialInstallCompletes
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        let s = SettingsInstaller(settingsURL: url)
        _ = s.install(now: now)
        var o = obj((try? Data(contentsOf: url)) ?? Data()) ?? [:]
        var h = o["hooks"] as? [String: Any] ?? [:]
        h.removeValue(forKey: "Stop"); h.removeValue(forKey: "PermissionRequest")
        o["hooks"] = h
        try? JSONSerialization.data(withJSONObject: o).write(to: url)
        check("partialNotInstalled", !s.isInstalled())
        let r = s.install(now: now)
        let out = (try? Data(contentsOf: url)) ?? Data()
        check("partialResult", { if case .installed(let b) = r { return b != nil } else { return false } }())
        check("partialCompleted", s.isInstalled())
        check("partialNoDuplicates", groups(out, "SessionStart").filter(isNotchy).count == 1
              && groups(out, "Stop").filter(isNotchy).count == 1)
        check("partialOneBackup", backups(in: dir).count == 1)
    }
    do { // uninstallRemovesOnlyNotchy
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(fixture.utf8).write(to: url)
        let s = SettingsInstaller(settingsURL: url)
        _ = s.install(now: now)
        // add a mixed group: foreign + notchy hook in one group
        var o = obj((try? Data(contentsOf: url)) ?? Data()) ?? [:]
        var h = o["hooks"] as? [String: Any] ?? [:]
        var stop = h["Stop"] as? [[String: Any]] ?? []
        stop.append(["hooks": [["type": "command", "command": "keep-me"],
                               ["type": "http", "url": "http://127.0.0.1:7850/hooks/event"]]])
        h["Stop"] = stop; o["hooks"] = h
        try? JSONSerialization.data(withJSONObject: o).write(to: url)
        let beforeBackups = backups(in: dir).count
        let changed = s.uninstall(now: now.addingTimeInterval(120))
        let out = (try? Data(contentsOf: url)) ?? Data()
        check("uninstallChanged", changed)
        check("uninstallNotInstalled", !s.isInstalled())
        check("uninstallNoNotchyLeft", allEvents.allSatisfy { groups(out, $0).filter(isNotchy).isEmpty })
        check("uninstallKeepsModel", obj(out)?["model"] as? String == "x")
        let pre = groups(out, "PreToolUse")
        check("uninstallKeepsForeignGroup", pre.count == 1 && pre[0]["matcher"] as? String == "*")
        check("uninstallKeepsStart", groups(out, "SessionStart").count == 1)
        let stopG = groups(out, "Stop")
        check("uninstallMixedGroupKept", stopG.count == 1
              && (stopG[0]["hooks"] as? [[String: Any]])?.count == 1
              && ((stopG[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "keep-me")
        check("uninstallEmptiedEventsDropped", ((obj(out)?["hooks"] as? [String: Any])?["PermissionRequest"]) == nil)
        check("uninstallBackedUp", backups(in: dir).count == beforeBackups + 1)
        let again = s.uninstall(now: now.addingTimeInterval(240))
        check("uninstallIdempotent", again == false && backups(in: dir).count == beforeBackups + 1)
    }
    do { // freshCommandForm
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        _ = SettingsInstaller(settingsURL: url).install(now: now)
        let out = (try? Data(contentsOf: url)) ?? Data()
        check("freshStatusCommandForm", statusEvents.allSatisfy { isCommandForm(notchyHook(out, $0)) })
        let ph = notchyHook(out, "PermissionRequest")
        check("freshPermissionHttp", ph?["type"] as? String == "http" && ph?["command"] == nil
              && ph?["url"] as? String == "http://127.0.0.1:7850/hooks/permission")
        check("freshNoBundlePath", !(String(data: out, encoding: .utf8) ?? "").contains(".app"))
    }
    do { // migrateFromHttp
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(oldHttpFixture.utf8).write(to: url)
        let s = SettingsInstaller(settingsURL: url)
        check("migrateOldNotInstalled", !s.isInstalled())
        let r = s.install(now: now)
        let out = (try? Data(contentsOf: url)) ?? Data()
        check("migrateResult", { if case .installed(let b) = r { return b != nil } else { return false } }())
        check("migrateStatusCommandForm", statusEvents.allSatisfy { isCommandForm(notchyHook(out, $0)) })
        check("migrateNoDuplicates", allEvents.allSatisfy { notchyHook(out, $0) != nil })
        check("migrateNoHttpStatus", !(String(data: out, encoding: .utf8) ?? "").contains("7850/hooks/event\""))
        let pre = groups(out, "PreToolUse")
        check("migrateKeepsForeignPre", pre.count == 2
              && ((pre[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "orca-hook pre")
        let stopHooks = groups(out, "Stop").flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
        check("migrateKeepsMixedForeign", stopHooks.filter { $0["command"] as? String == "keep-me" }.count == 1)
        check("migrateKeepsOtherEvent", groups(out, "SubagentStop").count == 1)
        check("migrateKeepsModel", obj(out)?["model"] as? String == "x")
        check("migrateIsInstalled", s.isInstalled())
        let bytes = out
        check("migrateIdempotent", s.install(now: now.addingTimeInterval(60)) == .alreadyInstalled
              && (try? Data(contentsOf: url)) == bytes)
    }
    do { // removeBothKinds
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(oldHttpFixture.utf8).write(to: url)
        let s = SettingsInstaller(settingsURL: url)
        // Mix: migrate PreToolUse only, leave old http form elsewhere, then add a command entry.
        var o = obj(Data(oldHttpFixture.utf8)) ?? [:]
        var h = o["hooks"] as? [String: Any] ?? [:]
        var stop = h["Stop"] as? [[String: Any]] ?? []
        stop.append(["hooks": [["type": "command", "command": expectedCommand, "timeout": 5]]])
        h["Stop"] = stop; o["hooks"] = h
        try? JSONSerialization.data(withJSONObject: o).write(to: url)
        check("removeChanged", s.uninstall(now: now))
        let out = (try? Data(contentsOf: url)) ?? Data()
        check("removeNoNotchyLeft", allEvents.allSatisfy { groups(out, $0).filter(isNotchy).isEmpty })
        check("removeNoMarkerLeft", !(String(data: out, encoding: .utf8) ?? "").contains("127.0.0.1:7850"))
        check("removeKeepsForeign", groups(out, "PreToolUse").count == 1 && groups(out, "SubagentStop").count == 1
              && groups(out, "Stop").count == 1)
    }
    do { // sortedKeysOutput
        let dir = tempDir(); let url = dir.appendingPathComponent("settings.json")
        try? Data(#"{"zeta": 1, "alpha": {"y": 2, "b": 3}, "hooks": {}}"#.utf8).write(to: url)
        _ = SettingsInstaller(settingsURL: url).install(now: now)
        let text = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) ?? ""
        func pos(_ k: String) -> Int { text.range(of: "\"\(k)\"").map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? -1 }
        check("sortedTopLevel", pos("alpha") >= 0 && pos("alpha") < pos("hooks") && pos("hooks") < pos("zeta"))
        check("sortedNested", pos("b") >= 0 && pos("b") < pos("y"))
        check("sortedPretty", text.contains("\n"))
    }
}
