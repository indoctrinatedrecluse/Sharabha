# Changelog

All notable changes to the **Sharabha (शरभेश्वर) — The Dual Aspect Engine** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.5.3] - 2026-11-05

### Fixed
- **Update downloads were impossible under Windows PowerShell 5.1** (the runtime the UI actually shells out to): `tools/updater.ps1` built its streaming client with `New-Object System.Net.Http.HttpClient`, and `System.Net.Http` is not resolvable in a stock 5.1 session — every `-Download` aborted with `Cannot find type [System.Net.Http.HttpClient]` *after* the progress state had already been written, which the modal rendered as a download that never starts. The transport is now `WebRequest`/`HttpWebRequest` (present in every supported runtime) with an explicit `Tls12`(+`Tls13` when available) negotiation, a `User-Agent`, redirect following, `Content-Length` used as a fallback size when the API omits it, and a non-zero exit code on failure. Verified end-to-end: a real 57.14 MB release asset streams, verifies, and lands in `%TEMP%\Sharabha-Update`.
- **Embedded LuaJIT no longer inherits a host-wide `LUA_PATH` / `LUA_CPATH`** — root cause of the "Cheat Engine / `require`" breakage investigated this cycle:
  - In Lua, an exported `LUA_PATH` **replaces** (never extends) the compiled-in default unless it contains a bare `;;` entry. Any machine carrying a leftover 5.1 LuaRocks / LuaJIT tree therefore redirected `require()` away from the modules that ship next to the host executable. That is exactly why a `.CT` script could not find its own `defines.lua` when the launch CWD was not the Cheat Engine folder, and why `package.cpath` entries could hand 5.1-ABI DLLs to the VM.
  - `ScriptEngine.init` (`src/scripting/engine.zig`) now pins `package.path` / `package.cpath` to deterministic roots before the first user script runs: `<exe>\lua\?.lua`, `<exe>\lua\?\init.lua`, the portable vessel root (`<root>\lua\?.lua`, `<root>\?.lua`) when the executable lives in `bin\`, `<exe>\?.lua`, `<exe>\?\init.lua`, and only then the process CWD — mirroring `engine_service.resolveProjectPath`. Native modules resolve from `<exe>\lua\?.dll`, `<root>\lua\?.dll`, `<exe>\?.dll`, `.\?.dll`.
  - Extension roots are still available, but only as a documented opt-in appended *after* the bundle: `SHARABHA_LUA_PATH` / `SHARABHA_LUA_CPATH`. A stale global can no longer shadow anything Sharabha ships.
  - Failure to pin is non-fatal (a single `[Lua Warning]` on stderr); the VM then keeps Lua's compiled-in defaults.
- **Auto-updater payload corruption paths (`tools/updater.ps1`)**:
  - The release-metadata cache is written atomically (`<cache>.tmp` → copy) and treated as stale after 30 minutes. `-Download` now refreshes instead of trusting a superseded tag/asset URL; `-Dismiss` re-serialises whatever is cached without touching the network.
  - Downloads are verified before they can ever be installed: byte count must equal the asset size **and** the payload must start with an `MZ` header. A truncated or HTML-error-page download is deleted from the staging folder rather than being picked up later as the newest `*setup.exe`.
  - `-Install` re-validates the payload (size + `MZ`), closes `Sharabha` / `slint-viewer` **before** the setup starts (bounded wait loop, so no files-in-use dialog), and reports an `Installer Payload Invalid` state instead of failing silently.
  - `published_at` / `body` are handled null-safely (`Format-ReleaseDate`); changelog bodies are capped at 32k with control bytes stripped so an oversized or ESC-laden release note can never break `slint-viewer --auto-reload`; version comparison is semver-aware (`Test-NewerVersion`, so `v0.5.10` correctly beats `v0.5.9`).

### Changed
- **Console cloaking contract documented and enforced for the updater**: the UI invokes it through `powershell.exe -WindowStyle Hidden`, the script sets `$ProgressPreference = 'SilentlyContinue'` so no progress bar can paint into an allocated console, and every child it spawns (`setup.exe`) is a GUI-subsystem binary. Check → download → install produces no terminal window and no dialog.
- Version bumped to **0.5.3** across `build.zig.zon`, `src/root.zig`, the installer UI / logic / check scripts, `tools/package.ps1`, `tools/extract_release_notes.ps1`, `tools/updater.ps1`, and the release workflow's fallback tag.

### Added
- **Regression tests for the Lua path pinning** (`src/scripting/engine.zig`): `buildPackagePath` ordering (exe → portable root → exe dir → CWD → opt-in), `buildPackageCpath` + `Lua` string escaping for Windows paths, and a live VM test asserting the running `package.path` starts with the executable's own `lua\?.lua` and never contains a host `LUA_PATH`.

---

## [0.5.2] - 2026-11-05

### Fixed
- **`.CT` (Cheat Engine table) loader crash — silent ParserError under Windows PowerShell 5.1**:
  - `tools/open_ct.ps1` contained non-ASCII glyphs (emoji + Devanagari) but no UTF-8 BOM. Windows PowerShell 5.1 decodes BOM-less scripts as ANSI (CP1252), so multi-byte UTF-8 continuation bytes (`0x93`/`0x94`) were re-read as smart quotes and the tokenizer aborted with a `ParserError`. The script therefore never executed, which the UI surfaced as a "crash" of the `.CT` import button.
  - Rewrote `tools/open_ct.ps1` with an explicit UTF-8 BOM and a header comment documenting the encoding contract, `$PSScriptRoot`-relative resolution of the bundled resources (works from `-File` invocations and any working directory), `Resolve-SharabhaCli` lookup (`bin\` → `zig-out\bin\` → `PATH`), a top-most invisible owner window for the file picker, persistence of the selected table path (`active_table_path.txt`, UTF-8 without BOM), and a guarded viewer poke that only fires when `live_table.slint` exists and is non-empty.
- **Slint viewer crash on generated tables (`--auto-reload`)**:
  - `slint-viewer --auto-reload` recompiles `src/ui/live_table.slint` the instant it changes, so a truncated or partially written file kills the whole UI process. Table export now publishes atomically: the payload is written to `<path>.tmp`, flushed, and swapped into place with `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`, falling back to a direct overwrite (and shadow-copy cleanup) if the rename cannot be performed. Refactored `writeFullFile` into `toWideZ` + `writeFileDirect` + atomic publish so every writer inherits the same guarantee.
- **Generated Slint literals are now guaranteed to be valid UTF-8**:
  - `appendEscapedSlint` escapes `"` and `\`, collapses CR/LF/TAB into spaces, drops remaining control bytes, and replaces malformed multi-byte sequences with `?`. A `.CT` authored in a legacy code page can no longer emit an uncompilable `live_table.slint`.
  - Table header assembly moved off a fixed 512-byte stack buffer to heap formatting, so long table names/paths can no longer fail with `NoSpaceLeft`; the table title/basename are now escaped as well.
