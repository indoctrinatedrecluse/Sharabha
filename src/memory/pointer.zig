const std = @import("std");
const process = @import("process.zig");
const win = process.win;

pub const MAX_POINTER_DEPTH: usize = 7;

pub const PointerPath = struct {
    base_module: [64]u8,
    base_module_len: usize,
    base_offset: usize,
    base_address: usize,
    offsets: [MAX_POINTER_DEPTH]usize,
    depth: usize,
    resolved_target: usize,
    is_static: bool,

    pub fn getModuleName(self: *const PointerPath) []const u8 {
        return self.base_module[0..self.base_module_len];
    }

    pub fn format(self: *const PointerPath, writer: anytype) !void {
        if (self.is_static and self.base_module_len > 0) {
            try writer.print("[{s}+0x{X}]", .{ self.getModuleName(), self.base_offset });
        } else {
            try writer.print("[0x{X}]", .{self.base_address});
        }
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            try writer.print("->[+0x{X}]", .{self.offsets[i]});
        }
        try writer.print(" => 0x{X}", .{self.resolved_target});
    }

    pub fn toString(self: *const PointerPath, buf: []u8) []const u8 {
        var cursor: usize = 0;
        if (self.is_static and self.base_module_len > 0) {
            const part = std.fmt.bufPrint(buf[cursor..], "[{s}+0x{X}]", .{ self.getModuleName(), self.base_offset }) catch return "";
            cursor += part.len;
        } else {
            const part = std.fmt.bufPrint(buf[cursor..], "[0x{X}]", .{self.base_address}) catch return "";
            cursor += part.len;
        }
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            const part = std.fmt.bufPrint(buf[cursor..], "->[+0x{X}]", .{self.offsets[i]}) catch return "";
            cursor += part.len;
        }
        const end_part = std.fmt.bufPrint(buf[cursor..], " => 0x{X}", .{self.resolved_target}) catch return "";
        cursor += end_part.len;
        return buf[0..cursor];
    }
};

pub const ScannedMemoryBlock = struct {
    base_address: usize,
    bytes: []const u8,
};

pub const ReversePointer = struct {
    address: usize,
    points_to: usize,
};

/// Candidate node during multi-level reverse pointer expansion
pub const PathNode = struct {
    current_addr: usize,
    depth: usize,
    offsets: [MAX_POINTER_DEPTH]usize,
};

