# Changelog

All notable changes to the **Sharabha (शरभेश्वर) — The Dual Aspect Engine** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.5.0] - 2026-11-04

### Added
- **Universal Unreal Engine 4/5 Save Parser ("माया सूत्र // Maya Sutra")**:
  - High-performance, zero-allocation binary parser and typed serializer (`src/save/gvas.zig`) for Unreal Engine 4 and 5 `.sav` files based on the `GVAS` container format.
  - Implemented complete GVAS header extraction: `save_game_version`, `package_version`, `engine_version` (major/minor/patch/build/branch), `custom_version_format`, `custom_versions` GUID table, and `save_game_class`.
  - Built-in type-safe property tree parser supporting `IntProperty`, `Int64Property`, `FloatProperty`, `DoubleProperty`, `BoolProperty`, `StrProperty`, `NameProperty`, `EnumProperty`, `StructProperty`, and typed `ArrayProperty`.
  - Type-safe mutation helpers (`setInt`, `setFloat`, `setBool`, `setString`) and binary repacker (`serializeGvas`) preserving metadata integrity and package hashes.
  - Atomic CLI mutation: `--write-save-kv` dynamically auto-detects `GVAS` magic headers and performs in-place mutation, automatic `.sharabha.bak` prana backup creation, and shadow temp-file swap.
  - Interactive UI integration: `tools/open_dialog.ps1` extracts all GVAS properties into Kalyana Sthiti (`src/ui/live_save.slint`) with 100% Curated Maya Sutra confidence and reactive mutation controls.
- **Visual Save Diff & Evolution Inspector ("काल चक्र // Kala Chakra")**:
  - High-throughput differential comparison engine (`src/save/diff.zig`) with 4-byte aligned scalar clustering for raw binary saves and recursive property trees for GVAS container saves.
  - Added `tools/diff_saves.ps1` supporting 1-click comparison of active save against automatic `.sharabha.bak` prana backup or an arbitrary historical save via OpenFileDialog.
  - Dynamic UI view in Kalyana Sthiti (`[KALA CHAKRA SAVE DIFF]` sub-tab):
    - Displays mutated offset/key, before/after values, signed delta (`+` / `-`), hex previews, and mutation status badges.
    - 1-click promotion to active editor (`PROMOTE TO FORGE`).
- **Hardware Breakpoints & "Find What Writes" Watcher ("नेत्र दृष्टान्त // Netra Drishtanta")**:
  - Implemented CPU hardware debug register interception (`src/memory/breakpoint.zig`) utilizing x86_64 Win32 debug registers `DR0`–`DR3` and control register `DR7` for non-invasive write watchpoints.
  - Captured full 64-bit CPU architectural register dump (`RAX, RBX, RCX, RDX, RSI, RDI, RSP, RBP, R8-R15`, `EFLAGS`) alongside instruction pointer (`RIP`), opcode disassembly, and real-time hit counts.
  - Added CLI command `--watch-writes <addr> [timeout_ms]` for live memory write interception and debugging.
  - Added interactive Layer 9 modal in `src/ui/app.slint` (`LiveNetra` global) featuring split-pane instruction hit list, disassembly, opcode view, and 16-register CPU state grid.
  - Connected `FIND WHAT WRITES` (`नेत्र`) buttons across memory scanner rows in Rudra Tandava to immediately open Netra Drishtanta on candidate addresses.

---

## [0.4.1] - 2026-11-04

### Added
- **Ashtamurti Auto-Updater Engine ("अद्यतन संशुद्धि // Ashtamurti Auto-Updater")**:
  - Implemented GitHub release synchronization engine (`tools/updater.ps1`) querying official temple releases via GitHub Releases REST API with automated version comparison.
  - Added interactive thematic modal dialog in `src/ui/app.slint` featuring a full Markdown changelog reader, version comparison badges, release metadata, and dual-aspect Shaivite gradient progress bar (`#ff4d2e` crimson to `#ca8a04` gold to `#38bdf8` cyan).
  - Streamed chunked binary download directly into user temporary staging (`%TEMP%\Sharabha-Update\Sharabha-vX.Y.Z-windows-x64-setup.exe`) with real-time byte count and percentage tracking.
  - Automated seamless handover: spawns the new self-extracting installer detached and gracefully closes the running application to avoid DLL or file-lock collisions.
  - Integrated `UPDATE` (`अद्यतन चक्र`) quick-trigger button in the main application header and registered `Check for Updates` in the Universal Command Palette (`Ctrl + P`).

