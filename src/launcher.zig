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
    pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
    pub extern "kernel32" fn GetExitCodeProcess(hProcess: HANDLE, lpExitCode: *DWORD) callconv(.winapi) BOOL;
    pub extern "kernel32" fn ExitProcess(uExitCode: DWORD) callconv(.winapi) noreturn;
    pub extern "kernel32" fn GetModuleFileNameW(hModule: ?HANDLE, lpFilename: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;
};

fn indexOfCaseInsensitiveU16(haystack: []const u16, needle: []const u16) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = haystack[i + j];
            const h_lower = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            const n_lower = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
            if (h_lower != n_lower) {
                match = false;
                break;
            }
        }
        if (match) return i;
    }
    return null;
}

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

    // 0. Handle Silent IPC Callback Proxy Mode:
    // When invoked with "--run-silent <cmd...>", execute target via CreateProcessW
    // using CREATE_NO_WINDOW and SW_HIDE with zero console window flashing.
    const full_cmd = win.GetCommandLineW();
    var cmd_len: usize = 0;
    while (full_cmd[cmd_len] != 0) : (cmd_len += 1) {}
    const cmd_slice = full_cmd[0..cmd_len];

    const silent_flag = std.unicode.utf8ToUtf16LeStringLiteral("--run-silent");
    if (indexOfCaseInsensitiveU16(cmd_slice, silent_flag)) |flag_idx| {
        var tail_idx = flag_idx + silent_flag.len;
        while (tail_idx < cmd_slice.len and (cmd_slice[tail_idx] == ' ' or cmd_slice[tail_idx] == '\t')) : (tail_idx += 1) {}
        if (tail_idx < cmd_slice.len) {
            const child_cmd = cmd_slice[tail_idx..];
            const child_cmd_w = try allocator.allocSentinel(u16, child_cmd.len, 0);
            @memcpy(child_cmd_w[0..child_cmd.len], child_cmd);

            var si_child: win.STARTUPINFOW = .{
                .dwFlags = 0x00000001, // STARTF_USESHOWWINDOW
                .wShowWindow = 0, // SW_HIDE
            };
            var pi_child: win.PROCESS_INFORMATION = undefined;

            if (win.CreateProcessW(null, child_cmd_w.ptr, null, null, 0, win.CREATE_NO_WINDOW, null, null, &si_child, &pi_child) != 0) {
                _ = win.WaitForSingleObject(pi_child.hProcess, win.INFINITE);
                var exit_code: win.DWORD = 0;
                _ = win.GetExitCodeProcess(pi_child.hProcess, &exit_code);
                _ = win.CloseHandle(pi_child.hProcess);
                _ = win.CloseHandle(pi_child.hThread);
                win.ExitProcess(exit_code);
            } else {
                win.ExitProcess(1);
            }
        }
        win.ExitProcess(0);
    }

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

    // 2. Discover self and companion binary paths
    var self_buf: [1024]u16 = undefined;
    const self_chars = win.GetModuleFileNameW(null, &self_buf, 1024);
    var self_exe: []const u8 = "zig-out/bin/Sharabha.exe";
    if (self_chars > 0 and self_chars < 1024) {
        self_exe = try std.unicode.utf16LeToUtf8Alloc(allocator, self_buf[0..self_chars]);
    }

    var cli_exe: []const u8 = "zig-out/bin/SharabhaCli.exe";
    if (fileExists(allocator, "bin/SharabhaCli.exe")) {
        cli_exe = "bin/SharabhaCli.exe";
    }

    // Discover slint-viewer executable location
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

    // 3. Assemble slint-viewer invocation with hidden, cloaked callbacks
    // All callback processes run through self --run-silent to ensure CREATE_NO_WINDOW
    // without any flashing black terminal windows.
    var cmd_builder: std.ArrayList(u8) = .empty;
    defer cmd_builder.deinit(allocator);

    const base_cmd = try std.fmt.allocPrint(allocator, "\"{s}\" src/ui/app.slint --auto-reload", .{slint_exe});
    try cmd_builder.appendSlice(allocator, base_cmd);

    const Callback = struct {
        name: []const u8,
        cmd: []const u8,
    };

    const callbacks = [_]Callback{
        .{ .name = "refresh_processes", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/refresh_processes.ps1" },
        .{ .name = "filter_processes", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/refresh_processes.ps1 -Filter \\\"$1\\\"" },
        .{ .name = "attach_process", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --attach $1", .{cli_exe}) },
        .{ .name = "start_memory_scan", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --scan \\\"$1\\\" \\\"$2\\\"", .{cli_exe}) },
        .{ .name = "rescan_memory", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --rescan \\\"$1\\\" \\\"$2\\\"", .{cli_exe}) },
        .{ .name = "reset_memory_scan", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --reset-scan", .{cli_exe}) },
        .{ .name = "write_memory_address", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --write-mem \\\"$1\\\" \\\"$2\\\"", .{cli_exe}) },
        .{ .name = "toggle_freeze_address", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --freeze-mem \\\"$1\\\" \\\"$2\\\"", .{cli_exe}) },
        .{ .name = "scan_pointer", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --pointer-scan \\\"$1\\\" 4 4096", .{cli_exe}) },
        .{ .name = "disassemble_address", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --disasm \\\"$1\\\" 16", .{cli_exe}) },
        .{ .name = "watch_address_writes", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --watch-writes \\\"$1\\\" 3000", .{cli_exe}) },
        .{ .name = "patch_memory_nop", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --nop-patch \\\"$1\\\" \\\"$2\\\"", .{cli_exe}) },
        .{ .name = "disarm_hardware_watcher", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --disarm-watcher", .{cli_exe}) },
        .{ .name = "run_lua_script", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --run-lua \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "open_save_file", .cmd = "powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1" },
        .{ .name = "reparse_save_file", .cmd = "powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File tools/open_dialog.ps1 -Reparse" },
        .{ .name = "write_save_field", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/write_save.ps1 -Key \\\"$1\\\" -NewValue \\\"$2\\\"" },
        .{ .name = "save_file_atomic", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --commit-save", .{cli_exe}) },
        .{ .name = "test_vault", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --test-vault", .{cli_exe}) },
        .{ .name = "save_vault", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --seal-vault", .{cli_exe}) },
        .{ .name = "save_memory_table", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --save-table \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "load_memory_table", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --load-table \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "load_ct_file", .cmd = "powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File tools/open_ct.ps1" },
        .{ .name = "load_ct_merge", .cmd = "powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File tools/open_ct.ps1 -Merge" },
        .{ .name = "refresh_ct_values", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --refresh-ct", .{cli_exe}) },
        .{ .name = "clear_ct_table", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --clear-ct", .{cli_exe}) },
        .{ .name = "filter_ct_table", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --filter-ct \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "auto_attach_process", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --attach-name \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "run_table_entry", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --run-ct-entry \\\"$1\\\" \\\"$2\\\" \\\"$3\\\"", .{cli_exe}) },
        .{ .name = "inject_dll", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --inject-dll \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "export_agamas", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --export-agamas \\\"$1\\\"", .{cli_exe}) },
        .{ .name = "filter_save_rows", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/filter_save.ps1 \\\"$1\\\"" },
        .{ .name = "check_for_updates", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/updater.ps1 -Check -ActiveTab $1" },
        .{ .name = "start_update_download", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/updater.ps1 -Download -ActiveTab $1" },
        .{ .name = "dismiss_update_modal", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/updater.ps1 -Dismiss -ActiveTab $1" },
        .{ .name = "install_update_and_exit", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/updater.ps1 -Install -TargetSetupPath \\\"$1\\\"" },
        .{ .name = "diff_saves_backup", .cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/diff_saves.ps1 -CompareWithBak" },
        .{ .name = "diff_saves_dialog", .cmd = "powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File tools/diff_saves.ps1" },
        .{ .name = "register_agama_profile", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --export-surreal", .{cli_exe}) },
        .{ .name = "toggle_ai_guidance", .cmd = try std.fmt.allocPrint(allocator, "\\\"{s}\\\" --analyze-ai", .{cli_exe}) },
    };

    for (callbacks) |cb| {
        const item = try std.fmt.allocPrint(allocator, " --on {s} \"\\\"{s}\\\" --run-silent {s}\"", .{ cb.name, self_exe, cb.cmd });
        try cmd_builder.appendSlice(allocator, item);
    }

    const cmd = cmd_builder.items;

    const cmd_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd);

    var si: win.STARTUPINFOW = .{
        .dwFlags = 0x00000001, // STARTF_USESHOWWINDOW
        .wShowWindow = 1, // SW_SHOWNORMAL
    };
    var pi: win.PROCESS_INFORMATION = undefined;

    // Launch slint-viewer with visible window but cloaked console window
    if (win.CreateProcessW(null, cmd_w.ptr, null, null, 0, win.CREATE_NO_WINDOW, null, null, &si, &pi) != 0) {
        _ = win.WaitForSingleObject(pi.hProcess, win.INFINITE);
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
    }
}
