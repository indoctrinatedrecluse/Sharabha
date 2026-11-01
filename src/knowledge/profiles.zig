const std = @import("std");
const fuzzy = @import("../save/fuzzy.zig");

pub const KnownFieldRule = struct {
    offset: usize,
    key_name: []const u8,
    display_title: []const u8,
    sanskrit_title: []const u8,
    field_type: fuzzy.InferredType,
    min_value: i64,
    max_value: i64,
};

pub const GameProfile = struct {
    id: []const u8,
    title: []const u8,
    sanskrit_title: []const u8,
    filename_pattern: []const u8,
    magic_signature: ?[]const u8,
    rules: []const KnownFieldRule,

    pub fn matchesFile(self: *const GameProfile, filename: []const u8, header: []const u8) bool {
        // Match by filename suffix or exact name
        if (std.mem.indexOf(u8, filename, self.filename_pattern) != null) {
            return true;
        }
        // Match by magic signature
        if (self.magic_signature) |sig| {
            if (header.len >= sig.len and std.mem.eql(u8, header[0..sig.len], sig)) {
                return true;
            }
        }
        return false;
    }
};

// =============================================================================
// AGAMA PROFILES REGISTRY (प्रमाण आगम ग्रन्थ)
// =============================================================================

const ELDEN_RING_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x1A0,
        .key_name = "RUNES_SOULS",
        .display_title = "Held Runes (अर्जित भस्म)",
        .sanskrit_title = "अर्जित भस्म // RUNES",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999999999,
    },
    .{
        .offset = 0x1A4,
        .key_name = "LEVEL",
        .display_title = "Character Level (आत्म स्तर)",
        .sanskrit_title = "आत्म स्तर // LEVEL",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 713,
    },
    .{
        .offset = 0x1B0,
        .key_name = "VIGOR",
        .display_title = "Vigor Stat (प्राण शक्ति)",
        .sanskrit_title = "प्राण शक्ति // VIGOR",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99,
    },
};

const CYBERPUNK_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x48,
        .key_name = "EDDIES_MONEY",
        .display_title = "Eurodollars (धन मुद्रा)",
        .sanskrit_title = "धन मुद्रा // EDDIES",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .offset = 0x4C,
        .key_name = "STREET_CRED",
        .display_title = "Street Cred (ख्याति)",
        .sanskrit_title = "ख्याति // STREET CRED",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 50,
    },
};

const GENERIC_RPG_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x0C,
        .key_name = "HERO_GOLD",
        .display_title = "Treasury Gold (सुवर्ण निधि)",
        .sanskrit_title = "सुवर्ण निधि // GOLD",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .offset = 0x1C,
        .key_name = "HP_FLOAT",
        .display_title = "Vitality / HP (प्राण तत्त्व)",
        .sanskrit_title = "प्राण तत्त्व // VITALITY",
        .field_type = .Float32LE,
        .min_value = 1,
        .max_value = 999999,
    },
};

pub const BUILTIN_PROFILES = [_]GameProfile{
    .{
        .id = "elden_ring",
        .title = "Elden Ring (एल्डन रिंग)",
        .sanskrit_title = "एल्डन रिंग // LANDS BETWEEN",
        .filename_pattern = ".sl2",
        .magic_signature = "BND4",
        .rules = &ELDEN_RING_RULES,
    },
    .{
        .id = "cyberpunk2077",
        .title = "Cyberpunk 2077 (साइबरपंक २०७७)",
        .sanskrit_title = "साइबरपंक २०७७ // NIGHT CITY",
        .filename_pattern = "sav.dat",
        .magic_signature = null,
        .rules = &CYBERPUNK_RULES,
    },
    .{
        .id = "generic_rpg",
        .title = "Generic RPG Altar (सार्वभौम आगम)",
        .sanskrit_title = "सार्वभौम आगम // GENERIC RPG",
        .filename_pattern = ".sav",
        .magic_signature = null,
        .rules = &GENERIC_RPG_RULES,
    },
};

pub fn findMatchingProfile(filename: []const u8, header: []const u8) ?*const GameProfile {
    for (&BUILTIN_PROFILES) |*prof| {
        if (prof.matchesFile(filename, header)) {
            return prof;
        }
    }
    return null;
}

test "GameProfile matching" {
    const elden = findMatchingProfile("ER0000.sl2", "BND4\x00\x00");
    try std.testing.expect(elden != null);
    try std.testing.expectEqualStrings("elden_ring", elden.?.id);

    const generic = findMatchingProfile("player_hero.sav", "\x00\x00\x00\x00");
    try std.testing.expect(generic != null);
    try std.testing.expectEqualStrings("generic_rpg", generic.?.id);
}
