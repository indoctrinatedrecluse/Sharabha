param(
    [string]$Tag = "v0.3.0",
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$OutputPath = "release_notes.md"
)

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
