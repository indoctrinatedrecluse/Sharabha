const std = @import("std");

/// Jnana Kosha (ज्ञानकोश — Sheath of Knowledge)
/// Embedded Multi-Model Knowledge Graph Engine adhering to SurrealQL schema & graph semantics.
/// Persists games, known save structures, pointer paths, and Kavacha rules.

pub const GameNode = struct {
    id: []const u8, // e.g. "game:elden_ring"
    title: []const u8, // "Elden Ring"
    sanskrit_name: []const u8, // "एल्डन वलय"
    executable: []const u8, // "eldenring.exe"
};

pub const SaveProfileNode = struct {
    id: []const u8, // e.g. "save_profile:elden_sl2"
    game_id: []const u8, // "game:elden_ring"
    file_extension: []const u8, // ".sl2"
    default_metric: []const u8, // "ChiSquare"
    default_extractor: []const u8, // "HybridAgama"
    description: []const u8, // "FromSoftware BND4 Container"
};

pub const PointerPathNode = struct {
    id: []const u8, // e.g. "pointer_path:elden_runes"
    game_id: []const u8, // "game:elden_ring"
    name: []const u8, // "Hero Runes / Currency"
    sanskrit_title: []const u8, // "नायक धनम्"
    module_name: []const u8, // "eldenring.exe"
    base_offset: usize, // e.g. 0x03C5A810
    level_offsets: [4]usize, // Multi-level dereferencing offsets
    levels_count: usize,
};

pub const KavachaRuleNode = struct {
    id: []const u8, // e.g. "kavacha:checksum_md5"
    game_id: []const u8,
    rule_name: []const u8, // "Enforce 16-byte MD5 Header Checksum"
    sanskrit_title: []const u8, // "कवच रक्षा विधि"
    enabled: bool,
};

