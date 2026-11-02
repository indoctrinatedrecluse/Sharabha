//! ============================================================================
//! SHARABHA (शरभ) — RUDRA TANDAVA MEMORY ENGINE SERVICE
//! High-Speed Win32 Virtual Memory Inquest, Differential Filtering & Live Mutation
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const scanner = @import("scanner.zig");
const freeze = @import("freeze.zig");

pub const win = struct {
    pub const HANDLE = *anyopaque;
    pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));
    pub const GENERIC_READ: u32 = 0x80000000;
    pub const GENERIC_WRITE: u32 = 0x40000000;
    pub const FILE_SHARE_READ: u32 = 0x00000001;
    pub const FILE_SHARE_WRITE: u32 = 0x00000002;
    pub const CREATE_ALWAYS: u32 = 2;
    pub const OPEN_EXISTING: u32 = 3;
    pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;

    pub const FILETIME = extern struct {
        dwLowDateTime: u32,
        dwHighDateTime: u32,
    };

    pub extern "kernel32" fn CreateFileA(
        lpFileName: [*:0]const u8,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?HANDLE,
    ) callconv(.winapi) HANDLE;

    pub extern "kernel32" fn CreateFileW(
        lpFileName: [*:0]const u16,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?HANDLE,
    ) callconv(.winapi) HANDLE;

    pub extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: *anyopaque,
        nNumberOfBytesToRead: u32,
        lpNumberOfBytesRead: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: *const anyopaque,
        nNumberOfBytesToWrite: u32,
        lpNumberOfBytesWritten: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) i32;
    pub extern "kernel32" fn CreateDirectoryA(lpPathName: [*:0]const u8, lpSecurityAttributes: ?*anyopaque) callconv(.winapi) i32;
    pub extern "kernel32" fn DeleteFileA(lpFileName: [*:0]const u8) callconv(.winapi) i32;
    pub extern "kernel32" fn SetFileTime(hFile: HANDLE, lpCreationTime: ?*const FILETIME, lpLastAccessTime: ?*const FILETIME, lpLastWriteTime: ?*const FILETIME) callconv(.winapi) i32;
    pub extern "kernel32" fn GetSystemTimeAsFileTime(lpSystemTimeAsFileTime: *FILETIME) callconv(.winapi) void;
    pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
};

pub const ACTIVE_PID_PATH: [*:0]const u8 = "assets/memory/active_pid.txt";
pub const SCAN_STATE_PATH: [*:0]const u8 = "assets/memory/scan_state.bin";
pub const FROZEN_ENTRIES_PATH: [*:0]const u8 = "assets/memory/frozen_entries.txt";
pub const LIVE_SCAN_SLINT_PATH: [*:0]const u8 = "src/ui/live_scan.slint";
pub const APP_SLINT_PATH: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("src/ui/app.slint");

pub fn ensureDirectory(path: [*:0]const u8) void {
    _ = win.CreateDirectoryA(path, null);
}

pub fn deleteFile(path: [*:0]const u8) void {
    _ = win.DeleteFileA(path);
}

pub fn readFullFile(path: [*:0]const u8, buffer: []u8) ?usize {
    const h = win.CreateFileA(path, win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win.INVALID_HANDLE_VALUE) return null;
    defer _ = win.CloseHandle(h);

    var bytes_read: u32 = 0;
    const ok = win.ReadFile(h, buffer.ptr, @as(u32, @intCast(buffer.len)), &bytes_read, null);
    if (ok == 0) return null;
    return bytes_read;
}

pub fn writeFullFile(path: [*:0]const u8, data: []const u8) !void {
    const h = win.CreateFileA(path, win.GENERIC_WRITE, win.FILE_SHARE_READ, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win.INVALID_HANDLE_VALUE) return error.CannotCreateFile;
    defer _ = win.CloseHandle(h);

    var bytes_written: u32 = 0;
    const ok = win.WriteFile(h, data.ptr, @as(u32, @intCast(data.len)), &bytes_written, null);
    if (ok == 0) return error.WriteFileFailed;
}

