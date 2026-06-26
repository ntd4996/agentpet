using System.Windows.Threading;
using AgentPet.Windows.Models;

namespace AgentPet.Windows.Services;

public sealed class ReminderSchedulerService : IDisposable
{
    private static readonly int[] WarningMinutes = [15, 10, 5];

    private readonly DispatcherTimer _timer;
    private readonly HashSet<string> _completedKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _warningKeys = new(StringComparer.OrdinalIgnoreCase);
    private ReminderSettings _settings;
    private List<ScheduledReminderTask> _tasks = [];
    private DateOnly _taskDay = DateOnly.FromDateTime(DateTime.Now);
    private int _currentIndex = -1;
    private bool _disposed;

    public ReminderSchedulerService(ReminderSettings settings)
    {
        _settings = settings;
        _settings.Normalize();
        RebuildTasks();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _timer.Tick += (_, _) => CheckNow();
    }

    public event Action<ReminderNotification>? ReminderDue;

    public void Start()
    {
        _timer.Start();
        CheckNow();
    }

    public void Stop()
    {
        _timer.Stop();
    }

    public void UpdateSettings(ReminderSettings settings)
    {
        _settings = settings;
        _settings.Normalize();
        _completedKeys.Clear();
        _warningKeys.Clear();
        _currentIndex = -1;
        RebuildTasks();
        CheckNow();
    }

    public ReminderNotification ShowCurrentTask()
    {
        var now = DateTime.Now;
        EnsureCurrentDay(now);
        var task = CurrentTask(now);
        return task is null
            ? IdleNotification()
            : TaskNotification("Việc đang làm", task, ReminderNotificationKind.CurrentTask);
    }

    public ReminderNotification ShowNextTask()
    {
        var now = DateTime.Now;
        EnsureCurrentDay(now);
        var next = NextTask(now, includeFuture: true);
        if (next is null)
        {
            return AllDoneNotification(now);
        }

        _currentIndex = next.Index;
        return TaskNotification("Việc kế tiếp", next, ReminderNotificationKind.NextTask);
    }

