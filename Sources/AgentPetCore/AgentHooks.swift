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
    /// Kiro CLI agent config `~/.kiro/agents/<agent>.json`: a `"hooks"` key merged
    /// into the agent file as `{"hooks": {event: [{"command": ...}]}}` (plain
    /// command items, no extra keys). Other agent fields are preserved.
    case kiroFlat
    /// Pi (pi.dev): a TypeScript extension file dropped in
    /// `~/.pi/agent/extensions/`. Like opencode, the extension hardcodes its own
    /// `pi.on(...)` handlers and reports state through the `agentpet hook` CLI.
    case piExtension
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
        case .copilot:
            // GitHub Copilot CLI: ~/.copilot/hooks/*.json, same flat shape as
            // Cursor (version + {type:command, command}). PascalCase event names
            // make Copilot send a snake_case payload with `hook_event_name`,
            // which decodes via the Claude payload. PreToolUse is deliberately
            // omitted: its command hook is fail-closed, so an error would block
            // the user's tools.
            return AgentHookSpec(
                kind: .copilot, style: .cursorFlat,
                events: ["SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"],
                settingsPath: home + "/.copilot/hooks/agentpet.json")
        case .kiroCLI:
            // Kiro CLI: hooks live inside an agent config file. We target the
            // default agent. camelCase lifecycle events; STDIN carries
            // hook_event_name/cwd/session_id (Claude-style). preToolUse omitted
            // to avoid any chance of blocking tool calls.
            return AgentHookSpec(
                kind: .kiroCLI, style: .kiroFlat,
                events: ["agentSpawn", "userPromptSubmit", "postToolUse", "stop"],
                settingsPath: home + "/.kiro/agents/default.json")
        case .droid:
            // Factory Droid CLI: ~/.factory/hooks.json, identical nested shape and
            // snake_case stdin payload as Claude (session_id/cwd/hook_event_name).
            // Notification fires on permission/approval requests (and 60s idle),
            // which we map to "waiting". Our hook command always exits 0, so the
            // PreToolUse hook can't block tool calls.
            return AgentHookSpec(
                kind: .droid, style: .claudeNested,
                events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop", "SessionEnd"],
                settingsPath: home + "/.factory/hooks.json")
        case .pi:
            // Pi has no Claude-style command hooks; its native mechanism is a TS
            // extension auto-discovered in ~/.pi/agent/extensions/. The extension
            // hardcodes its own pi.on() handlers, so no event list is registered
            // through the generic installer. Pi has no built-in approval gate, so
            // only working/done/registered are reported (no "waiting").
            return AgentHookSpec(
                kind: .pi, style: .piExtension,
                events: [],
                settingsPath: home + "/.pi/agent/extensions/agentpet.ts")
        case .cli, .unknown:
            return nil
        }
    }
}
