using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace NekoTool.App.ViewModels;

public sealed class DashboardViewModel : INotifyPropertyChanged
{
    private string _steamName = "Steam 用户";
    private string _steamId64 = string.Empty;
    private string _statusText = "Deep diving... · 状态占位符";
    private ImageSource? _avatarSource;

    public string SteamName
    {
        get => _steamName;
        private set => SetField(ref _steamName, value);
    }

    public string SteamId64
    {
        get => _steamId64;
        private set
        {
            if (SetField(ref _steamId64, value))
            {
                OnPropertyChanged(nameof(SteamIdDisplay));
            }
        }
    }

    public string SteamIdDisplay =>
        string.IsNullOrWhiteSpace(SteamId64) ? "SteamID64 未读取" : $"SteamID64 · {SteamId64}";

    public string StatusText
    {
        get => _statusText;
        set => SetField(ref _statusText, value);
    }

    public ImageSource? AvatarSource
    {
        get => _avatarSource;
        private set => SetField(ref _avatarSource, value);
    }

    public void SetSteam(string? name, string? steamId64)
    {
        SteamName = string.IsNullOrWhiteSpace(name) ? "Steam 用户" : name.Trim();
        SteamId64 = steamId64?.Trim() ?? string.Empty;
    }

    public void SetAvatarUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url) ||
            !Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            AvatarSource = null;
            return;
        }

        AvatarSource = new BitmapImage(uri);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged(string? propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
