using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using NekoTool.App.Models;
using NekoTool.App.ViewModels;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;

namespace NekoTool.App;

public sealed partial class MainWindow : Window
{
    private readonly string _projectRoot;
    private readonly CancellationTokenSource _lifetime = new();

    private PreviewWindow? _previewWindow;
    private DispatcherTimer? _toastTimer;
    private PluginItem? _editingPlugin;
    private int _port;
    private bool _runAtStartup;
    private bool _silentRun = true;
    private bool _started;
    private bool _suppressToggle = true;
    private bool _closed;

    public DashboardViewModel ViewModel { get; } = new();

    public ObservableCollection<PluginItem> Plugins { get; } = new();

    public MainWindow(string projectRoot, int port)
    {
        _projectRoot = projectRoot;
        _port = port;

        InitializeComponent();

        Title = "NekoTool";
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        ApplyBackdrop();
        ConfigureTitleBar();

        try
        {
            AppWindow.Resize(new SizeInt32(1240, 840));
        }
        catch
        {
            // A fixed initial size is cosmetic.
        }

        SeedDemoPlugins();
        SettingsView.Initialize(_port, _runAtStartup, _silentRun);
        SettingsView.ApplyRequested += SettingsView_ApplyRequested;
        NavView.SelectedItem = PluginsNavItem;

        RootGrid.Loaded += RootGrid_Loaded;
        Closed += MainWindow_Closed;
    }

    private void ApplyBackdrop()
    {
        try
        {
            SystemBackdrop = MicaController.IsSupported()
                ? new MicaBackdrop { Kind = MicaKind.BaseAlt }
                : new DesktopAcrylicBackdrop();
        }
        catch
        {
            // Backdrop support is cosmetic; the dark surfaces remain usable.
        }
    }

    private void ConfigureTitleBar()
    {
        try
        {
            var titleBar = AppWindow.TitleBar;
            titleBar.ButtonBackgroundColor = Colors.Transparent;
            titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
            titleBar.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(30, 255, 255, 255);
            titleBar.ButtonPressedBackgroundColor = Windows.UI.Color.FromArgb(45, 255, 255, 255);
            titleBar.ButtonForegroundColor = Colors.White;
            titleBar.ButtonInactiveForegroundColor = Windows.UI.Color.FromArgb(255, 143, 152, 160);
            titleBar.ButtonHoverForegroundColor = Colors.White;
            titleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        }
        catch
        {
            // Older systems can expose a different title-bar implementation.
        }
    }

    private async void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        if (_started)
        {
            return;
        }

        _started = true;

        try
        {
            var profile = SteamProfileService.TryReadLocalProfile();
            if (profile is null)
            {
                ViewModel.SetSteam("Steam 用户", string.Empty);
                ViewModel.StatusText = "未检测到本地 Steam 登录用户 · 状态占位符";
            }
            else
            {
                ViewModel.SetSteam(profile.PersonaName, profile.SteamId64);
                ViewModel.StatusText = "Deep diving... · 状态占位符";

                var avatarUrl = await SteamProfileService.TryFetchAvatarUrlAsync(
                    profile.SteamId64,
                    _lifetime.Token);
                if (!_closed)
                {
                    ViewModel.SetAvatarUrl(avatarUrl);
                }
            }
        }
        catch (OperationCanceledException) when (_closed)
        {
        }
        catch (Exception ex)
        {
            ViewModel.StatusText = $"状态占位符 · Steam 读取失败：{ex.Message}";
        }
        finally
        {
            // Let the first batch of ToggleSwitch bindings settle before the
            // UI starts reporting user-driven changes.
            await Task.Delay(250);
            _suppressToggle = false;
        }
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _closed = true;
        _lifetime.Cancel();
        _toastTimer?.Stop();

        try
        {
            _previewWindow?.Close();
        }
        catch
        {
            // The preview may already be closing.
        }

