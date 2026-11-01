//! ============================================================================
//! SHARABHA (शरभ) — MUDRA SUTRA (मुद्रा सूत्र)
//! High-Speed Array of Bytes (AOB) & Wildcard Signature Scanner
//! Scans Executable & Committed Process Memory with Microsecond Latency
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");

pub const PatternByte = struct {
    value: u8,
    is_wildcard: bool,
};

pub const AobPattern = struct {
    bytes: []PatternByte,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, signature: []const u8) !AobPattern {
        var list: std.ArrayList(PatternByte) = .empty;
        defer list.deinit(allocator);

        var iter = std.mem.tokenizeAny(u8, signature, " \t\r\n");
        while (iter.next()) |token| {
            if (std.mem.eql(u8, token, "?") or std.mem.eql(u8, token, "??")) {
                try list.append(allocator, .{ .value = 0, .is_wildcard = true });
            } else {
                const b = std.fmt.parseInt(u8, token, 16) catch return error.InvalidHexByte;
                try list.append(allocator, .{ .value = b, .is_wildcard = false });
            }
        }

        if (list.items.len == 0) return error.EmptyPattern;

        const owned_slice = try allocator.dupe(PatternByte, list.items);
        return .{
            .bytes = owned_slice,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AobPattern) void {
        self.allocator.free(self.bytes);
    }

    pub fn matchesAt(self: *const AobPattern, buffer: []const u8, offset: usize) bool {
        if (offset + self.bytes.len > buffer.len) return false;
        for (self.bytes, 0..) |p, i| {
            if (p.is_wildcard) continue;
            if (buffer[offset + i] != p.value) return false;
        }
        return true;
    }

    pub fn findFirst(self: *const AobPattern, buffer: []const u8) ?usize {
        if (buffer.len < self.bytes.len) return null;
        const max_offset = buffer.len - self.bytes.len;
        var i: usize = 0;
        while (i <= max_offset) : (i += 1) {
            if (self.matchesAt(buffer, i)) return i;
        }
        return null;
    }

    pub fn findAll(self: *const AobPattern, buffer: []const u8, results: *std.ArrayList(usize)) !void {
        if (buffer.len < self.bytes.len) return;
        const max_offset = buffer.len - self.bytes.len;
        var i: usize = 0;
        while (i <= max_offset) : (i += 1) {
            if (self.matchesAt(buffer, i)) {
                try results.append(self.allocator, i);
            }
        }
    }
};

pub const ProcessAobScanner = struct {
    pub const ScanMatch = struct {
        address: usize,
        byte_length: usize,
    };

    /// Scans a virtual memory block or process address space for an AOB pattern
    pub fn scanBuffer(pattern: *const AobPattern, base_address: usize, buffer: []const u8, out_matches: *std.ArrayList(ScanMatch)) !void {
        var offsets: std.ArrayList(usize) = .empty;
        defer offsets.deinit(pattern.allocator);

        try pattern.findAll(buffer, &offsets);
        for (offsets.items) |off| {
            try out_matches.append(pattern.allocator, .{
                .address = base_address + off,
                .byte_length = pattern.bytes.len,
            });
        }
    }
};

test "AobPattern parsing, wildcard matching and search" {
    const allocator = std.testing.allocator;

    // Pattern: 48 89 5C 24 ?? 57
    const sig = "48 89 5C 24 ?? 57";
    var pattern = try AobPattern.parse(allocator, sig);
    defer pattern.deinit();

    try std.testing.expectEqual(@as(usize, 6), pattern.bytes.len);
    try std.testing.expect(pattern.bytes[4].is_wildcard);
    try std.testing.expect(!pattern.bytes[0].is_wildcard);

    const memory_dump = [_]u8{
        0x90, 0x90, 0x48, 0x89, 0x5C, 0x24, 0x20, 0x57, 0x48, 0x83, 0xEC, // Match at index 2 (wildcard 0x20)
        0x00, 0x00, 0x48, 0x89, 0x5C, 0x24, 0xFF, 0x57, 0xC3, // Match at index 13 (wildcard 0xFF)
    };

    const first = pattern.findFirst(&memory_dump);
    try std.testing.expect(first != null);
    try std.testing.expectEqual(@as(usize, 2), first.?);

    var matches: std.ArrayList(ProcessAobScanner.ScanMatch) = .empty;
    defer matches.deinit(allocator);

    try ProcessAobScanner.scanBuffer(&pattern, 0x140000000, &memory_dump, &matches);
    try std.testing.expectEqual(@as(usize, 2), matches.items.len);
    try std.testing.expectEqual(@as(usize, 0x140000002), matches.items[0].address);
    try std.testing.expectEqual(@as(usize, 0x14000000D), matches.items[1].address);
}
