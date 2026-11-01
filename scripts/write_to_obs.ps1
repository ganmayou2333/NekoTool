<#
.SYNOPSIS
    Continuously write the status line into a text file that NekoTrak and OBS read.

.DESCRIPTION
    NekoTrak runs its custom-text command with a hard 5 second timeout, but the
    text builder (ultimate_status.ps1) needs roughly 8 seconds: it samples the
    network for a second and runs every plugin in its own child job. Calling the
    builder from the custom-text command therefore fails on every refresh
    (custom_text_command_failed, elapsed_ms ~5010) and the presence line never
    updates.

    So the builder runs here, in its own loop, and both NekoTrak and OBS only
    read the prewritten file, which takes milliseconds. Point NekoTrak at the
    file with scripts/point-nekotrak-presence.ps1.

    The file is replaced atomically (write next to it, then swap), so a reader
    can never catch a half-written line. Each round is timed and only the
    remainder of -IntervalSeconds is slept, so a slow round cannot stack delays.

.EXAMPLE
    .\scripts\write_to_obs.ps1

.EXAMPLE
    .\scripts\write_to_obs.ps1 -Once

.EXAMPLE
    .\scripts\write_to_obs.ps1 -OutputPath 'D:\OBS\status.txt' -IntervalSeconds 3
#>
[CmdletBinding()]
param(
    # Resolved in the body: with [CmdletBinding()] PowerShell 5.1 binds
    # parameters before $PSScriptRoot exists, so a Join-Path default here fails
    # with "Cannot bind argument to parameter 'Path' because it is an empty
    # string" and the writer could never start at all.
    [string]$OutputPath = '',
    [ValidateRange(1, 3600)]
    # One round measures ~8 s (1 s network sample + a child job per plugin),
    # so anything below ~10 s would only stack warnings.
    [int]$IntervalSeconds = 10,
    [string]$StatusUrl = 'http://localhost:5099/status/',
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot '..\obs_status.txt'
}

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$OutputEncoding = [Console]::OutputEncoding

$resolvedPath = [IO.Path]::GetFullPath($OutputPath)
$directory = Split-Path -Parent $resolvedPath
if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ultimate = Join-Path $PSScriptRoot 'ultimate_status.ps1'

function Write-StatusFile {
    param([string]$Text)

    # Same directory, so the swap stays on one volume and is atomic for the
    # reader: it sees either the previous line or the new one, never a partial.
    $tempPath = "$resolvedPath.tmp"
    [IO.File]::WriteAllText($tempPath, $Text, $utf8NoBom)
    if (Test-Path -LiteralPath $resolvedPath) {
        # File.Replace is the atomic swap. [NullString]::Value is how PowerShell
        # 5.1 passes a real null for "no backup file" -- a plain $null binds to
        # an empty string and Replace throws "path is not of a legal form".
        [IO.File]::Replace($tempPath, $resolvedPath, [NullString]::Value)
    }
    else {
        Move-Item -LiteralPath $tempPath -Destination $resolvedPath -Force
    }
}

function Get-StatusText {
    $lines = & $ultimate -StatusUrl $StatusUrl
    $text = ($lines | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '📱 -- | 🔋 -- | 🎵 --'
    }
    return $text
}

Write-Host "Writing status to: $resolvedPath"
Write-Host "Refresh interval:  $IntervalSeconds s"
Write-Host 'Press Ctrl+C to stop.'

while ($true) {
    $started = Get-Date
    try {
        $text = Get-StatusText
        Write-StatusFile -Text $text
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Write-Host ("[{0}] {1:0.0}s {2}" -f (Get-Date -Format 'HH:mm:ss'), $elapsed, $text)
        if ($elapsed -gt $IntervalSeconds) {
            Write-Warning ("one round took {0:0.0}s, longer than the {1}s interval" -f $elapsed, $IntervalSeconds)
        }
    }
    catch {
        Write-Warning $_.Exception.Message
    }

    if ($Once) {
        break
    }

    $remaining = $IntervalSeconds - ((Get-Date) - $started).TotalSeconds
    if ($remaining -gt 0) {
        Start-Sleep -Milliseconds ([int]($remaining * 1000))
    }
}
