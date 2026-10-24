#Requires -Version 5.1
<#
.SYNOPSIS
    Check for NekoTool updates from GitHub and optionally fast-forward the checkout.

.DESCRIPTION
    Checks the latest GitHub Release first, then falls back to the latest Commit
    when the repository has no Release yet.

    * In a git checkout: fetch origin, report how many commits the local branch
      is behind, and with -AutoUpdate run `git pull --ff-only`.
    * In a downloaded zip (no .git): print the GitHub Release download page and
      never modify files automatically.
    * After a successful pull, print the latest 3 commits in cyan.

.PARAMETER Repo
    GitHub repository slug. Default: ganmayou2333/NekoTool

.PARAMETER Quiet
    Suppress console output and write messages to data/update.log instead.
    Used by launch_and_pull.ps1 for the silent background check.

.PARAMETER AutoUpdate
    Run `git pull --ff-only` when the git checkout is behind origin.

.PARAMETER CheckOnly
    Never pull; only report the result.

.EXAMPLE
    .\scripts\update.ps1

.EXAMPLE
    .\scripts\update.ps1 -AutoUpdate

.EXAMPLE
    .\scripts\update.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
    [string]$Repo = 'ganmayou2333/NekoTool',
    [switch]$Quiet,
    [switch]$AutoUpdate,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptRoot
$isGit = Test-Path -LiteralPath (Join-Path $projectRoot '.git')
$releasePage = "https://github.com/$Repo/releases/latest"
$logPath = Join-Path (Join-Path $projectRoot 'data') 'update.log'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
}

function Initialize-DataDirectory {
    $dataDir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $dataDir)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    }
}

