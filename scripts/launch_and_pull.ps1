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
    $process = Get-Process -Name 'StatusCast.Daemon', 'StatusCast.Gui', 'StatusCast' -ErrorAction SilentlyContinue
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

    # Preferred: the v3.1 headless daemon. Keep the old GUI as a fallback
    # for users upgrading from StatusCast <= v3.0.
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

    $guiRoot = Join-Path $root 'gui\StatusCast.Gui\bin'
    if (-not (Test-Path -LiteralPath $guiRoot)) {
        return $null
    }

    return Get-ChildItem -Path $guiRoot -Filter 'StatusCast.Gui.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\AppX\\' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
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

function Start-StatusCastWrapper {
    # Development fallback: run the existing GUI wrapper hidden. This is useful
    # for a packaged WinUI build where a direct exe has no package identity.
    $root = Find-StatusCastRoot -ExplicitRoot $StatusCastRoot
    if ($root) {
        $wrapper = Join-Path $root 'scripts\run_daemon.ps1'
        if (Test-Path -LiteralPath $wrapper) {
            try {
                Start-Process -FilePath 'powershell.exe' `
                    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $wrapper) `
                    -WindowStyle Hidden | Out-Null
                [Console]::Error.WriteLine("NekoTool: started StatusCast via $wrapper")
                return $true
            }
            catch {
                [Console]::Error.WriteLine("NekoTool: failed to start run_daemon.ps1: $($_.Exception.Message)")
            }
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

                # Packaged WinUI exe may lack identity. If the direct exe did
                # not come up, try the hidden dotnet wrapper for the remainder.
                if (-not $apiReady -and -not (Test-StatusCastProcess)) {
                    $wrapperStarted = Start-StatusCastWrapper
                    if ($wrapperStarted -and $waitBudget -gt 0) {
                        $apiReady = Wait-StatusCastApi -Url $StatusUrl -Seconds $waitBudget
                        $waitBudget = 0
                    }
                }
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