        _lifetime.Dispose();
    }

    private void SeedDemoPlugins()
    {
        Plugins.Add(new PluginItem
        {
            Name = "weather.ps1",
            Title = "天气插件",
            Description = "调用本地天气接口，输出一行当前天气与温度。",
            IconGlyph = "\uE753",
            IsEnabled = true,
            Content = "param()\n\n" +
                      "# 示例：读取天气并返回一行文本\n" +
                      "Write-Output \"🌤 晴 25℃\"\n",
        });

        Plugins.Add(new PluginItem
        {
            Name = "heart_rate.ps1",
            Title = "心率插件",
            Description = "从 data/heart_rate.json 读取最近一次心率数据。",
            IconGlyph = "\uEB51",
            IsEnabled = true,
            Content = "param()\n\n" +
                      "$data = Get-Content \"$PSScriptRoot\\..\\data\\heart_rate.json\" -Raw | ConvertFrom-Json\n" +
                      "Write-Output \"❤️ $($data.bpm) BPM\"\n",
        });

        Plugins.Add(new PluginItem
        {
            Name = "cpu_temp.ps1",
            Title = "CPU 温度",
            Description = "读取主板传感器温度，失败时静默跳过。",
            IconGlyph = "\uE950",
            IsEnabled = false,
            Content = "param()\n\n" +
                      "# 需要硬件传感器支持\n" +
                      "Write-Output \"🌡 CPU --℃\"\n",
        });

        Plugins.Add(new PluginItem
        {
            Name = "media.ps1",
            Title = "媒体信息",
            Description = "输出 Android 当前播放的歌曲与歌手。",
            IconGlyph = "\uE8D6",
            IsEnabled = true,
            Content = "param()\n\n" +
                      "# 原型阶段占位\n" +
                      "Write-Output \"🎵 暂无播放\"\n",
        });
    }

    private void NavView_SelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItemContainer as NavigationViewItem)?.Tag as string;
        var showSettings = string.Equals(tag, "settings", StringComparison.Ordinal);

        PluginsPage.Visibility = showSettings ? Visibility.Collapsed : Visibility.Visible;
        SettingsView.Visibility = showSettings ? Visibility.Visible : Visibility.Collapsed;

        if (showSettings && EditorSplitView.IsPaneOpen)
        {
            EditorSplitView.IsPaneOpen = false;
        }
    }

    private void CopyCommand_Click(object sender, RoutedEventArgs e)
    {
        var root = ResolveProjectRoot();
        var script = string.IsNullOrWhiteSpace(root)
            ? @"scripts\launch_and_pull.ps1"
            : Path.Combine(root, "scripts", "launch_and_pull.ps1");

        var command =
            "${(powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" +
            script +
            "\")}";

        CopyText(command, "PowerShell 启动命令已复制");
    }

    private void GenerateObsLink_Click(object sender, RoutedEventArgs e)
    {
        CopyText(BuildObsUrl(), "OBS 挂件链接已复制");
    }

    private void PreviewObs_Click(object sender, RoutedEventArgs e)
    {
        var url = BuildObsUrl();

        if (_previewWindow is null)
        {
            _previewWindow = new PreviewWindow(url);
            _previewWindow.Closed += (_, _) => _previewWindow = null;
        }
        else
        {
            _previewWindow.NavigateTo(url);
        }

        _previewWindow.Activate();
    }

    private string BuildObsUrl()
    {
        var root = ResolveProjectRoot();
        var widgetPath = string.IsNullOrWhiteSpace(root)
            ? string.Empty
            : Path.Combine(root, "web", "widget.html");

        var baseUrl = !string.IsNullOrWhiteSpace(widgetPath) && File.Exists(widgetPath)
            ? new Uri(widgetPath).AbsoluteUri
            : $"http://127.0.0.1:{_port}/widget.html";

        var theme = (ThemeComboBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "dark";
        var transparent = TransparentToggle.IsOn ? "true" : "false";
        var statusUrl = Uri.EscapeDataString("http://127.0.0.1:5099/status/");

        return $"{baseUrl}?url={statusUrl}" +
               $"&theme={Uri.EscapeDataString(theme)}" +
               $"&transparent={transparent}";
    }

    private string? ResolveProjectRoot()
    {
        if (!string.IsNullOrWhiteSpace(_projectRoot) && Directory.Exists(_projectRoot))
        {
            return _projectRoot;
        }

        return ProjectLocator.FindRoot(null);
    }

    private void EditPlugin_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string name })
        {
            return;
        }

        var plugin = Plugins.FirstOrDefault(item =>
            string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase));
        if (plugin is null)
        {
            return;
        }

        _editingPlugin = plugin;
        EditorTitle.Text = $"编辑：{plugin.Title}";
        EditorFileName.Text = plugin.Name;
        PluginEditor.Text = plugin.Content;
        EditorSplitView.IsPaneOpen = true;
        PluginEditor.Focus(FocusState.Programmatic);
    }

    private void CloseEditor_Click(object sender, RoutedEventArgs e)
    {
        EditorSplitView.IsPaneOpen = false;
    }

    private void EditorSplitView_PaneClosed(object sender, object args)
    {
        _editingPlugin = null;
    }

    private void SavePlugin_Click(object sender, RoutedEventArgs e)
    {
        if (_editingPlugin is null)
        {
            return;
        }

        _editingPlugin.Content = PluginEditor.Text;
        ShowToast($"{_editingPlugin.Title} 已保存（原型模式）", InfoBarSeverity.Success);
        EditorSplitView.IsPaneOpen = false;
    }

    private void PluginToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_suppressToggle)
        {
            return;
        }

        if (sender is ToggleSwitch toggle && toggle.DataContext is PluginItem plugin)
        {
            var state = toggle.IsOn ? "启用" : "停用";
            ShowToast($"{plugin.Title} 已{state}（原型模式）", InfoBarSeverity.Success);
        }
    }

    private async void DeletePlugin_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string name })
        {
            return;
        }

        var plugin = Plugins.FirstOrDefault(item =>
            string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase));
        if (plugin is null)
        {
            return;
        }

        var dialog = new ContentDialog
        {
            Title = "删除插件",
            Content = $"确定从本次原型列表中移除“{plugin.Title}”吗？\n\n" +
                      "原型模式不会删除磁盘上的 .ps1 文件。",
            PrimaryButtonText = "删除",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = RootGrid.XamlRoot,
        };

        try
        {
            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                return;
            }
        }
        catch
        {
            return;
        }

        if (ReferenceEquals(_editingPlugin, plugin))
        {
            EditorSplitView.IsPaneOpen = false;
        }

        Plugins.Remove(plugin);
        ShowToast($"{plugin.Title} 已从原型列表移除", InfoBarSeverity.Informational);
    }

    private void SettingsView_ApplyRequested(object? sender, SettingsAppliedEventArgs e)
    {
        _port = e.Port;
        _runAtStartup = e.RunAtStartup;
        _silentRun = e.SilentRun;
        ShowToast("设置已应用（原型模式，未写入注册表）", InfoBarSeverity.Success);
    }

    private void CopyText(string text, string successMessage)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
            Clipboard.Flush();
            ShowToast(successMessage, InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowToast($"复制失败：{ex.Message}", InfoBarSeverity.Error);
        }
    }

    private void ShowToast(string message, InfoBarSeverity severity)
    {
        ToastBar.Message = message;
        ToastBar.Severity = severity;
        ToastBar.IsOpen = true;

        _toastTimer?.Stop();
        _toastTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(3.5),
        };
        _toastTimer.Tick += (_, _) =>
        {
            ToastBar.IsOpen = false;
            _toastTimer?.Stop();
        };
        _toastTimer.Start();
    }
}
