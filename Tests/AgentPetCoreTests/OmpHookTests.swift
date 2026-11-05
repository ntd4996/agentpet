import XCTest
@testable import AgentPetCore

/// Integration tests for Oh My Pi (omp.sh). Oh My Pi uses a TypeScript extension
/// in ~/.omp/agent/extensions/agentpet.ts that reports lifecycle and tool approval
/// events via `agentpet hook`.
final class OmpHookTests: XCTestCase {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    func testOmpSpec() {
        let spec = AgentHooks.spec(for: .omp)!
        XCTAssertEqual(spec.style, .ompExtension)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.omp/agent/extensions/agentpet.ts"))
        XCTAssertTrue(spec.events.isEmpty)
    }

    func testOmpExtensionContent() {
        let ts = HookInstaller.ompExtension(binary: "/x/agentpet")
        XCTAssertTrue(ts.contains("pi.on(\"session_start\""))
        XCTAssertTrue(ts.contains("pi.on(\"agent_start\""))
        XCTAssertTrue(ts.contains("pi.on(\"turn_start\""))
        XCTAssertTrue(ts.contains("pi.on(\"tool_approval_requested\""))
        XCTAssertTrue(ts.contains("pi.on(\"tool_approval_resolved\""))
        XCTAssertTrue(ts.contains("pi.on(\"agent_end\""))
        XCTAssertTrue(ts.contains("--agent"))
        XCTAssertTrue(ts.contains("omp"))
        XCTAssertTrue(ts.contains("--transcript"))
        XCTAssertTrue(ts.contains("--model"))
        XCTAssertTrue(HookInstaller.isOurs(ts.replacingOccurrences(of: "\n", with: " ")))
    }

    func testOmpExtensionInstallRoundTrip() throws {
        let spec = AgentHooks.spec(for: .omp)!
        let path = tmp("agentpet.ts")
        let cmd = "\"/x/agentpet\" hook --agent omp"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .ompExtension)
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(source.contains("AGENTPET_BIN"))
        XCTAssertTrue(source.contains("/x/agentpet"))
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .ompExtension))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .ompExtension)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .ompExtension))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "omp extension file removed on uninstall")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testOmpStateMapping() {
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "session_start"), .registered)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "agent_start"), .working)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "turn_start"), .working)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "tool_call"), .working)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "tool_approval_resolved"), .working)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "tool_approval_requested"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "waiting"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "turn_end"), .done)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "agent_end"), .done)
        XCTAssertEqual(StateMapper.state(for: .omp, eventName: "session_shutdown"), .done)
    }

    func testOmpEventViaExplicitFlags() {
        let args = HookArguments.parse([
            "--agent", "omp",
            "--event", "waiting",
            "--session", "omp:/Users/test/session.jsonl",
            "--project", "/Users/test/myproject",
            "--transcript", "/Users/test/session.jsonl",
            "--model", "claude-3-7-sonnet",
            "--message", "Needs approval for bash"
        ])
        let event = args.makeEvent(now: Date())
        XCTAssertEqual(event?.agentKind, .omp)
        XCTAssertEqual(event?.eventName, "waiting")
        XCTAssertEqual(event?.project, "/Users/test/myproject")
        XCTAssertEqual(event?.transcriptPath, "/Users/test/session.jsonl")
        XCTAssertEqual(event?.model, "claude-3-7-sonnet")
        XCTAssertEqual(event?.message, "Needs approval for bash")
    }

    func testOmpInCatalog() {
        let omp = AgentCatalog.all.first { $0.kind == .omp }
        XCTAssertNotNil(omp)
        XCTAssertTrue(omp?.isSupported ?? false)
        XCTAssertEqual(omp?.displayName, "Oh My Pi")
    }

    func testOmpTranscriptUsageParsing() throws {
        let path = tmp("omp_session.jsonl")
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: dir)
            TranscriptReader.clearCache()
        }

        // Test camelCase tokens format used in Pi / Oh My Pi session files
        let line1 = """
        {"type":"message","id":"msg-1","message":{"id":"msg-1","model":"claude-3-7-sonnet","usage":{"inputTokens":100,"outputTokens":50,"cacheReadInputTokens":10}}}
        \n
        """
        try line1.write(toFile: path, atomically: true, encoding: .utf8)

        let delta1 = TranscriptReader.newUsageDelta(at: path)
        XCTAssertNotNil(delta1)
        XCTAssertEqual(delta1?.tokens, 150)
        XCTAssertGreaterThan(delta1?.costUSD ?? 0, 0)

        // Append line2
        let line2 = """
        {"type":"message","id":"msg-2","message":{"id":"msg-2","model":"claude-3-7-sonnet","usage":{"inputTokens":200,"outputTokens":100}}}
        \n
        """
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        handle.seekToEndOfFile()
        handle.write(Data(line2.utf8))
        handle.closeFile()

        let delta2 = TranscriptReader.newUsageDelta(at: path)
        XCTAssertNotNil(delta2)
        XCTAssertEqual(delta2?.tokens, 300)
    }
}
