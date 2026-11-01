<#
.SYNOPSIS
    Combine iPhone status, CPU, memory, network throughput and local time.

.DESCRIPTION
    This is the "ultimate" one-line status used by NekoTrak or any other text
    overlay. It reads the phone from StatusCast's local HTTP API and samples
    Windows performance counters for one second.

.EXAMPLE
    .\scripts\ultimate_status.ps1

.EXAMPLE
    .\scripts\ultimate_status.ps1 -SampleSeconds 0.5

.EXAMPLE
    .\scripts\ultimate_status.ps1 -MockMode

.EXAMPLE
    .\scripts\ultimate_status.ps1 -MockMode -MockHardware
#>
[CmdletBinding()]
param(
    [string]$StatusUrl = 'http://localhost:5099/status/',
    [ValidateRange(0.2, 5.0)]
    [double]$SampleSeconds = 1.0,
    [switch]$MockMode,
    [switch]$MockHardware,
    [ValidateRange(1, 30)]
    [int]$PluginTimeoutSeconds = 2
)

$ErrorActionPreference = 'SilentlyContinue'

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$OutputEncoding = [Console]::OutputEncoding


function Format-DeviceText {
    param($Device)

    if ($null -eq $Device) {
        return '📱 -- | 🔋 -- | 🎵 --'
    }

    $icon = if ($Device.platform -eq 'android') { '🤖' } else { '📱' }
    $name = if ($Device.displayName) { $Device.displayName }
        elseif ($Device.model) { $Device.model }
        else { '未知机型' }

    if ($null -eq $Device.batteryLevel) {
        $battery = '🔋 未知'
    }
    elseif ($Device.isCharging -eq $true) {
        $battery = "🔋 $($Device.batteryLevel)% ⚡"
    }
    else {
        $battery = "🔋 $($Device.batteryLevel)%"
    }

    if ($Device.mediaTitle) {
        $media = if ($Device.mediaArtist) {
            "🎵 $($Device.mediaTitle) - $($Device.mediaArtist)"
        }
        else {
            "🎵 $($Device.mediaTitle)"
        }
    }
    else {
        $media = '🎵 暂无播放'
    }

    # "只拿到存活信息" must be readable in the text, not just in the JSON:
    # a phone served over the LAN fallback shows which channel answered.
    $channel = ''
    if ($null -ne $Device.transport -and $Device.transport.degraded -eq $true) {
        $active = [string]$Device.transport.active
        $label = if ($active) { $active.ToUpperInvariant() } else { '降级' }
        $channel = " ($label)"
    }

    return "$icon $name$channel | $battery | $media"
}

function Get-MockPhoneText {
    $mockPath = Join-Path $PSScriptRoot 'mock_data.json'
    if (-not (Test-Path -LiteralPath $mockPath)) {
        return '📱 -- | 🔋 -- | 🎵 --'
    }

    try {
        $mock = Get-Content -LiteralPath $mockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $devices = @($mock.devices)
        $primary = $devices |
            Where-Object { $_.id -eq $mock.primaryDeviceId } |
            Select-Object -First 1

        if ($null -eq $primary) {
            $primary = $devices | Select-Object -First 1
        }

        if ($null -ne $primary) {
            if ($primary.text) {
                return [string]$primary.text
            }
            return Format-DeviceText $primary
        }
    }
    catch {
    }

    return '📱 -- | 🔋 -- | 🎵 --'
}