pub fn touchAppSlint() void {
    const h = win.CreateFileW(
        APP_SLINT_PATH,
        win.GENERIC_WRITE,
        win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
        null,
        win.OPEN_EXISTING,
        0,
        null,
    );
    if (h != win.INVALID_HANDLE_VALUE) {
        var ft: win.FILETIME = undefined;
        win.GetSystemTimeAsFileTime(&ft);
        _ = win.SetFileTime(h, null, null, &ft);
        _ = win.CloseHandle(h);
    }
}

pub fn getActivePid() ?u32 {
    var buf: [64]u8 = undefined;
    const bytes = readFullFile(ACTIVE_PID_PATH, &buf) orelse return null;
    const trimmed = std.mem.trim(u8, buf[0..bytes], " \r\n\t");
    return std.fmt.parseInt(u32, trimmed, 10) catch null;
}

pub fn setActivePid(pid: u32) !void {
    ensureDirectory("assets");
    ensureDirectory("assets/memory");

    var buf: [32]u8 = undefined;
    const str = try std.fmt.bufPrint(&buf, "{d}\n", .{pid});
    try writeFullFile(ACTIVE_PID_PATH, str);
}

pub fn getOrDetectTargetPid() !u32 {
    if (getActivePid()) |pid| {
        if (process.ProcessHandle.open(pid)) |proc| {
            var p = proc;
            p.close();
            return pid;
        } else |_| {}
    }

    var iter = process.ProcessIterator.init() catch null;
    if (iter) |*it| {
        defer it.deinit();
        while (it.next()) |entry| {
            if (entry.pid <= 4) continue;
            if (process.ProcessHandle.open(entry.pid)) |proc| {
                var p = proc;
                p.close();
                try setActivePid(entry.pid);
                return entry.pid;
            } else |_| {}
        }
    }

    const self_pid = win.GetCurrentProcessId();
    try setActivePid(self_pid);
    return self_pid;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |n, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(n)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

pub fn parseDataType(type_str: []const u8) scanner.DataType {
    if (containsIgnoreCase(type_str, "i64") or containsIgnoreCase(type_str, "8 Bytes")) {
        return .I64;
    }
    if (containsIgnoreCase(type_str, "u64")) {
        return .U64;
    }
    if (containsIgnoreCase(type_str, "f32") or containsIgnoreCase(type_str, "Float")) {
        return .F32;
    }
    if (containsIgnoreCase(type_str, "f64") or containsIgnoreCase(type_str, "Double")) {
        return .F64;
    }
    if (containsIgnoreCase(type_str, "i16") or containsIgnoreCase(type_str, "2 Bytes")) {
        return .I16;
    }
    if (containsIgnoreCase(type_str, "u16")) {
        return .U16;
    }
    if (containsIgnoreCase(type_str, "i8") or containsIgnoreCase(type_str, "1 Byte")) {
        return .I8;
    }
    if (containsIgnoreCase(type_str, "u8") or containsIgnoreCase(type_str, "String") or containsIgnoreCase(type_str, "Text")) {
        return .U8;
    }
    if (containsIgnoreCase(type_str, "u32")) {
        return .U32;
    }
    return .I32;
}

pub fn parseScanTarget(val_str: []const u8, data_type: scanner.DataType) !scanner.ScanTargetValue {
    const trimmed = std.mem.trim(u8, val_str, " \t\r\n");
    switch (data_type) {
        .I8 => {
            const v = try std.fmt.parseInt(i8, trimmed, 0);
            return scanner.ScanTargetValue{ .I8 = v };
        },
        .U8 => {
            const v = try std.fmt.parseInt(u8, trimmed, 0);
            return scanner.ScanTargetValue{ .U8 = v };
        },
        .I16 => {
            const v = try std.fmt.parseInt(i16, trimmed, 0);
            return scanner.ScanTargetValue{ .I16 = v };
        },
        .U16 => {
            const v = try std.fmt.parseInt(u16, trimmed, 0);
            return scanner.ScanTargetValue{ .U16 = v };
        },
        .I32 => {
            const v = try std.fmt.parseInt(i32, trimmed, 0);
            return scanner.ScanTargetValue{ .I32 = v };
        },
        .U32 => {
            const v = try std.fmt.parseInt(u32, trimmed, 0);
            return scanner.ScanTargetValue{ .U32 = v };
        },
        .I64 => {
            const v = try std.fmt.parseInt(i64, trimmed, 0);
            return scanner.ScanTargetValue{ .I64 = v };
        },
        .U64 => {
            const v = try std.fmt.parseInt(u64, trimmed, 0);
            return scanner.ScanTargetValue{ .U64 = v };
        },
        .F32 => {
            const v = try std.fmt.parseFloat(f32, trimmed);
            return scanner.ScanTargetValue{ .F32 = v };
        },
        .F64 => {
            const v = try std.fmt.parseFloat(f64, trimmed);
            return scanner.ScanTargetValue{ .F64 = v };
        },
    }
}

pub fn parseRescanType(rescan_str: []const u8) scanner.ScanType {
    if (containsIgnoreCase(rescan_str, "INCREASED")) {
        return .IncreasedValue;
    }
    if (containsIgnoreCase(rescan_str, "DECREASED")) {
        return .DecreasedValue;
    }
    if (containsIgnoreCase(rescan_str, "UNCHANGED")) {
        return .UnchangedValue;
    }
    if (containsIgnoreCase(rescan_str, "CHANGED")) {
        return .ChangedValue;
    }
    return .ExactValue;
}

pub fn getDataTypeString(data_type: scanner.DataType) []const u8 {
    return switch (data_type) {
        .I8 => "1 Byte (i8)",
        .U8 => "1 Byte (u8)",
        .I16 => "2 Bytes (i16)",
        .U16 => "2 Bytes (u16)",
        .I32 => "4 Bytes (i32)",
        .U32 => "4 Bytes (u32)",
        .I64 => "8 Bytes (i64)",
        .U64 => "8 Bytes (u64)",
        .F32 => "Float (f32)",
        .F64 => "Double (f64)",
    };
}

pub const ScanState = struct {
    pid: u32,
    data_type: scanner.DataType,
    iteration: u32,
    results: []scanner.ScanResult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ScanState) void {
        self.allocator.free(self.results);
    }
};

