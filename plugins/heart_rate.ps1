# NekoTool v3.2 plugin: latest heart rate collected by scripts/hr_collector.py.
# The collector writes data/heart_rate.json; a reading is shown only while its
# timestamp is less than 10 seconds old, otherwise "❤️ --".
$ErrorActionPreference = 'SilentlyContinue'

$result = '❤️ --'
$dataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\heart_rate.json'

try {
    if (Test-Path -LiteralPath $dataPath) {
        $raw = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8
        if ($raw) {
            $data = $raw | ConvertFrom-Json
            $bpmValue = $data.bpm
            $timestampValue = $data.timestamp

            if ($null -ne $bpmValue -and $null -ne $timestampValue) {
                $bpm = 0
                $bpmOk = [int]::TryParse(([string]$bpmValue), [ref]$bpm)
                if (-not $bpmOk) {
                    $bpmDouble = 0.0
                    if ([double]::TryParse(([string]$bpmValue), [ref]$bpmDouble)) {
                        $bpm = [int][Math]::Round($bpmDouble)
                        $bpmOk = $true
                    }
                }

                $timestamp = 0.0
                $timestampOk = [double]::TryParse(([string]$timestampValue), [ref]$timestamp)
                if (-not $timestampOk) {
                    $parsed = [DateTimeOffset]::MinValue
                    if ([DateTimeOffset]::TryParse(([string]$timestampValue), [ref]$parsed)) {
                        $timestamp = $parsed.ToUnixTimeSeconds()
                        $timestampOk = $true
                    }
                }

                if ($bpmOk -and $timestampOk -and $bpm -ge 25 -and $bpm -le 250) {
                    # Accept both Unix seconds and Unix milliseconds.
                    if ($timestamp -gt 100000000000) { $timestamp = $timestamp / 1000.0 }
                    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    $age = $now - $timestamp
                    # Allow 2 s of clock skew; stale readings (>10 s) show "--".
                    if ($age -ge -2 -and $age -le 10) {
                        $result = "❤️ $bpm BPM"
                    }
                }
            }
        }
    }
}
catch {
    $result = '❤️ --'
}

Write-Output $result
