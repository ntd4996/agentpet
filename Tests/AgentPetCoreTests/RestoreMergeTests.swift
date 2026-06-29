import XCTest
@testable import AgentPetCore

/// Covers PetCare.merging, the cross-device restore merge (issue #37).
final class RestoreMergeTests: XCTestCase {

    private func cloud(
        xp: Int = 0, tokens: Int = 0, meals: Int = 0, streak: Int = 0,
        lastFedAt: Date? = nil, achievements: Set<Achievement> = []
    ) -> PetCare.CloudCareStats {
        PetCare.CloudCareStats(xp: xp, tokens: tokens, meals: meals, streak: streak, lastFedAt: lastFedAt, achievements: achievements)
    }

    private let now = Date(timeIntervalSince1970: 1_782_700_000)

    // Lifetime counters never shrink: a lower cloud must not undo local progress.
    func testGrowOnlyNeverShrinksLocal() {
        var local = PetCareState()
        local.xp = 5000; local.totalTokens = 1_000_000; local.totalMeals = 200
        let merged = PetCare.merging(local, with: cloud(xp: 100, tokens: 10, meals: 1), now: now)
        XCTAssertEqual(merged.xp, 5000)
        XCTAssertEqual(merged.totalTokens, 1_000_000)
        XCTAssertEqual(merged.totalMeals, 200)
    }

    // A higher cloud lifts local up to the cloud values.
    func testCloudHigherLiftsLocal() {
        var local = PetCareState()
        local.xp = 100; local.totalTokens = 10; local.totalMeals = 1
        let merged = PetCare.merging(local, with: cloud(xp: 9000, tokens: 5_000_000, meals: 300), now: now)
        XCTAssertEqual(merged.xp, 9000)
        XCTAssertEqual(merged.totalTokens, 5_000_000)
        XCTAssertEqual(merged.totalMeals, 300)
    }

    // Restoring onto a brand-new device creates the pet from the cloud stats.
    func testRestoreOntoEmptyDevice() {
        let merged = PetCare.merging(nil, with: cloud(xp: 4200, tokens: 2_000_000, meals: 88, streak: 3,
                                                      lastFedAt: now), now: now)
        XCTAssertEqual(merged.xp, 4200)
        XCTAssertEqual(merged.totalMeals, 88)
        XCTAssertEqual(merged.streakDays, 3)
        XCTAssertEqual(merged.lastFedAt, now)
    }

    // Streak follows the most recent feeding, not max(): when the cloud fed more
    // recently it wins (even if its streak is lower, e.g. a reset).
    func testStreakFollowsMoreRecentCloud() {
        var local = PetCareState()
        local.streakDays = 9
        local.lastFedAt = Date(timeIntervalSince1970: 1_782_600_000) // older
        let cloudFed = Date(timeIntervalSince1970: 1_782_690_000)    // newer
        let merged = PetCare.merging(local, with: cloud(streak: 1, lastFedAt: cloudFed), now: now)
        XCTAssertEqual(merged.streakDays, 1)
        XCTAssertEqual(merged.lastFedAt, cloudFed)
    }

    // When this machine fed more recently, its streak and lastFedAt are kept.
    func testStreakKeepsMoreRecentLocal() {
        var local = PetCareState()
        local.streakDays = 12
        local.lastFedAt = Date(timeIntervalSince1970: 1_782_695_000) // newer
        let cloudFed = Date(timeIntervalSince1970: 1_782_600_000)    // older
        let merged = PetCare.merging(local, with: cloud(streak: 4, lastFedAt: cloudFed), now: now)
        XCTAssertEqual(merged.streakDays, 12)
        XCTAssertEqual(merged.lastFedAt, local.lastFedAt)
    }

    // Achievements union across machines.
    func testAchievementsUnion() {
        var local = PetCareState()
        local.unlockedAchievements = [.firstMeal, .level5]
        let merged = PetCare.merging(local, with: cloud(achievements: [.level5, .streak7]), now: now)
        XCTAssertTrue(merged.unlockedAchievements?.isSuperset(of: [.firstMeal, .level5, .streak7]) ?? false)
    }

    // Merging the higher stats re-reconciles badges they now qualify for, even if
    // the cloud didn't send them (e.g. level10 from a high XP).
    func testReconcilesBadgesFromMergedStats() {
        let merged = PetCare.merging(nil, with: cloud(xp: 200_000, meals: 1, lastFedAt: now), now: now)
        XCTAssertTrue(merged.unlockedAchievements?.contains(.level10) ?? false)
    }

    // Real payload shape from /api/care/restore decodes + merges without crashing.
    func testRealPayloadDecodesAndMerges() throws {
        let json = """
        {"pets":[{"id":"vibecoder","name":"VibeCoder","xp":75329,"tokens":287657950,"meals":745,"streak":8,"lastFedAt":1782717347,"week":[22097606,21226030,2541401,35203639,1773674,152404,2723342],"achievements":["tokens1M","firstMeal","sessions500","tokens50M","tokens10M","sessions100","level10","streak7","level5","nightOwl","level20"]}]}
        """
        struct CloudPet: Decodable {
            let id: String; let name: String?; let xp: Int; let tokens: Int; let meals: Int
            let streak: Int; let lastFedAt: Int?; let achievements: [String]?
        }
        struct Resp: Decodable { let pets: [CloudPet] }
        let resp = try JSONDecoder().decode(Resp.self, from: Data(json.utf8))
        let p = resp.pets[0]
        let ach = Set((p.achievements ?? []).compactMap { Achievement(rawValue: $0) })
        XCTAssertEqual(ach.count, 11, "all 11 server achievement keys must map to the Swift enum")
        let merged = PetCare.merging(nil, with: cloud(
            xp: p.xp, tokens: p.tokens, meals: p.meals, streak: p.streak,
            lastFedAt: p.lastFedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            achievements: ach), now: now)
        XCTAssertEqual(merged.xp, 75329)
        XCTAssertEqual(merged.totalTokens, 287657950)
        XCTAssertEqual(merged.totalMeals, 745)
        XCTAssertEqual(merged.streakDays, 8)
    }
}
