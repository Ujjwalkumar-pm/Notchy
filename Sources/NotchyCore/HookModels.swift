import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public struct HookEvent: Decodable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let eventName: String
    public let toolName: String?
    public let toolInput: JSONValue?
    public let sessionTitle: String?
    public let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case eventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case sessionTitle = "session_title"
        case notificationType = "notification_type"
    }
}

public enum PermissionDecision: Sendable, Equatable {
    case allow
    case deny(message: String)
    case none

    public func responseBody() -> Data {
        let obj: [String: Any]
        switch self {
        case .allow:
            obj = Self.wrap(["behavior": "allow"])
        case .deny(let message):
            obj = Self.wrap(["behavior": "deny", "message": message])
        case .none:
            obj = [:]
        }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func wrap(_ decision: [String: Any]) -> [String: Any] {
        ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }
}

public func toolSummary(toolName: String, input: JSONValue?) -> String {
    func field(_ key: String) -> String? {
        if case .object(let o)? = input, case .string(let s)? = o[key] { return s }
        return nil
    }
    let raw: String
    switch toolName {
    case "Bash": raw = field("command") ?? compact(input)
    case "Edit", "Write", "Read": raw = field("file_path") ?? compact(input)
    case "WebFetch": raw = field("url") ?? compact(input)
    default: raw = compact(input)
    }
    return raw.count > 400 ? String(raw.prefix(400)) + "…" : raw
}

/// Card command text shows at most this many lines.
public let cardCommandMaxLines = 12

/// True when the card can't show the whole command: `toolSummary` cut it (ends with "…") or it
/// needs more than `maxLines` lines. Wrapped lines are estimated at `charsPerLine` monospaced
/// characters (the default card fits ~47 at 12 pt); a wider panel only makes this cautious.
public func commandNeedsTruncationNote(_ summary: String, maxLines: Int = cardCommandMaxLines,
                                       charsPerLine: Int = 46) -> Bool {
    if summary.hasSuffix("…") { return true }
    return commandLineEstimate(summary, charsPerLine: charsPerLine) > maxLines
}

/// Collapsed command box shows this many lines (12 pt mono, 16 pt line height = 80 pt), the
/// rest scrolls; "Show all" expands it to `cardCommandMaxLines` (AUDIT A2).
public let cardCommandCollapsedLines = 5
/// Line height of the card's command text.
public let cardCommandLineHeight: Double = 16

/// Estimated display lines of `summary`: each `\n` line wraps at `charsPerLine` monospaced
/// characters (an empty line still takes one).
public func commandLineEstimate(_ summary: String, charsPerLine: Int = 46) -> Int {
    let perLine = max(1, charsPerLine)
    var lines = 0
    for line in summary.split(separator: "\n", omittingEmptySubsequences: false) {
        lines += max(1, (line.count + perLine - 1) / perLine)
    }
    return lines
}

/// True when the command doesn't fit the collapsed box: it scrolls, fades at the bottom and
/// offers "Show all".
public func commandNeedsShowAll(_ summary: String, collapsedLines: Int = cardCommandCollapsedLines,
                                charsPerLine: Int = 46) -> Bool {
    commandLineEstimate(summary, charsPerLine: charsPerLine) > collapsedLines
}

private func compact(_ input: JSONValue?) -> String {
    guard let input else { return "" }
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    guard let d = try? enc.encode(input), let s = String(data: d, encoding: .utf8) else { return "" }
    return s
}
