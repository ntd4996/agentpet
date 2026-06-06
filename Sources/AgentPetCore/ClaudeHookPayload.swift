import Foundation

/// The JSON Claude Code writes to a hook's stdin. Only the fields AgentPet
/// needs are decoded; the rest are ignored.
public struct ClaudeHookPayload: Decodable, Equatable {
    public let sessionId: String?
    public let cwd: String?
    public let hookEventName: String?
    public let message: String?
    public let toolName: String?
    /// Absolute path to the conversation's JSONL transcript file.
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case message
        case toolName = "tool_name"
        case transcriptPath = "transcript_path"
    }

    public static func decode(from data: Data) -> ClaudeHookPayload? {
        try? JSONDecoder().decode(ClaudeHookPayload.self, from: data)
    }

    /// Builds an `AgentEvent` from the payload, or `nil` if the essential
    /// fields (session id and event name) are missing.
    public func makeEvent(now: Date, kind: AgentKind = .claude) -> AgentEvent? {
        guard let sessionId, let hookEventName else { return nil }
        // Surface the running tool name when there's no explicit message.
        let context = message ?? toolName.map { "Using \($0)" }
        return AgentEvent(
            sessionId: sessionId, agentKind: kind, eventName: hookEventName,
            project: cwd, message: context, transcriptPath: transcriptPath, timestamp: now
        )
    }
}
