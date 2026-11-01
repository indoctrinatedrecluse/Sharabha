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
