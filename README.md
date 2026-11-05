# 🦁🐦 Sharabha (शरभेश्वर)

> **Sharabha** (शरभ) is the dual form of the Hindu god **Shiva** — part lion, part bird, eight-legged — manifested to subdue **Narasimha**, the ferocious lion avatar of Vishnu, and ultimately restore peace. It embodies the union of calm wisdom and devastating power: a serene aspect that resolves, and a violent aspect that overwhelms.
>
> This project carries that duality. **Save Forge (कल्याण स्थिति)** is the calm aspect — carefully parsing, understanding, and surgically editing save files with precision and safety. **Memory Engine (रुद्र ताण्डव)** is the violent aspect — attaching to live processes, ripping through gigabytes of memory, injecting code, resolving Cheat Engine `.CT` pointer trees, and bending a running game to your will. Together, they are Sharabha: an all-in-one game tool that is as gentle as it is destructive.

[![Release](https://img.shields.io/github/v/release/indoctrinatedrecluse/Sharabha?color=ff4d2e&label=Sanctified%20Release)](https://github.com/indoctrinatedrecluse/Sharabha/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-Windows%20x64%20(Baseline)-38bdf8)](https://github.com/indoctrinatedrecluse/Sharabha)
[![License](https://img.shields.io/badge/License-Apache%202.0-eab308)](LICENSE)

---

## What Is Sharabha?

Sharabha is a **native Windows desktop application** built on an entirely unconventional stack — **Zig**, **Slint**, **LuaJIT**, and **SurrealDB** — designed as a unified game modding, memory inquest, and save engineering toolkit with core pillars:

### 🧊 Save Forge (कल्याण स्थिति // Kalyana Sthiti) — Universal Save Editor
- **Agama Deterministic Overrides**: Direct structural support for known game containers:
  - **Capcom RE Engine**: `DSSS` container structure, header deserialization, and MurmurHash3 (32-bit) verification for *Dragon's Dogma 2*, *Resident Evil*, and other RE Engine titles.
  - **Mass Effect Legendary Edition**: Complete save model support for MELE1, MELE2, and MELE3 with UE3 bitstreams, chunked decompression, and CRC-32/BZIP2 integrity seals.
  - **Suzerain**: Raw JSON / `.suave` container parsing with multi-field search and instant balance manipulation.
- **Pravaha Fuzzy Heuristic Parsing**: When facing unknown binary save formats, Sharabha computes **Shannon entropy**, byte sparsity, and Chi-Square goodness-of-fit distributions to extract candidate string and numeric key-value tables without prior knowledge.
- **Atomic Consecration (कर्म कवच संकल्प)**: Guaranteed zero-corruption writes via pre-write `.bak` snapshots, shadow buffer serialization, structural validation, and Win32 `MoveFileEx` atomic swapping.

### 🔥 Memory Engine (रुद्र ताण्डव // Rudra Tandava) — Process Inquest & Cheat Engine Altar
- **Cheat Engine Table (`.CT`) Inquest**: High-throughput zero-dependency XML streaming parser (`src/memory/ct_parser.zig`) handling nested entries, variable types, bottom-up `<Offsets>` pointer chains, user-defined symbols, and embedded scripts. Tested on massive 12,000+ entry tables (*Elden Ring*, *Baldur's Gate 3*, *Assassin's Creed Valhalla*).
- **Embedded Lua Altar & CE Emulation (`ce_compat.zig`)**: Full LuaJIT 2.1 compatibility layer implementing Cheat Engine runtime APIs (`openProcess`, `getAddress`, `readInteger`, `writeInteger`, `readPointer`, `writePointer`, `executeCodeEx` remote thread execution, `sleep`, `messageDialog`, and GUI stubs).
- **Stambhana Sentinel (स्तम्भन सिद्धि)**: 100ms background memory freeze daemon locking target memory offsets.
- **SIMD Memory Scanner**: Scans committed pages via `VirtualQueryEx` with initial and iterative rescan filtering (Exact, Changed, Unchanged, Increased, Decreased).
- **Multi-Level Pointer Scanner**: Resolves bottom-up and top-down pointer paths through dynamic entity structures.

### ⚡ Ashtamurti Auto-Updater (अद्यतन संशुद्धि) & Silent Process Cloaking
- **Built-in Auto-Updater**: Checks GitHub Releases API for new releases, displays an interactive thematic modal with rendered Markdown changelog and dual-aspect gradient progress bar, streams the setup package, and cleanly delegates handover to the self-extracting installer.
- **Zero-Console Process Cloaking**: Both `Sharabha.exe` and `SharabhaSetup.exe` utilize `CREATE_NO_WINDOW` and PE Subsystem 2 (Windows GUI) patching to completely eliminate black terminal window flashing during application and installer startup.

---

## Tech Stack

| Layer | Technology | Role |
|---|---|---|
| **UI** | [Slint](https://slint.dev/) | Declarative, compiled, GPU-accelerated native desktop UI toolkit |
| **Core** | [Zig](https://ziglang.org/) | Systems language for all business logic, memory manipulation, and file I/O |
| **Scripting** | [LuaJIT](https://luajit.org/) | Embedded scripting engine for Memory Engine automation (via C API) |
| **Database** | [SurrealDB](https://surrealdb.com/) | Embedded multi-model DB (document + graph + relational) for the game knowledge base |

### Why This Stack?

- **Zig** provides direct Windows API access via `@cImport("windows.h")` with zero bindings overhead, manual memory management without a GC (critical for a memory scanner), and SIMD intrinsics via `@Vector` for high-performance scanning.
- **Slint** compiles to native machine code with its own GPU-accelerated renderer — no Electron, no browser engine, no DOM. The `.slint` declarative markup language has first-class Zig bindings.
- **LuaJIT** is the standard scripting language for game modding tools (Cheat Engine uses it). Its C API is trivially importable into Zig.
- **SurrealDB** runs embedded (in-process) so the app ships as a single binary with no external database server. Its multi-model nature fits the knowledge base perfectly: game profiles are documents, format→field relationships are graph edges, and queries use familiar SQL-like syntax.

---

## Save Forge — Design

### The Problem
Save game files are wildly inconsistent. Some are JSON, some are XML, some are SQLite databases, and many are proprietary binary blobs with no documentation. A *universal* save editor can't rely on knowing the format in advance.

### The Approach: Fuzzy-First, Deterministic When Known

```
┌─────────────────────────────────────────────┐
│              File Opened                     │
│                                             │
│  ┌──────────┐    ┌─────────────────────┐    │
│  │  Known   │ NO │   Fuzzy Heuristic   │    │
│  │  Format? ├───►│   Parsing Engine    │    │
│  └────┬─────┘    └──────────┬──────────┘    │
│   YES │                     │               │
│       ▼                     ▼               │
│  Deterministic         Inferred KV Map      │
│  Parser                with Confidence      │
│  (JSON/XML/INI/        Scores               │
│   SQLite/Protobuf)          │               │
│       │                     │               │
│       └─────────┬───────────┘               │
│                 ▼                            │
│        Editable Tree View                   │
│        in Slint UI                          │
└─────────────────────────────────────────────┘
```

### Fuzzy Parsing Engine

The fuzzy parser performs **structural inference** on unknown binary data:

1. **Entropy Analysis** — Detect whether regions are compressed/encrypted (high entropy) or structured data (low entropy)
2. **String Scanning** — Find UTF-8, UTF-16, null-terminated, and length-prefixed strings
3. **Numeric Scanning** — Detect i32/i64/f32/f64 values in both little-endian and big-endian
4. **Pattern Detection** — Identify repeating struct layouts, array-of-struct patterns, and alignment boundaries
5. **Confidence Scoring** — Each detected field gets a confidence percentage based on heuristic strength

The result is a **candidate key-value map** displayed in an editable tree view:

```
┌─────────────────────────────────────────────────────┐
│ 📄 save_001.sav  (2,847 bytes)                      │
├──────────┬──────────┬───────┬───────────────────────┤
│ Offset   │ Type     │ Conf. │ Label / Value          │
├──────────┼──────────┼───────┼───────────────────────┤
│ 0x0000   │ magic    │ 99%   │ "SAVE" (header)        │
│ 0x0004   │ u32 LE   │ 85%   │ 3  (version?)          │
│ 0x0008   │ str[32]  │ 92%   │ "PlayerOne"            │
│ 0x0028   │ i32 LE   │ 78%   │ 15000  (gold?)         │
│ 0x002C   │ f32 LE   │ 71%   │ 245.50  (x-pos?)       │
│ 0x0030   │ f32 LE   │ 71%   │ 1023.75 (y-pos?)       │
│ 0x0034   │ u8[48]   │ 40%   │ [raw bytes — unknown]  │
└──────────┴──────────┴───────┴───────────────────────┘
```

Users can override detected types, rename labels, and annotate fields. These annotations are persisted to SurrealDB and become **game-specific knowledge base entries** — so the fuzzy parser gets smarter over time, and known games eventually get deterministic-quality parsing.

### Safe Rewrite Strategy

Save corruption is unacceptable. The rewrite engine follows a strict protocol:

1. **Backup** — Copy original to `{filename}.sharabha.bak` before any write
2. **Shadow Write** — Write modified bytes to a temporary file
3. **Size Validation** — Assert output size matches original (fixed-size saves) or validate structural integrity (variable-size)
4. **Checksum Repair** — If the format has CRC/hash fields (identified via knowledge base), recalculate them
5. **Atomic Rename** — `MoveFileEx` with `MOVEFILE_REPLACE_EXISTING` for atomic swap

---

## Memory Engine — Design

### Capabilities

| Feature | Description |
|---|---|
| **Process List** | Enumerate running processes with PID, name, and architecture (x86/x64) |
| **Attach** | Open a process handle with full memory access |
| **Value Scan** | First scan + iterative rescan to narrow results (exact, range, increased/decreased, changed/unchanged) |
| **AOB Scan** | Array-of-bytes pattern scan with wildcard support (`48 8B ?? ?? 90`) |
| **Memory Write** | Modify values at known addresses |
| **Freeze** | Continuously write a value on a timer to lock it |
| **Pointer Scan** | Multi-level pointer chain resolution to find stable base addresses |
| **DLL Injection** | Inject custom DLLs via `CreateRemoteThread` + `LoadLibraryA` |
| **Code Injection** | Write and activate code caves / inline hooks |
| **Lua Scripting** | Automate all of the above via embedded LuaJIT scripts |

### Lua Scripting API (Planned)

The embedded LuaJIT runtime exposes the Memory Engine's core functions:

```lua
-- Attach to a process
local proc = sharabha.attach("GameName.exe")

-- Scan for a value
local results = proc:scan_value(999, "i32")

-- Filter results
results = proc:rescan_value(results, 998, "i32")

-- Write to the first result
proc:write(results[1], 999999, "i32")

-- Freeze a value
proc:freeze(results[1], 999999, "i32", 100) -- 100ms interval

-- AOB scan
local addrs = proc:aob_scan("48 8B ?? 05 ?? ?? ?? ?? 90")

-- Read a pointer chain
local value = proc:read_pointer_chain(0x00400000, {0x10, 0x28, 0x04}, "f32")
```

---

## Game Knowledge Base

The knowledge base is stored in SurrealDB (embedded) and serves as the bridge between Save Forge and Memory Engine:

### Schema

```
Game {
    id, title, engine, save_paths[], save_extensions[],
    process_name, architecture
}

SaveFormat {
    id, game_id, version, is_compressed, compression_algo,
    is_encrypted, header_size, endianness, checksum_offset,
    checksum_algo
}

FieldDef {
    id, format_id, offset, type, label, description,
    constraints, confidence_origin (fuzzy | manual | imported)
}

MemoryTable {
    id, game_id, game_version, description
}

MemoryEntry {
    id, table_id, label, address_type (static | pointer_chain),
    base_address, offsets[], value_type, description
}
```

- **Game profiles** link both save format definitions and memory tables
- **Field definitions** are created automatically by the fuzzy parser and refined manually by users
- **Memory tables** store known addresses and pointer chains for specific game versions (like Cheat Engine `.CT` files)
- Profiles can be **exported/imported** as JSON for community sharing

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                      Slint UI Layer                       │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Memory Engine │  │  Save Forge  │  │  Knowledge   │   │
│  │    Tab        │  │    Tab       │  │  Base Tab    │   │
│  │              │  │              │  │              │   │
│  │ Process List │  │ File Browser │  │ Game Profiles│   │
│  │ Scan Results │  │ Hex View     │  │ Field Editor │   │
│  │ Freeze Table │  │ KV Tree View │  │ Import/Export│   │
│  │ Script Editor│  │ Type Picker  │  │ Search       │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │            │
└─────────┼─────────────────┼─────────────────┼────────────┘
          │                 │                 │
┌─────────┼─────────────────┼─────────────────┼────────────┐
│         ▼                 ▼                 ▼            │
│                      Zig Core                            │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Memory I/O   │  │ File Parser  │  │ DB Interface │   │
│  │ Scanner      │  │ Fuzzy Engine │  │              │   │
│  │ Injector     │  │ Rewrite Eng. │  │              │   │
│  │ LuaJIT RT    │  │ Hex Engine   │  │              │   │
│  └──────────────┘  └──────────────┘  └──────┬───────┘   │
│                                             │            │
└─────────────────────────────────────────────┼────────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │   SurrealDB       │
                                    │   (Embedded)      │
                                    │                   │
                                    │ Game Profiles     │
                                    │ Save Formats      │
                                    │ Field Definitions │
                                    │ Memory Tables     │
                                    │ User Annotations  │
                                    └───────────────────┘
```

---

## Development Status & Architecture Phases

- [x] **Phase 1 — Foundation**: Zig 0.14+ scaffold with Slint 1.18+ UI integration, embedded SurrealDB, 24 FPS hardware splash cinema (Chitrapata), and ambient video loop canvas.
- [x] **Phase 2 — Memory Engine MVP**: Win32 process inquest, page traversal (`VirtualQueryEx`), SIMD value scanner (exact, range, increased, decreased), live results refresh, and Stambhana freeze daemon.
- [x] **Phase 3 — Save Forge MVP**: Dual-mode save editor, deterministic container parsers (JSON, XML, INI), Shannon entropy & Chi-Square heuristic binary inference, interactive KV editor, and MoveFileEx atomic write engine.
- [x] **Phase 4 — Scripting & Knowledge Base**: Embedded LuaJIT 2.1 C API integration, live script altar with Ashtamurti memory hooks, SurrealDB cosmic Agama graph profiles, and DPAPI-encrypted Gupta Kosha hardware vault.
- [x] **Phase 5 — Advanced Inquest & Game Overrides**: AOB wildcard pattern scanning, multi-level pointer resolution, Capcom RE Engine (`DSSS` / MurmurHash3), Mass Effect Legendary Edition, and Suzerain deterministic override containers.
- [x] **Phase 6 — Cheat Engine `.CT` & Auto-Updater (v0.4.0 - v0.4.1)**:
  - Streaming XML Cheat Engine table parser (`ct_parser.zig`) for complex nested entries, `<Offsets>`, and `<UserdefinedSymbols>`.
  - Embedded Cheat Engine Lua runtime emulation (`ce_compat.zig`).
  - Ashtamurti Built-in GitHub Auto-Updater (`tools/updater.ps1`) with interactive Markdown changelog modal, live progress stream, and seamless installer handover.
  - Zero-console process cloaking eliminating terminal window flashing during application and installer startup.
- [x] **Phase 7 — Unreal Engine 5 GVAS, Save Diff & Hardware Breakpoints (v0.5.0 - v0.5.1)**:
  - **Universal Unreal Engine 4/5 Save Parser (`माया सूत्र // Maya Sutra`)**: Zero-allocation binary parser and typed serializer (`gvas.zig`) decoding GVAS container headers, custom version GUID tables, and nested `FProperty` trees with atomic CLI mutation and 100% Curated confidence.
  - **Universal Unity Engine Save Parser (`ऐक्य सूत्र // Aikya Sutra`)**: Tri-format container parser and repacker (`unity.zig`) supporting Unity BinaryFormatter (.NET NRBF), Easy Save 2/3 (ES3 JSON), and PlayerPrefs XML with typed mutations and live diffing.
  - **Visual Save Diff & Evolution Inspector (`काल चक्र // Kala Chakra`)**: 4-byte aligned scalar clustering, GVAS, and Unity property diffing (`diff.zig`) with side-by-side comparison against automatic `.sharabha.bak` backups and 1-click forge promotion.
  - **Hardware Breakpoints & "Find What Writes" Watcher (`नेत्र दृष्टान्त // Netra Drishtanta`)**: CPU debug register (`DR0`–`DR3`, `DR7`) non-invasive write interception (`breakpoint.zig`) capturing RIP, instruction disassembly, opcodes, hit counts, and full 64-bit register dumps (`RAX..R15`, `EFLAGS`) in a split-pane modal UI.
- [x] **Phase 8 — Visual Novel & RPG Maker Parsers, `.CT` Hardening (v0.5.2)**:
  - **Ren'Py Visual Novel Save Parser (`काव्य सूत्र // Kavya Sutra`)**: `renpy.zig` decodes the `Ren'Py Save Game` header, reports pickle protocol metadata, inflates the zlib payload, and exposes a bounded typed field tree with typed getters/setters and deterministic reserialization.
  - **RPG Maker Save Parser (`माया लीला सूत्र // Maya Lila Sutra`)**: `rpgmaker.zig` detects and decodes Ruby Marshal 4.8 (`.rxdata`/`.rvdata`/`.rvdata2`), LZ-String Base64 (`.rpgsave`), and plain JSON containers, surfacing party gold, actor stats, variables, switches, and inventory. Mutations are span-surgical (gold, a single actor's level/HP/MP, one variable, one switch, one item stack) and commit atomically with a `.sharabha.bak` backup; Ruby Marshal containers are reported as read-only instead of silently discarding edits. `tools/open_dialog.ps1` wires the parser into the save-editor UI (`--parse-rpg` rows with `Gold`/`Actor2.Level`/`Variable3`/`Switch2`/`Item17` keys that round-trip through `--write-save-kv`).
  - **`.CT` loader crash elimination, encoding normalisation & atomic Slint publication**: PowerShell scripts now carry a UTF-8 BOM (Windows PowerShell 5.1 read BOM-less UTF-8 as ANSI and aborted on the first continuation byte), `tools/check_scripts.ps1` parses every script as a guard, table export publishes `src/ui/live_table.slint` via `MoveFileExW` swap, generated literals are sanitized to valid UTF-8 so `slint-viewer --auto-reload` can never observe a truncated file, UTF-8-BOM/UTF-16LE/UTF-16BE tables are transcoded before parsing, `--load-ct` exits non-zero on failure so the UI can report it, and the generated bridges are resolved against the project root so packaged `bin\Sharabha.exe` runs update the files the viewer watches.
  - **Freeze daemon disarm**: `SharabhaCli.exe --freeze-stop` terminates an armed Stambhana sentinel and clears its PID record, so no orphaned daemon can keep `SharabhaCli.exe` mapped and silently break `zig build` installs.

---

## Building

> **Prerequisites**: Zig (latest stable), Slint (Zig bindings), SurrealDB (embedded library), LuaJIT

```bash
# Clone
git clone https://github.com/indoctrinatedrecluse/Sharabha.git
cd Sharabha

# Build
zig build

# Run
zig build run
```

*Detailed build instructions will be added as the project scaffolding is set up.*

---

## License & Credits

This project is licensed under the **Apache License, Version 2.0**.  
Copyright © 2026 **Abhishek Mitra** (`indoctrinatedrecluse`).

See the [LICENSE](LICENSE) and [NOTICE](NOTICE) files for full legal details.

### Third-Party Attributions
- **SaveEditor.top**: The Ren'Py (`.save`) and RPG Maker (`.rpgsave`/`.rvdata2`) container research — header layouts, LZ-String/pickle payload framing, and field naming used to validate the Kavya Sutra and Maya Lila Sutra parsers — was cross-referenced against the open-source SaveEditor.top project by **paradoxie** ([`paradoxie/saveeditor`](https://github.com/paradoxie/saveeditor), MIT License).
- **Mass Effect Trilogy Save Editor**: The deterministic Agama save override profiles for Mass Effect Legendary Edition (MELE1, MELE2, MELE3), including UE3 serialization layouts, chunk container decompression, and CRC-32/BZIP2 integrity algorithms, are based on reverse engineering research and save models by **Karlitos** ([`KarlitosVII/trilogy-save-editor`](https://github.com/KarlitosVII/trilogy-save-editor), MIT License).
- **Dragon's Dogma 2 Content Editor**: The deterministic Agama save override profiles and variable schemas for Dragon's Dogma 2 are based on reverse engineering research and item database mappings by **kagenocookie** ([`kagenocookie/dd2-content-editor`](https://github.com/kagenocookie/dd2-content-editor), MIT License).
- **Capcom RE Engine Save Editor**: The RE Engine `DSSS` save container specifications and MurmurHash3 (32-bit) integrity verification engine are derived from reverse engineering research and tooling by **kvasszn** ([`kvasszn/ree-save-editor`](https://github.com/kvasszn/ree-save-editor), MIT License).

---

<p align="center">
  <em>"To subdue violence, one must first embody it — and then choose peace."</em><br/>
  <strong>— The Sharabha Upanishad</strong>
</p>
