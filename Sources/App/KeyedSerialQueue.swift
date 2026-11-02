import Foundation

/// Runs async jobs one after another *per key*. Jobs for the same key keep
/// their submission order, jobs for different keys never wait on each other, so
/// one session's slow file scan cannot hold up another session's baseline.
@MainActor
final class KeyedSerialQueue {
    private var tails: [String: (id: Int, task: Task<Void, Never>)] = [:]
    private var counter = 0

    func enqueue(_ key: String, _ job: @escaping @MainActor () async -> Void) {
        let previous = tails[key]?.task
        counter += 1
        let id = counter
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await job()
            // Drop the entry once the newest job for this key is done, so the
            // dictionary only holds keys with work in flight.
            if self?.tails[key]?.id == id { self?.tails[key] = nil }
        }
        tails[key] = (id, task)
    }

    /// Keys with work still queued or running.
    var pendingKeys: Int { tails.count }
}
