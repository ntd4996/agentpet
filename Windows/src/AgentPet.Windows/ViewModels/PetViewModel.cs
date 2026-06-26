using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using AgentPet.Core.Models;
using AgentPet.Core.State;
using AgentPet.Core.Text;
using AgentPet.Windows.Services;

namespace AgentPet.Windows.ViewModels;

public sealed class PetViewModel : ViewModelBase
{
    private const int MaxBubbleRows = 3;

    private readonly DispatcherTimer _reminderBubbleTimer;
    private string? _temporaryMood;
    private AgentSession[] _latestSessions = [];
    private string _mood = "idle";
    private string? _previewMood;
    private string? _selectedPetSpritesheet;
    private int _petSize = 170;
    private int _bubbleDurationSeconds = 12;
    private int _bubbleWidth = 340;
    private bool _reminderBubblesEnabled = true;
    private bool _reminderBubbleActive;
    private Visibility _bubbleVisibility = Visibility.Collapsed;
    private string _footerText = string.Empty;
    private Visibility _footerVisibility = Visibility.Collapsed;

    public PetViewModel()
    {
        _reminderBubbleTimer = new DispatcherTimer();
        _reminderBubbleTimer.Tick += (_, _) => HideReminderBubble();
    }

    public ObservableCollection<PetBubbleRowViewModel> BubbleRows { get; } = new();

    public string Mood
    {
        get => _mood;
        private set => SetProperty(ref _mood, value);
    }

    public string? SelectedPetSpritesheet
    {
        get => _selectedPetSpritesheet;
        private set => SetProperty(ref _selectedPetSpritesheet, value);
    }

    public int PetSize
    {
        get => _petSize;
        private set => SetProperty(ref _petSize, value);
    }

    public Visibility BubbleVisibility
    {
        get => _bubbleVisibility;
        private set => SetProperty(ref _bubbleVisibility, value);
    }

    public int BubbleWidth
    {
        get => _bubbleWidth;
        private set
        {
            if (SetProperty(ref _bubbleWidth, value))
            {
                OnPropertyChanged(nameof(BubbleContentWidth));
                OnPropertyChanged(nameof(PetWindowWidth));
            }
        }
    }

    public int BubbleContentWidth => Math.Max(160, BubbleWidth - 30);
    public int PetWindowWidth => Math.Max(420, BubbleWidth + 80);

    public string FooterText
    {
        get => _footerText;
        private set => SetProperty(ref _footerText, value);
    }

    public Visibility FooterVisibility
    {
        get => _footerVisibility;
        private set => SetProperty(ref _footerVisibility, value);
    }

    public void SelectPetSpritesheet(string? spritesheetPath)
    {
        SelectedPetSpritesheet = spritesheetPath;
    }

    public void SetPreviewMood(string? mood)
    {
        _previewMood = string.IsNullOrWhiteSpace(mood) ? null : mood;
        RefreshMood();
    }

    public void SetPetSize(int size)
    {
        PetSize = Math.Clamp(size, 96, 260);
    }

    public void ConfigureBubbles(bool reminderBubblesEnabled, int bubbleDurationSeconds, int bubbleWidth)
    {
        _reminderBubblesEnabled = reminderBubblesEnabled;
        _bubbleDurationSeconds = Math.Clamp(bubbleDurationSeconds, 3, 60);
        SetBubbleWidth(bubbleWidth);
    }

    public void SetBubbleWidth(int width)
    {
        BubbleWidth = Math.Clamp(width, 260, 520);
    }

    public void ShowReminder(string message)
    {
        ShowBubble("Nhắc việc", message, "waiting", _bubbleDurationSeconds);
    }

    public void ShowReminder(ReminderNotification notification)
    {
        var mood = notification.Kind switch
        {
            ReminderNotificationKind.NextTask => "working",
            ReminderNotificationKind.Completed or ReminderNotificationKind.CompletedEarly or ReminderNotificationKind.AllCompleted => "celebrate",
            ReminderNotificationKind.Info => "done",
            _ => "waiting"
        };
        ShowBubble(notification.Title, notification.Message, mood, _bubbleDurationSeconds);
    }