pub const JnanaKosha = struct {
    allocator: std.mem.Allocator,
    games: std.ArrayList(GameNode),
    save_profiles: std.ArrayList(SaveProfileNode),
    pointer_paths: std.ArrayList(PointerPathNode),
    kavacha_rules: std.ArrayList(KavachaRuleNode),

    pub fn init(allocator: std.mem.Allocator) JnanaKosha {
        var kosha = JnanaKosha{
            .allocator = allocator,
            .games = .empty,
            .save_profiles = .empty,
            .pointer_paths = .empty,
            .kavacha_rules = .empty,
        };

        kosha.seedCanonicalKnowledge() catch {};
        return kosha;
    }

    pub fn deinit(self: *JnanaKosha) void {
        self.games.deinit(self.allocator);
        self.save_profiles.deinit(self.allocator);
        self.pointer_paths.deinit(self.allocator);
        self.kavacha_rules.deinit(self.allocator);
    }

    /// Seed the canonical Vedic and AAA gaming knowledge graph into the embedded SurrealQL store
    pub fn seedCanonicalKnowledge(self: *JnanaKosha) !void {
        // [1] Elden Ring
        try self.games.append(self.allocator, .{
            .id = "game:elden_ring",
            .title = "Elden Ring",
            .sanskrit_name = "एल्डन वलय // हिरण्यगर्भ",
            .executable = "eldenring.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:elden_ring_sl2",
            .game_id = "game:elden_ring",
            .file_extension = ".sl2",
            .default_metric = "ChiSquare",
            .default_extractor = "HybridAgama",
            .description = "BND4 Archive with MD5 checksum and 10 character slots",
        });

        try self.pointer_paths.append(self.allocator, .{
            .id = "pointer:elden_runes",
            .game_id = "game:elden_ring",
            .name = "Player Runes (मृत्युंजय धन)",
            .sanskrit_title = "नायक धनम्",
            .module_name = "eldenring.exe",
            .base_offset = 0x03C5A810,
            .level_offsets = .{ 0x10, 0x68, 0x18, 0x00 },
            .levels_count = 3,
        });

        try self.kavacha_rules.append(self.allocator, .{
            .id = "kavacha:elden_md5",
            .game_id = "game:elden_ring",
            .rule_name = "Recompute MD5 Checksum at Offset 0x0000..0x0010",
            .sanskrit_title = "मुद्रा शुद्धि // MD5 संस्कार",
            .enabled = true,
        });

        // [2] Cyberpunk 2077
        try self.games.append(self.allocator, .{
            .id = "game:cyberpunk_2077",
            .title = "Cyberpunk 2077",
            .sanskrit_name = "माया नगरी २०७७ // कलियुग",
            .executable = "Cyberpunk2077.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:cyberpunk_dat",
            .game_id = "game:cyberpunk_2077",
            .file_extension = ".dat",
            .default_metric = "Density",
            .default_extractor = "RecordTable",
            .description = "REDengine Sav.dat with Node table and CRC32 footer",
        });

        try self.pointer_paths.append(self.allocator, .{
            .id = "pointer:cyberpunk_eddies",
            .game_id = "game:cyberpunk_2077",
            .name = "Eurodollars (Eddies / सुवर्ण मुद्रा)",
            .sanskrit_title = "सुवर्ण कोश",
            .module_name = "Cyberpunk2077.exe",
            .base_offset = 0x0419B220,
            .level_offsets = .{ 0x30, 0x140, 0x28, 0x00 },
            .levels_count = 3,
        });

        // [3] Generic Indie / Unreal RPG
        try self.games.append(self.allocator, .{
            .id = "game:unreal_rpg",
            .title = "Unreal Engine Game",
            .sanskrit_name = "अतुल्य क्रीडा // मायावी",
            .executable = "Game-Win64-Shipping.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:unreal_gvas",
            .game_id = "game:unreal_rpg",
            .file_extension = ".sav",
            .default_metric = "ShannonEntropy",
            .default_extractor = "BinaryTLV",
            .description = "GVAS Header with tagged property reflection",
        });
    }

    /// Auto-discover game profile and pointer routes by active process executable name
    pub fn findGameByExecutable(self: *const JnanaKosha, exe_name: []const u8) ?GameNode {
        for (self.games.items) |g| {
            if (std.ascii.eqlIgnoreCase(g.executable, exe_name)) {
                return g;
            }
        }
        return null;
    }

    /// Auto-discover save profile and recommended parsing metrics by file extension
    pub fn findSaveProfileByExtension(self: *const JnanaKosha, file_path: []const u8) ?SaveProfileNode {
        for (self.save_profiles.items) |p| {
            if (std.mem.endsWith(u8, file_path, p.file_extension)) {
                return p;
            }
        }
        return null;
    }

    /// Retrieve all graph-connected pointer paths for a specific game
    pub fn getPointersForGame(self: *const JnanaKosha, game_id: []const u8, out_buf: []PointerPathNode) usize {
        var count: usize = 0;
        for (self.pointer_paths.items) |ptr| {
            if (std.mem.eql(u8, ptr.game_id, game_id)) {
                if (count < out_buf.len) {
                    out_buf[count] = ptr;
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Export the entire knowledge graph as standard SurrealQL statements
    pub fn exportSurrealQL(self: *const JnanaKosha, list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        var buf: [512]u8 = undefined;

        try list.appendSlice(allocator,
            \\-- ========================================================
            \\-- SHARABHA JNANA KOSHA // SURREALQL GRAPH EXPORT
            \\-- ॐ नमः शरभाय // Embedded Knowledge Graph Schema
            \\-- ========================================================
            \\
            \\DEFINE TABLE game SCHEMALESS;
            \\DEFINE TABLE save_profile SCHEMALESS;
            \\DEFINE TABLE pointer_path SCHEMALESS;
            \\DEFINE TABLE has_profile SCHEMALESS;
            \\DEFINE TABLE has_pointer SCHEMALESS;
            \\
            \\
        );

        // Insert Games
        for (self.games.items) |g| {
            const line = try std.fmt.bufPrint(&buf, "CREATE {s} SET title = '{s}', sanskrit = '{s}', executable = '{s}';\n", .{
                g.id, g.title, g.sanskrit_name, g.executable,
            });
            try list.appendSlice(allocator, line);
        }
        try list.appendSlice(allocator, "\n");

        // Insert Save Profiles & Relate
        for (self.save_profiles.items) |sp| {
            const line1 = try std.fmt.bufPrint(&buf, "CREATE {s} SET ext = '{s}', metric = '{s}', extractor = '{s}', desc = '{s}';\n", .{
                sp.id, sp.file_extension, sp.default_metric, sp.default_extractor, sp.description,
            });
            try list.appendSlice(allocator, line1);

            const line2 = try std.fmt.bufPrint(&buf, "RELATE {s}->has_profile->{s};\n", .{ sp.game_id, sp.id });
            try list.appendSlice(allocator, line2);
        }
        try list.appendSlice(allocator, "\n");

        // Insert Pointer Paths & Relate
        for (self.pointer_paths.items) |pp| {
            const line1 = try std.fmt.bufPrint(&buf, "CREATE {s} SET name = '{s}', module = '{s}', base = 0x{X};\n", .{
                pp.id, pp.name, pp.module_name, pp.base_offset,
            });
            try list.appendSlice(allocator, line1);

            const line2 = try std.fmt.bufPrint(&buf, "RELATE {s}->has_pointer->{s};\n", .{ pp.game_id, pp.id });
            try list.appendSlice(allocator, line2);
        }
        try list.appendSlice(allocator, "\n-- End of SurrealQL Knowledge Graph Seed\n");
    }
};

test "Jnana Kosha embedded graph discovery and SurrealQL export" {
    var kosha = JnanaKosha.init(std.testing.allocator);
    defer kosha.deinit();

    // Verify auto-discovery by executable
    const game = kosha.findGameByExecutable("eldenring.exe");
    try std.testing.expect(game != null);
    try std.testing.expectEqualStrings("Elden Ring", game.?.title);

    // Verify auto-discovery of save profile by extension
    const profile = kosha.findSaveProfileByExtension("my_character.sl2");
    try std.testing.expect(profile != null);
    try std.testing.expectEqualStrings("ChiSquare", profile.?.default_metric);
    try std.testing.expectEqualStrings("HybridAgama", profile.?.default_extractor);

    // Verify graph pointer relations
    var ptrs: [4]PointerPathNode = undefined;
    const ptr_count = kosha.getPointersForGame("game:elden_ring", &ptrs);
    try std.testing.expectEqual(@as(usize, 1), ptr_count);
    try std.testing.expectEqual(@as(usize, 0x03C5A810), ptrs[0].base_offset);

    // Verify SurrealQL generation
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try kosha.exportSurrealQL(&list, std.testing.allocator);

    const surreal_text = list.items;
    try std.testing.expect(std.mem.indexOf(u8, surreal_text, "CREATE game:elden_ring") != null);
    try std.testing.expect(std.mem.indexOf(u8, surreal_text, "RELATE game:elden_ring->has_profile->save_profile:elden_ring_sl2") != null);
}
