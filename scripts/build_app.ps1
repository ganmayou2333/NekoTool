<#
.SYNOPSIS
    Build NekoTool.App (WinUI 3 + WebView2) as a single-file executable.

.DESCRIPTION
    Publishes the WinUI 3 shell to .\dist and copies the exe to the NekoTool
    root when the publish output is a true single file.

    Requires the .NET 10 SDK and the Microsoft Edge WebView2 Evergreen Runtime.
    The default build is self-contained (bundles .NET + Windows App SDK, larger).
    Use -FrameworkDependent for a smaller build that needs .NET 10 Desktop Runtime.

    Windows App SDK native components may be extracted to a temporary folder on
    first launch; this is expected for WinUI 3 single-file deployment.

.EXAMPLE
    .\scripts\build_app.ps1

.EXAMPLE
    .\scripts\build_app.ps1 -FrameworkDependent
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$FrameworkDependent
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ((Split-Path -Leaf $scriptDir) -ieq 'scripts') {
    $projectRoot = Split-Path -Parent $scriptDir
}
else {
    $projectRoot = $scriptDir
}

$project = Join-Path $projectRoot 'NekoTool.App\NekoTool.App.csproj'
$dist = Join-Path $projectRoot 'dist'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '找不到 dotnet。请安装 .NET 10 SDK。'
}
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
    throw "找不到项目文件：$project"
}

if (Test-Path -LiteralPath $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}

$selfContainedValue = if ($FrameworkDependent) { 'false' } else { 'true' }

Write-Host ''
Write-Host '  NekoTool.App · WinUI 3 publish' -ForegroundColor Cyan
Write-Host "  Project       : $project" -ForegroundColor DarkGray
Write-Host "  Runtime       : $Runtime" -ForegroundColor DarkGray
Write-Host "  SelfContained : $selfContainedValue" -ForegroundColor DarkGray
Write-Host ''

$publishArgs = @(
    'publish',
    $project,
    '-c', $Configuration,
    '-r', $Runtime,
    '--self-contained', $selfContainedValue,
    '-p:WindowsPackageType=None',
    '-p:WindowsAppSDKSelfContained=true',
    '-p:PublishSingleFile=true',
    '-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:PublishTrimmed=false',
    '-p:PublishReadyToRun=false',
    '-p:DebugType=None',
    '-p:DebugSymbols=false',
    '-o', $dist
)

& dotnet @publishArgs
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish 失败，退出码 $LASTEXITCODE"
}

$publishedExe = Join-Path $dist 'NekoTool.App.exe'
if (-not (Test-Path -LiteralPath $publishedExe -PathType Leaf)) {
    throw "发布失败：找不到 $publishedExe"
}

$distFiles = @(Get-ChildItem -LiteralPath $dist -File)
$rootExe = Join-Path $projectRoot 'NekoTool.App.exe'
if ($distFiles.Count -eq 1) {
    Copy-Item -LiteralPath $publishedExe -Destination $rootExe -Force
}
else {
    $rootExe = $null
}

Write-Host ''
Write-Host '  ✔ NekoTool.App 发布完成' -ForegroundColor Green
Write-Host "    $publishedExe" -ForegroundColor Gray
if ($rootExe) {
    Write-Host "    $rootExe" -ForegroundColor Gray
}
else {
    Write-Host '    发布目录包含多个文件，未复制到根目录；请从 dist 运行。' -ForegroundColor Yellow
}
Write-Host "    文件数：$($distFiles.Count)" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  需要 Microsoft Edge WebView2 Evergreen Runtime。' -ForegroundColor DarkGray
Write-Host '  双击 exe 即可启动；关闭窗口不会停止 Python/StatusCast。' -ForegroundColor DarkGray
