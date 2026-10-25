using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace NekoTool.App.Models;

/// <summary>
/// One PowerShell plugin displayed in the plugin list.
/// The first version uses in-memory demo entries; the shape already matches the
/// fields returned by the optional Python dashboard API.
/// </summary>
public sealed class PluginItem : INotifyPropertyChanged
{
    private string _title = string.Empty;
    private string _description = string.Empty;
    private string _content = string.Empty;
    private bool _isEnabled;

    public string Name { get; set; } = string.Empty;

    public string IconGlyph { get; set; } = "\uE8B7";

    public string Title
    {
        get => _title;
        set => SetField(ref _title, value);
    }

    public string Description
    {
        get => _description;
        set => SetField(ref _description, value);
    }

    public string Content
    {
        get => _content;
        set => SetField(ref _content, value);
    }

    public bool IsEnabled
    {
        get => _isEnabled;
        set => SetField(ref _isEnabled, value);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void SetField<T>(
        ref T field,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
