<#
.SYNOPSIS
    Build a distributable StatusCast + NekoTool release zip.

.DESCRIPTION
    Publishes StatusCast.Daemon, stages StatusCast's Python collectors and
    NekoTool's scripts/web/plugins, generates start.bat and setup.ps1, then
    creates StatusCast_v<Version>_Release.zip.

    By default the daemon is published as a self-contained single file so a
    clean Windows machine does not need the .NET runtime. Use
    -SelfContained:$false for a much smaller framework-dependent build.

.EXAMPLE
    .\scripts\build_release.ps1

.EXAMPLE
    .\scripts\build_release.ps1 -SelfContained:$false -Version 3.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = '3.3.0',
    [bool]$SelfContained = $true,
    [string]$StatusCastRoot = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot
$nekotoolRoot = Split-Path -Parent $scriptRoot

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-StatusCastRoot {
    param([string]$ExplicitRoot)

    $candidates = @()
    if ($ExplicitRoot) {
        $candidates += $ExplicitRoot
    }
    if ($env:STATUSCAST_ROOT) {
        $candidates += $env:STATUSCAST_ROOT
    }
    $candidates += (Join-Path (Split-Path -Parent $nekotoolRoot) 'StatusCast')
    $candidates += (Join-Path $nekotoolRoot 'StatusCast')

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }
        $project = Join-Path $candidate 'src\StatusCast.Daemon\StatusCast.Daemon.csproj'
        if (Test-Path -LiteralPath $project -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw '找不到 StatusCast 仓库。请把 StatusCast 放到 NekoTool 同级目录，或设置 STATUSCAST_ROOT。'
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '未找到 dotnet SDK。请安装 .NET 10 SDK。'
}

$statusCastRoot = Find-StatusCastRoot -ExplicitRoot $StatusCastRoot
$daemonProject = Join-Path $statusCastRoot 'src\StatusCast.Daemon\StatusCast.Daemon.csproj'
$statusCore = Join-Path $statusCastRoot 'status_core.py'
$statusCoreAndroid = Join-Path $statusCastRoot 'status_core_android.py'

foreach ($required in @($daemonProject, $statusCore, $statusCoreAndroid)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "缺少发布文件：$required"
    }
}

$publishRoot = Join-Path $nekotoolRoot 'publish'
$outputRoot = if ($OutputDirectory) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    $nekotoolRoot
}
if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}
$zipPath = Join-Path $outputRoot ("StatusCast_v{0}_Release.zip" -f $Version)

Write-Step "清理旧的 publish 目录"
if (Test-Path -LiteralPath $publishRoot) {
    Remove-Item -LiteralPath $publishRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null

Write-Step "发布 StatusCast.Daemon (self-contained=$SelfContained)"
$selfContainedValue = $SelfContained.ToString().ToLowerInvariant()
& dotnet publish $daemonProject `
    -c Release `
    -r win-x64 `
    --self-contained $selfContainedValue `
    -p:PublishSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $publishRoot

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish 失败，退出码 $LASTEXITCODE"
}

$daemonExe = Join-Path $publishRoot 'StatusCast.Daemon.exe'
if (-not (Test-Path -LiteralPath $daemonExe -PathType Leaf)) {
    throw "发布目录中找不到 StatusCast.Daemon.exe：$publishRoot"
}

Write-Step "整理发布结构"
Copy-Item -LiteralPath $statusCore -Destination $publishRoot -Force
Copy-Item -LiteralPath $statusCoreAndroid -Destination $publishRoot -Force

$requirements = Join-Path $statusCastRoot 'requirements.txt'
if (Test-Path -LiteralPath $requirements) {
    Copy-Item -LiteralPath $requirements -Destination (Join-Path $publishRoot 'requirements.txt') -Force
}

$nekotoolRequirements = Join-Path $nekotoolRoot 'requirements.txt'
if (Test-Path -LiteralPath $nekotoolRequirements) {
    Copy-Item -LiteralPath $nekotoolRequirements -Destination (Join-Path $publishRoot 'requirements-nekotool.txt') -Force
}

$statusConfig = Join-Path $statusCastRoot 'config.json'
if (Test-Path -LiteralPath $statusConfig) {
    Copy-Item -LiteralPath $statusConfig -Destination (Join-Path $publishRoot 'config.json') -Force
}

foreach ($folder in @('scripts', 'web', 'plugins', 'collectors')) {
    $source = Join-Path $nekotoolRoot $folder
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "缺少 NekoTool 目录：$source"
    }
    Copy-Item -LiteralPath $source -Destination $publishRoot -Recurse -Force
}

# The release keeps a single setup.ps1 at the package root; avoid shipping a
# duplicate copy inside scripts/.
$packagedScriptsSetup = Join-Path $publishRoot 'scripts\setup.ps1'
if (Test-Path -LiteralPath $packagedScriptsSetup) {
    Remove-Item -LiteralPath $packagedScriptsSetup -Force
}

Copy-Item -LiteralPath (Join-Path $nekotoolRoot 'README.md') -Destination (Join-Path $publishRoot 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $nekotoolRoot 'LICENSE') -Destination (Join-Path $publishRoot 'LICENSE') -Force

$setupSource = Join-Path $nekotoolRoot 'scripts\setup.ps1'
if (Test-Path -LiteralPath $setupSource) {
    Copy-Item -LiteralPath $setupSource -Destination (Join-Path $publishRoot 'setup.ps1') -Force
}

$startBat = @'
@echo off
setlocal
cd /d "%~dp0"

if not exist "StatusCast.Daemon.exe" (
    echo StatusCast.Daemon.exe not found.
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq StatusCast.Daemon.exe" 2>NUL | find /I "StatusCast.Daemon.exe" >NUL
if not errorlevel 1 exit /b 0

start "" /min "StatusCast.Daemon.exe"
endlocal
'@
Write-Utf8NoBom -Path (Join-Path $publishRoot 'start.bat') -Content ($startBat.TrimStart() + "`r`n")

Get-ChildItem -Path $publishRoot -Filter '*.pdb' -File -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

# Never ship local runtime state or a machine-specific generated config.
foreach ($runtimeItem in @('run', 'config.ps1')) {
    $path = Join-Path $publishRoot $runtimeItem
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

Write-Step "生成压缩包"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $publishRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force

$zipSize = (Get-Item -LiteralPath $zipPath).Length / 1MB
Write-Host ''
Write-Host "✔ 发布包已生成" -ForegroundColor Green
Write-Host "  $zipPath" -ForegroundColor White
Write-Host ("  大小：{0:N1} MB" -f $zipSize) -ForegroundColor DarkGray
Write-Host '  解压后运行 start.bat；首次使用可运行 setup.ps1 配置 StatusCast.Daemon.exe。' -ForegroundColor DarkGray
