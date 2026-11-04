param(
    [string]$InstallPath = "",
    [string]$LaunchFlag = "true"
)

$doLaunch = ($LaunchFlag -eq "true" -or $LaunchFlag -eq "True" -or $LaunchFlag -eq "1" -or $LaunchFlag -eq $true)

# 1. Resolve Target Sharabha Executable Path
$targetDir = $InstallPath
if (-not $targetDir -or -not (Test-Path $targetDir)) {
    # Check Registry
    $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Sharabha"
    if (Test-Path $regKey) {
        $props = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
        if ($props -and $props.InstallLocation) {
            $targetDir = $props.InstallLocation
        }
    }
}
if (-not $targetDir -or -not (Test-Path $targetDir)) {
    $targetDir = "$env:LOCALAPPDATA\Programs\Sharabha"
}

$mainExe = Join-Path $targetDir "bin\Sharabha.exe"
if (-not (Test-Path $mainExe)) {
    $mainExe = Join-Path $targetDir "Sharabha.exe"
}

# 2. Identify the Installer's slint-viewer parent process so we don't kill other processes
$installerViewerPid = 0
try {
    $proc = Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -eq $PID }
    if ($proc) {
        $parentProc = Get-Process -Id $proc.ParentProcessId -ErrorAction SilentlyContinue
        if ($parentProc -and $parentProc.ProcessName -match "slint-viewer") {
            $installerViewerPid = $parentProc.Id
        }
    }
} catch { }

# 3. If Launch requested, spawn Sharabha.exe detached
if ($doLaunch -and (Test-Path $mainExe)) {
    Start-Process -FilePath $mainExe -WorkingDirectory $targetDir
}

# 4. Terminate ONLY the Installer GUI Window
if ($installerViewerPid -gt 0) {
    Stop-Process -Id $installerViewerPid -Force -ErrorAction SilentlyContinue
}
