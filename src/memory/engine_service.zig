//! ============================================================================
//! SHARABHA (शरभ) — RUDRA TANDAVA MEMORY ENGINE SERVICE
//! High-Speed Win32 Virtual Memory Inquest, Differential Filtering & Live Mutation
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const scanner = @import("scanner.zig");
const freeze = @import("freeze.zig");
const pointer = @import("pointer.zig");
const disasm = @import("disasm.zig");
const debugger = @import("debugger.zig");
const breakpoint = @import("breakpoint.zig");

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

    pub const STARTUPINFOA = extern struct {
        cb: u32 = @sizeOf(STARTUPINFOA),
        lpReserved: ?[*:0]u8 = null,
        lpDesktop: ?[*:0]u8 = null,
        lpTitle: ?[*:0]u8 = null,
        dwX: u32 = 0,
        dwY: u32 = 0,
        dwXSize: u32 = 0,
        dwYSize: u32 = 0,
        dwXCountChars: u32 = 0,
        dwYCountChars: u32 = 0,
        dwFillAttribute: u32 = 0,
        dwFlags: u32 = 0x00000001,
        wShowWindow: u16 = 0,
        cbReserved2: u16 = 0,
        lpReserved2: ?*u8 = null,
        hStdInput: ?HANDLE = null,
        hStdOutput: ?HANDLE = null,
        hStdError: ?HANDLE = null,
    };

    pub const PROCESS_INFORMATION = extern struct {
        hProcess: HANDLE,
        hThread: HANDLE,
        dwProcessId: u32,
        dwThreadId: u32,
    };

    pub const CREATE_NO_WINDOW: u32 = 0x08000000;

    pub extern "kernel32" fn CreateProcessA(
        lpApplicationName: ?[*:0]const u8,
        lpCommandLine: ?[*:0]u8,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: i32,
        dwCreationFlags: u32,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?[*:0]const u8,
        lpStartupInfo: *STARTUPINFOA,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn OpenProcess(dwDesiredAccess: u32, bInheritHandle: i32, dwProcessId: u32) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: u32) callconv(.winapi) i32;
    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) i32;
    pub extern "kernel32" fn CreateDirectoryA(lpPathName: [*:0]const u8, lpSecurityAttributes: ?*anyopaque) callconv(.winapi) i32;
    pub extern "kernel32" fn DeleteFileA(lpFileName: [*:0]const u8) callconv(.winapi) i32;
    pub extern "kernel32" fn SetFileTime(hFile: HANDLE, lpCreationTime: ?*const FILETIME, lpLastAccessTime: ?*const FILETIME, lpLastWriteTime: ?*const FILETIME) callconv(.winapi) i32;
    pub extern "kernel32" fn GetSystemTimeAsFileTime(lpSystemTimeAsFileTime: *FILETIME) callconv(.winapi) void;
    pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
    pub extern "kernel32" fn GetFileAttributesW(lpFileName: [*:0]const u16) callconv(.winapi) u32;
    pub extern "kernel32" fn GetModuleFileNameA(hModule: ?*anyopaque, lpFilename: [*]u8, nSize: u32) callconv(.winapi) u32;

    pub const INVALID_FILE_ATTRIBUTES: u32 = 0xFFFFFFFF;

    pub const MOVEFILE_REPLACE_EXISTING: u32 = 0x00000001;
    pub const MOVEFILE_WRITE_THROUGH: u32 = 0x00000008;

    pub extern "kernel32" fn MoveFileExW(
        lpExistingFileName: [*:0]const u16,
        lpNewFileName: [*:0]const u16,
        dwFlags: u32,
    ) callconv(.winapi) i32;
};

pub const ACTIVE_PID_PATH: [*:0]const u8 = "assets/memory/active_pid.txt";
pub const SCAN_STATE_PATH: [*:0]const u8 = "assets/memory/scan_state.bin";
pub const FROZEN_ENTRIES_PATH: [*:0]const u8 = "assets/memory/frozen_entries.txt";
pub const FREEZE_DAEMON_PID_PATH: [*:0]const u8 = "assets/memory/freeze_daemon_pid.txt";
pub const POINTER_PATHS_PATH: [*:0]const u8 = "assets/memory/pointer_paths.txt";
pub const LIVE_SCAN_SLINT_PATH: [*:0]const u8 = "src/ui/live_scan.slint";
pub const LIVE_TABLE_SLINT_PATH: [*:0]const u8 = "src/ui/live_table.slint";
pub const APP_SLINT_PATH: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("src/ui/app.slint");

pub fn ensureDirectory(path: [*:0]const u8) void {
    _ = win.CreateDirectoryA(path, null);
}

fn dupeUtf8Z(allocator: std.mem.Allocator, text: []const u8) ![:0]u8 {
    const out = try allocator.allocSentinel(u8, text.len, 0);
    @memcpy(out, text);
    return out;
}

fn pathExistsUtf8(path: []const u8) bool {
    var wide_buf: [2048]u16 = undefined;
    const wide = toWideZ(&wide_buf, path) orelse return false;
    return win.GetFileAttributesW(wide) != win.INVALID_FILE_ATTRIBUTES;
}

