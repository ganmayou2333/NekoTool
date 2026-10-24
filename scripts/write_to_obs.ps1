<#
.SYNOPSIS
    Continuously write the ultimate status to a text file for OBS.

.DESCRIPTION
    OBS Text (GDI+) sources can read a local text file. This script refreshes
    that file on an interval and uses UTF-8 without BOM so OBS and other tools
    see clean text.

.EXAMPLE
    .\scripts\write_to_obs.ps1

.EXAMPLE
    .\scripts\write_to_obs.ps1 -OutputPath 'D:\OBS\status.txt' -IntervalSeconds 3
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\obs_status.txt'),
    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 5,
    [string]$StatusUrl = 'http://localhost:5099/status/'
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$OutputEncoding = [Console]::OutputEncoding


$resolvedPath = [IO.Path]::GetFullPath($OutputPath)
$directory = Split-Path -Parent $resolvedPath
if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ultimate = Join-Path $PSScriptRoot 'ultimate_status.ps1'

Write-Host "Writing status to: $resolvedPath"
Write-Host "Refresh interval:  $IntervalSeconds s"
Write-Host 'Press Ctrl+C to stop.'

while ($true) {
    try {
        $lines = & $ultimate -StatusUrl $StatusUrl
        $text = ($lines | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = '📱 -- | 🔋 -- | 🎵 --'
        }

        [IO.File]::WriteAllText($resolvedPath, $text, $utf8NoBom)
        Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $text)
    }
    catch {
        Write-Warning $_.Exception.Message
    }

    Start-Sleep -Seconds $IntervalSeconds
}
