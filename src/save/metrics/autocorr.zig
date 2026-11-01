const std = @import("std");

pub const StrideAnalysis = struct {
    detected_stride: usize, // 0 if no periodicity detected, else 8, 16, 32, 64 etc.
    confidence: f32, // 0.0 to 1.0
    estimated_record_count: usize,
};

/// Computes lagged byte correlation to detect repeating struct strides
pub fn detectStridePeriodicity(buffer: []const u8) StrideAnalysis {
    if (buffer.len < 128) {
        return .{
            .detected_stride = 0,
            .confidence = 0.0,
            .estimated_record_count = 0,
        };
    }

    const test_strides = [_]usize{ 8, 12, 16, 20, 24, 32, 48, 64, 128 };
    var best_stride: usize = 0;
    var best_score: f32 = 0.0;

    for (test_strides) |stride| {
        if (stride * 3 > buffer.len) continue;

        var matches: usize = 0;
        var total_comparisons: usize = 0;

        var i: usize = 0;
        while (i + stride < buffer.len) : (i += 1) {
            if (buffer[i] == buffer[i + stride]) {
                matches += 1;
            }
            total_comparisons += 1;
        }

        if (total_comparisons == 0) continue;
        const score = @as(f32, @floatFromInt(matches)) / @as(f32, @floatFromInt(total_comparisons));
        if (score > best_score and score > 0.35) {
            best_score = score;
            best_stride = stride;
        }
    }

    if (best_stride > 0) {
        return .{
            .detected_stride = best_stride,
            .confidence = best_score,
            .estimated_record_count = buffer.len / best_stride,
        };
    }

    return .{
        .detected_stride = 0,
        .confidence = 0.0,
        .estimated_record_count = 0,
    };
}

test "Stride periodicity detection on repeated structs" {
    // 32-byte repeating record structure
    var buffer: [32 * 8]u8 = undefined;
    for (0..8) |record_idx| {
        const base = record_idx * 32;
        @memcpy(buffer[base .. base + 4], "ITEM");
        std.mem.writeInt(u32, buffer[base + 4 ..][0..4], 100, .little);
        @memset(buffer[base + 8 .. base + 32], 0);
    }

    const analysis = detectStridePeriodicity(&buffer);
    try std.testing.expectEqual(@as(usize, 32), analysis.detected_stride);
    try std.testing.expect(analysis.confidence > 0.50);
}