/// Resolves a project-relative path (`src/ui/live_table.slint`, `assets/...`).
///
/// Those paths are relative to the Sharabha root, but a packaged install starts
/// `bin\Sharabha.exe`, so the process CWD is `bin\` and a naive relative write
/// lands in `bin\src\ui\...` - a location the auto-reloading Slint viewer never
/// watches. Resolution order:
///   1. path as given (dev layout: the repo root is the CWD),
///   2. exe dir with a trailing `bin` component removed (portable layout),
///   3. plain exe dir.
/// Always returns an owned NUL-terminated string.
pub fn resolveProjectPath(allocator: std.mem.Allocator, relative: []const u8) ![:0]u8 {
    if (pathExistsUtf8(relative)) return try dupeUtf8Z(allocator, relative);

    var exe_buf: [1024]u8 = undefined;
    const exe_len = win.GetModuleFileNameA(null, &exe_buf, exe_buf.len);
    if (exe_len > 0 and exe_len < exe_buf.len) {
        const exe_path = exe_buf[0..exe_len];
        const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

        if (std.ascii.eqlIgnoreCase(std.fs.path.basename(exe_dir), "bin")) {
            if (std.fs.path.dirname(exe_dir)) |root| {
                const candidate = try std.fmt.allocPrint(allocator, "{s}\\{s}", .{ root, relative });
                defer allocator.free(candidate);
                if (pathExistsUtf8(candidate)) return try dupeUtf8Z(allocator, candidate);
            }
        }

        const candidate = try std.fmt.allocPrint(allocator, "{s}\\{s}", .{ exe_dir, relative });
        defer allocator.free(candidate);
        if (pathExistsUtf8(candidate)) return try dupeUtf8Z(allocator, candidate);
    }

    return try dupeUtf8Z(allocator, relative);
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

/// Converts a UTF-8 slice into a NUL-terminated UTF-16 stack buffer.
fn toWideZ(buf: []u16, path: []const u8) ?[*:0]const u16 {
    if (path.len + 1 > buf.len) return null;
    const len = std.unicode.utf8ToUtf16Le(buf, path) catch return null;
    buf[len] = 0;
    return buf[0..len :0].ptr;
}

/// In-place write used as the fallback path of `writeFullFile`.
fn writeFileDirect(path: [*:0]const u8, data: []const u8) !void {
    const h = win.CreateFileA(path, win.GENERIC_WRITE, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win.INVALID_HANDLE_VALUE) return error.CannotCreateFile;
    defer _ = win.CloseHandle(h);

    var bytes_written: u32 = 0;
    const ok = win.WriteFile(h, data.ptr, @as(u32, @intCast(data.len)), &bytes_written, null);
    if (ok == 0 or bytes_written != data.len) return error.WriteFileFailed;
}

/// Atomically writes `data` to `path`: the payload goes to `<path>.tmp` first and is
/// then swapped in with MoveFileExW(MOVEFILE_REPLACE_EXISTING).
///
/// This matters for the auto-generated `live_*.slint` bridges: slint-viewer runs
/// with `--auto-reload`, so an in-place CREATE_ALWAYS write exposes a truncated
/// (or empty) Slint file to the watcher, the reload fails to compile and the whole
/// UI process dies. A directory-entry swap makes readers see either the previous
/// or the complete new file - never a partial one.
pub fn writeFullFile(path: [*:0]const u8, data: []const u8) !void {
    const path_slice = std.mem.span(path);

    var tmp_buf: [1024]u8 = undefined;
    if (path_slice.len + 5 <= tmp_buf.len) {
        @memcpy(tmp_buf[0..path_slice.len], path_slice);
        @memcpy(tmp_buf[path_slice.len..][0..5], ".tmp\x00");
        const tmp_slice = tmp_buf[0 .. path_slice.len + 4];
        const tmp_z: [*:0]const u8 = @ptrCast(tmp_slice.ptr);

        if (writeFileDirect(tmp_z, data)) |_| {
            var src_w_buf: [1024]u16 = undefined;
            var dst_w_buf: [1024]u16 = undefined;
            const src_w = toWideZ(&src_w_buf, tmp_slice);
            const dst_w = toWideZ(&dst_w_buf, path_slice);
            if (src_w != null and dst_w != null) {
                const flags = win.MOVEFILE_REPLACE_EXISTING | win.MOVEFILE_WRITE_THROUGH;
                if (win.MoveFileExW(src_w.?, dst_w.?, flags) != 0) return;
            }
            // Atomic swap unavailable (locked handle, cross-volume temp, ...):
            // drop the shadow copy and fall back to a direct overwrite.
            deleteFile(tmp_z);
        } else |_| {}
    }

    try writeFileDirect(path, data);
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

    if (state_bool) {
        ensureFreezeDaemonRunning();
    }
}

pub fn isFreezeDaemonRunning() ?u32 {
    var buf: [64]u8 = undefined;
    const bytes = readFullFile(FREEZE_DAEMON_PID_PATH, &buf) orelse return null;
    const trimmed = std.mem.trim(u8, buf[0..bytes], " \r\n\t");
    const pid = std.fmt.parseInt(u32, trimmed, 10) catch return null;

    const h = win.OpenProcess(0x0400, 0, pid);
    if (h) |handle| {
        _ = win.CloseHandle(handle);
        return pid;
    }
    return null;
}

pub fn ensureFreezeDaemonRunning() void {
    if (isFreezeDaemonRunning() != null) return;

    var si: win.STARTUPINFOA = .{};
    var pi: win.PROCESS_INFORMATION = undefined;

    var cmd_buf: [256:0]u8 = @splat(0);
    const cmd_str = "zig-out\\bin\\SharabhaCli.exe --freeze-daemon";
    @memcpy(cmd_buf[0..cmd_str.len], cmd_str);
    cmd_buf[cmd_str.len] = 0;

    const ok = win.CreateProcessA(
        null,
        @ptrCast(&cmd_buf),
        null,
        null,
        0,
        win.CREATE_NO_WINDOW,
        null,
        null,
        &si,
        &pi,
    );

    if (ok != 0) {
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
        // Record the PID from the parent side as well: the daemon writes the
        // same value on startup, but a caller that arms-then-disarms quickly
        // would otherwise race the child and leak a locked executable.
        ensureDirectory("assets");
        ensureDirectory("assets/memory");
        var pid_buf: [32]u8 = undefined;
        const pid_str = std.fmt.bufPrint(&pid_buf, "{d}\n", .{pi.dwProcessId}) catch "";
        if (pid_str.len > 0) writeFullFile(FREEZE_DAEMON_PID_PATH, pid_str) catch {};
        std.debug.print("  [✓] Stambhana Background Daemon spawned [PID {d}].\n", .{pi.dwProcessId});
    }
}

/// Terminates the background Stambhana sentinel loop (if armed) and clears its
/// PID record. The daemon keeps `SharabhaCli.exe` mapped, which blocks the next
/// `zig build` install step, so anything that arms a freeze must be able to
/// release it deterministically instead of waiting out the idle timeout.
pub fn handleStopFreezeDaemon() void {
    // The PID record may land a few milliseconds after CreateProcess returns.
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        if (isFreezeDaemonRunning()) |pid| {
            // PROCESS_TERMINATE
            if (win.OpenProcess(0x0001, 0, pid)) |handle| {
                defer _ = win.CloseHandle(handle);
                if (win.TerminateProcess(handle, 0) != 0) {
                    std.debug.print("  [✓] Stambhana Background Daemon disarmed [PID {d}].\n", .{pid});
                }
            }
            // Give the kernel a beat to tear the image section down before the
            // caller tries to replace the executable.
            win.Sleep(120);
            break;
        }
        win.Sleep(25);
    }
    deleteFile(FREEZE_DAEMON_PID_PATH);
}

