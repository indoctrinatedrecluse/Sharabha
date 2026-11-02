const std = @import("std");
const process = @import("process.zig");
const win = process.win;

pub const Instruction = struct {
    address: usize,
    bytes: [15]u8,
    len: u8,
    mnemonic: [16]u8,
    mnemonic_len: u8,
    operands: [48]u8,
    operands_len: u8,

    pub fn getMnemonic(self: *const Instruction) []const u8 {
        return self.mnemonic[0..self.mnemonic_len];
    }

    pub fn getOperands(self: *const Instruction) []const u8 {
        return self.operands[0..self.operands_len];
    }

    pub fn format(self: *const Instruction, writer: anytype) !void {
        try writer.print("0x{X:0>12} | ", .{self.address});
        var b_idx: usize = 0;
        while (b_idx < self.len) : (b_idx += 1) {
            try writer.print("{X:0>2} ", .{self.bytes[b_idx]});
        }
        while (b_idx < 8) : (b_idx += 1) {
            try writer.print("   ", .{});
        }
        try writer.print("| {s: <6} {s}", .{ self.getMnemonic(), self.getOperands() });
    }

    pub fn toString(self: *const Instruction, buf: []u8) []const u8 {
        var cursor: usize = 0;
        const p1 = std.fmt.bufPrint(buf[cursor..], "0x{X:0>12} | ", .{self.address}) catch return "";
        cursor += p1.len;

        var b_idx: usize = 0;
        while (b_idx < self.len) : (b_idx += 1) {
            const p = std.fmt.bufPrint(buf[cursor..], "{X:0>2} ", .{self.bytes[b_idx]}) catch return buf[0..cursor];
            cursor += p.len;
        }
        while (b_idx < 8) : (b_idx += 1) {
            const p = std.fmt.bufPrint(buf[cursor..], "   ", .{}) catch return buf[0..cursor];
            cursor += p.len;
        }
        const p2 = std.fmt.bufPrint(buf[cursor..], "| {s: <6} {s}", .{ self.getMnemonic(), self.getOperands() }) catch return buf[0..cursor];
        cursor += p2.len;
        return buf[0..cursor];
    }
};

const REG_64 = [_][]const u8{
    "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
    "r8",  "r9",  "r10", "r11", "r12", "r13", "r14", "r15",
};

const REG_32 = [_][]const u8{
    "eax",  "ecx",  "edx",  "ebx",  "esp",  "ebp",  "esi",  "edi",
    "r8d",  "r9d",  "r10d", "r11d", "r12d", "r13d", "r14d", "r15d",
};

const REG_16 = [_][]const u8{
    "ax",   "cx",   "dx",   "bx",   "sp",   "bp",   "si",   "di",
    "r8w",  "r9w",  "r10w", "r11w", "r12w", "r13w", "r14w", "r15w",
};

const REG_8 = [_][]const u8{
    "al",   "cl",   "dl",   "bl",   "spl",  "bpl",  "sil",  "dil",
    "r8b",  "r9b",  "r10b", "r11b", "r12b", "r13b", "r14b", "r15b",
};

const JCC_MNEMONICS = [_][]const u8{
    "jo",  "jno", "jb",  "jae", "je",  "jne", "jbe", "ja",
    "js",  "jns", "jp",  "jnp", "jl",  "jge", "jle", "jg",
};

