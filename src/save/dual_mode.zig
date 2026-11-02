//! ============================================================================
//! SHARABHA (शरभ) — AGAMA & PRAVAHA DUAL-MODE SAVE PARSER
//! Blends Deterministic Agama Temple Profiles with Multi-Metric Fuzzy Inference
//! Sthiti Kavacha Backup & Automatic Checksum Recalculation Included
//! Deterministic parsing logic is ONLY an option for recognized games.
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
    offset: usize,
    data_type: fuzzy.InferredType,
    int_value: i64 = 0,
    float_value: f32 = 0.0,
    string_value: [32]u8 = @splat(0),
    min_val: i64 = 0,
    max_val: i64 = 999999999,
};

pub const DualModeSaveState = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file_extension: []const u8,
    raw_buffer: []u8,
    view_mode: SaveViewMode,

    // Agama deterministic fields (if profile matched)
    is_known_game: bool,
    game_title: []const u8,
    sanskrit_title: []const u8,
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
            .game_title = "Unknown Sthiti (अज्ञात)",
            .sanskrit_title = "प्रवाह रूप (Raw Stream)",
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
        const header_slice = if (self.raw_buffer.len >= 16) self.raw_buffer[0..16] else self.raw_buffer;
        const matched_profile = profiles.findMatchingProfile(self.file_path, header_slice);

        if (matched_profile) |prof| {
            self.is_known_game = true;
            self.game_title = prof.title;
            self.sanskrit_title = prof.sanskrit_title;
            // Primary view remains Pravaha Fuzzy until user switches to deterministic
            self.view_mode = .PravahaFuzzyRaw;

            for (prof.rules) |rule| {
                const int_val = if (rule.offset + 4 <= self.raw_buffer.len)
                    std.mem.readInt(i32, self.raw_buffer[rule.offset..][0..4], .little)
                else
                    0;
                try self.agama_fields.append(self.allocator, .{
                    .id = rule.key_name,
                    .name = rule.display_title,
                    .sanskrit_name = rule.sanskrit_title,
                    .offset = rule.offset,
                    .data_type = rule.field_type,
                    .int_value = int_val,
                    .min_val = rule.min_value,
                    .max_val = rule.max_value,
                });
            }
        } else {
            // Deterministic engine is WIP until game-by-game profiles are added.
            // Exclusively driven by the generic fuzzy overseer engine.
            self.is_known_game = false;
            self.game_title = "Generic Binary Stream (सामान्य प्रपत्र)";
            self.sanskrit_title = "प्रवाह दर्शन (Pravaha Stream)";
            self.view_mode = .PravahaFuzzyRaw;
        }
    }

    /// Modifies a deterministic Agama field by ID and updates raw buffer
    pub fn setAgamaField(self: *DualModeSaveState, field_id: []const u8, new_value: i64) !void {
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

test "DualModeSaveState - Defaults to Pravaha Fuzzy Raw Table (Agama WIP)" {
    const allocator = std.testing.allocator;

    var unknown_mock: [64]u8 = @splat(0);
    @memcpy(unknown_mock[0..4], "CUST");
    std.mem.writeInt(i32, unknown_mock[8..12], 12345, .little);

    var state = try DualModeSaveState.init(allocator, "custom_unknown.dat", &unknown_mock);
    defer state.deinit();

    // Deterministic option is WIP until game-by-game logic is added
    try std.testing.expect(!state.is_known_game);
    try std.testing.expectEqual(SaveViewMode.PravahaFuzzyRaw, state.view_mode);
    try std.testing.expectEqual(@as(usize, 0), state.agama_fields.items.len);

    // Generic fuzzy overseer engine extracts candidates ranked by confidence
    try std.testing.expect(state.fuzzy_results.items.len > 0);
    for (0..state.fuzzy_results.items.len - 1) |i| {
        try std.testing.expect(state.fuzzy_results.items[i].confidence >= state.fuzzy_results.items[i + 1].confidence);
    }
}
