import XCTest
@testable import AgentPetCore

/// Native xAI Grok Build integration. Grok's hook payload uses camelCase keys
/// (`hookEventName`, `sessionId`, `toolName`) with snake_case event VALUES
/// (`pre_tool_use`, `stop`) , different from Claude's snake_case keys +
/// PascalCase values, which is why the Claude-compat path never worked (#51).
final class GrokHookTests: XCTestCase {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    // The bug from #51: Grok's payload can't decode as a Claude event, so the CLI
    // must fail OPEN (exit 0). Here we prove the decode returns nil for .claude.
    func testGrokPayloadIsNotAClaudeEvent() {
        let grok = #"{"hookEventName":"stop","sessionId":"abc","cwd":"/tmp"}"#.data(using: .utf8)!
        XCTAssertNil(HookPayload.event(forAgent: .claude, stdin: grok, now: Date()))
        XCTAssertNil(HookPayload.event(forAgent: .cursor, stdin: grok, now: Date()))
    }

    func testGrokPayloadDecodesAsGrok() {
        let grok = #"{"hookEventName":"pre_tool_use","sessionId":"abc-123","cwd":"/Users/me/proj","toolName":"run_terminal_command","toolInput":{"command":"npm test"}}"#.data(using: .utf8)!
        let e = HookPayload.event(forAgent: .grok, stdin: grok, now: Date())
        XCTAssertEqual(e?.agentKind, .grok)
        XCTAssertEqual(e?.eventName, "pre_tool_use")
        XCTAssertEqual(e?.sessionId, "abc-123")
        XCTAssertEqual(e?.project, "/Users/me/proj")
    }

    func testGrokFallsBackToWorkspaceRoot() {
        let grok = #"{"hookEventName":"stop","sessionId":"s1","workspaceRoot":"/ws"}"#.data(using: .utf8)!
        let e = HookPayload.event(forAgent: .grok, stdin: grok, now: Date())
        XCTAssertEqual(e?.project, "/ws")
    }

    func testGrokStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "session_start"), .registered)
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "user_prompt_submit"), .working)
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "pre_tool_use"), .working)
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "post_tool_use"), .working)
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "notification"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .grok, eventName: "stop"), .done)
        XCTAssertNil(StateMapper.state(for: .grok, eventName: "post_compact"))
    }

    func testGrokSessionEnd() {
        XCTAssertTrue(StateMapper.isSessionEnd(for: .grok, eventName: "session_end"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .grok, eventName: "stop"))
    }

    func testGrokSpec() {
        let spec = AgentHooks.spec(for: .grok)!
        XCTAssertEqual(spec.style, .claudeNested)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.grok/hooks/agentpet.json"))
        // PreToolUse is deliberately omitted (its deny gate is risky).
        XCTAssertFalse(spec.events.contains("PreToolUse"))
        XCTAssertTrue(spec.events.contains("Stop"))
        XCTAssertTrue(spec.events.contains("SessionEnd"))
    }

    func testGrokInstallRoundTrip() throws {
        let spec = AgentHooks.spec(for: .grok)!
        let path = tmp("agentpet.json")
        let cmd = "\"/x/agentpet\" hook --agent grok"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .claudeNested)
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        let json = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(json.contains("--agent grok"))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testGrokInCatalog() {
        let grok = AgentCatalog.all.first { $0.kind == .grok }
        XCTAssertNotNil(grok)
        XCTAssertTrue(grok?.isSupported ?? false)
        XCTAssertEqual(grok?.displayName, "Grok Build")
    }
}
