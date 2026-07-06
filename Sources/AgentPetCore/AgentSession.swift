import Foundation

/// A gated tool call awaiting the user's allow/deny decision.
public struct PendingApproval: Sendable, Equatable {
    public let requestId: String
    public let toolName: String
    public let summary: String

    public init(requestId: String, toolName: String, summary: String) {
        self.requestId = requestId
        self.toolName = toolName
        self.summary = summary
    }
}

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
    /// Display name of the LLM model in use (e.g. "Sonnet 4.6"), if any hook
    /// event for this session reported one. Sticky: once set, persists across
    /// later events that omit it.
    public var model: String?
    public var source: AgentSource
    public var updatedAt: Date
    /// When the session entered its current `state`; resets on state change.
    public var stateSince: Date
    /// When the session was first created (first `apply` event).
    public var createdAt: Date
    /// Gated tool call currently awaiting the user's decision, if any.
    public var pendingApproval: PendingApproval?

    public init(
        id: String,
        agentKind: AgentKind,
        project: String? = nil,
        title: String? = nil,
        state: AgentState,
        message: String? = nil,
        model: String? = nil,
        source: AgentSource,
        updatedAt: Date,
        stateSince: Date? = nil,
        createdAt: Date? = nil,
        pendingApproval: PendingApproval? = nil
    ) {
        self.id = id
        self.agentKind = agentKind
        self.project = project
        self.title = title
        self.state = state
        self.message = message
        self.model = model
        self.source = source
        self.updatedAt = updatedAt
        self.stateSince = stateSince ?? updatedAt
        self.createdAt = createdAt ?? updatedAt
        self.pendingApproval = pendingApproval
    }
}
