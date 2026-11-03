//! ============================================================================
//! SHARABHA (शरभ) — AGAMA & PRAVAHA DUAL-MODE SAVE PARSER
//! Blends Deterministic Agama Temple Profiles with Multi-Metric Fuzzy Inference
//! Sthiti Kavacha Backup & Automatic Checksum Recalculation Included
//! Deterministic parsing logic is ONLY an option for recognized games.
//! Includes full official support for Torpor Games' Suzerain (Sordland & Rizia).
//! ============================================================================

const std = @import("std");
const fuzzy = @import("fuzzy.zig");
const switcher = @import("switcher.zig");
const checksum = @import("checksum.zig");
const rewrite = @import("rewrite.zig");
const profiles = @import("../knowledge/profiles.zig");

pub const SaveViewMode = enum(u8) {
    AgamaDeterministic = 0, // Known game profiles with specific field cards & sliders
    PravahaFuzzyRaw = 1, // Unknown/unmapped heuristic field table with confidence & hex
};

pub const AgamaField = struct {
    id: []const u8,
    name: []const u8,
    sanskrit_name: []const u8,
    category: []const u8 = "General",
    offset: usize = 0,
    data_type: fuzzy.InferredType,
    int_value: i64 = 0,
    float_value: f32 = 0.0,
    bool_value: bool = false,
    string_value: [64]u8 = @splat(0),
    string_len: usize = 0,
    min_val: i64 = 0,
    max_val: i64 = 999999999,
    warning: ?[]const u8 = null,

    pub fn getString(self: *const AgamaField) []const u8 {
        return self.string_value[0..self.string_len];
    }
};

/// High-speed zero-copy value extractor for Suzerain key-value format:
/// Matches `[\"<key>\"]\s*=\s*(?<val>[^,\r\n\}\]]+)`
pub fn extractSuzerainValue(content: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [128]u8 = undefined;
    if (key.len + 6 > search_buf.len) return null;

    // First try standard on-disk escaped format: [\"<key>\"]
    var needle = std.fmt.bufPrint(&search_buf, "[\\\"{s}\\\"]", .{key}) catch return null;
    var needle_pos = std.mem.indexOf(u8, content, needle);

    // Fallback to unescaped format: ["<key>"]
    if (needle_pos == null) {
        needle = std.fmt.bufPrint(&search_buf, "[\"{s}\"]", .{key}) catch return null;
        needle_pos = std.mem.indexOf(u8, content, needle);
    }

    const pos = needle_pos orelse return null;
    var cursor = pos + needle.len;

    while (cursor < content.len and (content[cursor] == ' ' or content[cursor] == '\t')) : (cursor += 1) {}
    if (cursor >= content.len or content[cursor] != '=') return null;
    cursor += 1;
    while (cursor < content.len and (content[cursor] == ' ' or content[cursor] == '\t')) : (cursor += 1) {}

    const val_start = cursor;
    while (cursor < content.len) : (cursor += 1) {
        const c = content[cursor];
        if (c == ',' or c == '}' or c == ']' or c == '\r' or c == '\n' or c == ' ' or c == '\t') break;
    }

    if (cursor > val_start) {
        return content[val_start..cursor];
    }
    return null;
}

