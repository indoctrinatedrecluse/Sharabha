const std = @import("std");
const process = @import("process.zig");

pub const ScanType = enum {
    ExactValue,
    IncreasedValue,
    DecreasedValue,
    ChangedValue,
    UnchangedValue,
    ValueBetween,
};

pub const DataType = enum {
    I8,
    U8,
    I16,
    U16,
    I32,
    U32,
    I64,
    U64,
    F32,
    F64,

    pub fn size(self: DataType) usize {
        return switch (self) {
            .I8, .U8 => 1,
            .I16, .U16 => 2,
            .I32, .U32, .F32 => 4,
            .I64, .U64, .F64 => 8,
        };
    }
};

pub const ScanTargetValue = union(DataType) {
    I8: i8,
    U8: u8,
    I16: i16,
    U16: u16,
    I32: i32,
    U32: u32,
    I64: i64,
    U64: u64,
    F32: f32,
    F64: f64,

    pub fn size(self: ScanTargetValue) usize {
        return switch (self) {
            .I8, .U8 => 1,
            .I16, .U16 => 2,
            .I32, .U32, .F32 => 4,
            .I64, .U64, .F64 => 8,
        };
    }

    pub fn matchesBytes(self: ScanTargetValue, bytes: []const u8) bool {
        switch (self) {
            .I8 => |val| {
                if (bytes.len < 1) return false;
                return @as(i8, @bitCast(bytes[0])) == val;
            },
            .U8 => |val| {
                if (bytes.len < 1) return false;
                return bytes[0] == val;
            },
            .I16 => |val| {
                if (bytes.len < 2) return false;
                return std.mem.readInt(i16, bytes[0..2], .little) == val;
            },
            .U16 => |val| {
                if (bytes.len < 2) return false;
                return std.mem.readInt(u16, bytes[0..2], .little) == val;
            },
            .I32 => |val| {
                if (bytes.len < 4) return false;
                const v = std.mem.readInt(i32, bytes[0..4], .little);
                return v == val;
            },
            .U32 => |val| {
                if (bytes.len < 4) return false;
                const v = std.mem.readInt(u32, bytes[0..4], .little);
                return v == val;
            },
            .I64 => |val| {
                if (bytes.len < 8) return false;
                const v = std.mem.readInt(i64, bytes[0..8], .little);
                return v == val;
            },
            .U64 => |val| {
                if (bytes.len < 8) return false;
                const v = std.mem.readInt(u64, bytes[0..8], .little);
                return v == val;
            },
            .F32 => |val| {
                if (bytes.len < 4) return false;
                const raw = std.mem.readInt(u32, bytes[0..4], .little);
                const v = @as(f32, @bitCast(raw));
                return @abs(v - val) < 0.0001;
            },
            .F64 => |val| {
                if (bytes.len < 8) return false;
                const raw = std.mem.readInt(u64, bytes[0..8], .little);
                const v = @as(f64, @bitCast(raw));
                return @abs(v - val) < 0.000001;
            },
        }
    }

    pub fn toI64(self: ScanTargetValue) i64 {
        return switch (self) {
            .I8 => |v| v,
            .U8 => |v| v,
            .I16 => |v| v,
            .U16 => |v| v,
            .I32 => |v| v,
            .U32 => |v| v,
            .I64 => |v| v,
            .U64 => |v| @as(i64, @intCast(@min(v, @as(u64, std.math.maxInt(i64))))),
            .F32 => |v| @intFromFloat(v),
            .F64 => |v| @intFromFloat(v),
        };
    }
};

const win = struct {
    pub const MEM_COMMIT: u32 = 0x1000;
    pub const PAGE_NOACCESS: u32 = 0x01;
    pub const PAGE_GUARD: u32 = 0x100;
    pub const PAGE_READWRITE: u32 = 0x04;
    pub const PAGE_WRITECOPY: u32 = 0x08;
    pub const PAGE_EXECUTE_READWRITE: u32 = 0x40;
    pub const PAGE_EXECUTE_WRITECOPY: u32 = 0x80;

    pub const MEMORY_BASIC_INFORMATION = extern struct {
        BaseAddress: ?*anyopaque,
        AllocationBase: ?*anyopaque,
        AllocationProtect: u32,
        PartitionId: u16,
        RegionSize: usize,
        State: u32,
        Protect: u32,
        Type: u32,
    };

    pub extern "kernel32" fn VirtualQueryEx(
        hProcess: process.win.HANDLE,
        lpAddress: ?*const anyopaque,
        lpBuffer: *MEMORY_BASIC_INFORMATION,
        dwLength: usize,
    ) callconv(.winapi) usize;
};

pub const MemoryRegion = struct {
    base_address: usize,
    size: usize,
    protect: u32,
};