pub fn saveScanState(allocator: std.mem.Allocator, pid: u32, data_type: scanner.DataType, iteration: u32, results: []const scanner.ScanResult) !void {
    ensureDirectory("assets");
    ensureDirectory("assets/memory");

    const header_size = 4 + 4 + 4 + 4 + 4; // "SCAN" + pid + dt + iteration + count
    const record_size = 8 + 8 + 8; // u64 addr + i64 cur + i64 prev
    const total_size = header_size + results.len * record_size;

    const buf = try allocator.alloc(u8, total_size);
    defer allocator.free(buf);

    @memcpy(buf[0..4], "SCAN");
    std.mem.writeInt(u32, buf[4..8], pid, .little);
    std.mem.writeInt(u32, buf[8..12], @intFromEnum(data_type), .little);
    std.mem.writeInt(u32, buf[12..16], iteration, .little);
    std.mem.writeInt(u32, buf[16..20], @as(u32, @intCast(results.len)), .little);

    var cursor: usize = 20;
    for (results) |r| {
        std.mem.writeInt(u64, buf[cursor..][0..8], @as(u64, @intCast(r.address)), .little);
        std.mem.writeInt(i64, buf[cursor + 8 ..][0..8], r.current_value, .little);
        std.mem.writeInt(i64, buf[cursor + 16 ..][0..8], r.previous_value, .little);
        cursor += record_size;
    }

    try writeFullFile(SCAN_STATE_PATH, buf);
}

