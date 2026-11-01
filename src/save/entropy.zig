const std = @import("std");

pub const RegionEntropyClass = enum {
    SparseOrText,     // < 3.8: plain text, null padding, simple tables
    StructuredBinary, // 3.8 - 7.2: binary structs, pointers, packed numeric data
    CompressedOrEncrypted, // > 7.2: zlib, lz4, gzip, encrypted payloads
};

pub const EntropySegment = struct {
    offset: usize,
    length: usize,
    entropy: f64,
    classification: RegionEntropyClass,
};

/// Calculates Shannon entropy for a given slice of bytes (returns 0.0 to 8.0 bits per byte)
pub fn calculateShannonEntropy(data: []const u8) f64 {
    if (data.len == 0) return 0.0;

    var frequencies: [256]usize = @splat(0);
    for (data) |byte| {
        frequencies[byte] += 1;
    }

    var entropy: f64 = 0.0;
    const len_f64: f64 = @floatFromInt(data.len);

    for (frequencies) |count| {
        if (count > 0) {
            const p = @as(f64, @floatFromInt(count)) / len_f64;
            entropy -= p * @log2(p);
        }
    }

    return entropy;
}

/// Classifies entropy value into domain categories
pub fn classifyEntropy(entropy: f64) RegionEntropyClass {
    if (entropy < 3.8) {
        return .SparseOrText;
    } else if (entropy <= 7.2) {
        return .StructuredBinary;
    } else {
        return .CompressedOrEncrypted;
    }
}

/// Analyzes an entire save game buffer by sliding window (e.g. 512 bytes)
pub fn analyzeBufferEntropy(
    allocator: std.mem.Allocator,
    data: []const u8,
    window_size: usize,
) ![]EntropySegment {
    if (data.len == 0) return &[_]EntropySegment{};

    const actual_window = @max(64, window_size);
    const num_segments = (data.len + actual_window - 1) / actual_window;
    var segments = try allocator.alloc(EntropySegment, num_segments);

    var offset: usize = 0;
    var seg_idx: usize = 0;

    while (offset < data.len) : (offset += actual_window) {
        const chunk_len = @min(actual_window, data.len - offset);
        const chunk = data[offset .. offset + chunk_len];
        const h = calculateShannonEntropy(chunk);

        segments[seg_idx] = .{
            .offset = offset,
            .length = chunk_len,
            .entropy = h,
            .classification = classifyEntropy(h),
        };
        seg_idx += 1;
    }

    return segments[0..seg_idx];
}

test "entropy of uniform zeros is zero" {
    const zeros: [1024]u8 = @splat(0);
    const h = calculateShannonEntropy(&zeros);
    try std.testing.expect(h == 0.0);
    try std.testing.expect(classifyEntropy(h) == .SparseOrText);
}

test "entropy of random bytes is high" {
    var prng = std.Random.DefaultPrng.init(0x1337);
    const random = prng.random();
    var random_bytes: [1024]u8 = undefined;
    random.bytes(&random_bytes);

    const h = calculateShannonEntropy(&random_bytes);
    try std.testing.expect(h > 7.0);
}
