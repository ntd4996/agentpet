using AgentPet.Core.Models;
using AgentPet.Core.Paths;

namespace AgentPet.Core.Events;

public static class EventSender
{
    public static bool Send(AgentEvent evt) => Send(evt, AgentPetPaths.PipeName, AgentPetPaths.QueueDir);

    public static bool Send(AgentEvent evt, string pipeName, string queueDir)
    {
        var client = new EventPipeClient(pipeName);
        if (client.Send(evt))
        {
            return true;
        }

        try
        {
            EventQueue.Enqueue(evt, queueDir);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return false;
    }

    public static async Task<bool> SendAsync(AgentEvent evt, string pipeName, string queueDir, CancellationToken cancellationToken = default)
    {
        var client = new EventPipeClient(pipeName);
        if (await client.SendAsync(evt, cancellationToken: cancellationToken).ConfigureAwait(false))
        {
            return true;
        }

        try
        {
            EventQueue.Enqueue(evt, queueDir);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return false;
    }
}
