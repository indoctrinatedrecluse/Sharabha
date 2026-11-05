<#
================================================================================
  SHARABHA // SCRIPT ENCODING & PARSE GUARD
  --------------------------------------------------------------------------------
  Windows PowerShell 5.1 decodes BOM-less .ps1 files as ANSI (Windows-1252).
  Any emoji or Devanagari glyph then decodes into "smart quotes" (0x93 / 0x94)
  or other punctuation, which the tokenizer treats as string delimiters, so the
  whole script fails with "The string is missing the terminator" and the UI
  callback that shells it out dies silently. This guard parses every script in
  tools\ and reports ParserError locations.

  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_scripts.ps1
  Exit  :  0 = all scripts parse, 1 = at least one script failed to parse
================================================================================
#>

$ErrorActionPreference = "Continue"

$toolsDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$scripts = Get-ChildItem -LiteralPath $toolsDir -Filter "*.ps1" -File | Sort-Object Name

$failures = 0
$checked = 0

foreach ($script in $scripts) {
    $checked++
    $errors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $failures++
        Write-Host "[FAIL] $($script.Name)" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host ("       line {0}: {1}" -f $err.Extent.StartLineNumber, $err.Message) -ForegroundColor Red
        }
        continue
    }

    # Warn when a script carries non-ASCII text but no UTF-8 BOM (fragile encoding)
    $bytes = [System.IO.File]::ReadAllBytes($script.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -gt 0x7F) { $nonAscii = $true; break }
    }
    if ($nonAscii -and -not $hasBom) {
        Write-Host "[WARN] $($script.Name): non-ASCII text without UTF-8 BOM (add a BOM)" -ForegroundColor Yellow
    } else {
        Write-Host "[ OK ] $($script.Name)" -ForegroundColor Green
    }
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "$failures of $checked script(s) failed to parse." -ForegroundColor Red
    exit 1
}

Write-Host "All $checked script(s) parse cleanly." -ForegroundColor Cyan
exit 0