- **RPG Maker writer could corrupt the wrong field (and silently no-op)**:
  - `setActorLevel` ignored its `actor_idx` argument and rewrote the *first* `_level` in the container, so editing "Actor #2 Level" changed Actor #1; `setVariable` was an empty stub. Both now operate on JSON *byte spans* (`findField`/`findScopedSpan`/`arrayElement`/`replaceSpan`), so `party._gold`, `actors._data[n]._level|_hp|_mp`, `variables._data[n]`, `switches._data[n]` and `party._items["<id>"]` are edited individually and the rest of the file stays byte-identical.
  - Scope lookups skip decoy `null` values (MZ containers carry `"system": { "switches": null }` before the real `"switches": {"_data": [...]}`), which previously made every switch/variable edit fail with `SwitchNotFound`.
  - Ruby Marshal containers (`.rxdata`/`.rvdata`/`.rvdata2`) now return `error.MarshalMutationUnsupported` and a read-only warning instead of reporting a successful write that `serialize` dropped on the floor.
  - `--write-save-kv` commits RPG Maker mutations through `RpgMakerSave.writeToDisk` (`{path}.sharabha.tmp` + `MoveFileExW` + `.sharabha.bak`) instead of a direct `CREATE_ALWAYS` overwrite.
- **`.CT` tables saved as "Unicode" parsed as zero entries**: `ct_parser.readCtFile` now normalises the payload (`normalizeCtBytes`): UTF-8 BOM is stripped, UTF-16LE/BE (with BOM, including surrogate pairs) is transcoded to UTF-8 before the tag scanner runs. Cheat Engine's default UTF-8-BOM output and legacy UTF-16 tables both parse identically.
- **`--load-ct` failures were reported as success**: the CLI exited `0` even when the table could not be read, so `tools/open_ct.ps1`'s `$LASTEXITCODE` guard could never fire and the UI kept showing a stale table. Load/parse failures now exit `1` with the offending path in the message.
- **Generated bridges were written relative to the current directory**: `src/ui/live_table.slint` and `assets/tables/active_table_path.txt` are resolved through `resolveProjectPath` (CWD → exe dir → exe dir with a trailing `bin\` removed), so a packaged `bin\Sharabha.exe` (CWD = `bin\`) updates the files the Slint viewer and launcher scripts read instead of writing into `bin\src\ui\`.
- **Stambhana freeze daemon lifecycle / `zig build` install lock**:
  - The sentinel daemon keeps `SharabhaCli.exe` mapped, so a daemon surviving a test run broke the following `zig build` install step with an opaque failure. The spawning side now records the child PID immediately (no window where the PID file lags behind the process), the test suite disarms the daemon before finishing, and a new `SharabhaCli.exe --freeze-stop` command terminates an armed sentinel and clears its PID record.

### Added
- **PowerShell encoding guard (`tools/check_scripts.ps1`)**: parses every `tools\*.ps1` with `[System.Management.Automation.Language.Parser]`, fails on any `ParserError` (with line/message), and warns when a script contains non-ASCII characters without a UTF-8 BOM. Intended as the CI/pre-commit guard for the class of failure described above.
- **Ren'Py Visual Novel save parser ("काव्य सूत्र // Kavya Sutra")** (`src/save/renpy.zig`):
  - `Ren'Py Save Game` header/metadata parsing with pickle-protocol reporting, zlib inflate/deflate of the save payload, and a bounded (8192-field) typed field tree.
  - Typed accessors and mutators (`getInt`/`getFloat`/`getBool`/`getString`, `setInt`/`setFloat`/`setBool`/`setString`, `applyEdit`) plus deterministic reserialization preserving the container.
  - CLI: `--parse-renpy [path]` inspector output (`FORMAT:`/`PROP:` rows consumable by the UI) and `--write-save-kv <key> <value>` support with `.sharabha.bak` backups and atomic swap.
  - Detection registered in `src/save/metrics/magic_header.zig` (`RenpySave`).
  - Sample fixture `assets/saves/SampleRenpy.save` and generator `tools/create_mock_renpy.ps1`.
- **RPG Maker save parser ("माया लीला सूत्र // Maya Lila Sutra")** (`src/save/rpgmaker.zig`):
  - Container detection and decoding for Ruby Marshal 4.8 (`.rxdata`/`.rvdata`/`.rvdata2`), LZ-String Base64 (`.rpgsave`), and plain JSON saves.
  - Extraction of party gold, actor stats (name/level/HP/MP), game variables, switches, and inventory item counts, with indexed mutators (`setGold`, `setActorField`/`setActorLevel`, `setVariable`, `setSwitch`, `setItem`, `applyEdit`), reserialization, and `writeToDisk` (`.sharabha.bak` + atomic swap).
  - `applyEdit` accepts the exact `--parse-rpg` row labels (`Party Gold (_gold)`, `Actor #2 Level (Marsha)`, `Variable #0003`, `Switch #0002`, `Item #17`) as well as short keys (`Gold`, `Actor2.Level`, `Switch2`, ...).
- **RPG Maker vessel in the save-editor UI pipeline** (`tools/open_dialog.ps1`): RPG Maker containers are now detected from extension (`.rpgsave`/`.rvdata`/`.rvdata2`/`.rxdata`), MV/MZ JSON shape, or an RGSS Ruby Marshal payload, decoded through `SharabhaCli.exe --parse-rpg` (single implementation shared with the CLI), and rendered as curated rows whose keys round-trip through `--write-save-kv`. The file picker gained matching filters.
  - CLI: `--parse-rpg [path]` inspector output, `--write-save-kv` support, and RPG Maker deltas in `diffRpgMakerSaves` (`src/save/diff.zig`).
  - Detection registered in `src/save/metrics/magic_header.zig` (`RpgMakerSave`).
  - Sample fixture `assets/saves/SampleRpgMaker.rpgsave`.
- **`.CT` loader smoke fixtures**: `assets/tables/SampleTable.CT` (pointer entry with offsets, 4/8-byte float types, auto-assembler script, userdefined symbols, `LuaScript`) exercises the full parse → `live_table.slint` export path without requiring a live game process.

### Changed
- Version bumped to **0.5.2** across `build.zig.zon`, `src/root.zig` banner, `src/ui/installer.slint`, `src/ui/updater_state.slint`, `tools/package.ps1`, `tools/extract_release_notes.ps1`, `tools/installer_*.ps1`, and `tools/updater.ps1`.

### Credits
- Save-format research for the Ren'Py and RPG Maker containers was cross-referenced against the open-source **SaveEditor.top** project by **paradoxie** ([`paradoxie/saveeditor`](https://github.com/paradoxie/saveeditor), MIT License).

---

## [0.5.1] - 2026-11-04

### Added
- **Universal Unity Engine Save Parser ("ऐक्य सूत्र // Aikya Sutra")**:
  - Implemented universal Unity save container parser and typed serializer (`src/save/unity.zig`) supporting the three predominant save architectures across thousands of Unity games:
    1. **Unity BinaryFormatter (.NET NRBF)**: Binary deserializer for `SerializationHeaderRecord`, `SystemClassWithMembersAndTypes`, and `ClassWithMembersAndTypes`. Extracts class name, member names, types (`Boolean`, `Byte`, `Int16`, `Int32`, `Int64`, `Single`, `Double`, `String`), and values with in-place byte mutation.
    2. **Unity Easy Save 2 & 3 (ES3 JSON)**: Parser and serializer for the industry-standard Easy Save format, extracting typed property dictionaries (`__type`, `value`).
    3. **Unity PlayerPrefs XML**: Native parser and serializer for `<unity_prefs>` XML storage containing typed `<pref name="..." type="...">` elements.
  - Type-safe mutation helpers: `setInt`, `setFloat`, `setBool`, and `setString` with deterministic serialization.
  - Multi-metric container detection (`src/save/metrics/magic_header.zig`) auto-identifying Unity NRBF headers, Easy Save JSON dictionaries, and PlayerPrefs XML tags.
  - CLI in-place mutation: `--write-save-kv` automatically detects Unity containers, applies typed mutations, generates `.sharabha.bak` backups, and atomically swaps via Win32 `MoveFileExW`.
  - UI integration: `tools/open_dialog.ps1` dynamically parses Unity saves into Kalyana Sthiti (`src/ui/live_save.slint`) with 100% Curated Aikya Sutra confidence.
  - Added visual save diff support (`diffUnitySaves` in `src/save/diff.zig` and `tools/diff_saves.ps1`) providing 1-click delta comparison against backups for Unity saves.
  - Added sample test fixtures and mock generator `tools/create_mock_unity.ps1` producing `SampleUnity.dat` (NRBF) and `SampleUnity.es3` (Easy Save 3).

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