/// Vyuha Sutra (व्यूह सूत्र) — Multi-Level Pointer Map Inquest
/// Recursively walks reverse dereference graphs to discover static module-base pointer chains
/// that remain invariant across game restarts and dynamic ASLR reallocations.
pub const PointerScanner = struct {
    allocator: std.mem.Allocator,
    max_depth: usize,
    max_offset: usize,
    is_64bit: bool,

    pub fn init(allocator: std.mem.Allocator) PointerScanner {
        return PointerScanner{
            .allocator = allocator,
            .max_depth = 4,
            .max_offset = 4096,
            .is_64bit = @sizeOf(usize) == 8,
        };
    }

    pub fn setMaxDepth(self: *PointerScanner, depth: usize) void {
        self.max_depth = @min(@max(1, depth), MAX_POINTER_DEPTH);
    }

    pub fn setMaxOffset(self: *PointerScanner, offset: usize) void {
        self.max_offset = offset;
    }

    /// Discovers all aligned pointers within the provided memory blocks
    pub fn collectPointers(
        self: *PointerScanner,
        blocks: []const ScannedMemoryBlock,
    ) !std.ArrayList(ReversePointer) {
        var list: std.ArrayList(ReversePointer) = .empty;
        errdefer list.deinit(self.allocator);

        const ptr_size: usize = if (self.is_64bit) 8 else 4;

        for (blocks) |block| {
            var off: usize = 0;
            while (off + ptr_size <= block.bytes.len) : (off += ptr_size) {
                const target: usize = if (self.is_64bit)
                    @as(usize, @intCast(std.mem.readInt(u64, block.bytes[off..][0..8], .little)))
                else
                    @as(usize, @intCast(std.mem.readInt(u32, block.bytes[off..][0..4], .little)));

                // Filter out non-canonical or null pointers
                if (target < 0x10000 or (self.is_64bit and target > 0x00007FFFFFFFFFF)) {
                    continue;
                }

                try list.append(self.allocator, ReversePointer{
                    .address = block.base_address + off,
                    .points_to = target,
                });
            }
        }

        return list;
    }

    /// Checks if an address falls within any loaded module, identifying a static base
    pub fn findModuleForAddress(
        modules: []const process.ModuleEntry,
        address: usize,
    ) ?struct { entry: process.ModuleEntry, offset: usize } {
        for (modules) |mod| {
            if (address >= mod.base_address and address < (mod.base_address + mod.size)) {
                return .{
                    .entry = mod,
                    .offset = address - mod.base_address,
                };
            }
        }
        return null;
    }

    /// Performs multi-level reverse pointer scanning to discover static and dynamic pointer paths
    pub fn findMultiLevelPaths(
        self: *PointerScanner,
        pointers: []const ReversePointer,
        modules: []const process.ModuleEntry,
        target_addr: usize,
        max_results: usize,
    ) !std.ArrayList(PointerPath) {
        var results: std.ArrayList(PointerPath) = .empty;
        errdefer results.deinit(self.allocator);

        var current_level_nodes: std.ArrayList(PathNode) = .empty;
        defer current_level_nodes.deinit(self.allocator);

        // Seed with root target (level 0)
        const root_node = PathNode{
            .current_addr = target_addr,
            .depth = 0,
            .offsets = @splat(0),
        };
        try current_level_nodes.append(self.allocator, root_node);

        var level: usize = 1;
        while (level <= self.max_depth and current_level_nodes.items.len > 0) : (level += 1) {
            var next_level_nodes: std.ArrayList(PathNode) = .empty;
            defer next_level_nodes.deinit(self.allocator);

            for (current_level_nodes.items) |parent_node| {
                if (results.items.len >= max_results) break;

                for (pointers) |ptr| {
                    if (results.items.len >= max_results) break;

                    if (ptr.points_to <= parent_node.current_addr) {
                        const diff = parent_node.current_addr - ptr.points_to;
                        if (diff <= self.max_offset) {
                            var new_offsets = parent_node.offsets;
                            // Level offset stored into new_offsets
                            new_offsets[level - 1] = diff;

                            // Check if this pointer itself resides in a static module
                            if (findModuleForAddress(modules, ptr.address)) |mod_match| {
                                var path = PointerPath{
                                    .base_module = @splat(0),
                                    .base_module_len = mod_match.entry.name_len,
                                    .base_offset = mod_match.offset,
                                    .base_address = ptr.address,
                                    .offsets = @splat(0),
                                    .depth = level,
                                    .resolved_target = target_addr,
                                    .is_static = true,
                                };
                                const copy_len = @min(mod_match.entry.name_len, 64);
                                @memcpy(path.base_module[0..copy_len], mod_match.entry.name[0..copy_len]);
                                path.base_module_len = copy_len;

                                // Reverse offsets into forward order: base -> level 1 -> ... -> target
                                var o_idx: usize = 0;
                                while (o_idx < level) : (o_idx += 1) {
                                    path.offsets[o_idx] = new_offsets[level - 1 - o_idx];
                                }

                                try results.append(self.allocator, path);
                            } else if (level < self.max_depth) {
                                // Add as candidate for next depth
                                try next_level_nodes.append(self.allocator, PathNode{
                                    .current_addr = ptr.address,
                                    .depth = level,
                                    .offsets = new_offsets,
                                });
                            }
                        }
                    }
                }
            }

            // Cap next level exploration to prevent exponential explosion
            current_level_nodes.clearRetainingCapacity();
            const cap = @min(next_level_nodes.items.len, 1000);
            try current_level_nodes.appendSlice(self.allocator, next_level_nodes.items[0..cap]);
        }

        return results;
    }

    /// Verifies a pointer path by reading through memory dereferences
    pub fn resolvePath(
        self: *const PointerScanner,
        proc: *const process.ProcessHandle,
        path: *const PointerPath,
        modules: []const process.ModuleEntry,
    ) !usize {
        var current_addr: usize = 0;
        if (path.is_static and path.base_module_len > 0) {
            var found_mod = false;
            for (modules) |m| {
                if (std.mem.eql(u8, m.getName(), path.getModuleName())) {
                    current_addr = m.base_address + path.base_offset;
                    found_mod = true;
                    break;
                }
            }
            if (!found_mod) return error.ModuleNotFound;
        } else {
            current_addr = path.base_address;
        }

        const ptr_size: usize = if (self.is_64bit) 8 else 4;
        var buf: [8]u8 = undefined;

        var i: usize = 0;
        while (i < path.depth) : (i += 1) {
            _ = try proc.readMemory(current_addr, buf[0..ptr_size]);
            const ptr_val: usize = if (self.is_64bit)
                @as(usize, @intCast(std.mem.readInt(u64, buf[0..8], .little)))
            else
                @as(usize, @intCast(std.mem.readInt(u32, buf[0..4], .little)));

            if (ptr_val == 0) return error.NullPointerDereference;
            current_addr = ptr_val + path.offsets[i];
        }

        return current_addr;
    }
};

