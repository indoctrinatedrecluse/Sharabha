# Cancel / Exit Installer GUI Window
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

if ($installerViewerPid -gt 0) {
    Stop-Process -Id $installerViewerPid -Force -ErrorAction SilentlyContinue
}
