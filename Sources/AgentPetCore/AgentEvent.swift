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
    /// Non-nil marks this event as a gated `PreToolUse` request: the daemon
    /// is holding the hook's connection open until the user approves/denies.
    public var approvalRequestId: String?
    /// Name of the tool awaiting approval (e.g. `"Bash"`). Set alongside
    /// `approvalRequestId`.
    public var toolName: String?
    /// Human-readable summary of the pending tool call (e.g. the shell
    /// command), truncated for display. Set alongside `approvalRequestId`.
    public var toolSummary: String?
    /// `TERM_PROGRAM` of the terminal the agent runs in (e.g. `"iTerm.app"`,
    /// `"Apple_Terminal"`, `"WarpTerminal"`). Used to focus that terminal when
    /// the user clicks the session's bubble row. `nil` outside a terminal.
    public var terminalProgram: String?
    /// Controlling TTY device of the terminal (e.g. `"/dev/ttys003"`), used to
    /// activate the exact window/tab in Terminal.app and iTerm2.
    public var terminalTTY: String?
    /// Deep link that focuses the exact tab/pane (Warp's `WARP_FOCUS_URL`). Used
    /// for terminals that expose a URL scheme instead of AppleScript.
    public var terminalFocusURL: String?
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
        approvalRequestId: String? = nil,
        toolName: String? = nil,
        toolSummary: String? = nil,
        terminalProgram: String? = nil,
        terminalTTY: String? = nil,
        terminalFocusURL: String? = nil,
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
        self.approvalRequestId = approvalRequestId
        self.toolName = toolName
        self.toolSummary = toolSummary
        self.terminalProgram = terminalProgram
        self.terminalTTY = terminalTTY
        self.terminalFocusURL = terminalFocusURL
        self.timestamp = timestamp
    }
}
