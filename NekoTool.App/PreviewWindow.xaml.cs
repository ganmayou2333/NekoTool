using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Windows.Graphics;
using Windows.System;

namespace NekoTool.App;

public sealed partial class PreviewWindow : Window
{
    private readonly CancellationTokenSource _lifetime = new();
    private string _url;
    private bool _initialized;
    private bool _closed;

    public PreviewWindow(string url)
    {
        _url = url;

        InitializeComponent();

        Title = "OBS 挂件预览";
        UrlText.Text = url;

        // Keep the WebView2 cache out of the repository. This environment
        // variable is read when the control creates its first browser process.
        var userDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NekoTool",
            "WebView2");
        Directory.CreateDirectory(userDataFolder);
        Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", userDataFolder);

        try
        {
            AppWindow.Resize(new SizeInt32(980, 560));
        }
        catch
        {
            // The default window size is fine if resizing is unavailable.
        }

        RootGrid.Loaded += RootGrid_Loaded;
        Closed += PreviewWindow_Closed;
    }

    public void NavigateTo(string url)
    {
        _url = url;
        UrlText.Text = url;
        ErrorOverlay.Visibility = Visibility.Collapsed;
        LoadingOverlay.Visibility = Visibility.Visible;
        LoadingRing.IsActive = true;

        if (_initialized && !_closed)
        {
            PreviewView.CoreWebView2?.Navigate(url);
        }
        else if (!_closed)
        {
            _ = InitializeWebViewAsync();
        }
    }

    private async void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized)
        {
            return;
        }

        await InitializeWebViewAsync();
    }

    private async Task InitializeWebViewAsync()
    {
        if (_initialized || _closed)
        {
            return;
        }

        try
        {
            var runtimeVersion = CoreWebView2Environment.GetAvailableBrowserVersionString();
            if (string.IsNullOrWhiteSpace(runtimeVersion))
            {
                ShowError(
                    "未检测到 Microsoft Edge WebView2 Runtime。\n" +
                    "请安装 WebView2 Runtime 后重试。");
                return;
            }

            // Keep the WebView2 cache out of the repository.
            await PreviewView.EnsureCoreWebView2Async();

            if (_closed)
            {
                return;
            }

            PreviewView.DefaultBackgroundColor = Colors.Transparent;
            ConfigureWebView();
            _initialized = true;
            PreviewView.CoreWebView2.Navigate(_url);
        }
        catch (Exception ex)
        {
            if (!_closed)
            {
                ShowError($"预览加载失败：{ex.Message}");
            }
        }
    }

    private void ConfigureWebView()
    {
        var core = PreviewView.CoreWebView2
            ?? throw new InvalidOperationException("WebView2 初始化完成但 CoreWebView2 为空。");

        core.Settings.IsStatusBarEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.IsZoomControlEnabled = true;
        core.Settings.IsSwipeNavigationEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;

        core.NavigationCompleted += Core_NavigationCompleted;
        core.ProcessFailed += Core_ProcessFailed;
    }

    private void Core_NavigationCompleted(
        object? sender,
        CoreWebView2NavigationCompletedEventArgs e)
    {
        if (_closed)
        {
            return;
        }

        if (e.IsSuccess)
        {
            LoadingRing.IsActive = false;
            LoadingOverlay.Visibility = Visibility.Collapsed;
            ErrorOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        ShowError($"挂件加载失败：{e.WebErrorStatus}");
    }

    private void Core_ProcessFailed(object? sender, CoreWebView2ProcessFailedEventArgs e)
    {
        if (_closed)
        {
            return;
        }

        DispatcherQueue.TryEnqueue(() =>
        {
            if (!_closed)
            {
                ShowError("WebView2 进程异常，请重新打开预览窗口。");
            }
        });
    }

    private void ShowError(string message)
    {
        if (_closed)
        {
            return;
        }

        ErrorMessage.Text = message;
        LoadingRing.IsActive = false;
        LoadingOverlay.Visibility = Visibility.Collapsed;
        ErrorOverlay.Visibility = Visibility.Visible;
    }

    private void ReloadButton_Click(object sender, RoutedEventArgs e)
    {
        NavigateTo(_url);
    }

    private async void OpenExternalButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            await Launcher.LaunchUriAsync(new Uri(_url));
        }
        catch
        {
            // A file:// URL may be rejected by the shell; the preview still works.
        }
    }

    private async void RetryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_initialized)
        {
            NavigateTo(_url);
            return;
        }

        await InitializeWebViewAsync();
    }

    private void PreviewWindow_Closed(object sender, WindowEventArgs args)
    {
        _closed = true;
        _lifetime.Cancel();

        try
        {
            var core = PreviewView.CoreWebView2;
            if (core is not null)
            {
                core.NavigationCompleted -= Core_NavigationCompleted;
                core.ProcessFailed -= Core_ProcessFailed;
                core.Stop();
            }

            // Removing the control from the tree lets WebView2 release the
            // browser process and its GPU allocations immediately. The native
            // main shell is unaffected.
            PreviewHost.Children.Clear();
            PreviewView.Close();
        }
        catch
        {
            // Browser shutdown is best effort.
        }

        _lifetime.Dispose();
    }
}
