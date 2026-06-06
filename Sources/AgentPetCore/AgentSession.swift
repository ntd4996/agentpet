import Foundation

/// Current known state of one agent session.
public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public var agentKind: AgentKind
    public var project: String?
    /// Human-readable conversation title (e.g. Claude Code's summary, or first
    /// user message). Populated lazily from the transcript when available.
    public var title: String?
    public var state: AgentState
    public var message: String?
    public var source: AgentSource
    public var updatedAt: Date
    /// When the session entered its current `state`; resets on state change.
    public var stateSince: Date

    public init(
        id: String,
        agentKind: AgentKind,
        project: String? = nil,
        title: String? = nil,
        state: AgentState,
        message: String? = nil,
        source: AgentSource,
        updatedAt: Date,
        stateSince: Date? = nil
    ) {
        self.id = id
        self.agentKind = agentKind
        self.project = project
        self.title = title
        self.state = state
        self.message = message
        self.source = source
        self.updatedAt = updatedAt
        self.stateSince = stateSince ?? updatedAt
    }
}
