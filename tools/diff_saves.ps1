param(
    [string]$SavePathA = "",
    [string]$SavePathB = "",
    [switch]$CompareWithBak
)

# ==============================================================================
# SHARABHA // KALA CHAKRA (काल चक्र) VISUAL SAVE DIFF & EVOLUTION INSPECTOR
# Compares Baseline Vessel (A) against Evolved Vessel (B)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$activeSaveFile = Join-Path $projectDir "assets\saves\active_save_path.txt"

$pathA = $SavePathA
$pathB = $SavePathB

if ($CompareWithBak -or (-not $pathA -and -not $pathB)) {
    if (Test-Path $activeSaveFile) {
        $curSave = (Get-Content $activeSaveFile -Raw).Trim()
        $bakCand = $curSave + ".sharabha.bak"
        if (-not (Test-Path $bakCand)) { $bakCand = $curSave + ".bak" }

        if ((Test-Path $curSave) -and (Test-Path $bakCand)) {
            $pathA = $bakCand
            $pathB = $curSave
            Write-Host "[OK] Kala Chakra auto-paired active save with Sthiti Kavacha backup."
        }
    }
}

if (-not $pathA -or -not (Test-Path $pathA)) {
    $dialogA = New-Object System.Windows.Forms.OpenFileDialog
    $dialogA.Title = "KALA CHAKRA // Select Baseline Save Vessel (A - काल पूर्व)"
    $dialogA.Filter = "All Supported Saves (*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin;*.bak)|*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin;*.bak|All Files (*.*)|*.*"
    $dialogA.InitialDirectory = Join-Path $projectDir "assets\saves"

    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.StartPosition = "CenterScreen"; $owner.Size = New-Object System.Drawing.Size(1, 1); $owner.Opacity = 0; $owner.Show(); $owner.BringToFront()
    $resA = $dialogA.ShowDialog($owner)
    $owner.Close(); $owner.Dispose()

    if ($resA -ne [System.Windows.Forms.DialogResult]::OK -or -not (Test-Path $dialogA.FileName)) {
        Write-Host "[!] Diff cancelled by user."
        exit 0
    }
    $pathA = $dialogA.FileName
}

if (-not $pathB -or -not (Test-Path $pathB)) {
    $dialogB = New-Object System.Windows.Forms.OpenFileDialog
    $dialogB.Title = "KALA CHAKRA // Select Evolved Save Vessel (B - काल पश्चात्)"
    $dialogB.Filter = "All Supported Saves (*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin;*.bak)|*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin;*.bak|All Files (*.*)|*.*"
    $dialogB.InitialDirectory = Split-Path -Parent $pathA

    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.StartPosition = "CenterScreen"; $owner.Size = New-Object System.Drawing.Size(1, 1); $owner.Opacity = 0; $owner.Show(); $owner.BringToFront()
    $resB = $dialogB.ShowDialog($owner)
    $owner.Close(); $owner.Dispose()

    if ($resB -ne [System.Windows.Forms.DialogResult]::OK -or -not (Test-Path $dialogB.FileName)) {
        Write-Host "[!] Diff cancelled by user."
        exit 0
    }
    $pathB = $dialogB.FileName
}

$fileA = Get-Item $pathA
$fileB = Get-Item $pathB
$bytesA = [System.IO.File]::ReadAllBytes($fileA.FullName)
$bytesB = [System.IO.File]::ReadAllBytes($fileB.FullName)

Write-Host "Comparing: $($fileA.Name) ($($bytesA.Length) B) vs $($fileB.Name) ($($bytesB.Length) B)..."

$mutations = [System.Collections.Generic.List[PSCustomObject]]::new()

# Check if both are Unreal Engine GVAS saves
$isGvasA = ($bytesA.Length -ge 4 -and $bytesA[0] -eq 0x47 -and $bytesA[1] -eq 0x56 -and $bytesA[2] -eq 0x41 -and $bytesA[3] -eq 0x53)
$isGvasB = ($bytesB.Length -ge 4 -and $bytesB[0] -eq 0x47 -and $bytesB[1] -eq 0x56 -and $bytesB[2] -eq 0x41 -and $bytesB[3] -eq 0x53)

