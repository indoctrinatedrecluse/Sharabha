const std = @import("std");
const process = @import("../memory/process.zig");
const win = process.win;
const freeze = @import("../memory/freeze.zig");
const injector = @import("../memory/injector.zig");

// Lua 5.1 / LuaJIT C-API declarations for Zig via build.zig translate-c
pub const c = @import("lua");

pub fn luaToString(L: ?*c.lua_State, idx: c_int) ?[:0]const u8 {
    const ptr = c.lua_tolstring(L, idx, null);
    if (ptr == null) return null;
    return std.mem.span(ptr);
}

pub const ExecutionResult = struct {
    success: bool,
    output: []const u8,
    error_msg: ?[]const u8,
};

pub const ScriptEngine = struct {
    L: ?*c.lua_State,
    allocator: std.mem.Allocator,
    target_pid: u32,
    process_handle: ?win.HANDLE,
    freeze_mgr: ?*freeze.FreezeManager,
    output_log: std.ArrayList(u8),

    // Sentinel to reference the active engine for Lua C-callbacks
    var active_instance: ?*ScriptEngine = null;

    pub fn init(allocator: std.mem.Allocator, freeze_mgr: ?*freeze.FreezeManager) !ScriptEngine {
        const L = c.luaL_newstate() orelse return error.LuaStateInitFailed;
        c.luaL_openlibs(L);

        var self = ScriptEngine{
            .L = L,
            .allocator = allocator,
            .target_pid = 0,
            .process_handle = null,
            .freeze_mgr = freeze_mgr,
            .output_log = .empty,
        };

        active_instance = &self;
        self.registerBindings();
        return self;
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.output_log.deinit(self.allocator);
        if (self.process_handle) |h| {
            _ = win.CloseHandle(h);
            self.process_handle = null;
        }
        if (self.L) |l| {
            c.lua_close(l);
            self.L = null;
        }
        if (active_instance == self) {
            active_instance = null;
        }
    }

    pub fn attach(self: *ScriptEngine, pid: u32) !void {
        if (self.process_handle) |h| {
            _ = win.CloseHandle(h);
            self.process_handle = null;
        }
        const ph = try process.ProcessHandle.open(pid);
        self.process_handle = ph.handle;
        self.target_pid = pid;
    }

    pub fn runString(self: *ScriptEngine, code: [:0]const u8) !void {
        const L = self.L orelse return error.NoLuaState;
        active_instance = self;

        if (c.luaL_loadstring(L, code.ptr) != 0) {
            const err_msg = luaToString(L, -1);
            if (err_msg) |msg| {
                std.debug.print("[Lua Error]: {s}\n", .{msg});
            }
            c.lua_settop(L, -2);
            return error.LuaCompileError;
        }

        if (c.lua_pcall(L, 0, c.LUA_MULTRET, 0) != 0) {
            const err_msg = luaToString(L, -1);
            if (err_msg) |msg| {
                std.debug.print("[Lua Runtime Error]: {s}\n", .{msg});
            }
            c.lua_settop(L, -2);
            return error.LuaRuntimeError;
        }
    }

    pub fn executeWithOutput(self: *ScriptEngine, code: [:0]const u8) ExecutionResult {
        self.output_log.clearRetainingCapacity();
        active_instance = self;
        const L = self.L orelse return .{
            .success = false,
            .output = "",
            .error_msg = "No Lua state active",
        };

        if (c.luaL_loadstring(L, code.ptr) != 0) {
            const err = luaToString(L, -1) orelse "Lua compilation error";
            c.lua_settop(L, -2);
            return .{
                .success = false,
                .output = self.output_log.items,
                .error_msg = err,
            };
        }

        if (c.lua_pcall(L, 0, c.LUA_MULTRET, 0) != 0) {
            const err = luaToString(L, -1) orelse "Lua runtime error";
            c.lua_settop(L, -2);
            return .{
                .success = false,
                .output = self.output_log.items,
                .error_msg = err,
            };
        }

        return .{
            .success = true,
            .output = self.output_log.items,
            .error_msg = null,
        };
    }

    fn registerBindings(self: *ScriptEngine) void {
        const L = self.L orelse return;

        // Override standard Lua `print(...)` to capture output into engine buffer
        c.lua_pushcclosure(L, luaPrint, 0);
        c.lua_setglobal(L, "print");

        // Register table `sharabha`
        c.lua_createtable(L, 0, 16);

        // sharabha.log(str)
        c.lua_pushcclosure(L, luaLog, 0);
        c.lua_setfield(L, -2, "log");

        // sharabha.read_i32 / read_u32(address) -> integer
        c.lua_pushcclosure(L, luaReadI32, 0);
        c.lua_setfield(L, -2, "read_i32");
        c.lua_pushcclosure(L, luaReadI32, 0);
        c.lua_setfield(L, -2, "read_u32");

        // sharabha.write_i32 / write_u32(address, value) -> boolean
        c.lua_pushcclosure(L, luaWriteI32, 0);
        c.lua_setfield(L, -2, "write_i32");
        c.lua_pushcclosure(L, luaWriteI32, 0);
        c.lua_setfield(L, -2, "write_u32");

        // sharabha.read_i64 / write_i64
        c.lua_pushcclosure(L, luaReadI64, 0);
        c.lua_setfield(L, -2, "read_i64");
        c.lua_pushcclosure(L, luaWriteI64, 0);
        c.lua_setfield(L, -2, "write_i64");

        // sharabha.read_f32(address) -> number
        c.lua_pushcclosure(L, luaReadF32, 0);
        c.lua_setfield(L, -2, "read_f32");

        // sharabha.write_f32(address, value) -> boolean
        c.lua_pushcclosure(L, luaWriteF32, 0);
        c.lua_setfield(L, -2, "write_f32");

        // sharabha.read_f64 / write_f64
        c.lua_pushcclosure(L, luaReadF64, 0);
        c.lua_setfield(L, -2, "read_f64");
        c.lua_pushcclosure(L, luaWriteF64, 0);
        c.lua_setfield(L, -2, "write_f64");

        // sharabha.read_pointer(base_address, offsets_table) -> resolved_address
        c.lua_pushcclosure(L, luaReadPointer, 0);
        c.lua_setfield(L, -2, "read_pointer");

        // sharabha.freeze_i32 / freeze_u32(address, value, desc) -> boolean
        c.lua_pushcclosure(L, luaFreezeI32, 0);
        c.lua_setfield(L, -2, "freeze_i32");
        c.lua_pushcclosure(L, luaFreezeI32, 0);
        c.lua_setfield(L, -2, "freeze_u32");

        // sharabha.unfreeze(address) -> boolean
        c.lua_pushcclosure(L, luaUnfreeze, 0);
        c.lua_setfield(L, -2, "unfreeze");

        // sharabha.inject_dll(dll_path) -> remote_module_base
        c.lua_pushcclosure(L, luaInjectDll, 0);
        c.lua_setfield(L, -2, "inject_dll");

        // sharabha.allocate_cave(size) -> remote_cave_address
        c.lua_pushcclosure(L, luaAllocateCave, 0);
        c.lua_setfield(L, -2, "allocate_cave");

        // Set global "sharabha"
        c.lua_setglobal(L, "sharabha");
    }

    // Callbacks from Lua
    fn luaPrint(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const l = L orelse return 0;
        const n = c.lua_gettop(l);
        var i: c_int = 1;
        while (i <= n) : (i += 1) {
            if (i > 1) {
                inst.output_log.appendSlice(inst.allocator, "\t") catch {};
            }
            const s = luaToString(l, i) orelse "";
            inst.output_log.appendSlice(inst.allocator, s) catch {};
        }
        inst.output_log.appendSlice(inst.allocator, "\n") catch {};
        return 0;
    }

    fn luaLog(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const msg = luaToString(L, 1);
        if (msg) |str| {
            std.debug.print("🔱 [Sharabha Lua]: {s}\n", .{str});
            inst.output_log.appendSlice(inst.allocator, "🔱 ") catch {};
            inst.output_log.appendSlice(inst.allocator, str) catch {};
            inst.output_log.appendSlice(inst.allocator, "\n") catch {};
        }
        return 0;
    }

    fn luaReadI32(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const h = inst.process_handle orelse return 0;
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));

        var val: i32 = 0;
        var bytes_read: usize = 0;
        const success = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&val)),
            @sizeOf(i32),
            &bytes_read,
        );

        if (success != 0 and bytes_read == @sizeOf(i32)) {
            c.lua_pushinteger(L, @as(c.lua_Integer, val));
            return 1;
        }
        return 0;
    }

    fn luaWriteI32(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        const val = @as(i32, @truncate(c.lua_tointeger(L, 2)));

        var bytes_written: usize = 0;
        const success = win.WriteProcessMemory(
            h,
            @as(?*anyopaque, @ptrFromInt(addr)),
            @as(*const anyopaque, @ptrCast(&val)),
            @sizeOf(i32),
            &bytes_written,
        );

        c.lua_pushboolean(L, if (success != 0 and bytes_written == @sizeOf(i32)) 1 else 0);
        return 1;
    }

    fn luaReadI64(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const h = inst.process_handle orelse return 0;
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));

        var val: i64 = 0;
        var bytes_read: usize = 0;
        const success = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&val)),
            @sizeOf(i64),
            &bytes_read,
        );

        if (success != 0 and bytes_read == @sizeOf(i64)) {
            c.lua_pushnumber(L, @as(f64, @floatFromInt(val)));
            return 1;
        }
        return 0;
    }

    fn luaWriteI64(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        const val = @as(i64, @intFromFloat(c.lua_tonumber(L, 2)));

        var bytes_written: usize = 0;
        const success = win.WriteProcessMemory(
            h,
            @as(?*anyopaque, @ptrFromInt(addr)),
            @as(*const anyopaque, @ptrCast(&val)),
            @sizeOf(i64),
            &bytes_written,
        );

        c.lua_pushboolean(L, if (success != 0 and bytes_written == @sizeOf(i64)) 1 else 0);
        return 1;
    }

    fn luaReadF32(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const h = inst.process_handle orelse return 0;
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));

        var val: f32 = 0;
        var bytes_read: usize = 0;
        const success = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&val)),
            @sizeOf(f32),
            &bytes_read,
        );

        if (success != 0 and bytes_read == @sizeOf(f32)) {
            c.lua_pushnumber(L, @as(f64, @floatCast(val)));
            return 1;
        }
        return 0;
    }

    fn luaWriteF32(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        const val = @as(f32, @floatCast(c.lua_tonumber(L, 2)));

        var bytes_written: usize = 0;
        const success = win.WriteProcessMemory(
            h,
            @as(?*anyopaque, @ptrFromInt(addr)),
            @as(*const anyopaque, @ptrCast(&val)),
            @sizeOf(f32),
            &bytes_written,
        );

        c.lua_pushboolean(L, if (success != 0 and bytes_written == @sizeOf(f32)) 1 else 0);
        return 1;
    }

    fn luaReadF64(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const h = inst.process_handle orelse return 0;
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));

        var val: f64 = 0;
        var bytes_read: usize = 0;
        const success = win.ReadProcessMemory(
            h,
            @as(?*const anyopaque, @ptrFromInt(addr)),
            @as(*anyopaque, @ptrCast(&val)),
            @sizeOf(f64),
            &bytes_read,
        );

        if (success != 0 and bytes_read == @sizeOf(f64)) {
            c.lua_pushnumber(L, val);
            return 1;
        }
        return 0;
    }

    fn luaWriteF64(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        const val = c.lua_tonumber(L, 2);

        var bytes_written: usize = 0;
        const success = win.WriteProcessMemory(
            h,
            @as(?*anyopaque, @ptrFromInt(addr)),
            @as(*const anyopaque, @ptrCast(&val)),
            @sizeOf(f64),
            &bytes_written,
        );

        c.lua_pushboolean(L, if (success != 0 and bytes_written == @sizeOf(f64)) 1 else 0);
        return 1;
    }

    fn luaReadPointer(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse return 0;
        const h = inst.process_handle orelse return 0;
        const l = L orelse return 0;

        var current_addr = @as(usize, @intCast(c.lua_tointeger(l, 1)));

        // Second parameter is a table of offsets e.g. { 0x10, 0x68, 0x18 }
        if (c.lua_istable(l, 2)) {
            const len = c.lua_objlen(l, 2);
            var i: usize = 1;
            while (i <= len) : (i += 1) {
                c.lua_rawgeti(l, 2, @intCast(i));
                const offset = @as(usize, @intCast(c.lua_tointeger(l, -1)));
                c.lua_settop(l, -2);

                var ptr_val: usize = 0;
                var bytes_read: usize = 0;
                const success = win.ReadProcessMemory(
                    h,
                    @as(?*const anyopaque, @ptrFromInt(current_addr)),
                    @as(*anyopaque, @ptrCast(&ptr_val)),
                    @sizeOf(usize),
                    &bytes_read,
                );
                if (success == 0 or bytes_read != @sizeOf(usize) or ptr_val == 0) {
                    c.lua_pushnil(l);
                    return 1;
                }
                current_addr = ptr_val + offset;
            }
        }

        c.lua_pushinteger(l, @as(c.lua_Integer, @intCast(current_addr)));
        return 1;
    }

    fn luaFreezeI32(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const fm = inst.freeze_mgr orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };

        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        const val = @as(i32, @truncate(c.lua_tointeger(L, 2)));
        const desc = luaToString(L, 3) orelse "Lua Inquest Freeze";

        var val_bytes = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        std.mem.writeInt(i32, val_bytes[0..4], val, .little);

        fm.addOrUpdate(addr, val_bytes[0..4], desc) catch {
            c.lua_pushboolean(L, 0);
            return 1;
        };

        c.lua_pushboolean(L, 1);
        return 1;
    }

    fn luaUnfreeze(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };
        const fm = inst.freeze_mgr orelse {
            c.lua_pushboolean(L, 0);
            return 1;
        };

        const addr = @as(usize, @intCast(c.lua_tointeger(L, 1)));
        fm.remove(addr);
        c.lua_pushboolean(L, 1);
        return 1;
    }

    fn luaInjectDll(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushnil(L);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushnil(L);
            return 1;
        };
        const path = luaToString(L, 1) orelse {
            c.lua_pushnil(L);
            return 1;
        };

        const mod_base = injector.PashaBandhana.injectDll(h, path, 5000, inst.allocator) catch {
            c.lua_pushnil(L);
            return 1;
        };

        c.lua_pushinteger(L, @as(c.lua_Integer, @intCast(mod_base)));
        return 1;
    }

    fn luaAllocateCave(L: ?*c.lua_State) callconv(.c) c_int {
        const inst = active_instance orelse {
            c.lua_pushnil(L);
            return 1;
        };
        const h = inst.process_handle orelse {
            c.lua_pushnil(L);
            return 1;
        };
        const size = @as(usize, @intCast(c.lua_tointeger(L, 1)));

        const cave_addr = injector.PashaBandhana.allocateCodeCave(h, size, win.PAGE_EXECUTE_READWRITE) catch {
            c.lua_pushnil(L);
            return 1;
        };

        c.lua_pushinteger(L, @as(c.lua_Integer, @intCast(cave_addr)));
        return 1;
    }
};

