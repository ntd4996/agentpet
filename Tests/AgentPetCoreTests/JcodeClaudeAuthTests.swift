import XCTest
@testable import AgentPetCore

final class JcodeClaudeAuthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var futureMs: Double { (now.timeIntervalSince1970 + 3600) * 1000 }
    private var pastMs: Double { (now.timeIntervalSince1970 - 60) * 1000 }

    private func auth(_ accounts: [[String: Any]], active: String?) -> Data {
        var json: [String: Any] = ["anthropic_accounts": accounts]
        if let active { json["active_anthropic_account"] = active }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testActiveAccountWins() {
        let data = auth([
            ["label": "a", "access": "tok-a", "expires": futureMs],
            ["label": "b", "access": "tok-b", "expires": futureMs],
        ], active: "b")
        XCTAssertEqual(JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now), "tok-b")
    }

    func testFallsBackToFirstAccountWhenActiveUnknown() {
        let data = auth([["label": "a", "access": "tok-a", "expires": futureMs]], active: "gone")
        XCTAssertEqual(JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now), "tok-a")
        let noActive = auth([["label": "a", "access": "tok-a", "expires": futureMs]], active: nil)
        XCTAssertEqual(JcodeClaudeAuth.accessToken(fromAuthJSON: noActive, now: now), "tok-a")
    }

    func testExpiredTokenIsSkipped() {
        let data = auth([["label": "a", "access": "tok-a", "expires": pastMs]], active: "a")
        XCTAssertNil(JcodeClaudeAuth.accessToken(fromAuthJSON: data, now: now))
    }

    func testMalformedOrEmptyIsNil() {
        XCTAssertNil(JcodeClaudeAuth.accessToken(fromAuthJSON: Data("not json".utf8), now: now))
        XCTAssertNil(JcodeClaudeAuth.accessToken(fromAuthJSON: Data("{}".utf8), now: now))
        XCTAssertNil(JcodeClaudeAuth.accessToken(fromAuthJSON: auth([], active: nil), now: now))
        let blank = auth([["label": "a", "access": "", "expires": futureMs]], active: "a")
        XCTAssertNil(JcodeClaudeAuth.accessToken(fromAuthJSON: blank, now: now))
    }

    func testExpiryUnits() {
        let t = now.timeIntervalSince1970
        XCTAssertTrue(OAuthExpiry.isExpired(NSNumber(value: (t - 1) * 1000), now: now), "ms, past")
        XCTAssertFalse(OAuthExpiry.isExpired(NSNumber(value: (t + 60) * 1000), now: now), "ms, future")
        XCTAssertTrue(OAuthExpiry.isExpired(NSNumber(value: t - 1), now: now), "seconds, past")
        XCTAssertFalse(OAuthExpiry.isExpired(NSNumber(value: t + 60), now: now), "seconds, future")
        XCTAssertFalse(OAuthExpiry.isExpired(nil, now: now), "unknown expiry: let the API decide")
        XCTAssertFalse(OAuthExpiry.isExpired("soon", now: now))
    }
}
