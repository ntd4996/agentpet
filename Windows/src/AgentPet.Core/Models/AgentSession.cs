namespace AgentPet.Core.Models;

public sealed record AgentSession(
    string Id,
    AgentKind AgentKind,
    string? Project,
    string? Title,
    AgentState State,
    string? Message,
    AgentSource Source,
    DateTimeOffset UpdatedAt,
    DateTimeOffset StateSince)
{
    public AgentSession(
        string id,
        AgentKind agentKind,
        AgentState state,
        AgentSource source,
        DateTimeOffset updatedAt,
        string? project = null,
        string? title = null,
        string? message = null,
        DateTimeOffset? stateSince = null)
        : this(id, agentKind, project, title, state, message, source, updatedAt, stateSince ?? updatedAt)
    {
    }
}
