using System.IO.Pipes;
using System.Text;
using AgentPet.Core.Models;

namespace AgentPet.Core.Events;

public sealed class EventPipeServer : IAsyncDisposable, IDisposable
{
    private readonly string _pipeName;
    private CancellationTokenSource? _stopSource;
    private Task? _loopTask;

    public EventPipeServer(string pipeName)
    {
        _pipeName = pipeName;
    }

    public void Start(Action<AgentEvent> onEvent)
    {
        Start(evt =>
        {
            onEvent(evt);
            return Task.CompletedTask;
        });
    }

    public void Start(Func<AgentEvent, Task> onEvent)
    {
        if (_loopTask is { IsCompleted: false })
        {
            return;
        }

        _stopSource = new CancellationTokenSource();
        _loopTask = RunAsync(onEvent, _stopSource.Token);
    }

    public async Task StartAsync(Func<AgentEvent, Task> onEvent, CancellationToken cancellationToken = default)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        if (_stopSource is not null)
        {
            linked.Token.Register(_stopSource.Cancel);
        }

        await RunAsync(onEvent, linked.Token).ConfigureAwait(false);
    }

    public void Stop()
    {
        _stopSource?.Cancel();
    }

    public static IReadOnlyList<AgentEvent> DrainQueue(string directory) => EventQueue.Drain(directory);

    public static void DrainQueue(string directory, Action<AgentEvent> onEvent) => EventQueue.Drain(directory, onEvent);

    public void Dispose()
    {
        Stop();
        try
        {
            _loopTask?.Wait(TimeSpan.FromSeconds(1));
        }
        catch (AggregateException)
        {
        }
        _stopSource?.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        Stop();
        if (_loopTask is not null)
        {
            try
            {
                await _loopTask.WaitAsync(TimeSpan.FromSeconds(1)).ConfigureAwait(false);
            }
            catch (TimeoutException)
            {
            }
            catch (OperationCanceledException)
            {
            }
        }
        _stopSource?.Dispose();
    }

    private async Task RunAsync(Func<AgentEvent, Task> onEvent, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(
                    _pipeName,
                    PipeDirection.In,
                    NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);

                await pipe.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
                var text = await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
                foreach (var evt in EventCoding.DecodeLines(text))
                {
                    await onEvent(evt).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (IOException) when (!cancellationToken.IsCancellationRequested)
            {
            }
        }
    }
}
