import XCTest
@testable import agentpet

/// Reset times from real provider payloads (shapes captured 2026-10-02).
/// Bodies go through JSONSerialization like the live probes, so numbers are
/// NSNumber exactly as in production.
final class UsageResetParsingTests: XCTestCase {

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    private func epoch(_ s: String) -> TimeInterval {
        ISO8601DateFormatter().date(from: s)!.timeIntervalSince1970
    }

    /// `api/oauth/usage` sends microsecond ISO timestamps with a +00:00 offset.
    func testClaudeResetParsesFractionalSeconds() throws {
        let body = try json("""
        {"five_hour": {"utilization": 37.0, "resets_at": "2026-10-02T23:59:59.536032+00:00"},
         "seven_day": {"utilization": 79.0, "resets_at": "2026-10-05T03:59:59.536051+00:00"}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.claudeProvider(from: body))
        XCTAssertEqual(p.windowLabel, "Weekly")
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970,
                       epoch("2026-10-05T03:59:59Z"), accuracy: 1)
    }

    /// `wham/usage` gives `reset_after_seconds` and an epoch `reset_at`.
    func testCodexResetFromRealKeys() throws {
        let body = try json("""
        {"rate_limit": {
          "primary_window": {"used_percent": 16, "limit_window_seconds": 18000,
                             "reset_after_seconds": 15151, "reset_at": 1790997688},
          "secondary_window": {"used_percent": 3, "limit_window_seconds": 604800,
                               "reset_after_seconds": 601951, "reset_at": 1791584488}}}
        """)
        let now = Date(timeIntervalSince1970: 1_790_982_537)
        let p = try XCTUnwrap(NativeUsageProbe.codexProvider(from: body, now: now) { _ in nil })
        XCTAssertEqual(p.windowLabel, "Session")
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970, 1_790_997_688, accuracy: 1)
    }

    /// Without an absolute `reset_at`, the relative seconds count from `now`.
    func testCodexResetFallsBackToRelativeSeconds() throws {
        let body = try json("""
        {"rate_limit": {"primary_window": {"used_percent": 40, "reset_after_seconds": 3600}}}
        """)
        let now = Date(timeIntervalSince1970: 1_790_982_537)
        let p = try XCTUnwrap(NativeUsageProbe.codexProvider(from: body, now: now) { _ in nil })
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970, 1_790_986_137, accuracy: 1)
    }

    /// OpenUsage's local API sends millisecond ISO timestamps (`.000Z`).
    func testOpenUsageResetParsesMilliseconds() throws {
        let body = try json("""
        {"providerId": "antigravity", "lines": [
          {"type": "progress", "label": "Session", "used": 0, "limit": 100,
           "resetsAt": "2026-10-03T04:00:08.000Z"},
          {"type": "progress", "label": "Weekly", "used": 9, "limit": 100,
           "resetsAt": "2026-10-07T02:26:05.000Z"}]}
        """)
        let p = try XCTUnwrap(OpenUsageClient.provider(from: body))
        XCTAssertEqual(p.windowLabel, "Weekly")
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970,
                       epoch("2026-10-07T02:26:05Z"), accuracy: 1)
    }

    /// Whole-second timestamps must keep working.
    func testWholeSecondTimestampsStillParse() throws {
        let body = try json("""
        {"seven_day": {"utilization": 50.0, "resets_at": "2026-10-05T04:00:00Z"}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.claudeProvider(from: body))
        XCTAssertEqual(try XCTUnwrap(p.resetsAt).timeIntervalSince1970,
                       epoch("2026-10-05T04:00:00Z"), accuracy: 1)
    }
}
