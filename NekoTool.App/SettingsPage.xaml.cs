using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace NekoTool.App;

public sealed partial class SettingsPage : UserControl
{
    private int _port = 5100;

    public SettingsPage()
    {
        InitializeComponent();
    }

    public event EventHandler<SettingsAppliedEventArgs>? ApplyRequested;

    public void Initialize(int port, bool runAtStartup, bool silentRun)
    {
        _port = port;
        PortBox.Text = port.ToString(System.Globalization.CultureInfo.InvariantCulture);
        StartupToggle.IsOn = runAtStartup;
        SilentToggle.IsOn = silentRun;
        SettingsBar.IsOpen = false;
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        var rawPort = PortBox.Text.Trim();
        if (!int.TryParse(rawPort, out var port) || port is < 1 or > 65535)
        {
            SettingsBar.Severity = InfoBarSeverity.Error;
            SettingsBar.Message = "端口必须是 1–65535 之间的整数。";
            SettingsBar.IsOpen = true;
            return;
        }

        _port = port;
        SettingsBar.Severity = InfoBarSeverity.Success;
        SettingsBar.Message = "设置已应用；端口修改会在原型阶段立即影响新生成的 OBS 链接。";
        SettingsBar.IsOpen = true;

        ApplyRequested?.Invoke(
            this,
            new SettingsAppliedEventArgs(
                _port,
                StartupToggle.IsOn,
                SilentToggle.IsOn));
    }
}

public sealed record SettingsAppliedEventArgs(
    int Port,
    bool RunAtStartup,
    bool SilentRun);
