using AgentPet.Core.Models;

namespace AgentPet.Core.Text;

public static class TickerFormatter
{
    public static string AgentLabel(AgentKind kind) => kind switch
    {
        AgentKind.Claude => "Claude",
        AgentKind.Cursor => "Cursor",
        AgentKind.Codex => "Codex",
        AgentKind.Gemini => "Gemini",
        AgentKind.Opencode => "Opencode",
        AgentKind.Windsurf => "Windsurf",
        AgentKind.Antigravity => "Antigravity",
        AgentKind.Cli => "Agent",
        _ => "Agent"
    };

    public static string Line(AgentSession session)
    {
        var label = AgentLabel(session.AgentKind);
        var project = ProjectLabel(session.Project) ?? session.Id;
        var message = string.IsNullOrWhiteSpace(session.Message)
            ? StateDisplayName(session.State)
            : session.Message!;
        return $"{label} [{project}] → {message}";
    }

    public static IReadOnlyList<AgentSession> Sorted(IEnumerable<AgentSession> sessions) => sessions
        .OrderBy(session => Priority(session.State))
        .ThenByDescending(session => session.UpdatedAt)
        .ToArray();

    private static string? ProjectLabel(string? project)
    {
        if (string.IsNullOrWhiteSpace(project))
        {
            return null;
        }

        var trimmed = project.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar, '/', '\\');
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        return Path.GetFileName(trimmed);
    }

    private static string StateDisplayName(AgentState state)
    {
        var name = state.WireName();
        return string.Concat(name[..1].ToUpperInvariant(), name.AsSpan(1));
    }

    private static int Priority(AgentState state) => state switch
    {
        AgentState.Waiting => 0,
        AgentState.Working => 1,
        AgentState.Done => 2,
        AgentState.Idle => 3,
        AgentState.Registered => 4,
        _ => 5
    };
}
