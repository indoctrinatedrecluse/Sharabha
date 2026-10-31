# 🦁🐦 Sharabha

> **Sharabha** (शरभ) is the dual form of the Hindu god **Shiva** — part lion, part bird, eight-legged — manifested to subdue **Narasimha**, the ferocious lion avatar of Vishnu, and ultimately restore peace. It embodies the union of calm wisdom and devastating power: a serene aspect that resolves, and a violent aspect that overwhelms.
>
> This project carries that duality. **Save Forge** is the calm aspect — carefully parsing, understanding, and surgically editing save files with precision and safety. **Memory Engine** is the violent aspect — attaching to live processes, ripping through gigabytes of memory, injecting code, and bending a running game to your will. Together, they are Sharabha: an all-in-one game tool that is as gentle as it is destructive.

---

## What Is Sharabha?

Sharabha is a **native Windows desktop application** built on an entirely unconventional stack — **Zig**, **Slint**, and **SurrealDB** — designed as a unified game modding and cheating toolkit with two core pillars:

### 🧊 Save Forge — Universal Save Game Editor
A save game editor that doesn't need to know your game's save format ahead of time. It uses a **fuzzy heuristic parsing engine** to infer structure from raw binary data, presenting an editable key-value interface that lets you modify and safely rewrite save files for *any* game.

### 🔥 Memory Engine — Process Memory Scanner & Injector
A Cheat Engine–style memory manipulation suite with process attachment, value/AOB scanning, pointer chain resolution, memory freezing, DLL injection, and an embedded **Lua (LuaJIT)** scripting runtime for automation.

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

## Build Phases

### Phase 1 — Foundation
- Zig project scaffold with Slint UI integration
- SurrealDB embedded setup
- App shell with tab navigation (Memory Engine │ Save Forge │ Knowledge Base)
- Basic theming and window management

### Phase 2 — Memory Engine MVP
- Process enumeration and attachment
- Memory read/write primitives
- Value scanner (exact match, first scan + rescan filtering)
- Results table with live value refresh
- Simple value freeze (write-on-timer)

### Phase 3 — Save Forge MVP
- File open dialog + raw hex view
- Deterministic parser layer (JSON, XML, INI auto-detection)
- Fuzzy binary parser v1 (string + integer + float detection with confidence scoring)
- Editable KV tree view with type override
- Safe rewrite engine with backup + atomic rename

### Phase 4 — Scripting & Knowledge Base
- Embedded LuaJIT runtime integration
- Script editor panel with Lua syntax highlighting
- Lua API bindings to Memory Engine functions
- Game profile CRUD in SurrealDB
- Manual field definition and annotation UI
- Knowledge base search

### Phase 5 — Advanced Features
- AOB (array-of-bytes) pattern scanning with wildcard support
- Multi-level pointer scanner
- DLL injection via `CreateRemoteThread`
- Code cave / inline hook injection
- Fuzzy parser v2 (struct-of-array detection, repeating pattern inference, confidence tuning)
- Knowledge base import/export (JSON format for community sharing)
- Memory table save/load (`.sharabha` files, analogous to Cheat Engine `.CT` files)

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

## License

TBD

---

<p align="center">
  <em>"To subdue violence, one must first embody it — and then choose peace."</em><br/>
  <strong>— The Sharabha Upanishad</strong>
</p>