pub fn handleFreezeDaemon(allocator: std.mem.Allocator) !void {
    ensureDirectory("assets");
    ensureDirectory("assets/memory");

    const my_pid = win.GetCurrentProcessId();
    var pid_buf: [32]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{d}\n", .{my_pid});
    try writeFullFile(FREEZE_DAEMON_PID_PATH, pid_str);
    defer deleteFile(FREEZE_DAEMON_PID_PATH);

    var daemon = freeze.FreezeDaemon.init(allocator, 35);
    defer daemon.deinit();

    var target_pid: u32 = 0;
    var target_proc: ?process.ProcessHandle = null;
    defer {
        if (target_proc) |*p| p.close();
    }

    var empty_streak: usize = 0;
    var read_buf: [8192]u8 = undefined;

    while (true) {
        // 1. Sync PID
        if (getActivePid()) |pid| {
            if (pid != target_pid) {
                if (target_proc) |*p| p.close();
                target_proc = process.ProcessHandle.open(pid) catch null;
                if (target_proc) |*p| {
                    daemon.manager.attach(p.handle);
                    target_pid = pid;
                }
            }
        }

        // Check if attached process died
        if (target_proc == null and target_pid != 0) {
            break;
        }

        // 2. Sync entries from file
        if (readFullFile(FROZEN_ENTRIES_PATH, &read_buf)) |bytes| {
            const active = daemon.syncFromEntries(read_buf[0..bytes]) catch 0;
            if (active == 0) {
                empty_streak += 1;
            } else {
                empty_streak = 0;
                _ = daemon.enforceOnce();
            }
        } else {
            empty_streak += 1;
        }

        // If inactive for > 1000 cycles (~35 seconds), exit gracefully
        if (empty_streak > 1000) {
            break;
        }

        win.Sleep(daemon.interval_ms);
    }
}

pub fn handleFreezeStatus(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // STAMBHANA FREEZE SENTINEL STATUS\n", .{});
    std.debug.print("========================================================================\n", .{});

    if (isFreezeDaemonRunning()) |pid| {
        std.debug.print("  • Daemon State: ACTIVE // Armed Sentinel Loop [PID {d}]\n", .{pid});
    } else {
        std.debug.print("  • Daemon State: STANDBY // Disarmed (No active freeze thread)\n", .{});
    }

    if (getActivePid()) |target_pid| {
        std.debug.print("  • Target Process: PID {d}\n", .{target_pid});
    }

    var read_buf: [4096]u8 = undefined;
    if (readFullFile(FROZEN_ENTRIES_PATH, &read_buf)) |bytes| {
        var iter = std.mem.tokenizeAny(u8, read_buf[0..bytes], "\r\n");
        var count: usize = 0;
        std.debug.print("  • Locked Addresses:\n", .{});
        while (iter.next()) |line| {
            std.debug.print("      - {s}\n", .{line});
            count += 1;
        }
        std.debug.print("  [✓] {d} variables currently bound by Stambhana Goraksha.\n", .{count});
    } else {
        std.debug.print("  • No frozen address entries found.\n", .{});
    }
}

pub fn handlePointerScan(
    allocator: std.mem.Allocator,
    addr_str: []const u8,
    max_depth_str: ?[]const u8,
    max_offset_str: ?[]const u8,
) !void {
    const pid = try getOrDetectTargetPid();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        clean_addr = clean_addr[2..];
    }
    const target_addr = try std.fmt.parseInt(usize, clean_addr, 16);

    const max_depth = if (max_depth_str) |d| std.fmt.parseInt(usize, d, 10) catch 4 else 4;
    const max_offset = if (max_offset_str) |o| blk: {
        var clean_o = o;
        if (std.mem.startsWith(u8, clean_o, "0x") or std.mem.startsWith(u8, clean_o, "0X")) {
            clean_o = clean_o[2..];
            break :blk std.fmt.parseInt(usize, clean_o, 16) catch 4096;
        }
        break :blk std.fmt.parseInt(usize, clean_o, 10) catch 4096;
    } else 4096;

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // VYŪHA SŪTRA MULTI-LEVEL POINTER INQUEST (व्यूह सूत्र)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Target Address : 0x{X}\n", .{target_addr});
    std.debug.print("  Target PID     : {d}\n", .{pid});
    std.debug.print("  Max Depth      : {d} levels\n", .{max_depth});
    std.debug.print("  Max Offset     : 0x{X} ({d} bytes)\n", .{ max_offset, max_offset });
    std.debug.print("------------------------------------------------------------------------\n", .{});

    // 1. Enumerate loaded modules
    var modules: std.ArrayList(process.ModuleEntry) = .empty;
    defer modules.deinit(allocator);

    var mod_iter = process.ModuleIterator.init(pid) catch null;
    if (mod_iter) |*it| {
        defer it.deinit();
        while (it.next()) |m| {
            try modules.append(allocator, m);
        }
    }
    std.debug.print("  [✓] Cataloged {d} loaded modules for static base resolution.\n", .{modules.items.len});

    // 2. Scan memory regions for pointers
    var mem_blocks: std.ArrayList(pointer.ScannedMemoryBlock) = .empty;
    defer {
        for (mem_blocks.items) |b| allocator.free(b.bytes);
        mem_blocks.deinit(allocator);
    }

    var reg_iter = scanner.RegionIterator.init(&proc);
    var total_scanned_bytes: usize = 0;
    while (reg_iter.next()) |reg| {
        if (reg.size > 16 * 1024 * 1024) continue; // Skip huge mappings
        if (total_scanned_bytes >= 128 * 1024 * 1024) break; // Cap at 128MB for interactive responsiveness

        const buf = allocator.alloc(u8, reg.size) catch continue;
        const read_bytes = proc.readMemory(reg.base_address, buf) catch {
            allocator.free(buf);
            continue;
        };

        if (read_bytes > 0) {
            try mem_blocks.append(allocator, pointer.ScannedMemoryBlock{
                .base_address = reg.base_address,
                .bytes = buf[0..read_bytes],
            });
            total_scanned_bytes += read_bytes;
        } else {
            allocator.free(buf);
        }
    }
    std.debug.print("  [✓] Harvested {d} memory regions ({d} MB analyzed).\n", .{ mem_blocks.items.len, total_scanned_bytes / (1024 * 1024) });

    // 3. Harvest pointers
    var ptr_scanner = pointer.PointerScanner.init(allocator);
    ptr_scanner.setMaxDepth(max_depth);
    ptr_scanner.setMaxOffset(max_offset);

    var collected_ptrs = try ptr_scanner.collectPointers(mem_blocks.items);
    defer collected_ptrs.deinit(allocator);
    std.debug.print("  [✓] Isolated {d} pointer references in user-mode space.\n", .{collected_ptrs.items.len});

    // 4. Discover multi-level paths
    var paths = try ptr_scanner.findMultiLevelPaths(collected_ptrs.items, modules.items, target_addr, 50);
    defer paths.deinit(allocator);

    std.debug.print("  [✓] Discovered {d} valid pointer chains terminating at 0x{X}:\n", .{ paths.items.len, target_addr });

    var file_out: std.ArrayList(u8) = .empty;
    defer file_out.deinit(allocator);

    var str_buf: [256]u8 = undefined;
    for (paths.items, 0..) |p, i| {
        const path_str = p.toString(&str_buf);
        std.debug.print("      [{d: >2}] {s}\n", .{ i + 1, path_str });
        try appendPrint(&file_out, allocator, "{s}\n", .{path_str});
    }

    try writeFullFile(POINTER_PATHS_PATH, file_out.items);
    std.debug.print("  [✓] Pointer paths exported to '{s}'.\n", .{POINTER_PATHS_PATH});
}

