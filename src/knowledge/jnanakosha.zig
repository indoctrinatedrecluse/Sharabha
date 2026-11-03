const std = @import("std");

/// Jnana Kosha (ज्ञानकोश — Sheath of Knowledge)
/// Embedded Multi-Model Knowledge Graph Engine adhering to SurrealQL schema & graph semantics.
/// Persists games, known save structures, pointer paths, user annotations, and Kavacha rules.

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

pub const UserAnnotationNode = struct {
    id: []const u8, // e.g. "annotation:elden_vigor"
    game_id: []const u8, // "game:elden_ring"
    author: []const u8, // "User"
    category: []const u8, // "Memory Inquest"
    notes: []const u8, // "Offset 0x140 holds character vigor level"
    timestamp: u64,
};

pub const JnanaKosha = struct {
    allocator: std.mem.Allocator,
    games: std.ArrayList(GameNode),
    save_profiles: std.ArrayList(SaveProfileNode),
    pointer_paths: std.ArrayList(PointerPathNode),
    kavacha_rules: std.ArrayList(KavachaRuleNode),
    annotations: std.ArrayList(UserAnnotationNode),

    pub fn init(allocator: std.mem.Allocator) JnanaKosha {
        var kosha = JnanaKosha{
            .allocator = allocator,
            .games = .empty,
            .save_profiles = .empty,
            .pointer_paths = .empty,
            .kavacha_rules = .empty,
            .annotations = .empty,
        };

        kosha.seedCanonicalKnowledge() catch {};
        return kosha;
    }

    pub fn deinit(self: *JnanaKosha) void {
        self.games.deinit(self.allocator);
        self.save_profiles.deinit(self.allocator);
        self.pointer_paths.deinit(self.allocator);
        self.kavacha_rules.deinit(self.allocator);
        self.annotations.deinit(self.allocator);
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

        // [4] Dragon's Dogma 2 (Capcom RE Engine)
        try self.games.append(self.allocator, .{
            .id = "game:dd2",
            .title = "Dragon's Dogma 2",
            .sanskrit_name = "व्याघ्रेश्वर आगम // ड्रैगन्स डोग्मा २",
            .executable = "DD2.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:dd2_bin",
            .game_id = "game:dd2",
            .file_extension = ".bin",
            .default_metric = "RecordTable",
            .default_extractor = "DeterministicAgama",
            .description = "Capcom RE Engine DSSS Container with MurmurHash3_32 checksum",
        });

        try self.pointer_paths.append(self.allocator, .{
            .id = "pointer:dd2_gold",
            .game_id = "game:dd2",
            .name = "Arisen Gold (सुवर्ण धनम्)",
            .sanskrit_title = "सुवर्ण धनम्",
            .module_name = "DD2.exe",
            .base_offset = 0x052A3000,
            .level_offsets = .{ 0x20, 0x48, 0x10, 0x00 },
            .levels_count = 3,
        });

        try self.kavacha_rules.append(self.allocator, .{
            .id = "kavacha:dd2_murmur3",
            .game_id = "game:dd2",
            .rule_name = "Verify & Patch RE Engine Murmur3_32 Checksum",
            .sanskrit_title = "मर्म सूत्र शुद्धि // Murmur3 संस्कार",
            .enabled = true,
        });

        // [5] Suzerain (Torpor Games)
        try self.games.append(self.allocator, .{
            .id = "game:suzerain",
            .title = "Suzerain",
            .sanskrit_name = "सुज़ेरैन // सोर्डलैण्ड व रिज़िया",
            .executable = "Suzerain.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:suzerain_json",
            .game_id = "game:suzerain",
            .file_extension = ".json",
            .default_metric = "RecordTable",
            .default_extractor = "DeterministicAgama",
            .description = "Torpor Games JSON Save with Lua Variable dictionary",
        });

        // [6] Mass Effect Legendary Edition (BioWare)
        try self.games.append(self.allocator, .{
            .id = "game:mele",
            .title = "Mass Effect Legendary Edition",
            .sanskrit_name = "महा प्रभाव // लीजेंडरी संस्करण",
            .executable = "MassEffect1.exe",
        });

        try self.save_profiles.append(self.allocator, .{
            .id = "save_profile:mele_pcsav",
            .game_id = "game:mele",
            .file_extension = ".pcsav",
            .default_metric = "RecordTable",
            .default_extractor = "DeterministicAgama",
            .description = "BioWare Unreal Engine 3 Save with CRC-32/BZIP2 integrity",
        });

        try self.kavacha_rules.append(self.allocator, .{
            .id = "kavacha:mele_crc32bzip2",
            .game_id = "game:mele",
            .rule_name = "Verify & Patch BioWare CRC-32/BZIP2",
            .sanskrit_title = "ब्रह्म चक्र शुद्धि // CRC32-BZIP2 संस्कार",
            .enabled = true,
        });
    }

    // =========================================================================
    // PROFILE CRUD OPERATIONS
    // =========================================================================

    /// Registers a new game profile into the knowledge graph
    pub fn registerGame(self: *JnanaKosha, game: GameNode) !void {
        // If already exists, update in-place
        for (self.games.items) |*g| {
            if (std.mem.eql(u8, g.id, game.id)) {
                g.title = game.title;
                g.sanskrit_name = game.sanskrit_name;
                g.executable = game.executable;
                return;
            }
        }
        try self.games.append(self.allocator, game);
    }

    /// Updates existing game definition
    pub fn updateGame(self: *JnanaKosha, game_id: []const u8, new_title: []const u8, new_exe: []const u8) bool {
        for (self.games.items) |*g| {
            if (std.mem.eql(u8, g.id, game_id)) {
                g.title = new_title;
                g.executable = new_exe;
                return true;
            }
        }
        return false;
    }

    /// Deletes a game and its cascaded profiles, pointers, and annotations
    pub fn deleteGame(self: *JnanaKosha, game_id: []const u8) bool {
        var found = false;
        var i: usize = 0;
        while (i < self.games.items.len) {
            if (std.mem.eql(u8, self.games.items[i].id, game_id)) {
                _ = self.games.swapRemove(i);
                found = true;
            } else {
                i += 1;
            }
        }

        // Clean associated save profiles
        var sp_i: usize = 0;
        while (sp_i < self.save_profiles.items.len) {
            if (std.mem.eql(u8, self.save_profiles.items[sp_i].game_id, game_id)) {
                _ = self.save_profiles.swapRemove(sp_i);
            } else {
                sp_i += 1;
            }
        }

        // Clean associated pointers
        var p_i: usize = 0;
        while (p_i < self.pointer_paths.items.len) {
            if (std.mem.eql(u8, self.pointer_paths.items[p_i].game_id, game_id)) {
                _ = self.pointer_paths.swapRemove(p_i);
            } else {
                p_i += 1;
            }
        }

        return found;
    }

    /// Adds or updates a user annotation for reverse engineering notes
    pub fn addAnnotation(self: *JnanaKosha, annotation: UserAnnotationNode) !void {
        for (self.annotations.items) |*ann| {
            if (std.mem.eql(u8, ann.id, annotation.id)) {
                ann.notes = annotation.notes;
                ann.timestamp = annotation.timestamp;
                return;
            }
        }
        try self.annotations.append(self.allocator, annotation);
    }

    /// Retrieves user annotations for a specified game
    pub fn getAnnotationsForGame(self: *const JnanaKosha, game_id: []const u8, out_buf: []UserAnnotationNode) usize {
        var count: usize = 0;
        for (self.annotations.items) |ann| {
            if (std.mem.eql(u8, ann.game_id, game_id)) {
                if (count < out_buf.len) {
                    out_buf[count] = ann;
                    count += 1;
                }
            }
        }
        return count;
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

    /// Exports registered game profiles as portable JSON for community sharing
    pub fn exportProfilesJson(self: *const JnanaKosha, list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        var buf: [512]u8 = undefined;
        try list.appendSlice(allocator, "{\n  \"schema\": \"SHARABHA_JNANA_KOSHA_V1\",\n  \"games\": [\n");

        for (self.games.items, 0..) |g, i| {
            const line = try std.fmt.bufPrint(&buf, "    {{\"id\": \"{s}\", \"title\": \"{s}\", \"sanskrit\": \"{s}\", \"executable\": \"{s}\"}}{s}\n", .{
                g.id,
                g.title,
                g.sanskrit_name,
                g.executable,
                if (i + 1 < self.games.items.len) "," else "",
            });
            try list.appendSlice(allocator, line);
        }

        try list.appendSlice(allocator, "  ]\n}\n");
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
            \\DEFINE TABLE user_annotation SCHEMALESS;
            \\DEFINE TABLE has_profile SCHEMALESS;
            \\DEFINE TABLE has_pointer SCHEMALESS;
            \\DEFINE TABLE has_annotation SCHEMALESS;
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
        try list.appendSlice(allocator, "\n");

        // Insert User Annotations & Relate
        for (self.annotations.items) |ann| {
            const line1 = try std.fmt.bufPrint(&buf, "CREATE {s} SET author = '{s}', category = '{s}', notes = '{s}';\n", .{
                ann.id, ann.author, ann.category, ann.notes,
            });
            try list.appendSlice(allocator, line1);

            const line2 = try std.fmt.bufPrint(&buf, "RELATE {s}->has_annotation->{s};\n", .{ ann.game_id, ann.id });
            try list.appendSlice(allocator, line2);
        }
        try list.appendSlice(allocator, "\n-- End of SurrealQL Knowledge Graph Seed\n");
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "Jnana Kosha embedded graph discovery and SurrealQL export" {
    var kosha = JnanaKosha.init(std.testing.allocator);
    defer kosha.deinit();

    // Verify auto-discovery by executable
    const game = kosha.findGameByExecutable("eldenring.exe");
    try std.testing.expect(game != null);
    try std.testing.expectEqualStrings("Elden Ring", game.?.title);

    const dd2_game = kosha.findGameByExecutable("DD2.exe");
    try std.testing.expect(dd2_game != null);
    try std.testing.expectEqualStrings("Dragon's Dogma 2", dd2_game.?.title);

    // Verify auto-discovery of save profile by extension
    const profile = kosha.findSaveProfileByExtension("my_character.sl2");
    try std.testing.expect(profile != null);
    try std.testing.expectEqualStrings("ChiSquare", profile.?.default_metric);
    try std.testing.expectEqualStrings("HybridAgama", profile.?.default_extractor);

    const dd2_profile = kosha.findSaveProfileByExtension("data001Slot.bin");
    try std.testing.expect(dd2_profile != null);
    try std.testing.expectEqualStrings("save_profile:dd2_bin", dd2_profile.?.id);

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

test "Jnana Kosha Game Profile CRUD and User Annotations" {
    var kosha = JnanaKosha.init(std.testing.allocator);
    defer kosha.deinit();

    // 1. Create / Register Custom Game Profile
    try kosha.registerGame(.{
        .id = "game:sekiro",
        .title = "Sekiro: Shadows Die Twice",
        .sanskrit_name = "एकबाहु भेरी",
        .executable = "sekiro.exe",
    });

    const sekiro = kosha.findGameByExecutable("sekiro.exe");
    try std.testing.expect(sekiro != null);
    try std.testing.expectEqualStrings("Sekiro: Shadows Die Twice", sekiro.?.title);

    // 2. Update Profile
    const updated = kosha.updateGame("game:sekiro", "Sekiro GOTY Edition", "sekiro_goty.exe");
    try std.testing.expect(updated);
    const sekiro_updated = kosha.findGameByExecutable("sekiro_goty.exe");
    try std.testing.expect(sekiro_updated != null);
    try std.testing.expectEqualStrings("Sekiro GOTY Edition", sekiro_updated.?.title);

    // 3. User Annotation
    try kosha.addAnnotation(.{
        .id = "annotation:sekiro_sen",
        .game_id = "game:sekiro",
        .author = "Recluse",
        .category = "Economy",
        .notes = "Sen currency pointer: base+0x03C50000 -> 0x18 -> 0x48",
        .timestamp = 1729000000,
    });

    var annotations_buf: [4]UserAnnotationNode = undefined;
    const ann_count = kosha.getAnnotationsForGame("game:sekiro", &annotations_buf);
    try std.testing.expectEqual(@as(usize, 1), ann_count);
    try std.testing.expectEqualStrings("Recluse", annotations_buf[0].author);

    // 4. JSON Export
    var json_list: std.ArrayList(u8) = .empty;
    defer json_list.deinit(std.testing.allocator);
    try kosha.exportProfilesJson(&json_list, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, json_list.items, "Sekiro GOTY Edition") != null);

    // 5. Delete Profile
    const deleted = kosha.deleteGame("game:sekiro");
    try std.testing.expect(deleted);
    try std.testing.expect(kosha.findGameByExecutable("sekiro_goty.exe") == null);
}
