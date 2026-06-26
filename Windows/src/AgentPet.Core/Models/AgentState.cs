namespace AgentPet.Core.Models;

public enum AgentState
{
    Registered,
    Working,
    Waiting,
    Done,
    Idle
}

public static class AgentStateExtensions
{
    public static string WireName(this AgentState state) => state switch
    {
        AgentState.Registered => "registered",
        AgentState.Working => "working",
        AgentState.Waiting => "waiting",
        AgentState.Done => "done",
        AgentState.Idle => "idle",
        _ => "idle"
    };

    public static int AttentionPriority(this AgentState state) => state switch
    {
        AgentState.Working => 4,
        AgentState.Waiting => 3,
        AgentState.Done => 2,
        AgentState.Registered => 1,
        AgentState.Idle => 0,
        _ => 0
    };

    public static bool TryParseWireName(string value, out AgentState state)
    {
        state = value switch
        {
            "registered" => AgentState.Registered,
            "working" => AgentState.Working,
            "waiting" => AgentState.Waiting,
            "done" => AgentState.Done,
            "idle" => AgentState.Idle,
            _ => AgentState.Idle
        };
        return value is "registered" or "working" or "waiting" or "done" or "idle";
    }
}
