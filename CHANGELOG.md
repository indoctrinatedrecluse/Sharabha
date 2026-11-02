# Changelog

All notable changes to the **Sharabha (शरभेश्वर) — The Dual Aspect Engine** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
