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
        // File extension matching alone is forbidden to avoid over-generalization:
        // .pcsav is shared by Mass Effect 1-3, Andromeda, Dragon Age, Death Stranding.
        // .dat and .json are generic containers used by thousands of games.
        // A deterministic profile requires BOTH signature verification (if specified)
        // AND specific game identity pattern verification.
        if (self.magic_signature) |sig| {
            if (header.len < sig.len or !std.mem.eql(u8, header[0..sig.len], sig)) {
                return false;
            }
        }
        if (self.filename_pattern.len > 0) {
            if (std.mem.indexOf(u8, filename, self.filename_pattern) == null) {
                return false;
            }
        }
        return (self.magic_signature != null or self.filename_pattern.len > 0);
    }
};

// =============================================================================
// AGAMA PROFILES REGISTRY (प्रमाण आगम ग्रन्थ)
// Deterministic parsing logic is ONLY an option for recognized games here.
// =============================================================================

const ELDEN_RING_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x0C,
        .key_name = "PLAYER_RUNES",
        .display_title = "Held Runes (अर्जित भस्म)",
        .sanskrit_title = "अर्जित भस्म // RUNES",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999999999,
    },
    .{
        .offset = 0x10,
        .key_name = "RUNE_LEVEL",
        .display_title = "Character Level (आत्म स्तर)",
        .sanskrit_title = "आत्म स्तर // LEVEL",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 713,
    },
    .{
        .offset = 0x14,
        .key_name = "VIGOR_HP",
        .display_title = "Vigor Stat (प्राण शक्ति)",
        .sanskrit_title = "प्राण शक्ति // VIGOR",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99,
    },
    .{
        .offset = 0x18,
        .key_name = "MIND_FP",
        .display_title = "Mind Stat (मनस् शक्ति)",
        .sanskrit_title = "मनस् शक्ति // MIND",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99,
    },
    .{
        .offset = 0x1C,
        .key_name = "ENDURANCE_STAMINA",
        .display_title = "Endurance Stat (धृति)",
        .sanskrit_title = "धृति // ENDURANCE",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99,
    },
};

const CYBERPUNK_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x08,
        .key_name = "EDDIES_CURRENCY",
        .display_title = "Eurodollars (धन मुद्रा)",
        .sanskrit_title = "धन मुद्रा // EDDIES",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .offset = 0x0C,
        .key_name = "STREET_CRED",
        .display_title = "Street Cred (ख्याति)",
        .sanskrit_title = "ख्याति // STREET CRED",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 50,
    },
    .{
        .offset = 0x10,
        .key_name = "ATTRIBUTE_BODY",
        .display_title = "Body Attribute (देह)",
        .sanskrit_title = "देह // BODY",
        .field_type = .Int32LE,
        .min_value = 3,
        .max_value = 20,
    },
    .{
        .offset = 0x14,
        .key_name = "ATTRIBUTE_REFLEXES",
        .display_title = "Reflexes Attribute (वेग)",
        .sanskrit_title = "वेग // REFLEXES",
        .field_type = .Int32LE,
        .min_value = 3,
        .max_value = 20,
    },
};

const MASS_EFFECT_RULES = [_]KnownFieldRule{
    .{
        .offset = 0x00,
        .key_name = "MAGIC_PACKAGE",
        .display_title = "BioWare Unreal Package Magic",
        .sanskrit_title = "माया लक्षण // MAGIC",
        .field_type = .UInt32LE,
        .min_value = 0,
        .max_value = std.math.maxInt(i64),
    },
    .{
        .offset = 0x08,
        .key_name = "COMPRESSED_SIZE",
        .display_title = "Compressed Payload Size (Bytes)",
        .sanskrit_title = "संपुट परिमाण // COMP_SIZE",
        .field_type = .UInt32LE,
        .min_value = 0,
        .max_value = 100000000,
    },
    .{
        .offset = 0x0C,
        .key_name = "DECOMPRESSED_CAPACITY",
        .display_title = "Decompressed Payload Capacity (Bytes)",
        .sanskrit_title = "विस्तार परिमाण // DECOMP_CAP",
        .field_type = .UInt32LE,
        .min_value = 0,
        .max_value = 100000000,
    },
};

pub const BUILTIN_PROFILES = [_]GameProfile{
    .{
        .id = "elden_ring",
        .title = "Elden Ring (एल्डन रिंग)",
        .sanskrit_title = "एल्डन रिंग // LANDS BETWEEN",
        .filename_pattern = "ER0000",
        .magic_signature = "BND4",
        .rules = &ELDEN_RING_RULES,
    },
    .{
        .id = "cyberpunk2077",
        .title = "Cyberpunk 2077 (साइबरपंक २०७७)",
        .sanskrit_title = "साइबरपंक २०७७ // NIGHT CITY",
        .filename_pattern = "sav.dat",
        .magic_signature = "CP77",
        .rules = &CYBERPUNK_RULES,
    },
    .{
        .id = "mass_effect_le",
        .title = "Mass Effect 1 LE (बायोवेयर प्रपत्र)",
        .sanskrit_title = "बायोवेयर प्रपत्र // MASS EFFECT",
        .filename_pattern = "ME1",
        .magic_signature = "\xC1\x83\x2A\x9E",
        .rules = &MASS_EFFECT_RULES,
    },
};

/// Returns a matching game profile only if the file is recognized in our deterministic knowledge base.
/// Unrecognized games return null, ensuring deterministic mode is only available for recognized games.
pub fn findMatchingProfile(filename: []const u8, header: []const u8) ?*const GameProfile {
    for (&BUILTIN_PROFILES) |*prof| {
        if (prof.matchesFile(filename, header)) {
            return prof;
        }
    }
    return null;
}

test "GameProfile matching - recognized vs unrecognized" {
    const elden = findMatchingProfile("ER0000.sl2", "BND4\x00\x00");
    try std.testing.expect(elden != null);
    try std.testing.expectEqualStrings("elden_ring", elden.?.id);

    // Specific Mass Effect 1 save path matches
    const me1 = findMatchingProfile("Save\\ME1\\Nyx00\\AutoSave.pcsav", "\xC1\x83\x2A\x9E\x00");
    try std.testing.expect(me1 != null);
    try std.testing.expectEqualStrings("mass_effect_le", me1.?.id);

    // Other games sharing .pcsav (e.g. Death Stranding, Dragon Age, or ME2/ME3) must NOT match ME1
    const death_stranding = findMatchingProfile("DeathStranding.pcsav", "\x00\x01\x02\x03\x04");
    try std.testing.expect(death_stranding == null);

    const dragon_age = findMatchingProfile("DragonAge_Save.pcsav", "\xC1\x83\x2A\x9E\x00");
    try std.testing.expect(dragon_age == null);

    // Other games sharing .dat must NOT match Cyberpunk
    const minecraft_dat = findMatchingProfile("level.dat", "\x1F\x8B\x08\x00");
    try std.testing.expect(minecraft_dat == null);

    // Unrecognized file must return null
    const unknown = findMatchingProfile("random_game.sav", "\x00\x01\x02\x03");
    try std.testing.expect(unknown == null);
}