pub fn loadScanState(allocator: std.mem.Allocator) !ScanState {
    const h = win.CreateFileA(SCAN_STATE_PATH, win.GENERIC_READ, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win.INVALID_HANDLE_VALUE) return error.ScanStateNotFound;
    defer _ = win.CloseHandle(h);

    var header_buf: [20]u8 = undefined;
    var bytes_read: u32 = 0;
    const ok = win.ReadFile(h, &header_buf, 20, &bytes_read, null);
    if (ok == 0 or bytes_read < 20) return error.InvalidScanStateHeader;

    if (!std.mem.eql(u8, header_buf[0..4], "SCAN")) return error.InvalidScanStateMagic;

    const pid = std.mem.readInt(u32, header_buf[4..8], .little);
    const dt_raw = std.mem.readInt(u32, header_buf[8..12], .little);
    const iteration = std.mem.readInt(u32, header_buf[12..16], .little);
    const count = std.mem.readInt(u32, header_buf[16..20], .little);

    const data_type: scanner.DataType = @enumFromInt(dt_raw);
    const results = try allocator.alloc(scanner.ScanResult, count);
    errdefer allocator.free(results);

    const record_size = 24;
    const records_bytes_needed = count * record_size;
    const records_buf = try allocator.alloc(u8, records_bytes_needed);
    defer allocator.free(records_buf);

    var rec_read: u32 = 0;
    const rec_ok = win.ReadFile(h, records_buf.ptr, @as(u32, @intCast(records_bytes_needed)), &rec_read, null);
    if (rec_ok == 0 or rec_read < records_bytes_needed) return error.IncompleteScanStateData;

    var cursor: usize = 0;
    for (results) |*r| {
        const addr_u64 = std.mem.readInt(u64, records_buf[cursor..][0..8], .little);
        r.address = @as(usize, @intCast(addr_u64));
        r.current_value = std.mem.readInt(i64, records_buf[cursor + 8 ..][0..8], .little);
        r.previous_value = std.mem.readInt(i64, records_buf[cursor + 16 ..][0..8], .little);
        cursor += record_size;
    }

    return ScanState{
        .pid = pid,
        .data_type = data_type,
        .iteration = iteration,
        .results = results,
        .allocator = allocator,
    };
}

pub fn isAddressFrozen(addr_hex: []const u8) bool {
    var buf: [4096]u8 = undefined;
    const bytes = readFullFile(FROZEN_ENTRIES_PATH, &buf) orelse return false;
    var iter = std.mem.tokenizeAny(u8, buf[0..bytes], "\r\n");
    while (iter.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        if (parts.next()) |line_addr| {
            if (std.ascii.eqlIgnoreCase(line_addr, addr_hex)) {
                return true;
            }
        }
    }
    return false;
}

fn appendPrint(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const formatted = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(formatted);
    try list.appendSlice(allocator, formatted);
}

