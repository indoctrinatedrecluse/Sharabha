//! ============================================================================
//! SHARABHA (शरभ) — STHITI RAKSHA (स्थिति रक्षा)
//! Universal Game Save Integrity & Checksum Recomputation Engine
//! Supports: CRC-32 (IEEE), Adler-32, MD5 (128-bit), Sum32, and XOR-8
//! ============================================================================

const std = @import("std");

pub const ChecksumAlgorithm = enum(u8) {
    Crc32 = 0,
    Adler32 = 1,
    Md5 = 2,
    Sum32 = 3,
    Xor8 = 4,
    Crc32Bzip2 = 5,
    Murmur3_32 = 6,

    pub fn getName(self: ChecksumAlgorithm) []const u8 {
        return switch (self) {
            .Crc32 => "CRC-32 (IEEE 802.3)",
            .Adler32 => "Adler-32 (Zlib)",
            .Md5 => "MD5 (128-bit FromSoftware)",
            .Sum32 => "Additive Sum-32",
            .Xor8 => "Rolling XOR-8",
            .Crc32Bzip2 => "CRC-32/BZIP2 (BioWare Unreal)",
            .Murmur3_32 => "MurmurHash3 (32-bit Capcom RE Engine)",
        };
    }

    pub fn getSanskritName(self: ChecksumAlgorithm) []const u8 {
        return switch (self) {
            .Crc32 => "चक्रव्यूह गणना (Chakravyuha)",
            .Adler32 => "आदित्य संक्षेप (Aditya)",
            .Md5 => "मृत्युंजय मुद्रा (Mrityunjaya)",
            .Sum32 => "योग संकलन (Yoga)",
            .Xor8 => "विलोम सूत्र (Viloma)",
            .Crc32Bzip2 => "ब्रह्म चक्र (Brahma Chakra)",
            .Murmur3_32 => "मर्म सूत्र (Marma Sutra)",
        };
    }
};

pub const ChecksumResult = union(ChecksumAlgorithm) {
    Crc32: u32,
    Adler32: u32,
    Md5: [16]u8,
    Sum32: u32,
    Xor8: u8,
    Crc32Bzip2: u32,
    Murmur3_32: u32,
};

pub const ChecksumTarget = struct {
    algorithm: ChecksumAlgorithm,
    payload_start: usize,
    payload_end: usize, // 0 = until end of buffer
    target_offset: usize, // where hash is stored in file
    is_little_endian: bool = true,
};

