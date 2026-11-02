const std = @import("std");
const fuzzy = @import("../fuzzy.zig");
const profiles = @import("../../knowledge/profiles.zig");

pub const HybridExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HybridExtractor {
        return HybridExtractor{ .allocator = allocator };
    }

    pub fn extract(
        self: *HybridExtractor,
        buffer: []const u8,
        filename: []const u8,
    ) !std.ArrayList(fuzzy.InferredField) {
        var results: std.ArrayList(fuzzy.InferredField) = .empty;
        errdefer results.deinit(self.allocator);

        // 1. Check for deterministic Agama game profile (only if recognized in knowledge base)
        const header_slice = if (buffer.len >= 16) buffer[0..16] else buffer;
        const matched_profile = profiles.findMatchingProfile(filename, header_slice);

        var claimed_offsets: [64]usize = @splat(std.math.maxInt(usize));
        var claimed_count: usize = 0;

        if (matched_profile) |prof| {
            for (prof.rules) |rule| {
                if (rule.offset + 4 <= buffer.len and claimed_count < 64) {
                    var field = fuzzy.InferredField{
                        .offset = rule.offset,
                        .length = 4,
                        .confidence = 100, // Deterministic profile rules carry 100% confidence
                        .inferred_type = rule.field_type,
                        .display_value = @splat(0),
                        .display_value_len = 0,
                        .suggested_label = @splat(0),
                        .suggested_label_len = 0,
                    };

                    const k_len = @min(rule.key_name.len, 64);
                    @memcpy(field.suggested_label[0..k_len], rule.key_name[0..k_len]);
                    field.suggested_label_len = k_len;

                    if (rule.field_type == .Int32LE) {
                        const val = std.mem.readInt(i32, buffer[rule.offset..][0..4], .little);
                        const disp = std.fmt.bufPrint(&field.display_value, "{d}", .{val}) catch "ERR";
                        field.display_value_len = disp.len;
                    } else if (rule.field_type == .UInt32LE) {
                        const val = std.mem.readInt(u32, buffer[rule.offset..][0..4], .little);
                        const disp = std.fmt.bufPrint(&field.display_value, "{d}", .{val}) catch "ERR";
                        field.display_value_len = disp.len;
                    } else if (rule.field_type == .Float32LE) {
                        const raw = std.mem.readInt(u32, buffer[rule.offset..][0..4], .little);
                        const val = @as(f32, @bitCast(raw));
                        const disp = std.fmt.bufPrint(&field.display_value, "{d:.2}", .{val}) catch "ERR";
                        field.display_value_len = disp.len;
                    }

                    try results.append(self.allocator, field);

                    claimed_offsets[claimed_count] = rule.offset;
                    claimed_count += 1;
                }
            }
        }

        // 2. Generic fuzzy extraction for remaining regions (including lower confidence & unclassified values)
        var parser = fuzzy.FuzzyParser.init(self.allocator);
        defer parser.deinit();

        const raw_candidates = try parser.parse(buffer);

        for (raw_candidates) |candidate| {
            // Check if this offset was already claimed by a deterministic rule
            var already_claimed = false;
            for (claimed_offsets[0..claimed_count]) |off| {
                if (candidate.offset == off) {
                    already_claimed = true;
                    break;
                }
            }

            if (!already_claimed) {
                try results.append(self.allocator, candidate);
            }
        }

        // 3. Rank entire combined results by confidence rating in descending order!
        std.mem.sort(fuzzy.InferredField, results.items, {}, fuzzy.sortDescByConfidence);

        return results;
    }
};

test "HybridExtractor deterministic + fuzzy fusion ranked by confidence" {
    const allocator = std.testing.allocator;
    var hybrid = HybridExtractor.init(allocator);

    // Mock Elden Ring save buffer:
    // Offset 0x0C has 750000 (PLAYER_RUNES), offset 0x10 has 150 (RUNE_LEVEL)
    var buf: [128]u8 = @splat(0);
    @memcpy(buf[0..4], "BND4");
    std.mem.writeInt(i32, buf[0x0C .. 0x0C + 4], 750000, .little);
    std.mem.writeInt(i32, buf[0x10 .. 0x10 + 4], 150, .little);

    // Additional arbitrary unknown string + number for fuzzy overseer extractor
    @memcpy(buf[32..40], "MANA_MAX");
    std.mem.writeInt(i32, buf[44..48], 1500, .little);
    std.mem.writeInt(u32, buf[60..64], 0xDEADBEEF, .little); // unclassified candidate

    var fields = try hybrid.extract(&buf, "ER0000.sl2");
    defer fields.deinit(allocator);

    try std.testing.expect(fields.items.len >= 3);
    // Deterministic rules should be at top with 100% confidence
    try std.testing.expectEqual(@as(u8, 100), fields.items[0].confidence);

    // Verify descending sort order across all items
    for (0..fields.items.len - 1) |i| {
        try std.testing.expect(fields.items[i].confidence >= fields.items[i + 1].confidence);
    }
}
