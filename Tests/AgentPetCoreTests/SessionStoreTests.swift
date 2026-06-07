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
        XCTAssertNil(StateMapper.state(for: .claude, eventName: "SubagentStop"),
                     "a subagent finishing mid-task must not change the main session's state")
    }

    func testUnknownEventIsIgnored() {
        XCTAssertNil(StateMapper.state(for: .claude, eventName: "Bogus"))
        XCTAssertNil(StateMapper.state(for: .codex, eventName: "Bogus"))
        XCTAssertNil(StateMapper.state(for: .unknown, eventName: "Stop"))
    }

    func testDirectStateNameMapsForAnyKind() {
        XCTAssertEqual(StateMapper.state(for: .cli, eventName: "working"), .working)
        XCTAssertEqual(StateMapper.state(for: .cli, eventName: "done"), .done)
        XCTAssertEqual(StateMapper.state(for: .unknown, eventName: "waiting"), .waiting)
    }

    func testCodexMapping() {
        XCTAssertEqual(StateMapper.state(for: .codex, eventName: "SessionStart"), .registered)
        XCTAssertEqual(StateMapper.state(for: .codex, eventName: "PreToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .codex, eventName: "PermissionRequest"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .codex, eventName: "Stop"), .done)
    }

    func testGeminiMapping() {
        XCTAssertEqual(StateMapper.state(for: .gemini, eventName: "BeforeTool"), .working)
        XCTAssertEqual(StateMapper.state(for: .gemini, eventName: "Notification"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .gemini, eventName: "AfterAgent"), .done)
    }

    func testHookSpecsCoverInstallEvents() {
        // Every event we register must either map to a state, end the session,
        // or be an intentionally-ignored event (documented here).
        let intentionallyIgnored: [AgentKind: Set<String>] = [
            .claude: ["SubagentStop"]
        ]
        for kind in [AgentKind.claude, .codex, .gemini] {
            let spec = AgentHooks.spec(for: kind)!
            let ignored = intentionallyIgnored[kind] ?? []
            for event in spec.events
            where !StateMapper.isSessionEnd(for: kind, eventName: event) && !ignored.contains(event) {
                XCTAssertNotNil(StateMapper.state(for: kind, eventName: event), "\(kind) \(event)")
            }
        }
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

    func testRefineStateAppliesWhenStateAndSinceStillMatch() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        XCTAssertEqual(applied?.state, .done)

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        let refined = store.session(id: "s1")
        XCTAssertEqual(refined?.state, .waiting)
        XCTAssertEqual(refined?.stateSince, applied!.stateSince,
                       "correction preserves the original transition time")
    }

    func testRefineStateNoOpsWhenANewerEventAlreadyChangedState() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        store.apply(event("UserPromptSubmit"), now: t0.addingTimeInterval(2))   // user replied -> working

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        XCTAssertEqual(store.session(id: "s1")?.state, .working,
                       "a newer transition must never be clobbered by a stale correction")
    }

    func testRefineStateNoOpsWhenSinceNoLongerMatches() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        let staleSince = applied!.stateSince.addingTimeInterval(-10)

        store.refineState(id: "s1", from: .done, to: .waiting, since: staleSince)

        XCTAssertEqual(store.session(id: "s1")?.state, .done,
                       "a `since` mismatch means this correction targets a transition that's gone")
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

    func testPruneRemovesStaleRegisteredSooner() {
        let store = SessionStore(staleActiveAfter: 300, staleRegisteredAfter: 90)
        store.apply(event("SessionStart"), now: t0)   // registered, never worked
        store.prune(now: t0.addingTimeInterval(60))
        XCTAssertNotNil(store.session(id: "s1"), "kept before registered timeout")
        store.prune(now: t0.addingTimeInterval(90))
        XCTAssertNil(store.session(id: "s1"), "idle registered session removed sooner than working")
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
