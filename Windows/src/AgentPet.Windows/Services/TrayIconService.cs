using System.ComponentModel;
using System.Drawing;
using System.IO;
using AgentPet.Windows.ViewModels;
using AgentPet.Windows.Windows;
using Forms = System.Windows.Forms;

namespace AgentPet.Windows.Services;

public sealed class TrayIconService : IDisposable
{
    private readonly Forms.NotifyIcon _notifyIcon;
    private readonly TrayFlyoutWindow _flyoutWindow;
    private readonly PetWindow _petWindow;
    private readonly MainWindow _settingsWindow;
    private bool _disposed;
    private bool _isExiting;

    public TrayIconService(TrayViewModel trayViewModel, TrayFlyoutWindow flyoutWindow, PetWindow petWindow, MainWindow settingsWindow)
    {
        _flyoutWindow = flyoutWindow;
        _petWindow = petWindow;
        _settingsWindow = settingsWindow;
        _notifyIcon = new Forms.NotifyIcon
        {
            Text = "AgentPet",
            Icon = LoadAppIcon(),
            Visible = true,
            ContextMenuStrip = BuildMenu()
        };
        _notifyIcon.DoubleClick += (_, _) => ToggleFlyout();
        _flyoutWindow.Closing += HideFlyoutInsteadOfClosing;
        _petWindow.Closing += HidePetInsteadOfClosing;
        _settingsWindow.Closing += HideSettingsInsteadOfClosing;
        trayViewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(TrayViewModel.Summary))
            {
                _notifyIcon.Text = TrimNotifyText($"AgentPet - {trayViewModel.Summary}");
            }
        };
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _isExiting = true;
        _flyoutWindow.Closing -= HideFlyoutInsteadOfClosing;
        _petWindow.Closing -= HidePetInsteadOfClosing;
        _settingsWindow.Closing -= HideSettingsInsteadOfClosing;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _disposed = true;
    }

    private Forms.ContextMenuStrip BuildMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Mở cài đặt", null, (_, _) => ShowSettings());
        menu.Items.Add("Hiện AgentPet", null, (_, _) => ShowWindows());
        menu.Items.Add("Ẩn thú cưng", null, (_, _) => _petWindow.Hide());
        menu.Items.Add("Thoát", null, (_, _) =>
        {
            _isExiting = true;
            System.Windows.Application.Current.Shutdown();
        });
        return menu;
    }

    private static Icon LoadAppIcon()
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");
        if (File.Exists(iconPath))
        {
            return new Icon(iconPath);
        }

        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath) && File.Exists(processPath))
        {
            return Icon.ExtractAssociatedIcon(processPath) ?? SystemIcons.Application;
        }

        return SystemIcons.Application;
    }

    private void HideFlyoutInsteadOfClosing(object? sender, CancelEventArgs args)
    {
        if (_isExiting)
        {
            return;
        }

        args.Cancel = true;
        _flyoutWindow.Hide();
    }

    private void HidePetInsteadOfClosing(object? sender, CancelEventArgs args)
    {
        if (_isExiting)
        {
            return;
        }

        args.Cancel = true;
        _petWindow.Hide();
    }

    private void HideSettingsInsteadOfClosing(object? sender, CancelEventArgs args)
    {
        if (_isExiting)
        {
            return;
        }

        args.Cancel = true;
        _settingsWindow.Hide();
    }

    private void ShowSettings()
    {
        if (!_settingsWindow.IsVisible)
        {
            _settingsWindow.Show();
        }

        _settingsWindow.Activate();
    }

    public void ShowWindows()
    {
        if (!_petWindow.IsVisible)
        {
            _petWindow.Show();
        }

        _petWindow.Activate();
        ShowFlyout();
    }

    private void ToggleFlyout()
    {
        if (_flyoutWindow.IsVisible)
        {
            _flyoutWindow.Hide();
        }
        else
        {
            ShowFlyout();
        }
    }

    private void ShowFlyout()
    {
        PositionFlyout();
        _flyoutWindow.Show();
        _flyoutWindow.Activate();
    }

    private void PositionFlyout()
    {
        var workArea = System.Windows.SystemParameters.WorkArea;
        _flyoutWindow.Left = workArea.Right - _flyoutWindow.Width - 16;
        _flyoutWindow.Top = workArea.Bottom - _flyoutWindow.Height - 16;
    }

    private static string TrimNotifyText(string text) => text.Length <= 63 ? text : text[..63];
}
