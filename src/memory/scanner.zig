const std = @import("std");
const process = @import("process.zig");

pub const ScanType = enum {
    ExactValue,
    IncreasedValue,
    DecreasedValue,
    ChangedValue,
    UnchangedValue,
};

pub const DataType = enum {
    I32,
    U32,
    I64,
    U64,
    F32,
    F64,

    pub fn size(self: DataType) usize {
        return switch (self) {
            .I32, .U32, .F32 => 4,
            .I64, .U64, .F64 => 8,
        };
    }
};

pub const ScanTargetValue = union(DataType) {
    I32: i32,
    U32: u32,
    I64: i64,
    U64: u64,
    F32: f32,
    F64: f64,

    pub fn size(self: ScanTargetValue) usize {
        return switch (self) {
            .I32, .U32, .F32 => 4,
            .I64, .U64, .F64 => 8,
        };
    }

    pub fn matchesBytes(self: ScanTargetValue, bytes: []const u8) bool {
        switch (self) {
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
    is_writable: bool,

    pub fn isScannable(self: *const MemoryRegion) bool {
        return self.is_writable and self.size > 0;
    }
};

pub const RegionIterator = struct {
    process_handle: *const process.ProcessHandle,
    current_address: usize,

    pub fn init(proc: *const process.ProcessHandle) RegionIterator {
        return .{
            .process_handle = proc,
            .current_address = 0,
        };
    }

    pub fn next(self: *RegionIterator) ?MemoryRegion {
        var mbi: win.MEMORY_BASIC_INFORMATION = undefined;
        while (self.current_address < 0x7FFF_FFFF_FFFF) {
            const ptr: ?*const anyopaque = @ptrFromInt(self.current_address);
            const res = win.VirtualQueryEx(
                self.process_handle.handle,
                ptr,
                &mbi,
                @sizeOf(win.MEMORY_BASIC_INFORMATION),
            );

            if (res == 0) break;

            const base: usize = @intFromPtr(mbi.BaseAddress);
            const size = mbi.RegionSize;
            self.current_address = base + size;

            // Only scan committed, non-guard, writable memory
            if (mbi.State == win.MEM_COMMIT and (mbi.Protect & win.PAGE_GUARD) == 0 and (mbi.Protect & win.PAGE_NOACCESS) == 0) {
                const writable = (mbi.Protect & (win.PAGE_READWRITE | win.PAGE_WRITECOPY | win.PAGE_EXECUTE_READWRITE | win.PAGE_EXECUTE_WRITECOPY)) != 0;
                if (writable) {
                    return MemoryRegion{
                        .base_address = base,
                        .size = size,
                        .is_writable = true,
                    };
                }
            }
        }
        return null;
    }
};

pub const ScanResult = struct {
    address: usize,
    current_value: i64,
    previous_value: i64,
};

pub const MemoryScanner = struct {
    allocator: std.mem.Allocator,
    proc: *const process.ProcessHandle,
    results: std.ArrayList(ScanResult),

    pub fn init(allocator: std.mem.Allocator, proc: *const process.ProcessHandle) MemoryScanner {
        return .{
            .allocator = allocator,
            .proc = proc,
            .results = .empty,
        };
    }

    pub fn deinit(self: *MemoryScanner) void {
        self.results.deinit(self.allocator);
    }

    /// First scan across all writable committed memory regions
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
                    // Scan with natural 4-byte alignment
                    while (i + val_size <= bytes_read) : (i += 4) {
                        if (target.matchesBytes(buffer[i .. i + val_size])) {
                            const addr = region.base_address + offset + i;
                            const val_i64: i64 = switch (target) {
                                .I32 => std.mem.readInt(i32, buffer[i..][0..4], .little),
                                .U32 => std.mem.readInt(u32, buffer[i..][0..4], .little),
                                .I64 => std.mem.readInt(i64, buffer[i..][0..8], .little),
                                .U64 => @intCast(std.mem.readInt(u64, buffer[i..][0..8], .little)),
                                .F32 => @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, buffer[i..][0..4], .little)))),
                                .F64 => @intFromFloat(@as(f64, @bitCast(std.mem.readInt(u64, buffer[i..][0..8], .little)))),
                            };
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

    /// Next scan / filter: re-reads only previously matched addresses
    pub fn nextScan(self: *MemoryScanner, target: ScanTargetValue) !usize {
        var keep_idx: usize = 0;
        var buf: [8]u8 = undefined;
        const val_size = target.size();

        for (self.results.items) |entry| {
            const bytes_read = self.proc.readMemory(entry.address, buf[0..val_size]) catch 0;
            if (bytes_read == val_size and target.matchesBytes(buf[0..val_size])) {
                self.results.items[keep_idx] = .{
                    .address = entry.address,
                    .current_value = switch (target) {
                        .I32 => std.mem.readInt(i32, buf[0..4], .little),
                        .U32 => std.mem.readInt(u32, buf[0..4], .little),
                        .I64 => std.mem.readInt(i64, buf[0..8], .little),
                        .U64 => @intCast(std.mem.readInt(u64, buf[0..8], .little)),
                        .F32 => @intFromFloat(@as(f32, @bitCast(std.mem.readInt(u32, buf[0..4], .little)))),
                        .F64 => @intFromFloat(@as(f64, @bitCast(std.mem.readInt(u64, buf[0..8], .little)))),
                    },
                    .previous_value = entry.current_value,
                };
                keep_idx += 1;
            }
        }

        self.results.shrinkRetainingCapacity(keep_idx);
        return keep_idx;
    }
};
