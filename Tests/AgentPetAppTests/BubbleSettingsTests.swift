import XCTest
@testable import agentpet

@MainActor
final class BubbleSettingsTests: XCTestCase {
    private let multiAgentBubbleKey = "agentpet.bubble.multiAgentBubbleEnabled"
    private let sessionGroupingKey = "agentpet.bubble.sessionGrouping"
    private let collapseDuplicatesKey = "agentpet.bubble.collapseDuplicates"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
        UserDefaults.standard.removeObject(forKey: sessionGroupingKey)
        UserDefaults.standard.removeObject(forKey: collapseDuplicatesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
        UserDefaults.standard.removeObject(forKey: sessionGroupingKey)
        UserDefaults.standard.removeObject(forKey: collapseDuplicatesKey)
        super.tearDown()
    }

    func testMultiAgentBubbleDefaultsOn() {
        let settings = BubbleSettings()

        XCTAssertTrue(settings.multiAgentBubbleEnabled)
    }

    func testMultiAgentBubblePersists() {
        let settings = BubbleSettings()

        settings.multiAgentBubbleEnabled = true

        XCTAssertTrue(BubbleSettings().multiAgentBubbleEnabled)
    }

    func testSessionGroupingDefaultsToByKind() {
        XCTAssertEqual(BubbleSettings().sessionGrouping, .byKind)
    }

    func testSessionGroupingPersists() {
        let settings = BubbleSettings()
        settings.sessionGrouping = .allSessions
        XCTAssertEqual(BubbleSettings().sessionGrouping, .allSessions)
    }

    func testSessionGroupingMigratesFromLegacyCollapseOff() {
        UserDefaults.standard.set(false, forKey: collapseDuplicatesKey)
        XCTAssertEqual(BubbleSettings().sessionGrouping, .allSessions)
    }
}
