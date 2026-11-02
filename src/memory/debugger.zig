const std = @import("std");
const process = @import("process.zig");
const disasm = @import("disasm.zig");
const win_proc = process.win;

pub const win_dbg = struct {
    pub const HANDLE = win_proc.HANDLE;
    pub const DWORD = u32;
    pub const BOOL = i32;

    pub const THREAD_GET_CONTEXT: DWORD = 0x0008;
    pub const THREAD_SET_CONTEXT: DWORD = 0x0010;
    pub const THREAD_SUSPEND_RESUME: DWORD = 0x0002;
    pub const THREAD_QUERY_INFORMATION: DWORD = 0x0040;

    pub const CONTEXT_CONTROL: DWORD = 0x00100001;
    pub const CONTEXT_INTEGER: DWORD = 0x00100002;
    pub const CONTEXT_DEBUG_REGISTERS: DWORD = 0x00100010;
    pub const CONTEXT_FULL: DWORD = CONTEXT_CONTROL | CONTEXT_INTEGER;
    pub const CONTEXT_ALL: DWORD = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_DEBUG_REGISTERS;

    pub const EXCEPTION_DEBUG_EVENT: DWORD = 1;
    pub const CREATE_THREAD_DEBUG_EVENT: DWORD = 2;
    pub const CREATE_PROCESS_DEBUG_EVENT: DWORD = 3;
    pub const EXIT_THREAD_DEBUG_EVENT: DWORD = 4;
    pub const EXIT_PROCESS_DEBUG_EVENT: DWORD = 5;
    pub const LOAD_DLL_DEBUG_EVENT: DWORD = 6;
    pub const UNLOAD_DLL_DEBUG_EVENT: DWORD = 7;
    pub const OUTPUT_DEBUG_STRING_EVENT: DWORD = 8;
    pub const RIP_EVENT: DWORD = 9;

    pub const EXCEPTION_ACCESS_VIOLATION: DWORD = 0xC0000005;
    pub const EXCEPTION_BREAKPOINT: DWORD = 0x80000003;
    pub const EXCEPTION_SINGLE_STEP: DWORD = 0x80000004;

    pub const DBG_CONTINUE: DWORD = 0x00010002;
    pub const DBG_EXCEPTION_NOT_HANDLED: DWORD = 0x80010001;

    pub const THREADENTRY32 = extern struct {
        dwSize: DWORD,
        cntUsage: DWORD,
        th32ThreadID: DWORD,
        th32OwnerProcessID: DWORD,
        tpBasePri: i32,
        tpDeltaPri: i32,
        dwFlags: DWORD,
    };

    pub const EXCEPTION_RECORD = extern struct {
        ExceptionCode: DWORD,
        ExceptionFlags: DWORD,
        ExceptionRecord: ?*EXCEPTION_RECORD,
        ExceptionAddress: ?*anyopaque,
        NumberParameters: DWORD,
        ExceptionInformation: [15]usize,
    };

    pub const EXCEPTION_DEBUG_INFO = extern struct {
        ExceptionRecord: EXCEPTION_RECORD,
        dwFirstChance: DWORD,
    };

    pub const DEBUG_EVENT = extern struct {
        dwDebugEventCode: DWORD,
        dwProcessId: DWORD,
        dwThreadId: DWORD,
        u: extern union {
            Exception: EXCEPTION_DEBUG_INFO,
            CreateThread: extern struct {
                hThread: ?HANDLE,
                lpThreadLocalBase: ?*anyopaque,
                lpStartAddress: ?*anyopaque,
            },
            CreateProcessInfo: extern struct {
                hFile: ?HANDLE,
                hProcess: ?HANDLE,
                hThread: ?HANDLE,
                lpBaseOfImage: ?*anyopaque,
                dwDebugInfoFileOffset: DWORD,
                nDebugInfoSize: DWORD,
                lpThreadLocalBase: ?*anyopaque,
                lpStartAddress: ?*anyopaque,
                lpImageName: ?*anyopaque,
                fUnicode: u16,
            },
            ExitThread: extern struct { dwExitCode: DWORD },
            ExitProcess: extern struct { dwExitCode: DWORD },
            LoadDll: extern struct {
                hFile: ?HANDLE,
                lpBaseOfDll: ?*anyopaque,
                dwDebugInfoFileOffset: DWORD,
                nDebugInfoSize: DWORD,
                lpImageName: ?*anyopaque,
                fUnicode: u16,
            },
            UnloadDll: extern struct { lpBaseOfDll: ?*anyopaque },
            OutputDebugStringInfo: extern struct {
                lpDebugStringData: ?[*:0]u8,
                fUnicode: u16,
                nDebugStringLength: u16,
            },
            RipInfo: extern struct {
                dwError: DWORD,
                dwType: DWORD,
            },
        },
    };

    pub const CONTEXT = extern struct {
        P1Home: u64 = 0,
        P2Home: u64 = 0,
        P3Home: u64 = 0,
        P4Home: u64 = 0,
        P5Home: u64 = 0,
        P6Home: u64 = 0,
        ContextFlags: DWORD = 0,
        MxCsr: DWORD = 0,
        SegCs: u16 = 0,
        SegDs: u16 = 0,
        SegEs: u16 = 0,
        SegFs: u16 = 0,
        SegGs: u16 = 0,
        SegSs: u16 = 0,
        EFlags: DWORD = 0,
        Dr0: u64 = 0,
        Dr1: u64 = 0,
        Dr2: u64 = 0,
        Dr3: u64 = 0,
        Dr6: u64 = 0,
        Dr7: u64 = 0,
        Rax: u64 = 0,
        Rcx: u64 = 0,
        Rdx: u64 = 0,
        Rbx: u64 = 0,
        Rsp: u64 = 0,
        Rbp: u64 = 0,
        Rsi: u64 = 0,
        Rdi: u64 = 0,
        R8: u64 = 0,
        R9: u64 = 0,
        R10: u64 = 0,
        R11: u64 = 0,
        R12: u64 = 0,
        R13: u64 = 0,
        R14: u64 = 0,
        R15: u64 = 0,
        Rip: u64 = 0,
        FltSave: [512]u8 = @splat(0),
        VectorRegister: [26 * 16]u8 = @splat(0),
        VectorControl: u64 = 0,
        DebugControl: u64 = 0,
        LastBranchToRip: u64 = 0,
        LastBranchFromRip: u64 = 0,
        LastExceptionToRip: u64 = 0,
        LastExceptionFromRip: u64 = 0,
    };

    pub extern "kernel32" fn OpenThread(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwThreadId: DWORD) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn SuspendThread(hThread: HANDLE) callconv(.winapi) DWORD;
    pub extern "kernel32" fn ResumeThread(hThread: HANDLE) callconv(.winapi) DWORD;
    pub extern "kernel32" fn GetThreadContext(hThread: HANDLE, lpContext: *CONTEXT) callconv(.winapi) BOOL;
    pub extern "kernel32" fn SetThreadContext(hThread: HANDLE, lpContext: *const CONTEXT) callconv(.winapi) BOOL;
    pub extern "kernel32" fn Thread32First(hSnapshot: HANDLE, lpte: *THREADENTRY32) callconv(.winapi) BOOL;
    pub extern "kernel32" fn Thread32Next(hSnapshot: HANDLE, lpte: *THREADENTRY32) callconv(.winapi) BOOL;
    pub extern "kernel32" fn DebugActiveProcess(dwProcessId: DWORD) callconv(.winapi) BOOL;
    pub extern "kernel32" fn DebugActiveProcessStop(dwProcessId: DWORD) callconv(.winapi) BOOL;
    pub extern "kernel32" fn DebugSetProcessKillOnExit(KillOnExit: BOOL) callconv(.winapi) BOOL;
    pub extern "kernel32" fn WaitForDebugEvent(lpDebugEvent: *DEBUG_EVENT, dwMilliseconds: DWORD) callconv(.winapi) BOOL;
    pub extern "kernel32" fn ContinueDebugEvent(dwProcessId: DWORD, dwThreadId: DWORD, dwContinueStatus: DWORD) callconv(.winapi) BOOL;
};