pub const ChecksumEngine = struct {
    pub fn computeCrc32(data: []const u8) u32 {
        return std.hash.Crc32.hash(data);
    }

    pub fn computeAdler32(data: []const u8) u32 {
        return std.hash.Adler32.hash(data);
    }

    pub fn computeMd5(data: []const u8) [16]u8 {
        var digest: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(data, &digest, .{});
        return digest;
    }

    pub fn computeSum32(data: []const u8) u32 {
        var sum: u32 = 0;
        var i: usize = 0;
        while (i + 4 <= data.len) : (i += 4) {
            sum +%= std.mem.readInt(u32, data[i..][0..4], .little);
        }
        while (i < data.len) : (i += 1) {
            sum +%= data[i];
        }
        return sum;
    }

    pub fn computeXor8(data: []const u8) u8 {
        var xor_acc: u8 = 0;
        for (data) |b| {
            xor_acc ^= b;
        }
        return xor_acc;
    }

    pub fn computeCrc32Bzip2(data: []const u8) u32 {
        var crc: u32 = 0xFFFFFFFF;
        const poly: u32 = 0x04C11DB7;
        for (data) |b| {
            crc ^= (@as(u32, b) << 24);
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                if ((crc & 0x80000000) != 0) {
                    crc = (crc << 1) ^ poly;
                } else {
                    crc = crc << 1;
                }
            }
        }
        return crc ^ 0xFFFFFFFF;
    }

    /// MurmurHash3 (32-bit x86, seed 0xFFFFFFFF) used in Capcom RE Engine (Dragon's Dogma 2, RE4, etc.)
    pub fn computeMurmur3_32(data: []const u8, seed: u32) u32 {
        const c1: u32 = 0xcc9e2d51;
        const c2: u32 = 0x1b873593;

        var h: u32 = seed;
        const nblocks = data.len / 4;

        var i: usize = 0;
        while (i < nblocks) : (i += 1) {
            var k = std.mem.readInt(u32, data[i * 4 ..][0..4], .little);
            k = k *% c1;
            k = std.math.rotl(u32, k, 15);
            k = k *% c2;

            h ^= k;
            h = std.math.rotl(u32, h, 13);
            h = h *% 5 +% 0xe6546b64;
        }

        // Tail
        const tail = data[nblocks * 4 ..];
        var k1: u32 = 0;
        if (tail.len >= 3) k1 ^= @as(u32, tail[2]) << 16;
        if (tail.len >= 2) k1 ^= @as(u32, tail[1]) << 8;
        if (tail.len >= 1) {
            k1 ^= @as(u32, tail[0]);
            k1 = k1 *% c1;
            k1 = std.math.rotl(u32, k1, 15);
            k1 = k1 *% c2;
            h ^= k1;
        }

        // Finalization
        h ^= @as(u32, @intCast(data.len));
        h ^= h >> 16;
        h = h *% 0x85ebca6b;
        h ^= h >> 13;
        h = h *% 0xc2b2ae35;
        h ^= h >> 16;

        return h;
    }

    pub fn compute(algo: ChecksumAlgorithm, data: []const u8) ChecksumResult {
        return switch (algo) {
            .Crc32 => .{ .Crc32 = computeCrc32(data) },
            .Adler32 => .{ .Adler32 = computeAdler32(data) },
            .Md5 => .{ .Md5 = computeMd5(data) },
            .Sum32 => .{ .Sum32 = computeSum32(data) },
            .Xor8 => .{ .Xor8 = computeXor8(data) },
            .Crc32Bzip2 => .{ .Crc32Bzip2 = computeCrc32Bzip2(data) },
            .Murmur3_32 => .{ .Murmur3_32 = computeMurmur3_32(data, 0xFFFFFFFF) },
        };
    }

    /// Verifies if the stored checksum at target_offset matches the payload data
    pub fn verify(target: ChecksumTarget, data: []const u8) bool {
        const end = if (target.payload_end == 0 or target.payload_end > data.len) data.len else target.payload_end;
        if (target.payload_start >= end or end > data.len) return false;
        const payload = data[target.payload_start..end];

        switch (target.algorithm) {
            .Crc32 => {
                if (target.target_offset + 4 > data.len) return false;
                const expected = computeCrc32(payload);
                const stored = if (target.is_little_endian)
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .little)
                else
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .big);
                return expected == stored;
            },
            .Crc32Bzip2 => {
                if (target.target_offset + 4 > data.len) return false;
                const expected = computeCrc32Bzip2(payload);
                const stored = if (target.is_little_endian)
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .little)
                else
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .big);
                return expected == stored;
            },
            .Adler32 => {
                if (target.target_offset + 4 > data.len) return false;
                const expected = computeAdler32(payload);
                const stored = if (target.is_little_endian)
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .little)
                else
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .big);
                return expected == stored;
            },
            .Md5 => {
                if (target.target_offset + 16 > data.len) return false;
                const expected = computeMd5(payload);
                return std.mem.eql(u8, &expected, data[target.target_offset..][0..16]);
            },
            .Sum32 => {
                if (target.target_offset + 4 > data.len) return false;
                const expected = computeSum32(payload);
                const stored = std.mem.readInt(u32, data[target.target_offset..][0..4], .little);
                return expected == stored;
            },
            .Xor8 => {
                if (target.target_offset >= data.len) return false;
                const expected = computeXor8(payload);
                return expected == data[target.target_offset];
            },
            .Murmur3_32 => {
                if (target.target_offset + 4 > data.len) return false;
                const expected = computeMurmur3_32(payload, 0xFFFFFFFF);
                const stored = if (target.is_little_endian)
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .little)
                else
                    std.mem.readInt(u32, data[target.target_offset..][0..4], .big);
                return expected == stored;
            },
        }
    }

    /// Automatically recomputes the checksum and writes it directly to data[target_offset]
    pub fn patch(target: ChecksumTarget, data: []u8) !void {
        const end = if (target.payload_end == 0 or target.payload_end > data.len) data.len else target.payload_end;
        if (target.payload_start >= end or end > data.len) return error.InvalidPayloadBounds;
        const payload = data[target.payload_start..end];

        switch (target.algorithm) {
            .Crc32 => {
                if (target.target_offset + 4 > data.len) return error.TargetOffsetOutOfBounds;
                const val = computeCrc32(payload);
                if (target.is_little_endian) {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .little);
                } else {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .big);
                }
            },
            .Crc32Bzip2 => {
                if (target.target_offset + 4 > data.len) return error.TargetOffsetOutOfBounds;
                const val = computeCrc32Bzip2(payload);
                if (target.is_little_endian) {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .little);
                } else {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .big);
                }
            },
            .Adler32 => {
                if (target.target_offset + 4 > data.len) return error.TargetOffsetOutOfBounds;
                const val = computeAdler32(payload);
                if (target.is_little_endian) {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .little);
                } else {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .big);
                }
            },
            .Md5 => {
                if (target.target_offset + 16 > data.len) return error.TargetOffsetOutOfBounds;
                const digest = computeMd5(payload);
                @memcpy(data[target.target_offset..][0..16], &digest);
            },
            .Sum32 => {
                if (target.target_offset + 4 > data.len) return error.TargetOffsetOutOfBounds;
                const val = computeSum32(payload);
                std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .little);
            },
            .Xor8 => {
                if (target.target_offset >= data.len) return error.TargetOffsetOutOfBounds;
                data[target.target_offset] = computeXor8(payload);
            },
            .Murmur3_32 => {
                if (target.target_offset + 4 > data.len) return error.TargetOffsetOutOfBounds;
                const val = computeMurmur3_32(payload, 0xFFFFFFFF);
                if (target.is_little_endian) {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .little);
                } else {
                    std.mem.writeInt(u32, data[target.target_offset..][0..4], val, .big);
                }
            },
        }
    }

    /// Auto-detects game save type by extension and patches appropriate integrity seals
    pub fn autoPatchKnownFormat(file_ext: []const u8, data: []u8) !?ChecksumAlgorithm {
        // Capcom RE Engine saves (Dragon's Dogma 2, RE4, MH Wilds): DSSS container with trailing 4-byte Murmur3
        if (data.len >= 16 and std.mem.eql(u8, data[0..4], "DSSS")) {
            const payload_len = data.len - 4;
            try patch(.{
                .algorithm = .Murmur3_32,
                .payload_start = 0,
                .payload_end = payload_len,
                .target_offset = payload_len,
                .is_little_endian = true,
            }, data);
            return .Murmur3_32;
        }
        // Elden Ring (.sl2): 16-byte MD5 header at slot block 0x300
        if (std.mem.eql(u8, file_ext, ".sl2")) {
            if (data.len >= 0x400) {
                try patch(.{
                    .algorithm = .Md5,
                    .payload_start = 0x310,
                    .payload_end = 0,
                    .target_offset = 0x300,
                }, data);
                return .Md5;
            }
        }

        // Cyberpunk 2077 (.dat): CRC32 at footer or header
        if (std.mem.eql(u8, file_ext, ".dat")) {
            if (data.len >= 12) {
                try patch(.{
                    .algorithm = .Crc32,
                    .payload_start = 8,
                    .payload_end = 0,
                    .target_offset = 4,
                }, data);
                return .Crc32;
            }
        }

        // Unreal Engine (.sav / GVAS): CRC32 header
        if (std.mem.eql(u8, file_ext, ".sav")) {
            if (data.len >= 16 and std.mem.eql(u8, data[0..4], "GVAS")) {
                try patch(.{
                    .algorithm = .Crc32,
                    .payload_start = 8,
                    .payload_end = 0,
                    .target_offset = 4,
                }, data);
                return .Crc32;
            }
        }

        // Mass Effect Legendary Edition (.pcsav): CRC32/BZIP2 footer (LE2 / LE3)
        if (std.mem.eql(u8, file_ext, ".pcsav") or std.mem.eql(u8, file_ext, ".PCSAV")) {
            if (data.len >= 16) {
                const ver = std.mem.readInt(i32, data[0..4], .little);
                // MELE2 is ver 30, MELE3 is ver 59
                if (ver == 30 or ver == 59) {
                    try patch(.{
                        .algorithm = .Crc32Bzip2,
                        .payload_start = 0,
                        .payload_end = data.len - 4,
                        .target_offset = data.len - 4,
                        .is_little_endian = true,
                    }, data);
                    return .Crc32Bzip2;
                }
            }
        }

        return null;
    }
};

