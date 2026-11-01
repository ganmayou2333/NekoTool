<#
.SYNOPSIS
    Continuously write the presence line into a text file that NekoTrak reads.

.DESCRIPTION
    NekoTrak runs its custom-text command with a hard 5 second timeout, so it
    must never build the line itself (the full builder needs ~8 s). This script
    owns the loop instead and swaps obs_status.txt atomically; NekoTrak only
    reads that file (~190 ms).

    Two styles:

    -Style presence (default)
        The Discord presence line, built straight from /status/:
            🎮 <game or 挂台中> · 🔋 <name> <level>%[⚡] · 🍅 <mm:ss>
        The pomodoro segment only appears once the snapshot carries
        nekotrak.pomodoro (ticket 06); until then the line has two segments.

    -Style full
        Delegates to ultimate_status.ps1 for the long OBS line (CPU / memory /
        network / clock / plugins). That round takes ~8 s because each plugin
        runs in its own child job, which is exactly why the presence line does
        not use it.

    Replacing the file is atomic (write beside it, then swap), so a reader never
    sees a half-written line. Each round is timed and only the remainder of
    -IntervalSeconds is slept, so a slow round cannot stack delays.

.EXAMPLE
    .\scripts\write_to_obs.ps1

.EXAMPLE
    .\scripts\write_to_obs.ps1 -Once

.EXAMPLE
    .\scripts\write_to_obs.ps1 -Style full -OutputPath 'D:\OBS\status.txt'
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
    [ValidateSet('presence', 'full')]
    [string]$Style = 'presence',
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

function Get-FullText {
    $lines = & $ultimate -StatusUrl $StatusUrl
    $text = ($lines | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '📱 -- | 🔋 -- | 🎵 --'
    }
    return $text
}

function Get-DeviceName {
    param($Device)

    if ($null -eq $Device) {
        return $null
    }
    foreach ($candidate in @($Device.displayName, $Device.alias, $Device.model)) {
        $text = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }
        # The daemon fills displayName with a placeholder when the model is
        # unknown; "🔋 未知机型 未知" is worse than just "🔋 未知".
        if ($text -in @('未知机型', '未知设备', '--')) {
            continue
        }
        return $text
    }
    return $null
}

function Get-PresenceText {
    param($Status)

    $devices = @($Status.devices)
    $nekotrak = $devices | Where-Object { $_.platform -eq 'windows' } | Select-Object -First 1

    # Game: only a Steam-resolved title counts. The raw foreground process name
    # (chrome.exe) is noise in a Discord presence, so an unresolved foreground
    # means "idle", not "playing chrome".
    $game = '挂台中'
    if ($null -ne $nekotrak -and $null -ne $nekotrak.nekotrak -and
        -not [string]::IsNullOrWhiteSpace([string]$nekotrak.nekotrak.currentGame)) {
        $game = [string]$nekotrak.nekotrak.currentGame
    }

    # Battery: phones only. A MacBook or a console has no business representing
    # the phone battery, and a device without a level must not win the pick.
    $primary = $devices |
        Where-Object { $_.platform -eq 'ios' -and $null -ne $_.batteryLevel } |
        Select-Object -First 1
    if ($null -eq $primary) {
        $primary = $devices |
            Where-Object { $_.platform -eq 'android' -and $null -ne $_.batteryLevel } |
            Select-Object -First 1
    }
    if ($null -eq $primary) {
        $primary = $devices |
            Where-Object { $_.platform -eq 'ios' -or $_.platform -eq 'android' } |
            Select-Object -First 1
    }

    $battery = '🔋 未知'
    if ($null -ne $primary) {
        $name = Get-DeviceName $primary
        if ($null -ne $primary.batteryLevel) {
            $bolt = if ($primary.isCharging -eq $true) { '⚡' } else { '' }
            $battery = if ($name) {
                "🔋 $name $($primary.batteryLevel)%$bolt"
            }
            else {
                "🔋 $($primary.batteryLevel)%$bolt"
            }
        }
        elseif ($name) {
            $battery = "🔋 $name 未知"
        }
    }

    $parts = @("🎮 $game", $battery)

    # Pomodoro lands with ticket 06; until the snapshot carries it, no segment.
    if ($null -ne $nekotrak -and $null -ne $nekotrak.nekotrak -and
        $null -ne $nekotrak.nekotrak.pomodoro -and
        $null -ne $nekotrak.nekotrak.pomodoro.remainingSeconds) {
        $seconds = [int]$nekotrak.nekotrak.pomodoro.remainingSeconds
        if ($seconds -ge 0) {
            $parts += ('🍅 {0:d2}:{1:d2}' -f [int][Math]::Floor($seconds / 60), ($seconds % 60))
        }
    }

    return ($parts -join ' · ')
}

function Get-StatusText {
    if ($Style -eq 'full') {
        return Get-FullText
    }

    $status = Invoke-RestMethod -Uri $StatusUrl -UseBasicParsing -TimeoutSec 5
    return Get-PresenceText -Status $status
}

Write-Host "Writing status to: $resolvedPath"
Write-Host "Style:             $Style"
Write-Host "Refresh interval:  $IntervalSeconds s"
Write-Host 'Press Ctrl+C to stop.'

# How many rounds in a row failed to read /status/. After three (~30 s) the
# presence line is replaced with an explicit unknown line: keeping the last
# good line forever would show a stale 87% battery as if it were current.
$consecutiveFailures = 0
$PRESENCE_FALLBACK = '🎮 挂台中 · 🔋 未知'
$FAILURES_BEFORE_FALLBACK = 3

while ($true) {
    $started = Get-Date
    try {
        $text = Get-StatusText
        Write-StatusFile -Text $text
        $consecutiveFailures = 0
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Write-Host ("[{0}] {1:0.0}s {2}" -f (Get-Date -Format 'HH:mm:ss'), $elapsed, $text)
        if ($elapsed -gt $IntervalSeconds) {
            Write-Warning ("one round took {0:0.0}s, longer than the {1}s interval" -f $elapsed, $IntervalSeconds)
        }
    }
    catch {
        $consecutiveFailures++
        Write-Warning $_.Exception.Message
        if ($Style -eq 'presence' -and $consecutiveFailures -ge $FAILURES_BEFORE_FALLBACK) {
            try {
                Write-StatusFile -Text $PRESENCE_FALLBACK
                # Warn on the transition only: rewriting the same fallback is
                # fine, warning about it every round is noise.
                if ($consecutiveFailures -eq $FAILURES_BEFORE_FALLBACK) {
                    Write-Warning ("status API unreachable for {0} rounds; wrote the unknown line" -f $consecutiveFailures)
                }
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
    }

    if ($Once) {
        break
    }

    $remaining = $IntervalSeconds - ((Get-Date) - $started).TotalSeconds
    if ($remaining -gt 0) {
        Start-Sleep -Milliseconds ([int]($remaining * 1000))
    }
}
