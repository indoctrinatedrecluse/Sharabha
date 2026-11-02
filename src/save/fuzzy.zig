const std = @import("std");

pub const InferredType = enum {
    StringAscii,
    StringUtf16,
    Int32LE,
    UInt32LE,
    Int64LE,
    Float32LE,
    Float64LE,
    RawBinary,

    pub fn name(self: InferredType) []const u8 {
        return switch (self) {
            .StringAscii => "String (ASCII)",
            .StringUtf16 => "String (UTF-16)",
            .Int32LE => "i32 (Little Endian)",
            .UInt32LE => "u32 (Little Endian)",
            .Int64LE => "i64 (Little Endian)",
            .Float32LE => "f32 (Float)",
            .Float64LE => "f64 (Double)",
            .RawBinary => "Raw Bytes",
        };
    }
};

pub const InferredField = struct {
    offset: usize,
    length: usize,
    inferred_type: InferredType,
    confidence: u8, // 0 - 100%
    display_value: [128]u8,
    display_value_len: usize,
    suggested_label: [64]u8,
    suggested_label_len: usize,

    pub fn getDisplayValue(self: *const InferredField) []const u8 {
        return self.display_value[0..self.display_value_len];
    }

    pub fn getLabel(self: *const InferredField) []const u8 {
        return self.suggested_label[0..self.suggested_label_len];
    }
};

/// Comparator to rank inferred fields by confidence rating in descending order.
/// Ties are broken by offset ascending for deterministic sorting stability.
pub fn sortDescByConfidence(_: void, a: InferredField, b: InferredField) bool {
    if (a.confidence != b.confidence) {
        return a.confidence > b.confidence;
    }
    return a.offset < b.offset;
}