    public ReminderNotification CompleteCurrentAndAdvance()
    {
        var now = DateTime.Now;
        EnsureCurrentDay(now);
        var current = CurrentTask(now);
        if (current is null)
        {
            return IdleNotification();
        }

        _completedKeys.Add(current.Key(_taskDay));
        var next = NextTask(now, includeFuture: true);
        var completedEarly = TimeOnly.FromDateTime(now) < current.To;
        if (next is null)
        {
            return AllDoneNotification(now, current, completedEarly);
        }

        _currentIndex = next.Index;
        var message = $"Bạn đã hoàn thành công việc \"{current.TaskText}\" trong khoảng thời gian {FormatWindow(current)}. " +
            $"Bắt đầu công việc kế tiếp là từ {next.From:HH\\:mm} đến {next.To:HH\\:mm}: {next.TaskText}";
        return new ReminderNotification(
            completedEarly ? "Hoàn thành sớm" : "Đã hoàn thành",
            message,
            completedEarly ? ReminderNotificationKind.CompletedEarly : ReminderNotificationKind.Completed);
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

    private void CheckNow()
    {
        if (!_settings.RemindersEnabled || !_settings.ReminderBubblesEnabled)
        {
            return;
        }

        var now = DateTime.Now;
        EnsureCurrentDay(now);
        var task = CurrentTask(now);
        if (task is null)
        {
            return;
        }

        var time = TimeOnly.FromDateTime(now);
        if (!IsAvailable(task, time, includeFuture: false))
        {
            return;
        }

        var warning = WarningNotificationIfDue(task, now);
        ReminderDue?.Invoke(warning ?? TaskNotification("Nhắc việc", task, ReminderNotificationKind.CurrentTask));
    }

    private ReminderNotification? WarningNotificationIfDue(ScheduledReminderTask task, DateTime now)
    {
        var remaining = task.To.ToTimeSpan() - TimeOnly.FromDateTime(now).ToTimeSpan();
        if (remaining <= TimeSpan.Zero)
        {
            return null;
        }

        var dueMinute = WarningMinutes.OrderBy(minute => minute).FirstOrDefault(minute => remaining <= TimeSpan.FromMinutes(minute));
        if (dueMinute == 0)
        {
            return null;
        }

        var warningKey = $"{task.Key(_taskDay)}:warn:{dueMinute}";
        if (!_warningKeys.Add(warningKey))
        {
            return null;
        }

        return new ReminderNotification(
            $"Còn {dueMinute} phút",
            $"Còn {dueMinute} phút để hoàn thành \"{task.TaskText}\" trong khung giờ {FormatWindow(task)}. Nếu xong rồi, click 3 lần vào pet để xác nhận nhé.",
            ReminderNotificationKind.Warning);
    }

    private ScheduledReminderTask? CurrentTask(DateTime now)
    {
        if (_tasks.Count == 0)
        {
            return null;
        }

        if (IsUsableCurrent(now, includeFuture: true))
        {
            return _tasks[_currentIndex];
        }

        var time = TimeOnly.FromDateTime(now);
        var active = _tasks.FirstOrDefault(task => IsAvailable(task, time, includeFuture: false));
        var next = active ?? _tasks.FirstOrDefault(task => IsAvailable(task, time, includeFuture: true));
        _currentIndex = next?.Index ?? -1;
        return next;
    }

    private ScheduledReminderTask? NextTask(DateTime now, bool includeFuture)
    {
        if (_tasks.Count == 0)
        {
            return null;
        }

        var time = TimeOnly.FromDateTime(now);
        var start = _currentIndex < 0 ? -1 : _currentIndex;
        var ordered = _tasks.Skip(start + 1).Concat(_tasks.Take(start + 1));
        return ordered.FirstOrDefault(task => IsAvailable(task, time, includeFuture));
    }

    private bool IsUsableCurrent(DateTime now, bool includeFuture)
    {
        if (_currentIndex < 0 || _currentIndex >= _tasks.Count)
        {
            return false;
        }

        return IsAvailable(_tasks[_currentIndex], TimeOnly.FromDateTime(now), includeFuture);
    }

    private bool IsAvailable(ScheduledReminderTask task, TimeOnly time, bool includeFuture)
    {
        if (_completedKeys.Contains(task.Key(_taskDay)))
        {
            return false;
        }

        return includeFuture ? time <= task.To : task.From <= time && time <= task.To;
    }

    private ReminderNotification TaskNotification(string title, ScheduledReminderTask task, ReminderNotificationKind kind)
    {
        return new ReminderNotification(title, $"{FormatWindow(task)} — {FormatReminder(task.TaskText)}", kind);
    }

    private ReminderNotification IdleNotification()
    {
        return new ReminderNotification("Chưa có việc", "Hiện chưa có việc nào trong khung giờ nhắc. Mình sẽ nhắc khi đến giờ nhé.", ReminderNotificationKind.Info);
    }

    private ReminderNotification AllDoneNotification(DateTime now, ScheduledReminderTask? completedTask = null, bool completedEarly = false)
    {
        if (_tasks.Count == 0)
        {
            return new ReminderNotification("Hoàn tất", "Hôm nay chưa có việc nào được bật trong lịch nhắc.", ReminderNotificationKind.Info);
        }

        var first = _tasks.First();
        var last = _tasks.Last();
        var elapsed = TimeOnly.FromDateTime(now).ToTimeSpan() - first.From.ToTimeSpan();
        if (elapsed < TimeSpan.Zero)
        {
            elapsed = TimeSpan.Zero;
        }

        var spare = last.To.ToTimeSpan() - TimeOnly.FromDateTime(now).ToTimeSpan();
        if (spare < TimeSpan.Zero)
        {
            spare = TimeSpan.Zero;
        }

        var prefix = completedTask is null
            ? "Bạn đã hoàn tất toàn bộ công việc."
            : $"Bạn đã hoàn thành công việc \"{completedTask.TaskText}\" trong khoảng thời gian {FormatWindow(completedTask)}. Bạn đã hoàn tất toàn bộ công việc.";
        var message = $"{prefix} Tổng thời gian làm: {FormatDuration(elapsed)}. Thời gian rảnh còn dư: {FormatDuration(spare)}.";
        return new ReminderNotification(
            completedEarly ? "Hoàn thành sớm" : "Hoàn tất công việc",
            message,
            completedEarly ? ReminderNotificationKind.CompletedEarly : ReminderNotificationKind.AllCompleted);
    }

    private void EnsureCurrentDay(DateTime now)
    {
        var today = DateOnly.FromDateTime(now);
        if (today == _taskDay)
        {
            return;
        }

        _taskDay = today;
        _completedKeys.Clear();
        _warningKeys.Clear();
        _currentIndex = -1;
        RebuildTasks();
    }

    private void RebuildTasks()
    {
        var items = new List<ScheduledReminderTask>();
        AddSlotTasks(items, "morning", _settings.Morning);
        AddSlotTasks(items, "afternoon", _settings.Afternoon);
        _tasks = items.OrderBy(task => task.From).ThenBy(task => task.To).Select((task, index) => task with { Index = index }).ToList();
    }

    private static void AddSlotTasks(List<ScheduledReminderTask> items, string slotName, ReminderSlotSettings slot)
    {
        if (!slot.Enabled)
        {
            return;
        }

        for (var index = 0; index < slot.Tasks.Count; index++)
        {
            var task = slot.Tasks[index];
            if (!ShouldUse(task, out var from, out var to))
            {
                continue;
            }

            items.Add(new ScheduledReminderTask(slotName, index, items.Count, task.TaskText.Trim(), from, to));
        }
    }

    private string FormatReminder(string task)
    {
        var name = string.IsNullOrWhiteSpace(_settings.UserName) ? "bạn" : _settings.UserName.Trim();
        var template = string.IsNullOrWhiteSpace(_settings.ReminderPhrase) ? "{name} ơi, đến giờ: {task}" : _settings.ReminderPhrase;
        return template.Replace("{name}", name, StringComparison.OrdinalIgnoreCase)
            .Replace("{task}", task.Trim(), StringComparison.OrdinalIgnoreCase)
            .Replace("bạn", name, StringComparison.OrdinalIgnoreCase);
    }

    private static string FormatWindow(ScheduledReminderTask task) => $"từ {task.From:HH\\:mm} đến {task.To:HH\\:mm}";

    private static string FormatDuration(TimeSpan duration)
    {
        var totalMinutes = Math.Max(0, (int)Math.Round(duration.TotalMinutes));
        var hours = totalMinutes / 60;
        var minutes = totalMinutes % 60;
        if (hours > 0 && minutes > 0)
        {
            return $"{hours} giờ {minutes} phút";
        }

        if (hours > 0)
        {
            return $"{hours} giờ";
        }

        return $"{minutes} phút";
    }

    private static bool ShouldUse(ReminderTaskSettings task, out TimeOnly from, out TimeOnly to)
    {
        from = default;
        to = default;
        if (!task.Enabled || string.IsNullOrWhiteSpace(task.TaskText))
        {
            return false;
        }

        return TryParseWindow(task, out from, out to);
    }

    public static bool TryParseWindow(ReminderTaskSettings task, out TimeOnly from, out TimeOnly to)
    {
        from = default;
        to = default;
        if (!TimeOnly.TryParse(task.FromTime, out var parsedFrom) || !TimeOnly.TryParse(task.ToTime, out var parsedTo))
        {
            return false;
        }

        from = parsedFrom;
        to = parsedTo;
        return from <= to;
    }

    private sealed record ScheduledReminderTask(string SlotName, int SlotIndex, int Index, string TaskText, TimeOnly From, TimeOnly To)
    {
        public string Key(DateOnly day) => $"{day:yyyyMMdd}:{SlotName}:{SlotIndex}:{From:HH\\:mm}:{To:HH\\:mm}:{TaskText}";
    }
}

public sealed record ReminderNotification(string Title, string Message, ReminderNotificationKind Kind);

public enum ReminderNotificationKind
{
    Info,
    CurrentTask,
    NextTask,
    Warning,
    Completed,
    CompletedEarly,
    AllCompleted
}
