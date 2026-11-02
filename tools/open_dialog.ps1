param(
    [string]$TargetFilePath = "",
    [switch]$Reparse
)

# Sharabha Native Windows File Open Dialog & Deep Sūkshma Rekha (Fine Line) Save Engine
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = if ($scriptDir) { Split-Path -Parent $scriptDir } else { (Get-Location).Path }
$activeSaveFile = Join-Path $projectDir "assets\saves\active_save_path.txt"

# 1. Determine Target File Path
$selectedPath = ""
if ($TargetFilePath -and (Test-Path $TargetFilePath)) {
    $selectedPath = $TargetFilePath
} elseif ($Reparse) {
    if (Test-Path $activeSaveFile) {
        $candidate = (Get-Content $activeSaveFile -Raw).Trim()
        if (Test-Path $candidate) {
            $selectedPath = $candidate
        }
    }
}

if (-not $selectedPath) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "SHARABHA // Select Game Save Vessel (पात्र प्रवेश)"
    $dialog.Filter = "All Supported Saves (*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin)|*.json;*.pcsav;*.sl2;*.sav;*.dat;*.bin|JSON Saves (*.json)|*.json|Mass Effect LE (*.pcsav)|*.pcsav|FromSoftware (*.sl2)|*.sl2|Unreal Engine (*.sav)|*.sav|Cyberpunk 2077 (*.dat)|*.dat|All Files (*.*)|*.*"
    
    $initialDir = ""
    if (Test-Path $activeSaveFile) {
        $lastSaved = (Get-Content $activeSaveFile -Raw).Trim()
        if (Test-Path $lastSaved) {
            $initialDir = Split-Path -Parent $lastSaved
        }
    }
    if (-not $initialDir -or -not (Test-Path $initialDir)) {
        $candDir = Join-Path $projectDir "assets\saves"
        if (Test-Path $candDir) { $initialDir = $candDir }
    }
    if ($initialDir) {
        $dialog.InitialDirectory = $initialDir
    }

    # Present dialog in foreground over Slint window
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $owner.Opacity = 0
    $owner.Show()
    $owner.BringToFront()

    $res = $dialog.ShowDialog($owner)
    $owner.Close()
    $owner.Dispose()

    if ($res -ne [System.Windows.Forms.DialogResult]::OK -or -not (Test-Path $dialog.FileName)) {
        Write-Host "[!] Save selection cancelled by user."
        exit 0
    }
    $selectedPath = $dialog.FileName
}

