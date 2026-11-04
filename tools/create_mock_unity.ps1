# ==============================================================================
# SHARABHA // AIKYA SUTRA (ऐक्य सूत्र) — MOCK UNITY SAVE GENERATOR
# Generates realistic Unity saves for verification:
# 1. SampleUnity.dat (NRBF BinaryFormatter)
# 2. SampleUnity.es3 (Easy Save 3 JSON)
# ==============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$savesDir = Join-Path $projectDir "assets\saves"
if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir -Force | Out-Null }

# 1. Generate SampleUnity.es3
$es3Path = Join-Path $savesDir "SampleUnity.es3"
$es3Lines = @(
    "{"
    '  "PlayerGold": {'
    '    "__type": "int",'
    '    "value": 50000'
    '  },'
    '  "PlayerHealth": {'
    '    "__type": "float",'
    '    "value": 100.0'
    '  },'
    '  "PlayerName": {'
    '    "__type": "string",'
    '    "value": "Arjuna"'
    '  },'
    '  "IsHardcore": {'
    '    "__type": "bool",'
    '    "value": false'
    '  },'
    '  "PlayerMana": {'
    '    "__type": "int",'
    '    "value": 250'
    '  }'
    "}"
)
$es3Content = [string]::Join("`r`n", $es3Lines)
[System.IO.File]::WriteAllText($es3Path, $es3Content, (New-Object System.Text.UTF8Encoding $false))
Write-Host "[OK] Created Sample Unity ES3 save: $es3Path"

# 2. Generate SampleUnity.dat (BinaryFormatter NRBF)
$datPath = Join-Path $savesDir "SampleUnity.dat"
$ms = New-Object System.IO.MemoryStream

function Write-7Bit([System.IO.MemoryStream]$stream, [int]$val) {
    $v = $val
    while ($v -ge 0x80) {
        $stream.WriteByte([byte]($v -bor 0x80))
        $v = $v -shr 7
    }
    $stream.WriteByte([byte]$v)
}

function Write-Str([System.IO.MemoryStream]$stream, [string]$s) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($s)
    Write-7Bit $stream $b.Length
    $stream.Write($b, 0, $b.Length)
}

# SerializationHeaderRecord (17 bytes)
$header = [byte[]]@(
    0x00,                               # RecordTypeEnum.SerializedStreamHeader
    0x01, 0x00, 0x00, 0x00,             # RootId = 1
    0xFF, 0xFF, 0xFF, 0xFF,             # HeaderId = -1
    0x01, 0x00, 0x00, 0x00,             # MajorVersion = 1
    0x00, 0x00, 0x00, 0x00              # MinorVersion = 0
)
$ms.Write($header, 0, $header.Length)

# SystemClassWithMembersAndTypes (RecordType 4)
$ms.WriteByte(0x04)
$ms.Write([System.BitConverter]::GetBytes([int]1), 0, 4) # ObjectId = 1
Write-Str $ms "PlayerProfileSave"

# Member count: 3
$ms.Write([System.BitConverter]::GetBytes([int]3), 0, 4)

# Member names
Write-Str $ms "PlayerGold"
Write-Str $ms "PlayerHealth"
Write-Str $ms "IsHardcore"

# BinaryTypeEnums: Primitive (0), Primitive (0), Primitive (0)
$ms.WriteByte(0x00)
$ms.WriteByte(0x00)
$ms.WriteByte(0x00)

# AdditionalTypeInfo: Int32 (8), Single (11), Boolean (1)
$ms.WriteByte(0x08)
$ms.WriteByte(0x0B)
$ms.WriteByte(0x01)

# Member Values
# PlayerGold = 88888 (0x00015B38)
$ms.Write([System.BitConverter]::GetBytes([int]88888), 0, 4)
# PlayerHealth = 100.0f
$ms.Write([System.BitConverter]::GetBytes([float]100.0), 0, 4)
# IsHardcore = false
$ms.WriteByte(0x00)

# MessageEnd (RecordType 11)
$ms.WriteByte(0x0B)

[System.IO.File]::WriteAllBytes($datPath, $ms.ToArray())
$ms.Dispose()
$datSize = (Get-Item $datPath).Length
Write-Host "[OK] Created Sample Unity NRBF save: $datPath ($datSize bytes)"
