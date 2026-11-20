//! ============================================================================
//! SHARABHA (शरभ) — CHEAT ENGINE LUA COMPATIBILITY SUBSYSTEM
//! Complete emulation layer for Cheat Engine (.CT) embedded Lua scripts.
//! Exposes standard CE globals, memory manipulators, address resolvers,
//! symbol registries, remote thread invocation (executeCodeEx), and GUI stubs.
//!
//! ॐ नमः शरभाय — The divine reconciler of foreign and native script altars.
//! ============================================================================

const std = @import("std");
const process = @import("../memory/process.zig");
const win = process.win;
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const ct_session = @import("../memory/ct_session.zig");

/// Global symbol table registry for user-defined symbols (registerSymbol / getAddress)
///
/// The registry owns its own allocator on purpose: symbols are registered from
/// table loads, Auto Assembler scripts and Lua blocks, each of which may run
/// inside a short-lived arena. Keying off the caller's allocator left dangling
/// keys/storage behind as soon as that arena was released.
var global_symbols: ?std.StringHashMap(usize) = null;

fn getSymbolMap() *std.StringHashMap(usize) {
    if (global_symbols == null) {
        global_symbols = std.StringHashMap(usize).init(std.heap.page_allocator);
    }
    return &global_symbols.?;
}

pub fn registerSymbol(name: []const u8, address: usize, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const map = getSymbolMap();
    if (map.getEntry(name)) |entry| {
        entry.value_ptr.* = address;
        return;
    }
    const key = try std.heap.page_allocator.dupe(u8, name);
    try map.put(key, address);
}

pub fn deinitSymbols() void {
    if (global_symbols) |*map| {
        var it = map.keyIterator();
        while (it.next()) |k| {
            std.heap.page_allocator.free(k.*);
        }
        map.deinit();
        global_symbols = null;
    }
}

pub fn unregisterSymbol(name: []const u8) void {
    if (global_symbols) |*map| {
        if (std.mem.eql(u8, name, "*")) {
            var it = map.keyIterator();
            while (it.next()) |k| {
                std.heap.page_allocator.free(k.*);
            }
            map.clearRetainingCapacity();
        } else if (map.fetchRemove(name)) |removed| {
            std.heap.page_allocator.free(removed.key);
        }
    }
}

pub fn lookupSymbol(name: []const u8) ?usize {
    if (global_symbols) |*map| {
        return map.get(name);
    }
    return null;
}

// ============================================================================
// BINDING PERSISTENCE
//
// Cheat Engine tables "auto-attach": their scripts call openProcess("game.exe")
// and from that moment every record resolves against that target. Sharabha's Lua
// VM only lives for the length of one CLI call, so the attach has to be written
// down: `assets/memory/active_pid.txt` for the engine and `src/ui/live_bind.slint`
// so the auto-reloading UI shows the newly hooked process.
// ============================================================================

