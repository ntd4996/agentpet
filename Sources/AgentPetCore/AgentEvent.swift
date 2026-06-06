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
    /// Path to the agent's conversation transcript file (e.g. Claude Code JSONL).
    /// Used to derive a human-readable title for the session.
    public var transcriptPath: String?
    public var timestamp: Date

    public init(
        sessionId: String,
        agentKind: AgentKind,
        eventName: String,
        project: String? = nil,
        message: String? = nil,
        transcriptPath: String? = nil,
        timestamp: Date
    ) {
        self.sessionId = sessionId
        self.agentKind = agentKind
        self.eventName = eventName
        self.project = project
        self.message = message
        self.transcriptPath = transcriptPath
        self.timestamp = timestamp
    }
}