### Fixed
- **Post-Install "Launch Now" Action Handover ("प्रतिष्ठापनोपरान्त उद्बोधन // Pratishthanoparanta Udbodhana")**:
  - Resolved an issue where selecting "Launch Sharabha now upon exit" on the post-install completion screen failed to launch the application.
  - Eliminated premature background process spawning in `tools/installer_logic.ps1` during file copying, transferring launch responsibility strictly to the post-installation completion hook in `tools/installer_finish.ps1`.
  - Implemented process parent PID detection so closing the installer terminates only the installer's viewer process, preventing collateral termination of the newly launched application window.
  - Added `tools/installer_cancel.ps1` for clean, isolated exit when cancelling the installer.

### Changed
- **Zero-Console Process Cloaking ("निराकार प्रक्रिया आवरण // Nirakara Prakriya Avarana")**:
  - Suppressed all black terminal/console windows and command prompt flashes during application startup and setup wizard launch.
  - Configured `win.CREATE_NO_WINDOW` (`0x08000000`) across `src/launcher.zig` and `src/installer_launcher.zig` when launching the Slint runtime.
  - Automated binary PE header patching in `tools/package.ps1` converting `slint-viewer.exe` from Subsystem 3 (Console / CUI) to Subsystem 2 (Windows GUI / `IMAGE_SUBSYSTEM_WINDOWS_GUI`), permanently preventing the Windows kernel from allocating a console window.

---

## [0.4.0] - 2026-11-04

### Added
- **Native Cheat Engine Table (`.CT`) Inquest Engine ("सीटी प्रवेश // CT Pravesha")**:
  - Implemented high-throughput, zero-dependency streaming XML parser (`src/memory/ct_parser.zig`) tailored to the Cheat Engine schema (`CheatTable`, `CheatEngineTableVersion`, `CheatEntries`, `CheatEntry`, `ID`, `Description`, `VariableType`, `Address`, `Offsets`, `Offset`, `ShowAsSigned`, `Color`, `AssemblerScript`, `UserdefinedSymbols`, `SymbolEntry`, `LuaScript`).
  - Added XML entity unescaping for `&quot;`, `&apos;`, `&lt;`, `&gt;`, `&amp;`, and numeric newline entities (`&#10;`, `&#13;`, `&#x0A;`, `&#x0D;`).
  - Built-in hierarchical tree preservation and fast linear array flattening for reactive table synchronization.
  - Stress-tested and verified across massive real-world tables from `D:\Mods`:
    - `D:\Mods\BG3\bg3.CT`: 830 entries extracted; verified execution of Entry `4501` (`Get Item's Template UUID`) with embedded `{$lua}` invoking `getAddress`, `writeString`, `PrepareCall`, and `executeCodeEx`.
    - `D:\Mods\AC Valhalla\AC Valhalla Inventory Editor - 1.6.2.CT`: 720 entries extracted; verified execution of Entry `23930` (`[COMPACT MODE]`) using CE GUI stubs.
    - `D:\Mods\Elden Ring\eldenring_all-in-one_Hexinton-v4.25_ce7.5.ct`: 12,866 entries parsed and synchronized in ~1.0s with zero memory leaks.
- **Cheat Engine Embedded Lua Compatibility Subsystem ("चेतना सूत्र // Chetana Sutra")**:
  - Developed full LuaJIT 2.1 emulation layer (`src/scripting/ce_compat.zig`) for Cheat Engine runtime globals and functions:
    - **Execution Environment:** `syntaxcheck = false` (allows runtime script evaluation while preventing false early returns), `process = "active"`.
    - **Process & Symbol Management:** `openProcess(name_or_pid)`, `getProcessIDFromProcessName(name)`, `getOpenedProcessID()`, `getAddress(symbol_or_expr)`, `getAddressSafe(symbol_or_expr)`, `registerSymbol(name, addr)`, and `unregisterSymbol(name)`. Supports module expressions like `"bg3.exe"+0x24A266F` and `$process+offset`.
    - **Memory Read/Write Functions:** `readInteger` / `writeInteger`, `readQword` / `writeQword`, `readPointer` / `writePointer`, `readFloat` / `writeFloat`, `readDouble` / `writeDouble`, `readString` / `writeString`, and `readBytes` / `writeBytes`.
    - **Remote Execution & System Calls:** `executeCodeEx(threadSync, timeout, funcAddr, [args...])` via native Win32 `CreateRemoteThread`, `sleep(ms)`, and `messageDialog(str, ...)`.
    - **CE GUI & Engine Stubs:** Stubs for `getMainForm()`, `createMenuItem(parent)`, `getAddressList()`, `getMemoryRecordByID(id)`, and `PrepareCall(...)` ensuring table customization scripts execute without nil-indexing exceptions.
