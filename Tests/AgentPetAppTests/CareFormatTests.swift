import XCTest
import AgentPetCore
@testable import agentpet

final class CareFormatTests: XCTestCase {
    func testTokensAreCompactAtEachMagnitude() {
        XCTAssertEqual(CareFormat.tokens(0), "0")
        XCTAssertEqual(CareFormat.tokens(999), "999")
        XCTAssertEqual(CareFormat.tokens(1_000), "1k")
        XCTAssertEqual(CareFormat.tokens(12_345), "12k")
        XCTAssertEqual(CareFormat.tokens(1_000_000), "1.0M")
        XCTAssertEqual(CareFormat.tokens(2_540_000), "2.5M")
    }

    func testHungerHasADistinctLabelForEveryCase() {
        let labels = PetHunger.allCases.map(CareFormat.hunger)
        XCTAssertEqual(labels, ["Full", "Satisfied", "Peckish", "Hungry", "Starving"])
        XCTAssertEqual(Set(labels).count, PetHunger.allCases.count)
    }

    func testPlainKeepsEveryDigit() {
        XCTAssertEqual(CareFormat.plain(0), "0")
        let digits = CareFormat.plain(1_234_567).filter(\.isNumber)
        XCTAssertEqual(digits, "1234567")
    }
}
