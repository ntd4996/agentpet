import XCTest
@testable import AgentPetCore

final class ActivityFormatterTests: XCTestCase {

    // MARK: - Rotation

    func test_rotation_doesNotRepeatConsecutively() {
        let first = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        let second = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "rot1",
            toolName: "Read", toolInput: nil, explicitMessage: nil
        )
        XCTAssertNotEqual(first, second, "consecutive calls same tool should rotate")
    }

    func test_rotation_cyclesFullPool() {
        // reading pool has 5 phrases — 5 distinct calls must yield 5 distinct phrases
        let poolSize = 5
        var seen = Set<String?>()
        for _ in 0..<poolSize {
            let msg = ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "rot2",
                toolName: "Read", toolInput: nil, explicitMessage: nil
            )
            seen.insert(msg)
        }
        XCTAssertEqual(seen.count, poolSize, "should cycle through all \(poolSize) reading phrases")
    }

    // MARK: - Tool categorization

    func test_toolCategory_matchesClaudeToolNames() {
        let cases: [(String, [String])] = [
            ("Read", ActivityTheme.chef.reading),
            ("Edit", ActivityTheme.chef.writing),
            ("Write", ActivityTheme.chef.writing),
            ("MultiEdit", ActivityTheme.chef.writing),
            ("Bash", ActivityTheme.chef.running),
            ("Glob", ActivityTheme.chef.searching),
            ("Grep", ActivityTheme.chef.searching),
            ("WebSearch", ActivityTheme.chef.searching),
            ("WebFetch", ActivityTheme.chef.searching),
            ("Agent", ActivityTheme.chef.delegating),
            ("Task", ActivityTheme.chef.delegating),
            ("Skill", ActivityTheme.chef.skill),
        ]
        for (toolName, pool) in cases {
            let msg = ActivityFormatter.activityMessage(
                eventName: "PreToolUse", sessionId: "cat-claude-\(toolName)",
                toolName: toolName, toolInput: nil, explicitMessage: nil
            )
            XCTAssertTrue(pool.contains(msg ?? ""), "\(toolName) -> \(msg ?? "nil") not in expected pool")
        }
    }

    func test_toolCategory_matchesCursorToolNames() {
        let cases: [(String, [String])] = [
            ("read_file", ActivityTheme.chef.reading),
            ("edit_file", ActivityTheme.chef.writing),
            ("delete_file", ActivityTheme.chef.writing),
            ("run_terminal_cmd", ActivityTheme.chef.running),
            ("codebase_search", ActivityTheme.chef.searching),
            ("grep_search", ActivityTheme.chef.searching),
            ("list_dir", ActivityTheme.chef.searching),
        ]
        for (toolName, pool) in cases {
            let msg = ActivityFormatter.activityMessage(
                eventName: "preToolUse", sessionId: "cat-cursor-\(toolName)",
                toolName: toolName, toolInput: nil, explicitMessage: nil
            )
            XCTAssertTrue(pool.contains(msg ?? ""), "\(toolName) -> \(msg ?? "nil") not in expected pool")
        }
    }

    // MARK: - Extension hints

    func test_extensionHint_testFile_reading() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext1",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Reviewing tests…")
    }

    func test_extensionHint_testFile_writing() {
        let input = ToolActivityInput(filePath: "Tests/FooTests/BarTests.swift")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext2",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Refining tests…")
    }

    func test_extensionHint_markdown_reading() {
        let input = ToolActivityInput(filePath: "README.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext3",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Reading the docs…")
    }

    func test_extensionHint_markdown_writing() {
        let input = ToolActivityInput(filePath: "docs/guide.md")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext4",
            toolName: "Write", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Updating the docs…")
    }

    func test_extensionHint_json_reading() {
        let input = ToolActivityInput(filePath: "config/settings.json")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext5",
            toolName: "Read", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Parsing config…")
    }

    func test_extensionHint_plist_writing() {
        let input = ToolActivityInput(filePath: "Info.plist")
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "ext6",
            toolName: "Edit", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Adjusting config…")
    }

    // MARK: - State messages

    func test_stateMessage_done_returnsPhrase() {
        XCTAssertNotNil(ActivityFormatter.stateMessage(for: .done))
    }

    func test_stateMessage_waiting_returnsPhrase() {
        XCTAssertNotNil(ActivityFormatter.stateMessage(for: .waiting))
    }

    func test_stateMessage_idle_returnsNil() {
        XCTAssertNil(ActivityFormatter.stateMessage(for: .idle))
    }

    func test_stateMessage_working_returnsNil() {
        XCTAssertNil(ActivityFormatter.stateMessage(for: .working))
    }

    func test_stateMessage_done_rotates() {
        let first  = ActivityFormatter.stateMessage(for: .done)
        let second = ActivityFormatter.stateMessage(for: .done)
        XCTAssertNotEqual(first, second, "done phrases should rotate")
    }

    // MARK: - Literal theme & action formatting

    override func setUp() {
        super.setUp()
        ActivityFormatter.currentTheme = .chef
    }

    override func tearDown() {
        super.tearDown()
        ActivityFormatter.currentTheme = .chef
    }

    func test_literalAction_descriptionSummaryWins() {
        let input = ToolActivityInput(
            filePath: "Sources/App/PetView.swift",
            command: "swift test",
            description: "Run unit test suite"
        )
        let result = ActivityFormatter.literalAction(toolName: "run_command", toolInput: input)
        XCTAssertEqual(result, "Run unit test suite")
    }

    func test_literalAction_filePathEditing() {
        let input = ToolActivityInput(filePath: "Sources/App/PetView.swift")
        let result = ActivityFormatter.literalAction(toolName: "edit_file", toolInput: input)
        XCTAssertEqual(result, "Editing PetView.swift")
    }

    func test_literalAction_filePathReading() {
        let input = ToolActivityInput(filePath: "Sources/App/PetView.swift")
        let result = ActivityFormatter.literalAction(toolName: "read_file", toolInput: input)
        XCTAssertEqual(result, "Reading PetView.swift")
    }

    func test_literalAction_commandRunning() {
        let input = ToolActivityInput(command: "swift build -c release")
        let result = ActivityFormatter.literalAction(toolName: "run_command", toolInput: input)
        XCTAssertEqual(result, "Running: swift build -c release")
    }

    func test_literalAction_searchQuery() {
        let input = ToolActivityInput(query: "ActivityFormatter")
        let result = ActivityFormatter.literalAction(toolName: "search_web", toolInput: input)
        XCTAssertEqual(result, "Searching: \"ActivityFormatter\"")
    }

    func test_literalAction_subagentPrompt() {
        let input = ToolActivityInput(prompt: "Analyze architecture and security")
        let result = ActivityFormatter.literalAction(toolName: "invoke_subagent", toolInput: input)
        XCTAssertEqual(result, "Subagent: Analyze architecture and se…")
    }

    func test_literalAction_fallbackFormattedToolName() {
        let result = ActivityFormatter.literalAction(toolName: "run_command", toolInput: nil)
        XCTAssertEqual(result, "Running command…")

        let result2 = ActivityFormatter.literalAction(toolName: "custom_mcp_tool", toolInput: nil)
        XCTAssertEqual(result2, "Using custom_mcp_tool…")
    }

    func test_themeLiteral_integratesWithActivityMessage() {
        ActivityFormatter.currentTheme = .literal
        let input = ToolActivityInput(
            filePath: "Sources/App/PetView.swift",
            command: "git status",
            description: "Check working directory status"
        )
        let msg = ActivityFormatter.activityMessage(
            eventName: "PreToolUse", sessionId: "lit1",
            toolName: "run_command", toolInput: input, explicitMessage: nil
        )
        XCTAssertEqual(msg, "Check working directory status")
    }

    func test_thinking_eventNameWorkingWithoutTool_returnsThinking() {
        ActivityFormatter.currentTheme = .literal
        let msg = ActivityFormatter.activityMessage(
            eventName: "working", sessionId: "think1",
            toolName: nil, toolInput: nil, explicitMessage: nil
        )
        XCTAssertTrue(ActivityTheme.literal.thinking.contains(msg ?? ""), "got \(msg ?? "nil")")
    }
}
