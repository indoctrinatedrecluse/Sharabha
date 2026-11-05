<#
================================================================================
  SHARABHA // CT PRAVESHA (सीटी प्रवेश) - Cheat Engine Table Loader
  Invoked from slint-viewer callback: --on load_ct_file
  --------------------------------------------------------------------------------
  ENCODING CONTRACT: this file MUST be saved as UTF-8 *with BOM*.
  Windows PowerShell 5.1 decodes BOM-less scripts as ANSI (Windows-1252); the
  continuation bytes of the emoji / Devanagari glyphs below then decode into
  "smart quotes" (0x93 / 0x94) and other punctuation, which the PowerShell
  tokenizer treats as string terminators -> ParserError, the script never runs,
  and the LOAD .CT action dies silently (the reported " .CT crash").
  Guard: powershell -NoProfile -File tools\check_scripts.ps1
================================================================================
#>
param(
    [string]$TargetFilePath = ""
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 1. Resolve project root (works from -File invocation and from any cwd)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$activeTableFile = Join-Path $projectDir "assets\tables\active_table_path.txt"
$liveTableSlint = Join-Path $projectDir "src\ui\live_table.slint"
$appSlint = Join-Path $projectDir "src\ui\app.slint"

function Resolve-SharabhaCli {
    # Packaged layout (bin\SharabhaCli.exe) first, then dev layout (zig-out\bin\)
    $candidates = @(
        (Join-Path $projectDir "bin\SharabhaCli.exe"),
        (Join-Path $projectDir "zig-out\bin\SharabhaCli.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    $onPath = Get-Command "SharabhaCli.exe" -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return ""
}

# 2. Determine target file path (argument, else native Windows file picker)
$selectedPath = ""
if ($TargetFilePath -and (Test-Path -LiteralPath $TargetFilePath)) {
    $selectedPath = (Resolve-Path -LiteralPath $TargetFilePath).Path
}

if (-not $selectedPath) {
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "SHARABHA // Select Cheat Engine Table (.CT) (सीटी प्रवेश)"
        $dialog.Filter = "All Supported Tables (*.CT;*.ct;*.sharabha)|*.CT;*.ct;*.sharabha|Cheat Engine Tables (*.CT;*.ct)|*.CT;*.ct|Sharabha Tables (*.sharabha)|*.sharabha|All Files (*.*)|*.*"
        $dialog.CheckFileExists = $true
        $dialog.RestoreDirectory = $true

        $initialDir = "D:\Mods"
        if (Test-Path -LiteralPath $activeTableFile) {
            $lastSaved = (Get-Content -LiteralPath $activeTableFile -Raw).Trim()
            if ($lastSaved) {
                $lastDir = Split-Path -Parent $lastSaved
                if ($lastDir -and (Test-Path -LiteralPath $lastDir)) { $initialDir = $lastDir }
            }
        }
        if (-not (Test-Path -LiteralPath $initialDir)) {
            $candDir = Join-Path $projectDir "assets\tables"
            if (Test-Path -LiteralPath $candDir) { $initialDir = $candDir } else { $initialDir = $projectDir }
        }
        $dialog.InitialDirectory = $initialDir

        # Invisible top-most owner form keeps the picker above the Slint window
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $owner.Size = New-Object System.Drawing.Size(1, 1)
        $owner.Opacity = 0
        $owner.Show()
        $owner.BringToFront()

        $res = $dialog.ShowDialog($owner)
        $owner.Close()
        $owner.Dispose()

        if ($res -ne [System.Windows.Forms.DialogResult]::OK -or -not (Test-Path -LiteralPath $dialog.FileName)) {
            Write-Host "[!] Table selection cancelled by user."
            exit 0
        }
        $selectedPath = $dialog.FileName
    } catch {
        Write-Host "[!] Table picker failed: $($_.Exception.Message)"
        exit 1
    }
}

# 3. Persist the active table path (UTF-8, no BOM)
try {
    $tblDir = Split-Path -Parent $activeTableFile
    if (-not (Test-Path -LiteralPath $tblDir)) { New-Item -ItemType Directory -Path $tblDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($activeTableFile, $selectedPath, (New-Object System.Text.UTF8Encoding $false))
} catch {
    Write-Host "[!] Could not persist active table path: $($_.Exception.Message)"
}

# 4. Invoke the inquest engine
$cliExe = Resolve-SharabhaCli
if (-not $cliExe) {
    Write-Host "[!] SharabhaCli.exe not found (looked in bin\ and zig-out\bin). Rebuild with 'zig build' or reinstall Sharabha."
    exit 1
}

Write-Host "🔱 Invoking SharabhaCli --load-ct on '$selectedPath'..."
& $cliExe --load-ct "$selectedPath"
$cliExit = $LASTEXITCODE
if ($cliExit -ne 0) {
    Write-Host "[!] SharabhaCli --load-ct exited with code $cliExit."
}

# 5. Only poke the watcher once the generated table is complete and non-empty.
#    slint-viewer runs with --auto-reload: reloading a truncated live_table.slint
#    fails to compile and takes the whole UI down with it.
$slintOk = (Test-Path -LiteralPath $liveTableSlint) -and ((Get-Item -LiteralPath $liveTableSlint).Length -gt 64)
if ($slintOk -and (Test-Path -LiteralPath $appSlint)) {
    (Get-Item -LiteralPath $appSlint).LastWriteTime = Get-Date
    Write-Host "[OK] Slint Viewer watcher signaled via app.slint touch"
} else {
    Write-Host "[!] src\ui\live_table.slint missing or empty; UI watcher not signaled."
    exit 1
}

exit $cliExit
