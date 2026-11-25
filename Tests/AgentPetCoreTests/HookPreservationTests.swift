import XCTest
@testable import AgentPetCore

final class HookPreservationTests: XCTestCase {
    private let ours = "\"/x/agentpet\" hook"
    private let foreign = "echo agentpet hook"

    func testNestedMixedGroupKeepsForeignAndMetadata() throws {
        let group: [String: Any] = ["matcher": "Bash", "timeout": 12,
            "hooks": [["command": ours], ["command": foreign, "timeout": 42]]]
        let input: [String: Any] = ["hooks": ["Stop": [group]]]
        let installed = HookInstaller.install(into: input, command: ours, events: ["Stop"])
        let groups = try XCTUnwrap((installed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertEqual(commands.filter { $0 == ours }.count, 1)
        XCTAssertEqual(commands.filter { $0 == foreign }.count, 1)
        let removed = HookInstaller.uninstall(from: input, events: ["Stop"])
        let kept = try XCTUnwrap(((removed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first)
        XCTAssertEqual(kept["matcher"] as? String, "Bash")
        XCTAssertEqual(kept["timeout"] as? Int, 12)
        XCTAssertEqual((kept["hooks"] as? [[String: Any]])?.first?["command"] as? String, foreign)
    }

    func testAntigravityMixedGroupAndPlainHandlersKeepForeign() throws {
        let input: [String: Any] = ["agentpet": [
            "PreToolUse": [["matcher": "Bash", "hooks": [["command": ours], ["command": foreign]]]],
            "Stop": [["command": ours], ["command": foreign]]]]
        let events = ["PreToolUse", "Stop"]
        let installed = HookInstaller.installAntigravity(into: input, command: ours, events: events)
        let removed = HookInstaller.uninstallAntigravity(from: installed, events: events)
        let group = try XCTUnwrap(removed["agentpet"] as? [String: Any])
        let nested = try XCTUnwrap((group["PreToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(nested["matcher"] as? String, "Bash")
        XCTAssertEqual((nested["hooks"] as? [[String: Any]])?.first?["command"] as? String, foreign)
        XCTAssertEqual((group["Stop"] as? [[String: Any]])?.first?["command"] as? String, foreign)
        let entries = try XCTUnwrap((installed["agentpet"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }.filter { $0 == ours }.count, 1)
    }

    func testFlatShapesKeepMisleadingForeignCommands() {
        for style: HookStyle in [.cursorFlat, .windsurfFlat, .kiroFlat] {
            let input: [String: Any] = ["hooks": ["stop": [["command": ours], ["command": foreign]]]]
            let installed = HookInstaller.installFlat(into: input, command: ours, events: ["stop"], style: style)
            let removed = HookInstaller.uninstallFlat(from: installed, events: ["stop"])
            let items = (removed["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
            XCTAssertEqual(items?.count, 1)
            XCTAssertEqual(items?.first?["command"] as? String, foreign)
        }
    }

    func testJcodeMixedInlineArrayKeepsForeign() throws {
        let input = "[hooks]\nturn_end = ['\(ours)', 'echo foreign'] # observers\n"
        let installed = try JcodeHookConfig.install(in: input, command: ours, events: ["turn_end"])
        XCTAssertTrue(installed.contains("echo foreign"))
        XCTAssertEqual(installed.components(separatedBy: ours).count - 1, 1)
        let removed = JcodeHookConfig.uninstall(in: input, events: ["turn_end"])
        XCTAssertTrue(removed.contains("echo foreign"))
        XCTAssertFalse(removed.contains(ours))
        XCTAssertTrue(removed.contains("# observers"))
    }

    func testJcodeMisleadingForeignStringIsRefused() {
        let input = "[hooks]\nturn_end = 'echo agentpet hook'\n"
        XCTAssertThrowsError(try JcodeHookConfig.install(in: input, command: ours, events: ["turn_end"]))
        XCTAssertEqual(JcodeHookConfig.uninstall(in: input, events: ["turn_end"]), input)
    }

    func testPluginShapesNeverOverwriteOrRemoveForeignSource() throws {
        for style: HookStyle in [.opencodePlugin, .piExtension] {
            let path = NSTemporaryDirectory() + "agentpet-plugin-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: path) }
            let source = "// agentpet hook is mentioned, but this is a foreign plugin\nexport const foreign = true\n"
            try Data(source.utf8).write(to: URL(fileURLWithPath: path))
            XCTAssertThrowsError(try HookInstaller.installToDisk(command: ours, path: path, events: [], style: style))
            XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), source)
            try HookInstaller.uninstallFromDisk(path: path, events: [], style: style)
            XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), source)
        }
    }
}
