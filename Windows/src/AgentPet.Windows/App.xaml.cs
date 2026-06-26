using System.Media;
using AgentPet.Windows.Services;
using AgentPet.Windows.ViewModels;
using AgentPet.Windows.Windows;

namespace AgentPet.Windows;

public partial class App : System.Windows.Application
{
    private AppDaemon? _daemon;
    private TrayIconService? _trayIcon;
    private ReminderSchedulerService? _reminderScheduler;
    private TrayViewModel? _trayViewModel;
    private PetViewModel? _petViewModel;
    private TrayFlyoutWindow? _flyoutWindow;
    private PetWindow? _petWindow;
    private MainWindow? _settingsWindow;

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);

        ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown;

        _trayViewModel = new TrayViewModel();
        _petViewModel = new PetViewModel();

        var settingsService = new ReminderSettingsService();
        var reminderSettings = settingsService.Load();
        var settingsViewModel = new SettingsViewModel(new PetCatalogService(), settingsService, reminderSettings);
        _petViewModel.SelectPetSpritesheet(settingsViewModel.SelectedPetSpritesheet);
        _petViewModel.SetPreviewMood(settingsViewModel.PreviewMood);
        _petViewModel.SetPetSize(settingsViewModel.PetSize);
        _petViewModel.ConfigureBubbles(settingsViewModel.ReminderBubblesEnabled, settingsViewModel.BubbleDurationSeconds, settingsViewModel.BubbleWidth);
        settingsViewModel.SelectedPetSpritesheetChanged += _petViewModel.SelectPetSpritesheet;
        settingsViewModel.PreviewMoodChanged += _petViewModel.SetPreviewMood;
        settingsViewModel.PetSizeChanged += size =>
        {
            _petViewModel.SetPetSize(size);
            _petWindow?.EnsurePetVisible();
        };
        settingsViewModel.BubbleWidthChanged += width =>
        {
            _petViewModel.SetBubbleWidth(width);
            _petWindow?.EnsurePetVisible();
        };
        settingsViewModel.SettingsSaved += settings =>
        {
            _petViewModel.ConfigureBubbles(settings.ReminderBubblesEnabled, settings.BubbleDurationSeconds, settings.BubbleWidth);
            _petViewModel.SetPetSize(settings.PetSize);
            _reminderScheduler?.UpdateSettings(settings);
            _petWindow?.EnsurePetVisible();
        };
        settingsViewModel.ReminderPreviewRequested += message => ShowReminder(message, settingsViewModel.BubbleDurationSeconds);
        settingsViewModel.BubblePreviewRequested += message => ShowReminder(message, settingsViewModel.BubbleDurationSeconds);

        _flyoutWindow = new TrayFlyoutWindow
        {
            DataContext = _trayViewModel
        };
        _petWindow = new PetWindow
        {
            DataContext = _petViewModel
        };
        _petWindow.PetClicked += HandlePetClicked;
        _settingsWindow = new MainWindow
        {
            DataContext = settingsViewModel
        };
        PositionPetWindow(_petWindow);
        _petWindow.Show();

        _daemon = new AppDaemon();
        _daemon.SessionsChanged += sessions =>
        {
            _trayViewModel.UpdateSessions(sessions);
            _petViewModel.UpdateSessions(sessions);
        };
        _daemon.Start();

        _reminderScheduler = new ReminderSchedulerService(settingsViewModel.CreateSettings());
        _reminderScheduler.ReminderDue += notification => Dispatcher.Invoke(() => ShowReminder(notification, settingsViewModel.BubbleDurationSeconds));
        _reminderScheduler.Start();

        _trayIcon = new TrayIconService(_trayViewModel, _flyoutWindow, _petWindow, _settingsWindow);
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        _reminderScheduler?.Dispose();
        _daemon?.Dispose();
        base.OnExit(e);
    }

    private void ShowReminder(string message, int durationSeconds)
    {
        ShowReminder(new ReminderNotification("Nhắc việc", message, ReminderNotificationKind.CurrentTask), durationSeconds);
    }

    private void ShowReminder(ReminderNotification notification, int durationSeconds)
    {
        _petViewModel?.ConfigureBubbles(true, durationSeconds, _petViewModel.BubbleWidth);
        _petViewModel?.ShowReminder(notification);
        PlayNotificationSound(notification.Kind);
        if (_petWindow is null)
        {
            return;
        }

        if (!_petWindow.IsVisible)
        {
            _petWindow.Show();
        }

        _petWindow.EnsurePetVisible();
    }

    private void HandlePetClicked(int clickCount)
    {
        if (_reminderScheduler is null)
        {
            return;
        }

        var notification = clickCount >= 3
            ? _reminderScheduler.CompleteCurrentAndAdvance()
            : clickCount == 2
                ? _reminderScheduler.ShowNextTask()
                : _reminderScheduler.ShowCurrentTask();
        ShowReminder(notification, 12);
    }

    private static void PlayNotificationSound(ReminderNotificationKind kind)
    {
        switch (kind)
        {
            case ReminderNotificationKind.Warning:
                SystemSounds.Exclamation.Play();
                break;
            case ReminderNotificationKind.CompletedEarly:
            case ReminderNotificationKind.Completed:
            case ReminderNotificationKind.AllCompleted:
                SystemSounds.Asterisk.Play();
                break;
        }
    }

    private static void PositionPetWindow(System.Windows.Window window)
    {
        window.Measure(new System.Windows.Size(double.PositiveInfinity, double.PositiveInfinity));
        var width = window.DesiredSize.Width > 0 ? window.DesiredSize.Width : window.Width;
        var height = window.DesiredSize.Height > 0 ? window.DesiredSize.Height : window.Height;
        var workArea = System.Windows.SystemParameters.WorkArea;
        window.Left = workArea.Right - width - 24;
        window.Top = workArea.Bottom - height - 32;
    }
}
