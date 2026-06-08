import Foundation

/// How an agent's hook configuration is written. The supported agents do not
/// share one format, so each spec carries its style.
public enum HookStyle: Sendable {
    /// Claude Code / Codex / Gemini: `{"hooks": {Event: [{"hooks": [{"type": "command", "command": ...}]}]}}`.
    case claudeNested
    /// Cursor `~/.cursor/hooks.json`: `{"version": 1, "hooks": {event: [{"command": ..., "type": "command"}]}}`.
    case cursorFlat
    /// Windsurf `~/.codeium/windsurf/hooks.json`: `{"hooks": {event: [{"command": ...}]}}`.
    case windsurfFlat
    /// opencode: a JS plugin file dropped in `~/.config/opencode/plugin/`.
    case opencodePlugin
    /// Antigravity `~/.gemini/config/hooks.json`: like claudeNested but the event
    /// map lives under a named hook group instead of a top-level `"hooks"` key:
    /// `{"agentpet": {Event: [{"hooks": [{"type": "command", "command": ...}]}]}}`.
    case antigravityNested
    /// Hermes `~/.hermes/config.yaml`: `hooks:\n  event:\n    - command: '...'`.
    case hermesYaml
}

/// Where and which lifecycle events to register for an agent.
public struct AgentHookSpec {
    public let kind: AgentKind
    public let style: HookStyle
    public let events: [String]
    public let settingsPath: String
}

public enum AgentHooks {
    public static func spec(for kind: AgentKind) -> AgentHookSpec? {
        let home = NSHomeDirectory()
        switch kind {
        case .claude:
            return AgentHookSpec(
                kind: .claude, style: .claudeNested,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"],
                settingsPath: home + "/.claude/settings.json")
        case .codex:
            return AgentHookSpec(
                kind: .codex, style: .claudeNested,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SubagentStop"],
                settingsPath: home + "/.codex/hooks.json")
        case .gemini:
            return AgentHookSpec(
                kind: .gemini, style: .claudeNested,
                events: ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"],
                settingsPath: home + "/.gemini/settings.json")
        case .cursor:
            return AgentHookSpec(
                kind: .cursor, style: .cursorFlat,
                events: ["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "subagentStop", "sessionEnd"],
                settingsPath: home + "/.cursor/hooks.json")
        case .windsurf:
            return AgentHookSpec(
                kind: .windsurf, style: .windsurfFlat,
                events: ["pre_user_prompt", "post_cascade_response"],
                settingsPath: home + "/.codeium/windsurf/hooks.json")
        case .opencode:
            // The JS plugin hardcodes its own session.created/session.idle hooks,
            // so no event list is registered through the generic installer.
            return AgentHookSpec(
                kind: .opencode, style: .opencodePlugin,
                events: [],
                settingsPath: home + "/.config/opencode/plugin/agentpet.js")
        case .antigravity:
            // Antigravity has no session-start/notification hooks, so we register
            // for the model-call and tool lifecycle plus Stop. PreInvocation fires
            // when a turn begins; Stop when the agent loop ends.
            return AgentHookSpec(
                kind: .antigravity, style: .antigravityNested,
                events: ["PreInvocation", "PreToolUse", "PostToolUse", "Stop"],
                settingsPath: home + "/.gemini/config/hooks.json")
        case .hermes:
            return AgentHookSpec(
                kind: .hermes, style: .hermesYaml,
                events: ["on_session_start", "pre_llm_call", "post_llm_call",
                         "pre_tool_call", "post_tool_call",
                         "on_session_end", "subagent_stop"],
                settingsPath: home + "/.hermes/config.yaml")
        case .cli, .unknown:
            return nil
        }
    }
}
