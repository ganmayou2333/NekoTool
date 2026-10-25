using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace NekoTool.App;

/// <summary>
/// Starts the Python dashboard server if it is not already listening.
///
/// Important: this class never owns the lifetime of the backend process. When
/// the WinUI 3 window closes we only exit the UI; the Python server (and
/// StatusCast) keep running for the next launch.
/// </summary>
internal static class BackendManager
{
    public const int DefaultPort = 5100;

    private static readonly HttpClient Http = new()
    {
        Timeout = TimeSpan.FromSeconds(1.5),
    };

    public static async Task EnsureRunningAsync(
        string projectRoot,
        int port,
        CancellationToken cancellationToken = default)
    {
        if (await IsDashboardReadyAsync(port, cancellationToken))
        {
            return;
        }

        if (await IsPortOpenAsync(port, cancellationToken))
        {
            // Port is open but /api/health did not answer: another program may
            // own it. Give a just-starting backend a short grace period first.
            if (await WaitForDashboardAsync(port, TimeSpan.FromSeconds(3), cancellationToken))
            {
                return;
            }

            throw new InvalidOperationException(
                $"端口 {port} 已被其他程序占用，但 /api/health 不是 NekoTool Dashboard。\n" +
                $"请关闭占用 {port} 的程序，或用 --port 换一个端口。");
        }

        var script = Path.Combine(projectRoot, "scripts", "dashboard_server.py");
        if (!File.Exists(script))
        {
            throw new FileNotFoundException(
                $"找不到后端脚本：{script}\n" +
                "请确认 exe 位于 NekoTool 目录（或 dist 子目录）下运行。",
                script);
        }

        var python = FindPython(projectRoot)
            ?? throw new InvalidOperationException(
                "找不到 Python。\n" +
                "请先创建虚拟环境（py -3 -m venv .venv）或把 pythonw.exe / python.exe 加入 PATH。");

        var startInfo = new ProcessStartInfo
        {
            FileName = python.FilePath,
            WorkingDirectory = projectRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };

        foreach (var prefix in python.PrefixArgs)
        {
            startInfo.ArgumentList.Add(prefix);
        }
        startInfo.ArgumentList.Add(script);
        startInfo.ArgumentList.Add("--port");
        startInfo.ArgumentList.Add(port.ToString(CultureInfo.InvariantCulture));

        try
        {
            // Dispose only the local Process handle. It does NOT terminate the
            // Python process; the backend deliberately outlives this window.
            using var process = Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"启动 Python Dashboard 失败：{ex.Message}\n" +
                $"Python: {python.FilePath}\n脚本：{script}",
                ex);
        }

        if (!await WaitForDashboardAsync(port, TimeSpan.FromSeconds(20), cancellationToken))
        {
            throw new TimeoutException(
                $"Dashboard 后端启动超时（20s）：http://127.0.0.1:{port}/api/health\n" +
                "请手动运行 scripts\\dashboard_server.py 查看错误。");
        }
    }

    private static async Task<bool> IsPortOpenAsync(int port, CancellationToken cancellationToken)
    {
        using var client = new TcpClient();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMilliseconds(400));

        try
        {
            await client.ConnectAsync(IPAddress.Loopback, port, timeout.Token);
            return true;
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return false;
        }
    }

    private static async Task<bool> IsDashboardReadyAsync(int port, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await Http.GetAsync(
                $"http://127.0.0.1:{port}/api/health",
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                return false;
            }

            var json = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(json);
            return document.RootElement.TryGetProperty("ok", out var ok) &&
                   ok.ValueKind == JsonValueKind.True;
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return false;
        }
    }

    private static async Task<bool> WaitForDashboardAsync(
        int port,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (await IsDashboardReadyAsync(port, cancellationToken))
            {
                return true;
            }
            await Task.Delay(250, cancellationToken);
        }
        return false;
    }

    private static PythonLaunch? FindPython(string projectRoot)
    {
        foreach (var environment in new[] { ".venv", "venv" })
        {
            var scripts = Path.Combine(projectRoot, environment, "Scripts");
            foreach (var name in new[] { "pythonw.exe", "python.exe" })
            {
                var candidate = Path.Combine(scripts, name);
                if (File.Exists(candidate))
                {
                    return new PythonLaunch(candidate, []);
                }
            }
        }

        var pythonw = FindOnPath("pythonw.exe");
        if (pythonw is not null)
        {
            return new PythonLaunch(pythonw, []);
        }

        var python = FindOnPath("python.exe");
        if (python is not null)
        {
            // Windows Python usually ships pythonw.exe beside python.exe.
            // Prefer it even when only python.exe is on PATH.
            var directory = Path.GetDirectoryName(python);
            if (!string.IsNullOrEmpty(directory))
            {
                var sibling = Path.Combine(directory, "pythonw.exe");
                if (File.Exists(sibling))
                {
                    return new PythonLaunch(sibling, []);
                }
            }

            return new PythonLaunch(python, []);
        }

        var py = FindOnPath("py.exe") ?? FindOnPath("pyw.exe");
        if (py is not null)
        {
            return new PythonLaunch(py, ["-3"]);
        }

        return null;
    }

    private static string? FindOnPath(string fileName)
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        foreach (var entry in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var directory = entry.Trim().Trim('"');
            if (directory.Length == 0)
            {
                continue;
            }

            try
            {
                var candidate = Path.Combine(directory, fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
                // Ignore malformed PATH entries.
            }
        }

        return null;
    }

    private sealed record PythonLaunch(string FilePath, string[] PrefixArgs);
}
