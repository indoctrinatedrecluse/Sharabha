# ==============================================================================
# SHARABHA // KAVYA SUTRA (Kavya Sutra) - MOCK RENPY SAVE GENERATOR
# Generates a realistic Ren'Py visual novel save vessel:
#     "Ren'Py Save Game <version> <timestamp>\n" + zlib(pickle protocol 2)
# Produces: assets\saves\SampleRenpy.save
# ==============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$savesDir = Join-Path $projectDir "assets\saves"
if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir -Force | Out-Null }

$targetPath = Join-Path $savesDir "SampleRenpy.save"

# ------------------------------------------------------------------------------
# Pickle protocol 2 stream builder (little-endian, mirrors Python's pickle.dumps)
# ------------------------------------------------------------------------------
$pickle = New-Object System.IO.MemoryStream

function BRaw([byte[]]$b) { $pickle.Write($b, 0, $b.Length) }
function B1([int]$v) { $pickle.WriteByte([byte]($v -band 0xFF)) }
function B2([int]$v) {
    B1 $v
    B1 ($v -shr 8)
}
function B4([int]$v) {
    B1 $v
    B1 ($v -shr 8)
    B1 ($v -shr 16)
    B1 ($v -shr 24)
}
# BINUNICODE 'X' <u32 len> <utf8 bytes>
function BStr([string]$s) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($s)
    B1 0x58
    B4 $b.Length
    BRaw $b
}
# BININT1 'K' <u8>
function BInt1([int]$v) {
    B1 0x4B
    B1 $v
}
# BININT2 'M' <u16le>
function BInt2([int]$v) {
    B1 0x4D
    B2 $v
}
# BINFLOAT 'G' <8 byte big-endian IEEE-754 double>
function BFloat([double]$d) {
    B1 0x47
    $b = [System.BitConverter]::GetBytes($d)
    [Array]::Reverse($b)
    BRaw $b
}
function BDictOpen() { B1 0x7D; B1 0x28 }   # EMPTY_DICT + MARK
function BDictCommit() { B1 0x75 }           # SETITEMS

# PROTO 2
B1 0x80
B1 0x02

# Outer dict: Ren'Py saves carry a nested "store" namespace of game variables.
BDictOpen
BStr "version"
BStr "1.4.2"

BStr "store"
BDictOpen
BStr "player_name"
BStr "Arjuna"
BStr "player_gold"
BInt2 1500
BStr "player_level"
BInt1 12
BStr "affection"
BFloat 87.5
BStr "is_hardcore"
B1 0x89                                      # NEWFALSE (protocol 2)
BStr "inventory"
BDictOpen
BStr "sword"
BInt1 1
BStr "potion"
BInt1 5
BDictCommit
BStr "chapter_title"
BStr "Chapter 3 - The Silent Ashram of the Sharabha (Kavya Sutra smoke test fixture)"
BDictCommit                                  # close "store"

BStr "save_name"
BStr "Ashram Gate - Slot 01"
BDictCommit                                  # close outer dict

B1 0x2E                                      # STOP

[byte[]]$plain = $pickle.ToArray()

# ------------------------------------------------------------------------------
# zlib wrapper: [0x78 0x9C] + raw deflate + Adler-32 (big-endian)
# ------------------------------------------------------------------------------
$adlerA = 1
$adlerB = 0
foreach ($byte in $plain) {
    $adlerA = ($adlerA + $byte) % 65521
    $adlerB = ($adlerB + $adlerA) % 65521
}
$adler = ($adlerB * 65536) + $adlerA

$zlib = New-Object System.IO.MemoryStream
$zlib.WriteByte(0x78)
$zlib.WriteByte(0x9C)
$deflate = New-Object System.IO.Compression.DeflateStream($zlib, [System.IO.Compression.CompressionLevel]::Optimal, $true)
$deflate.Write($plain, 0, $plain.Length)
$deflate.Close()
$zlib.WriteByte([byte](($adler -shr 24) -band 0xFF))
$zlib.WriteByte([byte](($adler -shr 16) -band 0xFF))
$zlib.WriteByte([byte](($adler -shr 8) -band 0xFF))
$zlib.WriteByte([byte]($adler -band 0xFF))

# ------------------------------------------------------------------------------
# Assemble header + payload
# ------------------------------------------------------------------------------
$headerText = "Ren'Py Save Game 8.3.4 2025-11-05 12:00:00`n"
[byte[]]$headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headerText)
[byte[]]$payloadBytes = $zlib.ToArray()

$vessel = New-Object System.IO.MemoryStream
$vessel.Write($headerBytes, 0, $headerBytes.Length)
$vessel.Write($payloadBytes, 0, $payloadBytes.Length)

[System.IO.File]::WriteAllBytes($targetPath, $vessel.ToArray())
Write-Host "[OK] Created Ren'Py mock save: $targetPath ($($vessel.Length) bytes, pickle protocol 2)"
