import XCTest
@testable import agentpet

@MainActor
final class ProjectUsageStoreCostTests: XCTestCase {
    private let storageKey = "agentpet.projectUsage"
    private let dirtyKey = "agentpet.projectUsage.dirty"

    nonisolated(unsafe) private var savedStorage: Any?
    nonisolated(unsafe) private var savedDirty: Any?

    override func setUp() {
        super.setUp()
        savedStorage = UserDefaults.standard.object(forKey: storageKey)
        savedDirty = UserDefaults.standard.object(forKey: dirtyKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: dirtyKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: dirtyKey)
        if let savedStorage { UserDefaults.standard.set(savedStorage, forKey: storageKey) }
        if let savedDirty { UserDefaults.standard.set(savedDirty, forKey: dirtyKey) }
        savedStorage = nil
        savedDirty = nil
        super.tearDown()
    }

    // a) Backward-compat decode: old JSON without costUSD must still decode, defaulting to 0.
    func testRowDecodesOldFormatWithoutCostUSD() throws {
        let json = """
        {"projectId":"p1","projectName":"test","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1}
        """
        let data = Data(json.utf8)
        let row = try JSONDecoder().decode(ProjectUsageStore.Row.self, from: data)
        XCTAssertEqual(row.costUSD, 0)
        XCTAssertEqual(row.tokens, 100)
    }

    // b) Forward decode: JSON with costUSD present decodes correctly.
    func testRowDecodesNewFormatWithCostUSD() throws {
        let json = """
        {"projectId":"p1","projectName":"test","agent":"claude","day":"2026-07-01","tokens":100,"sessions":1,"costUSD":1.5}
        """
        let data = Data(json.utf8)
        let row = try JSONDecoder().decode(ProjectUsageStore.Row.self, from: data)
        XCTAssertEqual(row.costUSD, 1.5)
    }

    // c) recordTokens with cost accumulates correctly across multiple calls.
    func testRecordTokensAccumulatesCost() {
        let store = ProjectUsageStore()
        store.recordTokens(1000, project: "/some/project", agent: "claude", costUSD: 0.05)
        store.recordTokens(1000, project: "/some/project", agent: "claude", costUSD: 0.05)

        let row = store.pendingRows().first { $0.agent == "claude" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.tokens, 2000)
        XCTAssertEqual(row?.costUSD ?? -1, 0.10, accuracy: 0.0001)
    }

    // d) recordTokens without cost arg defaults to 0, keeping existing call sites intact.
    func testRecordTokensWithoutCostDefaultsToZero() {
        let store = ProjectUsageStore()
        store.recordTokens(500, project: "/p", agent: "claude")

        let row = store.pendingRows().first { $0.agent == "claude" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.costUSD, 0)
    }

    // e) todayCostUSD sums today's rows across projects/agents.
    func testTodayCostUSDSumsAcrossProjects() {
        let store = ProjectUsageStore()
        store.recordTokens(1000, project: "/project/one", agent: "claude", costUSD: 0.10)
        store.recordTokens(2000, project: "/project/two", agent: "codex", costUSD: 0.20)

        XCTAssertEqual(store.todayCostUSD, 0.30, accuracy: 0.0001)
    }

    // f) monthlyCostUSD is at least todayCostUSD, and both are non-negative.
    func testMonthlyCostUSDIsAtLeastTodayCostUSD() {
        let store = ProjectUsageStore()
        store.recordTokens(1000, project: "/project/one", agent: "claude", costUSD: 0.10)

        XCTAssertGreaterThanOrEqual(store.monthlyCostUSD, store.todayCostUSD)
        XCTAssertGreaterThanOrEqual(store.todayCostUSD, 0)
        XCTAssertGreaterThanOrEqual(store.monthlyCostUSD, 0)
    }
}
