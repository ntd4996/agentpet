using AgentPet.Core.Models;
using AgentPet.Core.State;

namespace AgentPet.Core.Tests;

public sealed class SessionStoreTests
{
    private readonly DateTimeOffset _t0 = DateTimeOffset.FromUnixTimeSeconds(1_000_000);

    [Fact]
    public void ApplyCreatesSession()
    {
        var store = new SessionStore();
        var session = store.Apply(Event("SessionStart"), _t0);

        Assert.Equal(AgentState.Registered, session?.State);
        Assert.Equal("/proj", session?.Project);
        Assert.Equal(AgentSource.Hook, session?.Source);
        Assert.Single(store.Sessions);
    }

    [Fact]
    public void ApplyUpdatesExistingAndKeepsProjectWhenNil()
    {
        var store = new SessionStore();
        store.Apply(Event("SessionStart"), _t0);
        var updated = store.Apply(Event("Stop", project: null), _t0.AddSeconds(5));

        Assert.Equal(AgentState.Done, updated?.State);
        Assert.Equal("/proj", updated?.Project);
        Assert.Single(store.Sessions);
    }

    [Fact]
    public void ApplyIgnoresUnmappedEvent()
    {
        var store = new SessionStore();

        Assert.Null(store.Apply(Event("Bogus"), _t0));
        Assert.Empty(store.Sessions);
    }

    [Fact]
    public void ApplyRemovesSessionOnSessionEnd()
    {
        var store = new SessionStore();
        store.Apply(Event("UserPromptSubmit"), _t0);

        Assert.Null(store.Apply(Event("SessionEnd"), _t0.AddSeconds(1)));
        Assert.Empty(store.Sessions);
    }

    [Fact]
    public void RefineStateAppliesOnlyWhenStateAndSinceMatch()
    {
        var store = new SessionStore();
        var applied = store.Apply(Event("Stop"), _t0)!;

        store.RefineState("s1", AgentState.Done, AgentState.Waiting, applied.StateSince);

        Assert.Equal(AgentState.Waiting, store.Session("s1")?.State);
        Assert.Equal(applied.StateSince, store.Session("s1")?.StateSince);

        store.Apply(Event("UserPromptSubmit"), _t0.AddSeconds(2));
        store.RefineState("s1", AgentState.Waiting, AgentState.Done, applied.StateSince);
        Assert.Equal(AgentState.Working, store.Session("s1")?.State);
    }

    [Fact]
    public void PruneDemotesDoneThenRemovesIdle()
    {
        var store = new SessionStore(doneToIdleAfter: TimeSpan.FromSeconds(30), removeIdleAfter: TimeSpan.FromSeconds(600));
        store.Apply(Event("Stop"), _t0);

        store.Prune(_t0.AddSeconds(10));
        Assert.Equal(AgentState.Done, store.Session("s1")?.State);

        store.Prune(_t0.AddSeconds(40));
        Assert.Equal(AgentState.Idle, store.Session("s1")?.State);

        store.Prune(_t0.AddSeconds(640));
        Assert.Null(store.Session("s1"));
    }

    [Fact]
    public void PruneRemovesStaleActiveAndRegisteredSessions()
    {
        var store = new SessionStore(staleActiveAfter: TimeSpan.FromSeconds(300), staleRegisteredAfter: TimeSpan.FromSeconds(90));
        store.Apply(Event("UserPromptSubmit", session: "working"), _t0);
        store.Apply(Event("SessionStart", session: "registered"), _t0);

        store.Prune(_t0.AddSeconds(90));
        Assert.NotNull(store.Session("working"));
        Assert.Null(store.Session("registered"));

        store.Prune(_t0.AddSeconds(300));
        Assert.Null(store.Session("working"));
    }

    [Fact]
    public void SortedUsesAttentionPriorityThenRecency()
    {
        var store = new SessionStore();
        store.Apply(Event("Stop", session: "done"), _t0);
        store.Apply(Event("Notification", session: "waiting"), _t0.AddSeconds(1));
        store.Apply(Event("UserPromptSubmit", session: "working"), _t0);

        Assert.Equal(new[] { "working", "waiting", "done" }, store.Sorted.Select(session => session.Id));
    }

    private AgentEvent Event(string name, string session = "s1", string? project = "/proj") =>
        new(session, AgentKind.Claude, name, project, null, null, _t0);
}
