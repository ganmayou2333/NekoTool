param(
    [string]$BrowserPath = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$mockPath = Join-Path $PSScriptRoot "mock_data.json"
$widgetPath = Join-Path $root "web\widget.html"
$outputPath = Join-Path $root "web\preview-mock.png"
$tempHtml = Join-Path $root "web\.preview-mock.html"
$profile = Join-Path $env:TEMP ("nekotool-preview-" + [guid]::NewGuid().ToString("N"))

if (-not (Test-Path -LiteralPath $mockPath)) {
    throw "Missing mock data: $mockPath"
}
if (-not (Test-Path -LiteralPath $widgetPath)) {
    throw "Missing widget: $widgetPath"
}

if ([string]::IsNullOrWhiteSpace($BrowserPath)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe")
    )

    $BrowserPath = $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}

if (-not $BrowserPath) {
    throw "Edge or Chrome not found. Pass -BrowserPath explicitly."
}

$mockJson = Get-Content -LiteralPath $mockPath -Raw -Encoding UTF8 |
    ConvertFrom-Json |
    ConvertTo-Json -Depth 8 -Compress

$html = [IO.File]::ReadAllText($widgetPath, [Text.Encoding]::UTF8)
$injection = "<script>window.__NEKOTOOL_MOCK__ = $mockJson;</script>"

$previewHtml = $html.Replace("</head>", "$injection`n</head>")
[IO.File]::WriteAllText($tempHtml, $previewHtml, (New-Object Text.UTF8Encoding($false)))
New-Item -ItemType Directory -Path $profile -Force | Out-Null

try {
    $previewUri = ([Uri]$tempHtml).AbsoluteUri
    $arguments = @(
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--user-data-dir=$profile",
        "--window-size=800,300",
        "--virtual-time-budget=3000",
        "--screenshot=$outputPath",
        $previewUri
    )

    $process = Start-Process -FilePath $BrowserPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Browser exited with code $($process.ExitCode)"
    }

    # Some Edge builds hand off to a child process; wait for the file.
    for ($i = 0; $i -lt 50 -and -not (Test-Path -LiteralPath $outputPath); $i++) {
        Start-Sleep -Milliseconds 200
    }

    if (-not (Test-Path -LiteralPath $outputPath)) {
        throw "Screenshot was not created: $outputPath"
    }

    Write-Host "Preview written to: $outputPath"
}
finally {
    Remove-Item -LiteralPath $tempHtml -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue
}