- **Rudra Tandava UI Integration**:
  - Added dedicated **`LOAD .CT`** action button (Devanagari: `सीटी प्रवेश`, Amber `#ca8a04`) in `CHETANA TALIKA // CHEAT TABLE`.
  - Added **`Load Cheat Engine Table (.CT)`** action to the Universal Command Palette (`Ctrl + P`).
  - Added dynamic `CheatTableRow` list rendering with live memory values, freeze checkboxes, `WRITE` buttons for addresses, and `EXECUTE` (Devanagari: `प्रयोग`) buttons for embedded Auto Assembler / Lua scripts.
  - Implemented `tools/open_ct.ps1` with native Windows file picker dialog filtered to `*.CT;*.ct;*.sharabha` defaulting to `D:\Mods`.
- **CLI Subcommands**:
  - `--load-ct <path>`: Loads `.CT` tables, registers symbols, resolves pointer chains, runs master scripts, and syncs to `src/ui/live_table.slint`.
  - `--run-ct-entry <path> <id>`: Activates/runs specific entries (executing inline Lua or Auto Assembler).

---

## [0.3.1] - 2026-11-04

### Fixed
- **Save Editor Column Alignment & Full-Width Justification ("स्थान संरेखण // Sthana Samrekhana")**:
  - Re-anchored the save forge table from centered layout to flush-left start (`padding-left: 8px`), ensuring all columns start at the very left edge of available space.
  - Resolved container clipping and right-edge truncation by adding `overflow: elide` to dynamic game titles, vessel names, and status feedback bars.
  - Unlocked full horizontal stretch on the editable VALUE (`तत्त्व`) column, extending all the way to the right edge of the card.
  - Locked Column 7 (`ACTION` / `WRITE`) flush against the right border in both table headers and rows.
  - Guaranteed that column resizing flows strictly towards the right, eliminating leftward content shifting during column expansion.
- **Installer & Launcher Startup Visibility**:
  - Updated `src/launcher.zig` to use `wShowWindow = 1` (`SW_SHOWNORMAL`) and normal creation flags (`0` instead of `CREATE_NO_WINDOW`), ensuring double-clicking `Sharabha.exe` visibly renders the main application window without requiring a terminal console.
  - Reinforced universal baseline CPU architecture (`x86_64-windows`) across CI workflow and packaging tools, eliminating `0xC000001D` (`STATUS_ILLEGAL_INSTRUCTION`) exceptions.

### Added
- **Search Bar Explicit Action Button & Dynamic Gating Mechanism ("अन्वेषण शोधन // Anveshana Shodhana")**:
  - Added dedicated `SEARCH 🔍` (`अन्वेषण`) action button and dynamic `RESET ✖` (`निवारण`) clear filter button.
  - Introduced an intelligent gating mechanism (`filter_gating_threshold = 100`):
    - **Compact / Curated Lists (<= 100 entries)**: Live dynamic filtering on keystroke (`edited`) as the user types, accompanied by an emerald `⚡ LIVE FILTER` badge indicator.
    - **Large / Massive Datasets (> 100 entries)**: Dynamic keystroke filtering is gated to prevent performance overhead, allowing filtering on-demand via the `SEARCH 🔍` button or Enter (`accepted`), accompanied by an amber `🔒 GATED (>100)` badge indicator.
  - Implemented `tools/filter_save.ps1` powered by an in-memory JSON cache (`assets/saves/current_save_cache.json`) for multi-field search across key identifiers, hex offsets, data types, values, and confidence scores.

---

## [0.3.0] - 2026-11-03

### Added
- **Agama Deterministic Save Override Engine: Dragon's Dogma 2 & Capcom RE Engine Ecosystem**:
  - Full reverse-engineering and native container integration for Capcom RE Engine save format (`DSSS` container magic `0x44 0x53 0x53 0x53`, container version `2`).
  - **MurmurHash3 (32-bit x86) Integrity Algorithm ("मर्म सूत्र // Marma Sutra")**:
    - Added high-performance native Murmur3_32 checksum algorithm with seed `0xFFFFFFFF` over the `0..len-4` payload span to `src/save/checksum.zig`.
    - Automated detection and recalculation of trailing 4-byte checksum footers in `.bin` save vessels (`data001Slot.bin`), preventing in-game corruption or anti-tamper warnings upon loading edited saves.
  - **Dragon's Dogma 2 (`Steam AppID: 2054970`) Curated Variables (23 Ground-Truth Rules)**:
    - **Economy**: Gold (`Base.Gold`), Rift Crystals (`Base.RC`).
    - **Arisen Progression & Attributes**: Level (1..999), Total Experience (EXP), Discipline Points (DCP), Active Vocation (Jobs 0..9: Fighter, Archer, Mage, Thief, Warrior, Sorcerer, Magick Archer, Mystic Spearhand, Trickster, Warfarer), Current HP, Max HP, Loss Gauge (unrecoverable health), Current Stamina, Max Stamina.
    - **Main Pawn Progression & Attributes**: Level (1..999), Total Experience (EXP), Discipline Points (DCP), Active Vocation (Core Jobs 0..5), Current HP, Max HP, Loss Gauge, Current Stamina, Max Stamina.
    - **Key Items & Consumables**: Ferrystones (Item 81), Wakestones (Item 82), Allheal Elixirs (Item 3).
  - **RE Engine Ecosystem Profile Definitions**:
    - Pre-configured profiles with container signature validation for *Resident Evil 4 Remake* (`re4`), *Monster Hunter Wilds* (`re_mhw`), *Monster Hunter Rise* (`re_mhr`), *Resident Evil 2 Remake* (`re2`), *Resident Evil 3 Remake* (`re3`), *Resident Evil Village* (`re8`), and *Resident Evil 7: Biohazard* (`re7`).
  - **Jñāna Kośa Multi-Model Knowledge Graph Integration**:
    - Seeded canonical knowledge graph nodes: `game:dd2`, `save_profile:dd2_bin`, pointer path routes (`pointer:dd2_gold`), and integrity rule (`kavacha:dd2_murmur3`) into the embedded graph engine with SurrealQL export support.
  - **Third-Party Research Attribution & Legal Compliance**:
    - Added explicit legal notices and MIT acknowledgements in `README.md`, `NOTICE`, `LICENSE`, and code comments for `kagenocookie` (`dd2-content-editor`) and `kvasszn` (`ree-save-editor`).