function Parse-GvasProps([byte[]]$b) {
    $props = @{}
    if ($b.Length -lt 24) { return $props }
    function Read-S([ref]$p) {
        if ($p.Value + 4 -gt $b.Length) { return "" }
        $l = [System.BitConverter]::ToInt32($b, $p.Value); $p.Value += 4
        if ($l -le 0 -or $p.Value + $l -gt $b.Length) { return "" }
        $s = [System.Text.Encoding]::ASCII.GetString($b, $p.Value, [Math]::Max(0, $l - 1))
        $p.Value += $l; return $s
    }
    $pos = 4 + 4 + 4 + 2 + 2 + 2 + 4
    $branch = Read-S ([ref]$pos)
    $cFormat = [System.BitConverter]::ToInt32($b, $pos); $pos += 4
    $cCount = [System.BitConverter]::ToInt32($b, $pos); $pos += 4
    if ($cCount -gt 0 -and $cCount -lt 500) { $pos += ($cCount * 20) }
    $sClass = Read-S ([ref]$pos)

    while ($pos + 4 -le $b.Length -and $props.Count -lt 200) {
        $pName = Read-S ([ref]$pos)
        if (-not $pName -or $pName -eq "None") { break }
        $pType = Read-S ([ref]$pos)
        if (-not $pType) { break }
        $pSize = [System.BitConverter]::ToInt32($b, $pos); $pos += 4
        $arrIdx = [System.BitConverter]::ToInt32($b, $pos); $pos += 4

        $valStr = ""
        if ($pType -eq "IntProperty") {
            $pos += 1
            $v = [System.BitConverter]::ToInt32($b, $pos); $pos += 4
            $valStr = "$v"
        } elseif ($pType -eq "FloatProperty") {
            $pos += 1
            $v = [System.BitConverter]::ToSingle($b, $pos); $pos += 4
            $valStr = "$([Math]::Round($v, 2))"
        } elseif ($pType -eq "BoolProperty") {
            $bv = ($b[$pos] -ne 0); $pos += 2
            $valStr = if ($bv) { "true" } else { "false" }
        } elseif ($pType -eq "StrProperty" -or $pType -eq "NameProperty") {
            $pos += 1
            $valStr = "'" + (Read-S ([ref]$pos)) + "'"
        } else {
            $pos += ($pSize + 1)
            $valStr = "[$pType]"
        }
        $props[$pName] = @{ Type = $pType; Val = $valStr }
    }
    return $props
}

if ($isGvasA -and $isGvasB) {
    $pMapA = Parse-GvasProps $bytesA
    $pMapB = Parse-GvasProps $bytesB

    foreach ($k in $pMapB.Keys) {
        $itemB = $pMapB[$k]
        if ($pMapA.ContainsKey($k)) {
            $itemA = $pMapA[$k]
            if ($itemA.Val -ne $itemB.Val) {
                $deltaStr = "Mutated"
                if ($itemA.Val -match '^-?\d+$' -and $itemB.Val -match '^-?\d+$') {
                    $diffNum = [long]$itemB.Val - [long]$itemA.Val
                    $deltaStr = if ($diffNum -ge 0) { "+$diffNum" } else { "$diffNum" }
                }
                $mutations.Add([PSCustomObject]@{
                    Offset = "GVAS: $k"
                    Field = $k
                    Type = $itemB.Type
                    Before = $itemA.Val
                    After = $itemB.Val
                    Delta = $deltaStr
                    Conf = "100% Curated Maya Sutra"
                })
            }
        } else {
            $mutations.Add([PSCustomObject]@{
                Offset = "GVAS: $k"
                Field = $k
                Type = $itemB.Type
                Before = "(unset)"
                After = $itemB.Val
                Delta = "+New Property"
                Conf = "100% Curated Maya Sutra"
            })
        }
    }
} else {
    # Binary byte diff
    $minLen = [Math]::Min($bytesA.Length, $bytesB.Length)
    $cursor = 0

    while ($cursor -lt $minLen -and $mutations.Count -lt 150) {
        if ($bytesA[$cursor] -ne $bytesB[$cursor]) {
            $alignedStart = $cursor -band (-bnot 3)
            if ($alignedStart + 4 -le $minLen) {
                $isDiffDword = $false
                for ($k = 0; $k -lt 4; $k++) {
                    if ($bytesA[$alignedStart + $k] -ne $bytesB[$alignedStart + $k]) { $isDiffDword = $true; break }
                }
                if ($isDiffDword) {
                    $vA = [System.BitConverter]::ToInt32($bytesA, $alignedStart)
                    $vB = [System.BitConverter]::ToInt32($bytesB, $alignedStart)
                    $diff = [long]$vB - [long]$vA
                    $deltaStr = if ($diff -ge 0) { "+$diff" } else { "$diff" }

                    $mutations.Add([PSCustomObject]@{
                        Offset = "0x{0:X4}" -f $alignedStart
                        Field = "DWORD[0x{0:X4}]" -f $alignedStart
                        Type = "i32 (Scalar)"
                        Before = "$vA"
                        After = "$vB"
                        Delta = $deltaStr
                        Conf = "92% Aligned Scalar"
                    })
                    $cursor = $alignedStart + 4
                    continue
                }
            }

            $bA = $bytesA[$cursor]
            $bB = $bytesB[$cursor]
            $diffB = [int]$bB - [int]$bA
            $deltaB = if ($diffB -ge 0) { "+$diffB" } else { "$diffB" }

            $mutations.Add([PSCustomObject]@{
                Offset = "0x{0:X4}" -f $cursor
                Field = "BYTE[0x{0:X4}]" -f $cursor
                Type = "u8 (Byte)"
                Before = ("0x{0:X2} ({1})" -f @($bA, $bA))
                After = ("0x{0:X2} ({1})" -f @($bB, $bB))
                Delta = $deltaB
                Conf = "80% Byte Mutation"
            })
            $cursor += 1
        } else {
            $cursor += 1
        }
    }

    if ($bytesA.Length -ne $bytesB.Length) {
        $szDiff = [long]$bytesB.Length - [long]$bytesA.Length
        $dStr = if ($szDiff -ge 0) { "+$szDiff B" } else { "$szDiff B" }
        $mutations.Add([PSCustomObject]@{
            Offset = "VESSEL_EOF"
            Field = "Vessel Length Delta"
            Type = "Container Size"
            Before = "$($bytesA.Length) Bytes"
            After = "$($bytesB.Length) Bytes"
            Delta = $dStr
            Conf = "100% Deterministic"
        })
    }
}

