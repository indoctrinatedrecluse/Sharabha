<#
.SYNOPSIS
    Sharabha Rudra Tandava Memory Operations CLI & P/Invoke Orchestrator
.DESCRIPTION
    Wraps native Win32 memory scanning, differential filtering, RAM mutation, and active freezing.
    Dispatches directly to native SharabhaCli.exe with fallbacks.
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("Attach", "Scan", "Rescan", "Write", "Freeze", "Reset", "List")]
    [string]$Action = "Scan",

    [Parameter(Position=1)]
    [string]$TargetValue = "100",

    [Parameter(Position=2)]
    [string]$DataType = "4 Bytes (i32)",

    [string]$TargetAddress = "",
    [int]$TargetPid = 0,
    [bool]$FreezeState = $true,
    [string]$RescanType = "EXACT"
)

$cliExe = Join-Path $PSScriptRoot "..\zig-out\bin\SharabhaCli.exe"

if (-not (Test-Path $cliExe)) {
    Write-Error "SharabhaCli.exe not found at $cliExe. Please run 'zig build' first."
    exit 1
}

switch ($Action) {
    "Attach" {
        if ($TargetPid -gt 0) {
            & $cliExe --attach $TargetPid
        } else {
            & $cliExe --attach
        }
    }
    "Scan" {
        & $cliExe --scan $TargetValue $DataType
    }
    "Rescan" {
        & $cliExe --rescan $TargetValue $RescanType
    }
    "Write" {
        if (-not $TargetAddress) {
            Write-Error "TargetAddress required for Write action."
            exit 1
        }
        & $cliExe --write-mem $TargetAddress $TargetValue
    }
    "Freeze" {
        if (-not $TargetAddress) {
            Write-Error "TargetAddress required for Freeze action."
            exit 1
        }
        $stateStr = if ($FreezeState) { "true" } else { "false" }
        & $cliExe --freeze-mem $TargetAddress $stateStr
    }
    "Reset" {
        & $cliExe --reset-scan
    }
    "List" {
        & $cliExe --list-processes
    }
}
