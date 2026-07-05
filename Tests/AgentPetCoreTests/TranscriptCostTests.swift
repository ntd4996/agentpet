import XCTest
@testable import AgentPetCore

final class TranscriptCostTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "agentpet-cost-\(UUID().uuidString).jsonl"
        TranscriptReader.clearCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    private func append(_ lines: [String]) {
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func assistantLine(
        input: Int,
        output: Int,
        cacheCreate: Int = 0,
        cacheRead: Int = 0,
        model: String = "claude-sonnet-4-6-20260115"
    ) -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead)},"content":[{"type":"text","text":"hi"}]}}"#
    }

    func testDeltaMatchesHandComputedFormula() {
        append([
            assistantLine(input: 1_000, output: 250, cacheCreate: 500, cacheRead: 2_000, model: "claude-sonnet-4-6-20260115"),
        ])
        let delta = TranscriptReader.newUsageDelta(at: path)

        // sonnet: input $3.00/M, output $15.00/M, cache-create = inputRate*1.25, cache-read = inputRate*0.1
        let expectedCost = (1_000.0 * 3.00
            + 250.0 * 15.00
            + 500.0 * 3.00 * 1.25
            + 2_000.0 * 3.00 * 0.1) / 1_000_000.0

        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.tokens, 1_250)
        XCTAssertEqual(delta?.costUSD ?? -1, expectedCost, accuracy: 0.0000001)
    }

    func testSecondCallWithNoNewLinesReturnsZeroDelta() {
        append([assistantLine(input: 500, output: 100)])
        _ = TranscriptReader.newUsageDelta(at: path)

        let secondDelta = TranscriptReader.newUsageDelta(at: path)

        XCTAssertEqual(secondDelta, TranscriptReader.UsageDelta(tokens: 0, costUSD: 0))
    }

    func testSumsTokensAndCostAcrossLinesWithDifferentModels() {
        append([
            assistantLine(input: 1_000, output: 500, model: "claude-opus-4-1"),
            assistantLine(input: 2_000, output: 1_000, model: "claude-sonnet-4-6-20260115"),
        ])
        let delta = TranscriptReader.newUsageDelta(at: path)

        let opusCost = (1_000.0 * 15.00 + 500.0 * 75.00) / 1_000_000.0
        let sonnetCost = (2_000.0 * 3.00 + 1_000.0 * 15.00) / 1_000_000.0
        let expectedCost = opusCost + sonnetCost
        let expectedTokens = (1_000 + 500) + (2_000 + 1_000)

        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.tokens, expectedTokens)
        XCTAssertEqual(delta?.costUSD ?? -1, expectedCost, accuracy: 0.0000001)
    }

    func testNewUsageDeltaForUnreadPathReturnsNil() {
        let neverSeenPath = "/some/path/never/read/before-\(UUID().uuidString).jsonl"
        XCTAssertNil(TranscriptReader.newUsageDelta(at: neverSeenPath))
    }

    func testClearCacheResetsByteOffsetSoDeltaIsRecomputedFromStart() {
        append([assistantLine(input: 1_000, output: 250, model: "claude-sonnet-4-6-20260115")])
        let firstDelta = TranscriptReader.newUsageDelta(at: path)

        XCTAssertNotNil(firstDelta)
        XCTAssertNotEqual(firstDelta?.tokens, 0)
        XCTAssertNotEqual(firstDelta?.costUSD, 0)

        TranscriptReader.clearCache()

        let secondDelta = TranscriptReader.newUsageDelta(at: path)

        XCTAssertEqual(secondDelta?.tokens, firstDelta?.tokens)
        XCTAssertEqual(secondDelta?.costUSD ?? -1, firstDelta?.costUSD ?? -2, accuracy: 0.0000001)
    }
}