    private void ShowBubble(string title, string message, string mood, int seconds)
    {
        if (!_reminderBubblesEnabled || string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        _reminderBubbleActive = true;
        _temporaryMood = mood;
        _reminderBubbleTimer.Stop();
        _reminderBubbleTimer.Interval = TimeSpan.FromSeconds(Math.Clamp(seconds, 3, 60));
        BubbleRows.Clear();
        BubbleRows.Add(PetBubbleRowViewModel.Manual(title, message.Trim(), DotColor(AgentState.Waiting)));
        FooterText = string.Empty;
        FooterVisibility = Visibility.Collapsed;
        BubbleVisibility = Visibility.Visible;
        Mood = _previewMood ?? _temporaryMood;
        _reminderBubbleTimer.Start();
    }

    public void UpdateSessions(IEnumerable<AgentSession> sessions)
    {
        _latestSessions = sessions.ToArray();
        if (_reminderBubbleActive)
        {
            return;
        }

        RenderSessions(_latestSessions);
    }

    private void HideReminderBubble()
    {
        _reminderBubbleTimer.Stop();
        _reminderBubbleActive = false;
        _temporaryMood = null;
        RenderSessions(_latestSessions);
    }

    private void RenderSessions(IEnumerable<AgentSession> sessions)
    {
        var snapshot = sessions.ToArray();
        var visible = TickerFormatter.Sorted(snapshot.Where(session => session.State is not AgentState.Idle)).ToArray();

        RefreshMood(snapshot);

        BubbleRows.Clear();
        foreach (var session in visible.Take(MaxBubbleRows))
        {
            BubbleRows.Add(new PetBubbleRowViewModel(session));
        }

        var hidden = Math.Max(0, visible.Length - MaxBubbleRows);
        FooterText = hidden > 0 ? $"+{hidden} nữa" : string.Empty;
        FooterVisibility = hidden > 0 ? Visibility.Visible : Visibility.Collapsed;
        BubbleVisibility = visible.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshMood(AgentSession[]? sessions = null)
    {
        Mood = string.IsNullOrWhiteSpace(_previewMood)
            ? MoodResolver.Aggregate(sessions ?? _latestSessions).DisplayName()
            : _previewMood;
    }

    private static SolidColorBrush DotColor(AgentState state)
    {
        var color = state switch
        {
            AgentState.Waiting => System.Windows.Media.Color.FromRgb(0xF5, 0x9E, 0x0B),
            AgentState.Working or AgentState.Registered => System.Windows.Media.Color.FromRgb(0x3B, 0x82, 0xF6),
            AgentState.Done => System.Windows.Media.Color.FromRgb(0x21, 0xC4, 0x5D),
            _ => System.Windows.Media.Color.FromRgb(0x6B, 0x72, 0x80)
        };
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

public sealed class PetBubbleRowViewModel
{
    public PetBubbleRowViewModel(AgentSession session)
        : this(
            TickerFormatter.AgentLabel(session.AgentKind),
            ProjectLabel(session.Project) ?? session.Id,
            string.IsNullOrWhiteSpace(session.Message) ? StateMessage(session.State) : session.Message!,
            DotColor(session.State),
            session.State == AgentState.Waiting ? DotColor(session.State) : new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x11, 0x18, 0x27)))
    {
    }

    private PetBubbleRowViewModel(string agent, string project, string message, System.Windows.Media.Brush dotBrush, System.Windows.Media.Brush messageBrush)
    {
        Agent = agent;
        Project = project;
        Message = message;
        DotBrush = dotBrush;
        MessageBrush = messageBrush;
    }

    public string Agent { get; }
    public string Project { get; }
    public string Message { get; }
    public System.Windows.Media.Brush DotBrush { get; }
    public System.Windows.Media.Brush MessageBrush { get; }

    public static PetBubbleRowViewModel Manual(string title, string message, System.Windows.Media.Brush dotBrush)
    {
        return new PetBubbleRowViewModel(title, string.Empty, message, dotBrush, new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x11, 0x18, 0x27)));
    }

    private static string? ProjectLabel(string? project)
    {
        if (string.IsNullOrWhiteSpace(project))
        {
            return null;
        }

        var trimmed = project.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar, '/', '\\');
        return string.IsNullOrWhiteSpace(trimmed) ? null : Path.GetFileName(trimmed);
    }

    private static string StateMessage(AgentState state) => state switch
    {
        AgentState.Waiting => "Cần bạn xử lý",
        AgentState.Working => "Đang làm việc…",
        AgentState.Done => "Đã xong",
        AgentState.Registered => "Đang bắt đầu…",
        _ => "Rảnh"
    };

    private static SolidColorBrush DotColor(AgentState state)
    {
        var color = state switch
        {
            AgentState.Waiting => System.Windows.Media.Color.FromRgb(0xF5, 0x9E, 0x0B),
            AgentState.Working or AgentState.Registered => System.Windows.Media.Color.FromRgb(0x3B, 0x82, 0xF6),
            AgentState.Done => System.Windows.Media.Color.FromRgb(0x21, 0xC4, 0x5D),
            _ => System.Windows.Media.Color.FromRgb(0x6B, 0x72, 0x80)
        };
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