pub const RegionIterator = struct {
    proc: *process.ProcessHandle,
    current_address: usize,

    pub fn init(proc: *process.ProcessHandle) RegionIterator {
        return RegionIterator{
            .proc = proc,
            .current_address = 0,
        };
    }

    pub fn next(self: *RegionIterator) ?MemoryRegion {
        var mbi: win.MEMORY_BASIC_INFORMATION = undefined;

        while (true) {
            const query_res = win.VirtualQueryEx(
                self.proc.handle,
                @ptrFromInt(self.current_address),
                &mbi,
                @sizeOf(win.MEMORY_BASIC_INFORMATION),
            );

            if (query_res == 0) return null;

            const base = @intFromPtr(mbi.BaseAddress);
            const size = mbi.RegionSize;
            self.current_address = base + size;

            const is_committed = (mbi.State & win.MEM_COMMIT) != 0;
            const is_guarded = (mbi.Protect & win.PAGE_GUARD) != 0;
            const is_noaccess = (mbi.Protect & win.PAGE_NOACCESS) != 0;
            const is_writable = (mbi.Protect & (win.PAGE_READWRITE | win.PAGE_WRITECOPY | win.PAGE_EXECUTE_READWRITE | win.PAGE_EXECUTE_WRITECOPY)) != 0;

            if (is_committed and !is_guarded and !is_noaccess and is_writable) {
                return MemoryRegion{
                    .base_address = base,
                    .size = size,
                    .protect = mbi.Protect,
                };
            }
        }
    }
};

pub const ScanResult = struct {
    address: usize,
    current_value: i64,
    previous_value: i64,
};

pub const MemoryScanner = struct {
    allocator: std.mem.Allocator,
    proc: *process.ProcessHandle,
    results: std.ArrayList(ScanResult),
    alignment: usize,

    pub fn init(allocator: std.mem.Allocator, proc: *process.ProcessHandle) MemoryScanner {
        return MemoryScanner{
            .allocator = allocator,
            .proc = proc,
            .results = .empty,
            .alignment = 4,
        };
    }

    pub fn deinit(self: *MemoryScanner) void {
        self.results.deinit(self.allocator);
    }

    pub fn setAlignment(self: *MemoryScanner, align_bytes: usize) void {
        self.alignment = if (align_bytes == 0) 1 else align_bytes;
    }

    /// First scan: searches all committed writable regions for `target`
    pub fn firstScan(self: *MemoryScanner, target: ScanTargetValue) !usize {
        self.results.clearRetainingCapacity();

        var reg_iter = RegionIterator.init(self.proc);
        const chunk_size = 64 * 1024; // 64 KB read buffer
        var buffer: [chunk_size]u8 = undefined;

        const val_size = target.size();

        while (reg_iter.next()) |region| {
            var offset: usize = 0;
            while (offset < region.size) {
                const to_read = @min(chunk_size, region.size - offset);
                const bytes_read = self.proc.readMemory(region.base_address + offset, buffer[0..to_read]) catch 0;
                if (bytes_read >= val_size) {
                    var i: usize = 0;
                    while (i + val_size <= bytes_read) : (i += self.alignment) {
                        if (target.matchesBytes(buffer[i .. i + val_size])) {
                            const addr = region.base_address + offset + i;
                            const val_i64: i64 = readValueToI64(buffer[i..], target);
                            try self.results.append(self.allocator, .{
                                .address = addr,
                                .current_value = val_i64,
                                .previous_value = val_i64,
                            });
                        }
                    }
                }
                offset += to_read;
            }
        }
        return self.results.items.len;
    }

    /// Searches for byte patterns / ASCII strings
    pub fn firstScanPattern(self: *MemoryScanner, pattern: []const u8) !usize {
        self.results.clearRetainingCapacity();
        if (pattern.len == 0) return 0;

        var reg_iter = RegionIterator.init(self.proc);
        const chunk_size = 64 * 1024;
        var buffer: [chunk_size]u8 = undefined;

        while (reg_iter.next()) |region| {
            var offset: usize = 0;
            while (offset < region.size) {
                const to_read = @min(chunk_size, region.size - offset);
                const bytes_read = self.proc.readMemory(region.base_address + offset, buffer[0..to_read]) catch 0;
                if (bytes_read >= pattern.len) {
                    var i: usize = 0;
                    while (i + pattern.len <= bytes_read) : (i += 1) {
                        if (std.mem.eql(u8, buffer[i .. i + pattern.len], pattern)) {
                            const addr = region.base_address + offset + i;
                            try self.results.append(self.allocator, .{
                                .address = addr,
                                .current_value = @intCast(pattern.len),
                                .previous_value = @intCast(pattern.len),
                            });
                        }
                    }
                }
                offset += to_read;
            }
        }
        return self.results.items.len;
    }

    /// Next scan / filter: re-reads only previously matched addresses for an exact value
    pub fn nextScanExact(self: *MemoryScanner, target: ScanTargetValue) !usize {
        var keep_idx: usize = 0;
        var buf: [8]u8 = undefined;
        const val_size = target.size();

        for (self.results.items) |entry| {
            const bytes_read = self.proc.readMemory(entry.address, buf[0..val_size]) catch 0;
            if (bytes_read == val_size and target.matchesBytes(buf[0..val_size])) {
                self.results.items[keep_idx] = .{
                    .address = entry.address,
                    .current_value = readValueToI64(buf[0..val_size], target),
                    .previous_value = entry.current_value,
                };
                keep_idx += 1;
            }
        }

        self.results.shrinkRetainingCapacity(keep_idx);
        return keep_idx;
    }

    /// Differential next scan: filter by Increased, Decreased, Changed, or Unchanged
    pub fn nextScanDifferential(self: *MemoryScanner, scan_type: ScanType, data_type: DataType) !usize {
        var keep_idx: usize = 0;
        var buf: [8]u8 = undefined;
        const val_size = data_type.size();

        for (self.results.items) |entry| {
            const bytes_read = self.proc.readMemory(entry.address, buf[0..val_size]) catch 0;
            if (bytes_read == val_size) {
                const cur_val = readRawToI64(buf[0..val_size], data_type);
                const prev_val = entry.current_value;

                const keep = switch (scan_type) {
                    .IncreasedValue => cur_val > prev_val,
                    .DecreasedValue => cur_val < prev_val,
                    .ChangedValue => cur_val != prev_val,
                    .UnchangedValue => cur_val == prev_val,
                    else => false,
                };

                if (keep) {
                    self.results.items[keep_idx] = .{
                        .address = entry.address,
                        .current_value = cur_val,
                        .previous_value = prev_val,
                    };
                    keep_idx += 1;
                }
            }
        }

        self.results.shrinkRetainingCapacity(keep_idx);
        return keep_idx;
    }

    fn readValueToI64(bytes: []const u8, target: ScanTargetValue) i64 {
        return switch (target) {
            .I8 => @as(i8, @bitCast(bytes[0])),
            .U8 => bytes[0],
            .I16 => std.mem.readInt(i16, bytes[0..2], .little),
            .U16 => std.mem.readInt(u16, bytes[0..2], .little),
            .I32 => std.mem.readInt(i32, bytes[0..4], .little),
            .U32 => std.mem.readInt(u32, bytes[0..4], .little),
            .I64 => std.mem.readInt(i64, bytes[0..8], .little),
            .U64 => @as(i64, @intCast(@min(std.mem.readInt(u64, bytes[0..8], .little), @as(u64, std.math.maxInt(i64))))),
            .F32 => @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little)))),
            .F64 => @intFromFloat(@as(f64, @bitCast(std.mem.readInt(u64, bytes[0..8], .little)))),
        };
    }

    fn readRawToI64(bytes: []const u8, data_type: DataType) i64 {
        return switch (data_type) {
            .I8 => @as(i8, @bitCast(bytes[0])),
            .U8 => bytes[0],
            .I16 => std.mem.readInt(i16, bytes[0..2], .little),
            .U16 => std.mem.readInt(u16, bytes[0..2], .little),
            .I32 => std.mem.readInt(i32, bytes[0..4], .little),
            .U32 => std.mem.readInt(u32, bytes[0..4], .little),
            .I64 => std.mem.readInt(i64, bytes[0..8], .little),
            .U64 => @as(i64, @intCast(@min(std.mem.readInt(u64, bytes[0..8], .little), @as(u64, std.math.maxInt(i64))))),
            .F32 => @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little)))),
            .F64 => @intFromFloat(@as(f64, @bitCast(std.mem.readInt(u64, bytes[0..8], .little)))),
        };
    }
};

