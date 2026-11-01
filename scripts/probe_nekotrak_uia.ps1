<#
.SYNOPSIS
    Read NekoTrak's visible pomodoro countdown through UI Automation.

.DESCRIPTION
    The CDP route does not work on the shipped build: NekoTrak bundles a fixed
    WebView2 runtime and Tauri passes its own additional browser arguments, so
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS is ignored — a restart with
    --remote-debugging-port=9222 produced no listener, no such argument on any
    msedgewebview2 process and no DevToolsActivePort file.

    Windows UI Automation does expose the app's DOM text (the window class is
    "Tauri Window"), so the remaining time can be read without a debug port and
    without touching any NekoTrak configuration.

    This probe only reads. It reports how many labelled elements the window
    exposes and every time-looking string it can see. If no countdown appears,
    the pomodoro is simply not running — start a session and run the probe
    again.

.PARAMETER ProcessName
    Process to inspect. Defaults to NekoTrak.

.PARAMETER Json
    Emit JSON instead of a human-readable summary.

.EXAMPLE
    .\scripts\probe_nekotrak_uia.ps1

.EXAMPLE
    .\scripts\probe_nekotrak_uia.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$ProcessName = 'NekoTrak',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) {
    throw "Process '$ProcessName' is not running."
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)

# Chromium builds its accessibility tree lazily: the first query only wakes it
# up and returns a handful of nodes, so retry briefly before giving up.
$texts = New-Object System.Collections.ArrayList
$windows = 0
$elementCount = 0
for ($attempt = 1; $attempt -le 4; $attempt++) {
    $texts.Clear()
    $elementCount = 0
    $windows = 0
    foreach ($top in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $condition)) {
        $windows++
        foreach ($element in $top.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition)) {
            $elementCount++
            $name = $element.Current.Name
            if ($name -and $name.Trim()) {
                [void]$texts.Add($name.Trim())
            }
        }
    }
    if ($texts.Count -gt 10) {
        break
    }
    Start-Sleep -Milliseconds 600
}

$unique = @($texts | Select-Object -Unique)
# mm:ss and h:mm:ss both collapse to minutes:seconds here.
$countdowns = @($unique | Where-Object { $_ -match '^\d{1,3}:\d{2}$' })
$timeLike = @($unique | Where-Object { $_ -match '\d{1,3}:\d{2}' })
$started = @($unique | Where-Object { $_ -match '^(停止|暂停|继续)$' })
$idle = @($unique | Where-Object { $_ -match '^(开始|启动)$' })

$report = [pscustomobject]@{
    process   = $proc.Id
    windows   = $windows
    elements  = $elementCount
    labels    = $unique.Count
    countdown = if ($countdowns.Count) { $countdowns[0] } else { $null }
    countdowns = $countdowns
    timeLike  = $timeLike
    likelyRunning = ($started.Count -gt 0)
    hints     = @($unique | Where-Object { $_ -match '番茄|专注|休息' }) | Select-Object -First 8
}

if ($Json) {
    $report | ConvertTo-Json -Depth 4
    exit 0
}

Write-Host "process:        $($report.process) ($ProcessName)"
Write-Host "windows:        $($report.windows)   labelled elements: $($report.labels)/$($report.elements)"
Write-Host "likely running: $($report.likelyRunning)"
if ($report.countdown) {
    Write-Host "countdown:      $($report.countdown)" -ForegroundColor Green
}
else {
    Write-Host "countdown:      <none visible>" -ForegroundColor Yellow
}
if ($report.timeLike.Count -gt 1) {
    Write-Host "other times:    $($report.timeLike -join ', ')"
}
if (-not $report.countdown) {
    Write-Host ''
    Write-Host 'No countdown on screen. Start a pomodoro in NekoTrak and run this again:' -ForegroundColor Cyan
    Write-Host '  - if a countdown then appears, the remaining time is readable through UIA'
    Write-Host '  - if it still does not, the timer is drawn in a way UIA cannot see and the spike has failed'
}
