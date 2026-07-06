import XCTest
@testable import AgentPetCore

final class ClaudeHookPayloadTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)

    private func payload(_ json: String) -> ClaudeHookPayload? {
        ClaudeHookPayload.decode(from: Data(json.utf8))
    }

    func testDecodesSessionStart() {
        let event = payload(#"{"session_id":"abc","cwd":"/Users/x/proj","hook_event_name":"SessionStart"}"#)?
            .makeEvent(now: now)
        XCTAssertEqual(event?.sessionId, "abc")
        XCTAssertEqual(event?.project, "/Users/x/proj")
        XCTAssertEqual(event?.eventName, "SessionStart")
        XCTAssertEqual(event?.agentKind, .claude)
    }

    func testDecodesNotificationWithMessage() {
        let p = payload(#"{"session_id":"s","cwd":"/p","hook_event_name":"Notification","message":"needs permission"}"#)
        let event = p?.makeEvent(now: now)
        XCTAssertEqual(event?.message, "needs permission")
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: event!.eventName), .waiting)
    }

    func testIgnoresUnknownFields() {
        // Real Claude payloads carry extra keys (transcript_path, stop_hook_active, ...).
        let event = payload(#"{"session_id":"s","hook_event_name":"Stop","transcript_path":"/t","stop_hook_active":false}"#)?
            .makeEvent(now: now)
        XCTAssertEqual(event?.eventName, "Stop")
        XCTAssertNil(event?.project)
    }

    func testNilWhenMissingEssentialFields() {
        XCTAssertNil(payload(#"{"cwd":"/p"}"#)?.makeEvent(now: now))
        XCTAssertNil(payload("not json"))
    }

    // MARK: - model field

    func testDecodesModelDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"claude-sonnet-4-6-20250514","display_name":"Sonnet 4.6"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "Sonnet 4.6")
    }

    func testFallsBackToModelIdWhenNoDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"gpt-5.1"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "gpt-5.1")
    }

    func testDecodesBareStringModel() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":"some-model"}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "some-model")
    }

    func testNilModelWhenAbsent() {
        let json = #"{"session_id":"s","hook_event_name":"Stop"}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertNil(event?.model)
    }

    func testMalformedModelDoesNotBreakDecode() {
        // model is a number, not an object/string — must not fail the whole payload.
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":123}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.eventName, "Stop", "payload must still decode")
        XCTAssertNil(event?.model)
    }

    // MARK: - Other agents routed through ClaudeHookPayload (claudeNested style)

    func testCodexPreToolUseActivityMessage() {
        let json = #"{"session_id":"cx1","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now, kind: .codex)
        XCTAssertEqual(event?.agentKind, .codex)
        XCTAssertTrue(ActivityTheme.chef.running.contains(event?.message ?? ""), "got \(event?.message ?? "nil")")
    }

    func testGeminiBeforeToolActivityMessage() {
        let json = #"{"session_id":"gm1","cwd":"/proj","hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#
        let event = payload(json)?.makeEvent(now: now, kind: .gemini)
        XCTAssertEqual(event?.agentKind, .gemini)
        XCTAssertTrue(ActivityTheme.chef.running.contains(event?.message ?? ""), "got \(event?.message ?? "nil")")
    }

    // MARK: - approval gating (PreToolUse + Bash)

    func testPreToolUseBashPopulatesApprovalFields() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertNotNil(event?.approvalRequestId, "must generate a request id for a gated tool")
        XCTAssertEqual(event?.toolName, "Bash")
        XCTAssertEqual(event?.toolSummary, "npm test")
    }

    func testPreToolUseBashTruncatesSummaryTo80Characters() {
        let longCommand = String(repeating: "a", count: 200)
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(longCommand)"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.toolSummary?.count, 80, "summary must be truncated to 80 chars")
    }

    func testPreToolUseBashWithNoCommandFallsBackToToolName() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash"}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.toolSummary, "Bash", "no command in tool_input -> summary falls back to tool name")
    }

    func testPreToolUseNonGatedToolLeavesApprovalFieldsNil() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertNil(event?.approvalRequestId, "Read is not in the gated tool whitelist")
        XCTAssertNil(event?.toolName)
        XCTAssertNil(event?.toolSummary)
    }

    func testNonPreToolUseEventLeavesApprovalFieldsNilEvenForBash() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"Stop","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertNil(event?.approvalRequestId, "only PreToolUse should ever trigger gating")
        XCTAssertNil(event?.toolName)
        XCTAssertNil(event?.toolSummary)
    }

    func testPreToolUseBashForNonClaudeKindLeavesApprovalFieldsNil() {
        let json = #"{"session_id":"s","cwd":"/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#

        let codexEvent = payload(json)?.makeEvent(now: now, kind: .codex)
        XCTAssertNil(codexEvent?.approvalRequestId, "approval gating is a Claude-only contract")
        XCTAssertNil(codexEvent?.toolName)
        XCTAssertNil(codexEvent?.toolSummary)

        let droidEvent = payload(json)?.makeEvent(now: now, kind: .droid)
        XCTAssertNil(droidEvent?.approvalRequestId, "approval gating is a Claude-only contract")
        XCTAssertNil(droidEvent?.toolName)
        XCTAssertNil(droidEvent?.toolSummary)
    }
}
