using System.Text.Json.Serialization;

namespace AgentPet.Core.Models;

public sealed record AgentEvent
{
    [JsonConstructor]
    public AgentEvent(
        string sessionId,
        AgentKind agentKind,
        string eventName,
        string? project,
        string? message,
        string? transcriptPath,
        DateTimeOffset timestamp)
    {
        SessionId = sessionId;
        AgentKind = agentKind;
        EventName = eventName;
        Project = project;
        Message = message;
        TranscriptPath = transcriptPath;
        Timestamp = timestamp;
    }

    public AgentEvent(string sessionId, AgentKind agentKind, string eventName, DateTimeOffset timestamp)
        : this(sessionId, agentKind, eventName, null, null, null, timestamp)
    {
    }

    [JsonPropertyName("sessionId")]
    public string SessionId { get; init; }

    [JsonPropertyName("agentKind")]
    public AgentKind AgentKind { get; init; }

    [JsonPropertyName("eventName")]
    public string EventName { get; init; }

    [JsonPropertyName("project")]
    public string? Project { get; init; }

    [JsonPropertyName("message")]
    public string? Message { get; init; }

    [JsonPropertyName("transcriptPath")]
    public string? TranscriptPath { get; init; }

    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; init; }
}