pub const DualModeSaveState = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file_extension: []const u8,
    raw_buffer: []u8,
    view_mode: SaveViewMode,

    // Agama deterministic fields (if profile matched)
    is_known_game: bool,
    is_key_based: bool,
    game_title: []const u8,
    sanskrit_title: []const u8,
    campaign_name: []const u8,
    agama_fields: std.ArrayList(AgamaField),

    // Pravaha fuzzy candidates (heuristic multi-metric extraction)
    fuzzy_results: std.ArrayList(fuzzy.InferredField),
    detected_metric_name: []const u8,
    detected_container: switcher.MetricChoice,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8, data: []const u8) !DualModeSaveState {
        const owned_data = try allocator.dupe(u8, data);
        const ext = std.fs.path.extension(file_path);

        var state = DualModeSaveState{
            .allocator = allocator,
            .file_path = file_path,
            .file_extension = ext,
            .raw_buffer = owned_data,
            .view_mode = .PravahaFuzzyRaw,
            .is_known_game = false,
            .is_key_based = false,
            .game_title = "Unknown Sthiti (अज्ञात)",
            .sanskrit_title = "प्रवाह रूप (Raw Stream)",
            .campaign_name = "",
            .agama_fields = .empty,
            .fuzzy_results = .empty,
            .detected_metric_name = "Auto-Detect",
            .detected_container = .Auto,
        };

        try state.analyzeAndPopulate();
        return state;
    }

    pub fn deinit(self: *DualModeSaveState) void {
        self.allocator.free(self.raw_buffer);
        self.agama_fields.deinit(self.allocator);
        self.fuzzy_results.deinit(self.allocator);
    }

    pub fn analyzeAndPopulate(self: *DualModeSaveState) !void {
        // 1. Run Fuzzy Multi-Metric Overseer Engine on the buffer (ranked by confidence descending)
        var sw_engine = switcher.SwitchingEngine.init(self.allocator);
        self.fuzzy_results.deinit(self.allocator);
        self.fuzzy_results = try sw_engine.extractFields(.Auto, self.raw_buffer, self.file_path);
        self.detected_metric_name = "Auto Heuristic Multi-Metric";

        // 2. Check Agama Knowledge Base for known games.
        // Deterministic parsing logic is ONLY an option if recognized in the knowledge base!
        self.agama_fields.clearRetainingCapacity();
        const check_slice = if (self.raw_buffer.len >= 8192) self.raw_buffer[0..8192] else self.raw_buffer;
        const matched_profile = profiles.findMatchingProfile(self.file_path, check_slice);

        if (matched_profile) |prof| {
            self.is_known_game = true;
            self.is_key_based = prof.is_key_based;
            self.game_title = prof.title;
            self.sanskrit_title = prof.sanskrit_title;
            self.campaign_name = prof.campaign_name;
            // For recognized games, deterministic mode is immediately primed
            self.view_mode = .AgamaDeterministic;

            if (prof.is_key_based) {
                // Key-value extraction for Suzerain Torpor engine
                for (prof.rules) |rule| {
                    var field = AgamaField{
                        .id = rule.key_name,
                        .name = rule.display_title,
                        .sanskrit_name = rule.sanskrit_title,
                        .category = rule.category,
                        .offset = 0,
                        .data_type = rule.field_type,
                        .int_value = 0,
                        .bool_value = false,
                        .string_value = @splat(0),
                        .string_len = 0,
                        .min_val = rule.min_value,
                        .max_val = rule.max_value,
                        .warning = rule.warning,
                    };

                    if (extractSuzerainValue(self.raw_buffer, rule.key_name)) |val_str| {
                        const copy_len = @min(val_str.len, 64);
                        @memcpy(field.string_value[0..copy_len], val_str[0..copy_len]);
                        field.string_len = copy_len;

                        if (std.mem.eql(u8, val_str, "true")) {
                            field.int_value = 1;
                            field.bool_value = true;
                        } else if (std.mem.eql(u8, val_str, "false")) {
                            field.int_value = 0;
                            field.bool_value = false;
                        } else if (std.fmt.parseInt(i64, val_str, 10)) |int_parsed| {
                            field.int_value = int_parsed;
                            field.bool_value = (int_parsed != 0);
                        } else |_| {}
                    }

                    try self.agama_fields.append(self.allocator, field);
                }
            } else {
                // Binary offset rules
                for (prof.rules) |rule| {
                    const int_val = if (rule.offset + 4 <= self.raw_buffer.len)
                        std.mem.readInt(i32, self.raw_buffer[rule.offset..][0..4], .little)
                    else
                        0;
                    try self.agama_fields.append(self.allocator, .{
                        .id = rule.key_name,
                        .name = rule.display_title,
                        .sanskrit_name = rule.sanskrit_title,
                        .category = rule.category,
                        .offset = rule.offset,
                        .data_type = rule.field_type,
                        .int_value = int_val,
                        .min_val = rule.min_value,
                        .max_val = rule.max_value,
                        .warning = rule.warning,
                    });
                }
            }
        } else {
            // Deterministic engine is WIP for unrecognized games; defaults to universal fuzzy engine.
            self.is_known_game = false;
            self.is_key_based = false;
            self.game_title = "Generic Binary Stream (सामान्य प्रपत्र)";
            self.sanskrit_title = "प्रवाह दर्शन (Pravaha Stream)";
            self.campaign_name = "";
            self.view_mode = .PravahaFuzzyRaw;
        }
    }

    /// Exact string/scalar replacement in key-based save files (Suzerain)
    pub fn setSuzerainVariable(self: *DualModeSaveState, key: []const u8, new_val_str: []const u8) !void {
        var search_buf: [128]u8 = undefined;
        if (key.len + 6 > search_buf.len) return error.KeyTooLong;

        var needle = std.fmt.bufPrint(&search_buf, "[\\\"{s}\\\"]", .{key}) catch return error.KeyTooLong;
        var needle_pos = std.mem.indexOf(u8, self.raw_buffer, needle);
        if (needle_pos == null) {
            needle = std.fmt.bufPrint(&search_buf, "[\"{s}\"]", .{key}) catch return error.KeyTooLong;
            needle_pos = std.mem.indexOf(u8, self.raw_buffer, needle);
        }

        const pos = needle_pos orelse return error.FieldNotFound;
        var cursor = pos + needle.len;
        while (cursor < self.raw_buffer.len and (self.raw_buffer[cursor] == ' ' or self.raw_buffer[cursor] == '\t')) : (cursor += 1) {}
        if (cursor >= self.raw_buffer.len or self.raw_buffer[cursor] != '=') return error.MalformedSaveFormat;
        cursor += 1;
        while (cursor < self.raw_buffer.len and (self.raw_buffer[cursor] == ' ' or self.raw_buffer[cursor] == '\t')) : (cursor += 1) {}

        const val_start = cursor;
        while (cursor < self.raw_buffer.len) : (cursor += 1) {
            const c = self.raw_buffer[cursor];
            if (c == ',' or c == '}' or c == ']' or c == '\r' or c == '\n' or c == ' ' or c == '\t') break;
        }
        const val_end = cursor;

        // Allocate replacement buffer
        const old_val_len = val_end - val_start;
        const new_total_len = self.raw_buffer.len - old_val_len + new_val_str.len;
        const new_buf = try self.allocator.alloc(u8, new_total_len);

        @memcpy(new_buf[0..val_start], self.raw_buffer[0..val_start]);
        @memcpy(new_buf[val_start .. val_start + new_val_str.len], new_val_str);
        @memcpy(new_buf[val_start + new_val_str.len ..], self.raw_buffer[val_end..]);

        self.allocator.free(self.raw_buffer);
        self.raw_buffer = new_buf;

        // Update in-memory field representation
        for (self.agama_fields.items) |*f| {
            if (std.mem.eql(u8, f.id, key)) {
                const copy_len = @min(new_val_str.len, 64);
                @memcpy(f.string_value[0..copy_len], new_val_str[0..copy_len]);
                f.string_len = copy_len;
                if (std.fmt.parseInt(i64, new_val_str, 10)) |num| {
                    f.int_value = num;
                    f.bool_value = (num != 0);
                } else |_| {
                    if (std.mem.eql(u8, new_val_str, "true")) {
                        f.int_value = 1;
                        f.bool_value = true;
                    } else if (std.mem.eql(u8, new_val_str, "false")) {
                        f.int_value = 0;
                        f.bool_value = false;
                    }
                }
                break;
            }
        }
    }

    /// Modifies a deterministic Agama field by ID and updates raw buffer
    pub fn setAgamaField(self: *DualModeSaveState, field_id: []const u8, new_value: i64) !void {
        if (self.is_known_game and self.is_key_based) {
            var num_buf: [32]u8 = undefined;
            const num_str = try std.fmt.bufPrint(&num_buf, "{d}", .{new_value});
            return self.setSuzerainVariable(field_id, num_str);
        }

        for (self.agama_fields.items) |*f| {
            if (std.mem.eql(u8, f.id, field_id)) {
                f.int_value = new_value;
                if (f.offset + 4 <= self.raw_buffer.len) {
                    std.mem.writeInt(i32, self.raw_buffer[f.offset..][0..4], @intCast(new_value), .little);
                }
                return;
            }
        }
        return error.FieldNotFound;
    }

    /// Modifies a raw fuzzy candidate offset
    pub fn setFuzzyRawInt32(self: *DualModeSaveState, offset: usize, new_value: i32) !void {
        if (offset + 4 > self.raw_buffer.len) return error.OffsetOutOfBounds;
        std.mem.writeInt(i32, self.raw_buffer[offset..][0..4], new_value, .little);
    }

    /// Commits the modified save with automatic Sthiti Kavacha backup and checksum recalculation
    pub fn commitWithIntegrity(self: *DualModeSaveState) !void {
        // 1. Recalculate checksums automatically
        _ = try checksum.ChecksumEngine.autoPatchKnownFormat(self.file_extension, self.raw_buffer);

        // 2. Safe rewrite with .sharabha.bak
        var rw = rewrite.SafeRewriteEngine.init(self.allocator);
        try rw.commitSafe(self.file_path, self.raw_buffer);
    }
};

