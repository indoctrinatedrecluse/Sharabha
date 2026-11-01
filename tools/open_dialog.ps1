# Sharabha Native Windows File Open Dialog
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "SHARABHA // Select Game Save Vessel (पात्र प्रवेश)"
$dialog.Filter = "All Supported Saves (*.sl2;*.sav;*.dat;*.json;*.bin)|*.sl2;*.sav;*.dat;*.json;*.bin|Elden Ring (*.sl2)|*.sl2|Unreal GVAS (*.sav)|*.sav|Cyberpunk (*.dat)|*.dat|All Files (*.*)|*.*"
$initialDir = (Get-Item "assets\saves" -ErrorAction SilentlyContinue).FullName
if ($initialDir) {
    $dialog.InitialDirectory = $initialDir
}

$res = $dialog.ShowDialog()
if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Selected: $($dialog.FileName)"
    exit 0
} else {
    Write-Host "Cancelled by user."
    exit 1
}