const file_io = struct {
    const GENERIC_WRITE: u32 = 0x40000000;
    const CREATE_ALWAYS: u32 = 2;
    const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;

    pub extern "kernel32" fn CreateFileA(
        lpFileName: [*:0]const u8,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?*anyopaque,
    ) callconv(.winapi) ?*anyopaque;

    pub extern "kernel32" fn WriteFile(
        hFile: *anyopaque,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: u32,
        lpNumberOfBytesWritten: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn CreateDirectoryA(lpPathName: [*:0]const u8, lpSecurityAttributes: ?*anyopaque) callconv(.winapi) i32;
    pub extern "kernel32" fn GetCurrentDirectoryA(nBufferLength: u32, lpBuffer: [*]u8) callconv(.winapi) u32;
    pub extern "kernel32" fn GetFileAttributesA(lpFileName: [*:0]const u8) callconv(.winapi) u32;
};

fn writeTextFile(path: [*:0]const u8, text: []const u8) void {
    const handle = file_io.CreateFileA(path, file_io.GENERIC_WRITE, 3, null, file_io.CREATE_ALWAYS, file_io.FILE_ATTRIBUTE_NORMAL, null) orelse return;
    var written: u32 = 0;
    _ = file_io.WriteFile(handle, text.ptr, @intCast(text.len), &written, null);
    _ = win.CloseHandle(handle);
}

const file_read = struct {
    const GENERIC_READ: u32 = 0x80000000;
    const OPEN_EXISTING: u32 = 3;
    const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
    const INVALID_HANDLE_VALUE: *anyopaque = @ptrFromInt(std.math.maxInt(usize));

    pub extern "kernel32" fn CreateFileA(
        lpFileName: [*:0]const u8,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?*anyopaque,
    ) callconv(.winapi) ?*anyopaque;

    pub extern "kernel32" fn ReadFile(
        hFile: *anyopaque,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: u32,
        lpNumberOfBytesRead: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn GetFileSize(
        hFile: *anyopaque,
        lpFileSizeHigh: ?*u32,
    ) callconv(.winapi) u32;
};

fn readTextFile(path: [*:0]const u8, buffer: []u8) ?usize {
    const handle = file_read.CreateFileA(path, file_read.GENERIC_READ, 3, null, file_read.OPEN_EXISTING, file_read.FILE_ATTRIBUTE_NORMAL, null) orelse return null;
    var read: u32 = 0;
    const ok = file_read.ReadFile(handle, buffer.ptr, @intCast(buffer.len), &read, null);
    _ = win.CloseHandle(handle);
    if (ok == 0) return null;
    return read;
}

/// Directory that owns `assets\` and `src\ui\`. The dev layout runs with the repo
/// root as CWD; a packaged install runs from `bin\`, so the trailing `bin` is
/// stripped when the CWD has no `assets` folder of its own.
fn projectBase(buf: []u8) []const u8 {
    const cwd_len = file_io.GetCurrentDirectoryA(@intCast(buf.len), buf.ptr);
    if (cwd_len == 0 or cwd_len > buf.len) return ".";
    const cwd = buf[0..cwd_len];
    if (dirHasEntry(cwd, "assets")) return cwd;

    if (std.fs.path.dirname(cwd)) |parent| {
        if (dirHasEntry(parent, "assets")) {
            const copy_len = @min(parent.len, buf.len);
            @memcpy(buf[0..copy_len], parent[0..copy_len]);
            return buf[0..copy_len];
        }
    }
    return cwd;
}

fn zPath(buf: []u8, comptime fmt: []const u8, args: anytype) ?[:0]const u8 {
    if (buf.len < 2) return null;
    const text = std.fmt.bufPrint(buf[0 .. buf.len - 1], fmt, args) catch return null;
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

fn dirHasEntry(dir: []const u8, child: []const u8) bool {
    var tmp: [1024]u8 = undefined;
    const full = zPath(&tmp, "{s}\\{s}", .{ dir, child }) orelse return false;
    return file_io.GetFileAttributesA(full.ptr) != 0xFFFFFFFF;
}

fn buildPath(buf: []u8, relative: []const u8) ?[:0]const u8 {
    var base_buf: [1024]u8 = undefined;
    const base = projectBase(&base_buf);
    return zPath(buf, "{s}\\{s}", .{ base, relative });
}

// ============================================================================
// SYMBOL PERSISTENCE
//
// `registersymbol` / `aobscanmodule` produce addresses that the matching
// [DISABLE] section needs later ("dealloc(scratch)", "unregistersymbol(x)").
// Those sections run in a *different* CLI process, so the registry is mirrored to
// `assets/memory/ct_symbols.tsv` and rehydrated at Lua start-up.
// ============================================================================

const SYMBOLS_FILE = "assets\\memory\\ct_symbols.tsv";

pub fn persistSymbols() void {
    const map = getSymbolMap();

    var base_buf: [1024]u8 = undefined;
    const base = projectBase(&base_buf);
    ensureDir(base, "assets");
    ensureDir(base, "assets\\memory");

    var path_buf: [1200]u8 = undefined;
    const path = buildPath(&path_buf, SYMBOLS_FILE) orelse return;

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(std.heap.page_allocator);

    var it = map.iterator();
    while (it.next()) |kv| {
        text.print(std.heap.page_allocator, "{s}={X}\n", .{ kv.key_ptr.*, kv.value_ptr.* }) catch return;
        if (text.items.len > 256 * 1024) break;
    }
    writeTextFile(path.ptr, text.items);
}

fn ensureDir(base: []const u8, relative: []const u8) void {
    var tmp: [1024]u8 = undefined;
    const full = zPath(&tmp, "{s}\\{s}", .{ base, relative }) orelse return;
    _ = file_io.CreateDirectoryA(full.ptr, null);
}

pub fn loadPersistedSymbols() void {
    var path_buf: [1200]u8 = undefined;
    const path = buildPath(&path_buf, SYMBOLS_FILE) orelse return;

    const buf = std.heap.page_allocator.alloc(u8, 512 * 1024) catch return;
    defer std.heap.page_allocator.free(buf);

    const read = readTextFile(path.ptr, buf) orelse return;
    var lines = std.mem.splitScalar(u8, buf[0..read], '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\n\t");
        if (line.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = line[0..eq];
        const addr = std.fmt.parseInt(usize, line[eq + 1 ..], 16) catch continue;
        if (name.len == 0 or addr == 0) continue;
        registerSymbol(name, addr, std.heap.page_allocator) catch {};
    }
}

fn writeLiveBindSlint(pid: u32, name: []const u8) void {
    var base_buf: [1024]u8 = undefined;
    const base = projectBase(&base_buf);
    ensureDir(base, "src");
    ensureDir(base, "src\\ui");

    var buf: [512]u8 = undefined;
    var safe: [96]u8 = undefined;
    var safe_len: usize = 0;
    for (name) |ch| {
        if (safe_len >= safe.len) break;
        if (ch == '"' or ch == '\\') {
            safe[safe_len] = '_';
        } else {
            safe[safe_len] = ch;
        }
        safe_len += 1;
    }

    const text = std.fmt.bufPrint(
        &buf,
        "// Auto-generated by Sharabha Rudra Tandava Memory Inquest Engine\n" ++
            "// Bound target process (Netra Bandhana)\n" ++
            "export global LiveBind {{\n" ++
            "    in property <int> pid: {d};\n" ++
            "    in property <string> name: \"{s}\";\n" ++
            "    in property <bool> bound: {s};\n" ++
            "}}\n",
        .{ pid, safe[0..safe_len], if (pid != 0) "true" else "false" },
    ) catch return;

    var path_buf: [1200]u8 = undefined;
    const path = buildPath(&path_buf, "src\\ui\\live_bind.slint") orelse return;
    writeTextFile(path.ptr, text);
}

/// Persists an attach performed by `openProcess()` / `getProcessIDFromProcessName`.
fn persistBinding(pid: u32, name: []const u8) void {
    var base_buf: [1024]u8 = undefined;
    const base = projectBase(&base_buf);
    ensureDir(base, "assets");
    ensureDir(base, "assets\\memory");
    ensureDir(base, "src");
    ensureDir(base, "src\\ui");

    var path_buf: [1200]u8 = undefined;

    if (pid == 0) {
        if (buildPath(&path_buf, "assets\\memory\\active_pid.txt")) |path| writeTextFile(path.ptr, "0\n");
        writeLiveBindSlint(0, "");
        return;
    }

    var pid_buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&pid_buf, "{d}\n", .{pid}) catch return;
    if (buildPath(&path_buf, "assets\\memory\\active_pid.txt")) |path| writeTextFile(path.ptr, text);

    var name_buf: [260]u8 = undefined;
    var name_len: usize = 0;
    var iter = process.ProcessIterator.init() catch {
        writeLiveBindSlint(pid, name);
        return;
    };
    defer iter.deinit();
    while (iter.next()) |p| {
        if (p.pid != pid) continue;
        @memcpy(name_buf[0..p.name_len], p.getName());
        name_len = p.name_len;
        break;
    }
    writeLiveBindSlint(pid, if (name_len > 0) name_buf[0..name_len] else name);
}

/// Resolves an address or expression like "14023A10", "bg3.exe+0x24A266F", or "movedPtr"
pub fn resolveAddress(
    engine: *engine_mod.ScriptEngine,
    expr: []const u8,
) ?usize {
    const trimmed = std.mem.trim(u8, expr, " \"'\r\n\t");
    if (trimmed.len == 0) return null;

    // 1. Direct hex or decimal number
    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return std.fmt.parseInt(usize, trimmed[2..], 16) catch null;
    }

    var is_pure_dec = true;
    for (trimmed) |ch| {
        if (ch < '0' or ch > '9') {
            is_pure_dec = false;
            break;
        }
    }
    if (is_pure_dec and trimmed.len < 16) {
        if (std.fmt.parseInt(usize, trimmed, 10)) |val| {
            return val;
        } else |_| {}
    }

    // 2. Lookup in registered symbols
    if (lookupSymbol(trimmed)) |sym_addr| {
        return sym_addr;
    }

    // 3. Module offset expression e.g. "bg3.exe+24A266F" or "game.exe+0x100"
    if (std.mem.indexOf(u8, trimmed, "+")) |plus_idx| {
        const mod_name = std.mem.trim(u8, trimmed[0..plus_idx], " \"'");
        const off_str = std.mem.trim(u8, trimmed[plus_idx + 1 ..], " \"'");
        const offset = if (std.mem.startsWith(u8, off_str, "0x") or std.mem.startsWith(u8, off_str, "0X"))
            std.fmt.parseInt(usize, off_str[2..], 16) catch 0
        else
            std.fmt.parseInt(usize, off_str, 16) catch (std.fmt.parseInt(usize, off_str, 10) catch 0);

        // Check if left side is a registered symbol
        if (lookupSymbol(mod_name)) |base| {
            return base + offset;
        }

        // Check if left side is a loaded module in the attached process
        if (engine.target_pid != 0) {
            var mod_iter = process.ModuleIterator.init(engine.target_pid) catch return null;
            defer mod_iter.deinit();

            while (mod_iter.next()) |me| {
                if (std.ascii.eqlIgnoreCase(me.getName(), mod_name) or
                    std.mem.eql(u8, mod_name, "$process"))
                {
                    return me.base_address + offset;
                }
            }
        }
        return null;
    }

    // 4. Try parsing as hex string without prefix (e.g. "7FF74A8014E0" or "14023A10")
    if (std.fmt.parseInt(usize, trimmed, 16)) |hex_val| {
        return hex_val;
    } else |_| {}

    // 5. Bare module name (e.g. "eldenring.exe" -> module base address)
    if (engine.target_pid != 0) {
        var mod_iter = process.ModuleIterator.init(engine.target_pid) catch return null;
        defer mod_iter.deinit();

        while (mod_iter.next()) |me| {
            if (std.ascii.eqlIgnoreCase(me.getName(), trimmed)) {
                return me.base_address;
            }
        }
    }

    return null;
}

/// Helper to get numeric address from Lua argument (supports both integer and string symbol)
fn getAddressFromLua(L: ?*c.lua_State, idx: c_int, engine: *engine_mod.ScriptEngine) ?usize {
    const l = L orelse return null;
    const ltype = c.lua_type(l, idx);
    if (ltype == c.LUA_TNUMBER) {
        return @as(usize, @intCast(c.lua_tointeger(l, idx)));
    } else if (ltype == c.LUA_TSTRING) {
        const s = engine_mod.luaToString(l, idx) orelse return null;
        return resolveAddress(engine, s);
    }
    return null;
}

// ============================================================================
// CHEAT ENGINE LUA API IMPLEMENTATIONS
// ============================================================================

fn ceOpenProcess(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;

    const ltype = c.lua_type(l, 1);
    var target_pid: u32 = 0;

    if (ltype == c.LUA_TNUMBER) {
        target_pid = @as(u32, @intCast(c.lua_tointeger(l, 1)));
    } else if (ltype == c.LUA_TSTRING) {
        const name = engine_mod.luaToString(l, 1) orelse "";
        var iter = process.ProcessIterator.init() catch {
            c.lua_pushboolean(l, 0);
            return 1;
        };
        defer iter.deinit();

        while (iter.next()) |pe| {
            if (std.ascii.eqlIgnoreCase(pe.getName(), name)) {
                target_pid = pe.pid;
                break;
            }
        }
    }

    if (target_pid != 0) {
        inst.attach(target_pid) catch {
            c.lua_pushboolean(l, 0);
            return 1;
        };
        // Cheat Engine keeps the newly opened process for the whole table; the
        // CLI process is short-lived, so record it for the engine and the UI.
        persistBinding(target_pid, name_for_binding(target_pid));
        c.lua_pushboolean(l, 1);
        return 1;
    }

    c.lua_pushboolean(l, 0);
    return 1;
}

/// Process name used in `live_bind.slint`; empty when the PID vanished.
fn name_for_binding(pid: u32) []const u8 {
    _ = pid;
    return "";
}

fn ceTargetIs64Bit(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_pushboolean(l, 1);
    return 1;
}

/// `getProcessList()` — array of `{ pid, Name, ProcessName }` entries, enough for
/// the auto-attach loops published tables use (`for i=1,#list do ...`).
fn ceGetProcessList(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_newtable(l);

    var iter = process.ProcessIterator.init() catch return 1;
    defer iter.deinit();

    var index: c.lua_Integer = 0;
    while (iter.next()) |entry| {
        if (entry.pid <= 4) continue;
        index += 1;
        const name = entry.getName();

        c.lua_newtable(l);
        c.lua_pushinteger(l, @as(c.lua_Integer, entry.pid));
        c.lua_setfield(l, -2, "pid");
        c.lua_pushinteger(l, @as(c.lua_Integer, entry.pid));
        c.lua_setfield(l, -2, "ProcessID");
        c.lua_pushlstring(l, name.ptr, name.len);
        c.lua_setfield(l, -2, "Name");
        c.lua_pushlstring(l, name.ptr, name.len);
        c.lua_setfield(l, -2, "ProcessName");

        c.lua_rawseti(l, -2, @intCast(index));
        if (index >= 4096) break;
    }

    return 1;
}

/// `AOBScan(pattern)` — returns `"ADDRESS"` (or nil) like Cheat Engine.
fn ceAobScan(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const pattern = engine_mod.luaToString(l, 1) orelse {
        c.lua_pushnil(l);
        return 1;
    };
    if (inst.target_pid == 0) {
        c.lua_pushnil(l);
        return 1;
    }

    const aa_interp = @import("../memory/aa_interp.zig");
    var proc = process.ProcessHandle.open(inst.target_pid) catch {
        c.lua_pushnil(l);
        return 1;
    };
    defer proc.close();

    const hit = aa_interp.scanProcessPattern(inst.allocator, &proc, pattern) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{X}", .{hit.address}) catch {
        c.lua_pushnil(l);
        return 1;
    };
    c.lua_pushlstring(l, text.ptr, text.len);
    return 1;
}

/// `AOBScanModule(pattern, module)` — module-scoped signature scan.
fn ceAobScanModule(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const pattern = engine_mod.luaToString(l, 1) orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const module = engine_mod.luaToString(l, 2) orelse "$process";
    if (inst.target_pid == 0) {
        c.lua_pushnil(l);
        return 1;
    }

    const aa_interp = @import("../memory/aa_interp.zig");
    var proc = process.ProcessHandle.open(inst.target_pid) catch {
        c.lua_pushnil(l);
        return 1;
    };
    defer proc.close();

    const hit = aa_interp.scanModulePattern(inst.allocator, &proc, module, pattern) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{X}", .{hit.address}) catch {
        c.lua_pushnil(l);
        return 1;
    };
    c.lua_pushlstring(l, text.ptr, text.len);
    return 1;
}

