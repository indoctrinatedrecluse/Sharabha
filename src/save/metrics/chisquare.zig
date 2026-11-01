const std = @import("std");

pub const ChiSquareClassification = enum {
    UniformRandomOrEncrypted, // Chi-square close to degrees of freedom (255)
    StructuredBinary, // Moderate non-uniformity
    HighlyStructuredOrText, // Extreme deviation from uniform
};

/// Pearson's Chi-Square Test against uniform byte distribution
/// Degrees of freedom = 255.
pub fn calculateChiSquare(buffer: []const u8) f64 {
    if (buffer.len < 256) return 0.0;

    var observed: [256]f64 = @splat(0.0);
    for (buffer) |byte| {
        observed[byte] += 1.0;
    }

    const expected: f64 = @as(f64, @floatFromInt(buffer.len)) / 256.0;
    var chi_square: f64 = 0.0;

    for (observed) |obs| {
        const diff = obs - expected;
        chi_square += (diff * diff) / expected;
    }

    return chi_square;
}

pub fn classifyChiSquare(chi_square: f64, buffer_len: usize) ChiSquareClassification {
    if (buffer_len < 256) return .HighlyStructuredOrText;

    // Chi-square 99% critical value for 255 DoF is approx 310.
    if (chi_square < 320.0) {
        return .UniformRandomOrEncrypted;
    } else if (chi_square < 2500.0) {
        return .StructuredBinary;
    } else {
        return .HighlyStructuredOrText;
    }
}

test "Chi-Square on uniform vs repetitive data" {
    // 256 repetitions of 0..255 (perfect uniform distribution)
    var uniform: [256 * 4]u8 = undefined;
    for (0..4) |chunk| {
        for (0..256) |b| {
            uniform[chunk * 256 + b] = @intCast(b);
        }
    }
    const chi_uniform = calculateChiSquare(&uniform);
    try std.testing.expectEqual(@as(f64, 0.0), chi_uniform);
    try std.testing.expectEqual(ChiSquareClassification.UniformRandomOrEncrypted, classifyChiSquare(chi_uniform, uniform.len));

    // Structured text data
    const text_data = "PLAYER_NAME=Shiva;GOLD=999999;LEVEL=50;HEALTH=100.00;MANA=500.00;ACTIVE=1;" ++
        "PLAYER_NAME=Shiva;GOLD=999999;LEVEL=50;HEALTH=100.00;MANA=500.00;ACTIVE=1;" ++
        "PLAYER_NAME=Shiva;GOLD=999999;LEVEL=50;HEALTH=100.00;MANA=500.00;ACTIVE=1;" ++
        "PLAYER_NAME=Shiva;GOLD=999999;LEVEL=50;HEALTH=100.00;MANA=500.00;ACTIVE=1;";
    const chi_text = calculateChiSquare(text_data);
    try std.testing.expect(chi_text > 1000.0);
    try std.testing.expectEqual(ChiSquareClassification.HighlyStructuredOrText, classifyChiSquare(chi_text, text_data.len));
}