test "DualModeSaveState - Deterministic Suzerain Rizia Profile Recognition and Modification" {
    const allocator = std.testing.allocator;

    const mock_suzerain_rizia =
        \\{
        \\    "currentStoryPack": "StoryPack_Rizia",
        \\    "campaignName": "NG1",
        \\    "variables": "Variable={[\"RiziaDLC.Resources_Budget\"]=12, [\"RiziaDLC.Resources_Authority\"]=7, [\"RiziaDLC.CountryRelation_Lespia_Friendly\"]=false}"
        \\}
    ;

    var state = try DualModeSaveState.init(allocator, "FinalSave_11-12-2025.json", mock_suzerain_rizia);
    defer state.deinit();

    try std.testing.expect(state.is_known_game);
    try std.testing.expect(state.is_key_based);
    try std.testing.expectEqual(SaveViewMode.AgamaDeterministic, state.view_mode);
    try std.testing.expectEqualStrings("SUZERAIN // Rizia DLC (King Romus Toras)", state.game_title);

    // Verify extracted Agama fields
    var found_budget = false;
    var found_authority = false;
    for (state.agama_fields.items) |f| {
        if (std.mem.eql(u8, f.id, "RiziaDLC.Resources_Budget")) {
            try std.testing.expectEqual(@as(i64, 12), f.int_value);
            try std.testing.expectEqualStrings("12", f.getString());
            found_budget = true;
        } else if (std.mem.eql(u8, f.id, "RiziaDLC.Resources_Authority")) {
            try std.testing.expectEqual(@as(i64, 7), f.int_value);
            try std.testing.expectEqualStrings("7", f.getString());
            found_authority = true;
        }
    }
    try std.testing.expect(found_budget);
    try std.testing.expect(found_authority);

    // Modify budget to 25 (max)
    try state.setAgamaField("RiziaDLC.Resources_Budget", 25);
    const updated_val = extractSuzerainValue(state.raw_buffer, "RiziaDLC.Resources_Budget");
    try std.testing.expect(updated_val != null);
    try std.testing.expectEqualStrings("25", updated_val.?);

    // Modify bool flag
    try state.setSuzerainVariable("RiziaDLC.CountryRelation_Lespia_Friendly", "true");
    const updated_flag = extractSuzerainValue(state.raw_buffer, "RiziaDLC.CountryRelation_Lespia_Friendly");
    try std.testing.expect(updated_flag != null);
    try std.testing.expectEqualStrings("true", updated_flag.?);
}