/// `showMessage(text)` — CE surfaces it as a dialog; we route it to the Lua log.
fn ceShowMessage(L: ?*c.lua_State) callconv(.c) c_int {
    return ceMessageDialog(L);
}

fn ceGetProcessIDFromProcessName(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const name = engine_mod.luaToString(l, 1) orelse "";

    var iter = process.ProcessIterator.init() catch {
        c.lua_pushnil(l);
        return 1;
    };
    defer iter.deinit();

    while (iter.next()) |pe| {
        if (std.ascii.eqlIgnoreCase(pe.getName(), name)) {
            c.lua_pushinteger(l, @as(c.lua_Integer, pe.pid));
            return 1;
        }
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceGetOpenedProcessID(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushinteger(l, 0);
        return 1;
    };
    c.lua_pushinteger(l, @as(c.lua_Integer, inst.target_pid));
    return 1;
}

fn ceGetAddress(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;

    const addr = getAddressFromLua(l, 1, inst);
    if (addr) |a| {
        c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(a)));
        return 1;
    }

    c.lua_pushinteger(l, 0);
    return 1;
}

fn ceGetAddressSafe(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;

    const addr = getAddressFromLua(l, 1, inst);
    if (addr) |a| {
        c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(a)));
        return 1;
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceRegisterSymbol(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;

    const name = engine_mod.luaToString(l, 1) orelse return 0;
    const addr = getAddressFromLua(l, 2, inst) orelse 0;

    registerSymbol(name, addr, inst.allocator) catch {};
    c.lua_pushboolean(l, 1);
    return 1;
}

