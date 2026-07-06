import XCTest
@testable import AgentPetCore

final class AgentEventTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testApprovalFieldsDefaultToNil() {
        let event = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "Stop", timestamp: now)
        XCTAssertNil(event.approvalRequestId)
        XCTAssertNil(event.toolName)
        XCTAssertNil(event.toolSummary)
    }

    func testCodableRoundTripPreservesApprovalFields() throws {
        let event = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "PreToolUse",
            approvalRequestId: "req-1", toolName: "Bash", toolSummary: "npm test",
            timestamp: now
        )
        let data = try EventCoding.encoder.encode(event)
        let decoded = try EventCoding.decoder.decode(AgentEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.approvalRequestId, "req-1")
        XCTAssertEqual(decoded.toolName, "Bash")
        XCTAssertEqual(decoded.toolSummary, "npm test")
    }

    func testCodableRoundTripWithNilApprovalFields() throws {
        let event = AgentEvent(sessionId: "s1", agentKind: .claude, eventName: "Stop", timestamp: now)
        let data = try EventCoding.encoder.encode(event)
        let decoded = try EventCoding.decoder.decode(AgentEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertNil(decoded.approvalRequestId)
        XCTAssertNil(decoded.toolName)
        XCTAssertNil(decoded.toolSummary)
    }
}
