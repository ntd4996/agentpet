namespace AgentPet.Windows.Models;

public sealed class ReminderSettings
{
    public bool RemindersEnabled { get; set; } = true;
    public ReminderSlotSettings Morning { get; set; } = ReminderSlotSettings.MorningDefaults();
    public ReminderSlotSettings Afternoon { get; set; } = ReminderSlotSettings.AfternoonDefaults();
    public int PetSize { get; set; } = 170;
    public bool ReminderBubblesEnabled { get; set; } = true;
    public int BubbleDurationSeconds { get; set; } = 12;
    public int BubbleWidth { get; set; } = 340;
    public string UserName { get; set; } = "bạn";
    public string IdleBubbleText { get; set; } = "Mình sẽ nhắc bạn đúng giờ nhé.";
    public string GreetingPhrase { get; set; } = "Chào {name}, hôm nay mình cùng làm việc nhé!";
    public string ReminderPhrase { get; set; } = "{name} ơi, đến giờ: {task}";
    public string EncouragementPhrase { get; set; } = "Cố lên {name}, làm từng việc một thôi!";

    public static ReminderSettings Defaults() => new();

    public void Normalize()
    {
        Morning ??= ReminderSlotSettings.MorningDefaults();
        Afternoon ??= ReminderSlotSettings.AfternoonDefaults();
        Morning.Normalize(ReminderSlotSettings.MorningDefaults());
        Afternoon.Normalize(ReminderSlotSettings.AfternoonDefaults());
        PetSize = Math.Clamp(PetSize, 96, 260);
        BubbleDurationSeconds = Math.Clamp(BubbleDurationSeconds, 3, 60);
        BubbleWidth = Math.Clamp(BubbleWidth, 260, 520);
        if (string.IsNullOrWhiteSpace(UserName))
        {
            UserName = "bạn";
        }

        if (string.IsNullOrWhiteSpace(IdleBubbleText))
        {
            IdleBubbleText = "Mình sẽ nhắc bạn đúng giờ nhé.";
        }

        if (string.IsNullOrWhiteSpace(GreetingPhrase))
        {
            GreetingPhrase = "Chào {name}, hôm nay mình cùng làm việc nhé!";
        }

        if (string.IsNullOrWhiteSpace(ReminderPhrase))
        {
            ReminderPhrase = "{name} ơi, đến giờ: {task}";
        }

        if (string.IsNullOrWhiteSpace(EncouragementPhrase))
        {
            EncouragementPhrase = "Cố lên {name}, làm từng việc một thôi!";
        }
    }
}

public sealed class ReminderSlotSettings
{
    public bool Enabled { get; set; } = true;
    public List<ReminderTaskSettings> Tasks { get; set; } = [];

    // Backward-compatible fields from the first MVP. Normalize migrates these into Tasks.
    public string TaskText { get; set; } = string.Empty;
    public string FromTime { get; set; } = string.Empty;
    public string ToTime { get; set; } = string.Empty;

    public static ReminderSlotSettings MorningDefaults() => new()
    {
        Enabled = true,
        Tasks =
        [
            new ReminderTaskSettings { Enabled = true, TaskText = "Uống nước và xem kế hoạch buổi sáng.", FromTime = "08:00", ToTime = "09:00" },
            new ReminderTaskSettings { Enabled = true, TaskText = "Tập trung xử lý việc quan trọng nhất.", FromTime = "09:00", ToTime = "11:00" }
        ]
    };

    public static ReminderSlotSettings AfternoonDefaults() => new()
    {
        Enabled = true,
        Tasks =
        [
            new ReminderTaskSettings { Enabled = true, TaskText = "Đứng dậy vận động và uống nước.", FromTime = "14:00", ToTime = "15:00" },
            new ReminderTaskSettings { Enabled = true, TaskText = "Kiểm tra việc còn lại trước khi kết thúc ngày.", FromTime = "16:00", ToTime = "17:00" }
        ]
    };

    public void Normalize(ReminderSlotSettings defaults)
    {
        if ((Tasks is null || Tasks.Count == 0) && !string.IsNullOrWhiteSpace(TaskText))
        {
            Tasks =
            [
                new ReminderTaskSettings
                {
                    Enabled = Enabled,
                    TaskText = TaskText,
                    FromTime = string.IsNullOrWhiteSpace(FromTime) ? defaults.Tasks[0].FromTime : FromTime,
                    ToTime = string.IsNullOrWhiteSpace(ToTime) ? defaults.Tasks[0].ToTime : ToTime
                }
            ];
        }

        if (Tasks is null || Tasks.Count == 0)
        {
            Tasks = defaults.Tasks.Select(task => task.Clone()).ToList();
        }

        foreach (var task in Tasks)
        {
            task.Normalize(defaults.Tasks[0]);
        }
    }
}

public sealed class ReminderTaskSettings
{
    public bool Enabled { get; set; } = true;
    public string TaskText { get; set; } = string.Empty;
    public string FromTime { get; set; } = "08:00";
    public string ToTime { get; set; } = "09:00";

    public ReminderTaskSettings Clone() => new()
    {
        Enabled = Enabled,
        TaskText = TaskText,
        FromTime = FromTime,
        ToTime = ToTime
    };

    public void Normalize(ReminderTaskSettings fallback)
    {
        if (string.IsNullOrWhiteSpace(TaskText))
        {
            TaskText = fallback.TaskText;
        }

        if (string.IsNullOrWhiteSpace(FromTime))
        {
            FromTime = fallback.FromTime;
        }

        if (string.IsNullOrWhiteSpace(ToTime))
        {
            ToTime = fallback.ToTime;
        }
    }
}
