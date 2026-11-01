const std = @import("std");

const win = struct {
    pub const HANDLE = *anyopaque;
    pub const HMODULE = ?HANDLE;
    pub const HRSRC = HANDLE;
    pub const HGLOBAL = HANDLE;
    pub const DWORD = u32;
    pub const BOOL = i32;
    pub const LPWSTR = [*:0]u16;
    pub const LPCWSTR = [*:0]const u16;

    pub const STARTUPINFOW = extern struct {
        cb: DWORD = @sizeOf(STARTUPINFOW),
        lpReserved: ?LPWSTR = null,
        lpDesktop: ?LPWSTR = null,
        lpTitle: ?LPWSTR = null,
        dwX: DWORD = 0,
        dwY: DWORD = 0,
        dwXSize: DWORD = 0,
        dwYSize: DWORD = 0,
        dwXCountChars: DWORD = 0,
        dwYCountChars: DWORD = 0,
        dwFillAttribute: DWORD = 0,
        dwFlags: DWORD = 0x00000001, // STARTF_USESHOWWINDOW
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
        dwProcessId: DWORD,
        dwThreadId: DWORD,
    };

    pub const INFINITE: DWORD = 0xFFFFFFFF;
    pub const INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFFFFFF;
    pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
    pub const GENERIC_WRITE: DWORD = 0x40000000;
    pub const CREATE_ALWAYS: DWORD = 2;
    pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
    pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));

    pub extern "kernel32" fn CreateProcessW(
        lpApplicationName: ?LPCWSTR,
        lpCommandLine: ?LPWSTR,
        lpProcessAttributes: ?*anyopaque,
        lpThreadAttributes: ?*anyopaque,
        bInheritHandles: BOOL,
        dwCreationFlags: DWORD,
        lpEnvironment: ?*anyopaque,
        lpCurrentDirectory: ?LPCWSTR,
        lpStartupInfo: *STARTUPINFOW,
        lpProcessInformation: *PROCESS_INFORMATION,
    ) callconv(.winapi) BOOL;

    pub extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
    pub extern "kernel32" fn GetFileAttributesW(lpFileName: LPCWSTR) callconv(.winapi) DWORD;
    pub extern "kernel32" fn GetEnvironmentVariableW(lpName: LPCWSTR, lpBuffer: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;
    pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) DWORD;

    pub extern "kernel32" fn CreateDirectoryW(lpPathName: LPCWSTR, lpSecurityAttributes: ?*anyopaque) callconv(.winapi) BOOL;
    pub extern "kernel32" fn CreateFileW(
        lpFileName: LPCWSTR,
        dwDesiredAccess: DWORD,
        dwShareMode: DWORD,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: DWORD,
        dwFlagsAndAttributes: DWORD,
        hTemplateFile: ?HANDLE,
    ) callconv(.winapi) HANDLE;
    pub extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;
    pub extern "kernel32" fn DeleteFileW(lpFileName: LPCWSTR) callconv(.winapi) BOOL;

    pub extern "kernel32" fn FindResourceW(hModule: HMODULE, lpName: [*:0]const u16, lpType: [*:0]const u16) callconv(.winapi) ?HRSRC;
    pub extern "kernel32" fn LoadResource(hModule: HMODULE, hResInfo: HRSRC) callconv(.winapi) ?HGLOBAL;
    pub extern "kernel32" fn LockResource(hResData: HGLOBAL) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn SizeofResource(hModule: HMODULE, hResInfo: HRSRC) callconv(.winapi) DWORD;
};

fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_w);
    const attr = win.GetFileAttributesW(path_w.ptr);
    return attr != win.INVALID_FILE_ATTRIBUTES;
}