fn ceUnregisterSymbol(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const name = engine_mod.luaToString(l, 1) orelse return 0;

    unregisterSymbol(name);
    c.lua_pushboolean(l, 1);
    return 1;
}

fn ceReadInteger(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var val: i32 = 0;
    var bytes_read: usize = 0;
    const ok = win.ReadProcessMemory(
        h,
        @as(?*const anyopaque, @ptrFromInt(addr)),
        @as(*anyopaque, @ptrCast(&val)),
        @sizeOf(i32),
        &bytes_read,
    );

    if (ok != 0 and bytes_read == @sizeOf(i32)) {
        c.lua_pushinteger(l, @as(c.lua_Integer, val));
        return 1;
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceWriteInteger(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const val = @as(i32, @intCast(c.lua_tointeger(l, 2)));

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(&val)),
        @sizeOf(i32),
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0 and bytes_written == @sizeOf(i32)) 1 else 0);
    return 1;
}

fn ceReadQword(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var val: u64 = 0;
    var bytes_read: usize = 0;
    const ok = win.ReadProcessMemory(
        h,
        @as(?*const anyopaque, @ptrFromInt(addr)),
        @as(*anyopaque, @ptrCast(&val)),
        @sizeOf(u64),
        &bytes_read,
    );

    if (ok != 0 and bytes_read == @sizeOf(u64)) {
        c.lua_pushnumber(l, @as(f64, @floatFromInt(val)));
        return 1;
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceWriteQword(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };

    const val = if (c.lua_type(l, 2) == c.LUA_TNUMBER)
        @as(u64, @intFromFloat(c.lua_tonumber(l, 2)))
    else
        @as(u64, @intCast(c.lua_tointeger(l, 2)));

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(&val)),
        @sizeOf(u64),
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0 and bytes_written == @sizeOf(u64)) 1 else 0);
    return 1;
}

fn ceReadFloat(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var val: f32 = 0;
    var bytes_read: usize = 0;
    const ok = win.ReadProcessMemory(
        h,
        @as(?*const anyopaque, @ptrFromInt(addr)),
        @as(*anyopaque, @ptrCast(&val)),
        @sizeOf(f32),
        &bytes_read,
    );

    if (ok != 0 and bytes_read == @sizeOf(f32)) {
        c.lua_pushnumber(l, @as(f64, val));
        return 1;
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceWriteFloat(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const val = @as(f32, @floatCast(c.lua_tonumber(l, 2)));

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(&val)),
        @sizeOf(f32),
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0 and bytes_written == @sizeOf(f32)) 1 else 0);
    return 1;
}

fn ceReadDouble(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushnil(l);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushnil(l);
        return 1;
    };

    var val: f64 = 0;
    var bytes_read: usize = 0;
    const ok = win.ReadProcessMemory(
        h,
        @as(?*const anyopaque, @ptrFromInt(addr)),
        @as(*anyopaque, @ptrCast(&val)),
        @sizeOf(f64),
        &bytes_read,
    );

    if (ok != 0 and bytes_read == @sizeOf(f64)) {
        c.lua_pushnumber(l, val);
        return 1;
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceWriteDouble(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const val = c.lua_tonumber(l, 2);

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(&val)),
        @sizeOf(f64),
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0 and bytes_written == @sizeOf(f64)) 1 else 0);
    return 1;
}

fn ceReadString(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushstring(l, "");
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushstring(l, "");
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushstring(l, "");
        return 1;
    };

    const max_len = if (c.lua_gettop(l) >= 2 and c.lua_isnumber(l, 2) != 0)
        @as(usize, @intCast(@max(1, c.lua_tointeger(l, 2))))
    else
        256;

    const is_wide = if (c.lua_gettop(l) >= 3)
        (c.lua_toboolean(l, 3) != 0)
    else
        false;

    if (is_wide) {
        var wbuf: [512]u16 = undefined;
        const read_count = @min(max_len, wbuf.len);
        var bytes_read: usize = 0;
        const ok = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&wbuf)),
            read_count * @sizeOf(u16),
            &bytes_read,
        );

        if (ok != 0 and bytes_read > 0) {
            const num_chars = bytes_read / @sizeOf(u16);
            var len: usize = 0;
            while (len < num_chars and wbuf[len] != 0) : (len += 1) {}

            var utf8_buf: [1024]u8 = undefined;
            const u8_len = std.unicode.utf16LeToUtf8(&utf8_buf, wbuf[0..len]) catch 0;
            _ = c.lua_pushlstring(l, &utf8_buf, u8_len);
            return 1;
        }
    } else {
        var buf: [1024]u8 = undefined;
        const read_count = @min(max_len, buf.len);
        var bytes_read: usize = 0;
        const ok = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&buf)),
            read_count,
            &bytes_read,
        );

        if (ok != 0 and bytes_read > 0) {
            var len: usize = 0;
            while (len < bytes_read and buf[len] != 0) : (len += 1) {}
            _ = c.lua_pushlstring(l, &buf, len);
            return 1;
        }
    }

    c.lua_pushstring(l, "");
    return 1;
}

fn ceWriteString(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };

    var len: usize = 0;
    const ptr = c.lua_tolstring(l, 2, &len);
    if (ptr == null) {
        c.lua_pushboolean(l, 0);
        return 1;
    }

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(ptr.?)),
        len + 1, // Include null terminator
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0) 1 else 0);
    return 1;
}

