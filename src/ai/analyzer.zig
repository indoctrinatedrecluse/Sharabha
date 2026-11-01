const std = @import("std");
const fuzzy = @import("../save/fuzzy.zig");
const switcher = @import("../save/switcher.zig");

pub const LandmarkHint = struct {
    offset: usize,
    name: [32]u8,
    name_len: usize,

    pub fn getName(self: *const LandmarkHint) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const AiSaveHints = struct {
    container_format: [64]u8,
    container_len: usize,
    compression: [32]u8,
    compression_len: usize,
    endianness: [16]u8,
    endian_len: usize,
    key_hints: [16][32]u8,
    key_hints_lens: [16]usize,
    key_count: usize,
    landmarks: [8]LandmarkHint,
    landmark_count: usize,

    pub fn default() AiSaveHints {
        return .{
            .container_format = @splat(0),
            .container_len = 0,
            .compression = @splat(0),
            .compression_len = 0,
            .endianness = @splat(0),
            .endian_len = 0,
            .key_hints = @splat(@splat(0)),
            .key_hints_lens = @splat(0),
            .key_count = 0,
            .landmarks = @splat(.{
                .offset = 0,
                .name = @splat(0),
                .name_len = 0,
            }),
            .landmark_count = 0,
        };
    }

    pub fn addKeyHint(self: *AiSaveHints, key: []const u8) void {
        if (self.key_count >= 16) return;
        const len = @min(key.len, 32);
        @memcpy(self.key_hints[self.key_count][0..len], key[0..len]);
        self.key_hints_lens[self.key_count] = len;
        self.key_count += 1;
    }

    pub fn addLandmark(self: *AiSaveHints, offset: usize, name: []const u8) void {
        if (self.landmark_count >= 8) return;
        var lm = LandmarkHint{
            .offset = offset,
            .name = @splat(0),
            .name_len = 0,
        };
        const len = @min(name.len, 32);
        @memcpy(lm.name[0..len], name[0..len]);
        lm.name_len = len;
        self.landmarks[self.landmark_count] = lm;
        self.landmark_count += 1;
    }
};

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return i;
    }
    return null;
}

/// Constructs the prompt to be sent to Gemini / DeepSeek / OpenAI
pub fn buildAnalysisPrompt(
    allocator: std.mem.Allocator,
    filename: []const u8,
    buffer: []const u8,
    report: switcher.MetricAnalysisReport,
) ![]const u8 {
    var prompt_list: std.ArrayList(u8) = .empty;
    errdefer prompt_list.deinit(allocator);

    var temp_buf: [1024]u8 = undefined;

    const header = std.fmt.bufPrint(&temp_buf,
        \\You are the Divya Drishti (दिव्य दृष्टि / Divine Oracle) save file reverse-engineering intelligence for Sharabha.
        \\Analyze the following binary save header and telemetry metrics to deduce the serialization layout.
        \\
        \\SAVE TELEMETRY:
        \\- Filename: "{s}"
        \\- Total File Size: {d} bytes
        \\- Primary Metric Score: {s}
        \\- Metric Classification Verdict: {s}
        \\- Magic Header Detected: {s}
        \\
        \\FIRST 128 BYTES HEX DUMP:
        \\
    , .{
        filename,
        buffer.len,
        report.getScore(),
        report.getVerdict(),
        report.container.displayName(),
    }) catch "ERROR";
    try prompt_list.appendSlice(allocator, header);

    const dump_len = @min(buffer.len, 128);
    for (buffer[0..dump_len], 0..) |b, i| {
        const hex_token = std.fmt.bufPrint(&temp_buf, "{X:0>2} ", .{b}) catch "?? ";
        try prompt_list.appendSlice(allocator, hex_token);
        if ((i + 1) % 16 == 0) {
            try prompt_list.appendSlice(allocator, "\n");
        }
    }

    const instructions =
        \\
        \\
        \\CRITICAL INSTRUCTION:
        \\Respond ONLY with a valid RFC8259 JSON object without commentary or markdown code blocks:
        \\{
        \\  "container_format": "<string e.g. JSON, XML, Unreal GVAS, Raw C++ Struct, SQLite>",
        \\  "compression": "<string e.g. None, Zlib, Gzip>",
        \\  "endianness": "<string e.g. LittleEndian, BigEndian>",
        \\  "key_names": ["<predicted key 1>", "<predicted key 2>"],
        \\  "landmarks": [{"offset": 12, "name": "Gold"}]
        \\}
    ;
    try prompt_list.appendSlice(allocator, instructions);

    return prompt_list.toOwnedSlice(allocator);
}

