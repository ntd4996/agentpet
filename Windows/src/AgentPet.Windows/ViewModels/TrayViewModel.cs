using System.Collections.ObjectModel;
using System.IO;
using AgentPet.Core.Models;
using AgentPet.Core.Text;

namespace AgentPet.Windows.ViewModels;

public sealed class TrayViewModel : ViewModelBase
{
    private string _summary = "Đang chờ nhắc việc";

    public ObservableCollection<SessionRowViewModel> Sessions { get; } = new();

    public string Summary
    {
        get => _summary;
        private set => SetProperty(ref _summary, value);
    }

    public void UpdateSessions(IEnumerable<AgentSession> sessions)
    {
        var visible = sessions
            .Where(session => session.State is not AgentState.Idle)
            .ToArray();
        var sorted = TickerFormatter.Sorted(visible);

        Sessions.Clear();
        foreach (var session in sorted)
        {
            Sessions.Add(new SessionRowViewModel(session));
        }

        Summary = Sessions.Count == 0
            ? "Đang chờ nhắc việc"
            : $"{Sessions.Count} phiên Agent đang chạy";
    }
}

public sealed class SessionRowViewModel
{
    public SessionRowViewModel(AgentSession session)
    {
        Id = session.Id;
        Agent = TickerFormatter.AgentLabel(session.AgentKind);
        State = session.State.WireName();
        Project = ProjectLabel(session.Project) ?? session.Id;
        Message = string.IsNullOrWhiteSpace(session.Message) ? StateTitle(session.State) : session.Message!;
        UpdatedAt = session.UpdatedAt.ToLocalTime().ToString("HH:mm:ss");
        Line = TickerFormatter.Line(session);
    }

    public string Id { get; }
    public string Agent { get; }
    public string State { get; }
    public string Project { get; }
    public string Message { get; }
    public string UpdatedAt { get; }
    public string Line { get; }

    private static string? ProjectLabel(string? project)
    {
        if (string.IsNullOrWhiteSpace(project))
        {
            return null;
        }

        var trimmed = project.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar, '/', '\\');
        return string.IsNullOrWhiteSpace(trimmed) ? null : Path.GetFileName(trimmed);
    }

    private static string StateTitle(AgentState state) => state switch
    {
        AgentState.Waiting => "Cần bạn xử lý",
        AgentState.Working => "Đang làm việc",
        AgentState.Done => "Đã xong",
        AgentState.Registered => "Đang bắt đầu",
        _ => "Rảnh"
    };
}
