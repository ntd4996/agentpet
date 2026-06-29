import Foundation

/// A single state-change report from an agent, sent by the CLI helper to the
/// daemon. `eventName` is the agent-native event (e.g. Claude Code's "Stop");
/// `StateMapper` turns it into an `AgentState`.
public struct AgentEvent: Codable, Sendable, Equatable {
    public var sessionId: String
    public var agentKind: AgentKind
    public var eventName: String
    public var project: String?
    public var message: String?
    /// Display name of the LLM model in use (e.g. "Sonnet 4.6"), if the hook
    /// payload included one. `nil` when the agent doesn't report it.
    public var model: String?
    /// Path to the agent's conversation transcript file (e.g. Claude Code JSONL).
    /// Used to derive a human-readable title for the session.
    public var transcriptPath: String?
    /// Subagent identifier from a `SubagentStop` event (e.g. `"agent-abc123"`).
    public var subagentId: String?
    public var timestamp: Date

    public init(
        sessionId: String,
        agentKind: AgentKind,
        eventName: String,
        project: String? = nil,
        message: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil,
        subagentId: String? = nil,
        timestamp: Date
    ) {
        self.sessionId = sessionId
        self.agentKind = agentKind
        self.eventName = eventName
        self.project = project
        self.message = message
        self.model = model
        self.transcriptPath = transcriptPath
        self.subagentId = subagentId
        self.timestamp = timestamp
    }
}
