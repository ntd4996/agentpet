import XCTest
@testable import AgentPetCore

final class StateMapperTests: XCTestCase {
    func testClaudeEventMapping() {
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "SessionStart"), .registered)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "UserPromptSubmit"), .working)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "PreToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "PostToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "Notification"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "Stop"), .done)
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "SubagentStop"), .done)
    }

    func testUnknownEventIsIgnored() {
        XCTAssertNil(StateMapper.state(for: .claude, eventName: "Bogus"))
        XCTAssertNil(StateMapper.state(for: .codex, eventName: "Stop"))
    }

    func testDirectStateNameMapsForAnyKind() {
        XCTAssertEqual(StateMapper.state(for: .cli, eventName: "working"), .working)
        XCTAssertEqual(StateMapper.state(for: .cli, eventName: "done"), .done)
        XCTAssertEqual(StateMapper.state(for: .unknown, eventName: "waiting"), .waiting)
    }
}

final class SessionStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, session: String = "s1", project: String? = "/proj") -> AgentEvent {
        AgentEvent(sessionId: session, agentKind: .claude, eventName: name, project: project, message: nil, timestamp: t0)
    }

    func testApplyCreatesSession() {
        let store = SessionStore()
        let s = store.apply(event("SessionStart"), now: t0)
        XCTAssertEqual(s?.state, .registered)
        XCTAssertEqual(s?.project, "/proj")
        XCTAssertEqual(s?.source, .hook)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testApplyUpdatesExistingAndKeepsProjectWhenNil() {
        let store = SessionStore()
        store.apply(event("SessionStart"), now: t0)
        let updated = store.apply(event("Stop", project: nil), now: t0.addingTimeInterval(5))
        XCTAssertEqual(updated?.state, .done)
        XCTAssertEqual(updated?.project, "/proj", "project should persist when event omits it")
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testApplyIgnoresUnmappedEvent() {
        let store = SessionStore()
        XCTAssertNil(store.apply(event("Bogus"), now: t0))
        XCTAssertEqual(store.sessions.count, 0)
    }

    func testPruneDemotesDoneToIdle() {
        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 600)
        store.apply(event("Stop"), now: t0)
        store.prune(now: t0.addingTimeInterval(10))
        XCTAssertEqual(store.session(id: "s1")?.state, .done, "still done before threshold")
        store.prune(now: t0.addingTimeInterval(40))
        XCTAssertEqual(store.session(id: "s1")?.state, .idle, "demoted to idle after threshold")
    }

    func testPruneRemovesLongIdle() {
        let store = SessionStore(doneToIdleAfter: 30, removeIdleAfter: 600)
        store.apply(event("Stop"), now: t0)
        store.prune(now: t0.addingTimeInterval(40))   // -> idle at t0+40
        store.prune(now: t0.addingTimeInterval(40 + 600))
        XCTAssertNil(store.session(id: "s1"), "removed after idle timeout")
    }

    func testPruneRemovesStaleActiveSession() {
        let store = SessionStore(staleActiveAfter: 300)
        store.apply(event("UserPromptSubmit"), now: t0)   // working
        store.prune(now: t0.addingTimeInterval(120))
        XCTAssertNotNil(store.session(id: "s1"), "kept before stale timeout")
        store.prune(now: t0.addingTimeInterval(300))
        XCTAssertNil(store.session(id: "s1"), "stale working session removed")
    }

    func testClearRemovesAll() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "a"), now: t0)
        store.apply(event("UserPromptSubmit", session: "b"), now: t0)
        store.clear()
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testSortedByAttentionPriority() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "working"), now: t0)
        store.apply(event("Notification", session: "waiting"), now: t0)
        store.apply(event("Stop", session: "done"), now: t0)
        let order = store.sorted.map(\.id)
        XCTAssertEqual(order, ["working", "waiting", "done"])
    }
}
