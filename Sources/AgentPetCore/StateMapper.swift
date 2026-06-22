import Foundation

/// Maps an agent-native event name to a normalised `AgentState`.
///
/// Returns `nil` for events that should not change state (unknown or
/// irrelevant events are ignored rather than treated as an error).
public enum StateMapper {
    /// Events that mean the whole session ended (the agent was quit/closed), so
    /// the session should be removed immediately rather than lingering as done.
    public static func isSessionEnd(for kind: AgentKind, eventName: String) -> Bool {
        switch kind {
        case .claude: return eventName == "SessionEnd"
        case .gemini: return eventName == "SessionEnd"
        case .cursor: return eventName == "sessionEnd"
        case .droid: return eventName == "SessionEnd"
        default: return false
        }
    }

    public static func state(for kind: AgentKind, eventName: String) -> AgentState? {
        // Generic: any caller (e.g. the `agentpet run` wrapper) can send a
        // normalised state name directly.
        if let direct = AgentState(rawValue: eventName) { return direct }

        switch kind {
        case .claude:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
            case "Notification": return .waiting
            case "Stop": return .done
            // SubagentStop fires when a Task() subagent finishes mid-session —
            // not when the main session is done. Ignoring it (nil = "no state
            // change") avoids a false done→working flicker.
            case "SubagentStop": return nil
            default: return nil
            }
        case .codex:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart": return .working
            case "PermissionRequest": return .waiting
            case "Stop", "SubagentStop": return .done
            default: return nil
            }
        case .gemini:
            switch eventName {
            case "SessionStart": return .registered
            case "BeforeAgent", "BeforeModel", "BeforeTool", "AfterTool", "BeforeToolSelection", "AfterModel": return .working
            case "Notification": return .waiting
            case "AfterAgent", "SessionEnd": return .done
            default: return nil
            }
        case .cursor:
            switch eventName {
            case "sessionStart": return .registered
            case "beforeSubmitPrompt", "preToolUse", "beforeShellExecution": return .working
            case "stop", "subagentStop", "sessionEnd": return .done
            default: return nil
            }
        case .windsurf:
            switch eventName {
            case "pre_user_prompt": return .working
            case "post_cascade_response", "post_cascade_response_with_transcript": return .done
            default: return nil
            }
        case .opencode:
            // The plugin sends normalised states directly (handled above); these
            // map the raw opencode event names as a fallback.
            switch eventName {
            case "session.created": return .working
            case "session.idle": return .done
            default: return nil
            }
        case .antigravity:
            switch eventName {
            case "PreInvocation", "PreToolUse", "PostToolUse", "PostInvocation": return .working
            case "Stop": return .done
            default: return nil
            }
        case .copilot:
            // PascalCase events; PreToolUse is intentionally not registered
            // (its command hook is fail-closed and could block tools).
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "UserPromptSubmitted", "PostToolUse", "PreToolUse": return .working
            case "Notification", "PermissionRequest": return .waiting
            case "Stop", "AgentStop", "SessionEnd": return .done
            default: return nil
            }
        case .kiroCLI:
            // Kiro CLI sends camelCase event names; tolerate PascalCase too.
            switch eventName {
            case "agentSpawn", "AgentSpawn": return .registered
            case "userPromptSubmit", "UserPromptSubmit", "preToolUse", "PreToolUse",
                 "postToolUse", "PostToolUse": return .working
            case "notification", "Notification": return .waiting
            case "stop", "Stop": return .done
            default: return nil
            }
        case .droid:
            // Factory Droid CLI uses Claude-style PascalCase event names.
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
            case "Notification": return .waiting
            case "Stop": return .done
            // SubagentStop fires when a sub-droid task finishes mid-session, not
            // when the main session is done; ignore it to avoid a done→working flicker.
            case "SubagentStop": return nil
            default: return nil
            }
        case .pi:
            // The Pi extension sends normalised state names directly (handled by
            // the AgentState(rawValue:) check above). These map Pi's native event
            // names too, as a fallback. Pi has no approval gate, so no "waiting".
            switch eventName {
            case "session_start": return .registered
            case "agent_start", "turn_start", "tool_execution_start": return .working
            case "agent_end", "session_shutdown": return .done
            default: return nil
            }
        case .cli, .unknown:
            return nil
        }
    }
}