test "DualModeSaveState - Deterministic Suzerain Sordland Profile Recognition" {
    const allocator = std.testing.allocator;

    const mock_suzerain_sordland =
        \\{
        \\    "currentStoryPack": "StoryPack_Main",
        \\    "campaignName": "BaseGame",
        \\    "variables": "Variable={[\"BaseGame.GovernmentBudget\"]=3, [\"BaseGame.PersonalWealth\"]=8, [\"Albin_Convinced\"]=true}"
        \\}
    ;

    var state = try DualModeSaveState.init(allocator, "Active_01.json", mock_suzerain_sordland);
    defer state.deinit();

    try std.testing.expect(state.is_known_game);
    try std.testing.expect(state.is_key_based);
    try std.testing.expectEqual(SaveViewMode.AgamaDeterministic, state.view_mode);
    try std.testing.expectEqualStrings("SUZERAIN // Sordland (President Anton Rayne)", state.game_title);

    var budget_rule_found = false;
    for (state.agama_fields.items) |f| {
        if (std.mem.eql(u8, f.id, "BaseGame.GovernmentBudget")) {
            try std.testing.expectEqual(@as(i64, 3), f.int_value);
            try std.testing.expect(f.warning != null);
            budget_rule_found = true;
        }
    }
    try std.testing.expect(budget_rule_found);
}

