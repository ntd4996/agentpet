import XCTest
@testable import AgentPetCore

final class ModelPricingTests: XCTestCase {

    func testSonnetPricingWithAllFourTokenKinds() {
        // sonnet: input $3.00/M, output $15.00/M
        let cost = ModelPricing.costUSD(
            model: "claude-sonnet-4-6-20260115",
            inputTokens: 1_000,
            outputTokens: 250,
            cacheCreateTokens: 500,
            cacheReadTokens: 2_000
        )
        let inputRate = 3.00
        let outputRate = 15.00
        let expected = (1_000 * inputRate
            + 250 * outputRate
            + 500 * inputRate * 1.25
            + 2_000 * inputRate * 0.1) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }

    func testOpusPricing() {
        let cost = ModelPricing.costUSD(
            model: "claude-opus-4-1",
            inputTokens: 1_000,
            outputTokens: 500,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        let inputRate = 15.00
        let outputRate = 75.00
        let expected = (1_000 * inputRate + 500 * outputRate) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }

    func testHaikuPricing() {
        let cost = ModelPricing.costUSD(
            model: "claude-haiku-3-5",
            inputTokens: 2_000,
            outputTokens: 1_000,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        let inputRate = 1.00
        let outputRate = 5.00
        let expected = (2_000 * inputRate + 1_000 * outputRate) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }

    func testUnknownModelFallsBackToSonnetRate() {
        let cost = ModelPricing.costUSD(
            model: "some-unrecognized-model-xyz",
            inputTokens: 1_000,
            outputTokens: 1_000,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        let expected = (1_000 * 3.00 + 1_000 * 15.00) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }

    func testNilModelFallsBackToSonnetRate() {
        let cost = ModelPricing.costUSD(
            model: nil,
            inputTokens: 1_000,
            outputTokens: 1_000,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        let expected = (1_000 * 3.00 + 1_000 * 15.00) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }

    func testAllZeroTokensReturnsZero() {
        let cost = ModelPricing.costUSD(
            model: "claude-sonnet-4-6-20260115",
            inputTokens: 0,
            outputTokens: 0,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        XCTAssertEqual(cost, 0, accuracy: 0.0000001)
    }

    func testFullModelIdMatchesSonnetTierViaSubstring() {
        let cost = ModelPricing.costUSD(
            model: "claude-sonnet-4-6-20260115",
            inputTokens: 1_000,
            outputTokens: 1_000,
            cacheCreateTokens: 0,
            cacheReadTokens: 0
        )
        let expected = (1_000 * 3.00 + 1_000 * 15.00) / 1_000_000
        XCTAssertEqual(cost, expected, accuracy: 0.0000001)
    }
}
