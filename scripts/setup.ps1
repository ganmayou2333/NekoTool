<#
.SYNOPSIS
    Interactive first-run setup for NekoTool.

.DESCRIPTION
    Asks for the compiled StatusCast.Daemon.exe path, writes config.ps1, copies
    the NekoTrak command to the clipboard and optionally creates a Startup
    shortcut for StatusCast.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [string]$StatusCastExe = '',
    [switch]$NoAutoStart
)

$ErrorActionPreference = 'Stop'

# Source checkout: <root>/scripts/setup.ps1
# Release package: <root>/setup.ps1
$scriptDir = $PSScriptRoot
if ((Split-Path -Leaf $scriptDir) -ieq 'scripts') {
    $projectRoot = Split-Path -Parent $scriptDir
}
else {
    $projectRoot = $scriptDir
}

$configPath = Join-Path $projectRoot 'config.ps1'
$launcher = Join-Path $projectRoot 'scripts\launch_and_pull.ps1'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}
catch {
}
$OutputEncoding = [Console]::OutputEncoding

function Write-Banner {
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '  ║          NekoTool  ·  first-run setup        ║' -ForegroundColor White
    Write-Host '  ╚══════════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

function Find-DefaultExe {
    $packagedExe = Join-Path $projectRoot 'StatusCast.Daemon.exe'
    if (Test-Path -LiteralPath $packagedExe -PathType Leaf) {
        return $packagedExe
    }

    if ($env:STATUSCAST_EXE -and (Test-Path -LiteralPath $env:STATUSCAST_EXE)) {
        return (Resolve-Path -LiteralPath $env:STATUSCAST_EXE).Path
    }

    $root = Join-Path (Split-Path -Parent $projectRoot) 'StatusCast'
    $searchRoots = @(
        (Join-Path $root 'src\StatusCast.Daemon\bin'),
        (Join-Path $root 'dist')
    )
    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot)) {
            continue
        }
        $daemon = Get-ChildItem -Path $searchRoot -Filter 'StatusCast.Daemon.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($daemon) {
            return $daemon
        }
    }

    return $null
}

function Find-StatusCastRoot {
    param([string]$ExePath)

    $directory = Split-Path -Parent $ExePath
    for ($i = 0; $i -lt 12 -and $directory; $i++) {
        if (Test-Path -LiteralPath (Join-Path $directory 'status_core.py')) {
            return $directory
        }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) {
            break
        }
        $directory = $parent
    }

    return Split-Path -Parent $ExePath
}

function Set-ConfigValue {
    param([string]$Name, [string]$Value)

    $escaped = $Value.Replace("'", "''")
    return "`$$Name = '$escaped'"
}

function Create-StartupShortcut {
    param([string]$ExePath)

    $startup = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startup 'StatusCast.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $ExePath
    $shortcut.WorkingDirectory = Split-Path -Parent $ExePath
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'StatusCast'
    $shortcut.Save()
    return $shortcutPath
}

Write-Banner

# Load an existing config.ps1 so rerunning setup keeps the previous path.
if (Test-Path -LiteralPath $configPath) {
    try {
        . $configPath
        if ([string]::IsNullOrWhiteSpace($StatusCastExe) -and $NekoToolStatusCastExe) {
            $StatusCastExe = $NekoToolStatusCastExe
        }
        Write-Host "  发现已有配置：$configPath" -ForegroundColor DarkGray
        if ($StatusCastExe -and -not (Test-Path -LiteralPath $StatusCastExe -PathType Leaf)) {
            Write-Host '  旧配置中的 exe 已不存在，重新自动检测。' -ForegroundColor Yellow
            $StatusCastExe = ''
        }
    }
    catch {
        Write-Host '  已有 config.ps1 无法读取，将重新生成。' -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($StatusCastExe)) {
    $defaultExe = Find-DefaultExe
    if ($defaultExe) {
        Write-Host "  自动检测到：$defaultExe" -ForegroundColor DarkGray
        Write-Host ''
        $inputPath = Read-Host "  StatusCast.Daemon.exe 路径（回车使用自动检测）"
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            $StatusCastExe = $defaultExe
        }
        else {
            $StatusCastExe = $inputPath.Trim('"').Trim()
        }
    }
    else {
        Write-Host '  没有自动找到 StatusCast.Daemon.exe。' -ForegroundColor Yellow
        $StatusCastExe = (Read-Host '  请输入 StatusCast.Daemon.exe 的绝对路径').Trim('"').Trim()
    }
}

while ([string]::IsNullOrWhiteSpace($StatusCastExe) -or -not (Test-Path -LiteralPath $StatusCastExe -PathType Leaf)) {
    if (-not [string]::IsNullOrWhiteSpace($StatusCastExe)) {
        Write-Host "  路径不存在：$StatusCastExe" -ForegroundColor Red
    }
    $StatusCastExe = (Read-Host '  请重新输入 StatusCast.Daemon.exe 的绝对路径').Trim('"').Trim()
}

$StatusCastExe = (Resolve-Path -LiteralPath $StatusCastExe).Path
$StatusCastRoot = Find-StatusCastRoot -ExePath $StatusCastExe

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "启动脚本不存在：$launcher"
}

$nekotrakCommand = '${(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $launcher + '")}'

$configLines = @(
    '# Generated by NekoTool setup.ps1. Do not commit this file.',
    (Set-ConfigValue -Name 'NekoToolStatusCastExe' -Value $StatusCastExe),
    (Set-ConfigValue -Name 'NekoToolStatusCastRoot' -Value $StatusCastRoot),
    (Set-ConfigValue -Name 'NekoToolStatusUrl' -Value 'http://localhost:5099/status/')
)
Set-Content -LiteralPath $configPath -Value $configLines -Encoding UTF8

Write-Host ''
Write-Host '  ✔ 配置已保存' -ForegroundColor Green
Write-Host "    $configPath" -ForegroundColor DarkGray

$copied = $false
try {
    Set-Clipboard -Value $nekotrakCommand
    $copied = $true
}
catch {
    try {
        $nekotrakCommand | clip.exe
        $copied = $true
    }
    catch {
    }
}

Write-Host ''
Write-Host '  NekoTrak 自定义文本（已尝试复制到剪贴板）：' -ForegroundColor Cyan
Write-Host ''
Write-Host "  $nekotrakCommand" -ForegroundColor White
Write-Host ''
if (-not $copied) {
    Write-Host '  ⚠ 剪贴板不可用，请手动复制上面这行。' -ForegroundColor Yellow
}
else {
    Write-Host '  ✔ 已复制到剪贴板，直接粘贴到 NekoTrak。' -ForegroundColor Green
}

if (-not $NoAutoStart) {
    Write-Host ''
    $answer = Read-Host '  是否创建开机自启快捷方式？[y/N]'
    if ($answer -match '^[Yy]') {
        try {
            $shortcut = Create-StartupShortcut -ExePath $StatusCastExe
            Write-Host "  ✔ 已创建：$shortcut" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ 创建快捷方式失败：$($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host '  已跳过开机自启。' -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host '  完成。打开 NekoTrak，把上面的命令粘贴到自定义文本即可。' -ForegroundColor Cyan
Write-Host ''
