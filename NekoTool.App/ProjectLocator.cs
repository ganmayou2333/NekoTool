using System;
using System.IO;
using System.Linq;

namespace NekoTool.App;

internal sealed record LaunchOptions(string? Root, int Port)
{
    public static LaunchOptions Parse(string[] args)
    {
        string? root = null;
        var port = BackendManager.DefaultPort;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--root":
                    if (i + 1 >= args.Length)
                    {
                        throw new ArgumentException("--root 后缺少路径");
                    }
                    root = args[++i];
                    break;

                case "--port":
                    if (i + 1 >= args.Length ||
                        !int.TryParse(args[++i], out port) ||
                        port is < 1 or > 65535)
                    {
                        throw new ArgumentException("--port 需要 1-65535 之间的整数");
                    }
                    break;
            }
        }

        return new LaunchOptions(root, port);
    }
}

internal static class ProjectLocator
{
    private static readonly string[] RequiredFiles =
    [
        Path.Combine("scripts", "dashboard_server.py"),
        Path.Combine("web", "dashboard.html"),
    ];

    public static string? FindRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var full = Path.GetFullPath(explicitRoot.Trim());
            return IsRoot(full) ? full : null;
        }

        var starts = new[]
        {
            AppContext.BaseDirectory,
            Directory.GetCurrentDirectory(),
        };

        foreach (var start in starts)
        {
            var directory = new DirectoryInfo(start);
            for (var depth = 0; depth < 10 && directory is not null; depth++)
            {
                if (IsRoot(directory.FullName))
                {
                    return directory.FullName;
                }
                directory = directory.Parent;
            }
        }

        return null;
    }

    private static bool IsRoot(string directory)
    {
        try
        {
            return RequiredFiles.All(file => File.Exists(Path.Combine(directory, file)));
        }
        catch
        {
            return false;
        }
    }
}
