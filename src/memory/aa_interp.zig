//! ============================================================================
//! SHARABHA (शरभ) — AUTO ASSEMBLER INTERPRETER (स्वयं संयोजक)
//!
//! Cheat Engine `.CT` records are not Lua: they are Auto Assembler scripts with
//! `[ENABLE]` / `[DISABLE]` sections that scan for signatures, allocate remote
//! memory, register symbols and patch bytes. Handing that text to the Lua parser
//! (the previous behaviour) fails on every real-world table.
//!
//! This module implements the subset that 99% of published tables actually use:
//!   aobscanmodule / aobscan / alloc / globalalloc / dealloc / registersymbol /
//!   unregistersymbol / label / define / assert / db / dw / dd / dq / nop
//! plus `{$lua}` … `{$asm}` blocks, `{$try}` markers and `{ … }` comment blocks.
//! Full x86 assembly is *not* emitted; those lines are counted and reported
//! instead of aborting the whole script, so the symbol/pointer half of a table
//! still comes alive.
//!
//! ॐ नमः शरभाय — The hand that reads the foreign altar and writes with our own.
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const win = process.win;
const scanner = @import("scanner.zig");
const aob = @import("aob.zig");
const ce_compat = @import("../scripting/ce_compat.zig");
const engine_mod = @import("../scripting/engine.zig");

pub const Mode = enum { enable, disable };

/// Mirrors Cheat Engine's `memrec` global passed to `{$lua}` blocks.
pub const MemRec = struct {
    id: u32 = 0,
    address: usize = 0,
    description: []const u8 = "",
    active: bool = false,
};

pub const Report = struct {
    allocator: std.mem.Allocator,
    applied: usize = 0,
    skipped_instructions: usize = 0,
    lua_blocks: usize = 0,
    errors: usize = 0,
    log: std.ArrayList(u8) = .empty,

    pub fn line(self: *Report, comptime fmt: []const u8, args: anytype) void {
        self.log.print(self.allocator, fmt, args) catch {};
        self.log.append(self.allocator, '\n') catch {};
    }

    pub fn deinit(self: *Report) void {
        self.log.deinit(self.allocator);
    }
};

/// Executes the requested section of an Auto Assembler script.
/// `proc` may be null (no attached process): scans/allocations then fail
/// gracefully and only the Lua half runs.
pub fn run(
    allocator: std.mem.Allocator,
    engine: *engine_mod.ScriptEngine,
    proc: ?*process.ProcessHandle,
    script: []const u8,
    mode: Mode,
    memrec: MemRec,
) Report {
    var report: Report = .{ .allocator = allocator };
    // Arena for everything the interpreter allocates (label keys, section text);
    // only `report.log` uses the caller's allocator so it can be inspected.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aalloc = arena.allocator();

    var interp: Interpreter = .{
        .allocator = aalloc,
        .engine = engine,
        .proc = proc,
        .report = &report,
        .memrec = memrec,
        .labels = std.StringHashMap(usize).init(aalloc),
    };
    defer interp.labels.deinit();

    const section: []const u8 = selectSection(aalloc, script, mode) orelse script;

    interp.execute(section);

    // Mirror the symbol registry so the opposite section (run in another
    // process) can resolve `dealloc(...)` / `unregistersymbol(...)`.
    ce_compat.persistSymbols();

    return report;
}

/// Extracts the `[ENABLE]` / `[DISABLE]` body. Text before `[ENABLE]` belongs to
/// the enable pass (that is how Cheat Engine treats a leading `{$lua}` header).
fn selectSection(allocator: std.mem.Allocator, script: []const u8, mode: Mode) ?[]u8 {
    const en = indexOfIgnoreCase(script, "[ENABLE]");
    const dis = indexOfIgnoreCase(script, "[DISABLE]");

    switch (mode) {
        .enable => {
            const end = dis orelse script.len;
            if (en) |idx| {
                const head = script[0..idx];
                const body = script[idx + "[ENABLE]".len .. @max(idx + "[ENABLE]".len, end)];
                return std.mem.concat(allocator, u8, &.{ head, "\n", body }) catch null;
            }
            if (dis != null) return allocator.dupe(u8, script[0..end]) catch null;
            return allocator.dupe(u8, script) catch null;
        },
        .disable => {
            const idx = dis orelse return null;
            return allocator.dupe(u8, script[idx + "[DISABLE]".len ..]) catch null;
        },
    }
}

