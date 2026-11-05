# Creates a valid synthetic Unreal Engine 5 GVAS save file for testing and verification
param(
    [string]$OutPath = "assets\saves\SampleUe5.sav"
)

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

function Write-FString($str) {
    if (-not $str) {
        $bw.Write([int]0)
        return
    }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($str)
    $bw.Write([int]($bytes.Length + 1))
    $bw.Write($bytes)
    $bw.Write([byte]0)
}

# 1. GVAS Header
$bw.Write([System.Text.Encoding]::ASCII.GetBytes("GVAS")) # Magic
$bw.Write([int]3)                                         # SaveGameFileVersion
$bw.Write([int]518)                                       # PackageFileVersionUE4
$bw.Write([uint16]5)                                      # EngineMajor
$bw.Write([uint16]2)                                      # EngineMinor
$bw.Write([uint16]1)                                      # EnginePatch
$bw.Write([uint32]0)                                      # EngineBuild
Write-FString "++UE5+Release-5.2"                         # EngineBranch
$bw.Write([int]3)                                         # CustomVersionFormat
$bw.Write([int]0)                                         # CustomVersionCount
Write-FString "/Script/SharabhaGame.HeroSave"             # SaveGameClassName

# 2. Properties
# Property 1: "PlayerGold" (IntProperty = 99999)
Write-FString "PlayerGold"
Write-FString "IntProperty"
$bw.Write([int]4)                    # size
$bw.Write([int]0)                    # array index
$bw.Write([byte]0)                   # separator
$bw.Write([int]99999)

# Property 2: "IsHardcore" (BoolProperty = true)
Write-FString "IsHardcore"
Write-FString "BoolProperty"
$bw.Write([int]0)
$bw.Write([int]0)
$bw.Write([byte]1)                   # bool value
$bw.Write([byte]0)                   # separator

# Property 3: "MovementSpeed" (FloatProperty = 450.5)
Write-FString "MovementSpeed"
Write-FString "FloatProperty"
$bw.Write([int]4)
$bw.Write([int]0)
$bw.Write([byte]0)
$bw.Write([float]450.5)

# Property 4: "PlayerName" (StrProperty = "Sharabheshwara")
Write-FString "PlayerName"
Write-FString "StrProperty"
$strBytes = [System.Text.Encoding]::ASCII.GetBytes("Sharabheshwara")
$bw.Write([int]($strBytes.Length + 5))
$bw.Write([int]0)
$bw.Write([byte]0)
Write-FString "Sharabheshwara"

# "None" terminator
Write-FString "None"

$bw.Flush()
$data = $ms.ToArray()
$bw.Close()
$ms.Close()

$parent = Split-Path -Parent $OutPath
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllBytes($OutPath, $data)
$lenStr = $data.Length
Write-Host ('[✓] Created synthetic UE5 GVAS save file: ' + $OutPath + ' (' + $lenStr + ' bytes)')