pub const FuzzyParser = struct {
    allocator: std.mem.Allocator,
    fields: std.ArrayList(InferredField),

    pub fn init(allocator: std.mem.Allocator) FuzzyParser {
        return .{
            .allocator = allocator,
            .fields = .empty,
        };
    }

    pub fn deinit(self: *FuzzyParser) void {
        self.fields.deinit(self.allocator);
    }

    /// Parses the raw binary buffer using the generic fuzzy overseer engine.
    /// Extracts both high-confidence patterns and lower-confidence/unclassified variables,
    /// and ranks all extracted fields by confidence rating in descending order.
    pub fn parse(self: *FuzzyParser, data: []const u8) ![]const InferredField {
        self.fields.clearRetainingCapacity();

        var offset: usize = 0;
        var last_string_label: ?[64]u8 = null;
        var last_string_len: usize = 0;

        while (offset < data.len) {
            // 1. Try detect ASCII String (printable chars >= 3 ending in 0 or non-printable)
            if (self.tryDetectAscii(data, offset)) |field| {
                try self.fields.append(self.allocator, field);
                last_string_label = field.suggested_label;
                last_string_len = field.suggested_label_len;
                offset += field.length;
                continue;
            }

            // 2. Try detect UTF-16LE String
            if (self.tryDetectUtf16(data, offset)) |field| {
                try self.fields.append(self.allocator, field);
                last_string_label = field.suggested_label;
                last_string_len = field.suggested_label_len;
                offset += field.length;
                continue;
            }

            // 3. Try detect Float (f32) with sane range
            if (offset + 4 <= data.len) {
                if (self.tryDetectFloat32(data[offset .. offset + 4], offset, last_string_label, last_string_len)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_string_label = null;
                    continue;
                }
            }

            // 4. Try detect i32/u32 with contextual metrics (timestamps, resources, counters)
            if (offset + 4 <= data.len) {
                if (self.tryDetectInt32(data[offset .. offset + 4], offset, last_string_label, last_string_len)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_string_label = null;
                    continue;
                }
            }

            // 5. Unclassified Non-Zero Dwords (Lower Confidence Heuristic)
            // Even if we cannot classify or definitively label them, include them
            // because variable offsets and names like VAR_0x... make sense to the user.
            if (offset + 4 <= data.len) {
                if (self.tryDetectUnclassified(data[offset .. offset + 4], offset)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_string_label = null;
                    continue;
                }
            }

            // Fallback: advance 4 bytes or to end
            offset += @min(4, data.len - offset);
        }

        // Rank all extracted fields by confidence rating in descending order!
        std.mem.sort(InferredField, self.fields.items, {}, sortDescByConfidence);

        return self.fields.items;
    }

    fn tryDetectAscii(self: *FuzzyParser, data: []const u8, offset: usize) ?InferredField {
        _ = self;
        var len: usize = 0;
        while (offset + len < data.len and len < 64) {
            const b = data[offset + len];
            if (b == 0) break; // null terminator
            if (b < 0x20 or b > 0x7E) return null; // non-printable ASCII
            len += 1;
        }

        if (len >= 3) {
            var field: InferredField = .{
                .offset = offset,
                .length = if (offset + len < data.len and data[offset + len] == 0) len + 1 else len,
                .inferred_type = .StringAscii,
                .confidence = if (len >= 4) 92 else 75,
                .display_value = undefined,
                .display_value_len = len,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            @memcpy(field.display_value[0..len], data[offset .. offset + len]);

            // If it looks like an identifier/key, suggest it as a label
            const label_str = std.fmt.bufPrint(&field.suggested_label, "STR_0x{X:0>4}", .{offset}) catch "str";
            field.suggested_label_len = label_str.len;

            return field;
        }
        return null;
    }

    fn tryDetectUtf16(self: *FuzzyParser, data: []const u8, offset: usize) ?InferredField {
        _ = self;
        if (offset + 6 > data.len) return null;

        var char_count: usize = 0;
        while (offset + char_count * 2 + 1 < data.len and char_count < 32) {
            const low = data[offset + char_count * 2];
            const high = data[offset + char_count * 2 + 1];
            if (low == 0 and high == 0) break; // null terminator
            if (high != 0 or low < 0x20 or low > 0x7E) return null;
            char_count += 1;
        }

        if (char_count >= 3) {
            var field: InferredField = .{
                .offset = offset,
                .length = char_count * 2 + 2,
                .inferred_type = .StringUtf16,
                .confidence = 88,
                .display_value = undefined,
                .display_value_len = char_count,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            for (0..char_count) |i| {
                field.display_value[i] = data[offset + i * 2];
            }

            const label_str = std.fmt.bufPrint(&field.suggested_label, "U16_0x{X:0>4}", .{offset}) catch "u16";
            field.suggested_label_len = label_str.len;
            return field;
        }
        return null;
    }

    fn tryDetectInt32(
        self: *FuzzyParser,
        bytes: []const u8,
        offset: usize,
        prev_label: ?[64]u8,
        prev_label_len: usize,
    ) ?InferredField {
        _ = self;
        if (bytes.len < 4) return null;
        const val_i32 = std.mem.readInt(i32, bytes[0..4], .little);
        const val_u32 = std.mem.readInt(u32, bytes[0..4], .little);

        // Epoch Timestamp (high probability for timestamps in save headers)
        if (val_u32 >= 1_000_000_000 and val_u32 <= 2_000_000_000) {
            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .UInt32LE,
                .confidence = 90,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };
            const str = std.fmt.bufPrint(&field.display_value, "{d}", .{val_u32}) catch "0";
            field.display_value_len = str.len;
            const label_str = std.fmt.bufPrint(&field.suggested_label, "TIMESTAMP_0x{X:0>4}", .{offset}) catch "time";
            field.suggested_label_len = label_str.len;
            return field;
        }

        // Contextual or plausible gameplay resource range (currency, XP, health)
        if (val_i32 >= 1 and val_i32 <= 50_000_000) {
            var conf: u8 = 65;
            var prefix: []const u8 = "INT";
            if (val_i32 >= 100 and val_i32 <= 10_000_000) {
                conf = 82; // Currency or XP range
                prefix = "RESOURCE";
            } else if (val_i32 <= 100) {
                conf = 78; // Level or attribute range
                prefix = "LEVEL";
            }

            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .Int32LE,
                .confidence = conf,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            const str = std.fmt.bufPrint(&field.display_value, "{d}", .{val_i32}) catch "0";
            field.display_value_len = str.len;

            if (prev_label) |lbl| {
                const label_str = std.fmt.bufPrint(&field.suggested_label, "{s}_{s}", .{ prefix, lbl[0..prev_label_len] }) catch "val";
                field.suggested_label_len = label_str.len;
                field.confidence = @min(95, field.confidence + 15);
            } else {
                const label_str = std.fmt.bufPrint(&field.suggested_label, "{s}_0x{X:0>4}", .{ prefix, offset }) catch "int";
                field.suggested_label_len = label_str.len;
            }

            return field;
        }

        return null;
    }

    fn tryDetectFloat32(
        self: *FuzzyParser,
        bytes: []const u8,
        offset: usize,
        prev_label: ?[64]u8,
        prev_label_len: usize,
    ) ?InferredField {
        _ = self;
        if (bytes.len < 4) return null;
        const raw = std.mem.readInt(u32, bytes[0..4], .little);
        const f = @as(f32, @bitCast(raw));

        // Plausible game coordinates, timers, or health floats
        if (!std.math.isNan(f) and !std.math.isInf(f) and @abs(f) >= 0.01 and @abs(f) <= 50_000.0) {
            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .Float32LE,
                .confidence = 72,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            const str = std.fmt.bufPrint(&field.display_value, "{d:.2}", .{f}) catch "0.0";
            field.display_value_len = str.len;

            if (prev_label) |lbl| {
                const label_str = std.fmt.bufPrint(&field.suggested_label, "FLT_{s}", .{lbl[0..prev_label_len]}) catch "flt";
                field.suggested_label_len = label_str.len;
                field.confidence = @min(90, field.confidence + 15);
            } else {
                const label_str = std.fmt.bufPrint(&field.suggested_label, "FLT_0x{X:0>4}", .{offset}) catch "flt";
                field.suggested_label_len = label_str.len;
            }

            return field;
        }
        return null;
    }

    /// Lower-confidence extractor for non-zero binary dwords that cannot be classified definitively.
    /// Surfaced as candidate variables (VAR_0x0040) so the user can inspect and edit them.
    fn tryDetectUnclassified(self: *FuzzyParser, bytes: []const u8, offset: usize) ?InferredField {
        _ = self;
        if (bytes.len < 4) return null;
        const val_u32 = std.mem.readInt(u32, bytes[0..4], .little);
        const val_i32 = std.mem.readInt(i32, bytes[0..4], .little);

        // Skip all-zero null padding so the list isn't flooded with empty zeros
        if (val_u32 == 0) return null;

        var field: InferredField = .{
            .offset = offset,
            .length = 4,
            .inferred_type = .UInt32LE,
            .confidence = 45, // Lower confidence for unclassified / raw candidates
            .display_value = undefined,
            .display_value_len = 0,
            .suggested_label = undefined,
            .suggested_label_len = 0,
        };

        const label_str = std.fmt.bufPrint(&field.suggested_label, "VAR_0x{X:0>4}", .{offset}) catch "VAR";
        field.suggested_label_len = label_str.len;

        const disp_str = std.fmt.bufPrint(&field.display_value, "{d} (0x{X:0>8})", .{ val_i32, val_u32 }) catch "0";
        field.display_value_len = disp_str.len;

        return field;
    }
};

test "fuzzy parse mock save header and confidence descending order" {
    const allocator = std.testing.allocator;
    var parser = FuzzyParser.init(allocator);
    defer parser.deinit();

    // Construct a synthetic save file: "HERO_NAME\0" + i32(99999) + unclassified non-zero dword
    var buffer: [128]u8 = @splat(0);
    const label = "HERO_NAME";
    @memcpy(buffer[0..label.len], label);
    buffer[label.len] = 0;

    std.mem.writeInt(i32, buffer[12..16], 99999, .little);
    std.mem.writeInt(u32, buffer[20..24], 0xCAFEBABE, .little); // unclassified candidate

    const fields = try parser.parse(&buffer);
    try std.testing.expect(fields.len >= 3);

    // Verify descending sort by confidence
    for (0..fields.len - 1) |i| {
        try std.testing.expect(fields[i].confidence >= fields[i + 1].confidence);
    }

    // Top field should be highest confidence (ASCII string or contextual int)
    try std.testing.expect(fields[0].confidence >= 90);

    // Low confidence unclassified field should be at the bottom
    const last = fields[fields.len - 1];
    try std.testing.expect(last.confidence <= 50);
    try std.testing.expect(std.mem.startsWith(u8, last.getLabel(), "VAR_"));
}
