using AgentPet.Core.Models;
using AgentPet.Core.Text;

namespace AgentPet.Core.Tests;

public sealed class TickerFormatterTests
{
    [Fact]
    public void AgentLabelKnownKinds()
    {
        Assert.Equal("Claude", TickerFormatter.AgentLabel(AgentKind.Claude));
        Assert.Equal("Cursor", TickerFormatter.AgentLabel(AgentKind.Cursor));
        Assert.Equal("Codex", TickerFormatter.AgentLabel(AgentKind.Codex));
        Assert.Equal("Gemini", TickerFormatter.AgentLabel(AgentKind.Gemini));
        Assert.Equal("Opencode", TickerFormatter.AgentLabel(AgentKind.Opencode));
        Assert.Equal("Windsurf", TickerFormatter.AgentLabel(AgentKind.Windsurf));
        Assert.Equal("Antigravity", TickerFormatter.AgentLabel(AgentKind.Antigravity));
    }

    [Fact]
    public void AgentLabelFallbacks()
    {
        Assert.Equal("Agent", TickerFormatter.AgentLabel(AgentKind.Cli));
        Assert.Equal("Agent", TickerFormatter.AgentLabel(AgentKind.Unknown));
    }

    [Fact]
    public void LineWithMessageUsesProjectLastPathComponent()
    {
        var session = new AgentSession("claude-abc", AgentKind.Claude, AgentState.Working, AgentSource.Hook, DateTimeOffset.UnixEpoch, project: @"C:\dev\agentpet", message: "running bash…");

        Assert.Equal("Claude [agentpet] → running bash…", TickerFormatter.Line(session));
    }

    [Fact]
    public void LineWithoutMessageUsesCapitalizedState()
    {
        var session = new AgentSession("cursor-xyz", AgentKind.Cursor, AgentState.Waiting, AgentSource.Hook, DateTimeOffset.UnixEpoch, project: "/Users/me/my-api");

        Assert.Equal("Cursor [my-api] → Waiting", TickerFormatter.Line(session));
    }

    [Fact]
    public void LineWithWhitespaceMessageUsesCapitalizedState()
    {
        var session = new AgentSession("gemini-1", AgentKind.Gemini, AgentState.Working, AgentSource.Hook, DateTimeOffset.UnixEpoch, project: "/Users/me/frontend", message: "   ");

        Assert.Equal("Gemini [frontend] → Working", TickerFormatter.Line(session));
    }

    [Fact]
    public void LineFallsBackToIdWhenNoProject()
    {
        var session = new AgentSession("my-session-id", AgentKind.Cli, AgentState.Working, AgentSource.Hook, DateTimeOffset.UnixEpoch, message: "running");

        Assert.Equal("Agent [my-session-id] → running", TickerFormatter.Line(session));
    }

    [Fact]
    public void SortedPutsWaitingFirstThenWorkingThenDone()
    {
        var t = DateTimeOffset.UnixEpoch;
        var working = new AgentSession("a", AgentKind.Claude, AgentState.Working, AgentSource.Hook, t);
        var waiting = new AgentSession("b", AgentKind.Cursor, AgentState.Waiting, AgentSource.Hook, t);
        var done = new AgentSession("c", AgentKind.Codex, AgentState.Done, AgentSource.Hook, t);

        Assert.Equal(new[] { "b", "a", "c" }, TickerFormatter.Sorted([done, working, waiting]).Select(session => session.Id));
    }

    [Fact]
    public void SortedUsesMostRecentWithinSamePriority()
    {
        var older = new AgentSession("old", AgentKind.Claude, AgentState.Working, AgentSource.Hook, DateTimeOffset.UnixEpoch);
        var newer = new AgentSession("newer", AgentKind.Cursor, AgentState.Working, AgentSource.Hook, DateTimeOffset.UnixEpoch.AddSeconds(10));

        Assert.Equal("newer", TickerFormatter.Sorted([older, newer]).First().Id);
    }
}