function Get-PhoneText {
    try {
        $status = Invoke-RestMethod -Uri $StatusUrl -UseBasicParsing -TimeoutSec 5
        $script:StatusData = $status

        # StatusCast v3: only a devices array is guaranteed.
        if ($null -ne $status.devices) {
            $devices = @($status.devices)
            # The primary line only accepts real phones. Battery-carrying
            # macos/linux nodes (e.g. a MacBook) must never be picked here,
            # otherwise they would be rendered with the phone icon.
            $primary = $devices |
                Where-Object { $_.platform -eq 'ios' -and $null -ne $_.batteryLevel } |
                Select-Object -First 1
            if ($null -eq $primary) {
                $primary = $devices |
                    Where-Object {
                        ($_.platform -eq 'ios' -or $_.platform -eq 'android') -and ($null -ne $_.batteryLevel)
                    } |
                    Select-Object -First 1
            }
            if ($null -eq $primary) {
                $primary = $devices |
                    Where-Object { $_.platform -eq 'ios' -or $_.platform -eq 'android' } |
                    Select-Object -First 1
            }

            if ($null -ne $primary) {
                if ($primary.text) {
                    return [string]$primary.text
                }
                return Format-DeviceText $primary
            }
        }

        # Backward compatibility with StatusCast <= v2.
        if ($status.text) {
            return [string]$status.text
        }
    }
    catch {
    }

    return '📱 -- | 🔋 -- | 🎵 --'
}

function Get-ConsoleTexts {
    $lines = @()
    if ($null -eq $script:StatusData) { return $lines }

    foreach ($dev in @($script:StatusData.devices)) {
        if ($dev.platform -ne 'console') { continue }

        # macos/linux nodes get their own rows in C3; only consoles here.

        $c = $dev.console
        $name = if ($dev.displayName) { $dev.displayName }
            elseif ($dev.model) { $dev.model }
            else { '主机' }

        # A device-level error (stale pipeline, failed refresh) wins over the
        # last known console.online so a stale snapshot never reports online;
        # otherwise console.online decides, and statusText carries the text.
        if ($dev.error -or ($null -ne $c -and $c.online -eq $false)) {
            $state = if ($null -ne $c -and $c.statusText) { [string]$c.statusText } else { '离线' }
        }
        else {
            $state = '在线'
        }

        $lines += "🎮 $name $state"
    }

    return $lines
}

function Get-NodeTexts {
    $lines = @()
    if ($null -eq $script:StatusData) { return $lines }

    foreach ($dev in @($script:StatusData.devices)) {
        $platform = [string]$dev.platform
        if ($platform -ne 'macos' -and $platform -ne 'linux') { continue }

        $n = $dev.node
        $icon = if ($platform -eq 'macos') { '💻' } else { '🐧' }
        $name = if ($dev.displayName) { $dev.displayName }
            elseif ($dev.model) { $dev.model }
            else { $platform }

        if ($dev.error -or ($null -ne $n -and $n.online -eq $false)) {
            $state = if ($null -ne $n -and $n.statusText) { [string]$n.statusText } else { '离线' }
        }
        else {
            $state = '在线'
        }

        $extra = ''
        if ($null -ne $dev.batteryLevel) {
            $bolt = if ($dev.isCharging -eq $true) { ' ⚡' } else { '' }
            $extra += " · 🔋 $($dev.batteryLevel)%$bolt"
        }
        if ($null -ne $dev.transport -and $dev.transport.degraded -eq $true) {
            $extra += ' · 仅探活'
        }

        $lines += "$icon $name $state$extra"
    }

    return $lines
}

function Get-BleTexts {
    $lines = @()
    if ($null -eq $script:StatusData) { return $lines }

    foreach ($dev in @($script:StatusData.devices)) {
        if ([string]$dev.platform -ne 'ble') { continue }

        $b = $dev.ble
        $name = if ($dev.displayName) { $dev.displayName }
            elseif ($dev.model) { $dev.model }
            elseif ($null -ne $b -and $b.name) { $b.name }
            else { 'BLE 设备' }

        if ($dev.error) { $state = '错误' }
        elseif ($null -ne $b -and $b.connected -eq $true) { $state = '已连接' }
        elseif ($null -ne $b -and $b.statusText) { $state = [string]$b.statusText }
        else { $state = '未发现' }

        $extra = ''
        if ($null -ne $dev.batteryLevel) { $extra += " · 🔋 $($dev.batteryLevel)%" }
        if ($null -ne $b -and $null -ne $b.heartRate) { $extra += " · ❤️ $($b.heartRate) BPM" }

        $lines += "📶 $name $state$extra"
    }

    return $lines
}