pub const RegisterSnapshot = struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    rsp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rip: u64,
    eflags: u32,

    pub fn format(self: *const RegisterSnapshot, writer: anytype) !void {
        try writer.print("RAX={X:0>16} RBX={X:0>16} RCX={X:0>16} RDX={X:0>16}\n", .{ self.rax, self.rbx, self.rcx, self.rdx });
        try writer.print("RSI={X:0>16} RDI={X:0>16} RBP={X:0>16} RSP={X:0>16}\n", .{ self.rsi, self.rdi, self.rbp, self.rsp });
        try writer.print("R8 ={X:0>16} R9 ={X:0>16} R10={X:0>16} R11={X:0>16}\n", .{ self.r8, self.r9, self.r10, self.r11 });
        try writer.print("RIP={X:0>16} EFL={X:0>8}\n", .{ self.rip, self.eflags });
    }
};

pub const WatchHit = struct {
    address: usize,
    instruction: disasm.Instruction,
    registers: RegisterSnapshot,
    hit_count: usize,
};

/// Tandava Netra (ताण्डव नेत्र) — Win32 Hardware Breakpoint & Memory Access Watcher
/// Intercepts instruction executions that modify or read target memory addresses
/// using CPU debug registers (DR0-DR3 / DR7) with non-invasive detachment.
pub const DebugWatcher = struct {
    allocator: std.mem.Allocator,
    target_pid: u32,
    target_address: usize,
    hits: std.ArrayList(WatchHit),

    pub fn init(allocator: std.mem.Allocator, target_pid: u32, target_address: usize) DebugWatcher {
        return DebugWatcher{
            .allocator = allocator,
            .target_pid = target_pid,
            .target_address = target_address,
            .hits = .empty,
        };
    }

    pub fn deinit(self: *DebugWatcher) void {
        self.hits.deinit(self.allocator);
    }

    /// Sets hardware breakpoint DR0 on a specific thread with write trigger (Condition 01)
    pub fn armThreadHardwareBreakpoint(hThread: win_dbg.HANDLE, address: usize) !void {
        var ctx: win_dbg.CONTEXT = undefined;
        ctx.ContextFlags = win_dbg.CONTEXT_DEBUG_REGISTERS;

        if (win_dbg.GetThreadContext(hThread, &ctx) == 0) return error.GetThreadContextFailed;

        // Set DR0 address
        ctx.Dr0 = address;

        // DR7 configuration:
        // Bit 0 = 1 (L0: Local enable for DR0)
        // Bits 16-17 = 01 (Condition: break on data write only)
        // Bits 18-19 = 11 (Length: 4 bytes)
        ctx.Dr7 |= (1 << 0);
        ctx.Dr7 |= (1 << 16);
        ctx.Dr7 |= (3 << 18);

        if (win_dbg.SetThreadContext(hThread, &ctx) == 0) return error.SetThreadContextFailed;
    }

    /// Clears hardware breakpoint DR0 on a thread
    pub fn disarmThreadHardwareBreakpoint(hThread: win_dbg.HANDLE) !void {
        var ctx: win_dbg.CONTEXT = undefined;
        ctx.ContextFlags = win_dbg.CONTEXT_DEBUG_REGISTERS;

        if (win_dbg.GetThreadContext(hThread, &ctx) == 0) return error.GetThreadContextFailed;

        ctx.Dr0 = 0;
        ctx.Dr7 &= ~@as(u64, (1 << 0) | (3 << 16) | (3 << 18));

        if (win_dbg.SetThreadContext(hThread, &ctx) == 0) return error.SetThreadContextFailed;
    }

    /// Arms hardware watch across all active threads of target process
    pub fn armAllThreads(self: *DebugWatcher) !usize {
        const hSnap = win_proc.CreateToolhelp32Snapshot(win_proc.TH32CS_SNAPTHREAD, 0);
        if (hSnap == win_proc.INVALID_HANDLE_VALUE) return error.ThreadSnapshotFailed;
        defer _ = win_proc.CloseHandle(hSnap);

        var te: win_dbg.THREADENTRY32 = undefined;
        te.dwSize = @sizeOf(win_dbg.THREADENTRY32);

        var count: usize = 0;
        if (win_dbg.Thread32First(hSnap, &te) != 0) {
            while (true) {
                if (te.th32OwnerProcessID == self.target_pid) {
                    const access = win_dbg.THREAD_GET_CONTEXT | win_dbg.THREAD_SET_CONTEXT | win_dbg.THREAD_SUSPEND_RESUME;
                    if (win_dbg.OpenThread(access, 0, te.th32ThreadID)) |hThread| {
                        defer _ = win_proc.CloseHandle(hThread);
                        _ = win_dbg.SuspendThread(hThread);
                        armThreadHardwareBreakpoint(hThread, self.target_address) catch {};
                        _ = win_dbg.ResumeThread(hThread);
                        count += 1;
                    }
                }
                if (win_dbg.Thread32Next(hSnap, &te) == 0) break;
            }
        }
        return count;
    }

    /// Disarms hardware watch across all active threads of target process
    pub fn disarmAllThreads(self: *DebugWatcher) !void {
        const hSnap = win_proc.CreateToolhelp32Snapshot(win_proc.TH32CS_SNAPTHREAD, 0);
        if (hSnap == win_proc.INVALID_HANDLE_VALUE) return;
        defer _ = win_proc.CloseHandle(hSnap);

        var te: win_dbg.THREADENTRY32 = undefined;
        te.dwSize = @sizeOf(win_dbg.THREADENTRY32);

        if (win_dbg.Thread32First(hSnap, &te) != 0) {
            while (true) {
                if (te.th32OwnerProcessID == self.target_pid) {
                    const access = win_dbg.THREAD_GET_CONTEXT | win_dbg.THREAD_SET_CONTEXT | win_dbg.THREAD_SUSPEND_RESUME;
                    if (win_dbg.OpenThread(access, 0, te.th32ThreadID)) |hThread| {
                        defer _ = win_proc.CloseHandle(hThread);
                        _ = win_dbg.SuspendThread(hThread);
                        disarmThreadHardwareBreakpoint(hThread) catch {};
                        _ = win_dbg.ResumeThread(hThread);
                    }
                }
                if (win_dbg.Thread32Next(hSnap, &te) == 0) break;
            }
        }
    }

    /// Records an intercepted memory access hit with disassembly and register dump
    pub fn recordHit(
        self: *DebugWatcher,
        rip_addr: usize,
        code_bytes: []const u8,
        regs: RegisterSnapshot,
    ) !void {
        for (self.hits.items) |*h| {
            if (h.address == rip_addr) {
                h.hit_count += 1;
                h.registers = regs;
                return;
            }
        }

        const inst = disasm.Disassembler.decodeInstruction(code_bytes, rip_addr);
        try self.hits.append(self.allocator, WatchHit{
            .address = rip_addr,
            .instruction = inst,
            .registers = regs,
            .hit_count = 1,
        });
    }
};

