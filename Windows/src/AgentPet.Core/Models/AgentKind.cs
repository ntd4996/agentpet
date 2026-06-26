namespace AgentPet.Core.Models;

public enum AgentKind
{
    Claude,
    Codex,
    Gemini,
    Cursor,
    Opencode,
    Windsurf,
    Antigravity,
    Cli,
    Unknown
}

public static class AgentKindExtensions
{
    public static string WireName(this AgentKind kind) => kind switch
    {
        AgentKind.Claude => "claude",
        AgentKind.Codex => "codex",
        AgentKind.Gemini => "gemini",
        AgentKind.Cursor => "cursor",
        AgentKind.Opencode => "opencode",
        AgentKind.Windsurf => "windsurf",
        AgentKind.Antigravity => "antigravity",
        AgentKind.Cli => "cli",
        _ => "unknown"
    };

    public static AgentKind Parse(string? value) => value?.ToLowerInvariant() switch
    {
        "claude" => AgentKind.Claude,
        "codex" => AgentKind.Codex,
        "gemini" => AgentKind.Gemini,
        "cursor" => AgentKind.Cursor,
        "opencode" => AgentKind.Opencode,
        "windsurf" => AgentKind.Windsurf,
        "antigravity" => AgentKind.Antigravity,
        "cli" => AgentKind.Cli,
        _ => AgentKind.Unknown
    };
}