test "ScanTargetValue matches" {
    const val: i32 = 42;
    const target = ScanTargetValue{ .I32 = val };
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, 42, .little);
    try std.testing.expect(target.matchesBytes(&buf));

    std.mem.writeInt(i32, &buf, 43, .little);
    try std.testing.expect(!target.matchesBytes(&buf));
}

test "MemoryScanner real scan, refine, and write on self process" {
    const allocator = std.testing.allocator;
    const pid = process.win.GetCurrentProcessId();
    var proc = try process.ProcessHandle.open(pid);
    defer proc.close();

    var target_val: i32 = 888777;
    const target_addr = @intFromPtr(&target_val);

    var scanner = MemoryScanner.init(allocator, &proc);
    defer scanner.deinit();

    // 1. First scan for 888777
    const count = try scanner.firstScan(ScanTargetValue{ .I32 = 888777 });
    try std.testing.expect(count > 0);

    // Verify target_addr was discovered in virtual memory
    var found = false;
    for (scanner.results.items) |r| {
        if (r.address == target_addr) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);

    // 2. Refine scan (Next Scan Exact) after value changes
    target_val = 888778;
    const refined_count = try scanner.nextScanExact(ScanTargetValue{ .I32 = 888778 });
    try std.testing.expect(refined_count > 0);
    try std.testing.expect(refined_count <= count);

    var found_refined = false;
    for (scanner.results.items) |r| {
        if (r.address == target_addr) {
            found_refined = true;
            break;
        }
    }
    try std.testing.expect(found_refined);

    // 3. Differential scan (IncreasedValue)
    target_val = 888790;
    const inc_count = try scanner.nextScanDifferential(.IncreasedValue, .I32);
    try std.testing.expect(inc_count > 0);

    // 4. Write memory test: mutate variable via Win32 WriteProcessMemory
    const new_val: i32 = 999111;
    _ = try proc.writeMemory(target_addr, std.mem.asBytes(&new_val));
    try std.testing.expectEqual(@as(i32, 999111), target_val);
}