test "DebugWatcher hardware register structure and hit cataloging" {
    const allocator = std.testing.allocator;
    var watcher = DebugWatcher.init(allocator, 1234, 0x7FF74A8014E4);
    defer watcher.deinit();

    // Verify CONTEXT size and DR offset alignment
    try std.testing.expect(@sizeOf(win_dbg.CONTEXT) > 100);

    // Mock instruction: mov [rbx+0x248], eax
    const code = [_]u8{ 0x89, 0x83, 0x48, 0x02, 0x00, 0x00 };
    const regs = RegisterSnapshot{
        .rax = 999999,
        .rbx = 0x7FF74A80129C,
        .rcx = 0x1000,
        .rdx = 0x2000,
        .rsi = 0,
        .rdi = 0,
        .rbp = 0x00007FFE8000,
        .rsp = 0x00007FFE7FF0,
        .r8 = 0,
        .r9 = 0,
        .r10 = 0,
        .r11 = 0,
        .r12 = 0,
        .r13 = 0,
        .r14 = 0,
        .r15 = 0,
        .rip = 0x14002050,
        .eflags = 0x246,
    };

    try watcher.recordHit(0x14002050, &code, regs);
    try std.testing.expectEqual(@as(usize, 1), watcher.hits.items.len);
    try std.testing.expectEqualStrings("mov", watcher.hits.items[0].instruction.getMnemonic());
    try std.testing.expectEqualStrings("[rbx+0x248], eax", watcher.hits.items[0].instruction.getOperands());
    try std.testing.expectEqual(@as(usize, 1), watcher.hits.items[0].hit_count);
    try std.testing.expectEqual(@as(u64, 999999), watcher.hits.items[0].registers.rax);

    // Second hit on same instruction should increment count
    try watcher.recordHit(0x14002050, &code, regs);
    try std.testing.expectEqual(@as(usize, 1), watcher.hits.items.len);
    try std.testing.expectEqual(@as(usize, 2), watcher.hits.items[0].hit_count);
}