- **Phase 5: Pasha Bandhana (Win32 Remote Thread DLL Injection)**:
  - Native DLL injection via `VirtualAllocEx`, `WriteProcessMemory`, and `CreateRemoteThread` invoking `LoadLibraryW`.
  - Comprehensive timeout tracking, remote `HMODULE` base address validation, and automatic remote parameter buffer cleanup.
  - CLI subcommand: `SharabhaCli.exe --inject-dll <pid> <path_to_dll>`.
  - Native Lua binding: `sharabha.inject_dll(dll_path)` returning the remote module base address.
- **Phase 5: Guha Sthapana (Code Cave & 64-Bit Absolute Detour Inline Hooks)**:
  - 14-byte 64-bit absolute indirect jump encoding: `FF 25 00 00 00 00 <8-byte destination>` (`JMP [RIP+0]`), operating without 2GB branch range limitations.
  - Stolen instructions preservation with automatic NOP padding.
  - Remote code cave allocation with `PAGE_EXECUTE_READWRITE` and trampoline return jump assembly.
  - `hook.remove(hProcess)` restoring original instruction bytes and releasing remote cave memory.
  - Native Lua binding: `sharabha.allocate_cave(size)` for dynamic code cave allocation.
- **Phase 5: Sharabha Memory Table Workspace (`.sharabha` Cheat Table Format)**:
  - Structured Cheat Engine `.CT` equivalent file format serializing full reverse-engineering workspaces.
  - Stores target process metadata, static addresses, multi-level pointer chains, AOB patterns, value types (`i32`, `i64`, `f32`, `f64`, `byte`, `string`), freeze values, hotkeys, annotations, and embedded Lua scripts.
  - Memory-safe serialization and deserialization powered by heap-backed `std.heap.ArenaAllocator`.
  - CLI subcommands: `SharabhaCli.exe --save-table <path>` and `SharabhaCli.exe --load-table <path>`.
  - Dedicated Slint UI buttons: `SAVE .sharabha` (सारिणी संग्रह) and `LOAD .sharabha` (सारिणी प्रवेश).
- **Phase 4: Lua Altar Interactive Script Editor & Output Console**:
  - In-app interactive script editor panel in Rudra Tandava targeting attached process PID.
  - Five canonical template quick-pickers: `READ/WRITE`, `POINTER CHAIN`, `FREEZE LOCK`, `INJECT DLL`, and `CODE CAVE`.
  - Output and error capture buffer routing all Lua `print(...)` and `sharabha.log(...)` calls to an interactive console row in the UI.
  - Expanded Lua API bindings: `sharabha.read_i64`/`write_i64`, `sharabha.read_f64`/`write_f64`, and multi-level pointer chain traversal (`sharabha.read_pointer(base, {offsets})`).
- **Phase 4: Jnana Kosha Profile CRUD & User Annotations**:
  - Embedded multi-model knowledge graph CRUD operations: `registerGame`, `updateGame`, and `deleteGame` with cascaded profile/pointer cleanup.
  - User reverse-engineering annotations: `addAnnotation` and `getAnnotationsForGame` tracking custom offset notes.
  - Community profile sharing: `exportProfilesJson` and `SharabhaCli.exe --export-agamas` generating portable community JSON.
  - Slint UI action: `EXPORT JSON // Community` in the Jnana Kosha tab.

---

## [0.2.0] - 2026-11-03