function Write-UpdateMessage {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    if ($Quiet) {
        Initialize-DataDirectory
        Add-Content -LiteralPath $logPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Invoke-GitHubJson {
    param([string]$Path)

    $headers = @{
        'User-Agent' = 'NekoTool-Updater/1.0'
        'Accept'     = 'application/vnd.github+json'
    }
    $uri = "https://api.github.com/repos/$Repo$Path"
    return Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 10 -ErrorAction Stop
}

function Get-LatestReleaseFromHtml {
    # The unauthenticated GitHub API has a 60 req/h limit. When it is exhausted
    # (HTTP 403), the /releases/latest redirect still exposes the release tag.
    try {
        $response = Invoke-WebRequest -Uri $releasePage `
            -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
            -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $finalUri = $response.BaseResponse.ResponseUri.AbsoluteUri
        if ($finalUri -match '/releases/tag/([^/?#]+)') {
            return [Uri]::UnescapeDataString($Matches[1])
        }
    }
    catch {
    }
    return $null
}

function Get-LatestCommitFromAtom {
    try {
        $atomUri = "https://github.com/$Repo/commits.atom"
        $atom = (Invoke-WebRequest -Uri $atomUri `
            -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop).Content
        $sha = $null
        $message = $null
        if ($atom -match '<id>[^<]*Commit/([0-9a-fA-F]{7,40})</id>') {
            $sha = $Matches[1]
        }
        if ($atom -match '<title>\s*([^<]+?)\s*</title>') {
            $message = $Matches[1]
        }
        if ($sha) {
            return @{ Sha = $sha; Message = $message }
        }
    }
    catch {
    }
    return $null
}

function Invoke-Git {
    param([string[]]$Arguments)

    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $output = & git -C $projectRoot @Arguments 2>$null
        return @{
            ExitCode = $LASTEXITCODE
            Output   = @($output)
        }
    }
    finally {
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
}

try {
    $latestTag = $null
    $latestTitle = $null
    $latestCommit = $null
    $latestCommitMessage = $null
    $release = $null

    try {
        $release = Invoke-GitHubJson -Path '/releases/latest'
        if ($release) {
            $latestTag = [string]$release.tag_name
            $latestTitle = [string]$release.name
        }
    }
    catch {
        # 403 means the unauthenticated rate limit was hit; fall back to the
        # release page redirect below. 404 means there is no Release yet.
    }

    if (-not $latestTag) {
        $latestTag = Get-LatestReleaseFromHtml
    }

    if (-not $latestTag) {
        try {
            $commits = @(Invoke-GitHubJson -Path '/commits?per_page=1')
            if ($commits.Count -gt 0) {
                $latestCommit = [string]$commits[0].sha
                $latestCommitMessage = [string]$commits[0].commit.message
            }
        }
        catch {
            $latestCommit = $null
        }

        if (-not $latestCommit) {
            $atomCommit = Get-LatestCommitFromAtom
            if ($atomCommit) {
                $latestCommit = $atomCommit.Sha
                $latestCommitMessage = $atomCommit.Message
            }
        }
    }

    if ($latestTag) {
        Write-UpdateMessage ("[update] latest release: {0}{1}" -f $latestTag, $(if ($latestTitle) { " ($latestTitle)" } else { '' })) Cyan
    }
    elseif ($latestCommit) {
        $shortSha = $latestCommit.Substring(0, [Math]::Min(7, $latestCommit.Length))
        Write-UpdateMessage ("[update] no Release yet; latest commit: {0} {1}" -f $shortSha, $latestCommitMessage) Cyan
    }
    else {
        Write-UpdateMessage '[update] GitHub is unreachable or rate-limited; cannot check for updates.' Yellow
        exit 0
    }

    if (-not $isGit) {
        Write-UpdateMessage ("[update] this is a zip download (no .git). Download the latest release: {0}" -f $releasePage) Yellow
        exit 2
    }

    $branchResult = Invoke-Git -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    $branch = ($branchResult.Output | Select-Object -First 1)
    $headResult = Invoke-Git -Arguments @('rev-parse', '--short', 'HEAD')
    $head = ($headResult.Output | Select-Object -First 1)

    if ($branchResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
        Write-UpdateMessage '[update] unable to read the current git branch.' Yellow
        exit 1
    }

    Write-UpdateMessage ("[update] local: {0} @ {1}" -f $branch, $head) Gray

    $fetchResult = Invoke-Git -Arguments @('fetch', '--quiet', 'origin')
    if ($fetchResult.ExitCode -ne 0) {
        Write-UpdateMessage '[update] git fetch failed (network or remote problem).' Yellow
        exit 1
    }

    $remoteRef = if ($branch -eq 'HEAD') { 'origin/HEAD' } else { "origin/$branch" }
    $verifyResult = Invoke-Git -Arguments @('rev-parse', '--verify', $remoteRef)
    if ($verifyResult.ExitCode -ne 0) {
        Write-UpdateMessage ("[update] remote branch not found: {0}" -f $remoteRef) Yellow
        exit 1
    }

    $countResult = Invoke-Git -Arguments @('rev-list', '--count', "HEAD..$remoteRef")
    $behind = 0
    if ($countResult.ExitCode -eq 0) {
        $countText = [string]($countResult.Output | Select-Object -First 1)
        [void][int]::TryParse($countText, [ref]$behind)
    }

    if ($behind -le 0) {
        Write-UpdateMessage '[update] already up to date.' Green
        exit 0
    }

    Write-UpdateMessage ("[update] behind {0} by {1} commit(s)." -f $remoteRef, $behind) Yellow

    if ($CheckOnly) {
        Write-UpdateMessage '[update] -CheckOnly: not pulling.' Gray
        exit 0
    }

    if (-not $AutoUpdate) {
        Write-UpdateMessage '[update] run with -AutoUpdate to fast-forward.' Gray
        exit 0
    }

    $pullResult = Invoke-Git -Arguments @('pull', '--ff-only')
    if ($pullResult.ExitCode -ne 0) {
        Write-UpdateMessage '[update] git pull --ff-only failed. Commit/stash local changes and retry.' Red
        $pullResult.Output | ForEach-Object { Write-UpdateMessage ("  " + $_) DarkGray }
        exit 1
    }

    Write-UpdateMessage '[update] updated successfully.' Green

    $logResult = Invoke-Git -Arguments @('log', '-n', '3', '--oneline')
    foreach ($line in $logResult.Output) {
        Write-UpdateMessage ("  " + $line) Cyan
    }

    exit 0
}
catch {
    Write-UpdateMessage ("[update] failed: " + $_.Exception.Message) Red
    exit 1
}
