import XCTest
@testable import AgentPetCore

final class RemoteEventServerTests: XCTestCase {
    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    private let testPort: UInt16 = 38399
    private let testToken = "test_secret_token_12345"

    func testHealthEndpoint() async throws {
        let token = testToken
        let server = RemoteEventServer(port: testPort, authTokenProvider: { token })
        try server.start { _ in }
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(testPort)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Not an HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.contains("\"status\":\"ok\""))
    }

    func testSetupScriptEndpoint() async throws {
        let token = testToken
        let server = RemoteEventServer(
            port: testPort,
            authTokenProvider: { token },
            setupScriptProvider: { "echo 'CUSTOM_SETUP'" }
        )
        try server.start { _ in }
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(testPort)/setup.sh")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Not an HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.contains("CUSTOM_SETUP"))
    }

    func testPostEventsRejectsInvalidToken() async throws {
        let token = testToken
        let server = RemoteEventServer(port: testPort, authTokenProvider: { token })
        try server.start { _ in }
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(testPort)/api/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer wrong_token", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"event":"working"}"#.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Not an HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 401)
    }

    func testPostEventsAcceptsValidTokenAndDeliversEvent() async throws {
        let box = Box<AgentEvent>()
        let expectation = expectation(description: "Event delivered")
        let token = testToken

        let server = RemoteEventServer(port: testPort, authTokenProvider: { token })
        try server.start { event in
            box.value = event
            expectation.fulfill()
        }
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(testPort)/api/events?agent=claude&host=vps-ubuntu-01")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let json = """
        {
          "sessionId": "s-remote-100",
          "agent": "claude",
          "event": "SessionStart",
          "project": "agentpet-remote",
          "message": "Starting turn on remote server"
        }
        """
        request.httpBody = Data(json.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Not an HTTP response")
            return
        }
        XCTAssertEqual(httpResponse.statusCode, 200)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.contains("\"ok\":true"))

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(box.value)
        XCTAssertEqual(box.value?.sessionId, "s-remote-100")
        XCTAssertEqual(box.value?.agentKind, .claude)
        XCTAssertEqual(box.value?.host, "vps-ubuntu-01")
        XCTAssertEqual(box.value?.project, "agentpet-remote")
    }

    func testSessionStoreAppliesRemoteEvent() {
        let store = SessionStore()
        let now = Date()
        let event = AgentEvent(
            sessionId: "rem-1",
            agentKind: .claude,
            eventName: "SessionStart",
            project: "vps-proj",
            message: "Running build on server",
            host: "aws-prod-1",
            timestamp: now
        )

        let session = store.apply(event, now: now)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.host, "aws-prod-1")
        XCTAssertEqual(session?.source, .remote)
        XCTAssertEqual(session?.groupKey, "claude@aws-prod-1")

        // Sticky host preservation on subsequent event
        let nextEvent = AgentEvent(
            sessionId: "rem-1",
            agentKind: .claude,
            eventName: "Stop",
            timestamp: now.addingTimeInterval(10)
        )
        let updated = store.apply(nextEvent, now: now.addingTimeInterval(10))
        XCTAssertEqual(updated?.host, "aws-prod-1")
        XCTAssertEqual(updated?.source, .remote)
    }
}
