using AgentPet.Core.Models;

namespace AgentPet.Core.State;

public static class StateMapper
{
    public static bool IsSessionEnd(AgentKind kind, string eventName) => kind switch
    {
        AgentKind.Claude => eventName == "SessionEnd",
        AgentKind.Gemini => eventName == "SessionEnd",
        AgentKind.Cursor => eventName == "sessionEnd",
        _ => false
    };

    public static AgentState? StateFor(AgentKind kind, string eventName)
    {
        if (AgentStateExtensions.TryParseWireName(eventName, out var direct))
        {
            return direct;
        }

        return kind switch
        {
            AgentKind.Claude => eventName switch
            {
                "SessionStart" => AgentState.Registered,
                "UserPromptSubmit" or "PreToolUse" or "PostToolUse" => AgentState.Working,
                "Notification" => AgentState.Waiting,
                "Stop" => AgentState.Done,
                "SubagentStop" => null,
                _ => null
            },
            AgentKind.Codex => eventName switch
            {
                "SessionStart" => AgentState.Registered,
                "UserPromptSubmit" or "PreToolUse" or "PostToolUse" or "SubagentStart" => AgentState.Working,
                "PermissionRequest" => AgentState.Waiting,
                "Stop" or "SubagentStop" => AgentState.Done,
                _ => null
            },
            AgentKind.Gemini => eventName switch
            {
                "SessionStart" => AgentState.Registered,
                "BeforeAgent" or "BeforeModel" or "BeforeTool" or "AfterTool" or "BeforeToolSelection" or "AfterModel" => AgentState.Working,
                "Notification" => AgentState.Waiting,
                "AfterAgent" or "SessionEnd" => AgentState.Done,
                _ => null
            },
            AgentKind.Cursor => eventName switch
            {
                "sessionStart" => AgentState.Registered,
                "beforeSubmitPrompt" or "preToolUse" or "beforeShellExecution" => AgentState.Working,
                "stop" or "subagentStop" or "sessionEnd" => AgentState.Done,
                _ => null
            },
            AgentKind.Windsurf => eventName switch
            {
                "pre_user_prompt" => AgentState.Working,
                "post_cascade_response" or "post_cascade_response_with_transcript" => AgentState.Done,
                _ => null
            },
            AgentKind.Opencode => eventName switch
            {
                "session.created" => AgentState.Working,
                "session.idle" => AgentState.Done,
                _ => null
            },
            AgentKind.Antigravity => eventName switch
            {
                "PreInvocation" or "PreToolUse" or "PostToolUse" or "PostInvocation" => AgentState.Working,
                "Stop" => AgentState.Done,
                _ => null
            },
            _ => null
        };
    }
}