### Added
- **Agama Deterministic Save Override Engine: Mass Effect Legendary Edition Trilogy (MELE1, MELE2, MELE3)**:
  - Full reverse-engineering and integration of BioWare Unreal Engine 3 save models, chunked container architectures, serialization streams, and CRC-32 integrity algorithms based on upstream ground-truth specifications (`KarlitosVII/trilogy-save-editor`).
  - **Strict Game & Edition Differentiation**:
    - **MELE1**: Detected strictly via `.pcsav` + Unreal chunk package magic `0x9E2A83C1` + multi-chunk zlib decompression table + uncompressed version `50`.
    - **MELE2**: Detected strictly via `.pcsav` + binary version integer `30` (`0x1E 0x00 0x00 0x00`). Original mid-2000s ME2 (version `29`) is strictly rejected from Agama deterministic mode and cleanly preserved for universal fuzzy Pravaha scanning.
    - **MELE3**: Detected strictly via `.pcsav` + binary version integer `59` (`0x3B 0x00 0x00 0x00`). Mid-2000s original ME3 and Mass Effect: Andromeda are strictly excluded.
  - **Curated High-Priority Variables (100% Curated Agama Score)**:
    - **MELE1 (11 variables)**: Credits, Medi-Gel, Grenades, Omni-Gel, Paragon Points (Plot Int 47), Renegade Points (Plot Int 46), Character Level, Experience Points (CurrentXP), Talent Points, Character First Name, Identity / Face Code.
    - **MELE2 (15 variables)**: Credits, Medi-Gel, Element Zero (Eezo), Iridium, Palladium, Platinum, Planetary Probes, Normandy Fuel, Paragon Points (Plot Int 2), Renegade Points (Plot Int 3), Character Level, Experience Points (CurrentXP), Talent Points, Character First Name, Identity / Face Code.
    - **MELE3 (14 variables)**: Credits, Medi-Gel, Grenades, Normandy Fuel, Paragon Points (Plot Key 10159), Renegade Points (Plot Key 10160), Reputation Bars (Plot Key 10297), Reputation Total Points (Plot Key 10380), War Assets Registered Count, Character Level, Experience Points (CurrentXP), Talent Points, Character First Name, Identity / Face Code.
  - **BioWare CRC-32/BZIP2 Integrity Algorithm ("ब्रह्म चक्र // Brahma Chakra")**:
    - Added polynomial `0x04C11DB7` (init `0xFFFFFFFF`, xorout `0xFFFFFFFF`, refin/refout `false`) to `src/save/checksum.zig`.
    - Automatic validation and auto-patching of trailing 4-byte CRC-32/BZIP2 footers in `.pcsav` save vessels during save writes.
  - **Zero-Dependency Native Extraction (`tools/open_dialog.ps1`)**:
    - Chunked zlib package decompression (`Unpack-Me1LePackage`) for MELE1 saves producing byte-for-byte identical streams against reference saves.
    - Fast binary parsing with backwards offsets from Face Code anchors and plot tables, eliminating heuristic scans and executing in under 1 second.
  - **Ground-Truth Test Suite & Fixture Coverage**:
    - Full Zig test coverage in `src/knowledge/profiles.zig`, `src/save/dual_mode.zig`, and `src/save/checksum.zig` verifying accurate profile detection, rejection of non-LE saves, and CRC32/BZIP2 calculation.
    - Verified against real MELE save fixtures in `assets/saves/ME1LeSave.pcsav`, `assets/saves/ME2LeSave.pcsav`, and `assets/saves/ME3Save.pcsav`.
    - Cloned reference repository `temp_trilogy_editor` cleanly removed upon verification.
  - **Open-Source Attributions & Licensing**:
    - Project licensed under Apache 2.0 with copyright to Abhishek Mitra (`indoctrinatedrecluse`).
    - Added formal `LICENSE` and `NOTICE` files incorporating explicit third-party attribution to Karlitos (`KarlitosVII/trilogy-save-editor`) for Mass Effect Trilogy save format research and models.
    - Documented third-party attributions in `README.md` and `src/knowledge/profiles.zig`.
