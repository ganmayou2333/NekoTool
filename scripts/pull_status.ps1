<#
.SYNOPSIS
    Read the current StatusCast snapshot and print it as one friendly line.

.DESCRIPTION
    This is the minimal NekoTool client. It talks only to the StatusCast local
    HTTP API and does not access USB or Bluetooth directly.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\pull_status.ps1

.EXAMPLE
    .\scripts\pull_status.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$StatusUrl = 'http://localhost:5099/status/',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$OutputEncoding = [Console]::OutputEncoding


try {
    $status = Invoke-RestMethod -Uri $StatusUrl -UseBasicParsing -TimeoutSec 3

    if ($Json) {
        $status | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }

    if ($status.text) {
        Write-Output $status.text
    }
    else {
        Write-Output '📱 -- | 🔋 -- | 🎵 --'
    }

    exit 0
}
catch {
    if ($Json) {
        Write-Output '{"error":"StatusCast API unreachable"}'
    }
    else {
        Write-Output '📱 -- | 🔋 -- | 🎵 --'
    }

    exit 1
}