# Persist active save path for instant re-parsing
try {
    $saveDir = Split-Path -Parent $activeSaveFile
    if (-not (Test-Path $saveDir)) { New-Item -ItemType Directory -Path $saveDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($activeSaveFile, $selectedPath, (New-Object System.Text.UTF8Encoding $false))
} catch { }

$file = Get-Item $selectedPath
$filename = $file.Name
$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
$len = $bytes.Length

# Calculate MD5
$md5 = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
$md5Str = [System.BitConverter]::ToString($md5).Replace("-", "").Substring(0, 16)

# ==============================================================================
# SŪKSHMA REKHA (सूक्ष्म रेखा / FINE LINE) HELPER FUNCTIONS
# ==============================================================================
function Get-Val32($offset, [byte[]]$buf = $bytes) {
    if ($offset + 4 -le $buf.Length) {
        return [System.BitConverter]::ToInt32($buf, $offset)
    }
    return 0
}
function Get-UVal32($offset, [byte[]]$buf = $bytes) {
    if ($offset + 4 -le $buf.Length) {
        return [System.BitConverter]::ToUInt32($buf, $offset)
    }
    return 0
}
function Get-Float32($offset, [byte[]]$buf = $bytes) {
    if ($offset + 4 -le $buf.Length) {
        $f = [System.BitConverter]::ToSingle($buf, $offset)
        if ([Single]::IsNaN($f) -or [Single]::IsInfinity($f)) { return 0.0 }
        return [Math]::Round($f, 2)
    }
    return 0.0
}
function Get-Hex($offset, $count = 4, [byte[]]$buf = $bytes) {
    if ($offset + $count -le $buf.Length) {
        $slice = $buf[$offset..($offset + $count - 1)]
        return ([System.BitConverter]::ToString($slice)).Replace("-", " ")
    }
    return "00 00 00 00"
}
function Get-Ascii($offset, $count = 4, [byte[]]$buf = $bytes) {
    if ($offset + $count -le $buf.Length) {
        $chars = [System.Text.Encoding]::ASCII.GetString($buf, $offset, $count)
        return $chars.Replace("`0", "").Trim()
    }
    return ""
}

# Fine Line Garbage Filter: Rejects null padding, MSVC debug fills, uninitialized memory, single-byte repeats
function Test-GarbageWord([uint32]$u) {
    if ($u -eq 0) { return $true }
    if ($u -eq 0xFFFFFFFF) { return $true }
    if ($u -eq 0xCDCDCDCD -or $u -eq 0xCCCCCCCC -or $u -eq 0xDDDDDDDD -or $u -eq 0xABABABAB -or $u -eq 0xFDFDFDFD -or $u -eq 0xFEEEFEEE) { return $true }
    $b = [byte]($u -band 0xFF)
    if ($u -eq ($b * 0x01010101)) { return $true }
    return $false
}

# Fine Line Float Validator: Validates IEEE-754 single precision bounds for gameplay attributes/coordinates
function Test-PlausibleFloatFromBits([uint32]$bits, [float]$f) {
    if ([Single]::IsNaN($f) -or [Single]::IsInfinity($f)) { return $false }
    $af = [Math]::Abs($f)
    if ($af -lt 0.001 -or $af -gt 100000.0) { return $false }
    $exp = ($bits -shr 23) -band 0xFF
    if ($exp -lt 117 -or $exp -gt 144) { return $false }
    return $true
}

# Container Auto-Decompressor: Extracts zlib/deflate streams
function Try-DecompressZlib([byte[]]$src, [int]$startOffset) {
    try {
        if ($startOffset + 2 -lt $src.Length) {
            $ms = New-Object System.IO.MemoryStream($src, $startOffset, ($src.Length - $startOffset))
            $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $outStream = New-Object System.IO.MemoryStream
            $ds.CopyTo($outStream)
            $res = $outStream.ToArray()
            $ds.Close()
            $ms.Close()
            if ($res -and $res.Length -ge 16) {
                return $res
            }
        }
    } catch { }
    return $null
}

$rows = [System.Collections.Generic.List[PSCustomObject]]::new()
$ext = $file.Extension.ToLower()
$isJson = ($ext -eq ".json")
$gameTitle = "$filename (Generic Fuzzy Overseer // प्रवाह दर्शन)"
$verdict = "GenericBinary (स्वयंसिद्ध प्रवाह)"
$isDeterministicProfile = $false

# Check Unreal / BioWare Package magic: 0x9E2A83C1 (C1 83 2A 9E)
$hasUnrealPackageMagic = ($len -ge 4 -and $bytes[0] -eq 0xC1 -and $bytes[1] -eq 0x83 -and $bytes[2] -eq 0x2A -and $bytes[3] -eq 0x9E)
$decompressedPayload = $null

if ($hasUnrealPackageMagic) {
    $decompressedPayload = Try-DecompressZlib $bytes 34
} elseif ($len -gt 10 -and $bytes[0] -eq 0x78 -and ($bytes[1] -eq 0x9C -or $bytes[1] -eq 0x01 -or $bytes[1] -eq 0xDA)) {
    $decompressedPayload = Try-DecompressZlib $bytes 2
}

# ==============================================================================
# 1. PRAVAHA SŪKSHMA REKHA & AGAMA DETERMINISTIC PROFILE ENGINE
# Deterministic parsing logic is loaded for recognized games (e.g. Suzerain).
# Base Game Sordland (Anton Rayne) & Rizia DLC (King Romus Toras) campaigns supported.
# Raw mode allows search and editing of all 300+ variables.
# ==============================================================================

$isDeterministicProfile = $false
$gameTitle = "$filename (Pravaha Sukshma Rekha // Fine Line Overseer)"

if ($isJson) {
    try {
        $jsonContent = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $parsed = ConvertFrom-Json $jsonContent -ErrorAction Stop

        $isSuzerain = ($parsed.currentStoryPack -ne $null -or ($jsonContent -match 'Variable=\{\[\"'))

        if ($isSuzerain) {
            $isRizia = ($parsed.currentStoryPack -eq "StoryPack_Rizia" -or $parsed.campaignName -eq "NG1")
            $campaignTitle = if ($isRizia) { "Rizia DLC (King Romus Toras)" } else { "Base Game Sordland (President Anton Rayne)" }
            $gameTitle = "SUZERAIN // $campaignTitle (Torpor Agama // प्रमाण आगम)"
            $verdict = "Torpor Games Save Vessel ($($parsed.currentStoryPack))"
            $isDeterministicProfile = $true

            # Extract all variables from embedded string
            $suzerainVars = @{}
            if ($parsed.variables) {
                $kvMatches = [System.Text.RegularExpressions.Regex]::Matches($parsed.variables, '\[\"(?<k>[\w\._-]+)\"\]\s*=\s*(?<v>[\w\.-]+|true|false)')
                foreach ($m in $kvMatches) {
                    $suzerainVars[$m.Groups["k"].Value] = $m.Groups["v"].Value
                }
            }

            # Add top-level JSON metadata
            $rows.Add([PSCustomObject]@{ offset = "METADATA: turnNo"; key = "turnNo"; type = "i32 (Turn)"; conf = "96% Root Value"; hex = "22 3A 22 20"; val = "$($parsed.turnNo)" })
            $rows.Add([PSCustomObject]@{ offset = "METADATA: currentStoryPack"; key = "currentStoryPack"; type = "String"; conf = "96% Root Value"; hex = "22 53 54 52"; val = "$($parsed.currentStoryPack)" })
            $rows.Add([PSCustomObject]@{ offset = "METADATA: campaignName"; key = "campaignName"; type = "String"; conf = "96% Root Value"; hex = "22 53 54 52"; val = "$($parsed.campaignName)" })
            $rows.Add([PSCustomObject]@{ offset = "METADATA: version"; key = "version"; type = "String"; conf = "96% Root Value"; hex = "22 53 54 52"; val = "$($parsed.version)" })

            # Curated campaign rules matching D:\Projects\Suzerain-save-editor
            $curatedRules = if ($isRizia) {
                @(
                    @{ key="RiziaDLC.Resources_Budget"; label="Royal Budget (Max 25)"; type="i32 (Economy)"; cat="ECONOMY" },
                    @{ key="RiziaDLC.Resources_Authority"; label="Royal Authority (Max 15)"; type="i32 (Authority)"; cat="ECONOMY" },
                    @{ key="RiziaDLC.Resources_Energy"; label="Energy Reserves (Max 25)"; type="i32 (Energy)"; cat="ECONOMY" },
                    @{ key="RiziaDLC.Budget_Modifier_IncomeTax"; label="Income Tax Modifier"; type="i32 (Modifier)"; cat="ECONOMY" },
                    @{ key="RiziaDLC.Energy_Modifier_BaseEnergy"; label="Base Energy Modifier"; type="i32 (Modifier)"; cat="ECONOMY" },
                    @{ key="RiziaDLC.Authority_Modifier_BaseMonarchRomus"; label="Monarch Authority Modifier"; type="i32 (Modifier)"; cat="ECONOMY" },

                    @{ key="RiziaDLC.Army_Unit_Infantry_Total"; label="Infantry Units Total"; type="i32 (Units)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Army_Unit_Tank_Total"; label="Tank Units Total"; type="i32 (Units)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Army_Unit_Submarine_Total"; label="Submarine Fleet Total"; type="i32 (Units)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Army_Unit_Support_Total"; label="Support Units Total"; type="i32 (Units)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Army_Unit_Ship_Total"; label="Capital Ships Total"; type="i32 (Units)"; cat="MILITARY" },

                    @{ key="RiziaDLC.Resources_Military_Trucks"; label="Trucks Stockpile"; type="i32 (Stockpile)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Resources_Military_Ships"; label="Ships Stockpile"; type="i32 (Stockpile)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Resources_Military_Tanks"; label="Tanks Stockpile"; type="i32 (Stockpile)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Resources_Military_Submarines"; label="Submarines Stockpile"; type="i32 (Stockpile)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Resources_Military_Manpower"; label="Manpower Reserve"; type="i32 (Stockpile)"; cat="MILITARY" },
                    @{ key="RiziaDLC.Resources_Military_Equipment"; label="Equipment Stockpile"; type="i32 (Stockpile)"; cat="MILITARY" },

                    @{ key="RiziaDLC.War_ActionPoints"; label="War Action Points (Unlimited AP)"; type="i32 (War)"; cat="WAR" },
                    @{ key="RiziaDLC.Resources_Military_AirStrikeRefillPerFragment"; label="Air Strike Refill per Fragment"; type="i32 (War)"; cat="WAR" },
                    @{ key="RiziaDLC.War_Pales_PublicWarSupport"; label="Pales War Public Support"; type="i32 (War)"; cat="WAR" },

                    @{ key="RiziaDLC.Country_ProductionCapacity"; label="Production Capacity"; type="i32 (Welfare)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_LivingStandards"; label="Living Standards"; type="i32 (Welfare)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_PublicOpinion"; label="Public Opinion (Rizia)"; type="i32 (Opinion)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_HouseToras"; label="House Toras Standing"; type="i32 (Houses)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_HouseSazon"; label="House Sazon Standing"; type="i32 (Houses)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_HouseAzaro"; label="House Azaro Standing"; type="i32 (Houses)"; cat="POLITICS" },

                    @{ key="RiziaDLC.Country_GolcondistOpinion"; label="Golcondist Religion Opinion"; type="i32 (Religion)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_WruhecistOpinion"; label="Wruhecist Religion Opinion"; type="i32 (Religion)"; cat="POLITICS" },
                    @{ key="RiziaDLC.Country_DastnuristOpinion"; label="Dastnurist Religion Opinion"; type="i32 (Religion)"; cat="POLITICS" },

                    @{ key="RiziaDLC.Diplomacy_Derdia_NegotiatingPower"; label="Derdia Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Morella_NegotiatingPower"; label="Morella Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Sordland_NegotiatingPower"; label="Sordland Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Zille_ReferendumPower"; label="Zille Referendum Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Lespia_NegotiatingPower"; label="Lespia Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.CountryRelation_Lespia_Friendly"; label="Lespia Friendly Relation"; type="bool (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Valgsland_NegotiatingPower"; label="Valgsland Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Pales_NegotiatingPower"; label="Pales Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Rumburg_NegotiatingPower"; label="Rumburg Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },
                    @{ key="RiziaDLC.Diplomacy_Wehlen_NegotiatingPower"; label="Wehlen Negotiating Power"; type="i32 (Diplomacy)"; cat="DIPLOMACY" },

                    @{ key="RiziaDLC.Relations_Sal"; label="Arch-Priest Sal Relation"; type="i32 (Council)"; cat="RELATIONS" },
                    @{ key="RiziaDLC.Relations_Vina"; label="Princess Vina Relation"; type="i32 (Council)"; cat="RELATIONS" },
                    @{ key="RiziaDLC.Relations_Estela"; label="Queen Mother Estela Relation"; type="i32 (Council)"; cat="RELATIONS" },
                    @{ key="RiziaDLC.Relations_Pabel"; label="Pabel Relation"; type="i32 (Council)"; cat="RELATIONS" },
                    @{ key="RiziaDLC.Relations_Hugo"; label="Uncle Hugo Relation"; type="i32 (Council)"; cat="RELATIONS" },
                    @{ key="RiziaDLC.Relations_Lucita_Romance"; label="Lucita Romance (Max 3)"; type="i32 (Council)"; cat="RELATIONS" }
                )
            } else {
                @(
                    @{ key="BaseGame.GovernmentBudget"; label="Government Budget (Warn > 3 Turn < 4)"; type="i32 (Budget)"; cat="ECONOMY" },
                    @{ key="BaseGame.PersonalWealth"; label="Personal Wealth (Rayne's Pockets)"; type="i32 (Wealth)"; cat="ECONOMY" },
                    @{ key="BaseGame.Country_Unrest"; label="Country Unrest"; type="i32 (Unrest)"; cat="POLITICS" },
                    @{ key="BaseGame.Public_Opinion"; label="Public Opinion"; type="i32 (Opinion)"; cat="POLITICS" },
                    @{ key="BaseGame.Bludish_Opinion"; label="Bludish Opinion"; type="i32 (Opinion)"; cat="POLITICS" },
                    @{ key="Game.Turn"; label="Game Turn"; type="i32 (Turn)"; cat="CORE" },

                    @{ key="BaseGame.BlackTuesdayHappened"; label="Black Tuesday Happened"; type="bool (Event)"; cat="EVENTS" },
                    @{ key="Game.IsMarketCrashing"; label="Is Market Crashing"; type="bool (Event)"; cat="EVENTS" },

                    @{ key="BaseGame.Reform_Assembly_Vote"; label="Reform Assembly Vote"; type="i32 (Vote)"; cat="POLITICS" },
                    @{ key="BaseGame.Reform_Court_Vote"; label="Reform Supreme Court Vote"; type="i32 (Vote)"; cat="POLITICS" },
                    @{ key="Albin_Convinced"; label="Albin Convinced"; type="bool (Convinced)"; cat="POLITICS" },
                    @{ key="Gloria_Convinced"; label="Gloria Convinced"; type="bool (Convinced)"; cat="POLITICS" },
                    @{ key="GameCondition.Turn04_A_Convince_Gloria"; label="Turn 4 Convince Gloria"; type="bool (Convinced)"; cat="POLITICS" },
                    @{ key="GameCondition.Turn04_A_Convince_Albin"; label="Turn 4 Convince Albin"; type="bool (Convinced)"; cat="POLITICS" },
                    @{ key="BaseGame.Amendment_USP_Gloria_Convinced"; label="USP Gloria Convinced (Art 6&7)"; type="bool (Convinced)"; cat="POLITICS" },
                    @{ key="BaseGame.Faction_USP_AgainstProposal"; label="USP Against Proposal"; type="bool (Faction)"; cat="POLITICS" },

                    @{ key="BaseGame.Economy_Agnland"; label="Agnland Economy (15=Recovered)"; type="i32 (Region)"; cat="ECONOMY" },
                    @{ key="BaseGame.Economy_Bergia"; label="Bergia Economy (15=Recovered)"; type="i32 (Region)"; cat="ECONOMY" },
                    @{ key="BaseGame.Economy_Lorren"; label="Lorren Economy (15=Recovered)"; type="i32 (Region)"; cat="ECONOMY" },
                    @{ key="BaseGame.Economy_Gruni"; label="Gruni Economy (15=Recovered)"; type="i32 (Region)"; cat="ECONOMY" },
                    @{ key="BaseGame.TradeAmount"; label="Trade Amount Modifier"; type="i32 (Trade)"; cat="ECONOMY" },

                    @{ key="BaseGame.Relations_Franc_Opinion"; label="Franc Opinion"; type="i32 (Relations)"; cat="RELATIONS" },
                    @{ key="BaseGame.Relations_Monica_Opinion"; label="Monica Opinion"; type="i32 (Relations)"; cat="RELATIONS" },
                    @{ key="BaseGame.Relations_Lucian_Opinion"; label="Lucian Opinion"; type="i32 (Relations)"; cat="RELATIONS" },
                    @{ key="BaseGame.Prologue_Studyplace_Deyr_History"; label="Study: Deyr History"; type="bool (Study)"; cat="RELATIONS" },
                    @{ key="BaseGame.Prologue_Studyplace_Holsord_Law"; label="Study: Holsord Law"; type="bool (Study)"; cat="RELATIONS" },
                    @{ key="BaseGame.Prologue_Studyplace_Lachaven_Economics"; label="Study: Lachaven Economics"; type="bool (Study)"; cat="RELATIONS" },
                    @{ key="BaseGame.LeakedScandals_Severity"; label="Leaked Scandals Severity (0=None)"; type="i32 (Scandal)"; cat="RELATIONS" },
                    @{ key="BaseGameIsolated.Turn09_A_TelevisionInterview_International_Empathy_Gained"; label="TV Interview Empathy Gained"; type="bool (Sanctions)"; cat="RELATIONS" },

                    @{ key="BaseGame.Turn06_SnO_Expansion_Army"; label="Expanded Army (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ExpandedArmy"; label="Expanded Army (Situation Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Turn06_SnO_Expansion_Navy"; label="Expanded Navy (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ExpandedNavy"; label="Expanded Navy (Situation Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Turn06_SnO_Expansion_Airforce"; label="Expanded Air Force (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ExpandedAirForce"; label="Expanded Air Force (Situation Flag)"; type="bool (Military)"; cat="MILITARY" },

                    @{ key="BaseGame.Turn06_SnO_Modernisation_Army"; label="Modernised Army (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ModernisedArmy"; label="Modernised Army (Situation Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Turn06_SnO_Modernisation_Navy"; label="Modernised Navy (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ModernisedNavy"; label="Modernised Navy (Situation Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Turn06_SnO_Modernisation_Airforce"; label="Modernised Air Force (Turn 6 Flag)"; type="bool (Military)"; cat="MILITARY" },
                    @{ key="BaseGame.Situation_Military_ModernisedAirForce"; label="Modernised Air Force (Situation Flag)"; type="bool (Military)"; cat="MILITARY" }
                )
            }

            # Add curated campaign variables FIRST (100% Curated Agama confidence)
            $curatedKeySet = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($rule in $curatedRules) {
                $curatedKeySet.Add($rule.key) | Out-Null
                $val = if ($suzerainVars.ContainsKey($rule.key)) { $suzerainVars[$rule.key] } else { "(unset)" }
                $hexStr = if ($val -eq "true") { "01 00 00 00" } elseif ($val -eq "false") { "00 00 00 00" } else { "41 47 41 4D" }
                $rows.Add([PSCustomObject]@{
                    offset = "AGAMA: $($rule.cat)"
                    key = "$($rule.label) [$($rule.key)]"
                    type = $rule.type
                    conf = "100% Curated Agama"
                    hex = $hexStr
                    val = "$val"
                })
            }

            # Follow with all remaining variables for Raw Editor mode
            $sortedSuzerainKeys = $suzerainVars.Keys | Sort-Object
            foreach ($k in $sortedSuzerainKeys) {
                if ($rows.Count -ge 350) { break }
                if ($curatedKeySet.Contains($k)) { continue }
                $v = $suzerainVars[$k]
                $itemType = "String (Embedded)"
                $itemHex = "45 4D 42 44"
                if ($v -eq "true" -or $v -eq "false") {
                    $itemType = "bool (State Flag)"
                    $itemHex = if ($v -eq "true") { "01 00 00 00" } else { "00 00 00 00" }
                } elseif ($v -match '^-?\d+$') {
                    $itemType = "i32 (Raw Variable)"
                    $itemHex = "4E 55 4D 31"
                } elseif ($v -match '^-?\d+\.\d+$') {
                    $itemType = "f64 (Raw Variable)"
                    $itemHex = "46 4C 54 31"
                }
                $rows.Add([PSCustomObject]@{
                    offset = "RAW: " + $k
                    key = $k
                    type = $itemType
                    conf = "80% Raw Save Variable"
                    hex = $itemHex
                    val = $v
                })
            }
        } else {
            $verdict = "Structured JSON Vessel"

            # Universal JSON Walker: extracts nested properties AND embedded serialized K-Vs
            function Walk-GenericJson($obj, $prefix, $depth) {
                if ($depth -gt 6 -or $rows.Count -ge 300) { return }
                $props = @()
                if ($obj -is [PSCustomObject]) {
                    $props = $obj.PSObject.Properties
                } elseif ($obj -is [System.Collections.IDictionary]) {
                    $props = $obj.GetEnumerator()
                }

                foreach ($p in $props) {
                    if ($rows.Count -ge 300) { break }
                    $k = if ($p.Name) { $p.Name } else { $p.Key }
                    $v = if ($p.Name) { $p.Value } else { $p.Value }
                    $fullKey = if ($prefix) { "$prefix.$k" } else { "$k" }

                    if ($v -is [PSCustomObject] -or $v -is [System.Collections.IDictionary]) {
                        Walk-GenericJson $v $fullKey ($depth + 1)
                    } elseif ($v -is [Array]) {
                        $rows.Add([PSCustomObject]@{
                            offset = "JSON: $fullKey"
                            key = "$fullKey [Array]"
                            type = "Array[$($v.Count)]"
                            conf = "85% Array Collection"
                            hex = "5B 5D 20 20"
                            val = (ConvertTo-Json -Compress $v)
                        })
                    } elseif ($v -is [string]) {
                        $strVal = [string]$v
                        if ($strVal.Length -gt 20 -and ($strVal -match '\[\".+\"\]\s*=' -or $strVal -match '[A-Za-z0-9_.\-]+[:=][A-Za-z0-9_.\-]+')) {
                            $kvMatches = [System.Text.RegularExpressions.Regex]::Matches($strVal, '\[\"?([A-Za-z0-9_.\-]+)\"?\]\s*=\s*([^,\r\n\}\]]+)')
                            if ($kvMatches.Count -gt 0) {
                                foreach ($m in $kvMatches) {
                                    if ($rows.Count -ge 300) { break }
                                    $rawK = $m.Groups[1].Value.Trim()
                                    $rawV = $m.Groups[2].Value.Trim()
                                    
                                    $itemType = "String (Embedded)"
                                    $itemConf = "70% Embedded Metric"
                                    $itemHex = "45 4D 42 44"
                                    if ($rawV -eq "true" -or $rawV -eq "false") {
                                        $itemType = "bool (State Flag)"
                                        $itemConf = "82% Embedded Flag"
                                        $itemHex = if ($rawV -eq "true") { "01 00 00 00" } else { "00 00 00 00" }
                                    } elseif ($rawV -match '^-?\d+$') {
                                        $itemType = "i32 (Embedded Number)"
                                        $itemConf = "88% Numeric Stat"
                                        $itemHex = "4E 55 4D 31"
                                    } elseif ($rawV -match '^-?\d+\.\d+$') {
                                        $itemType = "f64 (Embedded Float)"
                                        $itemConf = "84% Float Stat"
                                        $itemHex = "46 4C 54 31"
                                    }
                                    $rows.Add([PSCustomObject]@{
                                        offset = "EMBED: " + $rawK
                                        key = $rawK
                                        type = $itemType
                                        conf = $itemConf
                                        hex = $itemHex
                                        val = $rawV
                                    })
                                }
                            } else {
                                $rows.Add([PSCustomObject]@{
                                    offset = "JSON: $fullKey"
                                    key = "$fullKey"
                                    type = "String"
                                    conf = if ($depth -eq 0) { "95% Root String" } else { "75% String Identifier" }
                                    hex = "22 53 54 52"
                                    val = if ($strVal.Length -gt 120) { $strVal.Substring(0, 117) + "..." } else { $strVal }
                                })
                            }
                        } else {
                            $rows.Add([PSCustomObject]@{
                                offset = "JSON: $fullKey"
                                key = "$fullKey"
                                type = "String"
                                conf = if ($depth -eq 0) { "95% Root String" } else { "80% Property String" }
                                hex = "22 53 54 52"
                                val = "$v"
                            })
                        }
                    } else {
                        $tStr = if ($v -is [int] -or $v -is [long]) { "i32 (Integer)" } elseif ($v -is [double] -or $v -is [float]) { "f64 (Float)" } elseif ($v -is [bool]) { "bool" } else { "Scalar" }
                        $cStr = if ($depth -eq 0) { "96% Root Value" } elseif ($depth -eq 1) { "90% Nested Metric" } else { "78% Deep Value" }
                        $hexVal = if ($v -is [bool]) { if ($v) { "01 00 00 00" } else { "00 00 00 00" } } else { "22 3A 22 20" }
                        $rows.Add([PSCustomObject]@{
                            offset = "JSON: $fullKey"
                            key = "$fullKey"
                            type = $tStr
                            conf = $cStr
                            hex = $hexVal
                            val = "$v"
                        })
                    }
                }
            }

            Walk-GenericJson $parsed "" 0
        }
    } catch {
        Write-Warning "JSON parse error: $_"
    }
} else {
    $verdict = if ($decompressedPayload) { "Deflate Container Vessel ($($decompressedPayload.Length) Bytes Decompressed)" } else { "Binary Byte Stream ($len Bytes)" }
}

# Determine scan target: use decompressed payload if present (e.g. zlib containers), else raw bytes
$scanBuf = if ($decompressedPayload) { $decompressedPayload } else { $bytes }
$scanPrefix = if ($decompressedPayload) { "PAYLOAD" } else { "0x" }

if (-not $isJson -and $rows.Count -lt 250) {
    $cursor = 0
    $lastIdent = ""

    while ($cursor + 4 -le $scanBuf.Length -and $rows.Count -lt 250) {
        # Check for null padding runs: skip contiguous blocks of zeros (direct .NET read)
        $u32AtCursor = [System.BitConverter]::ToUInt32($scanBuf, $cursor)
        if ($u32AtCursor -eq 0) {
            $cursor += 4
            while ($cursor + 4 -le $scanBuf.Length -and ([System.BitConverter]::ToUInt32($scanBuf, $cursor)) -eq 0) {
                $cursor += 4
            }
            $lastIdent = ""
            continue
        }

        # Check Pascal Length-Prefixed String: [u32 len: 3..48] [ASCII chars]
        if ($cursor + 8 -le $scanBuf.Length -and $u32AtCursor -ge 3 -and $u32AtCursor -le 48 -and ($cursor + 4 + $u32AtCursor -le $scanBuf.Length)) {
            $candidateStr = [System.Text.Encoding]::ASCII.GetString($scanBuf, $cursor + 4, $u32AtCursor)
            if ($candidateStr -match '^[A-Za-z0-9_.\- ]{3,48}$') {
                $offLabel = if ($scanPrefix -eq "PAYLOAD") { "PAYLOAD[0x{0:X4}]" -f $cursor } else { "0x{0:X4}" -f $cursor }
                $cleanIdent = $candidateStr.Trim()
                $rows.Add([PSCustomObject]@{
                    offset = $offLabel
                    key = $cleanIdent
                    type = "String (Pascal Identifier)"
                    conf = "94% Named Anchor"
                    hex = (Get-Hex ($cursor + 4) ([Math]::Min(4, $u32AtCursor)) $scanBuf)
                    val = "'$cleanIdent'"
                })
                $lastIdent = $cleanIdent
                $cursor += (4 + $u32AtCursor)
                continue
            }
        }

        # Check Null-Terminated ASCII String (fast pre-check for letter/underscore byte)
        $b0 = $scanBuf[$cursor]
        if (($b0 -ge 65 -and $b0 -le 90) -or ($b0 -ge 97 -and $b0 -le 122) -or $b0 -eq 95) {
            $asciiTag = Get-Ascii $cursor 16 $scanBuf
            if ($asciiTag.Length -ge 3 -and $asciiTag -match '^[A-Za-z0-9_]{3,16}$') {
                $offLabel = if ($scanPrefix -eq "PAYLOAD") { "PAYLOAD[0x{0:X4}]" -f $cursor } else { "0x{0:X4}" -f $cursor }
                $rows.Add([PSCustomObject]@{
                    offset = $offLabel
                    key = $asciiTag
                    type = "ASCII Tag / Keyword"
                    conf = "90% Identifier"
                    hex = (Get-Hex $cursor 4 $scanBuf)
                    val = "'$asciiTag'"
                })
                $lastIdent = $asciiTag
                $cursor += [Math]::Max(4, $asciiTag.Length + 1)
                continue
            }
        }

        # Fine Line Scalar Evaluation (direct inline reading)
        $u32 = $u32AtCursor

        # Fast rejection of garbage words (nulls, uninitialized MSVC fills, byte repeats, etc.)
        if (Test-GarbageWord $u32) {
            $cursor += 4
            $lastIdent = ""
            continue
        }

        $v32 = [System.BitConverter]::ToInt32($scanBuf, $cursor)
        $rawSingle = [System.BitConverter]::ToSingle($scanBuf, $cursor)
        $f32 = if ([Single]::IsNaN($rawSingle) -or [Single]::IsInfinity($rawSingle)) { 0.0 } else { [Math]::Round($rawSingle, 2) }
        $hex = Get-Hex $cursor 4 $scanBuf
        $offLabel = if ($scanPrefix -eq "PAYLOAD") { "PAYLOAD[0x{0:X4}]" -f $cursor } else { "0x{0:X4}" -f $cursor }

        # 1. Identifier-Associated Value
        if ($lastIdent) {
            if (Test-PlausibleFloatFromBits $u32 $f32) {
                $rows.Add([PSCustomObject]@{
                    offset = $offLabel
                    key = "$lastIdent [Float]"
                    type = "f32 (Associated Float)"
                    conf = "94% Named Metric"
                    hex = $hex
                    val = "$f32"
                })
                $cursor += 4
                $lastIdent = ""
                continue
            } elseif ($v32 -ge 0 -and $v32 -le 50000000) {
                $suffix = if ($v32 -eq 0 -or $v32 -eq 1) { "[Flag]" } else { "[Val]" }
                $rows.Add([PSCustomObject]@{
                    offset = $offLabel
                    key = "$lastIdent $suffix"
                    type = "i32 (Associated Value)"
                    conf = "94% Named Metric"
                    hex = $hex
                    val = "$v32"
                })
                $cursor += 4
                $lastIdent = ""
                continue
            }
        }

        # 2. Plausible Float (f32)
        if (Test-PlausibleFloatFromBits $u32 $f32) {
            $rows.Add([PSCustomObject]@{
                offset = $offLabel
                key = "FLOAT [0x{0:X4}]" -f $cursor
                type = "f32 (Coord/Timer/Stat)"
                conf = "75% Heuristic Float"
                hex = $hex
                val = "$f32"
            })
            $cursor += 4
            $lastIdent = ""
            continue
        }

        # 3. Epoch Timestamps
        if ($u32 -ge 1000000000 -and $u32 -le 2100000000) {
            $rows.Add([PSCustomObject]@{
                offset = $offLabel
                key = "TIMESTAMP [0x{0:X4}]" -f $cursor
                type = "u32 (Epoch Seconds)"
                conf = "90% Probable Timestamp"
                hex = $hex
                val = "$u32"
            })
            $cursor += 4
            $lastIdent = ""
            continue
        }

        # 4. Plausible Gameplay Resources (Currency, XP, Score)
        if ($v32 -ge 100 -and $v32 -le 50000000) {
            $rows.Add([PSCustomObject]@{
                offset = $offLabel
                key = "RESOURCE [0x{0:X4}]" -f $cursor
                type = "i32 (Probable Currency/XP)"
                conf = "85% Game Resource"
                hex = $hex
                val = "$v32"
            })
            $cursor += 4
            $lastIdent = ""
            continue
        }

        # 5. Plausible Level or Stat Counter (1 to 255)
        if ($v32 -ge 1 -and $v32 -le 255) {
            $rows.Add([PSCustomObject]@{
                offset = $offLabel
                key = "STAT_OR_LEVEL [0x{0:X4}]" -f $cursor
                type = "i32 (Attribute / Level)"
                conf = "80% Player Attribute"
                hex = $hex
                val = "$v32"
            })
            $cursor += 4
            $lastIdent = ""
            continue
        }

        # 6. Clean Unclassified Dword (Fine Line Lower-Confidence Candidate)
        # Passed garbage filter, non-padding. Meaningful offset and word value.
        $rows.Add([PSCustomObject]@{
            offset = $offLabel
            key = "VAR_0x{0:X4}" -f $cursor
            type = "u32 (Raw Word)"
            conf = "50% Candidate Variable"
            hex = $hex
            val = "$v32 (0x{0:X8})" -f $u32
        })

        $cursor += 4
        $lastIdent = ""
    }
}

# ==============================================================================
# 3. RANK ALL EXTRACTED ROWS BY CONFIDENCE RATING IN DESCENDING ORDER
# Ensures highest confidence & deterministic fields are at the top of scrollable list,
# followed by high/medium heuristics, down to lower confidence unclassified variables.
# ==============================================================================
function Get-ConfidenceScore($confStr) {
    if ($confStr -match '(\d+)%') {
        return [int]$Matches[1]
    }
    return 50
}

$sortedRows = $rows | Sort-Object -Descending { Get-ConfidenceScore $_.conf }, { $_.offset }
$rows = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($item in $sortedRows) {
    $rows.Add($item)
}

$totalExtracted = $rows.Count
Write-Host "[OK] Extracted $totalExtracted key-values from $filename via Fine Line Engine (Ranked by confidence descending)"

# Helper for Slint string escaping
function Escape-Slint($str) {
    if (-not $str) { return "" }
    return ([string]$str).Replace('\', '\\').Replace('"', '\"')
}

$q = '"'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("// Auto-generated by Sharabha Sthiti Pariksha Engine")
$lines.Add("export struct SaveKeyValueRowData {")
$lines.Add("    offset: string,")
$lines.Add("    key: string,")
$lines.Add("    type_name: string,")
$lines.Add("    conf: string,")
$lines.Add("    hex: string,")
$lines.Add("    val: string,")
$lines.Add("}")
$lines.Add("")
$lines.Add("export global LiveSave {")
$lines.Add("    in property <int> active_tab_hint: 1;")
$lines.Add("    in property <bool> skip_splash_hint: true;")
$lines.Add("    in property <bool> is_deterministic_profile: $($isDeterministicProfile.ToString().ToLower());")
$lines.Add("    in property <string> filename: ${q}$(Escape-Slint $filename)${q};")
$lines.Add("    in property <string> game_title: ${q}$(Escape-Slint $gameTitle)${q};")
$lines.Add("    in property <string> checksum_info: ${q}Sthiti Raksha: MD5 Seal Active [${md5Str}]${q};")
$lines.Add("    in property <string> metric_verdict: ${q}$(Escape-Slint $verdict)${q};")
$lines.Add("    in property <string> metric_score: ${q}${len} Bytes Analyzed${q};")
$lines.Add("    in property <string> status_feedback: ${q}Loaded: $(Escape-Slint $filename) (${len} Bytes, ${totalExtracted} Key-Values, Ranked by Confidence Descending)${q};")
$lines.Add("    in property <int> total_extracted_count: ${totalExtracted};")
$lines.Add("")
$lines.Add("    in property <[SaveKeyValueRowData]> rows: [")

for ($i = 0; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    $o = Escape-Slint $r.offset
    $k = Escape-Slint $r.key
    $t = Escape-Slint $r.type
    $c = Escape-Slint $r.conf
    $h = Escape-Slint $r.hex
    $v = Escape-Slint $r.val
    $comma = if ($i -lt $rows.Count - 1) { "," } else { "" }
    $lines.Add("        { offset: ${q}${o}${q}, key: ${q}${k}${q}, type_name: ${q}${t}${q}, conf: ${q}${c}${q}, hex: ${q}${h}${q}, val: ${q}${v}${q} }${comma}")
}
$lines.Add("    ];")
$lines.Add("")

# Legacy backwards-compatible scalar row properties (rows 0 to 9)
for ($i = 0; $i -lt 10; $i++) {
    $o = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].offset } else { "" }
    $k = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].key } else { "" }
    $t = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].type } else { "" }
    $c = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].conf } else { "" }
    $h = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].hex } else { "" }
    $v = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].val } else { "" }
    $lines.Add("    in property <string> row_${i}_offset: ${q}${o}${q};")
    $lines.Add("    in property <string> row_${i}_key: ${q}${k}${q};")
    $lines.Add("    in property <string> row_${i}_type: ${q}${t}${q};")
    $lines.Add("    in property <string> row_${i}_conf: ${q}${c}${q};")
    $lines.Add("    in property <string> row_${i}_hex: ${q}${h}${q};")
    $lines.Add("    in property <string> row_${i}_val: ${q}${v}${q};")
}