pub fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        for (needle, 0..) |n, j| {
            if (std.ascii.toUpper(haystack[i + j]) != std.ascii.toUpper(n)) {
                matched = false;
                break;
            }
        }
        if (matched) return i;
    }
    return null;
}

// ============================================================================
// INTERPRETER
// ============================================================================

const Interpreter = struct {
    allocator: std.mem.Allocator,
    engine: *engine_mod.ScriptEngine,
    proc: ?*process.ProcessHandle,
    report: *Report,
    memrec: MemRec,
    /// Labels declared by this script (address 0 until a directive sets them).
    labels: std.StringHashMap(usize),
    /// Write cursor of the last `name:` label — data directives advance it.
    cursor: usize = 0,

    fn execute(self: *Interpreter, text: []const u8) void {
        var in_lua = false;
        var in_comment_block = false;
        var lua_buf: std.ArrayList(u8) = .empty;
        defer lua_buf.deinit(self.allocator);

        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");

            if (in_comment_block) {
                if (std.mem.startsWith(u8, line, "}")) in_comment_block = false;
                continue;
            }

            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "//")) continue;

            if (std.mem.startsWith(u8, line, "{")) {
                if (eqlIgnoreCase(line, "{$lua}")) {
                    in_lua = true;
                    continue;
                }
                if (eqlIgnoreCase(line, "{$asm}")) {
                    self.flushLua(&lua_buf);
                    in_lua = false;
                    continue;
                }
                if (eqlIgnoreCase(line, "{$try}") or eqlIgnoreCase(line, "{$except}") or
                    eqlIgnoreCase(line, "{$end}") or eqlIgnoreCase(line, "{$ccode}"))
                {
                    if (eqlIgnoreCase(line, "{$ccode}")) in_comment_block = true;
                    continue;
                }
                // `{` opens a multi-line comment block in Auto Assembler.
                in_comment_block = true;
                continue;
            }

            if (in_lua) {
                lua_buf.appendSlice(self.allocator, raw_line) catch {};
                lua_buf.append(self.allocator, '\n') catch {};
                continue;
            }

            self.executeLine(line);
        }

        self.flushLua(&lua_buf);
    }

    fn executeLine(self: *Interpreter, line_raw: []const u8) void {
        const line = stripLineComment(line_raw);
        if (line.len == 0) return;

        // `label:` — sets the write cursor for subsequent data directives.
        if (line[line.len - 1] == ':') {
            const name = std.mem.trim(u8, line[0 .. line.len - 1], " \t");
            if (name.len == 0) return;
            if (self.labels.get(name)) |known| {
                if (known != 0) {
                    self.cursor = known;
                    return;
                }
            }
            if (self.resolveExpr(name)) |addr| {
                if (addr != 0) {
                    self.cursor = addr;
                    self.labels.put(self.dup(name), addr) catch {};
                    return;
                }
            }
            // A label with no alloc'ed/known address (script bookkeeping only).
            self.report.line("      · label '{s}' has no address (assembly not emitted)", .{name});
            return;
        }

        if (parseCall(line)) |call| {
            self.dispatch(call.name, call.args);
            return;
        }

        if (self.dataDirective(line)) return;

        // Anything left is an x86 instruction we cannot emit.
        self.report.skipped_instructions += 1;
        if (self.report.skipped_instructions <= 3) {
            self.report.line("      · asm not emitted: {s}", .{line});
        }
    }

    fn dup(self: *Interpreter, str: []const u8) []const u8 {
        return self.allocator.dupe(u8, str) catch str;
    }

    fn dispatch(self: *Interpreter, name: []const u8, args: []const u8) void {
        if (eqlIgnoreCase(name, "aobscanmodule")) return self.cmdAobScanModule(args);
        if (eqlIgnoreCase(name, "aobscan")) return self.cmdAobScan(args);
        if (eqlIgnoreCase(name, "aobscanregion")) return self.cmdAobScan(args);
        if (eqlIgnoreCase(name, "alloc") or eqlIgnoreCase(name, "globalalloc")) return self.cmdAlloc(args);
        if (eqlIgnoreCase(name, "dealloc")) return self.cmdDealloc(args);
        if (eqlIgnoreCase(name, "registersymbol")) return self.cmdRegisterSymbol(args);
        if (eqlIgnoreCase(name, "unregistersymbol")) return self.cmdUnregisterSymbol(args);
        if (eqlIgnoreCase(name, "label")) return self.cmdLabel(args);
        if (eqlIgnoreCase(name, "define")) return self.cmdDefine(args);
        if (eqlIgnoreCase(name, "assert")) return self.cmdAssert(args);
        if (eqlIgnoreCase(name, "readmem") or eqlIgnoreCase(name, "include") or
            eqlIgnoreCase(name, "align") or eqlIgnoreCase(name, "createthread") or
            eqlIgnoreCase(name, "luacall") or eqlIgnoreCase(name, "loadlibrary") or
            eqlIgnoreCase(name, "struct") or eqlIgnoreCase(name, "end"))
        {
            // Recognised but intentionally inert: these either only generate
            // bookkeeping inside Cheat Engine or need a real assembler.
            if (!eqlIgnoreCase(name, "align") and !eqlIgnoreCase(name, "readmem")) {
                self.report.line("      · AA command not emulated: {s}", .{name});
            }
            return;
        }
        self.report.line("      · unknown AA command: {s}", .{name});
        self.report.errors += 1;
    }

    /// `aobscanmodule(symbol, module.exe, AA BB ?? CC)`
    fn cmdAobScanModule(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        const module = argAt(args, 1);
        const pattern = argAt(args, 2);
        if (symbol.len == 0 or pattern.len == 0) {
            self.report.line("      ✗ aobscanmodule: missing symbol or pattern", .{});
            self.report.errors += 1;
            return;
        }

        const found = self.scanModule(module, pattern) orelse {
            self.report.line("      ✗ aobscanmodule({s}): pattern not found in {s}", .{ symbol, module });
            self.report.errors += 1;
            return;
        };

        self.labels.put(self.dup(symbol), found.address) catch {};
        ce_compat.registerSymbol(symbol, found.address, self.allocator) catch {};
        self.report.applied += 1;
        self.report.line("      ✓ aobscanmodule({s}) -> 0x{X} ({d} matches)", .{
            symbol, found.address, found.matches,
        });
    }

    fn cmdAobScan(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        // aobscanregion(name, start, stop, pattern) — take the trailing pattern.
        var pattern = argAt(args, 1);
        if (argCount(args) >= 4) pattern = argAt(args, argCount(args) - 1);
        if (symbol.len == 0 or pattern.len == 0) {
            self.report.line("      ✗ aobscan: missing symbol or pattern", .{});
            self.report.errors += 1;
            return;
        }

        const found = self.scanProcess(pattern) orelse {
            self.report.line("      ✗ aobscan({s}): pattern not found in process", .{symbol});
            self.report.errors += 1;
            return;
        };

        self.labels.put(self.dup(symbol), found.address) catch {};
        ce_compat.registerSymbol(symbol, found.address, self.allocator) catch {};
        self.report.applied += 1;
        self.report.line("      ✓ aobscan({s}) -> 0x{X} ({d} matches)", .{
            symbol, found.address, found.matches,
        });
    }

    /// `alloc(symbol, $1000)` / `globalalloc(symbol, $1000)`
    fn cmdAlloc(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        const size = self.resolveExpr(argAt(args, 1)) orelse 0x1000;
        const proc = self.proc orelse {
            self.report.line("      ✗ alloc({s}): no attached process", .{symbol});
            self.report.errors += 1;
            return;
        };

        const raw = win.VirtualAllocEx(
            proc.handle,
            null,
            @max(size, 16),
            win.MEM_COMMIT | win.MEM_RESERVE,
            win.PAGE_EXECUTE_READWRITE,
        ) orelse {
            self.report.line("      ✗ alloc({s}): VirtualAllocEx failed", .{symbol});
            self.report.errors += 1;
            return;
        };

        const addr = @intFromPtr(raw);
        self.labels.put(self.dup(symbol), addr) catch {};
        ce_compat.registerSymbol(symbol, addr, self.allocator) catch {};
        self.report.applied += 1;
        self.report.line("      ✓ alloc({s}, 0x{X}) -> 0x{X}", .{ symbol, size, addr });
    }

    fn cmdDealloc(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        const addr = self.resolveExpr(symbol) orelse return;
        if (self.proc) |proc| {
            _ = win.VirtualFreeEx(proc.handle, @ptrFromInt(addr), 0, win.MEM_RELEASE);
            self.report.applied += 1;
            self.report.line("      ✓ dealloc({s})", .{symbol});
        }
        ce_compat.unregisterSymbol(symbol);
        _ = self.labels.remove(symbol);
    }

    fn cmdRegisterSymbol(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        if (symbol.len == 0) return;
        const addr = self.labels.get(symbol) orelse self.resolveExpr(symbol) orelse 0;
        if (addr == 0) {
            self.report.line("      · registersymbol({s}): unresolved (target not running?)", .{symbol});
            return;
        }
        ce_compat.registerSymbol(symbol, addr, self.allocator) catch {};
        self.report.applied += 1;
        self.report.line("      ✓ registersymbol({s}) = 0x{X}", .{ symbol, addr });
    }

    fn cmdUnregisterSymbol(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        if (symbol.len == 0) return;
        ce_compat.unregisterSymbol(symbol);
        _ = self.labels.remove(symbol);
        self.report.applied += 1;
        self.report.line("      ✓ unregistersymbol({s})", .{symbol});
    }

    /// `label(name)` — declares a label; its address is bound by `name:` or alloc.
    fn cmdLabel(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        if (symbol.len == 0) return;
        const existing = self.labels.get(symbol) orelse 0;
        self.labels.put(self.dup(symbol), existing) catch {};
    }

    fn cmdDefine(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        const value_raw = argAt(args, 1);
        if (symbol.len == 0) return;
        const addr = self.resolveExpr(value_raw) orelse 0;
        self.labels.put(self.dup(symbol), addr) catch {};
        if (addr != 0) ce_compat.registerSymbol(symbol, addr, self.allocator) catch {};
        self.report.applied += 1;
        self.report.line("      ✓ define({s}, 0x{X})", .{ symbol, addr });
    }

    /// `assert(symbol, 80 78 7E 00)` — verifies the target still looks patched.
    fn cmdAssert(self: *Interpreter, args: []const u8) void {
        const symbol = argAt(args, 0);
        const expected = argAt(args, 1);
        const addr = self.resolveExpr(symbol) orelse return;
        const bytes = parseByteList(self.allocator, expected) orelse return;
        defer self.allocator.free(bytes);
        if (bytes.len == 0) return;

        var actual: [32]u8 = undefined;
        const want = @min(bytes.len, actual.len);
        const got = self.readBytes(addr, actual[0..want]) catch {
            self.report.line("      · assert({s}): unreadable at 0x{X}", .{ symbol, addr });
            return;
        };
        if (!std.mem.eql(u8, got, bytes[0..want])) {
            self.report.line("      ⚠ assert({s}) mismatch at 0x{X}", .{ symbol, addr });
        }
    }

    // ------------------------------------------------------------------
    // SIGNATURE SCANNING
    // ------------------------------------------------------------------

    const ScanHit = struct { address: usize, matches: usize };

    fn scanModule(self: *Interpreter, module: []const u8, pattern: []const u8) ?ScanHit {
        const proc = self.proc orelse return null;
        return scanModulePattern(self.allocator, proc, module, pattern);
    }

    fn scanProcess(self: *Interpreter, pattern: []const u8) ?ScanHit {
        const proc = self.proc orelse return null;
        return scanProcessPattern(self.allocator, proc, pattern);
    }

    fn scanRange(self: *Interpreter, base: usize, size: usize, pat: *const aob.AobPattern) ?ScanHit {
        const proc = self.proc orelse return null;
        return scanRangePattern(self.allocator, proc, base, size, pat);
    }
    // ------------------------------------------------------------------
    // ADDRESS EXPRESSIONS
    // ------------------------------------------------------------------

    /// Resolves `sym`, `sym+0x10`, `module.exe+24A266F`, `$process+40`, `0x1234`.
    fn resolveExpr(self: *Interpreter, expr_raw: []const u8) ?usize {
        var expr = std.mem.trim(u8, expr_raw, " \t\r\n");
        expr = std.mem.trim(u8, expr, "\"'()");
        if (expr.len == 0) return null;

        var total: usize = 0;
        var any = false;
        var index: usize = 0;
        var term_start: usize = 0;
        var add = true;

        while (index <= expr.len) : (index += 1) {
            const is_sep = index == expr.len or expr[index] == '+' or expr[index] == '-';
            if (!is_sep) continue;
            const term = std.mem.trim(u8, expr[term_start..index], " \t");
            if (term.len > 0) {
                const value = self.resolveTerm(term) orelse return null;
                total = if (add) total +% value else total -% value;
                any = true;
            }
            if (index < expr.len) add = expr[index] == '+';
            term_start = index + 1;
        }
        return if (any) total else null;
    }

    fn resolveTerm(self: *Interpreter, term: []const u8) ?usize {
        if (term.len == 0) return null;

        if (std.mem.eql(u8, term, "$process")) return self.mainModuleBase();

        if (self.labels.get(term)) |addr| {
            if (addr != 0) return addr;
        }
        if (ce_compat.lookupSymbol(term)) |addr| {
            if (addr != 0) return addr;
        }

        if (std.mem.indexOf(u8, term, ".") != null) {
            if (self.moduleBase(term)) |base| return base;
        }

        if (term[0] == '$') {
            return std.fmt.parseInt(usize, term[1..], 16) catch null;
        }
        if (std.mem.startsWith(u8, term, "0x") or std.mem.startsWith(u8, term, "0X")) {
            return std.fmt.parseInt(usize, term[2..], 16) catch null;
        }
        // Auto Assembler literals are hexadecimal unless they cannot be.
        if (std.fmt.parseInt(usize, term, 16)) |hex_value| {
            return hex_value;
        } else |_| {}
        return std.fmt.parseInt(usize, term, 10) catch null;
    }

    fn mainModuleBase(self: *Interpreter) ?usize {
        const proc = self.proc orelse return null;
        var iter = process.ModuleIterator.init(proc.pid) catch return null;
        defer iter.deinit();
        const m = iter.next() orelse return null;
        return m.base_address;
    }

    fn moduleBase(self: *Interpreter, name: []const u8) ?usize {
        const proc = self.proc orelse return null;
        var iter = process.ModuleIterator.init(proc.pid) catch return null;
        defer iter.deinit();
        while (iter.next()) |m| {
            if (eqlIgnoreCase(m.getName(), name)) return m.base_address;
        }
        return null;
    }

    // ------------------------------------------------------------------
    // MEMORY PRIMITIVES
    // ------------------------------------------------------------------

    fn readBytes(self: *Interpreter, addr: usize, buf: []u8) ![]u8 {
        const proc = self.proc orelse return error.NoProcess;
        const got = try proc.readMemory(addr, buf);
        return buf[0..got];
    }

    fn writeBytes(self: *Interpreter, addr: usize, bytes: []const u8) bool {
        const proc = self.proc orelse return false;
        var old_protect: u32 = 0;
        _ = win.VirtualProtectEx(proc.handle, @ptrFromInt(addr), bytes.len, win.PAGE_EXECUTE_READWRITE, &old_protect);
        const written = proc.writeMemory(addr, bytes) catch 0;
        if (old_protect != 0) {
            var ignored: u32 = 0;
            _ = win.VirtualProtectEx(proc.handle, @ptrFromInt(addr), bytes.len, old_protect, &ignored);
        }
        return written == bytes.len;
    }

    /// `db 80 78 7E 01` / `dw 0x1F` / `dd` / `dq` / `nop 3` at the write cursor.
    fn dataDirective(self: *Interpreter, line: []const u8) bool {
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const kind = tokens.next() orelse return false;
        const width: usize = if (eqlIgnoreCase(kind, "db"))
            1
        else if (eqlIgnoreCase(kind, "dw"))
            2
        else if (eqlIgnoreCase(kind, "dd"))
            4
        else if (eqlIgnoreCase(kind, "dq"))
            8
        else
            0;

        if (eqlIgnoreCase(kind, "nop")) {
            const rest = std.mem.trim(u8, line[kind.len..], " \t");
            const count = std.fmt.parseInt(usize, rest, 16) catch 1;
            if (self.cursor == 0) return true;
            var pads: [64]u8 = undefined;
            @memset(&pads, 0x90);
            var remaining = @min(count, 64);
            var addr = self.cursor;
            while (remaining > 0) : (remaining -= 1) {
                if (!self.writeBytes(addr, pads[0..1])) break;
                addr += 1;
            }
            self.cursor = addr;
            self.report.applied += 1;
            return true;
        }

        if (width == 0) return false;
        if (self.cursor == 0) {
            self.report.line("      · {s}: no label before data directive", .{kind});
            return true;
        }

        const patch_start = self.cursor;
        var bytes_written: usize = 0;
        var token_iter = std.mem.splitAny(u8, line[kind.len..], " \t,");
        while (token_iter.next()) |token_raw| {
            const token = std.mem.trim(u8, token_raw, " \t\r");
            if (token.len == 0) continue;
            const value = std.fmt.parseInt(usize, token, 16) catch continue;
            var le: [8]u8 = undefined;
            var i: usize = 0;
            while (i < width) : (i += 1) {
                le[i] = @truncate(value >> @intCast(i * 8));
            }
            if (!self.writeBytes(patch_start + bytes_written, le[0..width])) {
                self.report.line("      ✗ {s}: write failed at 0x{X}", .{ kind, patch_start + bytes_written });
                self.report.errors += 1;
                return true;
            }
            bytes_written += width;
        }

        self.cursor = patch_start + bytes_written;
        if (bytes_written > 0) {
            self.report.applied += 1;
            self.report.line("      ✓ {s} patch at 0x{X} ({d} byte{s})", .{
                kind, patch_start, bytes_written, if (bytes_written == 1) "" else "s",
            });
        }
        return true;
    }

    // ------------------------------------------------------------------
    // LUA BLOCKS
    // ------------------------------------------------------------------

    /// Runs a collected `{$lua}` block with `memrec` and every AA label exposed
    /// as a Lua global, exactly like Cheat Engine does for a script record.
    fn flushLua(self: *Interpreter, buf: *std.ArrayList(u8)) void {
        if (buf.items.len == 0) return;
        defer buf.clearRetainingCapacity();

        var prelude: std.ArrayList(u8) = .empty;
        defer prelude.deinit(self.allocator);

        prelude.appendSlice(self.allocator, "syntaxcheck = false\n") catch return;
        prelude.print(self.allocator, "memrec = {{ ID = {d}, Address = 0x{X}, Description = \"", .{
            self.memrec.id, self.memrec.address,
        }) catch return;
        for (self.memrec.description) |ch| {
            if (ch == '"' or ch == '\\') {
                prelude.append(self.allocator, '\\') catch return;
            }
            prelude.append(self.allocator, ch) catch return;
        }
        prelude.print(self.allocator, "\", Active = {s} }}\n", .{
            if (self.memrec.active) "true" else "false",
        }) catch return;

        var it = self.labels.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.* == 0) continue;
            prelude.print(self.allocator, "{s} = 0x{X}\n", .{ kv.key_ptr.*, kv.value_ptr.* }) catch {};
        }

        const code = std.mem.concat(self.allocator, u8, &.{ prelude.items, buf.items, "\n" }) catch return;
        defer self.allocator.free(code);

        const code_z = self.allocator.allocSentinel(u8, code.len, 0) catch return;
        defer self.allocator.free(code_z);
        @memcpy(code_z, code);

        const result = self.engine.executeWithOutput(code_z);
        self.report.lua_blocks += 1;

        const output = std.mem.trim(u8, result.output, " \r\n");
        if (output.len > 0) {
            var lines = std.mem.splitScalar(u8, output, '\n');
            var printed: usize = 0;
            while (lines.next()) |out_line| {
                if (printed >= 6) {
                    self.report.line("      · … lua output truncated", .{});
                    break;
                }
                self.report.line("      │ {s}", .{std.mem.trimEnd(u8, out_line, "\r")});
                printed += 1;
            }
        }
        if (result.success) {
            self.report.applied += 1;
        } else {
            self.report.errors += 1;
            self.report.line("      ✗ lua block error: {s}", .{result.error_msg orelse "unknown"});
        }
    }
};

