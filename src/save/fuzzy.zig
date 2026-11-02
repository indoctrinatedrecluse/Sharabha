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

/// Sūkshma Rekha (सूक्ष्म रेखा / Fine Line) Heuristic Checker
/// Rejects uninitialized memory fills, debug patterns, repetitive single-byte noise, and null runs
pub fn isGarbagePattern(val: u32) bool {
    // 1. Direct sentinel patterns
    switch (val) {
        0x00000000 => return true, // All zeros null pad
        0xFFFFFFFF => return true, // Uninitialized / -1 sentinel fill
        0xCDCDCDCD => return true, // MSVC heap free
        0xCCCCCCCC => return true, // MSVC stack uninitialized
        0xDDDDDDDD => return true, // MSVC dead land
        0xABABABAB => return true, // MSVC memory block fill
        0xFDFDFDFD => return true, // MSVC no-mans-land
        0xFEEEFEEE => return true, // Heap free
        else => {},
    }

    // 2. Repetitive single byte pattern (e.g. 0x01010101, 0x20202020)
    const low_byte = @as(u8, @truncate(val));
    const repeated = @as(u32, low_byte) * 0x01010101;
    if (val == repeated) {
        return true;
    }

    return false;
}

/// Checks if single-precision float represents a plausible game parameter
/// Coordinates, velocity, health/mana, timers, percentages
pub fn isPlausibleFloat(f: f32) bool {
    if (std.math.isNan(f) or std.math.isInf(f)) return false;
    const abs_f = @abs(f);
    if (abs_f < 0.001 or abs_f > 100_000.0) return false;

    // Check IEEE-754 exponent bits: 2^-10 (approx 0.001) to 2^+17 (approx 131,072)
    // Exponent bias is 127. Valid exponents fall in [117 .. 144].
    const bits: u32 = @bitCast(f);
    const exp = (bits >> 23) & 0xFF;
    if (exp < 117 or exp > 144) return false;

    return true;
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

    /// Parses arbitrary save vessel buffers using the Sūkshma Rekha (Fine Line) Overseer Engine.
    /// Extracts a large amount of useful game variables without garbage-dumping padding or debug noise,
    /// and ranks all extracted fields by confidence rating in descending order.
    pub fn parse(self: *FuzzyParser, data: []const u8) ![]const InferredField {
        self.fields.clearRetainingCapacity();

        var offset: usize = 0;
        var last_identifier: ?[64]u8 = null;
        var last_identifier_len: usize = 0;

        while (offset < data.len) {
            // 0. Skip runs of null padding (4+ consecutive zeros)
            if (offset + 4 <= data.len and std.mem.readInt(u32, data[offset..][0..4], .little) == 0) {
                offset += 4;
                while (offset + 4 <= data.len and std.mem.readInt(u32, data[offset..][0..4], .little) == 0) {
                    offset += 4;
                }
                last_identifier = null;
                continue;
            }

            // 1. Try detect Pascal Length-Prefixed String (u32 length + ASCII text)
            if (self.tryDetectPascalString(data, offset)) |field| {
                try self.fields.append(self.allocator, field);
                last_identifier = field.suggested_label;
                last_identifier_len = field.suggested_label_len;
                offset += field.length;
                continue;
            }

            // 2. Try detect Null-Terminated ASCII String
            if (self.tryDetectAscii(data, offset)) |field| {
                try self.fields.append(self.allocator, field);
                last_identifier = field.suggested_label;
                last_identifier_len = field.suggested_label_len;
                offset += field.length;
                continue;
            }

            // 3. Try detect UTF-16LE String
            if (self.tryDetectUtf16(data, offset)) |field| {
                try self.fields.append(self.allocator, field);
                last_identifier = field.suggested_label;
                last_identifier_len = field.suggested_label_len;
                offset += field.length;
                continue;
            }

            // If we have 4 bytes available, evaluate scalars with Fine Line heuristics
            if (offset + 4 <= data.len) {
                const slice4: *const [4]u8 = data[offset..][0..4];
                const u32_val = std.mem.readInt(u32, slice4, .little);

                // Reject uninitialized memory, debug patterns, repetitive single-byte fills
                if (isGarbagePattern(u32_val)) {
                    offset += 4;
                    last_identifier = null;
                    continue;
                }

                // 4. Try detect Identifier-Associated Value (High Confidence 94%)
                if (last_identifier) |ident| {
                    if (self.tryDetectAssociatedValue(slice4, offset, ident[0..last_identifier_len])) |field| {
                        try self.fields.append(self.allocator, field);
                        offset += 4;
                        last_identifier = null;
                        continue;
                    }
                }

                // 5. Try detect Plausible Float (f32) with bounded game range
                if (self.tryDetectFloat32(slice4, offset)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_identifier = null;
                    continue;
                }

                // 6. Try detect Contextual Integers (timestamps, gameplay resources, levels/stats)
                if (self.tryDetectContextualInt(slice4, offset)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_identifier = null;
                    continue;
                }

                // 7. Clean Unclassified Dword (Fine Line Lower-Confidence Candidate)
                // Only non-garbage, non-padding dwords make it here.
                if (self.tryDetectCleanUnclassified(slice4, offset)) |field| {
                    try self.fields.append(self.allocator, field);
                    offset += 4;
                    last_identifier = null;
                    continue;
                }
            }

            // Fallback: advance 4 bytes or to end
            offset += @min(4, data.len - offset);
            last_identifier = null;
        }

        // Rank all extracted fields by confidence rating in descending order!
        std.mem.sort(InferredField, self.fields.items, {}, sortDescByConfidence);

        return self.fields.items;
    }

    /// Detects Pascal length-prefixed string: [u32 len] [ASCII chars]
    fn tryDetectPascalString(self: *FuzzyParser, data: []const u8, offset: usize) ?InferredField {
        _ = self;
        if (offset + 8 > data.len) return null;
        const str_len = std.mem.readInt(u32, data[offset..][0..4], .little);
        if (str_len < 3 or str_len > 48 or offset + 4 + str_len > data.len) return null;

        const candidate = data[offset + 4 .. offset + 4 + str_len];
        for (candidate) |c| {
            if (c < 0x20 or c > 0x7E) return null; // non-printable ASCII
        }

        var field: InferredField = .{
            .offset = offset,
            .length = 4 + str_len,
            .inferred_type = .StringAscii,
            .confidence = 94,
            .display_value = undefined,
            .display_value_len = @min(candidate.len, 128),
            .suggested_label = undefined,
            .suggested_label_len = 0,
        };

        @memcpy(field.display_value[0..field.display_value_len], candidate[0..field.display_value_len]);

        const copy_k = @min(candidate.len, 64);
        @memcpy(field.suggested_label[0..copy_k], candidate[0..copy_k]);
        field.suggested_label_len = copy_k;

        return field;
    }

    /// Detects null-terminated ASCII string (3 to 48 printable chars ending in 0)
    fn tryDetectAscii(self: *FuzzyParser, data: []const u8, offset: usize) ?InferredField {
        _ = self;
        var len: usize = 0;
        while (offset + len < data.len and len < 48) {
            const b = data[offset + len];
            if (b == 0) break; // null terminator
            if (b < 0x20 or b > 0x7E) return null; // non-printable
            len += 1;
        }

        if (len >= 3) {
            var field: InferredField = .{
                .offset = offset,
                .length = if (offset + len < data.len and data[offset + len] == 0) len + 1 else len,
                .inferred_type = .StringAscii,
                .confidence = if (len >= 4) 92 else 76,
                .display_value = undefined,
                .display_value_len = len,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            @memcpy(field.display_value[0..len], data[offset .. offset + len]);

            const copy_k = @min(len, 64);
            @memcpy(field.suggested_label[0..copy_k], data[offset .. offset + copy_k]);
            field.suggested_label_len = copy_k;

            return field;
        }
        return null;
    }

    /// Detects UTF-16LE string (3 to 32 chars)
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

            const copy_k = @min(char_count, 64);
            @memcpy(field.suggested_label[0..copy_k], field.display_value[0..copy_k]);
            field.suggested_label_len = copy_k;
            return field;
        }
        return null;
    }

    /// Binds an immediately preceding string anchor to a scalar value
    fn tryDetectAssociatedValue(
        self: *FuzzyParser,
        bytes: *const [4]u8,
        offset: usize,
        ident: []const u8,
    ) ?InferredField {
        _ = self;
        const u32_val = std.mem.readInt(u32, bytes, .little);
        const i32_val = std.mem.readInt(i32, bytes, .little);
        const f = @as(f32, @bitCast(u32_val));

        var field: InferredField = .{
            .offset = offset,
            .length = 4,
            .inferred_type = .Int32LE,
            .confidence = 94, // High confidence: anchored to preceding identifier!
            .display_value = undefined,
            .display_value_len = 0,
            .suggested_label = undefined,
            .suggested_label_len = 0,
        };

        if (isPlausibleFloat(f)) {
            field.inferred_type = .Float32LE;
            const str = std.fmt.bufPrint(&field.display_value, "{d:.2}", .{f}) catch "0.0";
            field.display_value_len = str.len;
            const lbl = std.fmt.bufPrint(&field.suggested_label, "{s} [Float]", .{ident}) catch "VAL";
            field.suggested_label_len = lbl.len;
            return field;
        }

        if (i32_val >= 0 and i32_val <= 50_000_000) {
            const str = std.fmt.bufPrint(&field.display_value, "{d}", .{i32_val}) catch "0";
            field.display_value_len = str.len;
            const suffix = if (i32_val == 0 or i32_val == 1) " [Flag]" else " [Val]";
            const lbl = std.fmt.bufPrint(&field.suggested_label, "{s}{s}", .{ ident, suffix }) catch "VAL";
            field.suggested_label_len = lbl.len;
            return field;
        }

        return null;
    }

    /// Detects single-precision float within valid game physics/attribute ranges
    fn tryDetectFloat32(self: *FuzzyParser, bytes: *const [4]u8, offset: usize) ?InferredField {
        _ = self;
        const raw = std.mem.readInt(u32, bytes, .little);
        const f = @as(f32, @bitCast(raw));

        if (isPlausibleFloat(f)) {
            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .Float32LE,
                .confidence = 74,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };

            const str = std.fmt.bufPrint(&field.display_value, "{d:.2}", .{f}) catch "0.0";
            field.display_value_len = str.len;

            const label_str = std.fmt.bufPrint(&field.suggested_label, "FLOAT_0x{X:0>4}", .{offset}) catch "flt";
            field.suggested_label_len = label_str.len;
            return field;
        }
        return null;
    }

    /// Detects contextual integers: timestamps, resources, levels, stats
    fn tryDetectContextualInt(self: *FuzzyParser, bytes: *const [4]u8, offset: usize) ?InferredField {
        _ = self;
        const val_i32 = std.mem.readInt(i32, bytes, .little);
        const val_u32 = std.mem.readInt(u32, bytes, .little);

        // Epoch Timestamp (high probability for timestamps in save headers)
        if (val_u32 >= 1_000_000_000 and val_u32 <= 2_100_000_000) {
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

        // Gameplay resource range (currency, XP, health)
        if (val_i32 >= 100 and val_i32 <= 50_000_000) {
            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .Int32LE,
                .confidence = 82,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };
            const str = std.fmt.bufPrint(&field.display_value, "{d}", .{val_i32}) catch "0";
            field.display_value_len = str.len;
            const label_str = std.fmt.bufPrint(&field.suggested_label, "RESOURCE_0x{X:0>4}", .{offset}) catch "res";
            field.suggested_label_len = label_str.len;
            return field;
        }

        // Level or attribute range (1 to 255)
        if (val_i32 >= 1 and val_i32 <= 255) {
            var field: InferredField = .{
                .offset = offset,
                .length = 4,
                .inferred_type = .Int32LE,
                .confidence = 78,
                .display_value = undefined,
                .display_value_len = 0,
                .suggested_label = undefined,
                .suggested_label_len = 0,
            };
            const str = std.fmt.bufPrint(&field.display_value, "{d}", .{val_i32}) catch "0";
            field.display_value_len = str.len;
            const label_str = std.fmt.bufPrint(&field.suggested_label, "LEVEL_OR_STAT_0x{X:0>4}", .{offset}) catch "lvl";
            field.suggested_label_len = label_str.len;
            return field;
        }

        return null;
    }

    /// Fine Line Extractor for clean, non-garbage unclassified dwords.
    /// Excludes null padding, MSVC debug fills, sentinel patterns, and byte repeats.
    fn tryDetectCleanUnclassified(self: *FuzzyParser, bytes: *const [4]u8, offset: usize) ?InferredField {
        _ = self;
        const val_u32 = std.mem.readInt(u32, bytes, .little);
        const val_i32 = std.mem.readInt(i32, bytes, .little);

        if (isGarbagePattern(val_u32)) return null;

        var field: InferredField = .{
            .offset = offset,
            .length = 4,
            .inferred_type = .UInt32LE,
            .confidence = 50, // Fine line lower confidence for clean unclassified candidate
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

test "fine line fuzzy parser filters garbage and ranks confidence descending" {
    const allocator = std.testing.allocator;
    var parser = FuzzyParser.init(allocator);
    defer parser.deinit();

    // Construct a synthetic save file:
    // 1. Pascal string: len 4 + "GOLD" + immediate i32 value 75000 (Anchor-value pair)
    // 2. Padding run of 16 zero bytes (must be skipped cleanly!)
    // 3. Debug fill 0xCDCDCDCD (must be rejected!)
    // 4. Plausible float (health = 100.0f)
    // 5. Clean unclassified non-zero dword 0x0A0B0C0D
    var buffer: [64]u8 = @splat(0);

    // 1. Pascal string at offset 0
    std.mem.writeInt(u32, buffer[0..4], 4, .little);
    @memcpy(buffer[4..8], "GOLD");
    // Associated value at offset 8
    std.mem.writeInt(i32, buffer[8..12], 75000, .little);

    // Offsets 12..28 are null zeros (must be skipped, no garbage dumping!)

    // Offset 28: Debug fill 0xCDCDCDCD (must be skipped)
    std.mem.writeInt(u32, buffer[28..32], 0xCDCDCDCD, .little);

    // Offset 32: Plausible float 100.0f
    const f_raw: u32 = @bitCast(@as(f32, 100.0));
    std.mem.writeInt(u32, buffer[32..36], f_raw, .little);

    // Offset 36: Clean unclassified dword
    std.mem.writeInt(u32, buffer[36..40], 0x0A0B0C0D, .little);

    const fields = try parser.parse(&buffer);
    try std.testing.expect(fields.len >= 3);

    // Verify descending sort by confidence
    for (0..fields.len - 1) |i| {
        try std.testing.expect(fields[i].confidence >= fields[i + 1].confidence);
    }

    // Top field should be high-confidence Pascal string or anchor-value pair
    try std.testing.expect(fields[0].confidence >= 90);

    // Verify garbage was NOT dumped: no 0xCDCDCDCD, no null pads
    for (fields) |f| {
        try std.testing.expect(!std.mem.eql(u8, f.getDisplayValue(), "-842150451"));
        try std.testing.expect(!std.mem.eql(u8, f.getLabel(), "VAR_0x001C"));
    }

    // Clean unclassified field VAR_0x0024 should be present with ~50% confidence
    const last = fields[fields.len - 1];
    try std.testing.expectEqual(@as(u8, 50), last.confidence);
    try std.testing.expect(std.mem.startsWith(u8, last.getLabel(), "VAR_"));
}
