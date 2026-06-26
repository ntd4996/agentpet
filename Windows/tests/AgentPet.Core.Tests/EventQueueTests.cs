using AgentPet.Core.Events;
using AgentPet.Core.Models;

namespace AgentPet.Core.Tests;

public sealed class EventQueueTests : IDisposable
{
    private readonly string _queueDir = Path.Combine(Path.GetTempPath(), "agentpet-q-" + Guid.NewGuid().ToString("N"));

    [Fact]
    public void EnqueueCreatesQueueDirectoryAndDrainReturnsEvent()
    {
        var evt = new AgentEvent("s10", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(7));

        EventQueue.Enqueue(evt, _queueDir);
        var received = EventQueue.Drain(_queueDir);

        Assert.Equal([evt], received);
        Assert.Empty(Directory.EnumerateFiles(_queueDir));
    }

    [Fact]
    public void DrainProcessesFilesInNameOrderAndRemovesInvalidFiles()
    {
        Directory.CreateDirectory(_queueDir);
        File.WriteAllText(Path.Combine(_queueDir, "0002.json"), EventCoding.EncodeLine(new AgentEvent("second", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(2))));
        File.WriteAllText(Path.Combine(_queueDir, "0001.json"), EventCoding.EncodeLine(new AgentEvent("first", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(1))));
        File.WriteAllText(Path.Combine(_queueDir, "0000.json"), "not-json\n");

        var received = EventQueue.Drain(_queueDir);

        Assert.Equal(new[] { "first", "second" }, received.Select(evt => evt.SessionId));
        Assert.Empty(Directory.EnumerateFiles(_queueDir));
    }

    [Fact]
    public void EventSenderQueuesWhenPipeIsMissing()
    {
        var evt = new AgentEvent("s11", AgentKind.Claude, "Notification", DateTimeOffset.FromUnixTimeSeconds(11));
        var pipeName = "agentpet-test-missing-" + Guid.NewGuid().ToString("N");

        var delivered = EventSender.Send(evt, pipeName, _queueDir);
        var received = EventQueue.Drain(_queueDir);

        Assert.False(delivered);
        Assert.Equal([evt], received);
    }

    public void Dispose()
    {
        if (Directory.Exists(_queueDir))
        {
            Directory.Delete(_queueDir, recursive: true);
        }
    }
}
