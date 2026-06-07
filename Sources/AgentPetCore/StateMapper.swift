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
        case .hermes: return eventName == "on_session_end"
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
            case "Stop", "SubagentStop": return .done
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
        case .hermes:
            switch eventName {
            case "on_session_start": return .registered
            case "pre_llm_call", "post_llm_call", "pre_tool_call", "post_tool_call",
                 "pre_api_request", "post_api_request": return .working
            case "on_session_end", "on_session_finalize", "on_session_reset",
                 "subagent_stop": return .done
            default: return nil
            }
        case .cli, .unknown:
            return nil
        }
    }
}