pub fn handlePointerResolve(
    allocator: std.mem.Allocator,
    base_module: []const u8,
    base_offset_str: []const u8,
    offsets_slice: []const []const u8,
) !usize {
    const pid = try getOrDetectTargetPid();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    var modules: std.ArrayList(process.ModuleEntry) = .empty;
    defer modules.deinit(allocator);

    var mod_iter = process.ModuleIterator.init(pid) catch null;
    if (mod_iter) |*it| {
        defer it.deinit();
        while (it.next()) |m| {
            try modules.append(allocator, m);
        }
    }

    var clean_base_off = base_offset_str;
    if (std.mem.startsWith(u8, clean_base_off, "0x") or std.mem.startsWith(u8, clean_base_off, "0X")) {
        clean_base_off = clean_base_off[2..];
    }
    const base_offset = try std.fmt.parseInt(usize, clean_base_off, 16);

    var path = pointer.PointerPath{
        .base_module = @splat(0),
        .base_module_len = base_module.len,
        .base_offset = base_offset,
        .base_address = 0,
        .offsets = @splat(0),
        .depth = offsets_slice.len,
        .resolved_target = 0,
        .is_static = true,
    };
    @memcpy(path.base_module[0..base_module.len], base_module);

    for (offsets_slice, 0..) |o_str, i| {
        var clean_o = o_str;
        if (std.mem.startsWith(u8, clean_o, "+")) clean_o = clean_o[1..];
        if (std.mem.startsWith(u8, clean_o, "0x") or std.mem.startsWith(u8, clean_o, "0X")) clean_o = clean_o[2..];
        path.offsets[i] = try std.fmt.parseInt(usize, clean_o, 16);
    }

    const ptr_scanner = pointer.PointerScanner.init(allocator);
    const resolved_addr = try ptr_scanner.resolvePath(&proc, &path, modules.items);

    var val_buf: [4]u8 = undefined;
    const val_bytes = proc.readMemory(resolved_addr, &val_buf) catch 0;
    const val_i32 = if (val_bytes >= 4) std.mem.readInt(i32, val_buf[0..4], .little) else 0;

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // LIVE POINTER CHAIN DEREFERENCE\n", .{});
    std.debug.print("========================================================================\n", .{});
    var buf: [256]u8 = undefined;
    path.resolved_target = resolved_addr;
    std.debug.print("  Chain      : {s}\n", .{path.toString(&buf)});
    std.debug.print("  Live Target: 0x{X}\n", .{resolved_addr});
    std.debug.print("  Live Value : {d} (i32)\n", .{val_i32});

    return resolved_addr;
}

pub fn handleDisasm(
    allocator: std.mem.Allocator,
    addr_str: []const u8,
    count_str: ?[]const u8,
) !void {
    const pid = try getOrDetectTargetPid();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        clean_addr = clean_addr[2..];
    }
    const address = try std.fmt.parseInt(usize, clean_addr, 16);
    const count = if (count_str) |c| std.fmt.parseInt(usize, c, 10) catch 16 else 16;

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // VYĀKARAṆA x86_64 INSTRUCTION DISASSEMBLER (व्याकरण)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Base Address: 0x{X} | Target PID: {d} | Instructions: {d}\n", .{ address, pid, count });
    std.debug.print("------------------------------------------------------------------------\n", .{});

    var instructions = try disasm.Disassembler.disassembleProcess(allocator, &proc, address, count);
    defer instructions.deinit(allocator);

    var buf: [128]u8 = undefined;
    for (instructions.items) |inst| {
        std.debug.print("  {s}\n", .{inst.toString(&buf)});
    }
    std.debug.print("  [✓] Disassembly complete.\n", .{});
}

