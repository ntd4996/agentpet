import XCTest
import AgentPetCore
@testable import agentpet

@MainActor
final class KeyedSerialQueueTests: XCTestCase {
    /// Lets a test hold a job open until it says so.
    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func settle() async {
        // Jobs are MainActor tasks: a few yields let every runnable one finish.
        for _ in 0..<20 { await Task.yield() }
    }

    func testSameKeyRunsInSubmissionOrder() async {
        let q = KeyedSerialQueue()
        let gate = Gate()
        var order: [Int] = []
        q.enqueue("s") { await gate.wait(); order.append(1) }
        q.enqueue("s") { order.append(2) }
        q.enqueue("s") { order.append(3) }
        await settle()
        XCTAssertEqual(order, [], "later jobs must wait for the first")
        gate.open()
        await settle()
        XCTAssertEqual(order, [1, 2, 3])
    }

    func testDifferentKeysDoNotWaitOnEachOther() async {
        let q = KeyedSerialQueue()
        let gate = Gate()
        var ran: [String] = []
        q.enqueue("slow") { await gate.wait(); ran.append("slow") }
        q.enqueue("other") { ran.append("other") }
        await settle()
        XCTAssertEqual(ran, ["other"])
        gate.open()
        await settle()
        XCTAssertEqual(ran, ["other", "slow"])
    }

    func testFinishedKeysAreDropped() async {
        let q = KeyedSerialQueue()
        for i in 0..<50 { q.enqueue("s\(i)") {} }
        q.enqueue("s0") {}
        await settle()
        XCTAssertEqual(q.pendingKeys, 0)
    }

    /// Session A has a slow scan queued first. Session B starts, spends tokens in
    /// its first turn, and ends the turn while A is still scanning. With one
    /// global chain B's baseline was taken after the turn and the turn fed 0;
    /// per session, B's baseline is taken as soon as B's own jobs run.
    func testSlowScanOfOneSessionDoesNotSwallowAnotherSessionsFirstTurn() async {
        let q = KeyedSerialQueue()
        let gate = Gate()
        var tracker = JcodeUsageTracker()
        var disk = ["A": 5000, "B": 1000]
        var fed = 0

        q.enqueue("A") { await gate.wait(); tracker.baseline(sessionId: "A", total: disk["A"]!) }
        q.enqueue("B") { tracker.baseline(sessionId: "B", total: disk["B"]!) }   // B.session_start
        await settle()
        disk["B"] = 1100                                                          // B's first turn
        q.enqueue("B") { fed += tracker.delta(sessionId: "B", total: disk["B"]!) } // B.turn_end
        await settle()
        gate.open()
        await settle()
        XCTAssertEqual(fed, 100)
    }

    /// forget runs behind the session's pending reads, so a read in flight cannot
    /// put the entry back afterwards.
    func testForgetQueuedBehindPendingReadLeavesNoEntry() async {
        let q = KeyedSerialQueue()
        let gate = Gate()
        var tracker = JcodeUsageTracker()
        q.enqueue("s") { await gate.wait(); _ = tracker.delta(sessionId: "s", total: 10) }
        q.enqueue("s") { tracker.forget(sessionId: "s") }                         // session_end
        await settle()
        gate.open()
        await settle()
        XCTAssertFalse(tracker.isTracking("s"))
    }
}
