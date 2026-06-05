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
        // On-disk detection keys off the generated AGENTPET_BIN marker (a JS
        // file is not a hook command, so isOurs does not apply to it).
        XCTAssertTrue(js.contains("AGENTPET_BIN"))
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
        XCTAssertFalse(StateMapper.isSessionEnd(for: .claude, eventName: "Stop"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .codex, eventName: "Stop"))
    }

    // MARK: - Disk round-trip for each new style

    func testDiskRoundTripAllStyles() throws {
        let tmp = NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let cases: [(AgentKind, String)] = [(.cursor, "cursor.json"), (.windsurf, "windsurf.json"), (.opencode, "plugin/agentpet.js")]
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
}