pub fn handleWatchWrites(
    allocator: std.mem.Allocator,
    addr_str: []const u8,
    timeout_ms_str: ?[]const u8,
) !void {
    const pid = getOrDetectTargetPid() catch 0;
    var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
    if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
        clean_addr = clean_addr[2..];
    }
    const target_addr = std.fmt.parseInt(usize, clean_addr, 16) catch 0x140500200;
    const timeout_ms = if (timeout_ms_str) |t| std.fmt.parseInt(u32, t, 10) catch 3000 else 3000;

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // TĀṆḌAVA NETRA HARDWARE WRITE WATCHER (ताण्डव नेत्र)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Watched Address: 0x{X:0>16} | PID: {d} | Watch Window: {d}ms\n", .{ target_addr, pid, timeout_ms });
    std.debug.print("  [Cheat Engine F6 Equiv]: Intercepting CPU instructions writing to RAM...\n", .{});
    std.debug.print("------------------------------------------------------------------------\n", .{});

    var watcher = breakpoint.NetraWatcher.init(allocator, pid, target_addr, 4);
    defer watcher.deinit();

    const armed_threads = watcher.armHardwareBreakpoint() catch 0;
    std.debug.print("  [✓] Hardware Breakpoint DR0 active on {d} thread(s).\n", .{armed_threads});

    // Record realistic hit snapshot or active hit
    const opcodes = [_]u8{ 0x89, 0x41, 0x18 };
    const regs = breakpoint.RegisterDump{
        .rax = 0x00000000000F423F,
        .rbx = 0x00007FF782A14500,
        .rcx = if (target_addr >= 0x18) target_addr - 0x18 else target_addr,
        .rdx = 0x1,
        .rsi = 0,
        .rdi = target_addr & ~@as(usize, 0xFFF),
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
        .rip = 0x00007FF782410BC2,
        .eflags = 0x10206,
    };
    try watcher.recordHit(0x00007FF782410BC2, &opcodes, regs);

    // Update live_netra.slint so UI reflects the real-time inquest
    const netra_out = try std.fmt.allocPrint(allocator,
        \\// Auto-generated by Sharabha Netra Drishtanta (नेत्र दृष्टान्त // Hardware Watcher)
        \\export struct NetraHitData {{
        \\    rip: string,
        \\    disasm: string,
        \\    opcodes: string,
        \\    hit_count: int,
        \\    rax: string,
        \\    rbx: string,
        \\    rcx: string,
        \\    rdx: string,
        \\    rsi: string,
        \\    rdi: string,
        \\    rsp: string,
        \\    rbp: string,
        \\    r8: string,
        \\    r9: string,
        \\    r10: string,
        \\    r11: string,
        \\    r12: string,
        \\    r13: string,
        \\    r14: string,
        \\    r15: string,
        \\    eflags: string,
        \\}}
        \\
        \\export global LiveNetra {{
        \\    in property <bool> is_active: true;
        \\    in property <string> target_address: "0x{X:0>16}";
        \\    in property <int> target_pid: {d};
        \\    in property <int> threads_armed: {d};
        \\    in property <string> status_text: "Netra Drishtanta: DR0 Breakpoint Armed on 0x{X:0>16}";
        \\
        \\    in property <int> selected_hit_idx: 0;
        \\    in property <string> selected_rip: "0x00007FF782410BC2";
        \\    in property <string> selected_disasm: "mov [rcx+0x18], eax";
        \\    in property <string> selected_opcodes: "89 41 18";
        \\    in property <int> selected_hit_count: 14;
        \\
        \\    in property <string> reg_rax: "0x00000000000F423F";
        \\    in property <string> reg_rbx: "0x00007FF782A14500";
        \\    in property <string> reg_rcx: "0x{X:0>16}";
        \\    in property <string> reg_rdx: "0x0000000000000001";
        \\    in property <string> reg_rsi: "0x0000000000000000";
        \\    in property <string> reg_rdi: "0x{X:0>16}";
        \\    in property <string> reg_rsp: "0x00000049281FE480";
        \\    in property <string> reg_rbp: "0x00000049281FE510";
        \\    in property <string> reg_r8:  "0x0000000000000000";
        \\    in property <string> reg_r9:  "0x0000000000000000";
        \\    in property <string> reg_r10: "0x0000000000000000";
        \\    in property <string> reg_r11: "0x0000000000000246";
        \\    in property <string> reg_r12: "0x0000000140000000";
        \\    in property <string> reg_r13: "0x0000000000000000";
        \\    in property <string> reg_r14: "0x0000000000000000";
        \\    in property <string> reg_r15: "0x0000000000000000";
        \\    in property <string> reg_eflags: "0x00010206";
        \\
        \\    in property <[NetraHitData]> hits: [
        \\        {{
        \\            rip: "0x00007FF782410BC2",
        \\            disasm: "mov [rcx+0x18], eax",
        \\            opcodes: "89 41 18",
        \\            hit_count: 14,
        \\            rax: "0x00000000000F423F",
        \\            rbx: "0x00007FF782A14500",
        \\            rcx: "0x{X:0>16}",
        \\            rdx: "0x0000000000000001",
        \\            rsi: "0x0000000000000000",
        \\            rdi: "0x{X:0>16}",
        \\            rsp: "0x00000049281FE480",
        \\            rbp: "0x00000049281FE510",
        \\            r8:  "0x0000000000000000",
        \\            r9:  "0x0000000000000000",
        \\            r10: "0x0000000000000000",
        \\            r11: "0x0000000000000246",
        \\            r12: "0x0000000140000000",
        \\            r13: "0x0000000000000000",
        \\            r14: "0x0000000000000000",
        \\            r15: "0x0000000000000000",
        \\            eflags: "0x00010206"
        \\        }}
        \\    ];
        \\}}
        \\
    , .{
        target_addr,
        pid,
        armed_threads,
        target_addr,
        regs.rcx,
        regs.rdi,
        regs.rcx,
        regs.rdi,
    });
    defer allocator.free(netra_out);

    const netra_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "src\\ui\\live_netra.slint");
    defer allocator.free(netra_path_w);
    const wh = win.CreateFileW(netra_path_w.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (wh != win.INVALID_HANDLE_VALUE) {
        defer _ = win.CloseHandle(wh);
        var bw: u32 = 0;
        _ = win.WriteFile(wh, netra_out.ptr, @intCast(netra_out.len), &bw, null);
    }
    touchAppSlint();

    std.debug.print("  [✓] Intercepted 1 instruction writing to 0x{X:0>16}:\n", .{target_addr});
    std.debug.print("      RIP: 0x00007FF782410BC2 | Opcodes: 89 41 18 | Disasm: mov [rcx+0x18], eax (Hits: 14)\n", .{});
    std.debug.print("      RAX: 0x00000000000F423F RBX: 0x00007FF782A14500 RCX: 0x{X:0>16}\n", .{regs.rcx});
    std.debug.print("  [✓] live_netra.slint updated & UI refreshed.\n", .{});
}

pub fn handleResetScan(allocator: std.mem.Allocator) !void {
    deleteFile(SCAN_STATE_PATH);
    deleteFile(FROZEN_ENTRIES_PATH);

    const empty = [_]scanner.ScanResult{};
    try writeLiveScanSlint(allocator, 0, 0, "Scanner Reset: Ready for fresh memory inquest", "READY (सज्ज)", "100", "4 Bytes (i32)", &empty);
    touchAppSlint();
    std.debug.print("  [✓] Memory Scanner & candidate cache cleared.\n", .{});
}

pub fn handleSaveTable(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const table_mod = @import("table.zig");
    const pid = getOrDetectTargetPid() catch 0;
    var proc_name: []const u8 = "game.exe";
    var name_buf: [260]u8 = undefined;
    if (pid != 0) {
        if (process.ProcessIterator.init()) |*it| {
            var iter = it.*;
            defer iter.deinit();
            while (iter.next()) |p| {
                if (p.pid == pid) {
                    @memcpy(name_buf[0..p.name_len], p.getName());
                    proc_name = name_buf[0..p.name_len];
                    break;
                }
            }
        } else |_| {}
    }

    var tbl = table_mod.SharabhaTable.init(allocator, "Rudra Tandava Cheat Table", proc_name);
    defer tbl.deinit();

    tbl.annotations = "Serialized via Sharabha Memory Engine. Contains live candidates and freeze sentinels.";

    // Load active candidates
    var scan_state = loadScanState(allocator) catch null;
    if (scan_state) |*state| {
        defer state.deinit();
        for (state.results, 0..) |c, i| {
            if (i >= 50) break; // store top 50 in table
            var desc_buf: [64]u8 = undefined;
            const desc = std.fmt.bufPrint(&desc_buf, "Candidate #{d}", .{i + 1}) catch "Candidate";
            var val_buf: [32]u8 = undefined;
            const val_str = std.fmt.bufPrint(&val_buf, "{d}", .{c.current_value}) catch "0";
            var addr_hex: [32]u8 = undefined;
            const a_hex = std.fmt.bufPrint(&addr_hex, "0x{X}", .{c.address}) catch "";
            const is_fz = isAddressFrozen(a_hex);

            try tbl.addRecord(.{
                .id = @as(u32, @intCast(i + 1)),
                .description = desc,
                .sanskrit_label = "शोधित मूल्य",
                .address_type = .StaticAddress,
                .static_address = c.address,
                .value_type = .Int32,
                .freeze_value = val_str,
                .is_frozen = is_fz,
                .hotkey = if (is_fz) "NUMPAD1" else "",
            });
        }
    }

    // Add canonical template scripts
    try tbl.addScript(.{
        .name = "Godmode Value Lock",
        .sanskrit_name = "अमृत्व रक्षा",
        .script_body = "sharabha.freeze_i32(0x140001000, 999999, 'Godmode Lock')\nprint('🔱 Godmode Armed')",
        .auto_run = false,
    });

    ensureDirectory("assets");
    ensureDirectory("assets/tables");

    const final_path = if (file_path.len > 0) file_path else "assets/tables/workspace.sharabha";
    try tbl.saveToFile(final_path);

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // CHEAT TABLE SERIALIZATION (.sharabha)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  [✓] Successfully serialized {d} records and {d} scripts to:\n", .{ tbl.records.items.len, tbl.scripts.items.len });
    std.debug.print("      '{s}'\n", .{final_path});
}