/// Scans one module (or the main module for `$process`) for a signature.
pub fn scanModulePattern(
    allocator: std.mem.Allocator,
    proc: *process.ProcessHandle,
    module: []const u8,
    pattern: []const u8,
) ?Interpreter.ScanHit {
    var pat = aob.AobPattern.parse(allocator, pattern) catch return null;
    defer pat.deinit();
    if (pat.bytes.len == 0) return null;

    var iter = process.ModuleIterator.init(proc.pid) catch return null;
    defer iter.deinit();

    const wants_main = module.len == 0 or std.mem.eql(u8, module, "$process");
    var fallback_base: usize = 0;
    var fallback_size: usize = 0;
    while (iter.next()) |m| {
        if (fallback_base == 0) {
            fallback_base = m.base_address;
            fallback_size = m.size;
        }
        if (eqlIgnoreCase(m.getName(), module)) {
            if (scanRangePattern(allocator, proc, m.base_address, m.size, &pat)) |hit| return hit;
        }
    }
    if (wants_main and fallback_base != 0) {
        return scanRangePattern(allocator, proc, fallback_base, fallback_size, &pat);
    }
    return null;
}

/// Whole-process AOB search: modules first (fast), then committed private
/// regions, with a byte budget so a single click never hangs the UI.
pub fn scanProcessPattern(
    allocator: std.mem.Allocator,
    proc: *process.ProcessHandle,
    pattern: []const u8,
) ?Interpreter.ScanHit {
    var pat = aob.AobPattern.parse(allocator, pattern) catch return null;
    defer pat.deinit();
    if (pat.bytes.len == 0) return null;

    var iter = process.ModuleIterator.init(proc.pid) catch null;
    if (iter) |*it| {
        defer it.deinit();
        while (it.next()) |m| {
            if (scanRangePattern(allocator, proc, m.base_address, m.size, &pat)) |hit| return hit;
        }
    }

    var regions = scanner.RegionIterator.init(proc);
    var budget: usize = 192 * 1024 * 1024;
    while (regions.next()) |region| {
        if (region.size > 32 * 1024 * 1024) continue;
        if (budget < region.size) break;
        budget -= region.size;
        if (scanRangePattern(allocator, proc, region.base_address, region.size, &pat)) |hit| return hit;
    }
    return null;
}

