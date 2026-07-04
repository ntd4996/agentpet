//! Maps an agent-native hook event name to a normalised pet state.
//! Ported from the macOS app's `StateMapper`. Returns `None` for events that
//! should not change state (ignored rather than treated as an error).

pub fn state(kind: &str, event: &str) -> Option<&'static str> {
    // Generic: a caller can pass a normalised state name directly.
    match event {
        "working" | "waiting" | "done" | "registered" | "idle" => {
            return Some(match event {
                "working" => "working",
                "waiting" => "waiting",
                "done" => "done",
                "registered" => "registered",
                _ => "idle",
            })
        }
        _ => {}
    }

    match kind {
        "claude" => match event {
            "SessionStart" => Some("registered"),
            "UserPromptSubmit" | "PreToolUse" | "PostToolUse" => Some("working"),
            "Notification" => Some("waiting"),
            "Stop" => Some("done"),
            _ => None, // SubagentStop etc. -> no change
        },
        "codex" => match event {
            "SessionStart" => Some("registered"),
            "UserPromptSubmit" | "PreToolUse" | "PostToolUse" | "SubagentStart" => Some("working"),
            "PermissionRequest" => Some("waiting"),
            "Stop" | "SubagentStop" => Some("done"),
            _ => None,
        },
        // Factory Droid CLI: same Claude-nested payload; Notification is a
        // permission/approval request or 60s idle, mapped to "waiting".
        "droid" => match event {
            "SessionStart" => Some("registered"),
            "UserPromptSubmit" | "PreToolUse" | "PostToolUse" => Some("working"),
            "Notification" => Some("waiting"),
            "Stop" => Some("done"),
            _ => None, // SubagentStop etc. -> no change
        },
        "gemini" => match event {
            "SessionStart" => Some("registered"),
            "BeforeAgent" | "BeforeModel" | "BeforeTool" | "AfterTool" | "BeforeToolSelection"
            | "AfterModel" => Some("working"),
            "Notification" => Some("waiting"),
            "AfterAgent" | "SessionEnd" => Some("done"),
            _ => None,
        },
        "cursor" => match event {
            "sessionStart" => Some("registered"),
            "beforeSubmitPrompt" | "preToolUse" | "beforeShellExecution" => Some("working"),
            "stop" | "subagentStop" | "sessionEnd" => Some("done"),
            _ => None,
        },
        "copilot" => match event {
            "SessionStart" => Some("registered"),
            "UserPromptSubmit" | "UserPromptSubmitted" | "PostToolUse" | "PreToolUse" => {
                Some("working")
            }
            "Notification" | "PermissionRequest" => Some("waiting"),
            "Stop" | "AgentStop" | "SessionEnd" => Some("done"),
            _ => None,
        },
        "opencode" => match event {
            // The JS plugin sends normalised states directly (handled at the top);
            // these map the raw opencode event names as a fallback.
            "session.created" => Some("working"),
            "session.idle" => Some("done"),
            _ => None,
        },
        "windsurf" => match event {
            "pre_user_prompt" => Some("working"),
            "post_cascade_response" | "post_cascade_response_with_transcript" => Some("done"),
            _ => None,
        },
        "antigravity" => match event {
            "PreInvocation" | "PreToolUse" | "PostToolUse" | "PostInvocation" => Some("working"),
            "Stop" => Some("done"),
            _ => None,
        },
        "kiro" => match event {
            "agentSpawn" | "AgentSpawn" => Some("registered"),
            "userPromptSubmit" | "UserPromptSubmit" | "preToolUse" | "PreToolUse"
            | "postToolUse" | "PostToolUse" => Some("working"),
            "notification" | "Notification" => Some("waiting"),
            "stop" | "Stop" => Some("done"),
            _ => None,
        },
        _ => None,
    }
}

/// True when an event means the whole session ended (remove it, don't linger).
pub fn is_session_end(kind: &str, event: &str) -> bool {
    matches!(
        (kind, event),
        ("claude", "SessionEnd") | ("gemini", "SessionEnd") | ("cursor", "sessionEnd") | ("droid", "SessionEnd")
    )
}
