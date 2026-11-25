import XCTest
@testable import AgentPetCore

final class CodexHookConfigTests: XCTestCase {
    func testEmptyConfigAddsFeaturesTable() {
        let out = CodexHookConfig.enableHooks(in: "")
        XCTAssertEqual(out, "\n[features]\nhooks = true\n")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out!))
    }

    func testAlreadyEnabledHooksIsNoOp() {
        XCTAssertNil(CodexHookConfig.enableHooks(in: "[features]\nhooks = true\n"))
    }

    func testCodexHooksAliasAloneStillAddsModernKey() {
        // `codex_hooks` is a deprecated alias recent Codex (Desktop 5.x) ignores,
        // so a config with only that must still get a real `hooks = true`.
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = true\n")
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("hooks = true"))
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out!))
    }

    func testFlipsHooksFalseToTrue() {
        let out = CodexHookConfig.enableHooks(in: "[features]\nhooks = false\n")
        XCTAssertEqual(out, "[features]\nhooks = true\n")
    }

    func testFlipsCodexHooksFalseToTrueWithoutDuplicate() {
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = false\n")!
        XCTAssertEqual(out.components(separatedBy: "true").count - 1, 1, "exactly one truthy flag, no duplicate")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out))
    }

    func testInsertsUnderExistingFeaturesPreservingOtherKeys() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"\n\n[features]\nweb_search = true\n")!
        XCTAssertTrue(out.contains("hooks = true"))
        XCTAssertTrue(out.contains("web_search = true"), "existing key kept")
        XCTAssertTrue(out.contains("model = \"o3\""), "unrelated key kept")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out))
    }

    func testAppendsFeaturesWhenAbsentPreservingContent() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"")!
        XCTAssertTrue(out.contains("model = \"o3\""))
        XCTAssertTrue(out.contains("[features]"))
        XCTAssertTrue(out.contains("hooks = true"))
    }

    func testCommentedFeaturesHeaderDoesNotCreateDuplicateTable() {
        let source = "[features] # comment\nweb_search = true\n"
        XCTAssertEqual(CodexHookConfig.enableHooks(in: source), "[features] # comment\nhooks = true\nweb_search = true\n")
    }

    func testOnlyFeaturesHooksCanBeFlippedOrCountAsEnabled() {
        for value in ["false", "true"] {
            let source = "[other]\nhooks = \(value)\n[features]\nweb_search = true\n"
            XCTAssertFalse(CodexHookConfig.alreadyEnabled(source))
            XCTAssertEqual(CodexHookConfig.enableHooks(in: source), "[other]\nhooks = \(value)\n[features]\nhooks = true\nweb_search = true\n")
        }
    }

    func testRootAndNestedHooksDoNotHideFeaturesFlag() {
        let source = "hooks = true\n[features.extra]\nhooks = true\n"
        XCTAssertFalse(CodexHookConfig.alreadyEnabled(source))
        XCTAssertEqual(CodexHookConfig.enableHooks(in: source), source + "\n[features]\nhooks = true\n")
    }

    func testQuotedAndSpacedFeaturesHeadersAreRecognized() {
        for header in ["[\"features\"] # flags", "['features']", "[ features ]\r"] {
            let source = "\(header)\nweb_search = true\n"
            XCTAssertEqual(CodexHookConfig.enableHooks(in: source), "\(header)\nhooks = true\nweb_search = true\n")
        }
    }

    func testExistingFeaturesFlagKeepsInlineCommentAndOtherTable() {
        let source = "[features] # flags\n  hooks\t= false # disabled\n[other]\nhooks = false\n"
        XCTAssertEqual(CodexHookConfig.enableHooks(in: source), "[features] # flags\n  hooks\t= true # disabled\n[other]\nhooks = false\n")
    }

    func testQuotedHooksKeyIsNotDuplicated() {
        XCTAssertEqual(CodexHookConfig.enableHooks(in: "[features]\n\"hooks\" = false\n"), "[features]\n\"hooks\" = true\n")
        XCTAssertNil(CodexHookConfig.enableHooks(in: "['features']\n'hooks' = true # active\n"))
    }

    func testUnsupportedFeaturesLayoutsAreLeftUntouched() {
        for source in [
            "features = { hooks = false }\n",
            "features.hooks = false\n",
            "description = '''\n[features]\nhooks = false\n'''\n",
            "[features]\nhooks = 'custom'\n",
        ] {
            XCTAssertNil(CodexHookConfig.enableHooks(in: source))
        }
    }

    func testCommentedFlagIsNotTreatedAsEnabled() {
        XCTAssertFalse(CodexHookConfig.alreadyEnabled("# hooks = true\n"))
    }
}