# Legacy field aliases (fields 0 to 3)
for ($i = 0; $i -lt 4; $i++) {
    $k = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].key } else { "" }
    $t = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].type } else { "" }
    $h = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].hex } else { "" }
    $v = if ($i -lt $rows.Count) { Escape-Slint $rows[$i].val } else { "" }
    $lines.Add("    in property <string> field_${i}_tag: ${q}${k}${q};")
    $lines.Add("    in property <string> field_${i}_type: ${q}${t}${q};")
    $lines.Add("    in property <string> field_${i}_hex: ${q}${h}${q};")
    $lines.Add("    in property <string> field_${i}_val: ${q}${v}${q};")
}

$lines.Add("}")

$targetPath = Join-Path $projectDir "src\ui\live_save.slint"
$content = [string]::Join("`r`n", $lines)
[System.IO.File]::WriteAllText($targetPath, $content, (New-Object System.Text.UTF8Encoding $true))
Write-Host "[OK] LiveSave updated: $targetPath ($totalExtracted Key-Values Extracted, Ranked by Confidence)"

# Touch src\ui\app.slint to trigger slint-viewer --auto-reload file watcher
$appSlint = Join-Path $projectDir "src\ui\app.slint"
if (Test-Path $appSlint) {
    (Get-Item $appSlint).LastWriteTime = Get-Date
    Write-Host "[OK] Slint Viewer watcher signaled via app.slint touch"
}
