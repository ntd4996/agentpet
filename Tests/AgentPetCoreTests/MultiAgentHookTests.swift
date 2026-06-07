import XCTest
@testable import AgentPetCore

final class MultiAgentHookTests: XCTestCase {
    private let cmd = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent cursor"

    // MARK: - Cursor flat shape

    func testCursorInstallShape() {
        let events = AgentHooks.spec(for: .cursor)!.events
        let result = HookInstaller.installFlat(into: [:], command: cmd, events: events, style: .cursorFlat)
        XCTAssertEqual(result["version"] as? Int, 1)
        XCTAssertTrue(HookInstaller.isInstalledFlat(in: result, events: events))
        let hooks = result["hooks"] as? [String: Any]
        let stop = hooks?["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        XCTAssertEqual(stop?.first?["type"] as? String, "command")
        XCTAssertTrue((stop?.first?["command"] as? String ?? "").contains("agentpet"))
    }

    func testCursorIdempotentAndForeignPreserved() {
        let events = AgentHooks.spec(for: .cursor)!.events
        let existing: [String: Any] = ["hooks": ["stop": [["command": "echo hi"]]]]
        let once = HookInstaller.installFlat(into: existing, command: cmd, events: events, style: .cursorFlat)
        let twice = HookInstaller.installFlat(into: once, command: cmd, events: events, style: .cursorFlat)
        let stop = (twice["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2, "foreign + ours, no duplicate")
        let removed = HookInstaller.uninstallFlat(from: twice, events: events)
        let stopAfter = (removed["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stopAfter?.count, 1, "foreign kept")
        XCTAssertFalse(HookInstaller.isInstalledFlat(in: removed, events: events))
    }

    // MARK: - Windsurf flat shape

    func testWindsurfInstallShape() {
        let events = AgentHooks.spec(for: .windsurf)!.events
        let cmd = "\"/x/agentpet\" hook --agent windsurf"
        let result = HookInstaller.installFlat(into: [:], command: cmd, events: events, style: .windsurfFlat)
        XCTAssertNil(result["version"], "Windsurf has no version field")
        let resp = (result["hooks"] as? [String: Any])?["post_cascade_response"] as? [[String: Any]]
        XCTAssertEqual(resp?.first?["command"] as? String, cmd)
        XCTAssertEqual(resp?.first?["show_output"] as? Bool, false)
        XCTAssertTrue(HookInstaller.isInstalledFlat(in: result, events: events))
    }

    // MARK: - Antigravity named-group shape

    func testAntigravityInstallShape() {
        let events = AgentHooks.spec(for: .antigravity)!.events
        let cmd = "\"/x/agentpet\" hook --agent antigravity"
        let result = HookInstaller.installAntigravity(into: [:], command: cmd, events: events)
        XCTAssertNil(result["hooks"], "Antigravity nests under a named group, not \"hooks\"")
        let group = result[HookInstaller.antigravityGroup] as? [String: Any]
        let stop = group?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        let inner = stop?.first?["hooks"] as? [[String: Any]]
        XCTAssertEqual(inner?.first?["type"] as? String, "command")
        XCTAssertEqual(inner?.first?["command"] as? String, cmd)
        XCTAssertTrue(HookInstaller.isInstalledAntigravity(in: result, events: events))
    }

    func testAntigravityIdempotentAndForeignPreserved() {
        let events = AgentHooks.spec(for: .antigravity)!.events
        let cmd = "\"/x/agentpet\" hook --agent antigravity"
        // A foreign hook group plus a foreign entry under one of our events.
        let existing: [String: Any] = [
            "my-linter": ["PostToolUse": [["hooks": [["type": "command", "command": "lint.sh"]]]]],
            HookInstaller.antigravityGroup: ["Stop": [["hooks": [["type": "command", "command": "echo hi"]]]]],
        ]
        let once = HookInstaller.installAntigravity(into: existing, command: cmd, events: events)
        let twice = HookInstaller.installAntigravity(into: once, command: cmd, events: events)
        let group = twice[HookInstaller.antigravityGroup] as? [String: Any]
        let stop = group?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2, "foreign Stop entry + ours, no duplicate")
        XCTAssertNotNil(twice["my-linter"], "foreign hook group untouched")
        let removed = HookInstaller.uninstallAntigravity(from: twice, events: events)
        let stopAfter = (removed[HookInstaller.antigravityGroup] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stopAfter?.count, 1, "foreign Stop entry kept")
        XCTAssertNotNil(removed["my-linter"], "foreign hook group still kept")
        XCTAssertFalse(HookInstaller.isInstalledAntigravity(in: removed, events: events))
    }

    func testAntigravityStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .antigravity, eventName: "PreInvocation"), .working)
        XCTAssertEqual(StateMapper.state(for: .antigravity, eventName: "PreToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .antigravity, eventName: "Stop"), .done)
        XCTAssertNil(StateMapper.state(for: .antigravity, eventName: "Unknown"))
    }

    func testAntigravityPayloadDecode() {
        // Antigravity's hooks.json mirrors Claude Code's, so its stdin payload is
        // decoded with the Claude field convention (snake_case).
        let json = #"{"session_id":"ag1","hook_event_name":"PreToolUse","cwd":"/proj","tool_name":"Bash"}"#
        let ev = HookPayload.event(forAgent: .antigravity, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(ev?.sessionId, "ag1")
        XCTAssertEqual(ev?.eventName, "PreToolUse")
        XCTAssertEqual(ev?.project, "/proj")
        XCTAssertEqual(ev?.agentKind, .antigravity)
    }

    // MARK: - opencode plugin

    func testOpencodeBinaryPathExtraction() {
        XCTAssertEqual(
            HookInstaller.binaryPath(fromCommand: "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent opencode"),
            "/Applications/AgentPet.app/Contents/MacOS/agentpet")
    }

    func testOpencodePluginContent() {
        let js = HookInstaller.opencodePlugin(binary: "/x/agentpet")
        XCTAssertTrue(js.contains("session.idle"))
        XCTAssertTrue(js.contains("session.created"))
        XCTAssertTrue(js.contains("--agent"))
        XCTAssertTrue(js.contains("opencode"))
        XCTAssertTrue(HookInstaller.isOurs(js.replacingOccurrences(of: "\n", with: " ")))
    }

    // MARK: - Payload parsing

    func testCursorPayloadDecode() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop","workspace_roots":["/proj"],"model":"x"}"#
        let ev = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(ev?.sessionId, "c1")
        XCTAssertEqual(ev?.eventName, "stop")
        XCTAssertEqual(ev?.project, "/proj")
        XCTAssertEqual(ev?.agentKind, .cursor)
    }

    func testWindsurfPayloadDecode() {
        let json = #"{"trajectory_id":"t1","agent_action_name":"post_cascade_response","model_name":"x"}"#
        let ev = HookPayload.event(forAgent: .windsurf, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(ev?.sessionId, "t1")
        XCTAssertEqual(ev?.eventName, "post_cascade_response")
        XCTAssertEqual(ev?.agentKind, .windsurf)
    }

    // MARK: - State mapping

    func testCursorStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .cursor, eventName: "sessionStart"), .registered)
        XCTAssertEqual(StateMapper.state(for: .cursor, eventName: "beforeSubmitPrompt"), .working)
        XCTAssertEqual(StateMapper.state(for: .cursor, eventName: "stop"), .done)
    }

    func testWindsurfStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .windsurf, eventName: "pre_user_prompt"), .working)
        XCTAssertEqual(StateMapper.state(for: .windsurf, eventName: "post_cascade_response"), .done)
    }

    func testOpencodeNormalisedStatePassThrough() {
        // The plugin sends normalised state names directly.
        XCTAssertEqual(StateMapper.state(for: .opencode, eventName: "done"), .done)
        XCTAssertEqual(StateMapper.state(for: .opencode, eventName: "working"), .working)
        XCTAssertEqual(StateMapper.state(for: .opencode, eventName: "session.idle"), .done)
    }

    // MARK: - Session end clears the session

    func testSessionEndRemovesSession() {
        let store = SessionStore()
        let now = Date()
        let start = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
                               project: "/p", message: nil, timestamp: now)
        XCTAssertNotNil(store.apply(start, now: now))
        XCTAssertEqual(store.sessions.count, 1)
        let end = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "SessionEnd",
                             project: "/p", message: nil, timestamp: now)
        XCTAssertNil(store.apply(end, now: now), "SessionEnd maps to no state")
        XCTAssertEqual(store.sessions.count, 0, "session cleared on quit")
    }

    func testIsSessionEnd() {
        XCTAssertTrue(StateMapper.isSessionEnd(for: .claude, eventName: "SessionEnd"))
        XCTAssertTrue(StateMapper.isSessionEnd(for: .gemini, eventName: "SessionEnd"))
        XCTAssertTrue(StateMapper.isSessionEnd(for: .cursor, eventName: "sessionEnd"))
        XCTAssertTrue(StateMapper.isSessionEnd(for: .hermes, eventName: "on_session_end"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .claude, eventName: "Stop"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .codex, eventName: "Stop"))
    }

    // MARK: - Disk round-trip for each new style

    func testDiskRoundTripAllStyles() throws {
        let tmp = NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let cases: [(AgentKind, String)] = [(.cursor, "cursor.json"), (.windsurf, "windsurf.json"), (.opencode, "plugin/agentpet.js"), (.antigravity, "config/hooks.json"), (.hermes, "config.yaml")]
        for (kind, file) in cases {
            let spec = AgentHooks.spec(for: kind)!
            let path = tmp + file
            let command = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent \(kind.rawValue)"
            XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style), "\(kind) clean")
            try HookInstaller.installToDisk(command: command, path: path, events: spec.events, style: spec.style)
            XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style), "\(kind) installed")
            try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: spec.style)
            XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: spec.style), "\(kind) removed")
        }
    }

    // MARK: - Hermes

    func testHermesStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "on_session_start"), .registered)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "pre_llm_call"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "post_llm_call"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "pre_tool_call"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "post_tool_call"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "pre_api_request"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "post_api_request"), .working)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "on_session_end"), .done)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "on_session_finalize"), .done)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "on_session_reset"), .done)
        XCTAssertEqual(StateMapper.state(for: .hermes, eventName: "subagent_stop"), .done)
        XCTAssertNil(StateMapper.state(for: .hermes, eventName: "unknown_event"))
    }

    func testHermesPayloadDecode() {
        // Hermes uses the same snake_case JSON fields as Claude Code.
        let json = #"{"session_id":"h1","hook_event_name":"pre_llm_call","cwd":"/proj","message":"processing"}"#
        let ev = HookPayload.event(forAgent: .hermes, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(ev?.sessionId, "h1")
        XCTAssertEqual(ev?.eventName, "pre_llm_call")
        XCTAssertEqual(ev?.project, "/proj")
        XCTAssertEqual(ev?.agentKind, .hermes)
        XCTAssertEqual(ev?.message, "processing")
    }

    func testHermesYamlInstall() {
        let cmd = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook --agent hermes"
        let events = AgentHooks.spec(for: .hermes)!.events

        // Install into empty content.
        let installed = HookInstaller.installHermesYaml(into: "", command: cmd, events: events)
        XCTAssertTrue(installed.contains(cmd))
        XCTAssertTrue(HookInstaller.isInstalledHermesYaml(in: installed))

        // Install again is idempotent.
        let reinstall = HookInstaller.installHermesYaml(into: installed, command: cmd, events: events)
        XCTAssertEqual(reinstall, installed)

        // Preserve existing top-level YAML keys before hooks:.
        let withPrefix = "model:\n  default: hermes-agent\n"
        let withHooks = HookInstaller.installHermesYaml(into: withPrefix, command: cmd, events: events)
        XCTAssertTrue(withHooks.hasPrefix(withPrefix))
        XCTAssertTrue(withHooks.contains(cmd))
        XCTAssertTrue(HookInstaller.isInstalledHermesYaml(in: withHooks))

        // Uninstall.
        let removed = HookInstaller.uninstallHermesYaml(from: withHooks)
        XCTAssertFalse(HookInstaller.isInstalledHermesYaml(in: removed))
        XCTAssertTrue(removed.contains("hooks: {}"))
        XCTAssertTrue(removed.hasPrefix(withPrefix), "prefix preserved after uninstall")
    }
}