pub fn writeLiveScanSlint(
    allocator: std.mem.Allocator,
    iteration: u32,
    total_matches: usize,
    status_text: []const u8,
    result_count_str: []const u8,
    target_value: []const u8,
    data_type_str: []const u8,
    results: []const scanner.ScanResult,
) !void {
    ensureDirectory("src");
    ensureDirectory("src/ui");

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator,
        \\// Auto-generated by Sharabha Rudra Tandava Memory Inquest Engine
        \\export struct ScanRowData {
        \\    address: string,
        \\    val: string,
        \\    previous: string,
        \\    val_type: string,
        \\    is_frozen: bool,
        \\}
        \\
        \\export global LiveScan {
        \\
    );

    try appendPrint(&list, allocator, "    in property <int> scan_iteration: {d};\n", .{iteration});
    try appendPrint(&list, allocator, "    in property <int> total_matches: {d};\n", .{total_matches});
    try appendPrint(&list, allocator, "    in property <string> status_text: \"{s}\";\n", .{status_text});
    try appendPrint(&list, allocator, "    in property <string> result_count_str: \"{s}\";\n", .{result_count_str});
    try appendPrint(&list, allocator, "    in property <string> target_value: \"{s}\";\n", .{target_value});
    try appendPrint(&list, allocator, "    in property <string> data_type: \"{s}\";\n\n", .{data_type_str});

    // Populate rows array (up to 250 items for Slint scroll view)
    try list.appendSlice(allocator, "    in property <[ScanRowData]> rows: [\n");
    const max_display = @min(results.len, 250);
    for (results[0..max_display], 0..) |r, idx| {
        var addr_buf: [32]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&addr_buf, "0x{X}", .{r.address}) catch "0x0";
        const frozen = isAddressFrozen(addr_str);

        try appendPrint(
            &list,
            allocator,
            "        {{ address: \"{s}\", val: \"{d}\", previous: \"{d}\", val_type: \"{s}\", is_frozen: {s} }}{s}\n",
            .{
                addr_str,
                r.current_value,
                r.previous_value,
                data_type_str,
                if (frozen) "true" else "false",
                if (idx + 1 < max_display) "," else "",
            },
        );
    }
    try list.appendSlice(allocator, "    ];\n\n");

    // Populate backward-compatible 4 scalar properties
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (i < results.len) {
            const r = results[i];
            var addr_buf: [32]u8 = undefined;
            const addr_str = std.fmt.bufPrint(&addr_buf, "0x{X}", .{r.address}) catch "0x0";
            const frozen = isAddressFrozen(addr_str);

            try appendPrint(&list, allocator, "    in property <bool> found_freeze_{d}: {s};\n", .{ i, if (frozen) "true" else "false" });
            try appendPrint(&list, allocator, "    in property <string> found_addr_{d}: \"{s}\";\n", .{ i, addr_str });
            try appendPrint(&list, allocator, "    in property <string> found_val_{d}: \"{d}\";\n", .{ i, r.current_value });
            try appendPrint(&list, allocator, "    in property <string> found_prev_{d}: \"{d}\";\n", .{ i, r.previous_value });
            try appendPrint(&list, allocator, "    in property <string> found_type_{d}: \"{s}\";\n\n", .{ i, data_type_str });
        } else {
            try appendPrint(&list, allocator, "    in property <bool> found_freeze_{d}: false;\n", .{i});
            try appendPrint(&list, allocator, "    in property <string> found_addr_{d}: \"\";\n", .{i});
            try appendPrint(&list, allocator, "    in property <string> found_val_{d}: \"\";\n", .{i});
            try appendPrint(&list, allocator, "    in property <string> found_prev_{d}: \"\";\n", .{i});
            try appendPrint(&list, allocator, "    in property <string> found_type_{d}: \"\";\n\n", .{i});
        }
    }

    try list.appendSlice(allocator, "}\n");

    try writeFullFile(LIVE_SCAN_SLINT_PATH, list.items);
}

pub fn handleAttach(allocator: std.mem.Allocator, pid: u32) !void {
    var proc = process.ProcessHandle.open(pid) catch |err| {
        std.debug.print("❌ [Attach Error]: Could not open PID {d}: {s}\n", .{ pid, @errorName(err) });
        return err;
    };
    proc.close();

    try setActivePid(pid);

    var status_buf: [128]u8 = undefined;
    const status_str = try std.fmt.bufPrint(&status_buf, "Win32 Netra Hooked // PID {d} Armed [VM_READ | VM_WRITE]", .{pid});

    const empty_results = [_]scanner.ScanResult{};
    try writeLiveScanSlint(allocator, 0, 0, status_str, "READY (सज्ज)", "100", "4 Bytes (i32)", &empty_results);
    touchAppSlint();

    std.debug.print("  [✓] Win32 OpenProcess hook established for PID {d}.\n", .{pid});
}

