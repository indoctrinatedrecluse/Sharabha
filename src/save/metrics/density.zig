const std = @import("std");

pub const DensityProfile = struct {
    null_ratio: f32, // Ratio of 0x00 bytes
    ascii_ratio: f32, // Ratio of printable ASCII bytes
    delim_ratio: f32, // Ratio of delimiters (=, :, {, }, [, ], ,, ;, \n)
    high_byte_ratio: f32, // Ratio of bytes > 0x7F
    format_verdict: DensityFormatVerdict,
};

pub const DensityFormatVerdict = enum {
    PureTextKV, // JSON, XML, INI, YAML
    PaddedBinaryStruct, // C/C++ struct with null alignments
    HighDensityBinary, // Packed serialization (MessagePack, Protobuf, Flatbuffers)
    EncryptedOrCompressed, // Uniform byte noise
    SparseBuffer, // Dominated by null bytes
};

pub fn analyzeByteDensity(buffer: []const u8) DensityProfile {
    if (buffer.len == 0) {
        return .{
            .null_ratio = 0,
            .ascii_ratio = 0,
            .delim_ratio = 0,
            .high_byte_ratio = 0,
            .format_verdict = .SparseBuffer,
        };
    }

    var null_count: usize = 0;
    var ascii_count: usize = 0;
    var delim_count: usize = 0;
    var high_count: usize = 0;

    for (buffer) |b| {
        if (b == 0) {
            null_count += 1;
        } else if (b >= 0x20 and b <= 0x7E) {
            ascii_count += 1;
            if (b == '=' or b == ':' or b == '{' or b == '}' or b == '[' or b == ']' or b == ',' or b == ';' or b == '"' or b == '\'') {
                delim_count += 1;
            }
        } else if (b == '\t' or b == '\r' or b == '\n') {
            ascii_count += 1;
            delim_count += 1;
        } else if (b > 0x7F) {
            high_count += 1;
        }
    }

    const total: f32 = @floatFromInt(buffer.len);
    const null_ratio = @as(f32, @floatFromInt(null_count)) / total;
    const ascii_ratio = @as(f32, @floatFromInt(ascii_count)) / total;
    const delim_ratio = @as(f32, @floatFromInt(delim_count)) / total;
    const high_ratio = @as(f32, @floatFromInt(high_count)) / total;

    var verdict: DensityFormatVerdict = .HighDensityBinary;

    if (null_ratio > 0.60) {
        verdict = .SparseBuffer;
    } else if (ascii_ratio > 0.75 and delim_ratio > 0.05) {
        verdict = .PureTextKV;
    } else if (null_ratio > 0.15 and ascii_ratio > 0.20) {
        verdict = .PaddedBinaryStruct;
    } else if (high_ratio > 0.40 and null_ratio < 0.05) {
        verdict = .EncryptedOrCompressed;
    }

    return .{
        .null_ratio = null_ratio,
        .ascii_ratio = ascii_ratio,
        .delim_ratio = delim_ratio,
        .high_byte_ratio = high_ratio,
        .format_verdict = verdict,
    };
}

test "analyzeByteDensity on JSON vs binary struct" {
    const json_sample = "{\"player\": \"Sharabha\", \"gold\": 999999, \"level\": 100}";
    const profile_json = analyzeByteDensity(json_sample);
    try std.testing.expectEqual(DensityFormatVerdict.PureTextKV, profile_json.format_verdict);

    var struct_sample: [64]u8 = @splat(0);
    @memcpy(struct_sample[0..4], "HERO");
    std.mem.writeInt(u32, struct_sample[16..20], 5000, .little);
    const profile_struct = analyzeByteDensity(&struct_sample);
    try std.testing.expectEqual(DensityFormatVerdict.SparseBuffer, profile_struct.format_verdict);
}
