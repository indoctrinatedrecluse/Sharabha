param(
    [string]$Tag = "v0.5.1"
)

$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "========================================================================"
Write-Host "  SHARABHA // PACKAGING RELEASE ARTIFACTS ($Tag)"
Write-Host "========================================================================"

$portableDir = Join-Path $projectRoot "Sharabha-$Tag-windows-x64-portable"
if (Test-Path $portableDir) { Remove-Item -Recurse -Force $portableDir }

# 1. Assemble Portable Directory
New-Item -ItemType Directory -Path (Join-Path $portableDir "bin") -Force | Out-Null
Copy-Item (Join-Path $projectRoot "zig-out\bin\Sharabha.exe") -Destination (Join-Path $portableDir "bin\Sharabha.exe") -Force
Copy-Item (Join-Path $projectRoot "zig-out\bin\SharabhaCli.exe") -Destination (Join-Path $portableDir "bin\SharabhaCli.exe") -Force
Copy-Item (Join-Path $projectRoot "zig-out\bin\lua51.dll") -Destination (Join-Path $portableDir "bin\lua51.dll") -Force

$cargoSlint = (Get-Command slint-viewer -ErrorAction SilentlyContinue).Source
if (-not $cargoSlint) { $cargoSlint = Join-Path $env:USERPROFILE ".cargo\bin\slint-viewer.exe" }
if (Test-Path $cargoSlint) {
    $destSlint = Join-Path $portableDir "bin\slint-viewer.exe"
    Copy-Item $cargoSlint -Destination $destSlint -Force
    # Patch PE Subsystem from 3 (Console) to 2 (Windows GUI) to eliminate any terminal window
    $bytes = [System.IO.File]::ReadAllBytes($destSlint)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $subsysOffset = $peOffset + 24 + 68
    $bytes[$subsysOffset] = 2
    $bytes[$subsysOffset + 1] = 0
    [System.IO.File]::WriteAllBytes($destSlint, $bytes)
}

Copy-Item -Path (Join-Path $projectRoot "assets") -Destination (Join-Path $portableDir "assets") -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "src\ui") -Destination (Join-Path $portableDir "src\ui") -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "tools") -Destination (Join-Path $portableDir "tools") -Recurse -Force
if (Test-Path (Join-Path $projectRoot "deps\luajit")) {
    Copy-Item -Path (Join-Path $projectRoot "deps\luajit") -Destination (Join-Path $portableDir "deps\luajit") -Recurse -Force
}
Copy-Item -Path (Join-Path $projectRoot "README.md") -Destination (Join-Path $portableDir "README.md") -Force -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $projectRoot "CHANGELOG.md") -Destination (Join-Path $portableDir "CHANGELOG.md") -Force -ErrorAction SilentlyContinue

# 2. Compress Portable ZIP
$zipName = "Sharabha-$Tag-windows-x64-portable.zip"
$zipPath = Join-Path $projectRoot $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path "$portableDir\*" -DestinationPath $zipPath -Force
Write-Host "  [OK] Created: $zipName" -ForegroundColor Green

# 3. Assemble Standalone Self-Extracting Installer
$setupName = "Sharabha-$Tag-windows-x64-setup.exe"
$setupPath = Join-Path $projectRoot $setupName
Write-Host "  - Embedding self-extracting payload into $setupName..." -ForegroundColor Cyan

$payloadZip = Join-Path $projectRoot "sharabha_payload.zip"
Copy-Item $zipPath -Destination $payloadZip -Force

$installerRc = Join-Path $projectRoot "res\installer.rc"
$rcContent = "1 ICON `"assets/media/app_icon.ico`"`n100 RCDATA `"sharabha_payload.zip`""
[System.IO.File]::WriteAllText($installerRc, $rcContent, [System.Text.Encoding]::ASCII)

Write-Host "  - Compiling resource table..." -ForegroundColor Cyan
Push-Location $projectRoot
zig rc res/installer.rc

Write-Host "  - Linking native Win32 GUI installer executable..." -ForegroundColor Cyan
zig build-exe src/installer_launcher.zig res/installer.res -O ReleaseFast -target x86_64-windows --subsystem windows -lc "-femit-bin=$setupName"

Remove-Item $payloadZip -Force -ErrorAction SilentlyContinue
Remove-Item $installerRc -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $projectRoot "res\installer.res") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $projectRoot "Sharabha-$Tag-windows-x64-setup.pdb") -Force -ErrorAction SilentlyContinue
Pop-Location

Write-Host "  [OK] Created: $setupName" -ForegroundColor Green

# 4. Clean up temporary portable directory
Remove-Item -Recurse -Force $portableDir

Get-Item $zipPath, $setupPath | Select-Object Name, Length
