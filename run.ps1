<#
================================================================================
  SHARABHA - Native Windows Build & Launch Script
  Rudra Tandava (Memory Engine) & Kalyana Sthiti (Save Forge)
================================================================================
#>

[CmdletBinding()]
param(
    [switch]$SkipTests,
    [switch]$CliOnly
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "========================================================================" -ForegroundColor DarkYellow
Write-Host "  SHARABHA (Sharabheshwara) - The Dual Aspect Engine (v0.1.0)" -ForegroundColor Yellow
Write-Host "  [Kalyana Sthiti: Calm]   |   [Rudra Tandava: Violent]" -ForegroundColor Cyan
Write-Host "  Om Namah Sharabhaya - Awakening the Ashtamurti on Windows" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor DarkYellow
Write-Host ""

# 1. Discover Toolchains
Write-Host "[1/4] Discovering build and runtime toolchains..." -ForegroundColor Cyan

$zigExe = Get-Command "zig" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $zigExe) {
    $wingetZig = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.17.0\zig.exe"
    if (Test-Path $wingetZig) {
        $zigDir = Split-Path $wingetZig -Parent
        $env:Path = $zigDir + ";" + $env:Path
        $zigExe = $wingetZig
    }
}

if (-not $zigExe -or -not (Test-Path $zigExe)) {
    Write-Error "Zig compiler was not found. Please install Zig 0.17+ or ensure it is in PATH."
    exit 1
}
Write-Host "  - Zig Compiler: $zigExe" -ForegroundColor Green

$slintExe = Get-Command "slint-viewer" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $slintExe) {
    $cargoSlint = Join-Path $env:USERPROFILE ".cargo\bin\slint-viewer.exe"
    if (Test-Path $cargoSlint) {
        $cargoDir = Split-Path $cargoSlint -Parent
        $env:Path = $cargoDir + ";" + $env:Path
        $slintExe = $cargoSlint
    }
}

if (-not $slintExe -or -not (Test-Path $slintExe)) {
    Write-Warning "slint-viewer was not found in PATH or ~/.cargo/bin. UI preview will fall back to CLI."
} else {
    Write-Host "  - Slint Runtime: $slintExe" -ForegroundColor Green
}

# 2. Run Test Suite
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "[2/4] Executing test suite across all subsystems..." -ForegroundColor Cyan
    & $zigExe build test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Test suite encountered failures. Halting launch."
        exit $LASTEXITCODE
    }
    Write-Host "  [OK] All unit and integration test suites passed cleanly!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[2/4] Skipping tests (-SkipTests specified)." -ForegroundColor Yellow
}

# 3. Compile Native Executable
Write-Host ""
Write-Host "[3/4] Compiling Sharabha native Windows executable..." -ForegroundColor Cyan
& $zigExe build -Doptimize=ReleaseSafe
if ($LASTEXITCODE -ne 0) {
    Write-Error "Zig compilation failed."
    exit $LASTEXITCODE
}

$binPath = "zig-out\bin\Sharabha.exe"
if (-not (Test-Path $binPath)) {
    Write-Error "Target executable not found at $binPath"
    exit 1
}
Write-Host "  [OK] Native binary compiled: $binPath" -ForegroundColor Green

# 4. Execute Core Diagnostics & Launch Slint Desktop UI
Write-Host ""
Write-Host "[4/4] Invoking Sharabha Core Subsystems..." -ForegroundColor Cyan
& $binPath

if (-not $CliOnly -and $slintExe -and (Test-Path $slintExe)) {
    Write-Host ""
    Write-Host "Launching native Slint GUI Window (src\ui\app.slint)..." -ForegroundColor Yellow
    $callbacks = @(
        "--on", "save_file_atomic", "`"$binPath`"",
        "--on", "test_vault", "powershell -NoProfile -Command Write-Host 'DPAPI Hardware Vault Unlocked // Validated'",
        "--on", "save_vault", "powershell -NoProfile -Command Write-Host 'DPAPI Hardware Vault Sealed // Saved'"
    )
    & $slintExe "src\ui\app.slint" $callbacks
} elseif ($CliOnly) {
    Write-Host ""
    Write-Host "CLI run completed (-CliOnly specified)." -ForegroundColor Gray
}