/// Chunked signature scan with a 1-byte overlap so matches spanning a chunk
/// boundary are still found.
pub fn scanRangePattern(
    allocator: std.mem.Allocator,
    proc: *process.ProcessHandle,
    base: usize,
    size: usize,
    pat: *const aob.AobPattern,
) ?Interpreter.ScanHit {
    const chunk: usize = 4 * 1024 * 1024;
    const buf = allocator.alloc(u8, chunk + pat.bytes.len) catch return null;
    defer allocator.free(buf);

    var first: usize = 0;
    var matches: usize = 0;
    var offset: usize = 0;

    while (offset < size) {
        const want = @min(chunk + pat.bytes.len - 1, size - offset);
        if (want < pat.bytes.len) break;
        const got = proc.readMemory(base + offset, buf[0..want]) catch break;
        if (got >= pat.bytes.len) {
            var cursor: usize = 0;
            while (cursor + pat.bytes.len <= got) {
                const rel = pat.findFirst(buf[cursor..got]) orelse break;
                matches += 1;
                if (first == 0) first = base + offset + cursor + rel;
                cursor += rel + 1;
                if (matches >= 64) break;
            }
        }
        offset += chunk;
    }

    if (matches == 0) return null;
    return .{ .address = first, .matches = matches };
}


// ============================================================================
// TEXT HELPERS
// ============================================================================

pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

/// Cuts a trailing `//` comment (Auto Assembler has no string escaping there).
fn stripLineComment(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "//")) |idx| {
        return std.mem.trim(u8, line[0..idx], " \t");
    }
    return line;
}

const Call = struct { name: []const u8, args: []const u8 };

/// Recognises `name(a, b, c)` — returns name plus the inner argument text.
fn parseCall(line: []const u8) ?Call {
    const open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    if (line[line.len - 1] != ')') return null;
    const name = std.mem.trim(u8, line[0..open], " \t");
    if (name.len == 0) return null;
    for (name) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '.') return null;
    }
    return .{ .name = name, .args = line[open + 1 .. line.len - 1] };
}

fn argCount(args: []const u8) usize {
    var count: usize = 0;
    var depth: usize = 0;
    for (args) |ch| {
        switch (ch) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            ',' => {
                if (depth == 0) count += 1;
            },
            else => {},
        }
    }
    if (std.mem.trim(u8, args, " \t").len == 0) return 0;
    return count + 1;
}

/// Nth (0-based) comma-separated argument, trimmed and unquoted.
fn argAt(args: []const u8, index: usize) []const u8 {
    var depth: usize = 0;
    var current: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= args.len) : (i += 1) {
        const at_end = i == args.len;
        if (!at_end) switch (args[i]) {
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            else => {},
        };
        const is_sep = at_end or (args[i] == ',' and depth == 0);
        if (!is_sep) continue;
        if (current == index) {
            var value = std.mem.trim(u8, args[start..i], " \t\r\n");
            value = std.mem.trim(u8, value, "\"'");
            return value;
        }
        current += 1;
        start = i + 1;
    }
    return "";
}