- **Agama Deterministic Save Override Engine: Suzerain by Torpor Games**:
  - Ground-truth integration with user's official save editor (`D:\Projects\Suzerain-save-editor`), replacing heuristics with 100% deterministic recognition and verified variable schemas for Torpor Games' Lua-in-JSON vessel structure.
  - **Dual Campaign Recognition**:
    - **Base Game Sordland (President Anton Rayne)**: Automatic detection of `StoryPack_Main`, curating Government Budget (with dynamic Turn < 4 and Budget > 3 Black Tuesday warning), Personal Wealth, Country Unrest, Public Opinion, Bludish Opinion, Market Crash toggles, Reform Assembly/Court Votes, Gloria/Albin convince flags, Article 6&7 USP support, Regional Economic recovery (Agnland, Bergia, Lorren, Gruni), Relations (Franc, Monica, Lucian), Scandals Severity, and paired Military Expansion & Modernisation branches (Army, Navy, Air Force).
    - **Rizia DLC (King Romus Toras)**: Automatic detection of `StoryPack_Rizia` and `NG1`, curating Royal Budget (capped at 25), Royal Authority (capped at 15), Energy Reserves (capped at 25), per-turn resource modifiers, Deployable Units (Infantry, Tanks, Submarines, Support, Capital Ships), Military Stockpiles (Trucks, Ships, Tanks, Submarines, Manpower, Equipment), War Action Points & Air Strike refills, Pales War Public Support, Welfare & Living Standards, Royal Houses Standing (Toras, Sazon, Azaro), Religious Opinions, Diplomatic Negotiating Power (10 nations/regions), and Council Relations (Arch-Priest Sal, Princess Vina, Queen Mother Estela, Pabel, Uncle Hugo, Lucita Romance).
  - **Agama Curated & Pravaha Raw Dual Mode**: Curated high-priority variables appear at the very top of the scrollable table with `100% Curated Agama` confidence, followed by all 350+ embedded variables in Raw Editor mode with real-time text filtering.
  - **Atomic Safe Mutation Engine**: Implemented `SharabhaCli.exe --write-save-kv <key> <val>` and `tools/write_save.ps1` utilizing exact regex pattern matching (`(\[\\\"" + Regex.Escape(key) + "\\\"\"\]\s*=\s*)([\w\.-]+|true|false)`) with automatic `.sharabha.bak` preservation, atomic swap, and live Slint UI synchronization.
  - **Ground-Truth Test Suite**: Comprehensive unit tests in `src/knowledge/profiles.zig` and `src/save/dual_mode.zig` validating Suzerain campaign detection, scalar/bool parsing, atomic in-place mutation, and live verification against `D:\Projects\Suzerain-save-editor\FinalSave_11-12-2025_22-14-25.json`.
- **Rudra Tandava Cheat Engine Expansion & Memory Manipulation Subsystem**:
  - **Multi-Level Pointer Scanning Engine (`src/memory/pointer_scan.zig`)**:
    - Configurable base address, target dynamic addresses, maximum depth, and maximum offset strides.
    - Resolves multi-level pointer paths across process address spaces for stable cheat table forging across game restarts.
  - **Stambhana Goraksha Memory Freezing Sentinel (`src/memory/freeze.zig`)**:
    - Thread-safe background freeze loop running non-blocking 100ms periodic writes.
    - Prevents games from overriding protected health, stamina, ammunition, and currency values.
  - **Memory Scanner & Disassembler Integration**:
    - Complete umbrella bugfix pass confirming pure Win32 VirtualQueryEx page enumeration, ReadProcessMemory, and WriteProcessMemory reliability without crashes or heap leakage.
- **Interactive Resizable & Justified Save Editor Columns (`src/ui/app.slint`)**:
  - Implemented custom draggable column splitters in `SaveKeyValueTable` allowing real-time interactive resizing of `Offset`, `Variable Key / Identifier`, `Type`, `Confidence`, `Hex Signature`, and `Live Value` columns.
  - Proper column justification and padded alignment preventing visual crowding across all screen resolutions.

---

## [0.1.0] - 2026-11-02

