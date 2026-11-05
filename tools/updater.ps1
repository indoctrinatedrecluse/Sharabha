<#
================================================================================
  SHARABHA // ASHTAMURTI AUTO-UPDATER ENGINE (अद्यतन संशुद्धि)
  GitHub Release Check, Changelog Markdown Inquest, & Live Consecration
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Download,
    [switch]$Install,
    [switch]$Dismiss,
    [int]$ActiveTab = -1,
    [string]$TargetSetupPath = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$stateFile = Join-Path $projectDir "src\ui\updater_state.slint"
$currentVersion = "v0.5.1"
$repoUri = "https://api.github.com/repos/indoctrinatedrecluse/Sharabha/releases/latest"
$cacheFile = Join-Path $env:TEMP "sharabha_latest_release.json"

function Escape-SlintString([string]$str) {
    if (-not $str) { return "" }
    return $str.Replace("\", "\\").Replace('"', '\"').Replace("`r`n", "\n").Replace("`n", "\n").Replace("`r", "\n")
}

function Write-UpdaterState([hashtable]$p) {
    $hasUpdate = if ($p.ContainsKey("has_update")) { $p.has_update.ToString().ToLower() } else { "false" }
    $isChecking = if ($p.ContainsKey("is_checking")) { $p.is_checking.ToString().ToLower() } else { "false" }
    $isDownloading = if ($p.ContainsKey("is_downloading")) { $p.is_downloading.ToString().ToLower() } else { "false" }
    $isReady = if ($p.ContainsKey("is_ready")) { $p.is_ready.ToString().ToLower() } else { "false" }
    $isModalOpen = if ($p.ContainsKey("is_modal_open")) { $p.is_modal_open.ToString().ToLower() } else { "false" }
    $tabVal = if ($p.ContainsKey("active_tab")) { [int]$p.active_tab } else { $ActiveTab }
    $curVer = if ($p.ContainsKey("current_version")) { $p.current_version } else { $currentVersion }
    $latVer = if ($p.ContainsKey("latest_version")) { $p.latest_version } else { $currentVersion }
    $title = Escape-SlintString $p.release_title
    $date = if ($p.ContainsKey("release_date")) { $p.release_date } else { (Get-Date -Format "yyyy-MM-dd") }
    $notes = Escape-SlintString $p.release_notes
    $progVal = if ($p.ContainsKey("download_progress")) { [float]$p.download_progress } else { 0.0 }
    $progressStr = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0.00}", $progVal)
    $status = Escape-SlintString $p.status_text
    $setup = Escape-SlintString $p.setup_path

    $lines = @(
        "// Sharabha Dynamic Auto-Updater State Codex",
        "// Reactively updated by tools/updater.ps1",
        "export global UpdaterState {",
        "    in property <bool> has_update: $hasUpdate;",
        "    in property <bool> is_checking: $isChecking;",
        "    in property <bool> is_downloading: $isDownloading;",
        "    in property <bool> is_ready: $isReady;",
        "    in property <bool> is_modal_open: $isModalOpen;",
        "    in property <int> active_tab: $tabVal;",
        "    in property <string> current_version: `"$curVer`";",
        "    in property <string> latest_version: `"$latVer`";",
        "    in property <string> release_title: `"$title`";",
        "    in property <string> release_date: `"$date`";",
        "    in property <string> release_notes: `"$notes`";",
        "    in property <float> download_progress: $progressStr;",
        "    in property <string> status_text: `"$status`";",
        "    in property <string> setup_path: `"$setup`";",
        "}"
    )

    $content = [string]::Join("`r`n", $lines)
    $tempFile = "$stateFile.tmp"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tempFile, $content, $utf8NoBom)

    # Atomic swap with retry
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            [System.IO.File]::Copy($tempFile, $stateFile, $true)
            [System.IO.File]::Delete($tempFile)
            break
        } catch {
            Start-Sleep -Milliseconds 50
        }
    }
}

# -----------------------------------------------------------------------------
# 1. DISMISS MODAL
# -----------------------------------------------------------------------------
if ($Dismiss) {
    $latestTag = $currentVersion
    $relName = ""
    $pubDate = (Get-Date -Format "yyyy-MM-dd")
    $body = ""
    $hasUpdate = $false
    if (Test-Path $cacheFile) {
        try {
            $release = Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json
            $latestTag = $release.tag_name
            $relName = if ($release.name) { $release.name } else { "Sharabha $latestTag" }
            $pubDate = if ($release.published_at) { $release.published_at.Substring(0, 10) } else { (Get-Date -Format "yyyy-MM-dd") }
            $body = if ($release.body) { $release.body } else { "" }
            $curClean = $currentVersion.TrimStart('v')
            $latClean = $latestTag.TrimStart('v')
            try {
                if ([version]$latClean -gt [version]$curClean) { $hasUpdate = $true }
            } catch {
                if ($latClean -ne $curClean) { $hasUpdate = $true }
            }
        } catch {}
    }
    Write-UpdaterState @{
        has_update = $hasUpdate
        is_checking = $false
        is_downloading = $false
        is_ready = $false
        is_modal_open = $false
        active_tab = $ActiveTab
        current_version = $currentVersion
        latest_version = $latestTag
        release_title = $relName
        release_date = $pubDate
        release_notes = $body
        download_progress = 0.0
        status_text = ""
        setup_path = ""
    }
    exit 0
}

# -----------------------------------------------------------------------------
# 2. CHECK FOR UPDATES
# -----------------------------------------------------------------------------
if ($Check) {
    Write-Host "[AUTO-UPDATER] Checking GitHub Temple Repository for Latest Release..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $headers = @{
            'User-Agent' = 'Sharabha-Engine-Updater'
            'Accept' = 'application/vnd.github.v3+json'
        }
        $release = Invoke-RestMethod -Uri $repoUri -Headers $headers -TimeoutSec 10 -ErrorAction Stop

        # Save to local cache
        $release | ConvertTo-Json -Depth 6 | Out-File -FilePath $cacheFile -Encoding utf8 -Force

        $latestTag = $release.tag_name
        $relName = if ($release.name) { $release.name } else { "Sharabha $latestTag" }
        $pubDate = if ($release.published_at) { $release.published_at.Substring(0, 10) } else { (Get-Date -Format "yyyy-MM-dd") }
        $body = if ($release.body) { $release.body } else { "No changelog provided." }

        # Check version numbers
        $curClean = $currentVersion.TrimStart('v')
        $latClean = $latestTag.TrimStart('v')

        $hasUpdate = $false
        try {
            $curV = [version]$curClean
            $latV = [version]$latClean
            if ($latV -gt $curV) {
                $hasUpdate = $true
            }
        } catch {
            if ($latClean -ne $curClean) {
                $hasUpdate = $true
            }
        }

        $statusMsg = if ($hasUpdate) {
            "New consecration available: $latestTag! Click 'CONSECRATE UPDATE' to download."
        } else {
            "Temple vessel is fully updated ($currentVersion). Showing latest release notes."
        }

        Write-UpdaterState @{
            has_update = $hasUpdate
            is_checking = $false
            is_downloading = $false
            is_ready = $false
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $latestTag
            release_title = $relName
            release_date = $pubDate
            release_notes = $body
            download_progress = 0.0
            status_text = $statusMsg
            setup_path = ""
        }

        Write-Host "  [OK] Check complete. Latest: $latestTag, Current: $currentVersion, HasUpdate: $hasUpdate" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to query GitHub API: $_"
        Write-UpdaterState @{
            has_update = $false
            is_checking = $false
            is_downloading = $false
            is_ready = $false
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $currentVersion
            release_title = "Offline Mode // Network Unavailable"
            release_date = (Get-Date -Format "yyyy-MM-dd")
            release_notes = "Could not reach GitHub release API. Please check your internet connectivity."
            download_progress = 0.0
            status_text = "Network error while checking temple repository."
            setup_path = ""
        }
    }
}

# -----------------------------------------------------------------------------
# 3. DOWNLOAD UPDATE
# -----------------------------------------------------------------------------
if ($Download) {
    Write-Host "[AUTO-UPDATER] Downloading Latest Release Asset..." -ForegroundColor Cyan
    try {
        if (-not (Test-Path $cacheFile)) {
            & $PSCommandPath -Check -ActiveTab $ActiveTab
        }
        $release = Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json
        $setupAsset = $release.assets | Where-Object { $_.name -like "*setup.exe" } | Select-Object -First 1

        if (-not $setupAsset) {
            throw "No setup.exe asset found in release $($release.tag_name)"
        }

        $downloadUrl = $setupAsset.browser_download_url
        $totalBytes = [int64]$setupAsset.size
        $updateDir = Join-Path $env:TEMP "Sharabha-Update"
        if (-not (Test-Path $updateDir)) { New-Item -ItemType Directory -Path $updateDir -Force | Out-Null }
        $destFile = Join-Path $updateDir $setupAsset.name

        Write-Host "  - Target URL:  $downloadUrl"
        Write-Host "  - Destination: $destFile"
        Write-Host "  - Asset Size:  $([Math]::Round($totalBytes / 1MB, 2)) MB"

        Write-UpdaterState @{
            has_update = $true
            is_checking = $false
            is_downloading = $true
            is_ready = $false
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $release.tag_name
            release_title = $release.name
            release_date = $release.published_at.Substring(0, 10)
            release_notes = $release.body
            download_progress = 0.05
            status_text = "Starting download of $($setupAsset.name)..."
            setup_path = $destFile
        }

        # Stream download with throttled progress calculation
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.DefaultRequestHeaders.Add("User-Agent", "Sharabha-Engine-Updater")
        $responseTask = $httpClient.GetAsync($downloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        $response = $responseTask.GetAwaiter().GetResult()
        $streamTask = $response.Content.ReadAsStreamAsync()
        $stream = $streamTask.GetAwaiter().GetResult()

        $fileStream = [System.IO.File]::Create($destFile)
        $buffer = New-Object byte[] 65536
        $downloadedBytes = 0
        $lastReport = [DateTime]::Now
        $lastReportFraction = 0.05

        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $bytesRead)
            $downloadedBytes += $bytesRead

            $fraction = if ($totalBytes -gt 0) { [Math]::Min(0.99, [float]($downloadedBytes / $totalBytes)) } else { 0.5 }
            $now = [DateTime]::Now

            # Throttle updates: at least 1500ms AND at least 8% progress jump
            if (($now - $lastReport).TotalMilliseconds -ge 1500 -and ($fraction - $lastReportFraction) -ge 0.08) {
                $lastReport = $now
                $lastReportFraction = $fraction
                $mbDownloaded = [Math]::Round($downloadedBytes / 1MB, 1)
                $mbTotal = [Math]::Round($totalBytes / 1MB, 1)
                $pct = [Math]::Round($fraction * 100)

                $statusStr = [string]::Format('Downloading: {0} MB / {1} MB ({2}%)...', $mbDownloaded, $mbTotal, $pct)
                Write-UpdaterState @{
                    has_update = $true
                    is_checking = $false
                    is_downloading = $true
                    is_ready = $false
                    is_modal_open = $true
                    active_tab = $ActiveTab
                    current_version = $currentVersion
                    latest_version = $release.tag_name
                    release_title = $release.name
                    release_date = $release.published_at.Substring(0, 10)
                    release_notes = $release.body
                    download_progress = $fraction
                    status_text = $statusStr
                    setup_path = $destFile
                }
            }
        }

        $fileStream.Flush()
        $fileStream.Close()
        $fileStream.Dispose()
        $stream.Close()
        $stream.Dispose()
        $httpClient.Dispose()

        Write-Host "  [OK] Download complete: $destFile" -ForegroundColor Green

        Write-UpdaterState @{
            has_update = $true
            is_checking = $false
            is_downloading = $false
            is_ready = $true
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $release.tag_name
            release_title = $release.name
            release_date = $release.published_at.Substring(0, 10)
            release_notes = $release.body
            download_progress = 1.0
            status_text = "Sanctified vessel downloaded ($([Math]::Round($totalBytes / 1MB, 1)) MB). Ready to consecrate!"
            setup_path = $destFile
        }

    } catch {
        Write-Warning "Download error: $_"
        Write-UpdaterState @{
            has_update = $false
            is_checking = $false
            is_downloading = $false
            is_ready = $false
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $currentVersion
            release_title = "Download Interrupted"
            release_date = (Get-Date -Format "yyyy-MM-dd")
            release_notes = "Error downloading update: $_"
            download_progress = 0.0
            status_text = "Download failed: $_"
            setup_path = ""
        }
    }
}

# -----------------------------------------------------------------------------
# 4. INSTALL & RESTART
# -----------------------------------------------------------------------------
if ($Install) {
    Write-Host "[AUTO-UPDATER] Launching Consecration Setup..." -ForegroundColor Cyan
    $targetExe = $TargetSetupPath
    if (-not $targetExe -or -not (Test-Path $targetExe)) {
        $updateDir = Join-Path $env:TEMP "Sharabha-Update"
        if (Test-Path $updateDir) {
            $latestExe = Get-ChildItem -Path $updateDir -Filter "*setup.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestExe) { $targetExe = $latestExe.FullName }
        }
    }

    if (-not $targetExe -or -not (Test-Path $targetExe)) {
        Write-Error "No valid setup executable found at: $targetExe"
        exit 1
    }

    Write-Host "  - Spawning Setup Executable: $targetExe" -ForegroundColor Green
    Start-Process -FilePath $targetExe

    # Gracefully exit Sharabha and its viewer so the installer can update files
    Start-Sleep -Milliseconds 800
    Stop-Process -Name "Sharabha", "slint-viewer" -Force -ErrorAction SilentlyContinue
}