fn ceReadBytes(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse {
        c.lua_pushstring(l, "");
        return 1;
    };
    const h = inst.process_handle orelse {
        c.lua_pushstring(l, "");
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushstring(l, "");
        return 1;
    };

    const count = if (c.lua_gettop(l) >= 2) @as(usize, @intCast(@max(1, c.lua_tointeger(l, 2)))) else 1;
    const return_table = if (c.lua_gettop(l) >= 3) (c.lua_toboolean(l, 3) != 0) else (count > 1);

    var buf: [512]u8 = undefined;
    const read_len = @min(count, buf.len);
    var bytes_read: usize = 0;
    const ok = win.ReadProcessMemory(
        h,
        @as(?*const anyopaque, @ptrFromInt(addr)),
        @as(*anyopaque, @ptrCast(&buf)),
        read_len,
        &bytes_read,
    );

    if (ok == 0 or bytes_read == 0) {
        c.lua_pushnil(l);
        return 1;
    }

    if (!return_table and bytes_read == 1) {
        c.lua_pushinteger(l, buf[0]);
        return 1;
    }

    c.lua_createtable(l, @as(c_int, @intCast(bytes_read)), 0);
    for (buf[0..bytes_read], 0..) |b, i| {
        c.lua_pushinteger(l, b);
        c.lua_rawseti(l, -2, @as(c_int, @intCast(i + 1)));
    }
    return 1;
}

fn ceWriteBytes(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };
    const addr = getAddressFromLua(l, 1, inst) orelse {
        c.lua_pushboolean(l, 0);
        return 1;
    };

    var bytes: [256]u8 = undefined;
    var byte_count: usize = 0;

    const top = c.lua_gettop(l);
    if (top == 2 and c.lua_istable(l, 2)) {
        const table_len = c.lua_objlen(l, 2);
        var i: usize = 1;
        while (i <= table_len and byte_count < bytes.len) : (i += 1) {
            c.lua_rawgeti(l, 2, @as(c_int, @intCast(i)));
            bytes[byte_count] = @as(u8, @intCast(c.lua_tointeger(l, -1) & 0xFF));
            c.lua_settop(l, -2);
            byte_count += 1;
        }
    } else {
        var i: c_int = 2;
        while (i <= top and byte_count < bytes.len) : (i += 1) {
            bytes[byte_count] = @as(u8, @intCast(c.lua_tointeger(l, i) & 0xFF));
            byte_count += 1;
        }
    }

    if (byte_count == 0) {
        c.lua_pushboolean(l, 1);
        return 1;
    }

    var bytes_written: usize = 0;
    const ok = win.WriteProcessMemory(
        h,
        @as(?*anyopaque, @ptrFromInt(addr)),
        @as(*const anyopaque, @ptrCast(&bytes)),
        byte_count,
        &bytes_written,
    );

    c.lua_pushboolean(l, if (ok != 0 and bytes_written == byte_count) 1 else 0);
    return 1;
}

/// Executes a function in the remote process: executeCodeEx(threadSync, timeout, funcAddr, [args...])
fn ceExecuteCodeEx(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const h = inst.process_handle orelse {
        c.lua_pushinteger(l, 0);
        return 1;
    };

    // arg 1: threadSync (0 = false, 1 = true)
    // arg 2: timeout (nil or ms)
    // arg 3: funcAddress
    const timeout_ms: u32 = if (c.lua_isnumber(l, 2) != 0)
        @as(u32, @intCast(c.lua_tointeger(l, 2)))
    else
        5000;

    const func_addr = getAddressFromLua(l, 3, inst) orelse {
        c.lua_pushinteger(l, 0);
        return 1;
    };

    var param_val: usize = 0;
    if (c.lua_gettop(l) >= 4) {
        param_val = getAddressFromLua(l, 4, inst) orelse 0;
    }

    var thread_id: u32 = 0;
    const hThread = win.CreateRemoteThread(
        h,
        null,
        0,
        @as(?*anyopaque, @ptrFromInt(func_addr)),
        @as(?*anyopaque, @ptrFromInt(param_val)),
        0,
        &thread_id,
    ) orelse {
        c.lua_pushinteger(l, 0);
        return 1;
    };
    defer _ = win.CloseHandle(hThread);

    const wait_res = win.WaitForSingleObject(hThread, timeout_ms);
    if (wait_res == win.WAIT_TIMEOUT) {
        c.lua_pushinteger(l, 0);
        return 1;
    }

    var exit_code: u32 = 0;
    const GetExitCodeThread_fn = struct {
        pub extern "kernel32" fn GetExitCodeThread(hTr: win.HANDLE, lpExitCode: *u32) callconv(.winapi) i32;
    }.GetExitCodeThread;

    _ = GetExitCodeThread_fn(hThread, &exit_code);
    c.lua_pushinteger(l, @as(c.lua_Integer, exit_code));
    return 1;
}

fn ceSleep(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const ms = if (c.lua_gettop(l) >= 1) @as(u32, @intCast(@max(0, c.lua_tointeger(l, 1)))) else 100;
    const Sleep_fn = struct {
        pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
    }.Sleep;
    Sleep_fn(ms);
    return 0;
}

fn ceMessageDialog(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance orelse return 0;
    const msg = engine_mod.luaToString(l, 1) orelse "";

    inst.output_log.appendSlice(inst.allocator, "💬 [CE Dialog]: ") catch {};
    inst.output_log.appendSlice(inst.allocator, msg) catch {};
    inst.output_log.appendSlice(inst.allocator, "\n") catch {};
    return 0;
}

fn cePrepareCall(L: ?*c.lua_State) callconv(.c) c_int {
    _ = L;
    return 0; // BG3.CT PrepareCall dummy
}

fn ceGetMainForm(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_newtable(l);

    // Add dummy Splitter1, Panel4, Panel5
    c.lua_newtable(l);
    c.lua_setfield(l, -2, "Splitter1");
    c.lua_newtable(l);
    c.lua_setfield(l, -2, "Panel4");
    c.lua_newtable(l);
    c.lua_setfield(l, -2, "Panel5");

    // Add Menu table
    c.lua_newtable(l);
    c.lua_newtable(l);
    c.lua_pushcclosure(l, dummyNoop, 0);
    c.lua_setfield(l, -2, "add");
    c.lua_setfield(l, -2, "Items");
    c.lua_setfield(l, -2, "Menu");

    return 1;
}

fn ceCreateMenuItem(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_newtable(l);
    c.lua_pushstring(l, "MenuItem");
    c.lua_setfield(l, -2, "Caption");
    return 1;
}

fn loadLiveSession(allocator: std.mem.Allocator) ?ct_session.Session {
    var path_buf: [1200]u8 = undefined;
    const path = buildPath(&path_buf, "assets\\tables\\ct_session.tsv") orelse return null;

    const handle = file_read.CreateFileA(path.ptr, file_read.GENERIC_READ, 3, null, file_read.OPEN_EXISTING, file_read.FILE_ATTRIBUTE_NORMAL, null) orelse return null;
    defer _ = win.CloseHandle(handle);

    var high: u32 = 0;
    const size = file_read.GetFileSize(handle, &high);
    if (size == 0xFFFFFFFF or size == 0) return null;

    const text = allocator.alloc(u8, size) catch return null;
    defer allocator.free(text);
    var bytes_read: u32 = 0;
    if (file_read.ReadFile(handle, text.ptr, size, &bytes_read, null) == 0 or bytes_read != size) return null;

    var session = ct_session.Session.init(allocator) catch return null;
    session.deserialize(text) catch {
        session.deinit();
        return null;
    };
    return session;
}

