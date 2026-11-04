param(
    [string]$SourcePath = "",
    [string]$TargetPath = "$env:LOCALAPPDATA\Programs\Sharabha",
    [string]$DesktopFlag = "true",
    [string]$StartMenuFlag = "true",
    [string]$LaunchFlag = "true",
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartMenu,
    [switch]$LaunchAfter
)

# Sharabha Sacred Consecration & Installation Logic Engine
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$makeDesktop = ($DesktopFlag -eq "true" -or $DesktopFlag -eq "True" -or $CreateDesktopShortcut)
$makeStartMenu = ($StartMenuFlag -eq "true" -or $StartMenuFlag -eq "True" -or $CreateStartMenu)
$doLaunch = ($LaunchFlag -eq "true" -or $LaunchFlag -eq "True" -or $LaunchAfter)

$projectRoot = if ($SourcePath -and (Test-Path $SourcePath)) {
    (Resolve-Path $SourcePath).Path
} else {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
}

Write-Host "========================================================================"
Write-Host "  SHARABHA // CONSECRATING APPLICATION VESSEL (प्रतिष्ठापन)"
Write-Host "========================================================================"
Write-Host "  • Source Root:    $projectRoot"
Write-Host "  • Target Vessel:  $TargetPath"

# 1. Create Target Directory Tree
if (-not (Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}

$dirsToCreate = @(
    "bin",
    "assets",
    "assets\media",
    "assets\saves",
    "src",
    "src\ui",
    "tools",
    "deps",
    "deps\luajit",
    "deps\luajit\bin"
)

foreach ($d in $dirsToCreate) {
    $p = Join-Path $TargetPath $d
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

# 2. Copy Binaries
Write-Host "  [1/5] Deploying Native Binaries (Sharabha.exe, SharabhaCli.exe, lua51.dll)..." -ForegroundColor Cyan
if (Test-Path "$projectRoot\bin") {
    Copy-Item -Path "$projectRoot\bin\*" -Destination (Join-Path $TargetPath "bin") -Recurse -Force
}
if (Test-Path "$projectRoot\zig-out\bin") {
    Copy-Item -Path "$projectRoot\zig-out\bin\*" -Destination (Join-Path $TargetPath "bin") -Recurse -Force
}

# Ensure slint-viewer is available in bin
if (-not (Test-Path (Join-Path $TargetPath "bin\slint-viewer.exe"))) {
    $localSlint = Join-Path $env:USERPROFILE ".cargo\bin\slint-viewer.exe"
    if (Test-Path $localSlint) {
        Copy-Item -Path $localSlint -Destination (Join-Path $TargetPath "bin\slint-viewer.exe") -Force
    }
}

# 3. Copy Assets & Hardware Frames
Write-Host "  [2/5] Copying Chitrapata Hardware Video Buffers & Sacred Media..." -ForegroundColor Cyan
if (Test-Path "$projectRoot\assets") {
    Copy-Item -Path "$projectRoot\assets\*" -Destination (Join-Path $TargetPath "assets") -Recurse -Force
}

# 4. Copy UI Declarations & Tools
Write-Host "  [3/5] Deploying Slint 1.18 Hardware Declarations & Inquest Tools..." -ForegroundColor Cyan
if (Test-Path "$projectRoot\src\ui") {
    Copy-Item -Path "$projectRoot\src\ui\*" -Destination (Join-Path $TargetPath "src\ui") -Recurse -Force
}
if (Test-Path "$projectRoot\tools") {
    Copy-Item -Path "$projectRoot\tools\*" -Destination (Join-Path $TargetPath "tools") -Recurse -Force
}
if (Test-Path "$projectRoot\deps") {
    Copy-Item -Path "$projectRoot\deps\*" -Destination (Join-Path $TargetPath "deps") -Recurse -Force
}
if (Test-Path "$projectRoot\README.md") {
    Copy-Item -Path "$projectRoot\README.md" -Destination (Join-Path $TargetPath "README.md") -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$projectRoot\CHANGELOG.md") {
    Copy-Item -Path "$projectRoot\CHANGELOG.md" -Destination (Join-Path $TargetPath "CHANGELOG.md") -Force -ErrorAction SilentlyContinue
}

# 5. Create Desktop & Start Menu Shortcuts
$wsh = New-Object -ComObject WScript.Shell
$mainExe = Join-Path $TargetPath "bin\Sharabha.exe"
$icoPath = Join-Path $TargetPath "assets\media\app_icon.ico"

if ($makeDesktop) {
    Write-Host "  [4/5] Forging Trishula Desktop Shortcut with Mythic App Icon..." -ForegroundColor Cyan
    $desktopDir = [System.Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopDir "Sharabha.lnk"
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $mainExe
    $shortcut.WorkingDirectory = $TargetPath
    $shortcut.IconLocation = "$icoPath, 0"
    $shortcut.Description = 'Sharabha (शरभेश्वर) - The Dual Aspect Engine (v0.4.0)'
    $shortcut.Save()
    Write-Host "    [✓] Desktop shortcut created: $shortcutPath" -ForegroundColor Green
}

if ($makeStartMenu) {
    $programsDir = [System.Environment]::GetFolderPath('Programs')
    $shortcutPath = Join-Path $programsDir "Sharabha.lnk"
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $mainExe
    $shortcut.WorkingDirectory = $TargetPath
    $shortcut.IconLocation = "$icoPath, 0"
    $shortcut.Description = 'Sharabha (शरभेश्वर) - The Dual Aspect Engine (v0.4.0)'
    $shortcut.Save()
    Write-Host "    [✓] Start Menu shortcut created: $shortcutPath" -ForegroundColor Green
}

# 6. Register in Windows Uninstall Registry
Write-Host "  [5/5] Registering Application in Windows Shell Registry..." -ForegroundColor Cyan
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Sharabha"
if (-not (Test-Path $regKey)) {
    New-Item -Path $regKey -Force | Out-Null
}
Set-ItemProperty -Path $regKey -Name "DisplayName" -Value "Sharabha (शरभेश्वर) - The Dual Aspect Engine" -Force
Set-ItemProperty -Path $regKey -Name "DisplayVersion" -Value "0.4.0" -Force
Set-ItemProperty -Path $regKey -Name "Publisher" -Value "Indoctrinated Recluse" -Force
Set-ItemProperty -Path $regKey -Name "DisplayIcon" -Value "$icoPath, 0" -Force
Set-ItemProperty -Path $regKey -Name "InstallLocation" -Value $TargetPath -Force
$uninstallerCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"Remove-Item -Recurse -Force '$TargetPath'; Remove-Item -Force '$regKey' -ErrorAction SilentlyContinue`""
Set-ItemProperty -Path $regKey -Name "UninstallString" -Value $uninstallerCmd -Force

Write-Host ""
Write-Host "========================================================================"
Write-Host "  [OK] CONSECRATION COMPLETE // SHARABHA READY FOR TEMPLE LAUNCH!" -ForegroundColor Green
Write-Host "========================================================================"

# 7. Complete Consecration
if ($LaunchAfter) {
    Write-Host "  - Awakening Sharabha Native Engine in Background..." -ForegroundColor Yellow
    Start-Process -FilePath $mainExe -WorkingDirectory $TargetPath
}
