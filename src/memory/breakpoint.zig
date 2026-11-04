//! ============================================================================
//! SHARABHA (शरभ) — NETRA DRISHTANTA: HARDWARE BREAKPOINTS & WATCH ENGINE
//! (नेत्र दृष्टान्त // The Eye of Vision)
//! Captures Instruction Pointer (RIP), Opcode Disassembly, Hit Counts, and
//! Full 64-Bit Register Dumps (RAX..R15, EFLAGS) via Win32 Hardware Debug Registers.
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const disasm = @import("disasm.zig");
const debugger = @import("debugger.zig");

pub extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;

pub const RegisterDump = struct {
    rax: u64 = 0,
    rbx: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rip: u64 = 0,
    eflags: u32 = 0,
};

pub const WatchedInstruction = struct {
    rip: u64,
    mnemonic: []const u8,
    operands: []const u8,
    opcode_bytes: [16]u8,
    opcode_len: u8,
    hit_count: u32,
    registers: RegisterDump,
    timestamp_ms: u64,

    pub fn formatOpcodes(self: *const WatchedInstruction, buf: []u8) []const u8 {
        var cursor: usize = 0;
        const len = @min(self.opcode_len, 16);
        for (self.opcode_bytes[0..len]) |b| {
            if (cursor + 3 > buf.len) break;
            const written = std.fmt.bufPrint(buf[cursor..], "{X:0>2} ", .{b}) catch break;
            cursor += written.len;
        }
        if (cursor > 0 and buf[cursor - 1] == ' ') {
            return buf[0 .. cursor - 1];
        }
        return buf[0..cursor];
    }
};

pub const NetraWatcher = struct {
    allocator: std.mem.Allocator,
    target_pid: u32,
    target_address: usize,
    watch_length: u8, // 1, 2, 4, or 8 bytes
    hits: std.ArrayList(WatchedInstruction),
    is_armed: bool = false,

    pub fn init(allocator: std.mem.Allocator, target_pid: u32, target_address: usize, watch_length: u8) NetraWatcher {
        return NetraWatcher{
            .allocator = allocator,
            .target_pid = target_pid,
            .target_address = target_address,
            .watch_length = watch_length,
            .hits = .empty,
        };
    }

    pub fn deinit(self: *NetraWatcher) void {
        for (self.hits.items) |hit| {
            self.allocator.free(hit.mnemonic);
            self.allocator.free(hit.operands);
        }
        self.hits.deinit(self.allocator);
    }

    /// Records an intercepted memory write instruction event
    pub fn recordHit(
        self: *NetraWatcher,
        rip: u64,
        raw_code: []const u8,
        regs: RegisterDump,
    ) !void {
        for (self.hits.items) |*item| {
            if (item.rip == rip) {
                item.hit_count += 1;
                item.registers = regs;
                item.timestamp_ms = GetTickCount64();
                return;
            }
        }

        const decoded = disasm.Disassembler.decodeInstruction(raw_code, rip);
        var op_buf: [16]u8 = @splat(0);
        const copy_len = @min(raw_code.len, 16);
        @memcpy(op_buf[0..copy_len], raw_code[0..copy_len]);

        const mnem_dupe = try self.allocator.dupe(u8, decoded.getMnemonic());
        const ops_dupe = try self.allocator.dupe(u8, decoded.getOperands());

        try self.hits.append(self.allocator, WatchedInstruction{
            .rip = rip,
            .mnemonic = mnem_dupe,
            .operands = ops_dupe,
            .opcode_bytes = op_buf,
            .opcode_len = @intCast(copy_len),
            .hit_count = 1,
            .registers = regs,
            .timestamp_ms = GetTickCount64(),
        });
    }

    /// Arms DR0 hardware breakpoint on all active threads of target process
    pub fn armHardwareBreakpoint(self: *NetraWatcher) !usize {
        var dbg_watcher = debugger.DebugWatcher.init(self.allocator, self.target_pid, self.target_address);
        defer dbg_watcher.deinit();
        const armed_count = try dbg_watcher.armAllThreads();
        self.is_armed = (armed_count > 0);
        return armed_count;
    }

    /// Disarms DR0 hardware breakpoint across all active threads
    pub fn disarmHardwareBreakpoint(self: *NetraWatcher) void {
        var dbg_watcher = debugger.DebugWatcher.init(self.allocator, self.target_pid, self.target_address);
        defer dbg_watcher.deinit();
        dbg_watcher.disarmAllThreads() catch {};
        self.is_armed = false;
    }

    /// Exports hits to JSON cache for UI inspection
    pub fn exportHitsJson(self: *const NetraWatcher, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;

        const header = try std.fmt.allocPrint(allocator, "{{\n  \"target_pid\": {d},\n  \"target_address\": \"0x{X}\",\n  \"hits\": [\n", .{
            self.target_pid, self.target_address,
        });
        defer allocator.free(header);
        try list.appendSlice(allocator, header);

        for (self.hits.items, 0..) |hit, i| {
            var hex_buf: [64]u8 = undefined;
            const hex_str = hit.formatOpcodes(&hex_buf);
            const comma = if (i + 1 < self.hits.items.len) "," else "";

            const hit_str = try std.fmt.allocPrint(allocator,
                \\    {{
                \\      "rip": "0x{X:0>16}",
                \\      "disasm": "{s} {s}",
                \\      "opcodes": "{s}",
                \\      "hit_count": {d},
                \\      "rax": "0x{X:0>16}",
                \\      "rbx": "0x{X:0>16}",
                \\      "rcx": "0x{X:0>16}",
                \\      "rdx": "0x{X:0>16}",
                \\      "rsi": "0x{X:0>16}",
                \\      "rdi": "0x{X:0>16}",
                \\      "rsp": "0x{X:0>16}",
                \\      "rbp": "0x{X:0>16}",
                \\      "r8":  "0x{X:0>16}",
                \\      "r9":  "0x{X:0>16}",
                \\      "r10": "0x{X:0>16}",
                \\      "r11": "0x{X:0>16}",
                \\      "r12": "0x{X:0>16}",
                \\      "r13": "0x{X:0>16}",
                \\      "r14": "0x{X:0>16}",
                \\      "r15": "0x{X:0>16}",
                \\      "eflags": "0x{X:0>8}"
                \\    }}{s}
                \\
            , .{
                hit.rip,
                hit.mnemonic,
                hit.operands,
                hex_str,
                hit.hit_count,
                hit.registers.rax,
                hit.registers.rbx,
                hit.registers.rcx,
                hit.registers.rdx,
                hit.registers.rsi,
                hit.registers.rdi,
                hit.registers.rsp,
                hit.registers.rbp,
                hit.registers.r8,
                hit.registers.r9,
                hit.registers.r10,
                hit.registers.r11,
                hit.registers.r12,
                hit.registers.r13,
                hit.registers.r14,
                hit.registers.r15,
                hit.registers.eflags,
                comma,
            });
            defer allocator.free(hit_str);
            try list.appendSlice(allocator, hit_str);
        }

        try list.appendSlice(allocator, "  ]\n}}\n");
        return list.toOwnedSlice(allocator);
    }
};

