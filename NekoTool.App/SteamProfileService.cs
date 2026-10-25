using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using Microsoft.Win32;

namespace NekoTool.App;

public sealed record SteamProfile(string PersonaName, string SteamId64);

/// <summary>
/// Reads the locally signed-in Steam account without requiring the Steam Web API
/// key:
///
///   1. find SteamPath under HKCU\Software\Valve\Steam;
///   2. parse config\loginusers.vdf and select the most recent account;
///   3. resolve the public avatar through the community profile XML.
///
/// Every public entry point fails soft: a missing registry value, malformed VDF,
/// or offline network simply returns null and the shell shows its fallback UI.
/// </summary>
public static class SteamProfileService
{
    private const string SteamRegistryPath = @"Software\Valve\Steam";
    private const string SteamProfileXmlTemplate =
        "https://steamcommunity.com/profiles/{0}/?xml=1";

    private static readonly HttpClient Http = CreateHttpClient();

    public static SteamProfile? TryReadLocalProfile()
    {
        try
        {
            var steamPath = TryReadSteamPath();
            if (string.IsNullOrWhiteSpace(steamPath))
            {
                return null;
            }

            var loginUsersPath = Path.Combine(steamPath, "config", "loginusers.vdf");
            if (!File.Exists(loginUsersPath))
            {
                return null;
            }

            // loginusers.vdf is UTF-8 (it may include a BOM). File.ReadAllText
            // detects the BOM and otherwise defaults to UTF-8.
            var text = File.ReadAllText(loginUsersPath);
            return ParseLoginUsers(text);
        }
        catch
        {
            // Registry access, file access and parsing are all best effort.
            return null;
        }
    }

    public static string BuildProfileXmlUrl(string steamId64)
    {
        return string.Format(
            System.Globalization.CultureInfo.InvariantCulture,
            SteamProfileXmlTemplate,
            Uri.EscapeDataString(steamId64.Trim()));
    }

    /// <summary>
    /// Steam does not expose the avatar hash in loginusers.vdf, so the public
    /// profile XML is the keyless way to get a real avatar URL. The resulting
    /// avatarFull value already points at avatars.steamstatic.com.
    /// </summary>
    public static async Task<string?> TryFetchAvatarUrlAsync(
        string? steamId64,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(steamId64))
        {
            return null;
        }

        try
        {
            var profileUrl = BuildProfileXmlUrl(steamId64);
            using var response = await Http.GetAsync(profileUrl, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return null;
            }

            var xml = await response.Content.ReadAsStringAsync(cancellationToken);
            var document = XDocument.Parse(xml);
            var avatar = document.Descendants("avatarFull").FirstOrDefault()?.Value.Trim();
            return Uri.TryCreate(avatar, UriKind.Absolute, out _) ? avatar : null;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    public static string? TryReadSteamPath()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(SteamRegistryPath);
            var raw = key?.GetValue("SteamPath") as string;
            if (string.IsNullOrWhiteSpace(raw))
            {
                return null;
            }

            // Steam stores this value with forward slashes on some installs.
            var path = raw.Trim().Replace('/', '\\');
            path = Environment.ExpandEnvironmentVariables(path);
            return Directory.Exists(path) ? path : null;
        }
        catch
        {
            return null;
        }
    }

    private static SteamProfile? ParseLoginUsers(string text)
    {
        var tokens = Tokenize(text);
        var index = 0;
        var root = ParseObject(tokens, ref index);

        if (!root.TryGetValue("users", out var usersValue) ||
            usersValue is not Dictionary<string, object> users)
        {
            return null;
        }

        SteamProfile? recent = null;
        SteamProfile? fallback = null;
        long newestTimestamp = long.MinValue;

        foreach (var pair in users)
        {
            if (pair.Value is not Dictionary<string, object> fields)
            {
                continue;
            }

            var name = GetString(fields, "PersonaName");
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }

            var profile = new SteamProfile(DecodeVdfString(name).Trim(), pair.Key);
            fallback ??= profile;

            if (GetString(fields, "MostRecent") == "1" ||
                GetString(fields, "AutoLogin") == "1")
            {
                if (recent is null)
                {
                    recent = profile;
                }
            }

            if (long.TryParse(GetString(fields, "timestamp"), out var timestamp) &&
                timestamp > newestTimestamp)
            {
                newestTimestamp = timestamp;
                fallback = profile;
            }
        }

        return recent ?? fallback;
    }

    private static string GetString(
        IReadOnlyDictionary<string, object> fields,
        string key)
    {
        return fields.TryGetValue(key, out var value) && value is string text
            ? text
            : string.Empty;
    }

    /// <summary>
    /// Minimal recursive VDF reader. Values are strings; nested blocks are
    /// dictionaries. That is enough for loginusers.vdf and avoids regexes that
    /// break on a persona name containing braces or escaped quotes.
    /// </summary>
    private static Dictionary<string, object> ParseObject(
        IReadOnlyList<string> tokens,
        ref int index,
        bool stopAtClosingBrace = false)
    {
        var result = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

        while (index < tokens.Count)
        {
            if (tokens[index] == "}")
            {
                index++;
                if (stopAtClosingBrace)
                {
                    break;
                }

                continue;
            }

            var key = tokens[index++];
            if (index >= tokens.Count)
            {
                break;
            }

            if (tokens[index] == "{")
            {
                index++;
                result[key] = ParseObject(tokens, ref index, stopAtClosingBrace: true);
            }
            else
            {
                result[key] = tokens[index++];
            }
        }

        return result;
    }

    private static List<string> Tokenize(string text)
    {
        var tokens = new List<string>();
        var index = 0;

        while (index < text.Length)
        {
            var current = text[index];

            if (char.IsWhiteSpace(current))
            {
                index++;
                continue;
            }

            if (current is '{' or '}')
            {
                tokens.Add(current.ToString());
                index++;
                continue;
            }

            if (current == '"')
            {
                index++;
                var builder = new StringBuilder();
                while (index < text.Length)
                {
                    var ch = text[index++];
                    if (ch == '"')
                    {
                        break;
                    }

                    if (ch == '\\' && index < text.Length)
                    {
                        builder.Append('\\');
                        builder.Append(text[index++]);
                        continue;
                    }

                    builder.Append(ch);
                }

                tokens.Add(builder.ToString());
                continue;
            }

            // Unquoted key/value (not used by loginusers.vdf today, but VDF
            // permits it for simple tokens).
            var start = index;
            while (index < text.Length &&
                   !char.IsWhiteSpace(text[index]) &&
                   text[index] is not '{' and not '}')
            {
                index++;
            }

            tokens.Add(text[start..index]);
        }

        return tokens;
    }

    private static string DecodeVdfString(string value)
    {
        return value
            .Replace("\\\\", "\\", StringComparison.Ordinal)
            .Replace("\\\"", "\"", StringComparison.Ordinal)
            .Replace("\\n", "\n", StringComparison.Ordinal)
            .Replace("\\t", "\t", StringComparison.Ordinal);
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(7),
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("NekoTool.App/1.0");
        return client;
    }
}
