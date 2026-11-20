param(
    [string]$Tag = "",
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$OutputPath = "release_notes.md"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }

if (-not $Tag) {
    $zon = Join-Path $projectDir "build.zig.zon"
    if (Test-Path $zon) {
        $txt = Get-Content $zon -Raw
        if ($txt -match '\.version\s*=\s*"([^"]+)"') {
            $Tag = "v" + $Matches[1].Trim().TrimStart('v', 'V')
        }
    }
    if (-not $Tag) { $Tag = "v0.6.0" }
}

$ver = $Tag.TrimStart('v')
$content = [System.IO.File]::ReadAllText($ChangelogPath, [System.Text.Encoding]::UTF8)
$pattern = "(?s)## \[$ver\][^\r\n]*\r?\n(.*?)(?=\r?\n## \[|\Z)"
if ($content -match $pattern) {
    $notes = $matches[1].Trim()
    [System.IO.File]::WriteAllText($OutputPath, $notes, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "[OK] Extracted release notes for $ver ($($notes.Length) chars)"
} else {
    Write-Warning "Could not find changelog section for [$ver]"
    [System.IO.File]::WriteAllText($OutputPath, "Release $Tag", (New-Object System.Text.UTF8Encoding $false))
}