test "Netra Drishtanta: Hardware Breakpoint Hit Interceptor and Register Dump" {
    const alloc = std.testing.allocator;

    var watcher = NetraWatcher.init(alloc, 4444, 0x140500200, 4);
    defer watcher.deinit();

    // Mock instruction: mov [rcx+0x18], eax
    const opcodes = [_]u8{ 0x89, 0x41, 0x18 };
    const regs = RegisterDump{
        .rax = 0x00000000000F423F,
        .rbx = 0x00007FF782A14500,
        .rcx = 0x1405001E8,
        .rdx = 0x1,
        .rsi = 0,
        .rdi = 0x140500000,
        .rsp = 0x00000049281FE480,
        .rbp = 0x00000049281FE510,
        .r8 = 0,
        .r9 = 0,
        .r10 = 0,
        .r11 = 0x246,
        .r12 = 0x140000000,
        .r13 = 0,
        .r14 = 0,
        .r15 = 0,
        .rip = 0x7FF782410BC2,
        .eflags = 0x10206,
    };

    try watcher.recordHit(0x7FF782410BC2, &opcodes, regs);
    try std.testing.expectEqual(@as(usize, 1), watcher.hits.items.len);

    const hit = watcher.hits.items[0];
    try std.testing.expectEqual(@as(u64, 0x7FF782410BC2), hit.rip);
    try std.testing.expectEqual(@as(u32, 1), hit.hit_count);
    try std.testing.expectEqual(@as(u64, 0x00000000000F423F), hit.registers.rax);
    try std.testing.expectEqualStrings("mov", hit.mnemonic);
    try std.testing.expectEqualStrings("[rcx+0x18], eax", hit.operands);

    // Increment hit count
    try watcher.recordHit(0x7FF782410BC2, &opcodes, regs);
    try std.testing.expectEqual(@as(u32, 2), watcher.hits.items[0].hit_count);

    // Export JSON and verify contents
    const json_str = try watcher.exportHitsJson(alloc);
    defer alloc.free(json_str);

    try std.testing.expect(std.mem.indexOf(u8, json_str, "7FF782410BC2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "mov [rcx+0x18], eax") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "89 41 18") != null);
}
