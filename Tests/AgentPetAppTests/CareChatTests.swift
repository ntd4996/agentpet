import XCTest
@testable import agentpet
import AgentPetCore

@MainActor
final class CareChatTests: XCTestCase {

    private let basePhrases = ["Hello!", "Hi there!"]

    func testIdlePoolFullHungerNoHungryLines() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .full)
        // Should not contain any hungry/starving care lines
        let careLines = Set(CareChat.hungry + CareChat.starving)
        for line in pool {
            XCTAssertFalse(careLines.contains(line), "Pool should not contain care line: \(line)")
        }
        // Base phrases should still be present
        XCTAssertTrue(pool.contains("Hello!"))
    }

    func testIdlePoolHungryAddsHungryLines() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .hungry)
        // Pool should include base phrases AND hungry care lines
        XCTAssertTrue(pool.count > basePhrases.count)
        XCTAssertTrue(pool.contains("Hello!"))
    }

    func testIdlePoolStarvingReplacesPool() {
        let pool = CareChat.idlePool(base: basePhrases, hunger: .starving)
        // Starving replaces the entire pool — base phrases should be gone
        XCTAssertFalse(pool.contains("Hello!"))
        XCTAssertFalse(pool.isEmpty)
    }
}