/// Predefined Lua Altar Template Scripts
pub fn getTemplateScript(template_name: []const u8) [:0]const u8 {
    if (std.mem.eql(u8, template_name, "pointer_chain")) {
        return 
            \\-- [Vedic Rudra Tandava] Multi-Level Pointer Dereference
            \\local base_addr = 0x7FF74A800000
            \\local offsets = { 0x18, 0x68, 0x30 }
            \\local target = sharabha.read_pointer(base_addr, offsets)
            \\if target then
            \\    local val = sharabha.read_i32(target)
            \\    print("✓ Resolved Dynamic Address: 0x" .. string.format("%X", target))
            \\    print("✓ Live Value: " .. tostring(val))
            \\else
            \\    print("❌ Pointer path broken during traversal")
            \\end
        ;
    } else if (std.mem.eql(u8, template_name, "freeze_loop")) {
        return 
            \\-- [Stambhana Sentinel] Lock Target Value in Samsara
            \\local addr = 0x7FF74A8014E0
            \\local frozen_val = 999999
            \\local success = sharabha.freeze_i32(addr, frozen_val, "Rudra Godmode Lock")
            \\if success then
            \\    print("✓ Stambhana Freeze Sentinel Armed at 0x" .. string.format("%X", addr))
            \\else
            \\    print("❌ Freeze Sentinel initialization failed")
            \\end
        ;
    } else if (std.mem.eql(u8, template_name, "dll_inject")) {
        return 
            \\-- [Pasha Bandhana] Win32 DLL Remote Thread Injection
            \\local dll_path = "C:\\Sharabha\\payload.dll"
            \\local hModule = sharabha.inject_dll(dll_path)
            \\if hModule then
            \\    print("✓ Remote Module Injected at Base: 0x" .. string.format("%X", hModule))
            \\else
            \\    print("❌ DLL Injection failed (Access denied or path missing)")
            \\end
        ;
    } else if (std.mem.eql(u8, template_name, "code_cave")) {
        return 
            \\-- [Guha Sthapana] Remote Executable Code Cave Allocation
            \\local cave_size = 256
            \\local cave_addr = sharabha.allocate_cave(cave_size)
            \\if cave_addr then
            \\    print("✓ Remote Code Cave Allocated at: 0x" .. string.format("%X", cave_addr))
            \\    print("✓ PAGE_EXECUTE_READWRITE Armed for Trampoline Detour")
            \\else
            \\    print("❌ Remote Code Cave Allocation failed")
            \\end
        ;
    } else {
        return 
            \\-- [Sharabha Ashtamurti] Direct Memory Read & Mutation
            \\local addr = 0x7FF74A8014E4
            \\local current_val = sharabha.read_i32(addr) or 0
            \\print("Current Value at 0x" .. string.format("%X", addr) .. ": " .. tostring(current_val))
            \\local ok = sharabha.write_i32(addr, current_val + 1000)
            \\if ok then
            \\    print("✓ Mutated Value to: " .. tostring(current_val + 1000))
            \\else
            \\    print("❌ WriteProcessMemory failed")
            \\end
        ;
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "LuaJIT state initialization and script execution" {
    var engine = try ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    const script =
        \\ local x = 40 + 2
        \\ sharabha.log("Rudra Tandava script awakened: " .. tostring(x))
        \\ assert(x == 42)
    ;

    try engine.runString(script);
}

test "LuaJIT memory manipulation on active process" {
    var engine = try ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    const current_pid = win.GetCurrentProcessId();
    try engine.attach(current_pid);

    var target_val: i32 = 100;
    const target_addr = @intFromPtr(&target_val);

    var buf: [512]u8 = undefined;
    const script = try std.fmt.bufPrintSentinel(&buf,
        \\ local addr = {d}
        \\ local old_val = sharabha.read_i32(addr)
        \\ assert(old_val == 100)
        \\ local success = sharabha.write_i32(addr, 777777)
        \\ assert(success == true)
        \\ local new_val = sharabha.read_i32(addr)
        \\ assert(new_val == 777777)
        \\ sharabha.log("Lua memory patch confirmed: " .. tostring(new_val))
    , .{target_addr}, 0);

    try engine.runString(script);
    try std.testing.expectEqual(@as(i32, 777777), target_val);
}

test "LuaJIT executeWithOutput captures print and log" {
    var engine = try ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    const script =
        \\ print("Hello from Lua print")
        \\ sharabha.log("Sacred log message")
    ;

    const res = engine.executeWithOutput(script);
    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "Hello from Lua print") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "Sacred log message") != null);
}

test "LuaJIT read_pointer chain traversal on self-process" {
    var engine = try ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    try engine.attach(win.GetCurrentProcessId());

    var final_val: i32 = 1337;
    const level1_ptr = @intFromPtr(&final_val);
    var level0_ptr = level1_ptr;
    const base_addr = @intFromPtr(&level0_ptr);

    var buf: [512]u8 = undefined;
    const script = try std.fmt.bufPrintSentinel(&buf,
        \\ local base = {d}
        \\ local target = sharabha.read_pointer(base, {{ 0 }})
        \\ assert(target == {d})
        \\ local val = sharabha.read_i32(target)
        \\ assert(val == 1337)
        \\ print("Pointer resolved successfully to 1337")
    , .{ base_addr, @intFromPtr(&final_val) }, 0);

    const res = engine.executeWithOutput(script);
    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "Pointer resolved successfully") != null);
}