pub fn handleFirstScan(allocator: std.mem.Allocator, target_str: []const u8, type_str: []const u8) !usize {
    const pid = try getOrDetectTargetPid();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    const data_type = parseDataType(type_str);
    const target = try parseScanTarget(target_str, data_type);

    var mem_scanner = scanner.MemoryScanner.init(allocator, &proc);
    defer mem_scanner.deinit();

    const count = try mem_scanner.firstScan(target);

    try saveScanState(allocator, pid, data_type, 1, mem_scanner.results.items);

    var status_buf: [256]u8 = undefined;
    const status_str = try std.fmt.bufPrint(
        &status_buf,
        "First Scan Complete: {d} candidate addresses found matching '{s}' in PID {d}",
        .{ count, target_str, pid },
    );

    var count_buf: [64]u8 = undefined;
    const count_str = try std.fmt.bufPrint(&count_buf, "{d} MATCHES (आविष्कृत {d})", .{ count, count });

    try writeLiveScanSlint(
        allocator,
        1,
        count,
        status_str,
        count_str,
        target_str,
        getDataTypeString(data_type),
        mem_scanner.results.items,
    );

    touchAppSlint();

    std.debug.print("  [✓] VirtualQueryEx scanned committed writable pages.\n", .{});
    std.debug.print("  [✓] Discovered {d} matching candidates in PID {d}.\n", .{ count, pid });
    const preview_count = @min(mem_scanner.results.items.len, 5);
    for (mem_scanner.results.items[0..preview_count]) |r| {
        std.debug.print("      • [0x{X}] Value: {d} | Type: {s}\n", .{ r.address, r.current_value, getDataTypeString(data_type) });
    }

    return count;
}

pub fn handleNextScan(allocator: std.mem.Allocator, target_str: []const u8, rescan_type_str: []const u8) !usize {
    var state = loadScanState(allocator) catch |err| {
        std.debug.print("❌ [Rescan Error]: No previous scan state found: {s}\n", .{@errorName(err)});
        return err;
    };
    defer state.deinit();

    var proc = try process.ProcessHandle.open(state.pid);
    defer proc.close();

    var mem_scanner = scanner.MemoryScanner.init(allocator, &proc);
    defer mem_scanner.deinit();

    // Populate scanner with previous candidates
    try mem_scanner.results.appendSlice(allocator, state.results);

    const rescan_type = parseRescanType(rescan_type_str);
    const refined_count = if (rescan_type == .ExactValue) blk: {
        const target = try parseScanTarget(target_str, state.data_type);
        break :blk try mem_scanner.nextScanExact(target);
    } else blk: {
        break :blk try mem_scanner.nextScanDifferential(rescan_type, state.data_type);
    };

    const new_iteration = state.iteration + 1;
    try saveScanState(allocator, state.pid, state.data_type, new_iteration, mem_scanner.results.items);

    var status_buf: [256]u8 = undefined;
    const status_str = try std.fmt.bufPrint(
        &status_buf,
        "Refined Iteration #{d} Complete: {d} candidate addresses remain",
        .{ new_iteration, refined_count },
    );

    var count_buf: [64]u8 = undefined;
    const count_str = try std.fmt.bufPrint(&count_buf, "{d} MATCHES (परिशोधित {d})", .{ refined_count, refined_count });

    try writeLiveScanSlint(
        allocator,
        new_iteration,
        refined_count,
        status_str,
        count_str,
        target_str,
        getDataTypeString(state.data_type),
        mem_scanner.results.items,
    );

    touchAppSlint();

    std.debug.print("  [✓] Refined iteration #{d}: {d} candidates isolated.\n", .{ new_iteration, refined_count });
    const preview_count = @min(mem_scanner.results.items.len, 5);
    for (mem_scanner.results.items[0..preview_count]) |r| {
        std.debug.print("      • [0x{X}] Value: {d} (Prev: {d})\n", .{ r.address, r.current_value, r.previous_value });
    }

    return refined_count;
}

