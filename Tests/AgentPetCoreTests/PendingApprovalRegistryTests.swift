import XCTest
@testable import AgentPetCore

final class PendingApprovalRegistryTests: XCTestCase {
    /// Creates a connected pipe pair, returning (readFD, writeFD). The caller
    /// owns the read end; `PendingApprovalRegistry` owns/closes the write end.
    private func makePipe() -> (readFD: Int32, writeFD: Int32) {
        var fds: [Int32] = [0, 0]
        fds.withUnsafeMutableBufferPointer { pipe($0.baseAddress) }
        return (fds[0], fds[1])
    }

    private func readAll(_ fd: Int32) -> String {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testResolveWritesDecisionJSONAndClosesFD() {
        let registry = PendingApprovalRegistry()
        let (readFD, writeFD) = makePipe()
        registry.register(requestId: "req-1", fd: writeFD)

        let resolved = registry.resolve(requestId: "req-1", decision: .allow)
        XCTAssertTrue(resolved)

        let output = readAll(readFD)
        XCTAssertEqual(output, "{\"decision\":\"allow\"}\n")
    }

    func testResolveIsIdempotentAndReturnsFalseOnSecondCall() {
        let registry = PendingApprovalRegistry()
        let (readFD, writeFD) = makePipe()
        registry.register(requestId: "req-1", fd: writeFD)

        XCTAssertTrue(registry.resolve(requestId: "req-1", decision: .deny))
        XCTAssertFalse(registry.resolve(requestId: "req-1", decision: .allow),
                        "second resolve for the same requestId must be a no-op")

        // Only one write/close should have happened; reading to EOF must not hang or crash.
        _ = readAll(readFD)
    }

    func testResolveUnknownRequestIdReturnsFalse() {
        let registry = PendingApprovalRegistry()
        XCTAssertFalse(registry.resolve(requestId: "never-registered", decision: .ask))
    }

    func testUnresolvedRequestAutoResolvesToAskAfterTimeout() {
        let registry = PendingApprovalRegistry()
        let (readFD, writeFD) = makePipe()
        let expectation = expectation(description: "timeout auto-resolve")

        registry.register(requestId: "req-timeout", fd: writeFD, timeout: 0.2)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        let output = readAll(readFD)
        XCTAssertEqual(output, "{\"decision\":\"ask\"}\n", "no manual resolve before timeout -> auto .ask")
    }

    func testManualResolveBeforeTimeoutPreventsAutoAskOverwrite() {
        let registry = PendingApprovalRegistry()
        let (readFD, writeFD) = makePipe()

        registry.register(requestId: "req-early", fd: writeFD, timeout: 0.2)
        XCTAssertTrue(registry.resolve(requestId: "req-early", decision: .allow))

        // Wait past the timeout window; the auto-timeout must not fire again
        // (fd is already closed) and must not crash.
        let expectation = expectation(description: "wait past timeout window")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        let output = readAll(readFD)
        XCTAssertEqual(output, "{\"decision\":\"allow\"}\n")
    }

    func testResolveAfterPeerClosedDoesNotCrash() {
        let registry = PendingApprovalRegistry()
        var fds: [Int32] = [0, 0]
        fds.withUnsafeMutableBufferPointer { _ = socketpair(AF_UNIX, SOCK_STREAM, 0, $0.baseAddress) }

        registry.register(requestId: "req-gone", fd: fds[1])
        close(fds[0])   // peer (the CLI side) goes away before the decision

        // Without SO_NOSIGPIPE this write raises SIGPIPE and kills the process.
        XCTAssertTrue(registry.resolve(requestId: "req-gone", decision: .ask),
                      "resolve still consumes the registration even when the write fails")
        XCTAssertFalse(registry.resolve(requestId: "req-gone", decision: .ask))
    }
}