/// Parses `80 78 7E 00` / `0x80,0x78` / `"text",0` into raw bytes.
fn parseByteList(allocator: std.mem.Allocator, text: []const u8) ?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const ch = text[i];
        if (ch == '"') {
            i += 1;
            while (i < text.len and text[i] != '"') : (i += 1) {
                out.append(allocator, text[i]) catch {};
            }
            i += 1;
            continue;
        }
        if (std.ascii.isHex(ch)) {
            var start = i;
            if (ch == '0' and i + 1 < text.len and (text[i + 1] == 'x' or text[i + 1] == 'X')) {
                i += 2;
                start = i;
            }
            while (i < text.len and std.ascii.isHex(text[i])) : (i += 1) {}
            const token = text[start..i];
            const value = std.fmt.parseInt(u8, token[0..@min(token.len, 2)], 16) catch {
                continue;
            };
            out.append(allocator, value) catch {};
            continue;
        }
        i += 1;
    }
    if (out.items.len == 0) {
        out.deinit(allocator);
        return null;
    }
    return out.toOwnedSlice(allocator) catch {
        out.deinit(allocator);
        return null;
    };
}

// ============================================================================
// TESTS
// ============================================================================

test "aa_interp selects [ENABLE]/[DISABLE] sections" {
    const allocator = std.testing.allocator;
    const script = "[ENABLE]\nalloc(newmem,$1000)\n[DISABLE]\ndealloc(newmem)\n";

    const en = selectSection(allocator, script, .enable) orelse return error.SectionMissing;
    defer allocator.free(en);
    try std.testing.expect(std.mem.indexOf(u8, en, "alloc(newmem,$1000)") != null);
    try std.testing.expect(std.mem.indexOf(u8, en, "dealloc(newmem)") == null);

    const dis = selectSection(allocator, script, .disable) orelse return error.SectionMissing;
    defer allocator.free(dis);
    try std.testing.expect(std.mem.indexOf(u8, dis, "dealloc(newmem)") != null);
    try std.testing.expect(std.mem.indexOf(u8, dis, "alloc(newmem,$1000)") == null);

    // A Lua-only record has no sections: enable returns the whole body.
    const lua_only = "print('hello')";
    const whole = selectSection(allocator, lua_only, .enable) orelse return error.SectionMissing;
    defer allocator.free(whole);
    try std.testing.expectEqualStrings(lua_only, whole);
}

