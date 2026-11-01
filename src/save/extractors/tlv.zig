const std = @import("std");
const fuzzy = @import("../fuzzy.zig");

/// Type-Length-Value (TLV) Binary Extractor
/// Scans for patterns: [LengthPrefix (4 bytes) | String Tag | Payload]
pub const TlvExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TlvExtractor {
        return TlvExtractor{ .allocator = allocator };
    }

    pub fn extract(self: *TlvExtractor, buffer: []const u8) !std.ArrayList(fuzzy.InferredField) {
        var results: std.ArrayList(fuzzy.InferredField) = .empty;
        errdefer results.deinit(self.allocator);

        if (buffer.len < 16) return results;

        var i: usize = 0;
        while (i + 8 <= buffer.len) {
            // Check for 4-byte little endian string length between 3 and 40
            const str_len = std.mem.readInt(u32, buffer[i..][0..4], .little);
            if (str_len >= 3 and str_len <= 40 and i + 4 + str_len <= buffer.len) {
                const candidate_str = buffer[i + 4 .. i + 4 + str_len];
                var is_printable = true;
                for (candidate_str) |c| {
                    if (c < 0x20 or c > 0x7E) {
                        is_printable = false;
                        break;
                    }
                }

                if (is_printable) {
                    const payload_offset = i + 4 + str_len;
                    if (payload_offset + 4 <= buffer.len) {
                        const val_candidate = std.mem.readInt(i32, buffer[payload_offset..][0..4], .little);

                        var field = fuzzy.InferredField{
                            .offset = payload_offset,
                            .length = 4,
                            .confidence = 85,
                            .inferred_type = .Int32LE,
                            .display_value = @splat(0),
                            .display_value_len = 0,
                            .suggested_label = @splat(0),
                            .suggested_label_len = 0,
                        };

                        const copy_k = @min(candidate_str.len, 64);
                        @memcpy(field.suggested_label[0..copy_k], candidate_str[0..copy_k]);
                        field.suggested_label_len = copy_k;

                        const disp = std.fmt.bufPrint(&field.display_value, "{d}", .{val_candidate}) catch "ERR";
                        field.display_value_len = disp.len;

                        try results.append(self.allocator, field);

                        i = payload_offset + 4;
                        continue;
                    }
                }
            }
            i += 1;
        }

        return results;
    }
};

test "TlvExtractor on length-prefixed struct" {
    const allocator = std.testing.allocator;
    var extractor = TlvExtractor.init(allocator);

    // Mock TLV: [len=4 "COIN" val=75000]
    var buf: [32]u8 = @splat(0);
    std.mem.writeInt(u32, buf[0..4], 4, .little);
    @memcpy(buf[4..8], "COIN");
    std.mem.writeInt(i32, buf[8..12], 75000, .little);

    var fields = try extractor.extract(&buf);
    defer fields.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), fields.items.len);
    try std.testing.expectEqualStrings("COIN", fields.items[0].getLabel());
    try std.testing.expectEqual(@as(usize, 8), fields.items[0].offset);
}