fn findSessionRowByID(session: *const ct_session.Session, id: u32) ?*const ct_session.Row {
    for (session.rows.items) |*row| {
        if (row.ce_id == id) return row;
    }
    return null;
}

fn findSessionRowByDescription(session: *const ct_session.Session, desc: []const u8) ?*const ct_session.Row {
    for (session.rows.items) |*row| {
        if (std.ascii.eqlIgnoreCase(row.description, desc)) return row;
    }
    for (session.rows.items) |*row| {
        if (ct_session.containsIgnoreCase(row.description, desc)) return row;
    }
    return null;
}

fn resolveRowAddress(row: *const ct_session.Row, inst: ?*engine_mod.ScriptEngine) usize {
    if (inst) |engine| {
        if (row.addr_expr.len > 0) {
            if (resolveAddress(engine, row.addr_expr)) |addr| {
                return addr;
            }
        }
    }
    var clean_addr = std.mem.trim(u8, row.address, " \t\r\n");
    if (std.mem.indexOf(u8, clean_addr, " ->")) |arrow_idx| {
        clean_addr = clean_addr[0..arrow_idx];
    }
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        return std.fmt.parseInt(usize, clean_addr[2..], 16) catch 0;
    }
    return std.fmt.parseInt(usize, clean_addr, 16) catch 0;
}

// MemoryRecord method implementations
fn mrGetDescription(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "Description");
    return 1;
}

fn mrSetDescription(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    if (c.lua_gettop(l) >= 2) {
        c.lua_pushvalue(l, 2);
        c.lua_setfield(l, 1, "Description");
    }
    return 0;
}

fn mrGetAddress(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "Address");
    return 1;
}

fn mrSetAddress(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    if (c.lua_gettop(l) >= 2) {
        c.lua_pushvalue(l, 2);
        c.lua_setfield(l, 1, "Address");
    }
    return 0;
}

fn mrGetValue(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "Value");
    return 1;
}

fn mrSetValue(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    if (c.lua_gettop(l) >= 2) {
        c.lua_pushvalue(l, 2);
        c.lua_setfield(l, 1, "Value");
    }
    return 0;
}

fn mrGetActive(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "Active");
    return 1;
}

fn mrSetActive(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    if (c.lua_gettop(l) >= 2) {
        c.lua_pushvalue(l, 2);
        c.lua_setfield(l, 1, "Active");
    }
    return 0;
}

fn mrGetCurrentAddress(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "CurrentAddress");
    return 1;
}

fn mrGetID(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_getfield(l, 1, "ID");
    return 1;
}

fn pushMemoryRecordTable(l: *c.lua_State, row: *const ct_session.Row, inst: ?*engine_mod.ScriptEngine) void {
    const resolved_addr = resolveRowAddress(row, inst);
    c.lua_newtable(l);

    c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(row.ce_id)));
    c.lua_setfield(l, -2, "ID");

    c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(row.seq)));
    c.lua_setfield(l, -2, "Index");

    c.lua_pushlstring(l, row.description.ptr, row.description.len);
    c.lua_setfield(l, -2, "Description");

    c.lua_pushlstring(l, row.addr_expr.ptr, row.addr_expr.len);
    c.lua_setfield(l, -2, "Address");

    c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(resolved_addr)));
    c.lua_setfield(l, -2, "CurrentAddress");

    c.lua_pushlstring(l, row.value.ptr, row.value.len);
    c.lua_setfield(l, -2, "Value");

    c.lua_pushboolean(l, if (row.script_active or row.is_frozen) 1 else 0);
    c.lua_setfield(l, -2, "Active");

    c.lua_pushlstring(l, row.val_type.ptr, row.val_type.len);
    c.lua_setfield(l, -2, "Type");
    c.lua_pushlstring(l, row.val_type.ptr, row.val_type.len);
    c.lua_setfield(l, -2, "VarType");

    // Methods
    c.lua_pushcclosure(l, mrGetDescription, 0);
    c.lua_setfield(l, -2, "getDescription");
    c.lua_pushcclosure(l, mrSetDescription, 0);
    c.lua_setfield(l, -2, "setDescription");

    c.lua_pushcclosure(l, mrGetAddress, 0);
    c.lua_setfield(l, -2, "getAddress");
    c.lua_pushcclosure(l, mrSetAddress, 0);
    c.lua_setfield(l, -2, "setAddress");

    c.lua_pushcclosure(l, mrGetValue, 0);
    c.lua_setfield(l, -2, "getValue");
    c.lua_pushcclosure(l, mrSetValue, 0);
    c.lua_setfield(l, -2, "setValue");

    c.lua_pushcclosure(l, mrGetActive, 0);
    c.lua_setfield(l, -2, "getActive");
    c.lua_pushcclosure(l, mrSetActive, 0);
    c.lua_setfield(l, -2, "setActive");

    c.lua_pushcclosure(l, mrGetCurrentAddress, 0);
    c.lua_setfield(l, -2, "getCurrentAddress");

    c.lua_pushcclosure(l, mrGetID, 0);
    c.lua_setfield(l, -2, "getID");
}

fn ceGetAddressList(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance;

    c.lua_newtable(l);

    c.lua_pushcclosure(l, ceGetMemoryRecordByID, 0);
    c.lua_setfield(l, -2, "getMemoryRecordByID");

    c.lua_pushcclosure(l, ceGetMemoryRecordByDescription, 0);
    c.lua_setfield(l, -2, "getMemoryRecordByDescription");

    c.lua_pushcclosure(l, ceGetMemoryRecordByIndex, 0);
    c.lua_setfield(l, -2, "getMemoryRecord");

    c.lua_pushcclosure(l, ceGetAddressListCount, 0);
    c.lua_setfield(l, -2, "getCount");

    var count: usize = 0;
    if (loadLiveSession(std.heap.page_allocator)) |*session_val| {
        var s = session_val.*;
        defer s.deinit();
        count = s.rows.items.len;

        const cap = @min(count, 512);
        for (s.rows.items[0..cap], 0..) |*row, i| {
            c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(i)));
            pushMemoryRecordTable(l, row, inst);
            c.lua_settable(l, -3);
        }
    }

    c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(count)));
    c.lua_setfield(l, -2, "Count");

    return 1;
}