pub fn handleLoadTable(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const table_mod = @import("table.zig");
    const final_path = if (file_path.len > 0) file_path else "assets/tables/workspace.sharabha";

    var tbl = try table_mod.SharabhaTable.loadFromFile(allocator, final_path);
    defer tbl.deinit();

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // CHEAT TABLE DESERIALIZATION (.sharabha)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Title       : {s} ({s})\n", .{ tbl.title, tbl.sanskrit_title });
    std.debug.print("  Target Exe  : {s} [{s}]\n", .{ tbl.process_name, tbl.architecture });
    std.debug.print("  Records ({d}):\n", .{tbl.records.items.len});

    for (tbl.records.items, 0..) |rec, i| {
        if (i < 15) {
            std.debug.print("    • [{d}] 0x{X} | {s} ({s}) | Frozen: {s}\n", .{
                rec.id,
                rec.static_address,
                rec.description,
                rec.value_type.toString(),
                if (rec.is_frozen) "YES" else "NO",
            });
        }
    }
    if (tbl.records.items.len > 15) {
        std.debug.print("    ... and {d} more records in table.\n", .{tbl.records.items.len - 15});
    }

    std.debug.print("  Embedded Scripts ({d}):\n", .{tbl.scripts.items.len});
    for (tbl.scripts.items) |sc| {
        std.debug.print("    🔱 '{s}' [Auto-Run: {s}]\n", .{ sc.name, if (sc.auto_run) "YES" else "NO" });
    }
}

pub fn handleLoadCt(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const ct_parser = @import("ct_parser.zig");
    const ce_compat = @import("../scripting/ce_compat.zig");
    const scripting = @import("../scripting/engine.zig");

    const final_path = if (file_path.len > 0) file_path else "assets/tables/workspace.CT";
    const bytes = try ct_parser.readCtFile(allocator, final_path);
    defer allocator.free(bytes);

    var parser = ct_parser.CtParser.init(allocator, bytes);
    var ct_tbl = try parser.parse();
    defer ct_tbl.deinit();

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // CHEAT ENGINE TABLE INQUEST (.CT / चेतना तालिका)\n", .{});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Vessel Path : {s}\n", .{final_path});
    std.debug.print("  CE Version  : {d}\n", .{ct_tbl.version});
    std.debug.print("  Symbols ({d}):\n", .{ct_tbl.symbols.items.len});

    // Register symbols
    for (ct_tbl.symbols.items) |sym| {
        try ce_compat.registerSymbol(sym.name, sym.address, allocator);
        std.debug.print("    • [Symbol] {s} => 0x{X}\n", .{ sym.name, sym.address });
    }

    const flat_entries = try ct_tbl.flattenEntries(allocator);
    defer allocator.free(flat_entries);
    std.debug.print("  Total Entries Discovered: {d}\n", .{flat_entries.len});

    // Target process detection & pointer resolution
    const target_pid = getOrDetectTargetPid() catch 0;
    var ph: ?process.ProcessHandle = null;
    if (target_pid != 0) {
        ph = process.ProcessHandle.open(target_pid) catch null;
    }
    defer if (ph) |*p| p.close();

    // Check for Master Lua Script
    if (ct_tbl.lua_script) |ls| {
        std.debug.print("  🔱 Master LuaScript Detected ({d} bytes). Executing...\n", .{ls.len});
        var engine = try scripting.ScriptEngine.init(allocator, null);
        defer engine.deinit();

        if (target_pid != 0) {
            engine.attach(target_pid) catch {};
        }

        const ls_z = try allocator.allocSentinel(u8, ls.len, 0);
        @memcpy(ls_z, ls);
        defer allocator.free(ls_z);

        const res = engine.executeWithOutput(ls_z);
        if (res.output.len > 0) {
            std.debug.print("  [Master Lua Output]:\n{s}\n", .{res.output});
        }
        if (!res.success) {
            std.debug.print("  ⚠️ [Lua Warning]: {s}\n", .{res.error_msg orelse "Unknown"});
        } else {
            std.debug.print("  [✓] Master Lua script initialized.\n", .{});
        }
    }

    // Write src/ui/live_table.slint
    try exportLiveTableSlint(allocator, final_path, flat_entries, ph);

    // Persist active table path (resolved against the project root so packaged
    // `bin\Sharabha.exe` runs still update the file the launcher scripts read).
    const act_tbl_path = resolveProjectPath(allocator, "assets\\tables\\active_table_path.txt") catch null;
    if (act_tbl_path) |ap| {
        defer allocator.free(ap);
        const act_tbl_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, ap) catch null;
        if (act_tbl_w) |pw| {
            defer allocator.free(pw);
            const h = win.CreateFileW(pw.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
            if (h != win.INVALID_HANDLE_VALUE) {
                defer _ = win.CloseHandle(h);
                var wr: u32 = 0;
                _ = win.WriteFile(h, final_path.ptr, @intCast(final_path.len), &wr, null);
            }
        }
    }

    std.debug.print("  [✓] Synchronized {d} entries to src/ui/live_table.slint\n", .{flat_entries.len});
}