Write-Host "[OK] Kala Chakra discovered $($mutations.Count) mutation(s)."

# Export to src\ui\live_diff.slint
function Escape-Slint($str) {
    if (-not $str) { return "" }
    return ([string]$str).Replace('\', '\\').Replace('"', '\"')
}

$q = '"'
$diffSlintPath = Join-Path $projectDir "src\ui\live_diff.slint"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('// Auto-generated by Sharabha Kala Chakra (काल चक्र // Save Diff Engine)')
$lines.Add('export struct DiffRowData {')
$lines.Add('    offset: string,')
$lines.Add('    field: string,')
$lines.Add('    type_name: string,')
$lines.Add('    before: string,')
$lines.Add('    after: string,')
$lines.Add('    delta: string,')
$lines.Add('    conf: string,')
$lines.Add('}')
$lines.Add('')
$lines.Add('export global LiveDiff {')
$lines.Add('    in property <bool> is_active: true;')
$lines.Add('    in property <string> file_a: ' + $q + (Escape-Slint $fileA.Name) + $q + ';')
$lines.Add('    in property <string> file_b: ' + $q + (Escape-Slint $fileB.Name) + $q + ';')
$lines.Add('    in property <int> total_mutations: ' + $mutations.Count + ';')
$lines.Add('    in property <string> status_text: ' + $q + 'Kala Chakra: ' + $mutations.Count + ' mutation(s) isolated between ' + (Escape-Slint $fileA.Name) + ' and ' + (Escape-Slint $fileB.Name) + $q + ';')
$lines.Add('')
$lines.Add('    in property <[DiffRowData]> rows: [')

for ($i = 0; $i -lt $mutations.Count; $i++) {
    $m = $mutations[$i]
    $comma = if ($i -lt $mutations.Count - 1) { "," } else { "" }
    $o = Escape-Slint $m.Offset
    $f = Escape-Slint $m.Field
    $t = Escape-Slint $m.Type
    $b = Escape-Slint $m.Before
    $a = Escape-Slint $m.After
    $d = Escape-Slint $m.Delta
    $c = Escape-Slint $m.Conf
    $lines.Add('        { offset: ' + $q + $o + $q + ', field: ' + $q + $f + $q + ', type_name: ' + $q + $t + $q + ', before: ' + $q + $b + $q + ', after: ' + $q + $a + $q + ', delta: ' + $q + $d + $q + ', conf: ' + $q + $c + $q + ' }' + $comma)
}

$lines.Add('    ];')
$lines.Add('}')

$content = [string]::Join("`r`n", $lines)
[System.IO.File]::WriteAllText($diffSlintPath, $content, (New-Object System.Text.UTF8Encoding $true))
Write-Host "[OK] LiveDiff Slint module updated: $diffSlintPath"

# Touch app.slint to trigger live reload
$appSlint = Join-Path $projectDir "src\ui\app.slint"
if (Test-Path $appSlint) {
    (Get-Item $appSlint).LastWriteTime = Get-Date
}
