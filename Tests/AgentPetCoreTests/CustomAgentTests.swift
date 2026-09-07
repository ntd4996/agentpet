import XCTest
@testable import AgentPetCore

/// Custom CLI agents hooked via `agentpet hook --agent <name>` must keep their
/// own identity instead of masquerading as Claude or collapsing together
/// (issue #56). These lock the three pieces that make that work: the flag →
/// kind/name resolution, the sticky carry-through in the store, and the
/// grouping key the bubble dedups on.
final class CustomAgentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - makeEvent flag resolution

    func testUnrecognizedAgentBecomesUnknownAndKeepsRawName() throws {
        let args = HookArguments(event: "working", session: "s1", agent: "hermes")
        let event = try XCTUnwrap(args.makeEvent(now: now))
        XCTAssertEqual(event.agentKind, .unknown)
        XCTAssertEqual(event.agentName, "hermes")
    }

    func testMissingAgentStillDefaultsToClaude() throws {
        // Claude's hooks omit `--agent`; that legacy default must not change.
        let args = HookArguments(event: "Stop", session: "s1", agent: nil)
        let event = try XCTUnwrap(args.makeEvent(now: now))
        XCTAssertEqual(event.agentKind, .claude)
        XCTAssertNil(event.agentName)
    }

    func testRecognizedAgentMapsToItsKindWithoutRawName() throws {
        let args = HookArguments(event: "working", session: "s1", agent: "codex")
        let event = try XCTUnwrap(args.makeEvent(now: now))
        XCTAssertEqual(event.agentKind, .codex)
        XCTAssertNil(event.agentName)
    }

    // MARK: - Grouping key

    func testDistinctCustomAgentsGetDistinctGroupKeys() {
        let hermes = session(name: "hermes")
        let openclaw = session(name: "openclaw")
        XCTAssertEqual(hermes.groupKey, "unknown:hermes")
        XCTAssertNotEqual(hermes.groupKey, openclaw.groupKey)
    }

    func testSameCustomAgentSharesGroupKeyCaseInsensitively() {
        XCTAssertEqual(session(name: "Hermes").groupKey, session(name: "hermes").groupKey)
    }

    func testKnownKindGroupsByKindNotName() {
        let s = AgentSession(id: "x", agentKind: .claude, state: .working,
                             source: .hook, updatedAt: now)
        XCTAssertEqual(s.groupKey, "claude")
    }

    // MARK: - Sticky carry-through in the store

    func testStoreCarriesAndKeepsCustomAgentName() throws {
        let store = SessionStore()
        _ = store.apply(HookArguments(event: "working", session: "s1", agent: "hermes")
            .makeEvent(now: now)!, now: now)
        // A later event for the same session omits the name (only the first
        // event carries it); it must stay sticky, not reset to nil.
        let updated = try XCTUnwrap(
            store.apply(AgentEvent(sessionId: "s1", agentKind: .unknown,
                                   eventName: "done", timestamp: now),
                        now: now.addingTimeInterval(1))
        )
        XCTAssertEqual(updated.agentName, "hermes")
        XCTAssertEqual(updated.groupKey, "unknown:hermes")
    }

    private func session(name: String) -> AgentSession {
        AgentSession(id: name, agentKind: .unknown, state: .working,
                     source: .hook, updatedAt: now, agentName: name)
    }
}
