const std = @import("std");

pub const ProcessEntry = struct {
    pid: u32,
    name: [260]u8,
    name_len: usize,

    pub fn getName(self: *const ProcessEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const win = struct {
    pub const HANDLE = *anyopaque;
    pub const HMODULE = *anyopaque;
    pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));
    pub const TH32CS_SNAPPROCESS: u32 = 0x00000002;
    pub const TH32CS_SNAPMODULE: u32 = 0x00000008;
    pub const TH32CS_SNAPMODULE32: u32 = 0x00000010;
    pub const TH32CS_SNAPTHREAD: u32 = 0x00000004;

    pub const PROCESS_ALL_ACCESS: u32 = 0x001F0FFF;
    pub const PROCESS_CREATE_THREAD: u32 = 0x0002;
    pub const PROCESS_VM_READ: u32 = 0x0010;
    pub const PROCESS_VM_WRITE: u32 = 0x0020;
    pub const PROCESS_VM_OPERATION: u32 = 0x0008;
    pub const PROCESS_QUERY_INFORMATION: u32 = 0x0400;

    pub const MEM_COMMIT: u32 = 0x00001000;
    pub const MEM_RESERVE: u32 = 0x00002000;
    pub const MEM_RELEASE: u32 = 0x00008000;

    pub const PAGE_NOACCESS: u32 = 0x01;
    pub const PAGE_READONLY: u32 = 0x02;
    pub const PAGE_READWRITE: u32 = 0x04;
    pub const PAGE_EXECUTE: u32 = 0x10;
    pub const PAGE_EXECUTE_READ: u32 = 0x20;
    pub const PAGE_EXECUTE_READWRITE: u32 = 0x40;

    pub const INFINITE: u32 = 0xFFFFFFFF;
    pub const WAIT_OBJECT_0: u32 = 0x00000000;
    pub const WAIT_TIMEOUT: u32 = 0x00000102;

    pub const PROCESSENTRY32W = extern struct {
        dwSize: u32,
        cntUsage: u32,
        th32ProcessID: u32,
        th32DefaultHeapID: usize,
        th32ModuleID: u32,
        cntThreads: u32,
        th32ParentProcessID: u32,
        pcPriClassBase: i32,
        dwFlags: u32,
        szExeFile: [260]u16,
    };

    pub const MODULEENTRY32W = extern struct {
        dwSize: u32,
        th32ModuleID: u32,
        th32ProcessID: u32,
        GlblcntUsage: u32,
        ProccntUsage: u32,
        modBaseAddr: ?*u8,
        modBaseSize: u32,
        hModule: ?HANDLE,
        szModule: [256]u16,
        szExePath: [260]u16,
    };

    pub extern "kernel32" fn CreateToolhelp32Snapshot(dwFlags: u32, th32ProcessID: u32) callconv(.winapi) HANDLE;
    pub extern "kernel32" fn Process32FirstW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) i32;
    pub extern "kernel32" fn Process32NextW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) i32;
    pub extern "kernel32" fn Module32FirstW(hSnapshot: HANDLE, lpme: *MODULEENTRY32W) callconv(.winapi) i32;
    pub extern "kernel32" fn Module32NextW(hSnapshot: HANDLE, lpme: *MODULEENTRY32W) callconv(.winapi) i32;
    pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) i32;
    pub extern "kernel32" fn OpenProcess(dwDesiredAccess: u32, bInheritHandle: i32, dwProcessId: u32) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn ReadProcessMemory(hProcess: HANDLE, lpBaseAddress: ?*const anyopaque, lpBuffer: *anyopaque, nSize: usize, lpNumberOfBytesRead: ?*usize) callconv(.winapi) i32;
    pub extern "kernel32" fn WriteProcessMemory(hProcess: HANDLE, lpBaseAddress: ?*anyopaque, lpBuffer: *const anyopaque, nSize: usize, lpNumberOfBytesWritten: ?*usize) callconv(.winapi) i32;
    pub extern "kernel32" fn DeleteFileW(lpFileName: [*:0]const u16) callconv(.winapi) i32;
    pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
    pub extern "kernel32" fn GetStdHandle(nStdHandle: i32) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: [*]const u8, nNumberOfBytesToWrite: u32, lpNumberOfBytesWritten: ?*u32, lpOverlapped: ?*anyopaque) callconv(.winapi) i32;
    pub extern "kernel32" fn VirtualAllocEx(hProcess: HANDLE, lpAddress: ?*anyopaque, dwSize: usize, flAllocationType: u32, flProtect: u32) callconv(.winapi) ?*anyopaque;
    pub extern "kernel32" fn VirtualFreeEx(hProcess: HANDLE, lpAddress: ?*anyopaque, dwSize: usize, dwFreeType: u32) callconv(.winapi) i32;
    pub extern "kernel32" fn VirtualProtectEx(hProcess: HANDLE, lpAddress: ?*anyopaque, dwSize: usize, flNewProtect: u32, lpflOldProtect: *u32) callconv(.winapi) i32;
    pub extern "kernel32" fn CreateRemoteThread(hProcess: HANDLE, lpThreadAttributes: ?*anyopaque, dwStackSize: usize, lpStartAddress: ?*const anyopaque, lpParameter: ?*anyopaque, dwCreationFlags: u32, lpThreadId: ?*u32) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: u32) callconv(.winapi) u32;
    pub extern "kernel32" fn GetExitCodeThread(hThread: HANDLE, lpExitCode: *u32) callconv(.winapi) i32;
    pub extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
    pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?HMODULE;
};