function Get-PluginTexts {
    $pluginDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'plugins'
    if (-not (Test-Path -LiteralPath $pluginDirectory)) {
        return @()
    }

    $texts = @()
    $scripts = Get-ChildItem -LiteralPath $pluginDirectory -Filter '*.ps1' -File |
        Sort-Object Name

    foreach ($script in $scripts) {
        $job = $null
        try {
            $job = Start-Job -ScriptBlock {
                param($pluginPath)
                & $pluginPath
            } -ArgumentList $script.FullName

            $finished = Wait-Job -Job $job -Timeout $PluginTimeoutSeconds
            if ($null -ne $finished) {
                $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
                $line = @($output |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { $_ }) |
                    Select-Object -First 1
                if ($line) {
                    $texts += $line
                }
            }
        }
        catch {
            # Bad plugins are isolated and skipped.
        }
        finally {
            if ($null -ne $job) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $texts
}

function Get-CpuPercent {
    try {
        $value = Get-CimInstance -ClassName Win32_Processor |
            Measure-Object -Property LoadPercentage -Average |
            Select-Object -ExpandProperty Average

        if ($null -ne $value) {
            return [int][Math]::Round($value)
        }
    }
    catch {
    }

    return $null
}

function Get-MemoryPercent {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize
        $free = [double]$os.FreePhysicalMemory

        if ($total -gt 0) {
            return [int][Math]::Round((1.0 - ($free / $total)) * 100)
        }
    }
    catch {
    }

    return $null
}

function Get-NetworkCounters {
    try {
        $stats = Get-NetAdapterStatistics
        $rx = ($stats | Measure-Object -Property ReceivedBytes -Sum).Sum
        $tx = ($stats | Measure-Object -Property SentBytes -Sum).Sum
        return @([double]$rx, [double]$tx)
    }
    catch {
        return $null
    }
}

function Format-Rate {
    param([double]$BytesPerSecond)

    if ($BytesPerSecond -ge 1MB) {
        return ('{0:0.0}M' -f ($BytesPerSecond / 1MB))
    }
    if ($BytesPerSecond -ge 1KB) {
        return ('{0:0}K' -f ($BytesPerSecond / 1KB))
    }

    return ('{0:0}B' -f $BytesPerSecond)
}

function Format-Percent {
    param($Value)

    if ($null -eq $Value) {
        return '--'
    }

    return "$Value%"
}

$phone = if ($MockMode) { Get-MockPhoneText } else { Get-PhoneText }

$rxRate = $null
$txRate = $null
if ($MockHardware) {
    $cpu = 33
    $memory = 63
    $rxRate = 1.2MB
    $txRate = 86KB
}
else {
    $cpu = Get-CpuPercent
    $memory = Get-MemoryPercent

    $before = Get-NetworkCounters
    Start-Sleep -Milliseconds ([int]($SampleSeconds * 1000))
    $after = Get-NetworkCounters

    if ($null -ne $before -and $null -ne $after) {
        $rxRate = [Math]::Max(0, ($after[0] - $before[0]) / $SampleSeconds)
        $txRate = [Math]::Max(0, ($after[1] - $before[1]) / $SampleSeconds)
    }
}

$network = if ($null -eq $rxRate) {
    '🌐 --'
}
else {
    "🌐 ↓$(Format-Rate $rxRate) ↑$(Format-Rate $txRate)"
}

$clock = Get-Date -Format 'HH:mm'
$pluginTexts = Get-PluginTexts

$parts = @(
    $phone,
    "🖥 $(Format-Percent $cpu)",
    "🧠 $(Format-Percent $memory)",
    $network,
    "🕐 $clock"
)
$parts += Get-ConsoleTexts
$parts += Get-NodeTexts
$parts += Get-BleTexts
$parts += $pluginTexts

Write-Output ($parts -join ' | ')
