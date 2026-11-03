const std = @import("std");

const win = struct {
    pub const HANDLE = *anyopaque;
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
        wShowWindow: u16 = 0, // SW_HIDE
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

    pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
    pub const INFINITE: DWORD = 0xFFFFFFFF;
    pub const INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFFFFFF;

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
};

fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_w);
    const attr = win.GetFileAttributesW(path_w.ptr);
    return attr != win.INVALID_FILE_ATTRIBUTES;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 1. Silently harvest host processes via hidden PowerShell execution
    var si_pre: win.STARTUPINFOW = .{};
    var pi_pre: win.PROCESS_INFORMATION = undefined;
    const pre_cmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/refresh_processes.ps1";
    const pre_cmd_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, pre_cmd);
    if (win.CreateProcessW(null, pre_cmd_w.ptr, null, null, 0, win.CREATE_NO_WINDOW, null, null, &si_pre, &pi_pre) != 0) {
        _ = win.WaitForSingleObject(pi_pre.hProcess, 4000);
        _ = win.CloseHandle(pi_pre.hProcess);
        _ = win.CloseHandle(pi_pre.hThread);
    }

    // 2. Discover slint-viewer executable location
    var slint_exe: []const u8 = "slint-viewer.exe";
    if (fileExists(allocator, "bin\\slint-viewer.exe")) {
        slint_exe = "bin\\slint-viewer.exe";
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

    // 3. Assemble slint-viewer invocation with hidden PowerShell callbacks
    const cmd = try std.fmt.allocPrint(allocator,
        "\"{s}\" src/ui/app.slint --auto-reload " ++
        "--on refresh_processes \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/refresh_processes.ps1\" " ++
        "--on attach_process \"zig-out/bin/SharabhaCli.exe --attach $1\" " ++
        "--on start_memory_scan \"zig-out/bin/SharabhaCli.exe --scan $1 $2\" " ++
        "--on rescan_memory \"zig-out/bin/SharabhaCli.exe --rescan $1 $2\" " ++
        "--on reset_memory_scan \"zig-out/bin/SharabhaCli.exe --reset-scan\" " ++
        "--on write_memory_address \"zig-out/bin/SharabhaCli.exe --write-mem $1 $2\" " ++
        "--on toggle_freeze_address \"zig-out/bin/SharabhaCli.exe --freeze-mem $1 $2\" " ++
        "--on scan_pointer \"zig-out/bin/SharabhaCli.exe --pointer-scan $1 4 4096\" " ++
        "--on disassemble_address \"zig-out/bin/SharabhaCli.exe --disasm $1 16\" " ++
        "--on watch_address_writes \"zig-out/bin/SharabhaCli.exe --watch-writes $1 3000\" " ++
        "--on run_lua_script \"zig-out/bin/SharabhaCli.exe --run-lua \\\"$1\\\"\" " ++
        "--on open_save_file \"powershell.exe -Sta -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1\" " ++
        "--on reparse_save_file \"powershell.exe -Sta -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1 -Reparse\" " ++
        "--on write_save_field \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/write_save.ps1 $1 $2\" " ++
        "--on save_file_atomic \"zig-out/bin/SharabhaCli.exe --commit-save\" " ++
        "--on test_vault \"zig-out/bin/SharabhaCli.exe --test-vault\" " ++
        "--on save_vault \"zig-out/bin/SharabhaCli.exe --seal-vault\" " ++
        "--on save_memory_table \"zig-out/bin/SharabhaCli.exe --save-table $1\" " ++
        "--on load_memory_table \"zig-out/bin/SharabhaCli.exe --load-table $1\" " ++
        "--on inject_dll \"zig-out/bin/SharabhaCli.exe --inject-dll $1\" " ++
        "--on export_agamas \"zig-out/bin/SharabhaCli.exe --export-agamas $1\" " ++
        "--on filter_save_rows \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/filter_save.ps1 \\\"$1\\\"\" " ++
        "--on register_agama_profile \"zig-out/bin/SharabhaCli.exe --export-surreal\"",
        .{slint_exe}
    );

    const cmd_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd);

    var si: win.STARTUPINFOW = .{
        .dwFlags = 0x00000001, // STARTF_USESHOWWINDOW
        .wShowWindow = 1, // SW_SHOWNORMAL
    };
    var pi: win.PROCESS_INFORMATION = undefined;

    // Launch slint-viewer with visible window
    if (win.CreateProcessW(null, cmd_w.ptr, null, null, 0, 0, null, null, &si, &pi) != 0) {
        _ = win.WaitForSingleObject(pi.hProcess, win.INFINITE);
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
    }
}
