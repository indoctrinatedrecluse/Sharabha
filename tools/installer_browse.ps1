Add-Type -AssemblyName System.Windows.Forms

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }

$f = New-Object System.Windows.Forms.FolderBrowserDialog
$f.Description = "Select Sharabha Vessel Installation Directory"
$f.ShowNewFolderButton = $true

$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$owner.Size = New-Object System.Drawing.Size(1, 1)
$owner.Opacity = 0
$owner.Show()
$owner.BringToFront()

$res = $f.ShowDialog($owner)
$owner.Close()
$owner.Dispose()

if ($res -eq [System.Windows.Forms.DialogResult]::OK -and $f.SelectedPath) {
    $chosen = $f.SelectedPath
    $isInstalled = (Test-Path (Join-Path $chosen "bin\Sharabha.exe"))
    $escapedPath = $chosen.Replace("\", "\\").Replace('"', '\"')
    $stateFile = Join-Path $projectDir "src\ui\installer_state.slint"

    $lines = @(
        "// Sharabha Installer Dynamic State Configuration",
        "// Automatically updated by installer_browse.ps1",
        "export global InstallerState {",
        "    in property <bool> is_already_installed: $($isInstalled.ToString().ToLower());",
        "    in property <string> installed_version: `"0.4.0`";",
        "    in property <string> detected_install_path: `"$escapedPath`";",
        "}"
    )

    $content = [string]::Join("`r`n", $lines)
    [System.IO.File]::WriteAllText($stateFile, $content, [System.Text.Encoding]::UTF8)

    # Touch installer.slint to trigger reload
    $installerSlint = Join-Path $projectDir "src\ui\installer.slint"
    if (Test-Path $installerSlint) {
        (Get-Item $installerSlint).LastWriteTime = Get-Date
    }
}