/// Vyakarana (व्याकरण) — x86_64 Machine Code Instruction Decoder & Disassembler
/// Disassembles virtual memory segments for live inspection, needle hooking, and write tracking.
pub const Disassembler = struct {
    pub fn decodeInstruction(bytes: []const u8, address: usize) Instruction {
        var inst = Instruction{
            .address = address,
            .bytes = @splat(0),
            .len = 0,
            .mnemonic = @splat(0),
            .mnemonic_len = 0,
            .operands = @splat(0),
            .operands_len = 0,
        };

        if (bytes.len == 0) return inst;

        var idx: usize = 0;
        var rex_w = false;
        var rex_r: u4 = 0;
        var rex_x: u4 = 0;
        var rex_b: u4 = 0;
        var has_rex = false;
        var is_16bit = false;
        var is_simd_f3 = false;
        var is_simd_f2 = false;

        // Parse Legacy Prefixes & REX
        while (idx < bytes.len) : (idx += 1) {
            const b = bytes[idx];
            if (b == 0x66) {
                is_16bit = true;
            } else if (b == 0xF3) {
                is_simd_f3 = true;
            } else if (b == 0xF2) {
                is_simd_f2 = true;
            } else if (b >= 0x40 and b <= 0x4F) {
                has_rex = true;
                rex_w = (b & 0x08) != 0;
                rex_r = @intCast((b >> 2) & 1);
                rex_x = @intCast((b >> 1) & 1);
                rex_b = @intCast(b & 1);
                idx += 1;
                break;
            } else {
                break;
            }
        }

        if (idx >= bytes.len) {
            setMnemonic(&inst, "db");
            setOperands(&inst, "0x00");
            inst.len = 1;
            inst.bytes[0] = bytes[0];
            return inst;
        }

        const opcode = bytes[idx];
        idx += 1;

        // 1. One-byte simple opcodes
        if (opcode == 0x90) {
            setMnemonic(&inst, "nop");
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }
        if (opcode == 0xC3) {
            setMnemonic(&inst, "ret");
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }
        if (opcode == 0xCC) {
            setMnemonic(&inst, "int3");
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // PUSH r64 (0x50..0x57)
        if (opcode >= 0x50 and opcode <= 0x57) {
            setMnemonic(&inst, "push");
            const reg_idx = (opcode - 0x50) + (rex_b << 3);
            setOperands(&inst, REG_64[reg_idx]);
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // POP r64 (0x58..0x5F)
        if (opcode >= 0x58 and opcode <= 0x5F) {
            setMnemonic(&inst, "pop");
            const reg_idx = (opcode - 0x58) + (rex_b << 3);
            setOperands(&inst, REG_64[reg_idx]);
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // MOV reg, imm (0xB8..0xBF)
        if (opcode >= 0xB8 and opcode <= 0xBF) {
            setMnemonic(&inst, "mov");
            const reg_idx = (opcode - 0xB8) + (rex_b << 3);
            if (rex_w and idx + 8 <= bytes.len) {
                const imm = std.mem.readInt(u64, bytes[idx..][0..8], .little);
                idx += 8;
                var op_buf: [48]u8 = undefined;
                const ops = std.fmt.bufPrint(&op_buf, "{s}, 0x{X}", .{ REG_64[reg_idx], imm }) catch "";
                setOperands(&inst, ops);
            } else if (idx + 4 <= bytes.len) {
                const imm = std.mem.readInt(u32, bytes[idx..][0..4], .little);
                idx += 4;
                var op_buf: [48]u8 = undefined;
                const ops = std.fmt.bufPrint(&op_buf, "{s}, 0x{X}", .{ REG_32[reg_idx], imm }) catch "";
                setOperands(&inst, ops);
            }
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // Jcc rel8 (0x70..0x7F)
        if (opcode >= 0x70 and opcode <= 0x7F and idx < bytes.len) {
            const cc = opcode - 0x70;
            setMnemonic(&inst, JCC_MNEMONICS[cc]);
            const rel: i8 = @bitCast(bytes[idx]);
            idx += 1;
            const target = @as(isize, @intCast(address + idx)) + rel;
            var op_buf: [48]u8 = undefined;
            const ops = std.fmt.bufPrint(&op_buf, "0x{X}", .{@as(usize, @intCast(target))}) catch "";
            setOperands(&inst, ops);
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // JMP rel8 (0xEB)
        if (opcode == 0xEB and idx < bytes.len) {
            setMnemonic(&inst, "jmp");
            const rel: i8 = @bitCast(bytes[idx]);
            idx += 1;
            const target = @as(isize, @intCast(address + idx)) + rel;
            var op_buf: [48]u8 = undefined;
            const ops = std.fmt.bufPrint(&op_buf, "0x{X}", .{@as(usize, @intCast(target))}) catch "";
            setOperands(&inst, ops);
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // CALL rel32 (0xE8) or JMP rel32 (0xE9)
        if ((opcode == 0xE8 or opcode == 0xE9) and idx + 4 <= bytes.len) {
            setMnemonic(&inst, if (opcode == 0xE8) "call" else "jmp");
            const rel = std.mem.readInt(i32, bytes[idx..][0..4], .little);
            idx += 4;
            const target = @as(isize, @intCast(address + idx)) + rel;
            var op_buf: [48]u8 = undefined;
            const ops = std.fmt.bufPrint(&op_buf, "0x{X}", .{@as(usize, @intCast(target))}) catch "";
            setOperands(&inst, ops);
            inst.len = @intCast(idx);
            @memcpy(inst.bytes[0..idx], bytes[0..idx]);
            return inst;
        }

        // Two-byte opcodes (0x0F ...)
        if (opcode == 0x0F and idx < bytes.len) {
            const op2 = bytes[idx];
            idx += 1;

            // Jcc rel32 (0x0F 0x80..0x8F)
            if (op2 >= 0x80 and op2 <= 0x8F and idx + 4 <= bytes.len) {
                const cc = op2 - 0x80;
                setMnemonic(&inst, JCC_MNEMONICS[cc]);
                const rel = std.mem.readInt(i32, bytes[idx..][0..4], .little);
                idx += 4;
                const target = @as(isize, @intCast(address + idx)) + rel;
                var op_buf: [48]u8 = undefined;
                const ops = std.fmt.bufPrint(&op_buf, "0x{X}", .{@as(usize, @intCast(target))}) catch "";
                setOperands(&inst, ops);
                inst.len = @intCast(idx);
                @memcpy(inst.bytes[0..idx], bytes[0..idx]);
                return inst;
            }

            // SIMD MOVSS/MOVSD
            if (op2 == 0x10 or op2 == 0x11) {
                const is_load = (op2 == 0x10);
                setMnemonic(&inst, if (is_simd_f2) "movsd" else "movss");
                if (idx < bytes.len) {
                    const modrm = bytes[idx];
                    idx += 1;
                    const parsed = parseModRM(bytes[idx..], modrm, rex_r, rex_x, rex_b, rex_w, address + idx);
                    idx += parsed.bytes_consumed;

                    var op_buf: [48]u8 = undefined;
                    const xmm_idx = parsed.reg_idx;
                    const ops = if (is_load)
                        std.fmt.bufPrint(&op_buf, "xmm{d}, {s}", .{ xmm_idx, parsed.getRm() }) catch ""
                    else
                        std.fmt.bufPrint(&op_buf, "{s}, xmm{d}", .{ parsed.getRm(), xmm_idx }) catch "";
                    setOperands(&inst, ops);
                    inst.len = @intCast(idx);
                    @memcpy(inst.bytes[0..idx], bytes[0..idx]);
                    return inst;
                }
            }
        }

        // Group 1: 0x83 (r/m, imm8) and 0x81 (r/m, imm32)
        if ((opcode == 0x83 or opcode == 0x81) and idx < bytes.len) {
            const modrm = bytes[idx];
            idx += 1;
            const sub_op: u3 = @truncate((modrm >> 3) & 7);
            switch (sub_op) {
                0 => setMnemonic(&inst, "add"),
                1 => setMnemonic(&inst, "or"),
                2 => setMnemonic(&inst, "adc"),
                3 => setMnemonic(&inst, "sbb"),
                4 => setMnemonic(&inst, "and"),
                5 => setMnemonic(&inst, "sub"),
                6 => setMnemonic(&inst, "xor"),
                7 => setMnemonic(&inst, "cmp"),
            }
            const parsed = parseModRM(bytes[idx..], modrm, rex_r, rex_x, rex_b, rex_w, address + idx);
            idx += parsed.bytes_consumed;

            if (opcode == 0x83 and idx < bytes.len) {
                const imm8: u8 = bytes[idx];
                idx += 1;
                var op_buf: [48]u8 = undefined;
                const ops = std.fmt.bufPrint(&op_buf, "{s}, 0x{X}", .{ parsed.getRm(), imm8 }) catch "";
                setOperands(&inst, ops);
                inst.len = @intCast(idx);
                @memcpy(inst.bytes[0..idx], bytes[0..idx]);
                return inst;
            } else if (opcode == 0x81 and idx + 4 <= bytes.len) {
                const imm32 = std.mem.readInt(u32, bytes[idx..][0..4], .little);
                idx += 4;
                var op_buf: [48]u8 = undefined;
                const ops = std.fmt.bufPrint(&op_buf, "{s}, 0x{X}", .{ parsed.getRm(), imm32 }) catch "";
                setOperands(&inst, ops);
                inst.len = @intCast(idx);
                @memcpy(inst.bytes[0..idx], bytes[0..idx]);
                return inst;
            }
        }

        // Common ModR/M Operations:
        // 0x89: MOV r/m, reg
        // 0x8B: MOV reg, r/m
        // 0x8D: LEA reg, m
        // 0x01: ADD r/m, reg
        // 0x03: ADD reg, r/m
        // 0x29: SUB r/m, reg
        // 0x2B: SUB reg, r/m
        // 0x31: XOR r/m, reg
        // 0x33: XOR reg, r/m
        // 0x85: TEST r/m, reg
        // 0x39: CMP r/m, reg
        // 0x3B: CMP reg, r/m
        if (idx < bytes.len) {
            const is_mov = (opcode == 0x89 or opcode == 0x8B);
            const is_lea = (opcode == 0x8D);
            const is_add = (opcode == 0x01 or opcode == 0x03);
            const is_sub = (opcode == 0x29 or opcode == 0x2B);
            const is_xor = (opcode == 0x31 or opcode == 0x33);
            const is_test = (opcode == 0x85);
            const is_cmp = (opcode == 0x39 or opcode == 0x3B);

            if (is_mov or is_lea or is_add or is_sub or is_xor or is_test or is_cmp) {
                if (is_mov) setMnemonic(&inst, "mov")
                else if (is_lea) setMnemonic(&inst, "lea")
                else if (is_add) setMnemonic(&inst, "add")
                else if (is_sub) setMnemonic(&inst, "sub")
                else if (is_xor) setMnemonic(&inst, "xor")
                else if (is_test) setMnemonic(&inst, "test")
                else if (is_cmp) setMnemonic(&inst, "cmp");

                const dir_reg_is_dest = (opcode == 0x8B or opcode == 0x8D or opcode == 0x03 or opcode == 0x2B or opcode == 0x33 or opcode == 0x3B);
                const modrm = bytes[idx];
                idx += 1;

                const parsed = parseModRM(bytes[idx..], modrm, rex_r, rex_x, rex_b, rex_w, address + idx);
                idx += parsed.bytes_consumed;

                const reg_str = if (rex_w)
                    REG_64[parsed.reg_idx]
                else if (is_16bit)
                    REG_16[parsed.reg_idx]
                else
                    REG_32[parsed.reg_idx];

                var op_buf: [48]u8 = undefined;
                const ops = if (dir_reg_is_dest)
                    std.fmt.bufPrint(&op_buf, "{s}, {s}", .{ reg_str, parsed.getRm() }) catch ""
                else
                    std.fmt.bufPrint(&op_buf, "{s}, {s}", .{ parsed.getRm(), reg_str }) catch "";
                setOperands(&inst, ops);

                inst.len = @intCast(idx);
                @memcpy(inst.bytes[0..idx], bytes[0..idx]);
                return inst;
            }
        }

        // Generic fallback for unhandled / raw bytes
        setMnemonic(&inst, "db");
        var hex_buf: [8]u8 = undefined;
        const hex = std.fmt.bufPrint(&hex_buf, "0x{X:0>2}", .{bytes[0]}) catch "";
        setOperands(&inst, hex);
        inst.len = 1;
        inst.bytes[0] = bytes[0];
        return inst;
    }

    fn setMnemonic(inst: *Instruction, m: []const u8) void {
        const len = @min(m.len, 16);
        @memcpy(inst.mnemonic[0..len], m[0..len]);
        inst.mnemonic_len = @intCast(len);
    }

    fn setOperands(inst: *Instruction, ops: []const u8) void {
        const len = @min(ops.len, 48);
        @memcpy(inst.operands[0..len], ops[0..len]);
        inst.operands_len = @intCast(len);
    }

    const ModRMResult = struct {
        reg_idx: usize,
        rm_str: [32]u8,
        rm_str_len: usize,
        bytes_consumed: usize,

        pub fn getRm(self: *const ModRMResult) []const u8 {
            return self.rm_str[0..self.rm_str_len];
        }
    };

    fn parseModRM(
        rest: []const u8,
        modrm: u8,
        rex_r: u4,
        rex_x: u4,
        rex_b: u4,
        rex_w: bool,
        current_ip: usize,
    ) ModRMResult {
        var res = ModRMResult{
            .reg_idx = ((modrm >> 3) & 7) + (@as(usize, rex_r) << 3),
            .rm_str = @splat(0),
            .rm_str_len = 0,
            .bytes_consumed = 0,
        };

        const mod = (modrm >> 6) & 3;
        const rm_raw = (modrm & 7) + (@as(usize, rex_b) << 3);

        if (mod == 3) {
            // Direct register
            const reg_name = if (rex_w) REG_64[rm_raw] else REG_32[rm_raw];
            @memcpy(res.rm_str[0..reg_name.len], reg_name);
            res.rm_str_len = reg_name.len;
            return res;
        }

        // Memory addressing modes
        if (mod == 0 and (modrm & 7) == 5) {
            // RIP-relative: [RIP + disp32]
            if (rest.len >= 4) {
                const disp = std.mem.readInt(i32, rest[0..4], .little);
                res.bytes_consumed = 4;
                const target = @as(isize, @intCast(current_ip + 4)) + disp;
                var buf: [32]u8 = undefined;
                const formatted = std.fmt.bufPrint(&buf, "[0x{X}]", .{@as(usize, @intCast(target))}) catch "[rip+disp32]";
                @memcpy(res.rm_str[0..formatted.len], formatted);
                res.rm_str_len = formatted.len;
            }
            return res;
        }

        // Check for SIB byte
        var base_name = REG_64[rm_raw];
        var sib_extra = false;
        var sib_index_str: []const u8 = "";

        if ((modrm & 7) == 4 and rest.len > 0) {
            sib_extra = true;
            const sib = rest[0];
            res.bytes_consumed += 1;
            const sib_base = (sib & 7) + (@as(usize, rex_b) << 3);
            const sib_idx = ((sib >> 3) & 7) + (@as(usize, rex_x) << 3);
            base_name = REG_64[sib_base];
            if (sib_idx != 4) {
                sib_index_str = REG_64[sib_idx];
            }
        }

        const remaining = rest[res.bytes_consumed..];

        if (mod == 0) {
            var buf: [32]u8 = undefined;
            const formatted = if (sib_extra and sib_index_str.len > 0)
                std.fmt.bufPrint(&buf, "[{s}+{s}]", .{ base_name, sib_index_str }) catch "[ptr]"
            else
                std.fmt.bufPrint(&buf, "[{s}]", .{base_name}) catch "[ptr]";
            @memcpy(res.rm_str[0..formatted.len], formatted);
            res.rm_str_len = formatted.len;
        } else if (mod == 1 and remaining.len >= 1) {
            const disp: i8 = @bitCast(remaining[0]);
            res.bytes_consumed += 1;
            var buf: [32]u8 = undefined;
            const formatted = if (disp >= 0)
                std.fmt.bufPrint(&buf, "[{s}+0x{X}]", .{ base_name, @as(u8, @bitCast(disp)) }) catch "[ptr]"
            else
                std.fmt.bufPrint(&buf, "[{s}-0x{X}]", .{ base_name, @as(u8, @bitCast(-disp)) }) catch "[ptr]";
            @memcpy(res.rm_str[0..formatted.len], formatted);
            res.rm_str_len = formatted.len;
        } else if (mod == 2 and remaining.len >= 4) {
            const disp = std.mem.readInt(i32, remaining[0..4], .little);
            res.bytes_consumed += 4;
            var buf: [32]u8 = undefined;
            const formatted = if (disp >= 0)
                std.fmt.bufPrint(&buf, "[{s}+0x{X}]", .{ base_name, @as(u32, @bitCast(disp)) }) catch "[ptr]"
            else
                std.fmt.bufPrint(&buf, "[{s}-0x{X}]", .{ base_name, @as(u32, @bitCast(-disp)) }) catch "[ptr]";
            @memcpy(res.rm_str[0..formatted.len], formatted);
            res.rm_str_len = formatted.len;
        }

        return res;
    }

    /// Disassembles multiple contiguous instructions from an in-memory buffer
    pub fn disassembleBuffer(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        base_address: usize,
        max_instructions: usize,
    ) !std.ArrayList(Instruction) {
        var list: std.ArrayList(Instruction) = .empty;
        errdefer list.deinit(allocator);

        var offset: usize = 0;
        var count: usize = 0;

        while (offset < bytes.len and count < max_instructions) : (count += 1) {
            const inst = decodeInstruction(bytes[offset..], base_address + offset);
            try list.append(allocator, inst);
            offset += if (inst.len == 0) 1 else inst.len;
        }

        return list;
    }

    /// Disassembles code memory from a live Win32 process
    pub fn disassembleProcess(
        allocator: std.mem.Allocator,
        proc: *const process.ProcessHandle,
        address: usize,
        count: usize,
    ) !std.ArrayList(Instruction) {
        var buffer: [256]u8 = undefined;
        const bytes_read = proc.readMemory(address, &buffer) catch 0;
        if (bytes_read == 0) return error.CannotReadProcessCode;

        return disassembleBuffer(allocator, buffer[0..bytes_read], address, count);
    }
};

test "Disassembler decodes common x86_64 game instructions" {
    // 1. mov [rbx+0x248], eax => 89 83 48 02 00 00
    const code1 = [_]u8{ 0x89, 0x83, 0x48, 0x02, 0x00, 0x00 };
    const inst1 = Disassembler.decodeInstruction(&code1, 0x7FF74A8014E4);
    try std.testing.expectEqualStrings("mov", inst1.getMnemonic());
    try std.testing.expectEqualStrings("[rbx+0x248], eax", inst1.getOperands());
    try std.testing.expectEqual(@as(u8, 6), inst1.len);

    // 2. add [rcx+0x18], edx => 01 51 18
    const code2 = [_]u8{ 0x01, 0x51, 0x18 };
    const inst2 = Disassembler.decodeInstruction(&code2, 0x7FF74A8014EA);
    try std.testing.expectEqualStrings("add", inst2.getMnemonic());
    try std.testing.expectEqualStrings("[rcx+0x18], edx", inst2.getOperands());

    // 3. nop, ret => 90 C3
    const code3 = [_]u8{ 0x90, 0xC3 };
    const inst3 = Disassembler.decodeInstruction(code3[0..1], 0x1000);
    try std.testing.expectEqualStrings("nop", inst3.getMnemonic());
    const inst4 = Disassembler.decodeInstruction(code3[1..2], 0x1001);
    try std.testing.expectEqualStrings("ret", inst4.getMnemonic());

    // 4. push rbx, pop rbx => 53 5B
    const inst5 = Disassembler.decodeInstruction(&[_]u8{0x53}, 0x1002);
    try std.testing.expectEqualStrings("push", inst5.getMnemonic());
    try std.testing.expectEqualStrings("rbx", inst5.getOperands());

    const inst6 = Disassembler.decodeInstruction(&[_]u8{0x5B}, 0x1003);
    try std.testing.expectEqualStrings("pop", inst6.getMnemonic());
    try std.testing.expectEqualStrings("rbx", inst6.getOperands());
}
