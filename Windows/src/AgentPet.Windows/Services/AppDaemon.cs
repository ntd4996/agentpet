using System.Windows.Threading;
using AgentPet.Core.Events;
using AgentPet.Core.Models;
using AgentPet.Core.Paths;
using AgentPet.Core.State;

namespace AgentPet.Windows.Services;

public sealed class AppDaemon : IDisposable
{
    private readonly SessionStore _store = new();
    private readonly DispatcherTimer _pruneTimer;
    private EventPipeServer? _server;
    private bool _disposed;

    public AppDaemon()
    {
        _pruneTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(5)
        };
        _pruneTimer.Tick += (_, _) =>
        {
            _store.Prune(DateTimeOffset.UtcNow);
            PublishSessions();
        };
    }

    public event Action<IReadOnlyList<AgentSession>>? SessionsChanged;

    public IReadOnlyList<AgentSession> Sessions => _store.Sorted;

    public void Start()
    {
        foreach (var queueDir in AgentPetPaths.QueueDirs)
        {
            EventQueue.Drain(queueDir, ApplyEvent);
        }

        _server = new EventPipeServer(AgentPetPaths.PipeName);
        _server.Start(ApplyEvent);
        _pruneTimer.Start();
        PublishSessions();
    }

    public void Stop()
    {
        _pruneTimer.Stop();
        _server?.Dispose();
        _server = null;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Stop();
        _disposed = true;
    }

    private void ApplyEvent(AgentEvent evt)
    {
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            _store.Apply(evt, DateTimeOffset.UtcNow);
            PublishSessions();
        });
    }

    private void PublishSessions()
    {
        SessionsChanged?.Invoke(_store.Sorted);
    }
}
