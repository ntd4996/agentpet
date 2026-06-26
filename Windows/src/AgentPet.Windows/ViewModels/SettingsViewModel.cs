using System.Collections.ObjectModel;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using AgentPet.Windows.Models;
using AgentPet.Windows.Services;

namespace AgentPet.Windows.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private const int PageSize = 8;
    private static readonly string[] PreviewMoods = ["idle", "working", "waiting", "done", "celebrate"];

    private readonly List<PetCardViewModel> _allPets;
    private readonly ReminderSettingsService _settingsService;
    private readonly UpdateService _updateService = new();
    private readonly DispatcherTimer _previewTimer;
    private string _searchText = string.Empty;
    private string _previewMood = PreviewMoods[0];
    private string _selectedTab = "general";
    private int _previewMoodIndex;
    private int _currentPage;
    private PetCardViewModel? _selectedPet;
    private string _statusText = "Sẵn sàng nhắc việc";
    private bool _remindersEnabled;
    private bool _morningEnabled;
    private bool _afternoonEnabled;
    private int _petSize = 170;
    private bool _reminderBubblesEnabled = true;
    private int _bubbleDurationSeconds = 12;
    private int _bubbleWidth = 340;
    private string _userName = "bạn";
    private string _idleBubbleText = string.Empty;
    private string _greetingPhrase = string.Empty;
    private string _reminderPhrase = string.Empty;
    private string _encouragementPhrase = string.Empty;
    private bool _isCheckingForUpdates;

    public SettingsViewModel()
        : this(new PetCatalogService(), new ReminderSettingsService())
    {
    }

    public SettingsViewModel(PetCatalogService catalog, ReminderSettingsService settingsService)
        : this(catalog, settingsService, settingsService.Load())
    {
    }

    public SettingsViewModel(PetCatalogService catalog, ReminderSettingsService settingsService, ReminderSettings settings)
    {
        _settingsService = settingsService;
        settings.Normalize();
        ApplySettings(settings);

        _allPets = catalog.Load().Select(item => new PetCardViewModel(item)).ToList();
        _selectedPet = _allPets.FirstOrDefault();
        if (_selectedPet is not null)
        {
            _selectedPet.IsSelected = true;
        }

        SelectGeneralTabCommand = new RelayCommand(() => SelectedTab = "general");
        SelectPetTabCommand = new RelayCommand(() => SelectedTab = "pet");
        SelectBubbleTabCommand = new RelayCommand(() => SelectedTab = "bubble");
        SelectAboutTabCommand = new RelayCommand(() => SelectedTab = "about");
        SelectPetCommand = new RelayCommand(parameter =>
        {
            if (parameter is PetCardViewModel pet)
            {
                SelectPet(pet);
            }
        });
        PreviousPageCommand = new RelayCommand(PreviousPage, () => CanGoPrevious);
        NextPageCommand = new RelayCommand(NextPage, () => CanGoNext);
        BrowseCommand = new RelayCommand(() => StatusText = "Tính năng mở thư mục thú cưng sẽ được bổ sung sau.");
        CreateCommand = new RelayCommand(() => StatusText = "Tính năng tạo thú cưng sẽ được bổ sung sau.");
        TogglePreviewCommand = new RelayCommand(ToggleLivePreview);
        SaveSettingsCommand = new RelayCommand(SaveSettings);
        TestReminderCommand = new RelayCommand(() => ReminderPreviewRequested?.Invoke(FormatPhrase(ReminderPhrase, FirstTaskText)));
        PreviewBubbleCommand = new RelayCommand(() => BubblePreviewRequested?.Invoke(string.IsNullOrWhiteSpace(IdleBubbleText) ? FormatPhrase(GreetingPhrase, string.Empty) : ApplyName(IdleBubbleText.Trim())));
        CheckForUpdatesCommand = new RelayCommand(CheckForUpdates);
        AddMorningTaskCommand = new RelayCommand(() => MorningTasks.Add(ReminderTaskViewModel.Default("Việc buổi sáng", "08:00", "09:00")));
        AddAfternoonTaskCommand = new RelayCommand(() => AfternoonTasks.Add(ReminderTaskViewModel.Default("Việc buổi chiều", "14:00", "15:00")));
        RemoveMorningTaskCommand = new RelayCommand(parameter => RemoveTask(MorningTasks, parameter));
        RemoveAfternoonTaskCommand = new RelayCommand(parameter => RemoveTask(AfternoonTasks, parameter));

        _previewTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _previewTimer.Tick += (_, _) => AdvancePreviewMood();
        _previewTimer.Start();

        RebuildPage();
    }

    public event Action<string?>? SelectedPetSpritesheetChanged;
    public event Action<string?>? PreviewMoodChanged;
    public event Action<ReminderSettings>? SettingsSaved;
    public event Action<int>? PetSizeChanged;
    public event Action<int>? BubbleWidthChanged;
    public event Action<string>? ReminderPreviewRequested;
    public event Action<string>? BubblePreviewRequested;

    public ObservableCollection<PetCardViewModel> PagedPets { get; } = new();
    public ObservableCollection<ReminderTaskViewModel> MorningTasks { get; } = new();
    public ObservableCollection<ReminderTaskViewModel> AfternoonTasks { get; } = new();
    public IReadOnlyList<string> TimeOptions { get; } = Enumerable.Range(0, 24 * 4).Select(i => TimeOnly.MinValue.AddMinutes(i * 15).ToString("HH:mm")).ToArray();

    public ICommand SelectGeneralTabCommand { get; }
    public ICommand SelectPetTabCommand { get; }
    public ICommand SelectBubbleTabCommand { get; }
    public ICommand SelectAboutTabCommand { get; }
    public ICommand SelectPetCommand { get; }
    public RelayCommand PreviousPageCommand { get; }
    public RelayCommand NextPageCommand { get; }
    public ICommand BrowseCommand { get; }
    public ICommand CreateCommand { get; }
    public ICommand TogglePreviewCommand { get; }
    public ICommand SaveSettingsCommand { get; }
    public ICommand TestReminderCommand { get; }
    public ICommand PreviewBubbleCommand { get; }
    public ICommand CheckForUpdatesCommand { get; }
    public ICommand AddMorningTaskCommand { get; }
    public ICommand AddAfternoonTaskCommand { get; }
    public ICommand RemoveMorningTaskCommand { get; }
    public ICommand RemoveAfternoonTaskCommand { get; }

    public string SelectedTab
    {
        get => _selectedTab;
        private set
        {
            if (SetProperty(ref _selectedTab, value))
            {
                OnPropertyChanged(nameof(GeneralTabVisibility));
                OnPropertyChanged(nameof(PetTabVisibility));
                OnPropertyChanged(nameof(BubbleTabVisibility));
                OnPropertyChanged(nameof(AboutTabVisibility));
            }
        }
    }

    public Visibility GeneralTabVisibility => SelectedTab == "general" ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PetTabVisibility => SelectedTab == "pet" ? Visibility.Visible : Visibility.Collapsed;
    public Visibility BubbleTabVisibility => SelectedTab == "bubble" ? Visibility.Visible : Visibility.Collapsed;
    public Visibility AboutTabVisibility => SelectedTab == "about" ? Visibility.Visible : Visibility.Collapsed;

    public bool RemindersEnabled { get => _remindersEnabled; set => SetProperty(ref _remindersEnabled, value); }
    public bool MorningEnabled { get => _morningEnabled; set => SetProperty(ref _morningEnabled, value); }
    public bool AfternoonEnabled { get => _afternoonEnabled; set => SetProperty(ref _afternoonEnabled, value); }

    public int PetSize
    {
        get => _petSize;
        set
        {
            var clamped = Math.Clamp(value, 96, 260);
            if (SetProperty(ref _petSize, clamped))
            {
                PetSizeChanged?.Invoke(clamped);
            }
        }
    }

    public bool ReminderBubblesEnabled { get => _reminderBubblesEnabled; set => SetProperty(ref _reminderBubblesEnabled, value); }
    public int BubbleDurationSeconds { get => _bubbleDurationSeconds; set => SetProperty(ref _bubbleDurationSeconds, Math.Clamp(value, 3, 60)); }
    public int BubbleWidth
    {
        get => _bubbleWidth;
        set
        {
            var clamped = Math.Clamp(value, 260, 520);
            if (SetProperty(ref _bubbleWidth, clamped))
            {
                BubbleWidthChanged?.Invoke(clamped);
            }
        }
    }
    public string UserName { get => _userName; set => SetProperty(ref _userName, value); }
    public string IdleBubbleText { get => _idleBubbleText; set => SetProperty(ref _idleBubbleText, value); }
    public string GreetingPhrase { get => _greetingPhrase; set => SetProperty(ref _greetingPhrase, value); }
    public string ReminderPhrase { get => _reminderPhrase; set => SetProperty(ref _reminderPhrase, value); }
    public string EncouragementPhrase { get => _encouragementPhrase; set => SetProperty(ref _encouragementPhrase, value); }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                _currentPage = 0;
                RebuildPage();
            }
        }
    }

    public PetCardViewModel? SelectedPet { get => _selectedPet; private set => SetProperty(ref _selectedPet, value); }
    public string SelectedPetName => SelectedPet?.DisplayName ?? "Chưa chọn thú cưng";
    public string SelectedPetDescription => SelectedPet?.Description ?? "Thêm gói thú cưng vào thư mục AgentPet pets.";
    public string? SelectedPetSpritesheet => SelectedPet?.SpritesheetPath;
    public ImageSource? SelectedPetThumbnail => SelectedPet?.Thumbnail;

    public string PreviewMood
    {
        get => _previewMood;
        private set
        {
            if (SetProperty(ref _previewMood, value))
            {
                PreviewMoodChanged?.Invoke(value);
            }
        }
    }

    public string PreviewButtonText => _previewTimer.IsEnabled ? "Tạm dừng xem thử" : "Xem thử chuyển động";
    public string PageIndicator => $"{CurrentPage + 1} / {PageCount}";

    public int CurrentPage
    {
        get => _currentPage;
        private set
        {
            if (SetProperty(ref _currentPage, value))
            {
                OnPageStateChanged();
            }
        }
    }

    public int PageCount => Math.Max(1, (int)Math.Ceiling((double)FilteredPets.Count / PageSize));
    public bool CanGoPrevious => CurrentPage > 0;
    public bool CanGoNext => CurrentPage < PageCount - 1;
    public string EmptyStateText => FilteredPets.Count == 0 ? "Không tìm thấy thú cưng phù hợp." : string.Empty;
    public string StatusText { get => _statusText; private set => SetProperty(ref _statusText, value); }

    private string FirstTaskText => MorningTasks.FirstOrDefault(task => !string.IsNullOrWhiteSpace(task.TaskText))?.TaskText
        ?? AfternoonTasks.FirstOrDefault(task => !string.IsNullOrWhiteSpace(task.TaskText))?.TaskText
        ?? "một việc cần làm";

    private List<PetCardViewModel> FilteredPets
    {
        get
        {
            if (string.IsNullOrWhiteSpace(SearchText))
            {
                return _allPets;
            }

            var query = SearchText.Trim();
            return _allPets.Where(pet => pet.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        }
    }

    public ReminderSettings CreateSettings()
    {
        var settings = new ReminderSettings
        {
            RemindersEnabled = RemindersEnabled,
            Morning = new ReminderSlotSettings { Enabled = MorningEnabled, Tasks = MorningTasks.Select(task => task.ToSettings()).ToList() },
            Afternoon = new ReminderSlotSettings { Enabled = AfternoonEnabled, Tasks = AfternoonTasks.Select(task => task.ToSettings()).ToList() },
            PetSize = PetSize,
            ReminderBubblesEnabled = ReminderBubblesEnabled,
            BubbleDurationSeconds = BubbleDurationSeconds,
            BubbleWidth = BubbleWidth,
            UserName = UserName,
            IdleBubbleText = IdleBubbleText,
            GreetingPhrase = GreetingPhrase,
            ReminderPhrase = ReminderPhrase,
            EncouragementPhrase = EncouragementPhrase
        };
        settings.Normalize();
        return settings;
    }

    private void ApplySettings(ReminderSettings settings)
    {
        RemindersEnabled = settings.RemindersEnabled;
        MorningEnabled = settings.Morning.Enabled;
        AfternoonEnabled = settings.Afternoon.Enabled;
        MorningTasks.Clear();
        foreach (var task in settings.Morning.Tasks)
        {
            MorningTasks.Add(new ReminderTaskViewModel(task));
        }

        AfternoonTasks.Clear();
        foreach (var task in settings.Afternoon.Tasks)
        {
            AfternoonTasks.Add(new ReminderTaskViewModel(task));
        }

        PetSize = settings.PetSize;
        ReminderBubblesEnabled = settings.ReminderBubblesEnabled;
        BubbleDurationSeconds = settings.BubbleDurationSeconds;
        BubbleWidth = settings.BubbleWidth;
        UserName = settings.UserName;
        IdleBubbleText = settings.IdleBubbleText;
        GreetingPhrase = settings.GreetingPhrase;
        ReminderPhrase = settings.ReminderPhrase;
        EncouragementPhrase = settings.EncouragementPhrase;
    }

    private void SaveSettings()
    {
        var settings = CreateSettings();
        if (!ValidateSlot(settings.Morning, "buổi sáng") || !ValidateSlot(settings.Afternoon, "buổi chiều"))
        {
            return;
        }

        try
        {
            _settingsService.Save(settings);
            SettingsSaved?.Invoke(settings);
            StatusText = "Đã lưu cài đặt nhắc việc.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            StatusText = "Không thể lưu cài đặt. Vui lòng kiểm tra quyền ghi thư mục AgentPet.";
        }
    }

    private bool ValidateSlot(ReminderSlotSettings slot, string label)
    {
        foreach (var task in slot.Tasks)
        {
            if (!ReminderSchedulerService.TryParseWindow(task, out _, out _))
            {
                StatusText = $"Giờ trong {label} không hợp lệ. Vui lòng chọn giờ bắt đầu <= giờ kết thúc.";
                return false;
            }
        }

        return true;
    }

    private string FormatPhrase(string template, string task)
    {
        template = string.IsNullOrWhiteSpace(template) ? "{name} ơi, đến giờ: {task}" : template;
        return ApplyName(template.Replace("{task}", task.Trim(), StringComparison.OrdinalIgnoreCase));
    }

    private string ApplyName(string text)
    {
        var name = string.IsNullOrWhiteSpace(UserName) ? "bạn" : UserName.Trim();
        return text.Replace("{name}", name, StringComparison.OrdinalIgnoreCase)
            .Replace("bạn", name, StringComparison.OrdinalIgnoreCase);
    }

    private async void CheckForUpdates()
    {
        if (_isCheckingForUpdates)
        {
            return;
        }

        _isCheckingForUpdates = true;
        StatusText = "Đang kiểm tra cập nhật…";
        try
        {
            var result = await _updateService.CheckAndDownloadLatestAsync();
            StatusText = result.Message;
            if (!result.HasUpdate || string.IsNullOrWhiteSpace(result.InstallerPath))
            {
                return;
            }

            _updateService.LaunchInstaller(result.InstallerPath);
            System.Windows.Application.Current.Shutdown();
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or UnauthorizedAccessException or JsonException or InvalidOperationException)
        {
            StatusText = "Không thể cập nhật tự động. Vui lòng kiểm tra mạng hoặc GitHub Releases.";
        }
        finally
        {
            _isCheckingForUpdates = false;
        }
    }

    private static void RemoveTask(ObservableCollection<ReminderTaskViewModel> tasks, object? parameter)
    {
        if (parameter is ReminderTaskViewModel task && tasks.Count > 1)
        {
            tasks.Remove(task);
        }
    }

    private void ToggleLivePreview()
    {
        if (_previewTimer.IsEnabled)
        {
            _previewTimer.Stop();
            PreviewMoodChanged?.Invoke(null);
            StatusText = "Đã tạm dừng xem thử chuyển động.";
        }
        else
        {
            _previewTimer.Start();
            PreviewMoodChanged?.Invoke(PreviewMood);
            StatusText = $"Đang xem thử {SelectedPetName}.";
        }

        OnPropertyChanged(nameof(PreviewButtonText));
    }

    private void AdvancePreviewMood()
    {
        _previewMoodIndex = (_previewMoodIndex + 1) % PreviewMoods.Length;
        PreviewMood = PreviewMoods[_previewMoodIndex];
    }

    private void SelectPet(PetCardViewModel pet)
    {
        if (SelectedPet is not null)
        {
            SelectedPet.IsSelected = false;
        }

        pet.IsSelected = true;
        SelectedPet = pet;
        StatusText = $"Đã chọn {pet.DisplayName}.";
        SelectedPetSpritesheetChanged?.Invoke(pet.SpritesheetPath);
        OnPropertyChanged(nameof(SelectedPetName));
        OnPropertyChanged(nameof(SelectedPetDescription));
        OnPropertyChanged(nameof(SelectedPetSpritesheet));
        OnPropertyChanged(nameof(SelectedPetThumbnail));
    }

    private void PreviousPage()
    {
        if (!CanGoPrevious) return;
        CurrentPage--;
        RebuildPage();
    }

    private void NextPage()
    {
        if (!CanGoNext) return;
        CurrentPage++;
        RebuildPage();
    }

    private void RebuildPage()
    {
        var filtered = FilteredPets;
        var maxPage = Math.Max(0, PageCount - 1);
        if (CurrentPage > maxPage)
        {
            CurrentPage = maxPage;
        }

        PagedPets.Clear();
        foreach (var pet in filtered.Skip(CurrentPage * PageSize).Take(PageSize))
        {
            PagedPets.Add(pet);
        }

        OnPageStateChanged();
        OnPropertyChanged(nameof(EmptyStateText));
    }

    private void OnPageStateChanged()
    {
        OnPropertyChanged(nameof(PageCount));
        OnPropertyChanged(nameof(PageIndicator));
        OnPropertyChanged(nameof(CanGoPrevious));
        OnPropertyChanged(nameof(CanGoNext));
        PreviousPageCommand.RaiseCanExecuteChanged();
        NextPageCommand.RaiseCanExecuteChanged();
    }
}

