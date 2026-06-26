using System.IO.Pipes;
using AgentPet.Core.Models;

namespace AgentPet.Core.Events;

public sealed class EventPipeClient
{
    private readonly string _pipeName;

    public EventPipeClient(string pipeName)
    {
        _pipeName = pipeName;
    }

    public bool Send(AgentEvent evt, int timeoutMilliseconds = 200)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", _pipeName, PipeDirection.Out);
            pipe.Connect(timeoutMilliseconds);
            var data = EventCoding.EncodeLineBytes(evt);
            pipe.Write(data, 0, data.Length);
            pipe.Flush();
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (TimeoutException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    public async Task<bool> SendAsync(AgentEvent evt, TimeSpan? timeout = null, CancellationToken cancellationToken = default)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", _pipeName, PipeDirection.Out, PipeOptions.Asynchronous);
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(timeout ?? TimeSpan.FromMilliseconds(200));
            await pipe.ConnectAsync(timeoutSource.Token).ConfigureAwait(false);
            var data = EventCoding.EncodeLineBytes(evt);
            await pipe.WriteAsync(data, timeoutSource.Token).ConfigureAwait(false);
            await pipe.FlushAsync(timeoutSource.Token).ConfigureAwait(false);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