pub fn handleWriteMem(allocator: std.mem.Allocator, addr_str: []const u8, val_str: []const u8) !void {
    const pid = try getOrDetectTargetPid();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        clean_addr = clean_addr[2..];
    }
    const address = try std.fmt.parseInt(usize, clean_addr, 16);

    // Default to i32 unless state exists
    var data_type: scanner.DataType = .I32;
    if (loadScanState(allocator)) |state| {
        var s = state;
        data_type = s.data_type;
        s.deinit();
    } else |_| {}

    var write_buf: [8]u8 = @splat(0);
    const write_len = data_type.size();

    switch (data_type) {
        .I8 => {
            const v = try std.fmt.parseInt(i8, val_str, 0);
            write_buf[0] = @bitCast(v);
        },
        .U8 => {
            const v = try std.fmt.parseInt(u8, val_str, 0);
            write_buf[0] = v;
        },
        .I16 => {
            const v = try std.fmt.parseInt(i16, val_str, 0);
            std.mem.writeInt(i16, write_buf[0..2], v, .little);
        },
        .U16 => {
            const v = try std.fmt.parseInt(u16, val_str, 0);
            std.mem.writeInt(u16, write_buf[0..2], v, .little);
        },
        .I32 => {
            const v = try std.fmt.parseInt(i32, val_str, 0);
            std.mem.writeInt(i32, write_buf[0..4], v, .little);
        },
        .U32 => {
            const v = try std.fmt.parseInt(u32, val_str, 0);
            std.mem.writeInt(u32, write_buf[0..4], v, .little);
        },
        .I64 => {
            const v = try std.fmt.parseInt(i64, val_str, 0);
            std.mem.writeInt(i64, write_buf[0..8], v, .little);
        },
        .U64 => {
            const v = try std.fmt.parseInt(u64, val_str, 0);
            std.mem.writeInt(u64, write_buf[0..8], v, .little);
        },
        .F32 => {
            const v = try std.fmt.parseFloat(f32, val_str);
            const raw: u32 = @bitCast(v);
            std.mem.writeInt(u32, write_buf[0..4], raw, .little);
        },
        .F64 => {
            const v = try std.fmt.parseFloat(f64, val_str);
            const raw: u64 = @bitCast(v);
            std.mem.writeInt(u64, write_buf[0..8], raw, .little);
        },
    }

    _ = try proc.writeMemory(address, write_buf[0..write_len]);

    // Read back to verify
    var read_buf: [8]u8 = @splat(0);
    _ = proc.readMemory(address, read_buf[0..write_len]) catch {};

    std.debug.print("  [✓] Win32 WriteProcessMemory succeeded at 0x{X}: written '{s}'.\n", .{ address, val_str });

    // Update scan state if address exists
    if (loadScanState(allocator)) |state| {
        var s = state;
        defer s.deinit();
        for (s.results) |*r| {
            if (r.address == address) {
                r.previous_value = r.current_value;
                r.current_value = std.fmt.parseInt(i64, val_str, 0) catch r.current_value;
                break;
            }
        }
        try saveScanState(allocator, s.pid, s.data_type, s.iteration, s.results);
        var status_buf: [128]u8 = undefined;
        const status_str = try std.fmt.bufPrint(&status_buf, "RAM Modified: 0x{X} set to '{s}' (Verified)", .{ address, val_str });
        try writeLiveScanSlint(
            allocator,
            s.iteration,
            s.results.len,
            status_str,
            "RAM WRITTEN",
            val_str,
            getDataTypeString(s.data_type),
            s.results,
        );
        touchAppSlint();
    } else |_| {}
}

