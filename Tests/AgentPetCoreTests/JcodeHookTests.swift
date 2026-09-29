import XCTest
@testable import AgentPetCore

/// jcode integration: observer hooks in ~/.jcode/config.toml `[hooks]`, event
/// delivered through JCODE_HOOK_* env vars (docs/HOOKS.md upstream).
final class JcodeHookTests: XCTestCase {
    private let cmd = "\"/x/agentpet\" hook --agent jcode"
    private var events: [String] { AgentHooks.spec(for: .jcode)!.events }

    // MARK: payload

    func testEnvPayloadBuildsEvent() {
        let e = JcodeHookPayload.event(env: [
            "JCODE_HOOK_EVENT": "post_tool", "JCODE_HOOK_SESSION_ID": "session_x_1",
            "JCODE_HOOK_CWD": "/proj", "JCODE_HOOK_TOOL_NAME": "bash",
        ], now: Date())
        XCTAssertEqual(e?.agentKind, .jcode)
        XCTAssertEqual(e?.eventName, "post_tool")
        XCTAssertEqual(e?.sessionId, "session_x_1")
        XCTAssertEqual(e?.project, "/proj")
        XCTAssertNotNil(e?.message, "tool activity feeds the bubble")
    }

    func testMissingSessionOrEventIsIgnored() {
        XCTAssertNil(JcodeHookPayload.event(env: ["JCODE_HOOK_EVENT": "turn_end"], now: Date()))
        XCTAssertNil(JcodeHookPayload.event(env: ["JCODE_HOOK_SESSION_ID": "s"], now: Date()))
        XCTAssertNil(JcodeHookPayload.event(env: [:], now: Date()))
    }

    func testTurnEndingOnQuestionIsWaiting() {
        let env = ["JCODE_HOOK_EVENT": "turn_end", "JCODE_HOOK_SESSION_ID": "s",
                   "JCODE_HOOK_STATUS": "ok",
                   "JCODE_HOOK_LAST_ASSISTANT_TEXT": "I found two options. Which one should I use?"]
        XCTAssertEqual(JcodeHookPayload.event(env: env, now: Date())?.eventName, "waiting")
    }

    func testTurnEndingWithSummaryIsDone() {
        let env = ["JCODE_HOOK_EVENT": "turn_end", "JCODE_HOOK_SESSION_ID": "s",
                   "JCODE_HOOK_STATUS": "ok", "JCODE_HOOK_LAST_ASSISTANT_TEXT": "Fixed the bug and tests pass."]
        let e = JcodeHookPayload.event(env: env, now: Date())
        XCTAssertEqual(e?.eventName, "turn_end")
        XCTAssertEqual(StateMapper.state(for: .jcode, eventName: e!.eventName), .done)
    }

    // MARK: state mapping

