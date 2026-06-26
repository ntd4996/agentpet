using AgentPet.Core.Models;
using AgentPet.Core.State;

namespace AgentPet.Core.Tests;

public sealed class StateMapperTests
{
    [Fact]
    public void ClaudeEventsMapToStates()
    {
        Assert.Equal(AgentState.Registered, StateMapper.StateFor(AgentKind.Claude, "SessionStart"));
        Assert.Equal(AgentState.Working, StateMapper.StateFor(AgentKind.Claude, "UserPromptSubmit"));
        Assert.Equal(AgentState.Working, StateMapper.StateFor(AgentKind.Claude, "PreToolUse"));
        Assert.Equal(AgentState.Working, StateMapper.StateFor(AgentKind.Claude, "PostToolUse"));
        Assert.Equal(AgentState.Waiting, StateMapper.StateFor(AgentKind.Claude, "Notification"));
        Assert.Equal(AgentState.Done, StateMapper.StateFor(AgentKind.Claude, "Stop"));
        Assert.Null(StateMapper.StateFor(AgentKind.Claude, "SubagentStop"));
    }

    [Fact]
    public void DirectStateNamesMapForAnyKind()
    {
        Assert.Equal(AgentState.Working, StateMapper.StateFor(AgentKind.Cli, "working"));
        Assert.Equal(AgentState.Done, StateMapper.StateFor(AgentKind.Cli, "done"));
        Assert.Equal(AgentState.Waiting, StateMapper.StateFor(AgentKind.Unknown, "waiting"));
    }

    [Fact]
    public void SessionEndRemovesClaudeSession()
    {
        Assert.True(StateMapper.IsSessionEnd(AgentKind.Claude, "SessionEnd"));
        Assert.False(StateMapper.IsSessionEnd(AgentKind.Claude, "Stop"));
    }
}
