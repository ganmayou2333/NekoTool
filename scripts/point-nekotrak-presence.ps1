<#
.SYNOPSIS
    Point NekoTrak's custom text at the prewritten obs_status.txt.

.DESCRIPTION
    NekoTrak evaluates its custom-text command with a hard 5 second timeout.
    Calling ultimate_status.ps1 there takes about 8 seconds (1 s network sample
    plus one child job per plugin), so the command reports
    custom_text_command_failed with elapsed_ms ~5010 on every refresh and the
    presence line never updates.

    This script rewrites that one template string in the per-user NekoTrak
    config so NekoTrak only reads the file that scripts/write_to_obs.ps1 keeps
    fresh (milliseconds instead of seconds).

    It edits the raw JSON text with a targeted string swap rather than
    re-serialising the document: NekoTrak's config holds deeply nested settings
    that a ConvertTo-Json round-trip would flatten.

    A timestamped backup is written next to the config first, and running the
    script twice is a no-op. Restart NekoTrak afterwards, because the template
    is read at startup.

.PARAMETER ObsStatusPath
    The file written by write_to_obs.ps1. Defaults to ..\obs_status.txt.

.PARAMETER NekoTrakHome
    NekoTrak data root. Defaults to %APPDATA%\NekoTrak.

.PARAMETER WhatIfMode
    Report what would change without touching the file.

.EXAMPLE
    .\scripts\point-nekotrak-presence.ps1

.EXAMPLE
    .\scripts\point-nekotrak-presence.ps1 -WhatIfMode
#>
[CmdletBinding()]
param(
    # Empty means "default", resolved in the body: with [CmdletBinding()]
    # PowerShell 5.1 binds parameters before $PSScriptRoot exists.
    [string]$ObsStatusPath = '',
    [string]$NekoTrakHome = '',
    [switch]$WhatIfMode
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ObsStatusPath)) {
    $ObsStatusPath = Join-Path $PSScriptRoot '..\obs_status.txt'
}

if ([string]::IsNullOrWhiteSpace($NekoTrakHome)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw 'APPDATA is not set; pass -NekoTrakHome explicitly.'
    }
    $NekoTrakHome = Join-Path $env:APPDATA 'NekoTrak'
}
if (-not (Test-Path -LiteralPath $NekoTrakHome)) {
    throw "NekoTrak data root not found: $NekoTrakHome"
}

$resolvedObs = [IO.Path]::GetFullPath($ObsStatusPath)
if (-not (Test-Path -LiteralPath $resolvedObs)) {
    Write-Warning "obs_status.txt does not exist yet: $resolvedObs"
    Write-Warning 'Start scripts/write_to_obs.ps1 (or let setup.ps1 register it at logon) so the file has content.'
}

# --------------------------------------------------------------------------
# Locate the per-user config
# --------------------------------------------------------------------------

$steamId = $null
$localPath = Join-Path $NekoTrakHome 'local.json'
if (Test-Path -LiteralPath $localPath) {
    try {
        $steamId = (Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json).steam_id
    }
    catch {
        $steamId = $null
    }
}
if ([string]::IsNullOrWhiteSpace([string]$steamId)) {
    $usersDir = Join-Path $NekoTrakHome 'users'
    if (Test-Path -LiteralPath $usersDir) {
        $steamId = Get-ChildItem -LiteralPath $usersDir -Directory |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty Name
    }
}
if ([string]::IsNullOrWhiteSpace([string]$steamId)) {
    throw "No steam id found under $NekoTrakHome (local.json or users/)."
}

$configPath = Join-Path (Join-Path (Join-Path $NekoTrakHome 'users') $steamId) 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Per-user config not found: $configPath"
}

Write-Host "NekoTrak config: $configPath"

# --------------------------------------------------------------------------
# Build the replacement template
# --------------------------------------------------------------------------

# NekoTrak substitutes ${...} expressions inline. Reading one file is the whole
# point: no PowerShell startup to wait for beyond the interpreter itself.
$newCommand = @'
${powershell.exe -NoProfile -Command "Get-Content -Raw '<PATH>'"}
'@
$newCommand = $newCommand.Replace('<PATH>', $resolvedObs)
$newCommand = $newCommand.Trim()

# The replacement goes into raw JSON text, so backslashes and quotes have to be
# escaped the same way the serializer would.
$jsonLiteral = $newCommand.Replace('\', '\\').Replace('"', '\"')

$raw = [IO.File]::ReadAllText($configPath)
$pattern = [regex]'\$\{powershell\.exe[^}]*\}'
$targets = @([regex]::Matches($raw, $pattern) |
    Where-Object { $_.Value -match '(ultimate_status|launch_and_pull|pull_status)\.ps1' })

if ($targets.Count -eq 0) {
    if ($raw.Contains('obs_status.txt')) {
        Write-Host 'Already pointing at obs_status.txt; nothing to do.' -ForegroundColor Green
        exit 0
    }
    throw 'No StatusCast presence template (ultimate_status / launch_and_pull / pull_status) found in the config.'
}

Write-Host "Found $($targets.Count) StatusCast presence template(s):" -ForegroundColor Cyan
foreach ($target in $targets) {
    Write-Host "  - $($target.Value)"
}
Write-Host 'Replacing with:' -ForegroundColor Cyan
Write-Host "  + $newCommand"

$updated = $raw
foreach ($target in ($targets | Sort-Object { $_.Index } -Descending)) {
    $updated = $updated.Remove($target.Index, $target.Length).Insert($target.Index, $jsonLiteral)
}

# Fail closed: the edit must still parse and must contain the new template.
$null = $updated | ConvertFrom-Json
if (-not $updated.Contains('obs_status.txt')) {
    throw 'Post-edit validation failed: obs_status.txt is not referenced.'
}

if ($WhatIfMode) {
    Write-Host 'WhatIfMode: no file was changed.' -ForegroundColor Yellow
    exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$configPath.bak-$stamp"
Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
Write-Host "Backup: $backupPath"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($configPath, $updated, $utf8NoBom)

Write-Host 'Updated.' -ForegroundColor Green
Write-Host 'Restart NekoTrak so it picks up the new template, then watch its log:' -ForegroundColor Cyan
Write-Host '  custom_text_command_failed should stop appearing (it currently fires every minute).'
if (-not (Test-Path -LiteralPath $resolvedObs)) {
    Write-Host "Remember to run scripts/write_to_obs.ps1: $resolvedObs does not exist yet." -ForegroundColor Yellow
}
