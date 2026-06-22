import XCTest
@testable import AgentPetCore

/// Integration tests for Pi (pi.dev). Pi has no Claude-style command hooks; it
/// loads a TypeScript extension from ~/.pi/agent/extensions/ that reports state
/// through the `agentpet hook` CLI with explicit flags (like the opencode plugin).
final class PiHookTests: XCTestCase {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "agentpet-test-\(UUID().uuidString)/\(name)"
    }

    func testPiSpec() {
        let spec = AgentHooks.spec(for: .pi)!
        XCTAssertEqual(spec.style, .piExtension)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.pi/agent/extensions/agentpet.ts"))
        // The extension hardcodes its own pi.on() handlers, so no events are
        // registered through the generic installer.
        XCTAssertTrue(spec.events.isEmpty)
    }

    func testPiExtensionContent() {
        let ts = HookInstaller.piExtension(binary: "/x/agentpet")
        XCTAssertTrue(ts.contains("pi.on(\"session_start\""))
        XCTAssertTrue(ts.contains("pi.on(\"agent_start\""))
        XCTAssertTrue(ts.contains("pi.on(\"agent_end\""))
        XCTAssertTrue(ts.contains("--agent"))
        XCTAssertTrue(ts.contains("pi"))
        // Must look "ours" so isInstalled detection works.
        XCTAssertTrue(HookInstaller.isOurs(ts.replacingOccurrences(of: "\n", with: " ")))
    }

    func testPiExtensionInstallRoundTrip() throws {
        let spec = AgentHooks.spec(for: .pi)!
        let path = tmp("agentpet.ts")
        let cmd = "\"/x/agentpet\" hook --agent pi"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .piExtension)
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(source.contains("AGENTPET_BIN"))
        XCTAssertTrue(source.contains("/x/agentpet"))
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .piExtension))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .piExtension)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .piExtension))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "extension file removed on uninstall")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testPiNormalisedStatesSentByExtension() {
        // The extension sends normalised AgentState raw values directly.
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "registered"), .registered)
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "working"), .working)
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "done"), .done)
    }

    func testPiNativeEventNamesFallback() {
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "session_start"), .registered)
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "agent_start"), .working)
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "agent_end"), .done)
        XCTAssertEqual(StateMapper.state(for: .pi, eventName: "session_shutdown"), .done)
        // Pi has no approval gate, so there is no "waiting" event.
        XCTAssertNil(StateMapper.state(for: .pi, eventName: "extension_ui_request"))
    }

    func testPiEventViaExplicitFlags() {
        // The extension uses explicit flags, not stdin, like opencode + the run wrapper.
        let args = HookArguments.parse(["--agent", "pi", "--event", "working", "--session", "pi:/proj", "--project", "/proj"])
        let event = args.makeEvent(now: Date())
        XCTAssertEqual(event?.agentKind, .pi)
        XCTAssertEqual(event?.eventName, "working")
        XCTAssertEqual(event?.project, "/proj")
    }

    func testPiInCatalog() {
        let pi = AgentCatalog.all.first { $0.kind == .pi }
        XCTAssertNotNil(pi)
        XCTAssertTrue(pi?.isSupported ?? false)
        XCTAssertEqual(pi?.displayName, "Pi")
    }
}