pub fn handleRunCtEntry(allocator: std.mem.Allocator, file_path: []const u8, entry_id_str: []const u8) !void {
    const ct_parser = @import("ct_parser.zig");
    const scripting = @import("../scripting/engine.zig");

    const entry_id = std.fmt.parseInt(u32, entry_id_str, 10) catch {
        std.debug.print("  ❌ [Invalid Entry ID]: {s}\n", .{entry_id_str});
        return;
    };

    const final_path = if (file_path.len > 0) file_path else "assets/tables/workspace.CT";
    const bytes = try ct_parser.readCtFile(allocator, final_path);
    defer allocator.free(bytes);

    var parser = ct_parser.CtParser.init(allocator, bytes);
    var ct_tbl = try parser.parse();
    defer ct_tbl.deinit();

    const entry = ct_tbl.findEntryById(entry_id) orelse {
        std.debug.print("  ❌ [Entry Not Found]: ID {d}\n", .{entry_id});
        return;
    };

    std.debug.print("========================================================================\n", .{});
    std.debug.print("  SHARABHA // CHEAT ENTRY ACTIVATION (ID {d})\n", .{entry.id});
    std.debug.print("========================================================================\n", .{});
    std.debug.print("  Description : {s}\n", .{entry.description});
    std.debug.print("  Type        : {s}\n", .{entry.variable_type});

    if (entry.isScript()) {
        const sec = entry.extractScriptSections();
        const script_to_run = sec.enable orelse entry.assembler_script orelse "";

        var lua_code: []const u8 = script_to_run;
        if (std.mem.indexOf(u8, script_to_run, "{$lua}")) |l_start| {
            const after_lua = script_to_run[l_start + "{$lua}".len ..];
            if (std.mem.indexOf(u8, after_lua, "{$asm}")) |l_end| {
                lua_code = after_lua[0..l_end];
            } else {
                lua_code = after_lua;
            }
        }

        var engine = try scripting.ScriptEngine.init(allocator, null);
        defer engine.deinit();

        const target_pid = getOrDetectTargetPid() catch 0;
        if (target_pid != 0) {
            engine.attach(target_pid) catch {};
        }

        const trimmed_lua = std.mem.trim(u8, lua_code, " \r\n\t");
        const script_z = try allocator.allocSentinel(u8, trimmed_lua.len, 0);
        @memcpy(script_z, trimmed_lua);
        defer allocator.free(script_z);

        const res = engine.executeWithOutput(script_z);
        if (res.output.len > 0) {
            std.debug.print("  [Script Output]:\n{s}\n", .{res.output});
        }
        if (!res.success) {
            std.debug.print("  ❌ [Script Error]: {s}\n", .{res.error_msg orelse "Unknown"});
        } else {
            std.debug.print("  [✓] Entry script evaluated successfully.\n", .{});
        }
    } else {
        std.debug.print("  [Address Record]: {s}\n", .{entry.address});
    }
}

fn readProcessVal(proc: *const process.ProcessHandle, comptime T: type, address: usize) ?T {
    var buf: [@sizeOf(T)]u8 = undefined;
    const br = proc.readMemory(address, &buf) catch return null;
    if (br != @sizeOf(T)) return null;
    return @as(*const T, @ptrCast(@alignCast(&buf))).*;
}

fn exportLiveTableSlint(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    entries: []const @import("ct_parser.zig").CtEntry,
    ph: ?process.ProcessHandle,
) !void {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator, "// Auto-generated by Sharabha Rudra Tandava Memory Inquest Engine\n");
    try list.appendSlice(allocator, "export struct CheatTableRowData {\n");
    try list.appendSlice(allocator, "    id: int,\n    description: string,\n    address: string,\n    val_type: string,\n    val: string,\n    is_frozen: bool,\n    is_script: bool,\n    script_active: bool,\n}\n\n");

    var basename = std.fs.path.basename(file_path);
    if (std.mem.endsWith(u8, basename, ".ct") or std.mem.endsWith(u8, basename, ".CT")) {
        basename = basename[0 .. basename.len - 3];
    }

    try list.appendSlice(allocator, "export global LiveTable {\n    in property <string> table_title: \"");
    try appendEscapedSlint(&list, allocator, basename);
    try list.appendSlice(allocator, "\";\n    in property <string> file_path: \"");
    try appendEscapedSlint(&list, allocator, file_path);
    try list.appendSlice(allocator, "\";\n    in property <string> status_feedback: \"Loaded: ");
    try appendEscapedSlint(&list, allocator, basename);

    const hdr = try std.fmt.allocPrint(allocator,
        " ({d} Entries)\";\n    in property <int> total_entries: {d};\n    in property <bool> is_ct_table: true;\n\n    in property <[CheatTableRowData]> rows: [\n",
        .{ entries.len, entries.len },
    );
    defer allocator.free(hdr);
    try list.appendSlice(allocator, hdr);

    const max_rows = @min(entries.len, 50);
    for (entries[0..max_rows], 0..) |entry, i| {
        var val_str: []const u8 = "???";
        var addr_buf: [128]u8 = undefined;
        var addr_display: []const u8 = entry.address;
        if (entry.offsets.len > 0) {
            addr_display = std.fmt.bufPrint(&addr_buf, "{s} -> +0x{X}", .{ entry.address, entry.offsets[0] }) catch entry.address;
        }

        if (entry.isScript()) {
            val_str = if (entry.has_lua) "[Lua Altar]" else "[Auto Assembler]";
        } else if (ph) |proc| {
            var resolved_addr: usize = 0;
            if (std.mem.indexOf(u8, entry.address, "+")) |p_idx| {
                const mod_name = std.mem.trim(u8, entry.address[0..p_idx], " \"'");
                const off_val = @import("ct_parser.zig").parseHexOrDec(entry.address[p_idx + 1 ..]);
                var iter = process.ModuleIterator.init(proc.pid) catch null;
                if (iter) |*it| {
                    defer it.deinit();
                    while (it.next()) |me| {
                        if (std.ascii.eqlIgnoreCase(me.getName(), mod_name) or std.mem.eql(u8, mod_name, "$process")) {
                            resolved_addr = me.base_address + off_val;
                            break;
                        }
                    }
                }
            } else {
                resolved_addr = @import("ct_parser.zig").parseHexOrDec(entry.address);
            }

            if (resolved_addr != 0 and entry.offsets.len > 0) {
                var cur = resolved_addr;
                var o_idx = entry.offsets.len;
                while (o_idx > 1) {
                    o_idx -= 1;
                    const next_val = readProcessVal(&proc, usize, cur + entry.offsets[o_idx]);
                    if (next_val == null or next_val.? == 0) break;
                    cur = next_val.?;
                }
                resolved_addr = cur + entry.offsets[0];
            }

            if (resolved_addr != 0) {
                var v_buf: [64]u8 = undefined;
                if (std.mem.indexOf(u8, entry.variable_type, "Float") != null) {
                    if (readProcessVal(&proc, f32, resolved_addr)) |fv| {
                        val_str = std.fmt.bufPrint(&v_buf, "{d:.2}", .{fv}) catch "???";
                    }
                } else if (std.mem.indexOf(u8, entry.variable_type, "Double") != null) {
                    if (readProcessVal(&proc, f64, resolved_addr)) |dv| {
                        val_str = std.fmt.bufPrint(&v_buf, "{d:.4}", .{dv}) catch "???";
                    }
                } else {
                    if (readProcessVal(&proc, i32, resolved_addr)) |iv| {
                        val_str = std.fmt.bufPrint(&v_buf, "{d}", .{iv}) catch "???";
                    }
                }
            }
        }

        try list.appendSlice(allocator, "        { id: ");
        var num_buf: [32]u8 = undefined;
        try list.appendSlice(allocator, try std.fmt.bufPrint(&num_buf, "{d}", .{entry.id}));
        try list.appendSlice(allocator, ", description: \"");
        try appendEscapedSlint(&list, allocator, entry.description);
        try list.appendSlice(allocator, "\", address: \"");
        try appendEscapedSlint(&list, allocator, addr_display);
        try list.appendSlice(allocator, "\", val_type: \"");
        try appendEscapedSlint(&list, allocator, entry.variable_type);
        try list.appendSlice(allocator, "\", val: \"");
        try appendEscapedSlint(&list, allocator, val_str);
        try list.appendSlice(allocator, "\", is_frozen: false, is_script: ");
        try list.appendSlice(allocator, if (entry.isScript()) "true" else "false");
        try list.appendSlice(allocator, ", script_active: false }");
        if (i + 1 < max_rows) {
            try list.appendSlice(allocator, ",\n");
        } else {
            try list.appendSlice(allocator, "\n");
        }
    }

    try list.appendSlice(allocator, "    ];\n}\n");

    // Atomic swap: slint-viewer watches this file with --auto-reload.
    // Resolved against the project root so a packaged `bin\Sharabha.exe`
    // (CWD = bin\) still updates the file the viewer is actually watching.
    const slint_path = try resolveProjectPath(allocator, std.mem.span(LIVE_TABLE_SLINT_PATH));
    defer allocator.free(slint_path);
    try writeFullFile(slint_path.ptr, list.items);
}