    func testStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .jcode, eventName: "session_start"), .registered)
        XCTAssertEqual(StateMapper.state(for: .jcode, eventName: "turn_start"), .working)
        XCTAssertEqual(StateMapper.state(for: .jcode, eventName: "post_tool"), .working)
        XCTAssertEqual(StateMapper.state(for: .jcode, eventName: "turn_end"), .done)
        XCTAssertNil(StateMapper.state(for: .jcode, eventName: "pre_tool"))
        XCTAssertTrue(StateMapper.isSessionEnd(for: .jcode, eventName: "session_end"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .jcode, eventName: "turn_end"))
    }

    func testSpecUsesObserversOnly() {
        let spec = AgentHooks.spec(for: .jcode)!
        XCTAssertEqual(spec.style, .jcodeToml)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.jcode/config.toml"))
        XCTAssertFalse(spec.events.contains("pre_tool"), "pre_tool is a blocking gate")
    }

    func testInCatalog() {
        XCTAssertEqual(AgentCatalog.all.first { $0.kind == .jcode }?.isSupported, true)
    }

    // MARK: TOML config

    private let sample = """
    # user comment
    [display]
    debug_socket = false

    [hooks]
    pre_tool_timeout_ms = 5000

    [ambient]
    enabled = false
    """

    func testInstallAddsKeysInsideHooksTableOnly() throws {
        let out = try JcodeHookConfig.install(in: sample, command: cmd, events: events)
        let lines = out.components(separatedBy: "\n")
        let hooks = lines.firstIndex(of: "[hooks]")!, ambient = lines.firstIndex(of: "[ambient]")!
        for event in events {
            let i = try XCTUnwrap(lines.firstIndex(of: "\(event) = '\(cmd)'"))
            XCTAssertTrue(i > hooks && i < ambient, "\(event) must sit in [hooks]")
        }
        // Everything else is untouched.
        XCTAssertEqual(JcodeHookConfig.uninstall(in: out, events: events), sample)
        XCTAssertTrue(JcodeHookConfig.isInstalled(in: out, events: events))
        XCTAssertFalse(JcodeHookConfig.isInstalled(in: sample, events: events))
    }

    func testInstallIsIdempotent() throws {
        let once = try JcodeHookConfig.install(in: sample, command: cmd, events: events)
        XCTAssertEqual(try JcodeHookConfig.install(in: once, command: cmd, events: events), once)
        // A moved binary rewrites our lines in place instead of duplicating them.
        let moved = try JcodeHookConfig.install(in: once, command: "\"/y/agentpet\" hook --agent jcode", events: events)
        XCTAssertEqual(moved.components(separatedBy: "\n").count, once.components(separatedBy: "\n").count)
        XCTAssertTrue(moved.contains("/y/agentpet") && !moved.contains("/x/agentpet"))
    }

    func testInstallCreatesHooksTableWhenMissing() throws {
        let out = try JcodeHookConfig.install(in: "[display]\nx = 1\n", command: cmd, events: ["turn_end"])
        XCTAssertTrue(out.hasPrefix("[display]\nx = 1\n\n[hooks]\nturn_end = '"))
        XCTAssertTrue(try JcodeHookConfig.install(in: "", command: cmd, events: ["turn_end"]).hasPrefix("[hooks]\n"))
    }

    func testForeignHookIsNeverOverwritten() {
        let foreign = sample.replacingOccurrences(of: "pre_tool_timeout_ms = 5000",
                                                  with: "pre_tool_timeout_ms = 5000\nturn_end = \"~/bin/notify\"")
        XCTAssertThrowsError(try JcodeHookConfig.install(in: foreign, command: cmd, events: events)) {
            XCTAssertEqual($0 as? JcodeHookConfigError, .conflictingHook(event: "turn_end", path: "config.toml"))
        }
        XCTAssertEqual(JcodeHookConfig.uninstall(in: foreign, events: events), foreign)
    }

    func testCommentedKeysAndSimilarNamesAreIgnored() throws {
        let toml = "[hooks]\n# turn_end = \"old\"\nturn_end_extra = 1\n"
        let out = try JcodeHookConfig.install(in: toml, command: cmd, events: ["turn_end"])
        XCTAssertTrue(out.contains("# turn_end = \"old\"\nturn_end_extra = 1"))
        XCTAssertTrue(out.contains("turn_end = '\(cmd)'"))
    }

    func testCommandWithApostropheUsesBasicString() {
        XCTAssertEqual(JcodeHookConfig.tomlString("\"/a b's/agentpet\" hook"), "\"\\\"/a b's/agentpet\\\" hook\"")
    }

    func testDiskRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)"
        let path = dir + "/config.toml"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data(sample.utf8).write(to: URL(fileURLWithPath: path))
        try HookInstaller.installToDisk(command: cmd, path: path, events: events, style: .jcodeToml)
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: events, style: .jcodeToml))
        try HookInstaller.uninstallFromDisk(path: path, events: events, style: .jcodeToml)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: events, style: .jcodeToml))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), sample)
    }
}