pub const ProcessIterator = struct {
    snapshot: win.HANDLE,
    entry: win.PROCESSENTRY32W,
    is_first: bool,

    pub fn init() !ProcessIterator {
        const hSnap = win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0);
        if (hSnap == win.INVALID_HANDLE_VALUE) {
            return error.SnapshotFailed;
        }

        var entry: win.PROCESSENTRY32W = undefined;
        entry.dwSize = @sizeOf(win.PROCESSENTRY32W);

        return ProcessIterator{
            .snapshot = hSnap,
            .entry = entry,
            .is_first = true,
        };
    }

    pub fn deinit(self: *ProcessIterator) void {
        _ = win.CloseHandle(self.snapshot);
        self.snapshot = win.INVALID_HANDLE_VALUE;
    }

    pub fn next(self: *ProcessIterator) ?ProcessEntry {
        const success = if (self.is_first) blk: {
            self.is_first = false;
            break :blk win.Process32FirstW(self.snapshot, &self.entry);
        } else win.Process32NextW(self.snapshot, &self.entry);

        if (success == 0) return null;

        var result: ProcessEntry = .{
            .pid = self.entry.th32ProcessID,
            .name = undefined,
            .name_len = 0,
        };

        // Convert UTF-16 wide string to UTF-8
        var i: usize = 0;
        while (i < 260 and self.entry.szExeFile[i] != 0) : (i += 1) {}
        const wide_slice = self.entry.szExeFile[0..i];
        const utf8_len = std.unicode.utf16LeToUtf8(&result.name, wide_slice) catch {
            return result;
        };
        result.name_len = utf8_len;

        return result;
    }
};

pub const ModuleEntry = struct {
    base_address: usize,
    size: usize,
    name: [260]u8,
    name_len: usize,

    pub fn getName(self: *const ModuleEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const ModuleIterator = struct {
    snapshot: win.HANDLE,
    entry: win.MODULEENTRY32W,
    is_first: bool,

    pub fn init(pid: u32) !ModuleIterator {
        const hSnap = win.CreateToolhelp32Snapshot(win.TH32CS_SNAPMODULE | win.TH32CS_SNAPMODULE32, pid);
        if (hSnap == win.INVALID_HANDLE_VALUE) {
            return error.SnapshotFailed;
        }

        var entry: win.MODULEENTRY32W = undefined;
        entry.dwSize = @sizeOf(win.MODULEENTRY32W);

        return ModuleIterator{
            .snapshot = hSnap,
            .entry = entry,
            .is_first = true,
        };
    }

    pub fn deinit(self: *ModuleIterator) void {
        _ = win.CloseHandle(self.snapshot);
        self.snapshot = win.INVALID_HANDLE_VALUE;
    }

    pub fn next(self: *ModuleIterator) ?ModuleEntry {
        const success = if (self.is_first) blk: {
            self.is_first = false;
            break :blk win.Module32FirstW(self.snapshot, &self.entry);
        } else win.Module32NextW(self.snapshot, &self.entry);

        if (success == 0) return null;

        var result: ModuleEntry = .{
            .base_address = @intFromPtr(self.entry.modBaseAddr),
            .size = @as(usize, @intCast(self.entry.modBaseSize)),
            .name = undefined,
            .name_len = 0,
        };

        var i: usize = 0;
        while (i < 256 and self.entry.szModule[i] != 0) : (i += 1) {}
        const wide_slice = self.entry.szModule[0..i];
        const utf8_len = std.unicode.utf16LeToUtf8(&result.name, wide_slice) catch {
            return result;
        };
        result.name_len = utf8_len;

        return result;
    }
};

pub const ProcessHandle = struct {
    handle: win.HANDLE,
    pid: u32,

    pub fn open(pid: u32) !ProcessHandle {
        const access = win.PROCESS_VM_READ | win.PROCESS_VM_WRITE | win.PROCESS_VM_OPERATION | win.PROCESS_QUERY_INFORMATION;
        const h = win.OpenProcess(access, 0, pid);
        if (h) |handle| {
            return ProcessHandle{
                .handle = handle,
                .pid = pid,
            };
        } else {
            return error.OpenProcessFailed;
        }
    }

    pub fn close(self: *ProcessHandle) void {
        _ = win.CloseHandle(self.handle);
    }

    pub fn readMemory(self: *const ProcessHandle, address: usize, buffer: []u8) !usize {
        var bytes_read: usize = 0;
        const ptr: ?*const anyopaque = @ptrFromInt(address);
        const ok = win.ReadProcessMemory(self.handle, ptr, buffer.ptr, buffer.len, &bytes_read);
        if (ok == 0) return error.ReadMemoryFailed;
        return bytes_read;
    }

    pub fn writeMemory(self: *const ProcessHandle, address: usize, buffer: []const u8) !usize {
        var bytes_written: usize = 0;
        const ptr: ?*anyopaque = @ptrFromInt(address);
        const ok = win.WriteProcessMemory(self.handle, ptr, buffer.ptr, buffer.len, &bytes_written);
        if (ok == 0) return error.WriteMemoryFailed;
        return bytes_written;
    }
};
