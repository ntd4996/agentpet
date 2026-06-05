import XCTest
@testable import AgentPetCore

final class HookInstallerTests: XCTestCase {
    private let cmd = "\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook"

    private func groups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    func testInstallIntoEmptyAddsAllEvents() {
        let result = HookInstaller.install(into: [:], command: cmd)
        XCTAssertTrue(HookInstaller.isInstalled(in: result))
        for event in HookInstaller.events {
            XCTAssertEqual(groups(result, event).count, 1, "event \(event)")
        }
    }

    func testInstallIsIdempotent() {
        let once = HookInstaller.install(into: [:], command: cmd)
        let twice = HookInstaller.install(into: once, command: cmd)
        for event in HookInstaller.events {
            XCTAssertEqual(groups(twice, event).count, 1, "no duplicate on \(event)")
        }
    }

    func testInstallPreservesForeignHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let result = HookInstaller.install(into: existing, command: cmd)
        XCTAssertEqual(groups(result, "Stop").count, 2, "foreign + ours")
    }

    func testUninstallRemovesOursKeepsForeign() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let installed = HookInstaller.install(into: existing, command: cmd)
        let removed = HookInstaller.uninstall(from: installed)
        XCTAssertFalse(HookInstaller.isInstalled(in: removed))
        XCTAssertEqual(groups(removed, "Stop").count, 1, "foreign hook survives")
        // Events that were only ours are dropped entirely.
        XCTAssertTrue(groups(removed, "SessionStart").isEmpty)
    }

    func testUninstallFromCleanIsNoop() {
        let removed = HookInstaller.uninstall(from: [:])
        XCTAssertNil(removed["hooks"])
    }

    // MARK: - Ownership matching

    func testIsOursMatchesInstalledCommandShapes() {
        // Quoted bundle path, with and without the v1-era missing --agent flag.
        XCTAssertTrue(HookInstaller.isOurs("\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" hook"))
        XCTAssertTrue(HookInstaller.isOurs("\"/Applications/AgentPet.app/Contents/MacOS/AgentPet\" hook --agent codex"))
        // Unquoted binary on PATH.
        XCTAssertTrue(HookInstaller.isOurs("/usr/local/bin/agentpet hook --agent claude"))
        XCTAssertTrue(HookInstaller.isOurs("agentpet hook"))
    }

    func testIsOursRejectsForeignCommands() {
        // A user's own hook whose path merely mentions agentpet.
        XCTAssertFalse(HookInstaller.isOurs("/Users/me/agentpet-experiments/my-hook.sh"))
        XCTAssertFalse(HookInstaller.isOurs("\"/Users/me/agentpet-tools/run-hooks.sh\" hook"))
        // Right words, wrong binary.
        XCTAssertFalse(HookInstaller.isOurs("echo agentpet hook done"))
        // Our binary, different subcommand.
        XCTAssertFalse(HookInstaller.isOurs("\"/Applications/AgentPet.app/Contents/MacOS/agentpet\" run -- make"))
        XCTAssertFalse(HookInstaller.isOurs("agentpet"))
        XCTAssertFalse(HookInstaller.isOurs(""))
    }

    func testDiskRoundTrip() throws {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try HookInstaller.installToDisk(command: cmd, path: path)
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path))
        try HookInstaller.uninstallFromDisk(path: path)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path))
    }
}
