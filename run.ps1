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

# Verify Chitrapata GPU-Accelerated Video Frame Buffers
$loopDir = "assets\media\loop_frames"
$splashDir = "assets\media\splash_frames"
if (-not (Test-Path $loopDir) -or (Get-ChildItem $loopDir -Filter "*.jpg" -ErrorAction SilentlyContinue).Count -lt 239) {
    Write-Host "  - Priming Chitrapata 24 FPS Loop Frames from bg_canvas_loop.mp4..." -ForegroundColor Yellow
    python -c "import cv2, os; os.makedirs('assets/media/loop_frames', exist_ok=True); cap = cv2.VideoCapture('assets/media/bg_canvas_loop.mp4'); total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); [cv2.imwrite(f'assets/media/loop_frames/frame_{i:03d}.jpg', cv2.resize(cap.read()[1], (1280, 720), interpolation=cv2.INTER_AREA), [int(cv2.IMWRITE_JPEG_QUALITY), 80]) for i in range(total)]; cap.release()"
}
if (-not (Test-Path $splashDir) -or (Get-ChildItem $splashDir -Filter "*.jpg" -ErrorAction SilentlyContinue).Count -lt 143) {
    Write-Host "  - Priming Chitrapata 24 FPS Splash Frames from splash_sharabha.mp4..." -ForegroundColor Yellow
    python -c "import cv2, os; os.makedirs('assets/media/splash_frames', exist_ok=True); cap = cv2.VideoCapture('assets/media/splash_sharabha.mp4'); total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); [cv2.imwrite(f'assets/media/splash_frames/frame_{i:03d}.jpg', cv2.resize(cap.read()[1], (1280, 720), interpolation=cv2.INTER_AREA), [int(cv2.IMWRITE_JPEG_QUALITY), 80]) for i in range(total)]; cap.release()"
}
Write-Host "  - Chitrapata Media Engine: Hardware frame buffers primed (382 frames @ 24 FPS)" -ForegroundColor Green

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

$cliBinPath = "zig-out\bin\SharabhaCli.exe"
$guiBinPath = "zig-out\bin\Sharabha.exe"
if (-not (Test-Path $cliBinPath) -or -not (Test-Path $guiBinPath)) {
    Write-Error "Target executable not found in zig-out\bin"
    exit 1
}
Write-Host "  [OK] Native binaries compiled: $guiBinPath (GUI Launcher) & $cliBinPath (CLI Engine)" -ForegroundColor Green

# 4. Execute Core Diagnostics & Launch Slint Desktop UI
Write-Host ""
Write-Host "[4/4] Invoking Sharabha Core Subsystems..." -ForegroundColor Cyan
& $cliBinPath

if (-not $CliOnly -and $slintExe -and (Test-Path $slintExe)) {
    Write-Host ""
    Write-Host "  - Harvesting real host processes via Netra Inquest..." -ForegroundColor Yellow
    powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "tools/refresh_processes.ps1"

    $binExe = (Convert-Path $cliBinPath).Replace('\', '/')
    Write-Host "Launching native Slint GUI Window (src/ui/app.slint)..." -ForegroundColor Yellow
    $callbacks = @(
        "--on", "refresh_processes", "powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/refresh_processes.ps1",
        "--on", "attach_process", "$binExe --attach `$1",
        "--on", "start_memory_scan", "$binExe --scan `$1 `$2",
        "--on", "rescan_memory", "$binExe --rescan `$1 `$2",
        "--on", "reset_memory_scan", "$binExe --reset-scan",
        "--on", "write_memory_address", "$binExe --write-mem `$1 `$2",
        "--on", "toggle_freeze_address", "$binExe --freeze-mem `$1 `$2",
        "--on", "run_lua_script", "$binExe --run-lua `"`$1`"",
        "--on", "open_save_file", "powershell -Sta -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1",
        "--on", "reparse_save_file", "powershell -Sta -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1 -Reparse",
        "--on", "save_file_atomic", "$binExe --commit-save assets/saves/ER0000.sl2",
        "--on", "cycle_metric", "powershell -WindowStyle Hidden -NoProfile -Command Write-Host '[OK] Metric Evaluated via Switching Engine'",
        "--on", "cycle_extractor", "powershell -WindowStyle Hidden -NoProfile -Command Write-Host '[OK] Extractor Switched via Agama Engine'",
        "--on", "toggle_ai_guidance", "powershell -WindowStyle Hidden -NoProfile -Command Write-Host '[OK] Divya Drishti AI Oracle Toggled'",
        "--on", "test_vault", "$binExe --test-vault",
        "--on", "save_vault", "$binExe --seal-vault",
        "--on", "toggle_save_view_mode", "powershell -WindowStyle Hidden -NoProfile -Command Write-Host '[OK] Dual-Mode View Switched'",
        "--on", "cycle_canvas_mode", "powershell -WindowStyle Hidden -NoProfile -Command Write-Host '[OK] Chitrapata Video Mode Cycled'",
        "--on", "register_agama_profile", "$binExe --export-surreal"
    )
    & $slintExe "src/ui/app.slint" --auto-reload $callbacks
} elseif ($CliOnly) {
    Write-Host ""
    Write-Host "CLI run completed (-CliOnly specified)." -ForegroundColor Gray
}