test "Multi-level pointer scan and chain resolution (Depth 1, 2, and 3)" {
    const allocator = std.testing.allocator;
    var scanner = PointerScanner.init(allocator);
    scanner.setMaxDepth(4);
    scanner.setMaxOffset(0x1000);

    // Mock Memory Layout:
    // Module: "hero_game.exe" at 0x140000000, size 0x20000
    //
    // Static Base in Module:
    //   Address: 0x140005000 (offset 0x5000 in hero_game.exe)
    //   Points To: Level 2 Struct at 0x20001000
    //
    // Level 2 Struct:
    //   Address: 0x20001000 + 0x20 = 0x20001020
    //   Points To: Level 1 Struct at 0x30002000
    //
    // Level 1 Struct:
    //   Address: 0x30002000 + 0x48 = 0x30002048
    //   Points To: Player Entity at 0x40005000
    //
    // Target Variable:
    //   Player Entity Health at 0x40005000 + 0x18 = 0x40005018

    const mod_base: usize = 0x140000000;
    var mod_name_buf: [260]u8 = @splat(0);
    const mod_str = "hero_game.exe";
    @memcpy(mod_name_buf[0..mod_str.len], mod_str);

    const modules = [_]process.ModuleEntry{
        .{
            .base_address = mod_base,
            .size = 0x20000,
            .name = mod_name_buf,
            .name_len = mod_str.len,
        },
    };

    // Synthetic memory pointers
    var pointers: [3]ReversePointer = undefined;
    // Static base at 0x140005000 points to 0x20001000
    pointers[0] = .{ .address = 0x140005000, .points_to = 0x20001000 };
    // At 0x20001020 points to 0x30002000
    pointers[1] = .{ .address = 0x20001020, .points_to = 0x30002000 };
    // At 0x30002048 points to 0x40005000
    pointers[2] = .{ .address = 0x30002048, .points_to = 0x40005000 };

    const target_health_addr: usize = 0x40005018;

    var paths = try scanner.findMultiLevelPaths(&pointers, &modules, target_health_addr, 10);
    defer paths.deinit(allocator);

    try std.testing.expect(paths.items.len >= 1);
    const path = paths.items[0];

    try std.testing.expect(path.is_static);
    try std.testing.expectEqualStrings("hero_game.exe", path.getModuleName());
    try std.testing.expectEqual(@as(usize, 0x5000), path.base_offset);
    try std.testing.expectEqual(@as(usize, 3), path.depth);
    try std.testing.expectEqual(@as(usize, 0x20), path.offsets[0]);
    try std.testing.expectEqual(@as(usize, 0x48), path.offsets[1]);
    try std.testing.expectEqual(@as(usize, 0x18), path.offsets[2]);
    try std.testing.expectEqual(target_health_addr, path.resolved_target);

    // Test formatting output
    var str_buf: [128]u8 = undefined;
    const formatted = path.toString(&str_buf);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "[hero_game.exe+0x5000]->[+0x20]->[+0x48]->[+0x18] => 0x40005018") != null);
}
