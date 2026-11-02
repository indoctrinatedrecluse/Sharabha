const std = @import("std");
const win = @import("process.zig").win;

pub const SRWLOCK = extern struct {
    ptr: ?*anyopaque = null,
};
pub extern "kernel32" fn AcquireSRWLockExclusive(SRWLock: *SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn ReleaseSRWLockExclusive(SRWLock: *SRWLOCK) callconv(.winapi) void;

pub const FrozenEntry = struct {
    address: usize,
    value: [8]u8,
    size: usize,
    active: bool,
    description: [64]u8,
    desc_len: usize,

    pub fn getDescription(self: *const FrozenEntry) []const u8 {
        return self.description[0..self.desc_len];
    }
};

/// Stambhana Goraksha (स्तम्भन गोरक्ष) — Active Memory Freeze Engine
/// Runs a dedicated background sentinel thread to repeatedly enforce locked memory states
/// against in-game reduction or reset loops.
pub const FreezeManager = struct {
    allocator: std.mem.Allocator,
    process_handle: ?win.HANDLE,
    entries: std.ArrayList(FrozenEntry),
    lock: SRWLOCK,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,
    interval_ms: u32,

    pub fn init(allocator: std.mem.Allocator, interval_ms: u32) FreezeManager {
        return FreezeManager{
            .allocator = allocator,
            .process_handle = null,
            .entries = .empty,
            .lock = .{},
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
            .interval_ms = if (interval_ms == 0) 40 else interval_ms,
        };
    }

    pub fn deinit(self: *FreezeManager) void {
        self.stop();
        self.entries.deinit(self.allocator);
    }

    pub fn attach(self: *FreezeManager, hProcess: win.HANDLE) void {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);
        self.process_handle = hProcess;
    }

    pub fn detach(self: *FreezeManager) void {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);
        self.process_handle = null;
    }

    pub fn start(self: *FreezeManager) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, sentinelLoop, .{self});
    }

    pub fn stop(self: *FreezeManager) void {
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    pub fn addOrUpdate(self: *FreezeManager, address: usize, value_slice: []const u8, desc: []const u8) !void {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);

        const capped_size = @min(value_slice.len, 8);
        var buf: [8]u8 = @splat(0);
        @memcpy(buf[0..capped_size], value_slice[0..capped_size]);

        var desc_buf: [64]u8 = @splat(0);
        const capped_desc_len = @min(desc.len, 64);
        @memcpy(desc_buf[0..capped_desc_len], desc[0..capped_desc_len]);

        for (self.entries.items) |*e| {
            if (e.address == address) {
                e.value = buf;
                e.size = capped_size;
                e.active = true;
                e.description = desc_buf;
                e.desc_len = capped_desc_len;
                return;
            }
        }

        try self.entries.append(self.allocator, FrozenEntry{
            .address = address,
            .value = buf,
            .size = capped_size,
            .active = true,
            .description = desc_buf,
            .desc_len = capped_desc_len,
        });
    }

    pub fn remove(self: *FreezeManager, address: usize) void {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);

        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].address == address) {
                _ = self.entries.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn toggle(self: *FreezeManager, address: usize) bool {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);

        for (self.entries.items) |*e| {
            if (e.address == address) {
                e.active = !e.active;
                return e.active;
            }
        }
        return false;
    }

    pub fn getActiveCount(self: *FreezeManager) usize {
        AcquireSRWLockExclusive(&self.lock);
        defer ReleaseSRWLockExclusive(&self.lock);

        var count: usize = 0;
        for (self.entries.items) |e| {
            if (e.active) count += 1;
        }
        return count;
    }

    fn sentinelLoop(self: *FreezeManager) void {
        while (self.running.load(.acquire)) {
            {
                AcquireSRWLockExclusive(&self.lock);
                defer ReleaseSRWLockExclusive(&self.lock);

                if (self.process_handle) |hProc| {
                    for (self.entries.items) |entry| {
                        if (!entry.active) continue;
                        var bytes_written: usize = 0;
                        _ = win.WriteProcessMemory(
                            hProc,
                            @ptrFromInt(entry.address),
                            &entry.value,
                            entry.size,
                            &bytes_written,
                        );
                    }
                }
            }

            std.Thread.sleep(@as(u64, self.interval_ms) * std.time.ns_per_ms);
        }
    }
};

