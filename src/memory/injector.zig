//! ============================================================================
//! SHARABHA (शरभ) — PASHA BANDHANA & GUHA STHAPANA (INJECTOR & CODE CAVE DETOURS)
//! Native Win32 DLL injection via CreateRemoteThread and 64-bit absolute code cave detours.
//!
//! ॐ नमः शरभाय — Subduing the process through binding and redirection.
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const win = process.win;

pub const PashaBandhana = struct {
    pub const InquestError = error{
        ProcessAccessDenied,
        RemoteAllocationFailed,
        RemoteWriteFailed,
        ModuleNotFound,
        CreateRemoteThreadFailed,
        RemoteThreadTimeout,
        DllLoadFailed,
        MemoryProtectionFailed,
        StolenLengthTooSmall,
        InvalidTargetAddress,
        CaveAllocationFailed,
    };

    /// 64-bit absolute jump: FF 25 00 00 00 00 <8-byte target address>
    /// Indirect RIP-relative JMP [RIP+0] executing jump to immediately following 64-bit destination.
    pub const ABSOLUTE_JMP64_SIZE: usize = 14;

    /// Formats a 14-byte 64-bit absolute jump into the given slice.
    pub fn encodeAbsoluteJmp64(out_buf: *[ABSOLUTE_JMP64_SIZE]u8, destination_addr: usize) void {
        out_buf[0] = 0xFF;
        out_buf[1] = 0x25;
        out_buf[2] = 0x00;
        out_buf[3] = 0x00;
        out_buf[4] = 0x00;
        out_buf[5] = 0x00;
        std.mem.writeInt(u64, out_buf[6..14], destination_addr, .little);
    }

    /// Pasha Bandhana (पाश बन्धन — Thread Binding):
    /// Injects a native dynamic link library (DLL) into a remote target process using CreateRemoteThread.
    /// Returns the remote HMODULE base address on success.
    pub fn injectDll(
        hProcess: win.HANDLE,
        dll_path_utf8: []const u8,
        timeout_ms: u32,
        allocator: std.mem.Allocator,
    ) InquestError!usize {
        // 1. Convert UTF-8 path to UTF-16LE with null-terminator
        const dll_path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, dll_path_utf8) catch return error.RemoteAllocationFailed;
        defer allocator.free(dll_path_w);

        const path_byte_size = (dll_path_w.len + 1) * @sizeOf(u16);

        // 2. Allocate memory in the remote target process
        const remote_buf = win.VirtualAllocEx(
            hProcess,
            null,
            path_byte_size,
            win.MEM_COMMIT | win.MEM_RESERVE,
            win.PAGE_READWRITE,
        ) orelse return error.RemoteAllocationFailed;
        errdefer _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);

        // 3. Write DLL path into remote process memory
        var bytes_written: usize = 0;
        const write_ok = win.WriteProcessMemory(
            hProcess,
            remote_buf,
            dll_path_w.ptr,
            path_byte_size,
            &bytes_written,
        );
        if (write_ok == 0 or bytes_written != path_byte_size) {
            _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);
            return error.RemoteWriteFailed;
        }

        // 4. Resolve LoadLibraryW in kernel32.dll
        const k32_name_w = std.unicode.utf8ToUtf16LeStringLiteral("kernel32.dll");
        const hKernel32 = win.GetModuleHandleW(k32_name_w) orelse {
            _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);
            return error.ModuleNotFound;
        };

        const load_lib_proc = win.GetProcAddress(hKernel32, "LoadLibraryW") orelse {
            _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);
            return error.ModuleNotFound;
        };

        // 5. Spawn remote thread executing LoadLibraryW(remote_buf)
        var thread_id: u32 = 0;
        const hThread = win.CreateRemoteThread(
            hProcess,
            null,
            0,
            load_lib_proc,
            remote_buf,
            0,
            &thread_id,
        ) orelse {
            _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);
            return error.CreateRemoteThreadFailed;
        };
        defer _ = win.CloseHandle(hThread);

        // 6. Wait for thread execution to finish
        const wait_res = win.WaitForSingleObject(hThread, timeout_ms);
        if (wait_res == win.WAIT_TIMEOUT) {
            _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);
            return error.RemoteThreadTimeout;
        }

        // 7. Retrieve exit code (the loaded remote HMODULE)
        var exit_code: u32 = 0;
        const exit_ok = win.GetExitCodeThread(hThread, &exit_code);

        // Free the remote parameter buffer
        _ = win.VirtualFreeEx(hProcess, remote_buf, 0, win.MEM_RELEASE);

        if (exit_ok == 0 or exit_code == 0) {
            return error.DllLoadFailed;
        }

        return @as(usize, exit_code);
    }

    /// Allocates an executable memory region in the target process for custom code caves.
    pub fn allocateCodeCave(hProcess: win.HANDLE, size: usize, protect: u32) InquestError!usize {
        const ptr = win.VirtualAllocEx(
            hProcess,
            null,
            size,
            win.MEM_COMMIT | win.MEM_RESERVE,
            protect,
        ) orelse return error.CaveAllocationFailed;

        return @intFromPtr(ptr);
    }

    /// Releases a previously allocated remote code cave.
    pub fn freeCodeCave(hProcess: win.HANDLE, cave_addr: usize) void {
        _ = win.VirtualFreeEx(
            hProcess,
            @as(?*anyopaque, @ptrFromInt(cave_addr)),
            0,
            win.MEM_RELEASE,
        );
    }

    /// Guha Sthapana (गुहा स्थापन — Code Cave Detour Hook):
    /// Structure holding metadata for an installed inline detour hook.
    pub const DetourHook = struct {
        target_addr: usize,
        cave_addr: usize,
        cave_size: usize,
        stolen_bytes: [32]u8,
        stolen_len: usize,
        original_protect: u32,
        is_installed: bool,

        /// Removes the detour hook, restoring the original instructions and freeing the code cave.
        pub fn remove(self: *DetourHook, hProcess: win.HANDLE) InquestError!void {
            if (!self.is_installed) return;

            var old_protect: u32 = 0;
            if (win.VirtualProtectEx(
                hProcess,
                @as(?*anyopaque, @ptrFromInt(self.target_addr)),
                self.stolen_len,
                win.PAGE_EXECUTE_READWRITE,
                &old_protect,
            ) == 0) {
                return error.MemoryProtectionFailed;
            }

            var bytes_written: usize = 0;
            _ = win.WriteProcessMemory(
                hProcess,
                @as(?*anyopaque, @ptrFromInt(self.target_addr)),
                &self.stolen_bytes,
                self.stolen_len,
                &bytes_written,
            );

            var dummy: u32 = 0;
            _ = win.VirtualProtectEx(
                hProcess,
                @as(?*anyopaque, @ptrFromInt(self.target_addr)),
                self.stolen_len,
                self.original_protect,
                &dummy,
            );

            freeCodeCave(hProcess, self.cave_addr);
            self.is_installed = false;
        }
    };

    /// Installs a 64-bit absolute detour hook at `target_addr`.
    /// 1. Reads `stolen_len` original bytes (must be >= 14 bytes).
    /// 2. Allocates a remote executable code cave.
    /// 3. Assembles the cave: `payload` + `stolen_bytes` + `JMP (target_addr + stolen_len)`.
    /// 4. Patches `target_addr` with `JMP cave_addr` + NOP padding.
    pub fn installDetour(
        hProcess: win.HANDLE,
        target_addr: usize,
        payload: []const u8,
        stolen_len: usize,
        allocator: std.mem.Allocator,
    ) InquestError!DetourHook {
        if (stolen_len < ABSOLUTE_JMP64_SIZE or stolen_len > 32) {
            return error.StolenLengthTooSmall;
        }

        var hook = DetourHook{
            .target_addr = target_addr,
            .cave_addr = 0,
            .cave_size = 0,
            .stolen_bytes = @splat(0),
            .stolen_len = stolen_len,
            .original_protect = 0,
            .is_installed = false,
        };

        // 1. Read the original instructions (stolen bytes)
        var bytes_read: usize = 0;
        if (win.ReadProcessMemory(
            hProcess,
            @as(?*const anyopaque, @ptrFromInt(target_addr)),
            &hook.stolen_bytes,
            stolen_len,
            &bytes_read,
        ) == 0 or bytes_read != stolen_len) {
            return error.RemoteAllocationFailed;
        }

        // 2. Allocate the code cave: payload + stolen_bytes + 14-byte return jump
        const total_cave_size = payload.len + stolen_len + ABSOLUTE_JMP64_SIZE;
        hook.cave_size = total_cave_size;
        hook.cave_addr = try allocateCodeCave(hProcess, total_cave_size, win.PAGE_EXECUTE_READWRITE);
        errdefer freeCodeCave(hProcess, hook.cave_addr);

        // 3. Assemble cave buffer
        const cave_buf = allocator.alloc(u8, total_cave_size) catch return error.RemoteAllocationFailed;
        defer allocator.free(cave_buf);

        // [a] Copy user payload (shellcode / mutation)
        if (payload.len > 0) {
            @memcpy(cave_buf[0..payload.len], payload);
        }

        // [b] Copy stolen instructions
        @memcpy(cave_buf[payload.len .. payload.len + stolen_len], hook.stolen_bytes[0..stolen_len]);

        // [c] Copy return jump back to (target_addr + stolen_len)
        var return_jmp: [ABSOLUTE_JMP64_SIZE]u8 = undefined;
        encodeAbsoluteJmp64(&return_jmp, target_addr + stolen_len);
        @memcpy(cave_buf[payload.len + stolen_len .. total_cave_size], &return_jmp);

        // Write assembled cave buffer to remote cave address
        var written: usize = 0;
        if (win.WriteProcessMemory(
            hProcess,
            @as(?*anyopaque, @ptrFromInt(hook.cave_addr)),
            cave_buf.ptr,
            total_cave_size,
            &written,
        ) == 0 or written != total_cave_size) {
            return error.RemoteWriteFailed;
        }

        // 4. Patch target function with 14-byte absolute jump to cave + NOP padding
        if (win.VirtualProtectEx(
            hProcess,
            @as(?*anyopaque, @ptrFromInt(target_addr)),
            stolen_len,
            win.PAGE_EXECUTE_READWRITE,
            &hook.original_protect,
        ) == 0) {
            return error.MemoryProtectionFailed;
        }

        var patch_buf: [32]u8 = undefined;
        encodeAbsoluteJmp64(patch_buf[0..ABSOLUTE_JMP64_SIZE], hook.cave_addr);

        // Fill remaining stolen bytes with NOP (0x90)
        var i: usize = ABSOLUTE_JMP64_SIZE;
        while (i < stolen_len) : (i += 1) {
            patch_buf[i] = 0x90;
        }

        var patch_written: usize = 0;
        if (win.WriteProcessMemory(
            hProcess,
            @as(?*anyopaque, @ptrFromInt(target_addr)),
            &patch_buf,
            stolen_len,
            &patch_written,
        ) == 0 or patch_written != stolen_len) {
            // Attempt restoring original protection
            var dummy: u32 = 0;
            _ = win.VirtualProtectEx(
                hProcess,
                @as(?*anyopaque, @ptrFromInt(target_addr)),
                stolen_len,
                hook.original_protect,
                &dummy,
            );
            return error.RemoteWriteFailed;
        }

        // 5. Restore target page protection
        var restored_protect: u32 = 0;
        _ = win.VirtualProtectEx(
            hProcess,
            @as(?*anyopaque, @ptrFromInt(target_addr)),
            stolen_len,
            hook.original_protect,
            &restored_protect,
        );

        hook.is_installed = true;
        return hook;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "Absolute 64-bit jump encoding" {
    var jmp_buf: [14]u8 = undefined;
    const dest: usize = 0x7FF7BADC0FFE;

    PashaBandhana.encodeAbsoluteJmp64(&jmp_buf, dest);

    // Verify JMP [RIP+0] opcode: FF 25 00 00 00 00
    try std.testing.expectEqual(@as(u8, 0xFF), jmp_buf[0]);
    try std.testing.expectEqual(@as(u8, 0x25), jmp_buf[1]);
    try std.testing.expectEqual(@as(u8, 0x00), jmp_buf[2]);
    try std.testing.expectEqual(@as(u8, 0x00), jmp_buf[3]);
    try std.testing.expectEqual(@as(u8, 0x00), jmp_buf[4]);
    try std.testing.expectEqual(@as(u8, 0x00), jmp_buf[5]);

    // Verify destination address little-endian encoding
    const encoded_dest = std.mem.readInt(u64, jmp_buf[6..14], .little);
    try std.testing.expectEqual(@as(u64, dest), encoded_dest);
}

test "Remote code cave allocation and free on self-process" {
    var cur_proc = try process.ProcessHandle.open(win.GetCurrentProcessId());
    defer cur_proc.close();

    const cave_size = 64;
    const cave_addr = try PashaBandhana.allocateCodeCave(cur_proc.handle, cave_size, win.PAGE_EXECUTE_READWRITE);
    try std.testing.expect(cave_addr != 0);

    // Write a NOP sled into the cave
    const nops: [16]u8 = @splat(0x90);
    var written: usize = 0;
    const ok = win.WriteProcessMemory(
        cur_proc.handle,
        @as(?*anyopaque, @ptrFromInt(cave_addr)),
        &nops,
        nops.len,
        &written,
    );
    try std.testing.expect(ok != 0);
    try std.testing.expectEqual(@as(usize, 16), written);

    // Free the code cave
    PashaBandhana.freeCodeCave(cur_proc.handle, cave_addr);
}

test "Detour hook installation and clean restoration" {
    var cur_proc = try process.ProcessHandle.open(win.GetCurrentProcessId());
    defer cur_proc.close();

    // Prepare a mock function buffer in readable/writable/executable memory
    const mock_code_size = 32;
    const mock_addr = try PashaBandhana.allocateCodeCave(cur_proc.handle, mock_code_size, win.PAGE_EXECUTE_READWRITE);
    defer PashaBandhana.freeCodeCave(cur_proc.handle, mock_addr);

    // Initialize mock function with 16 NOPs (0x90) followed by RET (0xC3)
    var initial_code: [mock_code_size]u8 = @splat(0x90);
    initial_code[16] = 0xC3;
    var written: usize = 0;
    _ = win.WriteProcessMemory(
        cur_proc.handle,
        @as(?*anyopaque, @ptrFromInt(mock_addr)),
        &initial_code,
        mock_code_size,
        &written,
    );

    // Install Detour with 16 stolen bytes and 4-byte payload
    const payload = [_]u8{ 0x48, 0x31, 0xC0, 0x90 }; // xor rax, rax; nop
    var hook = try PashaBandhana.installDetour(
        cur_proc.handle,
        mock_addr,
        &payload,
        16,
        std.testing.allocator,
    );
    try std.testing.expect(hook.is_installed);
    try std.testing.expect(hook.cave_addr != 0);

    // Verify target address was patched with 14-byte jump + 2 NOPs
    var patched_bytes: [16]u8 = undefined;
    var br: usize = 0;
    _ = win.ReadProcessMemory(
        cur_proc.handle,
        @as(?*const anyopaque, @ptrFromInt(mock_addr)),
        &patched_bytes,
        16,
        &br,
    );
    try std.testing.expectEqual(@as(u8, 0xFF), patched_bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x25), patched_bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x90), patched_bytes[14]);
    try std.testing.expectEqual(@as(u8, 0x90), patched_bytes[15]);

    // Remove the detour hook
    try hook.remove(cur_proc.handle);
    try std.testing.expect(!hook.is_installed);

    // Verify target address was restored to 16 original NOPs
    var restored_bytes: [16]u8 = undefined;
    _ = win.ReadProcessMemory(
        cur_proc.handle,
        @as(?*const anyopaque, @ptrFromInt(mock_addr)),
        &restored_bytes,
        16,
        &br,
    );
    for (restored_bytes) |b| {
        try std.testing.expectEqual(@as(u8, 0x90), b);
    }
}
