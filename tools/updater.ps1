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
$currentVersion = "v0.5.3"
$repoUri = "https://api.github.com/repos/indoctrinatedrecluse/Sharabha/releases/latest"
$cacheFile = Join-Path $env:TEMP "sharabha_latest_release.json"

# A release JSON older than this is treated as absent: `-Download` / `-Dismiss`
# would otherwise act on a tag that has since been superseded (or on an asset URL
# that no longer exists).
$cacheMaxAgeMinutes = 30
# Slint string literals are compiled by `slint-viewer --auto-reload` on every write,
# so an oversized changelog is capped instead of being serialised verbatim.
$maxNotesLength = 32000

# Cloaking contract: the UI shells this script out with `powershell.exe -WindowStyle
# Hidden`, every child we spawn is a GUI-subsystem binary, and nothing here may pop a
# dialog or paint a progress bar in a console window.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'

function Escape-SlintString([string]$str) {
    if (-not $str) { return "" }
    if ($str.Length -gt $maxNotesLength) {
        $str = $str.Substring(0, $maxNotesLength) + "`r`n`r`n... [release notes truncated by the Sharabha updater]"
    }
    $escaped = $str.Replace("\", "\\").Replace('"', '\"').Replace("`r`n", "\n").Replace("`n", "\n").Replace("`r", "\n")
    # Control bytes (a stray ESC from a hand-edited changelog, for example) are illegal
    # inside a Slint string literal and would break the auto-reload compile.
    return [System.Text.RegularExpressions.Regex]::Replace($escaped, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
}

# Null-safe `published_at` -> `yyyy-MM-dd` (a release can legitimately omit the field).
function Format-ReleaseDate($release) {
    if ($release -and $release.published_at -and $release.published_at.Length -ge 10) {
        return $release.published_at.Substring(0, 10)
    }
    return (Get-Date -Format "yyyy-MM-dd")
}

# Semantic version comparison that tolerates a leading `v` and unparsable tags
# (`v0.5.10` must beat `v0.5.9`, which a raw string comparison gets wrong).
function Test-NewerVersion([string]$LatestTag, [string]$CurrentTag) {
    if (-not $LatestTag) { return $false }
    $latestClean = $LatestTag.Trim().TrimStart('v', 'V')
    $currentClean = $CurrentTag.Trim().TrimStart('v', 'V')
    try {
        return ([version]$latestClean -gt [version]$currentClean)
    } catch {
        return ($latestClean -ne $currentClean)
    }
}

# Loads the cached release JSON, refreshing it once when the cache is missing, older
# than `$MaxAgeMinutes`, or unreadable. Returns `$null` when GitHub is unreachable and
# nothing usable is cached.
function Get-CachedRelease([int]$MaxAgeMinutes) {
    if (Test-Path $cacheFile) {
        try {
            $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
            if ($age.TotalMinutes -le $MaxAgeMinutes) {
                return (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json)
            }
        } catch {}
    }

    & $PSCommandPath -Check -ActiveTab $ActiveTab | Out-Null

    if (Test-Path $cacheFile) {
        try {
            return (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json)
        } catch {}
    }

    return $null
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
    # Closing the modal only preserves what the user was just looking at: no network
    # call is made here, the cached release (any age) is simply re-serialised with
    # `is_modal_open = $false`.
    if (Test-Path $cacheFile) {
        try {
            $release = Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json
            $latestTag = $release.tag_name
            $relName = if ($release.name) { $release.name } else { "Sharabha $latestTag" }
            $pubDate = Format-ReleaseDate $release
            $body = if ($release.body) { $release.body } else { "" }
            $hasUpdate = Test-NewerVersion $latestTag $currentVersion
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

        # Save to local cache (atomically: a concurrent -Download/-Dismiss must never
        # observe a half-written JSON document).
        $cacheTmp = "$cacheFile.tmp"
        $release | ConvertTo-Json -Depth 6 | Out-File -FilePath $cacheTmp -Encoding utf8 -Force
        try {
            [System.IO.File]::Copy($cacheTmp, $cacheFile, $true)
            [System.IO.File]::Delete($cacheTmp)
        } catch {}

        $latestTag = $release.tag_name
        $relName = if ($release.name) { $release.name } else { "Sharabha $latestTag" }
        $pubDate = Format-ReleaseDate $release
        $body = if ($release.body) { $release.body } else { "No changelog provided." }

        $hasUpdate = Test-NewerVersion $latestTag $currentVersion

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
    $destFile = $null
    try {
        # Refresh the release metadata when the cache is missing or stale: acting on a
        # superseded tag downloads an asset URL that no longer exists.
        $release = Get-CachedRelease $cacheMaxAgeMinutes
        if (-not $release) {
            throw "No release metadata available (GitHub unreachable and no cached release)."
        }
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
            release_date = Format-ReleaseDate $release
            release_notes = $release.body
            download_progress = 0.05
            status_text = "Starting download of $($setupAsset.name)..."
            setup_path = $destFile
        }

        # Stream download with throttled progress calculation.
        # `System.Net.Http.HttpClient` cannot be resolved in a stock Windows PowerShell
        # 5.1 session (the UI always shells out to `powershell.exe`), which silently broke
        # every download. The classic `WebRequest`/`HttpWebRequest` API exists in every
        # supported runtime and still yields a real byte stream plus `Content-Length`.
        try {
            $tlsProtocols = [Net.SecurityProtocolType]::Tls12
            if ([Enum]::IsDefined([Net.SecurityProtocolType], "Tls13")) {
                $tlsProtocols = $tlsProtocols -bor [Net.SecurityProtocolType]::Tls13
            }
            [Net.ServicePointManager]::SecurityProtocol = $tlsProtocols
        } catch {}
        $response = $null
        $stream = $null
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($downloadUrl)
        $request.Method = "GET"
        $request.UserAgent = "Sharabha-Engine-Updater"
        $request.AllowAutoRedirect = $true
        $request.Timeout = 60000
        $request.ReadWriteTimeout = 300000
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        if (-not $stream) {
            throw "Empty response stream for $($setupAsset.name)"
        }
        if ($totalBytes -le 0 -and $response.ContentLength -gt 0) {
            $totalBytes = [int64]$response.ContentLength
        }

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
                    release_date = Format-ReleaseDate $release
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
        $response.Close()
        $response.Dispose()

        # Integrity gates: a truncated or HTML-error-page "installer" must never be
        # handed to `-Install`.
        if ($totalBytes -gt 0 -and $downloadedBytes -ne $totalBytes) {
            throw "Download truncated: $downloadedBytes of $totalBytes bytes"
        }
        $probe = [System.IO.File]::OpenRead($destFile)
        try {
            $signature = New-Object byte[] 2
            $signatureBytes = $probe.Read($signature, 0, 2)
        } finally {
            $probe.Dispose()
        }
        if ($signatureBytes -ne 2 -or $signature[0] -ne 0x4D -or $signature[1] -ne 0x5A) {
            throw "Downloaded asset is not a valid Windows executable (missing MZ header)"
        }

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
            release_date = Format-ReleaseDate $release
            release_notes = $release.body
            download_progress = 1.0
            status_text = "Sanctified vessel downloaded ($([Math]::Round($totalBytes / 1MB, 1)) MB). Ready to consecrate!"
            setup_path = $destFile
        }

    } catch {
        Write-Warning "Download error: $_"
        # Never leave a partial/again-invalid payload behind: `-Install` would otherwise
        # pick it up as the newest `*setup.exe` in the staging folder.
        if ($destFile -and (Test-Path $destFile)) {
            Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue
        }
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
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 4. INSTALL & RESTART
# -----------------------------------------------------------------------------
if ($Install) {
    Write-Host "[AUTO-UPDATER] Launching Consecration Setup..." -ForegroundColor Cyan
    $targetExe = $TargetSetupPath
    if (-not $targetExe -or -not (Test-Path -LiteralPath $targetExe)) {
        $updateDir = Join-Path $env:TEMP "Sharabha-Update"
        if (Test-Path $updateDir) {
            $latestExe = Get-ChildItem -Path $updateDir -Filter "*setup.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestExe) { $targetExe = $latestExe.FullName }
        }
    }

    # Only a real PE payload may be executed: a truncated or partially written download
    # must never be launched.
    $setupValid = $false
    if ($targetExe -and (Test-Path -LiteralPath $targetExe)) {
        try {
            $item = Get-Item -LiteralPath $targetExe
            if ($item.Length -gt 1MB) {
                $probe = [System.IO.File]::OpenRead($targetExe)
                try {
                    $signature = New-Object byte[] 2
                    $signatureBytes = $probe.Read($signature, 0, 2)
                } finally {
                    $probe.Dispose()
                }
                $setupValid = ($signatureBytes -eq 2 -and $signature[0] -eq 0x4D -and $signature[1] -eq 0x5A)
            }
        } catch {}
    }

    if (-not $setupValid) {
        Write-Warning "No valid setup executable found at: $targetExe"
        Write-UpdaterState @{
            has_update = $true
            is_checking = $false
            is_downloading = $false
            is_ready = $false
            is_modal_open = $true
            active_tab = $ActiveTab
            current_version = $currentVersion
            latest_version = $currentVersion
            release_title = "Installer Payload Invalid"
            release_date = (Get-Date -Format "yyyy-MM-dd")
            release_notes = "The downloaded setup executable is missing or incomplete. Please run the update check again to download a fresh copy."
            download_progress = 0.0
            status_text = "Installer payload invalid; download the update again."
            setup_path = ""
        }
        exit 1
    }

    # Terminate Sharabha and its viewer *before* the setup starts: the installer
    # overwrites `bin\Sharabha.exe`, so launching it while the engine is still mapped
    # would surface a files-in-use dialog. The bounded wait keeps the handover
    # deterministic, and every step stays console-free.
    Stop-Process -Name "Sharabha", "slint-viewer" -Force -ErrorAction SilentlyContinue
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (-not (Get-Process -Name "Sharabha", "slint-viewer" -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 150
    }

    Write-Host "  - Spawning Setup Executable: $targetExe" -ForegroundColor Green
    try {
        Start-Process -FilePath $targetExe
    } catch {
        Write-Warning "Unable to launch setup: $_"
        exit 1
    }
    exit 0
}
