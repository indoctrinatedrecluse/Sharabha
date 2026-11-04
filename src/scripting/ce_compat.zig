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

/// Global symbol table registry for user-defined symbols (registerSymbol / getAddress)
var global_symbols: ?std.StringHashMap(usize) = null;
var global_allocator: ?std.mem.Allocator = null;

fn getSymbolMap(allocator: std.mem.Allocator) *std.StringHashMap(usize) {
    if (global_symbols == null) {
        global_symbols = std.StringHashMap(usize).init(allocator);
        global_allocator = allocator;
    }
    return &global_symbols.?;
}

pub fn registerSymbol(name: []const u8, address: usize, allocator: std.mem.Allocator) !void {
    const map = getSymbolMap(allocator);
    const key = try allocator.dupe(u8, name);
    try map.put(key, address);
}

pub fn deinitSymbols() void {
    if (global_symbols) |*map| {
        if (global_allocator) |alloc| {
            var it = map.keyIterator();
            while (it.next()) |k| {
                alloc.free(k.*);
            }
            map.deinit();
        }
        global_symbols = null;
        global_allocator = null;
    }
}

pub fn unregisterSymbol(name: []const u8) void {
    if (global_symbols) |*map| {
        if (std.mem.eql(u8, name, "*")) {
            map.clearRetainingCapacity();
        } else {
            _ = map.remove(name);
        }
    }
}

pub fn lookupSymbol(name: []const u8) ?usize {
    if (global_symbols) |*map| {
        return map.get(name);
    }
    return null;
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
        c.lua_pushboolean(l, 1);
        return 1;
    }

    c.lua_pushboolean(l, 0);
    return 1;
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

fn ceGetAddressList(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_newtable(l);
    c.lua_pushcclosure(l, ceGetMemoryRecordByID, 0);
    c.lua_setfield(l, -2, "getMemoryRecordByID");
    return 1;
}

fn ceGetMemoryRecordByID(L: ?*c.lua_State) callconv(.c) c_int {
    const l = L orelse return 0;
    c.lua_newtable(l);
    c.lua_pushinteger(l, 0);
    c.lua_setfield(l, -2, "CurrentAddress");
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
}