/// Stambhana Daemon Sentinel (स्तम्भन गोरक्ष दूत)
/// Persistent background worker loop that watches assets/memory/frozen_entries.txt
/// and repeatedly enforces locks into the target Win32 process every 30-40ms.
pub const FreezeDaemon = struct {
    allocator: std.mem.Allocator,
    manager: FreezeManager,
    current_pid: ?u32,
    interval_ms: u32,
    empty_streak: usize,

    pub fn init(allocator: std.mem.Allocator, interval_ms: u32) FreezeDaemon {
        return FreezeDaemon{
            .allocator = allocator,
            .manager = FreezeManager.init(allocator, interval_ms),
            .current_pid = null,
            .interval_ms = if (interval_ms == 0) 35 else interval_ms,
            .empty_streak = 0,
        };
    }

    pub fn deinit(self: *FreezeDaemon) void {
        self.manager.deinit();
    }

    pub fn syncFromEntries(self: *FreezeDaemon, entries_text: []const u8) !usize {
        AcquireSRWLockExclusive(&self.manager.lock);
        defer ReleaseSRWLockExclusive(&self.manager.lock);

        self.manager.entries.clearRetainingCapacity();

        var line_iter = std.mem.tokenizeAny(u8, entries_text, "\r\n");
        var active_count: usize = 0;

        while (line_iter.next()) |line| {
            var parts = std.mem.tokenizeAny(u8, line, " \t");
            const addr_str = parts.next() orelse continue;
            const val_str = parts.next() orelse continue;
            const type_str = parts.next() orelse "i32";

            var clean_addr = std.mem.trim(u8, addr_str, " \t\r\n");
            if (std.mem.startsWith(u8, clean_addr, "0x") or std.mem.startsWith(u8, clean_addr, "0X")) {
                clean_addr = clean_addr[2..];
            }
            const address = std.fmt.parseInt(usize, clean_addr, 16) catch continue;

            var val_bytes: [8]u8 = @splat(0);
            var val_size: usize = 4;

            if (std.ascii.eqlIgnoreCase(type_str, "i8")) {
                const v = std.fmt.parseInt(i8, val_str, 0) catch 0;
                val_bytes[0] = @bitCast(v);
                val_size = 1;
            } else if (std.ascii.eqlIgnoreCase(type_str, "u8")) {
                const v = std.fmt.parseInt(u8, val_str, 0) catch 0;
                val_bytes[0] = v;
                val_size = 1;
            } else if (std.ascii.eqlIgnoreCase(type_str, "i16")) {
                const v = std.fmt.parseInt(i16, val_str, 0) catch 0;
                std.mem.writeInt(i16, val_bytes[0..2], v, .little);
                val_size = 2;
            } else if (std.ascii.eqlIgnoreCase(type_str, "u16")) {
                const v = std.fmt.parseInt(u16, val_str, 0) catch 0;
                std.mem.writeInt(u16, val_bytes[0..2], v, .little);
                val_size = 2;
            } else if (std.ascii.eqlIgnoreCase(type_str, "i64")) {
                const v = std.fmt.parseInt(i64, val_str, 0) catch 0;
                std.mem.writeInt(i64, val_bytes[0..8], v, .little);
                val_size = 8;
            } else if (std.ascii.eqlIgnoreCase(type_str, "u64")) {
                const v = std.fmt.parseInt(u64, val_str, 0) catch 0;
                std.mem.writeInt(u64, val_bytes[0..8], v, .little);
                val_size = 8;
            } else if (std.ascii.eqlIgnoreCase(type_str, "f32")) {
                const v = std.fmt.parseFloat(f32, val_str) catch 0;
                const raw: u32 = @bitCast(v);
                std.mem.writeInt(u32, val_bytes[0..4], raw, .little);
                val_size = 4;
            } else if (std.ascii.eqlIgnoreCase(type_str, "f64")) {
                const v = std.fmt.parseFloat(f64, val_str) catch 0;
                const raw: u64 = @bitCast(v);
                std.mem.writeInt(u64, val_bytes[0..8], raw, .little);
                val_size = 8;
            } else {
                // Default i32 / u32
                const v = std.fmt.parseInt(i32, val_str, 0) catch 0;
                std.mem.writeInt(i32, val_bytes[0..4], v, .little);
                val_size = 4;
            }

            var desc_buf: [64]u8 = @splat(0);
            const desc = parts.rest();
            const desc_len = @min(desc.len, 64);
            @memcpy(desc_buf[0..desc_len], desc[0..desc_len]);

            try self.manager.entries.append(self.allocator, FrozenEntry{
                .address = address,
                .value = val_bytes,
                .size = val_size,
                .active = true,
                .description = desc_buf,
                .desc_len = desc_len,
            });
            active_count += 1;
        }

        return active_count;
    }

    /// Enforces a single cycle of WriteProcessMemory across all active entries
    pub fn enforceOnce(self: *FreezeDaemon) usize {
        AcquireSRWLockExclusive(&self.manager.lock);
        defer ReleaseSRWLockExclusive(&self.manager.lock);

        var written_count: usize = 0;
        if (self.manager.process_handle) |hProc| {
            for (self.manager.entries.items) |entry| {
                if (!entry.active) continue;
                var bytes_written: usize = 0;
                const ok = win.WriteProcessMemory(
                    hProc,
                    @ptrFromInt(entry.address),
                    &entry.value,
                    entry.size,
                    &bytes_written,
                );
                if (ok != 0 and bytes_written == entry.size) {
                    written_count += 1;
                }
            }
        }
        return written_count;
    }
};

