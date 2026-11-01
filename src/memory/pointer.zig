const std = @import("std");
const process = @import("process.zig");
const win = process.win;

pub const PointerPath = struct {
    base_module: [64]u8,
    base_module_len: usize,
    base_offset: usize,
    offsets: [4]usize,
    depth: usize,
    resolved_target: usize,

    pub fn getModuleName(self: *const PointerPath) []const u8 {
        return self.base_module[0..self.base_module_len];
    }

    pub fn format(self: *const PointerPath, writer: anytype) !void {
        try writer.print("[{s}+0x{X}]", .{ self.getModuleName(), self.base_offset });
        var i: usize = 0;
        while (i < self.depth) : (i += 1) {
            try writer.print("->[+0x{X}]", .{self.offsets[i]});
        }
        try writer.print(" => 0x{X}", .{self.resolved_target});
    }
};

pub const PointerScanner = struct {
    allocator: std.mem.Allocator,
    max_depth: usize,
    max_offset: usize,

    pub fn init(allocator: std.mem.Allocator) PointerScanner {
        return PointerScanner{
            .allocator = allocator,
            .max_depth = 3,
            .max_offset = 4096,
        };
    }

    /// Searches a memory buffer for direct pointers pointing within `[target_addr - max_offset, target_addr]`
    pub fn findLevel1Pointers(
        self: *PointerScanner,
        buffer: []const u8,
        buffer_base_addr: usize,
        target_addr: usize,
        is_64bit: bool,
    ) !std.ArrayList(PointerPath) {
        var results: std.ArrayList(PointerPath) = .empty;
        errdefer results.deinit(self.allocator);

        const ptr_size: usize = if (is_64bit) 8 else 4;
        var offset: usize = 0;

        while (offset + ptr_size <= buffer.len) : (offset += ptr_size) {
            const candidate_target: usize = if (is_64bit)
                @as(usize, @intCast(std.mem.readInt(u64, buffer[offset..][0..8], .little)))
            else
                @as(usize, @intCast(std.mem.readInt(u32, buffer[offset..][0..4], .little)));

            if (candidate_target <= target_addr and (target_addr - candidate_target) <= self.max_offset) {
                const diff = target_addr - candidate_target;
                var path = PointerPath{
                    .base_module = @splat(0),
                    .base_module_len = 0,
                    .base_offset = buffer_base_addr + offset,
                    .offsets = @splat(0),
                    .depth = 1,
                    .resolved_target = target_addr,
                };
                const mod_name = "game.exe";
                @memcpy(path.base_module[0..mod_name.len], mod_name);
                path.base_module_len = mod_name.len;
                path.offsets[0] = diff;

                try results.append(self.allocator, path);
            }
        }

        return results;
    }
};

test "PointerScanner level 1 pointer detection" {
    const allocator = std.testing.allocator;
    var scanner = PointerScanner.init(allocator);

    // Mock heap memory where offset 16 contains pointer to 0x00500000
    // Target address is 0x00500048 (offset +0x48 into player struct)
    var mem_buffer: [64]u8 = @splat(0);
    const struct_base: u64 = 0x00500000;
    std.mem.writeInt(u64, mem_buffer[16..24], struct_base, .little);

    const target_stat_addr: usize = 0x00500048;
    var paths = try scanner.findLevel1Pointers(&mem_buffer, 0x00400000, target_stat_addr, true);
    defer paths.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), paths.items.len);
    try std.testing.expectEqual(@as(usize, 0x00400010), paths.items[0].base_offset);
    try std.testing.expectEqual(@as(usize, 0x48), paths.items[0].offsets[0]);
    try std.testing.expectEqual(target_stat_addr, paths.items[0].resolved_target);
}
