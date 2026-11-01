param(
    [string]$Tag = "v0.1.0"
)

$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "========================================================================"
Write-Host "  SHARABHA // PACKAGING RELEASE ARTIFACTS ($Tag)"
Write-Host "========================================================================"

$portableDir = Join-Path $projectRoot "Sharabha-$Tag-windows-x64-portable"
if (Test-Path $portableDir) { Remove-Item -Recurse -Force $portableDir }

# 1. Assemble Portable Directory
New-Item -ItemType Directory -Path (Join-Path $portableDir "bin") -Force | Out-Null
Copy-Item (Join-Path $projectRoot "zig-out\bin\*") -Destination (Join-Path $portableDir "bin") -Recurse -Force

$cargoSlint = (Get-Command slint-viewer -ErrorAction SilentlyContinue).Source
if (-not $cargoSlint) { $cargoSlint = Join-Path $env:USERPROFILE ".cargo\bin\slint-viewer.exe" }
if (Test-Path $cargoSlint) {
    Copy-Item $cargoSlint -Destination (Join-Path $portableDir "bin\slint-viewer.exe") -Force
}

Copy-Item -Path (Join-Path $projectRoot "assets") -Destination (Join-Path $portableDir "assets") -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "src\ui") -Destination (Join-Path $portableDir "src\ui") -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "tools") -Destination (Join-Path $portableDir "tools") -Recurse -Force
if (Test-Path (Join-Path $projectRoot "deps")) {
    Copy-Item -Path (Join-Path $projectRoot "deps") -Destination (Join-Path $portableDir "deps") -Recurse -Force
}
Copy-Item -Path (Join-Path $projectRoot "README.md") -Destination (Join-Path $portableDir "README.md") -Force -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $projectRoot "CHANGELOG.md") -Destination (Join-Path $portableDir "CHANGELOG.md") -Force -ErrorAction SilentlyContinue

# 2. Compress Portable ZIP
$zipName = "Sharabha-$Tag-windows-x64-portable.zip"
$zipPath = Join-Path $projectRoot $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path "$portableDir\*" -DestinationPath $zipPath -Force
Write-Host "  [OK] Created: $zipName" -ForegroundColor Green

# 3. Setup Installer
$setupName = "Sharabha-$Tag-windows-x64-setup.exe"
$setupPath = Join-Path $projectRoot $setupName
$builtSetup = Join-Path $projectRoot "zig-out\bin\SharabhaSetup.exe"
if (Test-Path $builtSetup) {
    Copy-Item $builtSetup -Destination $setupPath -Force
    Write-Host "  [OK] Created: $setupName" -ForegroundColor Green
}

# 4. Clean up temporary directory
Remove-Item -Recurse -Force $portableDir

Get-Item $zipPath, $setupPath | Select-Object Name, Length