public sealed class ReminderTaskViewModel : ViewModelBase
{
    private bool _enabled;
    private string _taskText = string.Empty;
    private string _fromTime = "08:00";
    private string _toTime = "09:00";

    public ReminderTaskViewModel(ReminderTaskSettings settings)
    {
        _enabled = settings.Enabled;
        _taskText = settings.TaskText;
        _fromTime = settings.FromTime;
        _toTime = settings.ToTime;
    }

    public bool Enabled { get => _enabled; set => SetProperty(ref _enabled, value); }
    public string TaskText { get => _taskText; set => SetProperty(ref _taskText, value); }
    public string FromTime { get => _fromTime; set => SetProperty(ref _fromTime, value); }
    public string ToTime { get => _toTime; set => SetProperty(ref _toTime, value); }

    public static ReminderTaskViewModel Default(string text, string from, string to) => new(new ReminderTaskSettings { Enabled = true, TaskText = text, FromTime = from, ToTime = to });

    public ReminderTaskSettings ToSettings() => new()
    {
        Enabled = Enabled,
        TaskText = TaskText,
        FromTime = FromTime,
        ToTime = ToTime
    };
}

public sealed class PetCardViewModel : ViewModelBase
{
    private bool _isSelected;

    public PetCardViewModel(PetCatalogItem item)
    {
        Id = item.Id;
        DisplayName = item.DisplayName;
        Description = item.Description;
        SpritesheetPath = item.SpritesheetPath;
        Thumbnail = item.Thumbnail;
    }

    public string Id { get; }
    public string DisplayName { get; }
    public string Description { get; }
    public string? SpritesheetPath { get; }
    public ImageSource Thumbnail { get; }
    public bool IsSelected { get => _isSelected; set => SetProperty(ref _isSelected, value); }
}
