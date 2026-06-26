using AgentPet.Core.Events;
using AgentPet.Core.Models;

namespace AgentPet.Core.Tests;

public sealed class EventCodingTests
{
    [Fact]
    public void EncodeLineUsesSwiftCompatibleWireValues()
    {
        var evt = new AgentEvent("s1", AgentKind.Claude, "Stop", "/p", "done", null, DateTimeOffset.FromUnixTimeSeconds(123));

        var line = EventCoding.EncodeLine(evt);

        Assert.Contains("\"agentKind\":\"claude\"", line);
        Assert.Contains("\"timestamp\":123", line);
        Assert.EndsWith("\n", line);
    }

    [Fact]
    public void DecodeLineReadsSwiftShapedJson()
    {
        const string json = "{\"sessionId\":\"s\",\"agentKind\":\"claude\",\"eventName\":\"Stop\",\"project\":null,\"message\":null,\"transcriptPath\":null,\"timestamp\":7}";

        var evt = EventCoding.DecodeLine(json);

        Assert.NotNull(evt);
        Assert.Equal("s", evt.SessionId);
        Assert.Equal(AgentKind.Claude, evt.AgentKind);
        Assert.Equal("Stop", evt.EventName);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(7), evt.Timestamp);
    }

    [Fact]
    public void DecodeUnknownAgentKindAsUnknown()
    {
        const string json = "{\"sessionId\":\"s\",\"agentKind\":\"new-agent\",\"eventName\":\"Stop\",\"project\":null,\"message\":null,\"transcriptPath\":null,\"timestamp\":7}";

        var evt = EventCoding.DecodeLine(json);

        Assert.Equal(AgentKind.Unknown, evt?.AgentKind);
    }

    [Fact]
    public void DecodeLinesSkipsInvalidAndEmptyLines()
    {
        var valid = EventCoding.EncodeLine(new AgentEvent("s1", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(1)));
        var events = EventCoding.DecodeLines("\nnot-json\n" + valid + "\n").ToArray();

        Assert.Single(events);
        Assert.Equal("s1", events[0].SessionId);
    }
}
