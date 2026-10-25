<#
.SYNOPSIS
    Start the NekoTool local web dashboard.

.DESCRIPTION
    Starts scripts/dashboard_server.py with the project virtualenv and opens
    http://127.0.0.1:5100 in the default browser. Press Ctrl+C to stop.

.EXAMPLE
    .\scripts\dashboard.ps1

.EXAMPLE
    .\scripts\dashboard.ps1 -Port 5101 -NoBrowser
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 5100,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}
catch {
}
$OutputEncoding = [Console]::OutputEncoding

$scriptDir = $PSScriptRoot
if ((Split-Path -Leaf $scriptDir) -ieq 'scripts') {
    $projectRoot = Split-Path -Parent $scriptDir
}
else {
    $projectRoot = $scriptDir
}

$server = Join-Path $scriptDir 'dashboard_server.py'
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
    Write-Host "[dashboard] 找不到服务脚本：$server" -ForegroundColor Red
    exit 1
}

$python = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        Write-Host '[dashboard] 找不到 Python。请先创建项目虚拟环境：' -ForegroundColor Red
        Write-Host '  py -3 -m venv .venv' -ForegroundColor Yellow
        exit 1
    }
    $python = $pythonCommand.Source
}

Write-Host ''
Write-Host '  NekoTool · Dashboard' -ForegroundColor Cyan
Write-Host "  Project : $projectRoot" -ForegroundColor DarkGray
Write-Host "  Python  : $python" -ForegroundColor DarkGray
Write-Host "  URL     : http://127.0.0.1:$Port/" -ForegroundColor Green
Write-Host ''

$serverArgs = @($server, '--port', "$Port")
if (-not $NoBrowser) {
    $serverArgs += '--open'
}

& $python @serverArgs
exit $LASTEXITCODE