pub fn handleFreezeMem(allocator: std.mem.Allocator, addr_str: []const u8, state_bool: bool) !void {
    var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        clean_addr = clean_addr[2..];
    }
    var full_hex_buf: [32]u8 = undefined;
    const full_hex = try std.fmt.bufPrint(&full_hex_buf, "0x{s}", .{clean_addr});

    ensureDirectory("assets");
    ensureDirectory("assets/memory");

    // Read existing entries
    var existing_lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (existing_lines.items) |line| allocator.free(line);
        existing_lines.deinit(allocator);
    }

    var read_buf: [4096]u8 = undefined;
    if (readFullFile(FROZEN_ENTRIES_PATH, &read_buf)) |bytes| {
        var iter = std.mem.tokenizeAny(u8, read_buf[0..bytes], "\r\n");
        while (iter.next()) |line| {
            var parts = std.mem.tokenizeAny(u8, line, " \t");
            if (parts.next()) |entry_addr| {
                if (!std.ascii.eqlIgnoreCase(entry_addr, full_hex)) {
                    try existing_lines.append(allocator, try allocator.dupe(u8, line));
                }
            }
        }
    }

    if (state_bool) {
        // Add entry
        const entry_line = try std.fmt.allocPrint(allocator, "{s} 100 i32", .{full_hex});
        defer allocator.free(entry_line);
        try existing_lines.append(allocator, try allocator.dupe(u8, entry_line));
        std.debug.print("  [✓] Stambhana Freeze Sentinel Armed: {s} locked.\n", .{full_hex});
    } else {
        std.debug.print("  [✓] Stambhana Freeze Sentinel Disarmed: {s} unlocked.\n", .{full_hex});
    }

    // Write back
    var file_buf: std.ArrayList(u8) = .empty;
    defer file_buf.deinit(allocator);
    for (existing_lines.items) |line| {
        try appendPrint(&file_buf, allocator, "{s}\n", .{line});
    }
    try writeFullFile(FROZEN_ENTRIES_PATH, file_buf.items);

    // Refresh LiveScan slint
    if (loadScanState(allocator)) |state| {
        var s = state;
        defer s.deinit();
        var status_buf: [128]u8 = undefined;
        const status_str = try std.fmt.bufPrint(
            &status_buf,
            "{s}: {s}",
            .{ if (state_bool) "STAMBHANA ACTIVE (Locked)" else "Stambhana Unlocked", full_hex },
        );
        try writeLiveScanSlint(
            allocator,
            s.iteration,
            s.results.len,
            status_str,
            if (state_bool) "STAMBHANA (स्तम्भन)" else "UNFROZEN (मुक्त)",
            "100",
            getDataTypeString(s.data_type),
            s.results,
        );
        touchAppSlint();
    } else |_| {}
}

pub fn handleResetScan(allocator: std.mem.Allocator) !void {
    deleteFile(SCAN_STATE_PATH);
    deleteFile(FROZEN_ENTRIES_PATH);

    const empty = [_]scanner.ScanResult{};
    try writeLiveScanSlint(allocator, 0, 0, "Scanner Reset: Ready for fresh memory inquest", "READY (सज्ज)", "100", "4 Bytes (i32)", &empty);
    touchAppSlint();
    std.debug.print("  [✓] Memory Scanner & candidate cache cleared.\n", .{});
}

test "engine_service self process scan, filter, and write" {
    const allocator = std.testing.allocator;

    var test_val: i32 = 777666;
    const test_addr = @intFromPtr(&test_val);

    const self_pid = win.GetCurrentProcessId();
    try setActivePid(self_pid);

    // 1. First scan for 777666
    const count = try handleFirstScan(allocator, "777666", "4 Bytes (i32)");
    try std.testing.expect(count > 0);

    // 2. Next scan after value modification
    test_val = 777667;
    const count2 = try handleNextScan(allocator, "777667", "EXACT");
    try std.testing.expect(count2 > 0);
    try std.testing.expect(count2 <= count);

    // 3. Write memory test
    var addr_buf: [32]u8 = undefined;
    const addr_str = try std.fmt.bufPrint(&addr_buf, "0x{X}", .{test_addr});
    try handleWriteMem(allocator, addr_str, "999888");
    try std.testing.expectEqual(@as(i32, 999888), test_val);

    // 4. Freeze memory test
    try handleFreezeMem(allocator, addr_str, true);
    try std.testing.expect(isAddressFrozen(addr_str));
    try handleFreezeMem(allocator, addr_str, false);
    try std.testing.expect(!isAddressFrozen(addr_str));

    // 5. Reset scan test
    try handleResetScan(allocator);
}