test "FreezeManager lifecycle and activation" {
    const allocator = std.testing.allocator;
    var manager = FreezeManager.init(allocator, 10);
    defer manager.deinit();

    const val: i32 = 77777;
    const val_bytes = std.mem.asBytes(&val);

    try manager.addOrUpdate(0x00400000, val_bytes, "GOLD_LOCK");
    try std.testing.expectEqual(@as(usize, 1), manager.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), manager.getActiveCount());

    const toggled = manager.toggle(0x00400000);
    try std.testing.expect(!toggled);
    try std.testing.expectEqual(@as(usize, 0), manager.getActiveCount());

    const re_toggled = manager.toggle(0x00400000);
    try std.testing.expect(re_toggled);
    try std.testing.expectEqual(@as(usize, 1), manager.getActiveCount());

    manager.remove(0x00400000);
    try std.testing.expectEqual(@as(usize, 0), manager.entries.items.len);
}

test "FreezeDaemon entries synchronization and type parsing" {
    const allocator = std.testing.allocator;
    var daemon = FreezeDaemon.init(allocator, 20);
    defer daemon.deinit();

    const sample_entries =
        \\0x00501000 999999 i32 Player_Health
        \\0x00501010 450.5 f32 Movement_Speed
        \\0x00501020 120 u8 Staged_Level
    ;

    const count = try daemon.syncFromEntries(sample_entries);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(usize, 3), daemon.manager.entries.items.len);

    const e0 = daemon.manager.entries.items[0];
    try std.testing.expectEqual(@as(usize, 0x00501000), e0.address);
    try std.testing.expectEqual(@as(usize, 4), e0.size);
    try std.testing.expectEqual(@as(i32, 999999), std.mem.readInt(i32, e0.value[0..4], .little));

    const e1 = daemon.manager.entries.items[1];
    try std.testing.expectEqual(@as(usize, 0x00501010), e1.address);
    try std.testing.expectEqual(@as(usize, 4), e1.size);
    const parsed_f32: f32 = @bitCast(std.mem.readInt(u32, e1.value[0..4], .little));
    try std.testing.expect(@abs(parsed_f32 - 450.5) < 0.01);

    const e2 = daemon.manager.entries.items[2];
    try std.testing.expectEqual(@as(usize, 0x00501020), e2.address);
    try std.testing.expectEqual(@as(usize, 1), e2.size);
    try std.testing.expectEqual(@as(u8, 120), e2.value[0]);
}