test "DualModeSaveState - Real Suzerain FinalSave file verification" {
    const allocator = std.testing.allocator;
    const real_path = "D:\\Projects\\Suzerain-save-editor\\FinalSave_11-12-2025_22-14-25.json";

    const path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, real_path) catch return;
    defer allocator.free(path_w);

    const h_file = rewrite.win.CreateFileW(
        path_w.ptr,
        rewrite.win.GENERIC_READ,
        1, // FILE_SHARE_READ
        null,
        rewrite.win.OPEN_EXISTING,
        rewrite.win.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    if (h_file == rewrite.win.INVALID_HANDLE_VALUE) return; // Skip if file not found on current host
    defer _ = rewrite.win.CloseHandle(h_file);

    var high_size: u32 = 0;
    const low_size = rewrite.win.GetFileSize(h_file, &high_size);
    if (low_size == 0 or low_size == 0xFFFFFFFF) return;
    const read_len: usize = @min(@as(usize, low_size), 4 * 1024 * 1024);

    var bytes_read: u32 = 0;
    const test_buf = try allocator.alloc(u8, read_len);
    defer allocator.free(test_buf);
    _ = rewrite.win.ReadFile(h_file, test_buf.ptr, @intCast(test_buf.len), &bytes_read, null);

    if (bytes_read > 100) {
        var state = try DualModeSaveState.init(allocator, real_path, test_buf[0..bytes_read]);
        defer state.deinit();

        // Verify game title and campaign recognition
        try std.testing.expect(state.is_known_game);
        try std.testing.expect(state.is_key_based);
        try std.testing.expectEqualStrings("SUZERAIN // Rizia DLC (King Romus Toras)", state.game_title);
        try std.testing.expectEqualStrings("StoryPack_Rizia", state.campaign_name);
        try std.testing.expect(state.agama_fields.items.len >= 40);

        // Verify that key variables are extracted from real save
        var found_budget = false;
        for (state.agama_fields.items) |f| {
            if (std.mem.eql(u8, f.id, "RiziaDLC.Resources_Budget")) {
                found_budget = true;
                try std.testing.expect(f.string_len > 0);
            }
        }
        try std.testing.expect(found_budget);
    }
}

test "DualModeSaveState - Mass Effect Legendary Edition Recognition & Rejection of original ME2" {
    const allocator = std.testing.allocator;

    // 1. MELE1 (.pcsav with 0x9E2A83C1)
    const mele1_buf = [_]u8{ 0xC1, 0x83, 0x2A, 0x9E, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00 };
    var state1 = try DualModeSaveState.init(allocator, "Save_0001.pcsav", &mele1_buf);
    defer state1.deinit();
    try std.testing.expect(state1.is_known_game);
    try std.testing.expectEqual(SaveViewMode.AgamaDeterministic, state1.view_mode);
    try std.testing.expectEqualStrings("MASS EFFECT 1 // Legendary Edition (BioWare Unreal // प्रमाण आगम)", state1.game_title);
    try std.testing.expectEqual(@as(usize, 11), state1.agama_fields.items.len);

    // 2. MELE2 (.pcsav with version 30)
    const mele2_buf = [_]u8{ 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    var state2 = try DualModeSaveState.init(allocator, "Save_0002.pcsav", &mele2_buf);
    defer state2.deinit();
    try std.testing.expect(state2.is_known_game);
    try std.testing.expectEqual(SaveViewMode.AgamaDeterministic, state2.view_mode);
    try std.testing.expectEqualStrings("MASS EFFECT 2 // Legendary Edition (BioWare Unreal // प्रमाण आगम)", state2.game_title);
    try std.testing.expectEqual(@as(usize, 15), state2.agama_fields.items.len);

    // 3. MELE3 (.pcsav with version 59)
    const mele3_buf = [_]u8{ 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    var state3 = try DualModeSaveState.init(allocator, "Save_0003.pcsav", &mele3_buf);
    defer state3.deinit();
    try std.testing.expect(state3.is_known_game);
    try std.testing.expectEqual(SaveViewMode.AgamaDeterministic, state3.view_mode);
    try std.testing.expectEqualStrings("MASS EFFECT 3 // Legendary Edition (BioWare Unreal // प्रमाण आगम)", state3.game_title);
    try std.testing.expectEqual(@as(usize, 14), state3.agama_fields.items.len);

    // 4. Original ME2 (version 29): MUST NOT be treated as MELE, must fallback to PravahaFuzzyRaw
    const orig_me2_buf = [_]u8{ 0x1D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    var state_orig = try DualModeSaveState.init(allocator, "Save_0002.pcsav", &orig_me2_buf);
    defer state_orig.deinit();
    try std.testing.expect(!state_orig.is_known_game);
    try std.testing.expectEqual(SaveViewMode.PravahaFuzzyRaw, state_orig.view_mode);
}