test "ChecksumEngine - CRC32, Adler32, MD5 and Patching" {
    var buffer: [64]u8 = @splat(0);
    @memcpy(buffer[8..24], "SHARABHA_SAVE_10");

    const target = ChecksumTarget{
        .algorithm = .Crc32,
        .payload_start = 8,
        .payload_end = 24,
        .target_offset = 0,
    };

    try ChecksumEngine.patch(target, &buffer);
    const verified = ChecksumEngine.verify(target, &buffer);
    try std.testing.expect(verified);

    // Test MD5
    const md5_target = ChecksumTarget{
        .algorithm = .Md5,
        .payload_start = 16,
        .payload_end = 32,
        .target_offset = 32,
    };
    try ChecksumEngine.patch(md5_target, &buffer);
    try std.testing.expect(ChecksumEngine.verify(md5_target, &buffer));

    // Test Adler32
    const adler_target = ChecksumTarget{
        .algorithm = .Adler32,
        .payload_start = 8,
        .payload_end = 24,
        .target_offset = 48,
    };
    try ChecksumEngine.patch(adler_target, &buffer);
    try std.testing.expect(ChecksumEngine.verify(adler_target, &buffer));

    // Test Crc32Bzip2 (BioWare Unreal Engine)
    const bzip2_target = ChecksumTarget{
        .algorithm = .Crc32Bzip2,
        .payload_start = 8,
        .payload_end = 24,
        .target_offset = 52,
    };
    try ChecksumEngine.patch(bzip2_target, &buffer);
    try std.testing.expect(ChecksumEngine.verify(bzip2_target, &buffer));

    // Test Murmur3_32 (Capcom RE Engine)
    const murmur_target = ChecksumTarget{
        .algorithm = .Murmur3_32,
        .payload_start = 8,
        .payload_end = 24,
        .target_offset = 56,
        .is_little_endian = true,
    };
    try ChecksumEngine.patch(murmur_target, &buffer);
    try std.testing.expect(ChecksumEngine.verify(murmur_target, &buffer));

    // Test autoPatchKnownFormat with DSSS Capcom container
    var dsss_buf: [32]u8 = undefined;
    @memcpy(dsss_buf[0..4], "DSSS");
    std.mem.writeInt(u32, dsss_buf[4..8], 2, .little); // Version 2
    @memset(dsss_buf[8..28], 0x42);
    @memset(dsss_buf[28..32], 0x00); // Checksum space

    const algo = try ChecksumEngine.autoPatchKnownFormat(".bin", &dsss_buf);
    try std.testing.expect(algo != null);
    try std.testing.expectEqual(ChecksumAlgorithm.Murmur3_32, algo.?);
    // Verify that the patched checksum matches
    const dsss_verify = ChecksumEngine.verify(.{
        .algorithm = .Murmur3_32,
        .payload_start = 0,
        .payload_end = 28,
        .target_offset = 28,
        .is_little_endian = true,
    }, &dsss_buf);
    try std.testing.expect(dsss_verify);
}
