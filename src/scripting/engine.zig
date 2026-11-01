const std = @import("std");
const process = @import("../memory/process.zig");
const win = process.win;
const freeze = @import("../memory/freeze.zig");

// Lua 5.1 / LuaJIT C-API declarations for Zig via build.zig translate-c
pub const c = @import("lua");

pub fn luaToString(L: ?*c.lua_State, idx: c_int) ?[:0]const u8 {
    const ptr = c.lua_tolstring(L, idx, null);
    if (ptr == null) return null;
    return std.mem.span(ptr);
}

pub const ScriptEngine = struct {
    L: ?*c.lua_State,
    allocator: std.mem.Allocator,
    target_pid: u32,
    process_handle: ?win.HANDLE,
    freeze_mgr: ?*freeze.FreezeManager,

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
        };

        active_instance = &self;
        self.registerBindings();
        return self;
    }

    pub fn deinit(self: *ScriptEngine) void {
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

    fn registerBindings(self: *ScriptEngine) void {
        const L = self.L orelse return;

        // Register table `sharabha`
        c.lua_createtable(L, 0, 8);

        // sharabha.log(str)
        c.lua_pushcclosure(L, luaLog, 0);
        c.lua_setfield(L, -2, "log");

        // sharabha.read_i32(address) -> integer
        c.lua_pushcclosure(L, luaReadI32, 0);
        c.lua_setfield(L, -2, "read_i32");

        // sharabha.write_i32(address, value) -> boolean
        c.lua_pushcclosure(L, luaWriteI32, 0);
        c.lua_setfield(L, -2, "write_i32");

        // sharabha.read_f32(address) -> number
        c.lua_pushcclosure(L, luaReadF32, 0);
        c.lua_setfield(L, -2, "read_f32");

        // sharabha.write_f32(address, value) -> boolean
        c.lua_pushcclosure(L, luaWriteF32, 0);
        c.lua_setfield(L, -2, "write_f32");

        // sharabha.freeze_i32(address, value, desc) -> boolean
        c.lua_pushcclosure(L, luaFreezeI32, 0);
        c.lua_setfield(L, -2, "freeze_i32");

        // sharabha.unfreeze(address) -> boolean
        c.lua_pushcclosure(L, luaUnfreeze, 0);
        c.lua_setfield(L, -2, "unfreeze");

        // Set global "sharabha"
        c.lua_setglobal(L, "sharabha");
    }

    // Callbacks from Lua
    fn luaLog(L: ?*c.lua_State) callconv(.c) c_int {
        const msg = luaToString(L, 1);
        if (msg) |str| {
            std.debug.print("🔱 [Sharabha Lua]: {s}\n", .{str});
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
};

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
