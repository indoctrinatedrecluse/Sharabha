param(
    [string]$TargetFilePath = ""
)

# Sharabha Native Windows File Open Dialog & Cheat Engine (.CT) Table Loader
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$activeTableFile = Join-Path $projectDir "assets\tables\active_table_path.txt"

# 1. Determine Target File Path
$selectedPath = ""
if ($TargetFilePath -and (Test-Path $TargetFilePath)) {
    $selectedPath = $TargetFilePath
}

if (-not $selectedPath) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "SHARABHA // Select Cheat Engine Table (.CT) (सीटी प्रवेश)"
    $dialog.Filter = "All Supported Tables (*.CT;*.ct;*.sharabha)|*.CT;*.ct;*.sharabha|Cheat Engine Tables (*.CT;*.ct)|*.CT;*.ct|Sharabha Tables (*.sharabha)|*.sharabha|All Files (*.*)|*.*"
    
    $initialDir = "D:\Mods"
    if (Test-Path $activeTableFile) {
        $lastSaved = (Get-Content $activeTableFile -Raw).Trim()
        if (Test-Path $lastSaved) {
            $initialDir = Split-Path -Parent $lastSaved
        }
    }
    if (-not (Test-Path $initialDir)) {
        $candDir = Join-Path $projectDir "assets\tables"
        if (Test-Path $candDir) { $initialDir = $candDir }
    }
    $dialog.InitialDirectory = $initialDir

    # Present dialog in foreground over Slint window
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

    if ($res -ne [System.Windows.Forms.DialogResult]::OK -or -not (Test-Path $dialog.FileName)) {
        Write-Host "[!] Table selection cancelled by user."
        exit 0
    }
    $selectedPath = $dialog.FileName
}

# Persist active table path
try {
    $tblDir = Split-Path -Parent $activeTableFile
    if (-not (Test-Path $tblDir)) { New-Item -ItemType Directory -Path $tblDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($activeTableFile, $selectedPath, (New-Object System.Text.UTF8Encoding $false))
} catch { }

Write-Host "🔱 Invoking SharabhaCli --load-ct on '$selectedPath'..."
$cliExe = Join-Path $projectDir "zig-out\bin\SharabhaCli.exe"
if (Test-Path $cliExe) {
    & $cliExe --load-ct "$selectedPath"
} else {
    Write-Host "[!] SharabhaCli.exe not found in zig-out\bin."
}

# Touch src\ui\app.slint to trigger slint-viewer reload
$appSlint = Join-Path $projectDir "src\ui\app.slint"
if (Test-Path $appSlint) {
    (Get-Item $appSlint).LastWriteTime = Get-Date
    Write-Host "[OK] Slint Viewer watcher signaled via app.slint touch"
}
