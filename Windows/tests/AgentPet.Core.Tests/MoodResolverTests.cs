using AgentPet.Core.Models;
using AgentPet.Core.State;

namespace AgentPet.Core.Tests;

public sealed class MoodResolverTests
{
    [Fact]
    public void EmptyIsIdle()
    {
        Assert.Equal(PetMood.Idle, MoodResolver.Aggregate([]));
    }

    [Fact]
    public void WaitingWins()
    {
        var sessions = new[] { Session(AgentState.Working, "a"), Session(AgentState.Waiting, "b"), Session(AgentState.Done, "c") };
        Assert.Equal(PetMood.Waiting, MoodResolver.Aggregate(sessions));
    }

    [Fact]
    public void WaitingBeatsDone()
    {
        Assert.Equal(PetMood.Waiting, MoodResolver.Aggregate([Session(AgentState.Done, "a"), Session(AgentState.Waiting, "b")]));
    }

    [Fact]
    public void RegisteredIsNotWorking()
    {
        Assert.Equal(PetMood.Idle, MoodResolver.Aggregate([Session(AgentState.Registered, "a")]));
        Assert.Equal(PetMood.Working, MoodResolver.Aggregate([Session(AgentState.Registered, "a"), Session(AgentState.Working, "b")]));
    }

    [Fact]
    public void DoneOnly()
    {
        Assert.Equal(PetMood.Done, MoodResolver.Aggregate([Session(AgentState.Done, "a"), Session(AgentState.Idle, "b")]));
    }

    private static AgentSession Session(AgentState state, string id) =>
        new(id, AgentKind.Claude, state, AgentSource.Hook, DateTimeOffset.UnixEpoch);
}
