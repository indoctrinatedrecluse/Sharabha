//! ============================================================================
//! SHARABHA (शरभ) — AGAMA DETERMINISTIC KNOWLEDGE REGISTRY [WIP]
//! Deterministic game-specific parsing logic will be added on a game-by-game basis.
//! The universal Fuzzy Engine (Pravaha Sūkshma Rekha) serves as the primary parser.
//! ============================================================================

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

/// Deterministic profiles registry is currently WIP (कार्य प्रगति पर है).
/// Game-by-game profiles, recognition logic, and variable highlights will be
/// provided on an explicit game-by-game basis.
pub const BUILTIN_PROFILES = [_]GameProfile{};

/// Returns a matching profile if one has been registered for this specific game.
/// Returns null for now (WIP) so the engine defaults exclusively to the universal fuzzy engine.
pub fn findMatchingProfile(filename: []const u8, header: []const u8) ?*const GameProfile {
    for (&BUILTIN_PROFILES) |*prof| {
        if (prof.matchesFile(filename, header)) {
            return prof;
        }
    }
    return null;
}

test "Agama Profiles schema - WIP clean registry" {
    // Builtin profiles is empty until game-specific parsing logic is provided
    try std.testing.expectEqual(@as(usize, 0), BUILTIN_PROFILES.len);

    const match = findMatchingProfile("any_save.dat", "DATA");
    try std.testing.expect(match == null);
}