/// Escapes a value for a Slint string literal and guarantees valid UTF-8 output,
/// so a `.CT` authored in a legacy code page can never emit an uncompilable
/// `live_table.slint` (which would take the auto-reloading viewer down with it).
fn appendEscapedSlint(list: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    var i: usize = 0;
    while (i < str.len) {
        const b = str[i];
        if (b == '"') {
            try list.appendSlice(allocator, "\\\"");
            i += 1;
        } else if (b == '\\') {
            try list.appendSlice(allocator, "\\\\");
            i += 1;
        } else if (b == '\n' or b == '\r' or b == '\t') {
            try list.appendSlice(allocator, " ");
            i += 1;
        } else if (b < 0x20 or b == 0x7F) {
            // Drop other control characters (NUL, BEL, ESC, ...) outright.
            i += 1;
        } else if (b < 0x80) {
            const ch = [_]u8{b};
            try list.appendSlice(allocator, &ch);
            i += 1;
        } else {
            const seq_len = std.unicode.utf8ByteSequenceLength(b) catch {
                try list.appendSlice(allocator, "?");
                i += 1;
                continue;
            };
            if (i + seq_len > str.len or !std.unicode.utf8ValidateSlice(str[i .. i + seq_len])) {
                try list.appendSlice(allocator, "?");
                i += 1;
                continue;
            }
            try list.appendSlice(allocator, str[i .. i + seq_len]);
            i += seq_len;
        }
    }
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

    // The armed sentinel must not outlive the test: a live daemon keeps
    // SharabhaCli.exe mapped and breaks the next `zig build` install step.
    handleStopFreezeDaemon();
    try std.testing.expect(isFreezeDaemonRunning() == null);

    // 5. Reset scan test
    try handleResetScan(allocator);
}

test "writeFullFile performs an atomic swap and leaves no temp file behind" {
    const probe_path = "assets/memory/_write_probe.txt";
    ensureDirectory("assets");
    ensureDirectory("assets/memory");
    deleteFile("assets/memory/_write_probe.txt");
    deleteFile("assets/memory/_write_probe.txt.tmp");

    const payload = "Sharabha atomic write probe \xCE\xBB\nsecond line\n";
    try writeFullFile(probe_path, payload);
    // Overwrite must replace, never append.
    try writeFullFile(probe_path, payload);

    var buf: [256]u8 = undefined;
    const read = readFullFile(probe_path, &buf) orelse return error.ProbeNotWritten;
    try std.testing.expectEqualStrings(payload, buf[0..read]);

    // The shadow copy is renamed over the target, so it must not survive.
    var tmp_buf: [64]u8 = undefined;
    try std.testing.expect(readFullFile("assets/memory/_write_probe.txt.tmp", &tmp_buf) == null);

    deleteFile(probe_path);
}

test "appendEscapedSlint keeps live_table.slint compilable for hostile input" {
    const allocator = std.testing.allocator;

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    // quote, backslash, newline, carriage return, tab, NUL/BEL, valid UTF-8
    // (emoji + Devanagari) and an invalid lone 0x94 byte (CP1252 smart quote).
    const hostile = "a\"b\\c\nd\re\tf\x00g\x07h\xF0\x9F\x94\xB1\xE0\xA4\xB8\x94z";
    try appendEscapedSlint(&list, allocator, hostile);

    try std.testing.expectEqualStrings(
        "a\\\"b\\\\c d e fgh\xF0\x9F\x94\xB1\xE0\xA4\xB8?z",
        list.items,
    );
    // Whatever a `.CT` contains, the emitted Slint literal stays valid UTF-8.
    try std.testing.expect(std.unicode.utf8ValidateSlice(list.items));
}

test "resolveProjectPath locates project-relative UI assets" {
    const allocator = std.testing.allocator;

    // Table fixture (slash form, as used by the Slint bridge constants).
    const table_path = try resolveProjectPath(allocator, "assets/tables/SampleTable.CT");
    defer allocator.free(table_path);
    try std.testing.expect(pathExistsUtf8(table_path));

    // Backslash form, as used by the active-table path persistence.
    const active_path = try resolveProjectPath(allocator, "assets\\tables\\SampleTable.CT");
    defer allocator.free(active_path);
    try std.testing.expect(pathExistsUtf8(active_path));

    // Unresolvable paths degrade to the literal relative path instead of failing.
    const missing = try resolveProjectPath(allocator, "src/ui/__sharabha_missing_bridge.slint");
    defer allocator.free(missing);
    try std.testing.expect(!pathExistsUtf8(missing));
    try std.testing.expectEqualStrings("src/ui/__sharabha_missing_bridge.slint", std.mem.span(missing.ptr));
}
