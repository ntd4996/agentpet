import XCTest
@testable import agentpet

/// The Care tab warns only when OpenUsage answered earlier and has then missed
/// two polls in a row. Never having seen it must stay silent (most people
/// don't run it), and one slow answer must not raise a false alarm.
final class OpenUsageLostTests: XCTestCase {
    func testNeverSeenStaysSilentHoweverManyMisses() {
        XCTAssertFalse(OpenUsageClient.isLost(missedPolls: 0, everSeen: false))
        XCTAssertFalse(OpenUsageClient.isLost(missedPolls: 5, everSeen: false))
    }

    func testOneMissAfterSeenIsNotLostYet() {
        XCTAssertFalse(OpenUsageClient.isLost(missedPolls: 1, everSeen: true))
    }

    func testTwoMissesInARowAfterSeenIsLost() {
        XCTAssertTrue(OpenUsageClient.isLost(missedPolls: 2, everSeen: true))
        XCTAssertTrue(OpenUsageClient.isLost(missedPolls: 7, everSeen: true))
    }

    func testReachableIsNotLost() {
        XCTAssertFalse(OpenUsageClient.isLost(missedPolls: 0, everSeen: true))
    }
}
