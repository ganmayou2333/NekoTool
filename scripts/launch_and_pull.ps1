<#
.SYNOPSIS
    Ensure StatusCast is running, then print the NekoTool ultimate status.

.DESCRIPTION
    NekoTrak calls this script through its ${...} macro. If the StatusCast API
    is not ready, the script starts StatusCast once, waits up to 5 seconds for
    the API, and then delegates to ultimate_status.ps1.

.PARAMETER StatusUrl
    StatusCast API endpoint. Defaults to http://localhost:5099/status/.

.PARAMETER StatusCastRoot
    Optional StatusCast repository root. Defaults to a sibling directory of
    NekoTool, or the STATUSCAST_ROOT environment variable.

.PARAMETER StatusCastExe
    Optional explicit path to StatusCast.Daemon.exe.

.PARAMETER TimeoutSeconds
    Maximum wait after launching StatusCast.

.EXAMPLE
    .\scripts\launch_and_pull.ps1

.EXAMPLE
    .\scripts\launch_and_pull.ps1 -StatusCastExe 'D:\Apps\StatusCast.Daemon.exe'
#>
[CmdletBinding()]
param(
    [string]$StatusUrl = 'http://localhost:5099/status/',
    [string]$StatusCastRoot = '',
    [string]$StatusCastExe = '',
    [ValidateRange(1, 30)]
    [int]$TimeoutSeconds = 5
)

$ErrorActionPreference = 'SilentlyContinue'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
}
catch {
}
$OutputEncoding = [Console]::OutputEncoding

$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptRoot

function Invoke-BackgroundUpdateCheck {
    # Throttle the silent updater to once every 6 hours. The state file lives
    # under data/ and is ignored by Git.
    try {
        $dataDir = Join-Path $projectRoot 'data'
        if (-not (Test-Path -LiteralPath $dataDir)) {
            New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        }

        $statePath = Join-Path $dataDir 'update_check.json'
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $lastCheck = 0
        if (Test-Path -LiteralPath $statePath) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($state.lastCheck) { $lastCheck = [int64]$state.lastCheck }
            }
            catch {
            }
        }

        if (($now - $lastCheck) -lt 21600) {
            return
        }

        $stateJson = @{ lastCheck = $now } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($statePath, $stateJson, (New-Object Text.UTF8Encoding($false)))

        $updateScript = Join-Path $scriptRoot 'update.ps1'
        if (-not (Test-Path -LiteralPath $updateScript)) {
            return
        }

        # Fire-and-forget: NekoTrak must never wait for git/network work.
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-WindowStyle', 'Hidden',
                '-File', $updateScript,
                '-Quiet', '-AutoUpdate'
            ) `
            -WorkingDirectory $projectRoot `
            -WindowStyle Hidden | Out-Null
    }
    catch {
        # Update failures must never break status polling.
    }
}

# setup.ps1 writes this file. Values are optional; command-line parameters
# and environment variables still take precedence.
$configPath = Join-Path $projectRoot 'config.ps1'
if (Test-Path -LiteralPath $configPath) {
    try {
        . $configPath
        if ([string]::IsNullOrWhiteSpace($StatusCastExe) -and $NekoToolStatusCastExe) {
            $StatusCastExe = $NekoToolStatusCastExe
        }
        if ([string]::IsNullOrWhiteSpace($StatusCastRoot) -and $NekoToolStatusCastRoot) {
            $StatusCastRoot = $NekoToolStatusCastRoot
        }
        if ($StatusUrl -eq 'http://localhost:5099/status/' -and $NekoToolStatusUrl) {
            $StatusUrl = $NekoToolStatusUrl
        }
    }
    catch {
        [Console]::Error.WriteLine("NekoTool: config.ps1 could not be loaded: $($_.Exception.Message)")
    }
}

# Silent daily-ish update check. It never blocks the status request.
Invoke-BackgroundUpdateCheck

$mutex = $null
$hasLock = $false

function Test-StatusCastApi {
    param([string]$Url)

    try {
        $status = Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
        return ($null -ne $status -and ($null -ne $status.devices -or $null -ne $status.text))
    }
    catch {
        return $false
    }
}

function Test-StatusCastProcess {
    $process = Get-Process -Name 'StatusCast.Daemon' -ErrorAction SilentlyContinue
    return ($null -ne $process)
}

