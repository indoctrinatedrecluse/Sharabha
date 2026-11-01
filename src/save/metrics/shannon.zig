const std = @import("std");

pub const EntropyClassification = enum {
    SparseOrText,
    StructuredBinary,
    CompressedOrEncrypted,
};

/// Shannon Entropy: H(X) = - sum( P(x) * log2(P(x)) )
/// Output range: 0.0 (uniform single byte / empty) to 8.0 (pure uniform randomness / encryption / max compression)
pub fn calculateShannonEntropy(buffer: []const u8) f64 {
    if (buffer.len == 0) return 0.0;

    var frequencies: [256]usize = @splat(0);
    for (buffer) |byte| {
        frequencies[byte] += 1;
    }

    const total_bytes: f64 = @floatFromInt(buffer.len);
    var entropy: f64 = 0.0;

    for (frequencies) |count| {
        if (count == 0) continue;
        const p: f64 = @as(f64, @floatFromInt(count)) / total_bytes;
        entropy -= p * @log2(p);
    }

    return entropy;
}

pub fn classifyEntropy(entropy: f64) EntropyClassification {
    if (entropy < 3.8) {
        return .SparseOrText;
    } else if (entropy <= 7.2) {
        return .StructuredBinary;
    } else {
        return .CompressedOrEncrypted;
    }
}

test "Shannon Entropy bounds" {
    var zero_buf: [100]u8 = @splat(0);
    try std.testing.expectEqual(@as(f64, 0.0), calculateShannonEntropy(&zero_buf));

    var random_buf: [256]u8 = undefined;
    for (&random_buf, 0..) |*b, i| {
        b.* = @intCast(i);
    }
    const h = calculateShannonEntropy(&random_buf);
    try std.testing.expect(h > 7.9 and h <= 8.0);
    try std.testing.expectEqual(EntropyClassification.CompressedOrEncrypted, classifyEntropy(h));
}