/// Parses the AI's JSON response and extracts structured hints
pub fn parseAiResponse(response_text: []const u8) AiSaveHints {
    var hints = AiSaveHints.default();

    // Trim markdown fences if present
    var clean_json = std.mem.trim(u8, response_text, " \t\r\n`");
    if (std.mem.startsWith(u8, clean_json, "json")) {
        clean_json = std.mem.trim(u8, clean_json[4..], " \t\r\n`");
    }

    // Heuristic key extraction from JSON
    const search_tags = [_][]const u8{ "container_format", "compression", "endianness" };
    for (search_tags) |tag| {
        if (std.mem.indexOf(u8, clean_json, tag)) |tag_idx| {
            const after_tag = clean_json[tag_idx + tag.len ..];
            if (std.mem.indexOfScalar(u8, after_tag, ':')) |colon_idx| {
                const after_colon = after_tag[colon_idx + 1 ..];
                if (std.mem.indexOfScalar(u8, after_colon, '"')) |first_q| {
                    const val_part = after_colon[first_q + 1 ..];
                    if (std.mem.indexOfScalar(u8, val_part, '"')) |second_q| {
                        const extracted_val = val_part[0..second_q];
                        if (std.mem.eql(u8, tag, "container_format")) {
                            const len = @min(extracted_val.len, 64);
                            @memcpy(hints.container_format[0..len], extracted_val[0..len]);
                            hints.container_len = len;
                        } else if (std.mem.eql(u8, tag, "compression")) {
                            const len = @min(extracted_val.len, 32);
                            @memcpy(hints.compression[0..len], extracted_val[0..len]);
                            hints.compression_len = len;
                        } else if (std.mem.eql(u8, tag, "endianness")) {
                            const len = @min(extracted_val.len, 16);
                            @memcpy(hints.endianness[0..len], extracted_val[0..len]);
                            hints.endian_len = len;
                        }
                    }
                }
            }
        }
    }

    // Extract key_names array entries
    if (std.mem.indexOf(u8, clean_json, "key_names")) |keys_idx| {
        const arr_start = clean_json[keys_idx..];
        if (std.mem.indexOfScalar(u8, arr_start, '[')) |start_bracket| {
            if (std.mem.indexOfScalar(u8, arr_start, ']')) |end_bracket| {
                const array_slice = arr_start[start_bracket + 1 .. end_bracket];
                var token_iter = std.mem.splitScalar(u8, array_slice, ',');
                while (token_iter.next()) |tok| {
                    const trimmed = std.mem.trim(u8, tok, " \t\r\n\"'");
                    if (trimmed.len > 0) {
                        hints.addKeyHint(trimmed);
                    }
                }
            }
        }
    }

    return hints;
}

/// Feeds forward AI Save Hints into extracted fuzzy fields
pub fn applyHintsToFuzzyFields(hints: *const AiSaveHints, fields: []fuzzy.InferredField) void {
    if (hints.key_count == 0 and hints.landmark_count == 0) return;

    for (fields) |*field| {
        // 1. Check landmarks for direct offset matches
        for (hints.landmarks[0..hints.landmark_count]) |lm| {
            if (field.offset == lm.offset) {
                const name = lm.getName();
                const copy_len = @min(name.len, 64);
                @memcpy(field.suggested_label[0..copy_len], name[0..copy_len]);
                field.suggested_label_len = copy_len;
                field.confidence = @min(100, field.confidence + 35);
                break;
            }
        }

        // 2. Check key name hints for substring relevance
        const current_label = field.getLabel();
        for (0..hints.key_count) |k_idx| {
            const hint_name = hints.key_hints[k_idx][0..hints.key_hints_lens[k_idx]];
            if (indexOfIgnoreCase(current_label, hint_name) != null or
                indexOfIgnoreCase(hint_name, current_label) != null)
            {
                field.confidence = @min(100, field.confidence + 20);
                break;
            }
        }
    }
}

test "buildAnalysisPrompt and parseAiResponse round-trip" {
    const allocator = std.testing.allocator;

    const mock_resp =
        \\```json
        \\{
        \\  "container_format": "Unreal GVAS",
        \\  "compression": "None",
        \\  "endianness": "LittleEndian",
        \\  "key_names": ["HeroGold", "PlayerLevel", "ManaPool"],
        \\  "landmarks": [{"offset": 12, "name": "HeroGold"}]
        \\}
        \\```
    ;

    const hints = parseAiResponse(mock_resp);
    try std.testing.expectEqualStrings("Unreal GVAS", hints.container_format[0..hints.container_len]);
    try std.testing.expectEqualStrings("None", hints.compression[0..hints.compression_len]);
    try std.testing.expectEqualStrings("LittleEndian", hints.endianness[0..hints.endian_len]);
    try std.testing.expect(hints.key_count >= 2);

    // Feed forward into a mock field
    var mock_field = fuzzy.InferredField{
        .offset = 12,
        .length = 4,
        .confidence = 50,
        .inferred_type = .Int32LE,
        .display_value = @splat(0),
        .display_value_len = 0,
        .suggested_label = @splat(0),
        .suggested_label_len = 0,
    };
    @memcpy(mock_field.suggested_label[0..4], "GOLD");
    mock_field.suggested_label_len = 4;

    var fields = [_]fuzzy.InferredField{mock_field};
    applyHintsToFuzzyFields(&hints, &fields);

    // Confidence boosted because of landmark match and key match
    try std.testing.expect(fields[0].confidence > 50);

    // Test prompt generation
    const mock_report = switcher.MetricAnalysisReport{
        .metric = .ShannonEntropy,
        .score_display = @splat(0),
        .score_len = 0,
        .verdict_display = @splat(0),
        .verdict_len = 0,
        .container = .UnrealEngineGVAS,
        .stride = 0,
    };
    const prompt = try buildAnalysisPrompt(allocator, "save.sav", "GVAS\x00\x00\x00\x00", mock_report);
    defer allocator.free(prompt);
    try std.testing.expect(prompt.len > 100);
}
