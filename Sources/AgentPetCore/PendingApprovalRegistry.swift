import Foundation

/// The user's decision for a gated tool call, written back to the CLI hook.
public enum ApprovalDecision: String, Codable, Sendable {
    case allow, deny, ask
}

/// Builds the Claude Code hook JSON that carries a `PreToolUse` permission decision.
public enum ApprovalHookResponse {
    public static func json(for decision: ApprovalDecision) -> String {
        "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"\(decision.rawValue)\"}}"
    }
}

/// Tracks CLI hook connections (file descriptors) awaiting an approval
/// decision, keyed by request id, and writes the decision back when resolved.

// Known limitation (a): a timeout only resolves the CLI-side fd; it does not
// notify `SessionStore`, so the UI's pending approval clears on the next event.

// Known limitation (b): a decision after the timeout fires returns `false`
// from `resolve`, but the UI still clears — the timeout already decided.
public final class PendingApprovalRegistry: @unchecked Sendable {
    public static let shared = PendingApprovalRegistry()

    private let queue = DispatchQueue(label: "com.agentpet.pendingApprovalRegistry")
    private var fds: [String: Int32] = [:]

    public init() {}

    /// Registers `fd` for `requestId`, auto-resolving to `.ask` after
    /// `timeout` seconds if no manual `resolve` call arrives first.
    public func register(requestId: String, fd: Int32, timeout: TimeInterval = 25) {
        queue.async { self.fds[requestId] = fd }
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            _resolveLocked(requestId: requestId, decision: .ask)
        }
    }

    /// Writes the decision to the registered fd and closes it. Returns
    /// `false` (no-op) if `requestId` isn't registered (already resolved).
    @discardableResult
    public func resolve(requestId: String, decision: ApprovalDecision) -> Bool {
        queue.sync { _resolveLocked(requestId: requestId, decision: decision) }
    }

    // Must only be called on `queue`.
    @discardableResult
    private func _resolveLocked(requestId: String, decision: ApprovalDecision) -> Bool {
        guard let fd = fds.removeValue(forKey: requestId) else { return false }
        let data = Data("{\"decision\":\"\(decision.rawValue)\"}\n".utf8)
        _ = EventSender.writeAll(data, fd: fd)
        close(fd)
        return true
    }
}
