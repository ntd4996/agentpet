import XCTest
@testable import AgentPetCore

/// Token usage from jcode session files (`~/.jcode/sessions/<id>.json`).
/// Shapes copied from real sessions (2026-10-04).
final class JcodeUsageTests: XCTestCase {

    private func session(_ usages: [String]) -> Data {
        let messages = usages.map { u in
            #"{"role":"user","content":[{"type":"text","text":"say \"token_usage\": hi"}]},"#
                + #"{"role":"assistant","content":[],"token_usage":\#(u)}"#
        }
        return Data(#"{"id":"session_x_1","messages":[\#(messages.joined(separator: ","))],"compaction":null}"#.utf8)
    }

    /// Anthropic: input_tokens is already uncached, prompt = input + both cache fields.
    func testClaudeUsageCountsUncachedInputPlusOutput() {
        let data = session([
            #"{"prompt_tokens":88127,"input_tokens":482,"output_tokens":705,"cache_read_input_tokens":86688,"cache_creation_input_tokens":957}"#,
        ])
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: data), 482 + 705)
    }

    /// OpenAI: input_tokens includes the cached part, so it must not be added as is.
    func testOpenAIUsageSubtractsCachedPrompt() {
        let data = session([
            #"{"prompt_tokens":109406,"input_tokens":109406,"output_tokens":275,"cache_read_input_tokens":108032,"cache_creation_input_tokens":0}"#,
        ])
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: data), 109406 - 108032 + 275)
    }

    /// Sums every message, ignores the key quoted inside text, tolerates a null
    /// cache field and a usage without prompt_tokens.
    func testSumsAllMessagesAndSkipsQuotedKey() {
        let data = session([
            #"{"prompt_tokens":100,"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":90,"cache_creation_input_tokens":0}"#,
            #"{"prompt_tokens":50,"input_tokens":50,"output_tokens":1,"cache_read_input_tokens":null,"cache_creation_input_tokens":null}"#,
            #"{"input_tokens":7,"output_tokens":3}"#,
        ])
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: data), (10 + 5) + (50 + 1) + (7 + 3))
    }

    func testPrettyPrintedKeyIsFound() {
        let data = Data(#"{"messages":[{"token_usage": {"input_tokens": 4, "output_tokens": 2}}]}"#.utf8)
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: data), 6)
    }

    func testNotASessionGivesZero() {
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: Data("not json".utf8)), 0)
        XCTAssertEqual(JcodeUsage.totalTokens(sessionData: Data(#"{"token_usage":{"input_tokens":3"#.utf8)), 0)
    }

    func testSessionPathRejectsTraversal() {
        XCTAssertEqual(JcodeUsage.sessionPath(sessionId: "session_x_1", home: "/h"), "/h/.jcode/sessions/session_x_1.json")
        XCTAssertNil(JcodeUsage.sessionPath(sessionId: "../auth", home: "/h"))
        XCTAssertNil(JcodeUsage.sessionPath(sessionId: "a/b", home: "/h"))
        XCTAssertNil(JcodeUsage.sessionPath(sessionId: "", home: "/h"))
        XCTAssertEqual(JcodeUsage.journalPath(snapshotPath: "/h/.jcode/sessions/session_x_1.json"),
                       "/h/.jcode/sessions/session_x_1.journal.jsonl")
    }

    /// jcode appends new messages to `<id>.journal.jsonl` and only rewrites the
    /// snapshot every 512 KB, so the turn's tokens are usually in the journal.
    func testTotalAddsJournalToSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = dir.appendingPathComponent("session_x_1.json")
        try session([#"{"input_tokens":10,"output_tokens":5}"#]).write(to: snapshot)
        XCTAssertEqual(JcodeUsage.totalTokens(snapshotPath: snapshot.path), 15)   // no journal yet

        let journal = dir.appendingPathComponent("session_x_1.journal.jsonl")
        let lines = [
            #"{"meta":{"title":"t"},"append_messages":[{"role":"assistant","content":[],"token_usage":{"input_tokens":3,"output_tokens":2}}]}"#,
            #"{"meta":{"title":"t"},"append_messages":[{"role":"user","content":[]}]}"#,
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: journal)
        XCTAssertEqual(JcodeUsage.totalTokens(snapshotPath: snapshot.path), 15 + 5)
        XCTAssertEqual(JcodeUsage.totalTokens(snapshotPath: dir.appendingPathComponent("missing.json").path), 0)
    }

    // MARK: tracker

    func testTurnFeedsOnlyItsOwnTokens() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 4_500_000)   // turn_start of a long session
        XCTAssertEqual(t.delta(sessionId: "s", total: 4_512_000), 12_000)
        t.baseline(sessionId: "s", total: 4_512_000)   // next turn_start: already tracked
        XCTAssertEqual(t.delta(sessionId: "s", total: 4_520_000), 8_000)
    }

    /// AgentPet started mid-turn: the first turn_end only sets the baseline.
    func testFirstSightingFeedsNothing() {
        var t = JcodeUsageTracker()
        XCTAssertEqual(t.delta(sessionId: "s", total: 4_500_000), 0)
        XCTAssertEqual(t.delta(sessionId: "s", total: 4_501_000), 1_000)
    }

    /// Compaction drops old messages: no negative feed, new baseline instead.
    func testShrinkingTotalMovesBaseline() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 900)
        XCTAssertEqual(t.delta(sessionId: "s", total: 300), 0)
        XCTAssertEqual(t.delta(sessionId: "s", total: 350), 50)
    }

    /// Sessions that never send session_end must not pile up forever.
    func testTrackerKeepsOnlyRecentSessions() {
        var t = JcodeUsageTracker()
        let cap = JcodeUsageTracker.maxSessions
        for i in 0..<(cap + 50) { t.baseline(sessionId: "s\(i)", total: 10) }
        XCTAssertEqual(t.count, cap)
        XCTAssertFalse(t.isTracking("s0"))
        XCTAssertTrue(t.isTracking("s\(cap + 49)"))
        // A dropped session just re-baselines: nothing is fed.
        XCTAssertEqual(t.delta(sessionId: "s0", total: 999), 0)
    }

    func testBaselineDoesNotOverwriteAndForgetResets() {
        var t = JcodeUsageTracker()
        t.baseline(sessionId: "s", total: 100)
        t.baseline(sessionId: "s", total: 999)
        XCTAssertEqual(t.delta(sessionId: "s", total: 150), 50)
        t.forget(sessionId: "s")
        XCTAssertFalse(t.isTracking("s"))
        XCTAssertEqual(t.delta(sessionId: "s", total: 5_000), 0)
    }
}