fn executeCommandSync(allocator: std.mem.Allocator, cmd: []const u8, working_dir: ?[]const u8) bool {
    const cmd_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd) catch return false;
    defer allocator.free(cmd_w);

    var wd_w: ?[:0]const u16 = null;
    if (working_dir) |wd| {
        wd_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, wd) catch null;
    }
    defer if (wd_w) |w| allocator.free(w);

    var si: win.STARTUPINFOW = .{
        .dwFlags = 0x00000001,
        .wShowWindow = 0, // Hidden
    };
    var pi: win.PROCESS_INFORMATION = undefined;

    const wd_ptr = if (wd_w) |w| w.ptr else null;
    if (win.CreateProcessW(null, cmd_w.ptr, null, null, 0, win.CREATE_NO_WINDOW, null, wd_ptr, &si, &pi) != 0) {
        _ = win.WaitForSingleObject(pi.hProcess, win.INFINITE);
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
        return true;
    }
    return false;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var staging_dir: []const u8 = ".";
    var is_temp: bool = false;

    // Query %TEMP% directory
    var temp_buf: [512]u16 = undefined;
    const temp_var_w = std.unicode.utf8ToUtf16LeStringLiteral("TEMP");
    const temp_len = win.GetEnvironmentVariableW(temp_var_w, &temp_buf, 512);

    var base_temp: []const u8 = "C:\\Windows\\Temp";
    if (temp_len > 0 and temp_len < 512) {
        base_temp = try std.unicode.utf16LeToUtf8Alloc(allocator, temp_buf[0..temp_len]);
    }

    // Check for Embedded ZIP Payload (Resource ID 100, Type RT_RCDATA = 10)
    const res_type: [*:0]const u16 = @ptrFromInt(10);
    const res_name: [*:0]const u16 = @ptrFromInt(100);
    const hRes = win.FindResourceW(null, res_name, res_type);

    if (hRes) |res| {
        const size = win.SizeofResource(null, res);
        const res_data = win.LoadResource(null, res);
        if (size > 0 and res_data != null) {
            const raw_bytes: [*]const u8 = @ptrCast(win.LockResource(res_data.?));

            const pid = win.GetCurrentProcessId();
            const temp_dir = try std.fmt.allocPrint(allocator, "{s}\\Sharabha_Setup_{d}", .{ base_temp, pid });

            // Create staging directory via Win32
            const temp_dir_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, temp_dir);
            _ = win.CreateDirectoryW(temp_dir_w.ptr, null);

            // Dump embedded zip payload via Win32
            const zip_path = try std.fmt.allocPrint(allocator, "{s}\\payload.zip", .{temp_dir});
            const zip_path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, zip_path);
            const hFile = win.CreateFileW(zip_path_w.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
            if (hFile != win.INVALID_HANDLE_VALUE) {
                var bytes_written: win.DWORD = 0;
                _ = win.WriteFile(hFile, raw_bytes, size, &bytes_written, null);
                _ = win.CloseHandle(hFile);
            }

            // Extract with native Windows tar.exe (falls back to PowerShell)
            const tar_cmd = try std.fmt.allocPrint(allocator, "tar.exe -xf \"{s}\" -C \"{s}\"", .{ zip_path, temp_dir });
            const extracted = executeCommandSync(allocator, tar_cmd, temp_dir);
            if (!extracted) {
                const ps_cmd = try std.fmt.allocPrint(allocator, "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -Path '{s}' -DestinationPath '{s}' -Force\"", .{ zip_path, temp_dir });
                _ = executeCommandSync(allocator, ps_cmd, temp_dir);
            }

            // Remove zip to free disk space
            _ = win.DeleteFileW(zip_path_w.ptr);

            staging_dir = temp_dir;
            is_temp = true;
        }
    }

    // Discover slint-viewer executable
    var slint_exe: []const u8 = "slint-viewer.exe";
    const local_slint = try std.fmt.allocPrint(allocator, "{s}\\bin\\slint-viewer.exe", .{staging_dir});
    if (fileExists(allocator, local_slint)) {
        slint_exe = local_slint;
    } else {
        const root_slint = try std.fmt.allocPrint(allocator, "{s}\\slint-viewer.exe", .{staging_dir});
        if (fileExists(allocator, root_slint)) {
            slint_exe = root_slint;
        } else {
            var user_prof_buf: [512]u16 = undefined;
            const name_w = std.unicode.utf8ToUtf16LeStringLiteral("USERPROFILE");
            const chars = win.GetEnvironmentVariableW(name_w, &user_prof_buf, 512);
            if (chars > 0 and chars < 512) {
                const user_prof = try std.unicode.utf16LeToUtf8Alloc(allocator, user_prof_buf[0..chars]);
                const cargo_path = try std.fmt.allocPrint(allocator, "{s}\\.cargo\\bin\\slint-viewer.exe", .{user_prof});
                if (fileExists(allocator, cargo_path)) {
                    slint_exe = cargo_path;
                }
            }
        }
    }

    // Assemble Installer Slint Invocation directly launching slint-viewer
    const cmd = try std.fmt.allocPrint(allocator,
        "\"{s}\" \"{s}\\src\\ui\\installer.slint\" " ++
        "--on browse_dir \"{s}\\tools\\installer_browse.cmd\" " ++
        "--on start_install \"\\\"{s}\\tools\\installer_start.cmd\\\" $1 $2 $3 $4\" " ++
        "--on finish_install \"\\\"{s}\\tools\\installer_finish.cmd\\\" $1\" " ++
        "--on cancel \"{s}\\tools\\installer_cancel.cmd\"",
        .{ slint_exe, staging_dir, staging_dir, staging_dir, staging_dir, staging_dir }
    );

    const cmd_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd);
    const staging_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, staging_dir);

    var si: win.STARTUPINFOW = .{
        .dwFlags = 0,
    };
    var pi: win.PROCESS_INFORMATION = undefined;

    // Launch slint-viewer directly and wait for it to close
    if (win.CreateProcessW(null, cmd_w.ptr, null, null, 0, 0, null, staging_w.ptr, &si, &pi) != 0) {
        _ = win.WaitForSingleObject(pi.hProcess, win.INFINITE);
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
    }

    // Cleanup temporary staging files after installer has completely exited
    if (is_temp) {
        const cleanup_cmd = try std.fmt.allocPrint(allocator, "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command \"Start-Sleep -Seconds 3; Remove-Item -Recurse -Force '{s}' -ErrorAction SilentlyContinue\"", .{staging_dir});
        const cleanup_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cleanup_cmd);
        var csi: win.STARTUPINFOW = .{
            .dwFlags = 0x00000001,
            .wShowWindow = 0,
        };
        var cpi: win.PROCESS_INFORMATION = undefined;
        if (win.CreateProcessW(null, cleanup_w.ptr, null, null, 0, win.CREATE_NO_WINDOW, null, null, &csi, &cpi) != 0) {
            _ = win.CloseHandle(cpi.hProcess);
            _ = win.CloseHandle(cpi.hThread);
        }
    }
}