function Find-StatusCastRoot {
    param([string]$ExplicitRoot)

    if ($ExplicitRoot -and (Test-Path -LiteralPath $ExplicitRoot)) {
        return (Resolve-Path -LiteralPath $ExplicitRoot).Path
    }

    if ($env:STATUSCAST_ROOT -and (Test-Path -LiteralPath $env:STATUSCAST_ROOT)) {
        return (Resolve-Path -LiteralPath $env:STATUSCAST_ROOT).Path
    }

    $sibling = Join-Path (Split-Path -Parent $projectRoot) 'StatusCast'
    if (Test-Path -LiteralPath $sibling) {
        return $sibling
    }

    return $null
}

function Find-StatusCastExe {
    param([string]$ExplicitExe)

    if ($ExplicitExe -and (Test-Path -LiteralPath $ExplicitExe)) {
        return (Resolve-Path -LiteralPath $ExplicitExe).Path
    }

    if ($env:STATUSCAST_EXE -and (Test-Path -LiteralPath $env:STATUSCAST_EXE)) {
        return (Resolve-Path -LiteralPath $env:STATUSCAST_EXE).Path
    }

    # A release zip places the daemon next to scripts/ and web/.
    $packagedExe = Join-Path $projectRoot 'StatusCast.Daemon.exe'
    if (Test-Path -LiteralPath $packagedExe -PathType Leaf) {
        return (Resolve-Path -LiteralPath $packagedExe).Path
    }

    $root = Find-StatusCastRoot -ExplicitRoot $StatusCastRoot
    if (-not $root) {
        return $null
    }

    # Preferred: the v3.1+ headless daemon.
    $daemonRoots = @(
        (Join-Path $root 'src\StatusCast.Daemon\bin'),
        (Join-Path $root 'dist')
    )
    foreach ($searchRoot in $daemonRoots) {
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

function Start-StatusCast {
    $exe = Find-StatusCastExe -ExplicitExe $StatusCastExe
    if ($exe) {
        try {
            Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -WindowStyle Minimized | Out-Null
            [Console]::Error.WriteLine("NekoTool: started StatusCast: $exe")
            return $true
        }
        catch {
            [Console]::Error.WriteLine("NekoTool: failed to start $exe : $($_.Exception.Message)")
        }
    }

    return $false
}

function Wait-StatusCastApi {
    param([string]$Url, [int]$Seconds)

    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-StatusCastApi -Url $Url) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    }

    return (Test-StatusCastApi -Url $Url)
}

# A named mutex prevents two NekoTrak refreshes from launching StatusCast
# at the same time. If another instance owns it, this one only waits.
try {
    $mutex = New-Object System.Threading.Mutex($false, 'NekoTool.StatusCast.Launcher')
    $hasLock = $mutex.WaitOne(0)
}
catch {
    $hasLock = $false
}

try {
    $apiReady = Test-StatusCastApi -Url $StatusUrl

    if (-not $apiReady) {
        $processRunning = Test-StatusCastProcess
        $started = $false
        $waitBudget = 0

        if (-not $processRunning -and $hasLock) {
            $started = Start-StatusCast
            if ($started) {
                $firstWait = [Math]::Min(3, $TimeoutSeconds)
                $waitBudget = [Math]::Max(0, $TimeoutSeconds - $firstWait)
                $apiReady = Wait-StatusCastApi -Url $StatusUrl -Seconds $firstWait
            }
        }

        if (-not $apiReady) {
            if ($processRunning -or -not $hasLock) {
                $waitBudget = $TimeoutSeconds
            }
            if ($waitBudget -gt 0) {
                $apiReady = Wait-StatusCastApi -Url $StatusUrl -Seconds $waitBudget
            }
        }
    }

    $ultimate = Join-Path $scriptRoot 'ultimate_status.ps1'
    if (Test-Path -LiteralPath $ultimate) {
        $statusLine = & $ultimate -StatusUrl $StatusUrl
        if ($statusLine) {
            Write-Output $statusLine
        }
    }

    if (-not $apiReady) {
        exit 1
    }

    exit 0
}
finally {
    if ($hasLock -and $null -ne $mutex) {
        try {
            $mutex.ReleaseMutex()
        }
        catch {
        }
    }

    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
}
