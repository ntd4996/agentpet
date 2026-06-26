using AgentPet.Core.Events;
using AgentPet.Core.Models;

namespace AgentPet.Core.Tests;

public sealed class EventPipeTests
{
    [Fact]
    public async Task ClientReturnsFalseWhenNoServerIsRunning()
    {
        var client = new EventPipeClient("agentpet-test-missing-" + Guid.NewGuid().ToString("N"));
        var evt = new AgentEvent("s1", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(1));

        var delivered = await client.SendAsync(evt, TimeSpan.FromMilliseconds(50));

        Assert.False(delivered);
    }

    [Fact]
    public async Task ServerReceivesEventFromClient()
    {
        var pipeName = "agentpet-test-" + Guid.NewGuid().ToString("N");
        var evt = new AgentEvent("s1", AgentKind.Claude, "Stop", DateTimeOffset.FromUnixTimeSeconds(1));
        var received = new TaskCompletionSource<AgentEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var server = new EventPipeServer(pipeName);
        server.Start(agentEvent =>
        {
            received.TrySetResult(agentEvent);
            return Task.CompletedTask;
        });

        var delivered = await WaitForDelivery(pipeName, evt);
        var result = await received.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.True(delivered);
        Assert.Equal(evt, result);
    }

    private static async Task<bool> WaitForDelivery(string pipeName, AgentEvent evt)
    {
        var client = new EventPipeClient(pipeName);
        for (var attempt = 0; attempt < 20; attempt++)
        {
            if (await client.SendAsync(evt, TimeSpan.FromMilliseconds(100)))
            {
                return true;
            }

            await Task.Delay(25);
        }

        return false;
    }
}