fn ceGetMemoryRecordByID(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance;

    var arg_idx: c_int = 1;
    if (c.lua_istable(l, 1) and c.lua_gettop(l) >= 2) {
        arg_idx = 2;
    }
    const target_id = @as(u32, @intCast(@max(0, c.lua_tointeger(l, arg_idx))));

    if (loadLiveSession(std.heap.page_allocator)) |*session_val| {
        var s = session_val.*;
        defer s.deinit();

        if (findSessionRowByID(&s, target_id)) |row| {
            pushMemoryRecordTable(l, row, inst);
            return 1;
        }
    }

    // Fallback: return a default record table with CurrentAddress = 0 to prevent nil crashes
    c.lua_newtable(l);
    c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(target_id)));
    c.lua_setfield(l, -2, "ID");
    c.lua_pushinteger(l, 0);
    c.lua_setfield(l, -2, "CurrentAddress");
    c.lua_pushstring(l, "");
    c.lua_setfield(l, -2, "Description");
    c.lua_pushstring(l, "");
    c.lua_setfield(l, -2, "Address");
    c.lua_pushstring(l, "???");
    c.lua_setfield(l, -2, "Value");
    c.lua_pushboolean(l, 0);
    c.lua_setfield(l, -2, "Active");
    c.lua_pushstring(l, "4 Bytes");
    c.lua_setfield(l, -2, "Type");
    c.lua_pushstring(l, "4 Bytes");
    c.lua_setfield(l, -2, "VarType");

    // Methods
    c.lua_pushcclosure(l, mrGetDescription, 0);
    c.lua_setfield(l, -2, "getDescription");
    c.lua_pushcclosure(l, mrSetDescription, 0);
    c.lua_setfield(l, -2, "setDescription");
    c.lua_pushcclosure(l, mrGetAddress, 0);
    c.lua_setfield(l, -2, "getAddress");
    c.lua_pushcclosure(l, mrSetAddress, 0);
    c.lua_setfield(l, -2, "setAddress");
    c.lua_pushcclosure(l, mrGetValue, 0);
    c.lua_setfield(l, -2, "getValue");
    c.lua_pushcclosure(l, mrSetValue, 0);
    c.lua_setfield(l, -2, "setValue");
    c.lua_pushcclosure(l, mrGetActive, 0);
    c.lua_setfield(l, -2, "getActive");
    c.lua_pushcclosure(l, mrSetActive, 0);
    c.lua_setfield(l, -2, "setActive");
    c.lua_pushcclosure(l, mrGetCurrentAddress, 0);
    c.lua_setfield(l, -2, "getCurrentAddress");
    c.lua_pushcclosure(l, mrGetID, 0);
    c.lua_setfield(l, -2, "getID");
    return 1;
}

