import XCTest
@testable import AgentPetCore

final class PetWindowPlannerTests: XCTestCase {
    private func s(_ id: String, _ state: AgentState, project: String?) -> AgentSession {
        AgentSession(id: id, agentKind: .claude, project: project, state: state,
                     source: .hook, updatedAt: Date(timeIntervalSince1970: 0))
    }
    private let cat = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
    private func byKey(_ specs: [PetWindowSpec]) -> [String: PetWindowSpec] {
        Dictionary(uniqueKeysWithValues: specs.map { ($0.key, $0) })
    }

    // MARK: - Split OFF (single shared pet)

    func testSplitOffSingleAggregateSpec() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo"), s("2", .waiting, project: "/x")],
            split: false, mappings: [cat], defaultPetID: "boba")
        XCTAssertEqual(specs.count, 1)
        XCTAssertEqual(specs[0].key, "default")
        XCTAssertEqual(specs[0].petID, "boba")
        XCTAssertEqual(specs[0].mood, .working)      // working beats waiting
        XCTAssertEqual(specs[0].count, 2)
    }

    func testSplitOffIdleWhenNothingActive() {
        let specs = PetWindowPlanner.plan(sessions: [], split: false, mappings: [], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])
        XCTAssertEqual(specs[0].mood, .idle)
    }

    // MARK: - Split ON (only configured projects split off; the rest merge)

    func testConfiguredProjectGetsOwnWindowRestMergeToDefault() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/src"),   // matches cat
                       s("2", .done, project: "/other")],            // unconfigured → main pet
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        XCTAssertEqual(specs.count, 2)                  // cat window + the main pet
        XCTAssertEqual(m["/work/foo"]?.petID, "cat")
        XCTAssertEqual(m["/work/foo"]?.projectName, "foo")
        XCTAssertEqual(m["/work/foo"]?.mood, .working)
        XCTAssertNil(m["/other"], "an unconfigured project must not get its own window")
        XCTAssertEqual(m["default"]?.petID, "boba")     // /other folds into the main pet
        XCTAssertEqual(m["default"]?.mood, .done)
        XCTAssertEqual(m["default"]?.count, 1)
    }

    func testSubfolderSessionsCollapseToConfiguredRoot() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo/a"), s("2", .working, project: "/work/foo/b")],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        XCTAssertEqual(m["/work/foo"]?.count, 2)
        XCTAssertEqual(m["/work/foo"]?.mood, .working)
        XCTAssertEqual(m["default"]?.count, 0)          // main pet always present, idle here
        XCTAssertEqual(m["default"]?.mood, .idle)
    }

    func testConfiguredProjectPersistsWhenIdle() {
        // A configured project with no active session still shows its idle window
        // (does not vanish when its agent stops).
        let specs = PetWindowPlanner.plan(sessions: [], split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        XCTAssertEqual(m["/work/foo"]?.petID, "cat")
        XCTAssertEqual(m["/work/foo"]?.mood, .idle)
        XCTAssertEqual(m["default"]?.mood, .idle)
    }

    func testRemovingMappingFoldsBackToMainPet() {
        // Same session, but its mapping was removed → it merges into the main pet
        // and gets no window of its own.
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [], defaultPetID: "boba")
        XCTAssertEqual(specs.map(\.key), ["default"])
        XCTAssertEqual(specs[0].mood, .working)
        XCTAssertEqual(specs[0].count, 1)
    }

    func testProjectlessSessionsGoToMainPet() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: nil)],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        XCTAssertEqual(m["default"]?.mood, .working)    // no project → main pet
        XCTAssertEqual(m["/work/foo"]?.mood, .idle)     // configured cat still shown, idle
    }

    func testRegisteredAndIdleNotActive() {
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .idle, project: "/work/foo"), s("2", .registered, project: "/y")],
            split: true, mappings: [cat], defaultPetID: "boba")
        let m = byKey(specs)
        XCTAssertEqual(m["/work/foo"]?.mood, .idle)     // nothing active
        XCTAssertEqual(m["default"]?.mood, .idle)
        XCTAssertNil(m["/y"], "non-active unconfigured project gets no window")
    }

    func testSplitAlwaysHasMainPetWindow() {
        // The "default" (main pet) window is always present in split mode, so the
        // break nudge and project-less work always have a pet to show.
        let specs = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [cat], defaultPetID: "boba")
        XCTAssertTrue(specs.contains { $0.key == "default" })
    }

    func testHideIdleProjectsDropsIdleConfiguredWindow() {
        // Configured project idle + hideIdleProjects on → only the main pet shows.
        let idle = PetWindowPlanner.plan(
            sessions: [], split: true, mappings: [cat], defaultPetID: "boba", hideIdleProjects: true)
        XCTAssertEqual(idle.map(\.key), ["default"])
        // When it's active again, its window comes back even with the option on.
        let active = PetWindowPlanner.plan(
            sessions: [s("1", .working, project: "/work/foo")],
            split: true, mappings: [cat], defaultPetID: "boba", hideIdleProjects: true)
        XCTAssertTrue(active.contains { $0.key == "/work/foo" })
    }

    func testForceDefaultDoesNotDuplicateMainPet() {
        let specs = PetWindowPlanner.plan(
            sessions: [], split: true, mappings: [cat], defaultPetID: "boba", forceDefault: true)
        XCTAssertEqual(specs.filter { $0.key == "default" }.count, 1)
    }

    // MARK: - windowKeys

    func testWindowKeysSplitOffAlwaysReturnsDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: false,
                                               mappings: [cat], selectedPetID: "cat")
        XCTAssertEqual(keys, ["default"])
    }

    func testWindowKeysSplitOnMappedPet() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        // cat mapped to /work/foo → normalized key
        XCTAssertTrue(keys.contains(where: { $0.contains("foo") }))
        XCTAssertFalse(keys.contains("default"))
    }

    func testWindowKeysSplitOnSelectedPetIncludesDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "boba", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        XCTAssertTrue(keys.contains("default"))
    }

    func testWindowKeysSplitOnSharedPetMultipleKeys() {
        let m1 = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
        let m2 = ProjectPetMapping(projectPath: "/work/bar", petID: "cat")
        let keys = PetWindowPlanner.windowKeys(forPetID: "cat", split: true,
                                               mappings: [m1, m2], selectedPetID: "boba")
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.contains(where: { $0.contains("foo") }))
        XCTAssertTrue(keys.contains(where: { $0.contains("bar") }))
    }

    func testWindowKeysSplitOnUnknownPetFallsToDefault() {
        let keys = PetWindowPlanner.windowKeys(forPetID: "unknown", split: true,
                                               mappings: [cat], selectedPetID: "boba")
        XCTAssertEqual(keys, ["default"])
    }
}
