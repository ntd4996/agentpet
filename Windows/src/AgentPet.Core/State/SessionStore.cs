using AgentPet.Core.Models;

namespace AgentPet.Core.State;

public sealed class SessionStore
{
    private readonly TimeSpan _doneToIdleAfter;
    private readonly TimeSpan _removeIdleAfter;
    private readonly TimeSpan _staleActiveAfter;
    private readonly TimeSpan _staleRegisteredAfter;
    private readonly Dictionary<string, AgentSession> _byId = new();

    public SessionStore(
        TimeSpan? doneToIdleAfter = null,
        TimeSpan? removeIdleAfter = null,
        TimeSpan? staleActiveAfter = null,
        TimeSpan? staleRegisteredAfter = null)
    {
        _doneToIdleAfter = doneToIdleAfter ?? TimeSpan.FromSeconds(30);
        _removeIdleAfter = removeIdleAfter ?? TimeSpan.FromSeconds(600);
        _staleActiveAfter = staleActiveAfter ?? TimeSpan.FromSeconds(300);
        _staleRegisteredAfter = staleRegisteredAfter ?? TimeSpan.FromSeconds(90);
    }

    public IReadOnlyList<AgentSession> Sessions => _byId.Values.ToArray();

    public IReadOnlyList<AgentSession> Sorted => _byId.Values
        .OrderByDescending(session => session.State.AttentionPriority())
        .ThenByDescending(session => session.UpdatedAt)
        .ToArray();

    public void Clear() => _byId.Clear();

    public void Remove(string id) => _byId.Remove(id);

    public void UpdateTitle(string id, string title)
    {
        if (!_byId.TryGetValue(id, out var session))
        {
            return;
        }

        _byId[id] = session with { Title = title };
    }

    public void RefineState(string id, AgentState expected, AgentState refined, DateTimeOffset since)
    {
        if (!_byId.TryGetValue(id, out var session) || session.State != expected || session.StateSince != since)
        {
            return;
        }

        _byId[id] = session with { State = refined };
    }

    public AgentSession? Apply(AgentEvent evt, DateTimeOffset now)
    {
        if (StateMapper.IsSessionEnd(evt.AgentKind, evt.EventName))
        {
            _byId.Remove(evt.SessionId);
            return null;
        }

        var state = StateMapper.StateFor(evt.AgentKind, evt.EventName);
        if (state is null)
        {
            return null;
        }

        if (_byId.TryGetValue(evt.SessionId, out var existing))
        {
            var stateSince = existing.State == state.Value ? existing.StateSince : now;
            var updated = existing with
            {
                State = state.Value,
                UpdatedAt = now,
                StateSince = stateSince,
                Project = evt.Project ?? existing.Project,
                Message = evt.Message
            };
            _byId[evt.SessionId] = updated;
            return updated;
        }

        var session = new AgentSession(
            id: evt.SessionId,
            agentKind: evt.AgentKind,
            state: state.Value,
            source: AgentSource.Hook,
            updatedAt: now,
            project: evt.Project,
            message: evt.Message);
        _byId[evt.SessionId] = session;
        return session;
    }

    public void Prune(DateTimeOffset now)
    {
        foreach (var (id, session) in _byId.ToArray())
        {
            var quiet = now - session.UpdatedAt;
            switch (session.State)
            {
                case AgentState.Done when quiet >= _doneToIdleAfter:
                    _byId[id] = session with
                    {
                        State = AgentState.Idle,
                        UpdatedAt = now,
                        StateSince = now
                    };
                    break;
                case AgentState.Idle when quiet >= _removeIdleAfter:
                    _byId.Remove(id);
                    break;
                case AgentState.Registered when quiet >= _staleRegisteredAfter:
                    _byId.Remove(id);
                    break;
                case AgentState.Working or AgentState.Waiting when quiet >= _staleActiveAfter:
                    _byId.Remove(id);
                    break;
            }
        }
    }

    public AgentSession? Session(string id) => _byId.GetValueOrDefault(id);
}
