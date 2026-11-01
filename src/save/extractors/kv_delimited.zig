const std = @import("std");
const fuzzy = @import("../fuzzy.zig");

/// Delimited Key-Value Extractor for PlainText, JSON, XML, INI formats
pub const KvDelimitedExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KvDelimitedExtractor {
        return KvDelimitedExtractor{ .allocator = allocator };
    }

    pub fn extract(self: *KvDelimitedExtractor, buffer: []const u8) !std.ArrayList(fuzzy.InferredField) {
        var results: std.ArrayList(fuzzy.InferredField) = .empty;
        errdefer results.deinit(self.allocator);

        var line_iter = std.mem.splitScalar(u8, buffer, '\n');
        var offset: usize = 0;

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            defer offset += raw_line.len + 1;

            if (line.len == 0 or line[0] == '#' or line[0] == '/') continue;

            // Search for delimiter: '=', ':', or JSON quotes
            var delim_idx: ?usize = null;
            if (std.mem.indexOfScalar(u8, line, '=')) |idx| {
                delim_idx = idx;
            } else if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
                delim_idx = idx;
            }

            if (delim_idx) |d_idx| {
                const raw_key = std.mem.trim(u8, line[0..d_idx], " \t\"'{}[],");
                const raw_val = std.mem.trim(u8, line[d_idx + 1 ..], " \t\"'{}[],;");

                if (raw_key.len > 0 and raw_val.len > 0) {
                    var field = fuzzy.InferredField{
                        .offset = offset + (d_idx + 1),
                        .length = raw_val.len,
                        .confidence = 90,
                        .inferred_type = .StringAscii,
                        .display_value = @splat(0),
                        .display_value_len = 0,
                        .suggested_label = @splat(0),
                        .suggested_label_len = 0,
                    };

                    const k_len = @min(raw_key.len, 64);
                    @memcpy(field.suggested_label[0..k_len], raw_key[0..k_len]);
                    field.suggested_label_len = k_len;

                    // Try parsing as integer
                    if (std.fmt.parseInt(i32, raw_val, 10)) |num| {
                        field.inferred_type = .Int32LE;
                        field.length = 4;
                        const disp = std.fmt.bufPrint(&field.display_value, "{d}", .{num}) catch "ERR";
                        field.display_value_len = disp.len;
                    } else |_| {
                        // Keep as string
                        const v_len = @min(raw_val.len, 128);
                        @memcpy(field.display_value[0..v_len], raw_val[0..v_len]);
                        field.display_value_len = v_len;
                    }

                    try results.append(self.allocator, field);
                }
            }
        }

        return results;
    }
};

test "KvDelimitedExtractor parsing INI and JSON lines" {
    const allocator = std.testing.allocator;
    var extractor = KvDelimitedExtractor.init(allocator);

    const input =
        \\"PLAYER_GOLD"=999999
        \\"HEALTH": 100
        \\"NAME"=Shiva
    ;

    var fields = try extractor.extract(input);
    defer fields.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), fields.items.len);
    try std.testing.expectEqualStrings("PLAYER_GOLD", fields.items[0].getLabel());
    try std.testing.expectEqual(fuzzy.InferredType.Int32LE, fields.items[0].inferred_type);
}