fn ceGetMemoryRecordByDescription(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance;

    var arg_idx: c_int = 1;
    if (c.lua_istable(l, 1) and c.lua_gettop(l) >= 2) {
        arg_idx = 2;
    }
    const target_desc = engine_mod.luaToString(l, arg_idx) orelse "";

    if (loadLiveSession(std.heap.page_allocator)) |*session_val| {
        var s = session_val.*;
        defer s.deinit();

        if (findSessionRowByDescription(&s, target_desc)) |row| {
            pushMemoryRecordTable(l, row, inst);
            return 1;
        }
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceGetMemoryRecordByIndex(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    const inst = engine_mod.ScriptEngine.active_instance;

    var arg_idx: c_int = 1;
    if (c.lua_istable(l, 1) and c.lua_gettop(l) >= 2) {
        arg_idx = 2;
    }
    const target_idx = @as(usize, @intCast(@max(0, c.lua_tointeger(l, arg_idx))));

    if (loadLiveSession(std.heap.page_allocator)) |*session_val| {
        var s = session_val.*;
        defer s.deinit();

        if (target_idx < s.rows.items.len) {
            pushMemoryRecordTable(l, &s.rows.items[target_idx], inst);
            return 1;
        }
    }

    c.lua_pushnil(l);
    return 1;
}

fn ceGetAddressListCount(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    if (c.lua_istable(l, 1)) {
        c.lua_getfield(l, 1, "Count");
        return 1;
    }
    c.lua_pushinteger(l, 0);
    return 1;
}

fn dummyNoop(L: ?*c.lua_State) callconv(.c) c_int {
    _ = L;
    return 0;
}

// ============================================================================
// REGISTRATION ENTRYPOINT
// ============================================================================

pub fn registerCeCompatibility(engine: *engine_mod.ScriptEngine) void {
    const L = engine.L orelse return;

    // Rehydrate symbols produced by earlier runs: the [DISABLE] half of a script
    // ("dealloc(scratch)", "unregistersymbol(x)") runs in a later process and
    // needs the addresses the [ENABLE] half allocated.
    loadPersistedSymbols();

    // 1. Set global `syntaxcheck = false`
    c.lua_pushboolean(L, 0);
    c.lua_setglobal(L, "syntaxcheck");

    // 2. Set global `process = "active"`
    c.lua_pushstring(L, "active");
    c.lua_setglobal(L, "process");

    // 3. Process & PID functions
    c.lua_pushcclosure(L, ceOpenProcess, 0);
    c.lua_setglobal(L, "openProcess");
    c.lua_pushcclosure(L, ceOpenProcess, 0);
    c.lua_setglobal(L, "OpenProcess");

    c.lua_pushcclosure(L, ceGetProcessIDFromProcessName, 0);
    c.lua_setglobal(L, "getProcessIDFromProcessName");
    c.lua_pushcclosure(L, ceGetProcessIDFromProcessName, 0);
    c.lua_setglobal(L, "GetProcessIDFromProcessName");

    c.lua_pushcclosure(L, ceGetOpenedProcessID, 0);
    c.lua_setglobal(L, "getOpenedProcessID");

    // 4. Address resolution & Symbols
    c.lua_pushcclosure(L, ceGetAddress, 0);
    c.lua_setglobal(L, "getAddress");
    c.lua_pushcclosure(L, ceGetAddressSafe, 0);
    c.lua_setglobal(L, "getAddressSafe");
    c.lua_pushcclosure(L, ceGetAddressSafe, 0);
    c.lua_setglobal(L, "GetAddressSafe");

    c.lua_pushcclosure(L, ceRegisterSymbol, 0);
    c.lua_setglobal(L, "registerSymbol");
    c.lua_pushcclosure(L, ceUnregisterSymbol, 0);
    c.lua_setglobal(L, "unregisterSymbol");

    // 5. Memory read functions
    c.lua_pushcclosure(L, ceReadInteger, 0);
    c.lua_setglobal(L, "readInteger");
    c.lua_pushcclosure(L, ceReadQword, 0);
    c.lua_setglobal(L, "readQword");
    c.lua_pushcclosure(L, ceReadQword, 0);
    c.lua_setglobal(L, "readPointer");
    c.lua_pushcclosure(L, ceReadFloat, 0);
    c.lua_setglobal(L, "readFloat");
    c.lua_pushcclosure(L, ceReadDouble, 0);
    c.lua_setglobal(L, "readDouble");
    c.lua_pushcclosure(L, ceReadString, 0);
    c.lua_setglobal(L, "readString");
    c.lua_pushcclosure(L, ceReadBytes, 0);
    c.lua_setglobal(L, "readBytes");

    // 6. Memory write functions
    c.lua_pushcclosure(L, ceWriteInteger, 0);
    c.lua_setglobal(L, "writeInteger");
    c.lua_pushcclosure(L, ceWriteQword, 0);
    c.lua_setglobal(L, "writeQword");
    c.lua_pushcclosure(L, ceWriteQword, 0);
    c.lua_setglobal(L, "writePointer");
    c.lua_pushcclosure(L, ceWriteFloat, 0);
    c.lua_setglobal(L, "writeFloat");
    c.lua_pushcclosure(L, ceWriteDouble, 0);
    c.lua_setglobal(L, "writeDouble");
    c.lua_pushcclosure(L, ceWriteString, 0);
    c.lua_setglobal(L, "writeString");
    c.lua_pushcclosure(L, ceWriteBytes, 0);
    c.lua_setglobal(L, "writeBytes");

    // 7. Execution & Utility functions
    c.lua_pushcclosure(L, ceExecuteCodeEx, 0);
    c.lua_setglobal(L, "executeCodeEx");
    c.lua_pushcclosure(L, ceSleep, 0);
    c.lua_setglobal(L, "sleep");
    c.lua_pushcclosure(L, ceMessageDialog, 0);
    c.lua_setglobal(L, "messageDialog");
    c.lua_pushcclosure(L, cePrepareCall, 0);
    c.lua_setglobal(L, "PrepareCall");

    // 8. GUI and Table Stubs
    c.lua_pushcclosure(L, ceGetMainForm, 0);
    c.lua_setglobal(L, "getMainForm");
    c.lua_pushcclosure(L, ceCreateMenuItem, 0);
    c.lua_setglobal(L, "createMenuItem");
    c.lua_pushcclosure(L, ceGetAddressList, 0);
    c.lua_setglobal(L, "getAddressList");
    c.lua_pushcclosure(L, ceGetMemoryRecordByID, 0);
    c.lua_setglobal(L, "getMemoryRecordByID");
    c.lua_pushcclosure(L, ceGetMemoryRecordByDescription, 0);
    c.lua_setglobal(L, "getMemoryRecordByDescription");
    c.lua_pushcclosure(L, ceGetMemoryRecordByIndex, 0);
    c.lua_setglobal(L, "getMemoryRecord");

    // 9. Table-driving helpers used by auto-attach / auto-scan records
    c.lua_pushcclosure(L, ceGetProcessList, 0);
    c.lua_setglobal(L, "getProcessList");
    c.lua_pushcclosure(L, ceTargetIs64Bit, 0);
    c.lua_setglobal(L, "targetIs64Bit");
    c.lua_pushcclosure(L, ceTargetIs64Bit, 0);
    c.lua_setglobal(L, "targetIs64BitOS");
    c.lua_pushcclosure(L, ceAobScan, 0);
    c.lua_setglobal(L, "AOBScan");
    c.lua_pushcclosure(L, ceAobScanModule, 0);
    c.lua_setglobal(L, "AOBScanModule");
    c.lua_pushcclosure(L, ceShowMessage, 0);
    c.lua_setglobal(L, "showMessage");
}

// ============================================================================
// TESTS
// ============================================================================

test "CE Lua Compatibility layer registers symbols and evaluates scripts" {
    defer deinitSymbols();
    var engine = try engine_mod.ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    registerCeCompatibility(&engine);

    // Test syntaxcheck boolean
    const script1 =
        \\if syntaxcheck then
        \\    print("SYNTAX_CHECK_ACTIVE")
        \\else
        \\    print("SYNTAX_CHECK_DISABLED")
        \\end
    ;
    const res1 = engine.executeWithOutput(script1);
    try std.testing.expect(res1.success);
    try std.testing.expect(std.mem.indexOf(u8, res1.output, "SYNTAX_CHECK_DISABLED") != null);

    // Test registerSymbol and getAddress
    const script2 =
        \\registerSymbol("testHeroBase", 0x14050000)
        \\local addr = getAddress("testHeroBase")
        \\local addrSafe = getAddressSafe("nonExistentSymbol")
        \\print("HERO_ADDR:" .. tostring(addr))
        \\print("SAFE_ADDR:" .. tostring(addrSafe))
    ;
    const res2 = engine.executeWithOutput(script2);
    try std.testing.expect(res2.success);
    try std.testing.expect(std.mem.indexOf(u8, res2.output, "HERO_ADDR:335872000") != null);
    try std.testing.expect(std.mem.indexOf(u8, res2.output, "SAFE_ADDR:nil") != null);

    // Test CE GUI stub calls
    const script3 =
        \\local form = getMainForm()
        \\local item = createMenuItem(form)
        \\item.Caption = "Custom Menu"
        \\PrepareCall("GetTemplate")
        \\print("GUI_STUBS_OK:" .. item.Caption)
    ;
    const res3 = engine.executeWithOutput(script3);
    try std.testing.expect(res3.success);
    try std.testing.expect(std.mem.indexOf(u8, res3.output, "GUI_STUBS_OK:Custom Menu") != null);

    // Test CE AddressList and MemoryRecord methods
    const script4 =
        \\local al = getAddressList()
        \\local count = al.Count
        \\local rec = al.getMemoryRecordByID(10)
        \\rec:setDescription("Health_Var")
        \\rec:setValue("9999")
        \\rec:setActive(true)
        \\print("AL_COUNT:" .. tostring(count))
        \\print("REC_ID:" .. tostring(rec:getID()))
        \\print("REC_DESC:" .. rec:getDescription())
        \\print("REC_VAL:" .. rec:getValue())
        \\print("REC_ACT:" .. tostring(rec:getActive()))
    ;
    const res4 = engine.executeWithOutput(script4);
    if (!res4.success) {
        std.debug.print("LUA SCRIPT ERROR: {s}\n", .{res4.output});
    }
    try std.testing.expect(res4.success);
    try std.testing.expect(std.mem.indexOf(u8, res4.output, "REC_ID:10") != null);
    try std.testing.expect(std.mem.indexOf(u8, res4.output, "REC_DESC:Health_Var") != null);
    try std.testing.expect(std.mem.indexOf(u8, res4.output, "REC_VAL:9999") != null);
    try std.testing.expect(std.mem.indexOf(u8, res4.output, "REC_ACT:true") != null);
}
