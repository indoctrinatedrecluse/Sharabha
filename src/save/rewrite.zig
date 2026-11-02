const std = @import("std");

pub const win = struct {
    pub const HANDLE = *anyopaque;
    pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));

    pub const GENERIC_READ: u32 = 0x80000000;
    pub const GENERIC_WRITE: u32 = 0x40000000;
    pub const CREATE_ALWAYS: u32 = 2;
    pub const OPEN_EXISTING: u32 = 3;
    pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;

    pub const MOVEFILE_REPLACE_EXISTING: u32 = 0x00000001;
    pub const MOVEFILE_WRITE_THROUGH: u32 = 0x00000008;

    pub extern "kernel32" fn CreateFileW(
        lpFileName: [*:0]const u16,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?HANDLE,
    ) callconv(.winapi) HANDLE;

    pub extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: *const anyopaque,
        nNumberOfBytesToWrite: u32,
        lpNumberOfBytesWritten: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: *anyopaque,
        nNumberOfBytesToRead: u32,
        lpNumberOfBytesRead: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) i32;

    pub extern "kernel32" fn GetFileSize(hFile: HANDLE, lpFileSizeHigh: ?*u32) callconv(.winapi) u32;

    pub extern "kernel32" fn MoveFileExW(
        lpExistingFileName: [*:0]const u16,
        lpNewFileName: [*:0]const u16,
        dwFlags: u32,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn CopyFileW(
        lpExistingFileName: [*:0]const u16,
        lpNewFileName: [*:0]const u16,
        bFailIfExists: i32,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn DeleteFileW(lpFileName: [*:0]const u16) callconv(.winapi) i32;
};

pub const SafeRewriteError = error{
    BackupFailed,
    TempFileWriteFailed,
    AtomicReplaceFailed,
    FileNotFound,
    ReadFailed,
};

pub const SafeRewriteEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SafeRewriteEngine {
        return .{ .allocator = allocator };
    }

    /// Safely writes modified bytes to path with automatic backup and atomic replacement
    pub fn commitSafe(
        self: *SafeRewriteEngine,
        target_path_utf8: []const u8,
        modified_data: []const u8,
    ) !void {
        // 1. Convert target path to wide string
        const target_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, target_path_utf8);
        defer self.allocator.free(target_w);

        // 2. Form backup path: {target}.sharabha.bak
        const backup_path_utf8 = try std.fmt.allocPrint(self.allocator, "{s}.sharabha.bak", .{target_path_utf8});
        defer self.allocator.free(backup_path_utf8);
        const backup_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, backup_path_utf8);
        defer self.allocator.free(backup_w);

        // 3. Form temporary shadow write path: {target}.sharabha.tmp
        const tmp_path_utf8 = try std.fmt.allocPrint(self.allocator, "{s}.sharabha.tmp", .{target_path_utf8});
        defer self.allocator.free(tmp_path_utf8);
        const tmp_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, tmp_path_utf8);
        defer self.allocator.free(tmp_w);

        // Step A: Create backup copy of original (failsafe)
        _ = win.CopyFileW(target_w.ptr, backup_w.ptr, 0);

        // Step B: Write new payload to temp file via Win32 CreateFileW
        const hTmp = win.CreateFileW(
            tmp_w.ptr,
            win.GENERIC_WRITE,
            0,
            null,
            win.CREATE_ALWAYS,
            win.FILE_ATTRIBUTE_NORMAL,
            null,
        );
        if (hTmp == win.INVALID_HANDLE_VALUE) {
            return SafeRewriteError.TempFileWriteFailed;
        }

        var written: u32 = 0;
        const write_ok = win.WriteFile(hTmp, modified_data.ptr, @intCast(modified_data.len), &written, null);
        _ = win.CloseHandle(hTmp);

        if (write_ok == 0 or written != modified_data.len) {
            return SafeRewriteError.TempFileWriteFailed;
        }

        // Step C: Atomic Replace via MoveFileEx
        const flags = win.MOVEFILE_REPLACE_EXISTING | win.MOVEFILE_WRITE_THROUGH;
        const ok = win.MoveFileExW(tmp_w.ptr, target_w.ptr, flags);
        if (ok == 0) {
            return SafeRewriteError.AtomicReplaceFailed;
        }
    }
};

test "safe rewrite writes and creates backup" {
    const allocator = std.testing.allocator;
    var engine = SafeRewriteEngine.init(allocator);

    const test_file = "test_save_game.sav";
    const initial_data = "ORIGINAL_HERO_DATA_HP_100";
    const modified_data = "MODIFIED_HERO_DATA_HP_9999";

    const test_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, test_file);
    defer allocator.free(test_w);
    const bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "test_save_game.sav.sharabha.bak");
    defer allocator.free(bak_w);

    // Create initial test file
    const hInit = win.CreateFileW(test_w.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    try std.testing.expect(hInit != win.INVALID_HANDLE_VALUE);
    var bytes_written: u32 = 0;
    _ = win.WriteFile(hInit, initial_data.ptr, @intCast(initial_data.len), &bytes_written, null);
    _ = win.CloseHandle(hInit);

    defer _ = win.DeleteFileW(test_w.ptr);
    defer _ = win.DeleteFileW(bak_w.ptr);

    // Commit safe rewrite
    try engine.commitSafe(test_file, modified_data);

    // Verify modified file
    const hRead = win.CreateFileW(test_w.ptr, win.GENERIC_READ, 0, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    try std.testing.expect(hRead != win.INVALID_HANDLE_VALUE);
    var read_buf: [64]u8 = undefined;
    var bytes_read: u32 = 0;
    _ = win.ReadFile(hRead, &read_buf, 64, &bytes_read, null);
    _ = win.CloseHandle(hRead);

    try std.testing.expectEqualStrings(modified_data, read_buf[0..bytes_read]);

    // Verify backup file contains original data
    const hBak = win.CreateFileW(bak_w.ptr, win.GENERIC_READ, 0, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    try std.testing.expect(hBak != win.INVALID_HANDLE_VALUE);
    var bak_buf: [64]u8 = undefined;
    var bak_read: u32 = 0;
    _ = win.ReadFile(hBak, &bak_buf, 64, &bak_read, null);
    _ = win.CloseHandle(hBak);

    try std.testing.expectEqualStrings(initial_data, bak_buf[0..bak_read]);
}
