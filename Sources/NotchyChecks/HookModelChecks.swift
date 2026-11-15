import Foundation
import NotchyCore

private func jsonObject(_ data: Data) -> NSDictionary? {
    (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
}

private func parse(_ s: String) -> NSDictionary? { jsonObject(Data(s.utf8)) }

func runHookModelChecks() {
    let payload = """
    {"session_id":"s1","cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash",
     "tool_input":{"command":"ls"},"unknown_key":1,"effort":{"level":"high"}}
    """
    let ev = try? JSONDecoder().decode(HookEvent.self, from: Data(payload.utf8))
    check("decodesPreToolUse",
          ev?.sessionId == "s1" && ev?.cwd == "/tmp" && ev?.eventName == "PreToolUse"
          && ev?.toolName == "Bash" && ev?.toolInput == .object(["command": .string("ls")])
          && ev?.sessionTitle == nil)

    let minimal = try? JSONDecoder().decode(HookEvent.self,
        from: Data(#"{"session_id":"a","cwd":"/","hook_event_name":"Stop"}"#.utf8))
    check("decodesMinimal", minimal != nil && minimal?.toolName == nil)
    check("rejectsMissingSession",
          (try? JSONDecoder().decode(HookEvent.self, from: Data(#"{"cwd":"/","hook_event_name":"Stop"}"#.utf8))) == nil)

    let allow = parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    check("allowBody", allow != nil && jsonObject(PermissionDecision.allow.responseBody()) == allow)

    let deny = parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"no"}}}"#)
    check("denyBody", deny != nil && jsonObject(PermissionDecision.deny(message: "no").responseBody()) == deny)

    check("noneBody", jsonObject(PermissionDecision.none.responseBody()) == NSDictionary())

    check("summaryBash",
          toolSummary(toolName: "Bash", input: .object(["command": .string("ls")])) == "ls")
    let long = String(repeating: "a", count: 50_000)
    let s = toolSummary(toolName: "Bash", input: .object(["command": .string(long)]))
    check("summaryTruncates", s.count == 401 && s.hasSuffix("…"))

    // truncationNote: shown when toolSummary cut the text or it needs more than 12 lines.
    check("truncationNoteShort", !commandNeedsTruncationNote("ls -la"))
    check("truncationNoteEllipsis", commandNeedsTruncationNote(s))
    let twelve = (1...12).map { "line \($0)" }.joined(separator: "\n")
    check("truncationNoteTwelveLinesFits", !commandNeedsTruncationNote(twelve))
    check("truncationNoteThirteenLines", commandNeedsTruncationNote(twelve + "\nline 13"))
    check("truncationNoteWrapped",
          commandNeedsTruncationNote(String(repeating: "x", count: 46 * 12 + 1))
          && !commandNeedsTruncationNote(String(repeating: "x", count: 46 * 12)))
    // Show all (A2): collapsed box shows 5 lines, scrolls beyond that.
    let five = (1...5).map { "line \($0)" }.joined(separator: "\n")
    check("showAllFiveLinesFits", !commandNeedsShowAll(five) && commandLineEstimate(five) == 5)
    check("showAllSixLines", commandNeedsShowAll(five + "\nline 6"))
    check("showAllWrapped", commandNeedsShowAll(String(repeating: "x", count: 46 * 5 + 1))
          && !commandNeedsShowAll(String(repeating: "x", count: 46 * 5)))
    check("showAllEmptyLinesCount", commandLineEstimate("a\n\n\n\n\nb") == 6)
    check("showAllShort", !commandNeedsShowAll("ls -la"))
    check("collapsedHeight80", Double(cardCommandCollapsedLines) * cardCommandLineHeight == 80)
}
