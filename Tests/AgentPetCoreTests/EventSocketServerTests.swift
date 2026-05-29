import XCTest
@testable import AgentPetCore

final class EventSocketServerTests: XCTestCase {
    func testReceivesEventOverSocket() throws {
        let path = "/tmp/agentpet-\(UUID().uuidString).sock"
        let server = EventSocketServer(path: path)
        defer { server.stop() }

        let exp = expectation(description: "event delivered")
        let box = Box()
        try server.start { event in
            box.value = event
            exp.fulfill()
        }

        let event = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "Stop",
            project: "/p", message: "done", timestamp: Date(timeIntervalSince1970: 123)
        )
        var data = try EventCoding.encoder.encode(event)
        data.append(0x0A)
        try sendToUnixSocket(path: path, data: data)

        wait(for: [exp], timeout: 2)
        XCTAssertEqual(box.value, event)
    }

    func testDrainQueueEmitsAndRemovesFiles() throws {
        let dir = NSTemporaryDirectory() + "agentpet-q-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let event = AgentEvent(
            sessionId: "s2", agentKind: .claude, eventName: "Notification",
            timestamp: Date(timeIntervalSince1970: 5)
        )
        var data = try EventCoding.encoder.encode(event)
        data.append(0x0A)
        let file = dir + "/0001.json"
        try data.write(to: URL(fileURLWithPath: file))

        var received: [AgentEvent] = []
        EventSocketServer.drainQueue(directory: dir) { received.append($0) }

        XCTAssertEqual(received, [event])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file), "queue file removed after drain")
    }

    // MARK: - Helpers

    private final class Box: @unchecked Sendable {
        var value: AgentEvent?
    }

    private func sendToUnixSocket(path: String, data: Data) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        XCTAssertEqual(connected, 0, "connect failed errno=\(errno)")
        data.withUnsafeBytes { raw in
            let written = write(fd, raw.baseAddress, raw.count)
            XCTAssertEqual(written, raw.count)
        }
    }
}