### Added
- **Flashy Native Windows Setup & Installer (`SharabhaSetup.exe`)**:
  - Full-screen translucent glass installer UI (`src/ui/installer.slint`) themed with Shaivite mysticism and systems duality.
  - Looping 24 FPS hardware-accelerated background cinema from `splash_sharabha.mp4` playing beneath the installer canvas.
  - **Dynamic Existing Installation Auto-Detection**: Automatically queries Windows registry registration (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Sharabha`) and destination paths on startup (`tools/installer_check.ps1`).
  - **Automatic Install-to-Update Button Morphing**: If an existing installation is detected, the primary action button seamlessly transitions from `INSTALL // संस्थापन प्रारंभ` to `UPDATE // अद्यतन प्रारंभ` with sapphire blue styling and `🔄` insignia, preserving user settings and data while upgrading binaries.
  - **Live Reactive Directory Discovery**: When a custom folder is chosen in the browse dialog (`tools/installer_browse.ps1`), the installer checks for an existing `bin\Sharabha.exe` and instantly toggles between Install and Update modes via Slint `--auto-reload`.
  - Customizable target installation vessel directory with native Windows folder picker.
  - Option to forge Desktop Trishula shortcut with high-resolution mythic application icon.
  - Option to register Start Menu program entry.
  - Option to automatically awaken and launch Sharabha upon installation completion.
  - Embedded Windows PE resource (`res/installer.rc`) sharing the high-res `app_icon.ico` and packing the standalone payload.
- **Hardware-Accelerated Splash Screen Cinema**:
  - 24 FPS cinema overlay on application startup playing the 143 hardware frames of `splash_sharabha.mp4`.
  - Radiant mythic Sharabha emblem with glowing cyan and ember wings, particle simulation, and Devanagari typography.
  - Automatic transition into temple upon cinema completion (~3.8s) or instant entrance via `ENTER TEMPLE (मंदिर प्रवेश)`.
- **Silent Windows GUI Subsystem Launcher (`Sharabha.exe`)**:
  - Native Win32 GUI subsystem binary (`subsystem = .windows`) that completely suppresses and eliminates command prompt or PowerShell windows when double-clicked.
  - Spawns background process inquests and Slint desktop UI with `CREATE_NO_WINDOW` and `-WindowStyle Hidden`.
- **Universal Pravaha Sūkshma Rekha (प्रवाह सूक्ष्म रेखा) Fuzzy Save Overseer**:
  - Purged all hardcoded deterministic overfitting across game titles, file extensions, and character names (`Nyx00`, `Shepard`, `ME1`, `Suzerain`, `ER0000`).
  - Generalized recursive JSON crawler capable of extracting arbitrary nested dictionaries and deserializing serialized embedded key-value structures across 300+ variables.
  - Universal binary/container extractor with automatic zlib/deflate stream unwrapping, scanning for Pascal length-prefixed strings, ASCII tags, associated metrics, floats, and integer game resources.
  - Confidence-ranked descending sort across all extracted key-values, ensuring prominent anchors and high-certainty metrics lead the table.
  - Marked deterministic Agama engine as **[WIP]** in both backend and UI pending user-supplied game-by-game rules.
- **Unified Tabular Key-Value Save Editor (`SaveKeyValueRow`) in Kalyana Sthiti**:
  - Unified 7-column tabular editor with `OFFSET`, `KEY IDENTIFIER (लक्षण)`, `TYPE (रूप)`, `CONFIDENCE`, `HEX DUMP`, and editable in-place `PRE-LOADED VALUE`.
  - **Interactive Resizable Column Dividers**: Implemented interactive vertical grip dividers (`mouse-cursor: col-resize`) between every column in the table header. Dragging any divider dynamically resizes column widths (`OFFSET`, `KEY IDENTIFIER`, `TYPE`, `CONFIDENCE`, `HEX DUMP`, and `VALUE`) across both header and table rows in real time.
  - **Justified Column Alignment & Breathing Room**: Completely eliminated clumping by giving each column dedicated cell bounds, padding, and semantic alignment: left-aligned monospace offsets, bold key identifiers with key insignia, centered amber badges for types, centered emerald pill badges for confidence ratings, centered dark monospace hex cells, stretching value edit fields, and centered action buttons.
  - Individual `WRITE ✎` action buttons per row and bulk `APPLY ALL // Write (सर्व संस्कार)` commit bar.
  - Dynamic key-value search filter LineEdit for instant property filtering.
- **Generic Memory Scanner & Live Inquest Engine (Rudra Tandava)**:
  - Eliminated all hardcoded placeholder addresses, simulated counts, and mockups.
  - Implemented genuine Win32 `VirtualQueryEx` page crawling across committed, writable virtual memory spaces (`src/memory/scanner.zig`, `src/memory/engine_service.zig`).
  - Full multi-iteration differential filtering supporting `ExactValue`, `IncreasedValue`, `DecreasedValue`, `ChangedValue`, and `UnchangedValue`.
  - Real Win32 `WriteProcessMemory` live RAM mutation with automatic readback verification.
  - Dynamic `ScanResultRow` scrollable table in `src/ui/app.slint` rendering real memory addresses in hex, live values, previous values, and data types, with in-place editing, individual `WRITE` triggers, `+ PIN` to cheat table, and `FREEZE` toggling.
  - Binary state persistence (`assets/memory/scan_state.bin`) preserving scan results across CLI invocations.
- **Multi-Level Pointer Scanner (Vyūha Sūtra // व्यूह सूत्र)**:
  - High-speed recursive reverse dereference graph traversal (`src/memory/pointer.zig`) to discover pointer paths across arbitrary depths (up to 7 levels) and offsets (up to 4096+ bytes).
  - Win32 Toolhelp32 module enumeration (`process.ModuleIterator`) identifying static base pointers (`[module.exe + 0xOffset] -> [+0xOffset1] -> ... => 0xTarget`) that remain invariant across ASLR and restarts.
  - Real-time chain dereference resolver (`resolvePath`) that dereferences live pointer paths through process memory and reports target values.
  - CLI subcommands: `--pointer-scan <addr> [max_depth] [max_offset]` and `--pointer-resolve <base_module> <base_offset> <offsets...>`.
  - UI row action button `PTR 🔗` (व्यूह सूत्र) for instantaneous pointer path analysis directly from the memory scanner.
- **Persistent Active Memory Freeze Sentinel Daemon (Stambhana Goraksha // स्तम्भन गोरक्ष)**:
  - Dedicated background worker loop (`FreezeDaemon` in `src/memory/freeze.zig`) running at high-frequency 35ms cycles enforcing locked memory values via `WriteProcessMemory`.
  - Automatic background daemon lifecycle management: auto-spawns silently with `CREATE_NO_WINDOW` on first freeze command, tracks target PID, re-synchronizes with `frozen_entries.txt`, and gracefully terminates when all locks are released.
  - CLI subcommands: `--freeze-daemon` and `--freeze-status` for live health and active lock inspections.
- **x86_64 Machine Code Disassembler (Vyākaraṇa // व्याकरण)**:
  - High-performance pure-Zig instruction decoder and disassembler (`src/memory/disasm.zig`).
  - Full decoding for REX prefixes, ModR/M, SIB bytes, RIP-relative addressing (`[rip+disp32]`), immediate arithmetic groups (`0x81`/`0x83` add, sub, cmp, xor, and, or), branch/call instructions (`Jcc`, `JMP`, `CALL`, `RET`), register moves, and SSE/AVX vector memory instructions (`movss`, `movsd`).
  - CLI subcommand: `--disasm <addr> [count]` for inspecting assembly instructions at any process address in hex and mnemonic formats.
  - UI row action button `ASM ⚙` (व्याकरण) for instant disassembly inspection.
- **Tāṇḍava Netra Hardware Write Watcher (ताण्डव नेत्र)**:
  - Non-invasive Win32 Hardware Breakpoint monitor (`src/memory/debugger.zig`, Cheat Engine F6 equivalent).
  - Uses CPU debug registers (`DR0`..`DR3`, `DR7`) across all target process threads to intercept and catalog instructions that write to watched addresses without crashing the target.
  - Captures complete register state snapshots (`RAX`, `RBX`, `RCX`, `RDX`, `RSI`, `RDI`, `RBP`, `RSP`, `R8`..`R15`, `RIP`, `EFLAGS`) alongside disassembled instructions.
  - CLI subcommand: `--watch-writes <addr> [timeout_ms]`.
  - UI row action button `F6 👁` (ताण्डव) for memory write tracking.
  - Native CLI subcommands (`--attach`, `--scan`, `--rescan`, `--write-mem`, `--freeze-mem`, `--reset-scan`) and PowerShell companion orchestrator (`tools/memory_ops.ps1`).
  - Process picker dialog modal searching and filtering all active host processes.
- **Universal Command Palette & Knowledge Base**:
  - Quick action palette accessible via `Ctrl+P` or top navigation bar.
  - Dynamic searchable documentation widget covering Shannon entropy, chi-square, byte density, and Stambhana freeze.
- **Embedded Scripting & Hardware Vault**:
  - Embedded LuaJIT 2.1 scripting runtime with memory manipulation and freeze bindings.
  - Windows DPAPI Hardware Vault (`Gupta Kosha`) for Google Gemini AI oracle guidance.
  - Embedded SurrealDB knowledge graph (`Jnana Kosha`) linking games to pointer offsets.

### Changed
- **Zero-Window Background Execution**: Suppressed console and terminal windows during both installer and main application execution using Win32 `CREATE_NO_WINDOW` and `SW_HIDE` startup info.
- Decoupled `Sharabha.exe` (Win32 GUI launcher) and `SharabhaCli.exe` (diagnostics & test engine).
- Switched all PowerShell callbacks to direct `-WindowStyle Hidden` execution without `.cmd` console intermediaries.
- Defaulted `save_view_mode: 1` directly to Pravaha Fuzzy Raw Table view.
- Bound `AppWindow.active_tab` to `LiveSave.active_tab_hint` so that save file imports preserve the user's view in Kalyana Sthiti without jumping tabs.
- Widened table columns in Save Forge to prevent text clipping across long property names.

### Fixed
- Purged overfitted save detection logic in `profiles.zig` and `open_dialog.ps1` that assumed character name `Nyx00` or specific title strings.
- Fixed PowerShell argument parsing in native open dialog invocation.
- Removed unsupported layout properties from Slint `LineEdit` controls.
- Enforced UTF-8 BOM encoding across all helper scripts to prevent Devanagari character corruption in Windows PowerShell 5.1.

### Security
- Hardware-backed DPAPI encryption for all sensitive vault credentials via Win32 `CryptProtectData`.
- Sthiti Sankalpa atomic swap protection creating `.sharabha.bak` backups and temporary shadow buffer integrity checks before committing saves.

### Security
- Hardware-backed DPAPI encryption for all sensitive vault credentials via Win32 `CryptProtectData`.
- Sthiti Sankalpa atomic swap protection creating `.sharabha.bak` backups and temporary shadow buffer integrity checks before committing saves.
