param(
    [string]$Key,
    [string]$NewValue
)

# SHARABHA // STHITI SANKALPA ATOMIC SAVE MUTATION ENGINE
# Directly modifies key-value pairs matching SaveGameService.cs logic with .sharabha.bak backup.

if (-not $Key) {
    Write-Host "[!] No target key specified."
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$binExe = Join-Path $projectDir "zig-out\bin\SharabhaCli.exe"

# Extract raw key if formatted as "Label [Key]"
$rawKey = $Key.Trim()
if ($rawKey -match '\[([A-Za-z0-9_.\-]+)\]$') {
    $rawKey = $Matches[1]
}

if (Test-Path $binExe) {
    & $binExe --write-save-kv $rawKey $NewValue
} else {
    Write-Warning "SharabhaCli.exe not found at $binExe"
}

# Auto-reparse into LiveSave so Slint updates immediately
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir "open_dialog.ps1") -Reparse
