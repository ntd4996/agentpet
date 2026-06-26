import XCTest
@testable import AgentPetCore

final class HookArgumentsTests: XCTestCase {
    func testParseAllFlags() {
        let args = ["--event", "Stop", "--session", "s1", "--project", "/p",
                    "--agent", "claude", "--message", "hello world"]
        let parsed = HookArguments.parse(args)
        XCTAssertEqual(parsed, HookArguments(
            event: "Stop", session: "s1", project: "/p", agent: "claude", message: "hello world"
        ))
    }

    func testParseIgnoresUnknownFlags() {
        let parsed = HookArguments.parse(["--bogus", "x", "--event", "Stop", "--session", "s1"])
        XCTAssertEqual(parsed.event, "Stop")
        XCTAssertEqual(parsed.session, "s1")
    }

    func testMakeEventRequiresEventAndSession() {
        let now = Date(timeIntervalSince1970: 1)
        XCTAssertNil(HookArguments(event: "Stop").makeEvent(now: now))
        XCTAssertNil(HookArguments(session: "s1").makeEvent(now: now))
    }

    func testMakeEventDefaultsToClaude() {
        let now = Date(timeIntervalSince1970: 1)
        let event = HookArguments(event: "Stop", session: "s1").makeEvent(now: now)
        XCTAssertEqual(event?.agentKind, .claude)
        XCTAssertEqual(event?.eventName, "Stop")
        XCTAssertEqual(event?.timestamp, now)
    }
}

final class RunArgumentsTests: XCTestCase {
    func testParsesFlagsThenCommand() {
        let parsed = RunArguments.parse(["--session", "s1", "--project", "/p", "--agent", "cli", "--", "aider", "--model", "gpt"])
        XCTAssertEqual(parsed, RunArguments(session: "s1", project: "/p", agent: "cli", command: ["aider", "--model", "gpt"]))
    }

    func testNoFlagsJustCommand() {
        let parsed = RunArguments.parse(["--", "claude"])
        XCTAssertEqual(parsed.command, ["claude"])
        XCTAssertNil(parsed.session)
    }

    func testNoCommand() {
        XCTAssertTrue(RunArguments.parse(["--session", "x"]).command.isEmpty)
    }
}

final class EventSenderTests: XCTestCase {
    #if !os(Windows)
    func testSenderDeliversOverSocket() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpet-\(UUID().uuidString).sock")
            .path
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let exp = expectation(description: "delivered")
        let box = Box()
        try server.start { box.value = $0; exp.fulfill() }

        let event = AgentEvent(sessionId: "s9", agentKind: .claude, eventName: "Notification",
                               timestamp: Date(timeIntervalSince1970: 42))
        let queueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpet-unused-\(UUID().uuidString)", isDirectory: true)
            .path
        let delivered = EventSender.send(event, socketPath: path, queueDir: queueDir)

        wait(for: [exp], timeout: 2)
        XCTAssertTrue(delivered)
        XCTAssertEqual(box.value, event)
    }
    #endif

    func testSenderFallsBackToQueueWhenNoServer() throws {
        let socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpet-missing-\(UUID().uuidString).sock")
            .path
        let queueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentpet-q-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: queueDir) }

        let event = AgentEvent(sessionId: "s10", agentKind: .claude, eventName: "Stop",
                               timestamp: Date(timeIntervalSince1970: 7))
        let delivered = EventSender.send(event, socketPath: socketPath, queueDir: queueDir.path)
        XCTAssertFalse(delivered, "undelivered events should be queued")

        var received: [AgentEvent] = []
        EventSocketServer.drainQueue(directory: queueDir.path) { received.append($0) }
        XCTAssertEqual(received, [event])
    }

    private final class Box: @unchecked Sendable {
        var value: AgentEvent?
    }
}
