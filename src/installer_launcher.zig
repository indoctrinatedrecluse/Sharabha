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

    // 1. Discover slint-viewer executable
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

    // 2. Assemble Installer Slint Invocation
    const cmd = try std.fmt.allocPrint(allocator,
        "\"{s}\" src/ui/installer.slint " ++
        "--on browse_dir \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command \\\"Add-Type -AssemblyName System.Windows.Forms; \\$f = New-Object System.Windows.Forms.FolderBrowserDialog; \\$f.Description = 'Select Sharabha Vessel Installation Directory'; \\$f.ShowNewFolderButton = \\$true; if (\\$f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {{{{ Write-Host \\$f.SelectedPath }}}}\\\"\" " ++
        "--on start_install \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File tools/installer_logic.ps1 -TargetPath \\\"$1\\\" -CreateDesktopShortcut -CreateStartMenu -LaunchAfter\" " ++
        "--on finish_install \"powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command \\\"Start-Process -FilePath 'bin/Sharabha.exe'\\\"\"",
        .{slint_exe}
    );

    const cmd_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, cmd);

    var si: win.STARTUPINFOW = .{};
    si.dwFlags = 0;
    var pi: win.PROCESS_INFORMATION = undefined;

    if (win.CreateProcessW(null, cmd_w.ptr, null, null, 0, 0, null, null, &si, &pi) != 0) {
        _ = win.WaitForSingleObject(pi.hProcess, win.INFINITE);
        _ = win.CloseHandle(pi.hProcess);
        _ = win.CloseHandle(pi.hThread);
    }
}