test "aa_interp parses calls, arguments and byte lists" {
    const call = parseCall("aobscanmodule(console, $process, 3B ?? 2C 73)").?;
    try std.testing.expectEqualStrings("aobscanmodule", call.name);
    try std.testing.expectEqualStrings("console", argAt(call.args, 0));
    try std.testing.expectEqualStrings("$process", argAt(call.args, 1));
    try std.testing.expectEqualStrings("3B ?? 2C 73", argAt(call.args, 2));
    try std.testing.expectEqual(@as(usize, 3), argCount(call.args));

    // Instruction lines are not calls.
    try std.testing.expect(parseCall("mov rcx,cmdList") == null);

    const bytes = parseByteList(std.testing.allocator, "80 78 7e 01").?;
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x78, 0x7E, 0x01 }, bytes);

    const strings = parseByteList(std.testing.allocator, "\"AB\",00").?;
    defer std.testing.allocator.free(strings);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 'B', 0x00 }, strings);
}

test "aa_interp runs {$lua} blocks with memrec and tolerates missing process" {
    var engine = try engine_mod.ScriptEngine.init(std.testing.allocator, null);
    defer engine.deinit();

    const script =
        \\[ENABLE]
        \\label(pad)
        \\nop 2
        \\{$lua}
        \\print('aa lua ok id=' .. tostring(memrec.ID))
        \\{$asm}
        \\mov rcx,rax
        \\[DISABLE]
        \\{$lua}
        \\print('aa disable ok')
        \\{$asm}
    ;

    var report = run(std.testing.allocator, &engine, null, script, .enable, .{ .id = 42, .description = "Test Record" });
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 1), report.lua_blocks);
    try std.testing.expect(std.mem.indexOf(u8, report.log.items, "aa lua ok id=42") != null);
    // `mov rcx,rax` cannot be assembled but must not abort the script.
    try std.testing.expectEqual(@as(usize, 1), report.skipped_instructions);
    try std.testing.expect(std.mem.indexOf(u8, report.log.items, "aa disable ok") == null);

    var disable_report = run(std.testing.allocator, &engine, null, script, .disable, .{ .id = 42 });
    defer disable_report.deinit();
    try std.testing.expect(std.mem.indexOf(u8, disable_report.log.items, "aa disable ok") != null);
}
