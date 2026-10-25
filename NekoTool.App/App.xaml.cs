using System;
using System.Linq;
using Microsoft.UI.Xaml;

namespace NekoTool.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var options = LaunchOptions.Parse(
            Environment.GetCommandLineArgs().Skip(1).ToArray());

        var root = ProjectLocator.FindRoot(options.Root) ?? string.Empty;

        _window = new MainWindow(root, options.Port);
        _window.Activate();
    }
}
