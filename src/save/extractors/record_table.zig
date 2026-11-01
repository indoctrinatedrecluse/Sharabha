const std = @import("std");
const fuzzy = @import("../fuzzy.zig");

pub const RecordTableExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RecordTableExtractor {
        return RecordTableExtractor{ .allocator = allocator };
    }

    pub fn extract(self: *RecordTableExtractor, buffer: []const u8) !std.ArrayList(fuzzy.InferredField) {
        var parser = fuzzy.FuzzyParser.init(self.allocator);
        defer parser.deinit();

        const fields = try parser.parse(buffer);
        var results: std.ArrayList(fuzzy.InferredField) = .empty;
        errdefer results.deinit(self.allocator);

        try results.appendSlice(self.allocator, fields);
        return results;
    }
};
