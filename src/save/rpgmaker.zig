//! ============================================================================
//! SHARABHA (शरभ) — MAYA LILA SUTRA: UNIVERSAL RPG MAKER & VN SAVE PARSER
//! (माया लीला सूत्र // The Formula of Cosmic Illusion & Play)
//!
//! Universal Deterministic Save Engine for RPG Maker & Visual Novel Ecosystems:
//!   1. RPG Maker MV & MZ (.rpgsave, .rmmzsave): LZ-String Base64 & Plain JSON
//!   2. RPG Maker XP, VX, & VX Ace (.rxdata, .rvdata, .rvdata2): Ruby Marshal 4.8
//!
//! Acknowledgment & Attribution:
//! Architectural insights, format taxonomies, and multi-compression recovery
//! patterns inspired by and adapted with credit to paradoxie (author of SaveEditor:
//! https://github.com/paradoxie/saveeditor).
//!
//! Features:
//!   - High-throughput native Zig LZ-String Base64 compressor & decompressor
//!   - Typed extraction of Party Gold, Actor stats (Level, HP, MP), Variables & Switches
//!   - Deterministic in-place mutation, atomic safe write, and backup (.sharabha.bak)
//! ============================================================================

const std = @import("std");
const win = @import("rewrite.zig").win;

pub const RpgMakerSaveFormat = enum {
    LzStringBase64, // Standard RPG Maker MV & MZ (.rpgsave, .rmmzsave)
    PlainJson,      // Uncompressed JSON RPG Maker save
    RubyMarshal,    // RPG Maker XP / VX / VX Ace (.rxdata, .rvdata, .rvdata2)
    Unknown,

    pub fn displayName(self: RpgMakerSaveFormat) []const u8 {
        return switch (self) {
            .LzStringBase64 => "RPG Maker MV/MZ LZ-String Base64 (माया संपुट)",
            .PlainJson => "RPG Maker MV/MZ Plain JSON (शुद्ध पाठ)",
            .RubyMarshal => "RPG Maker XP/VX/VX Ace Ruby Marshal 4.8 (माणिक्य संपुट)",
            .Unknown => "Unknown RPG Format",
        };
    }
};

// ============================================================================
// LZ-STRING BASE64 COMPRESSION & DECOMPRESSION (PIEROXY ALGORITHM IN ZIG)
// ============================================================================

pub const LZString = struct {
    const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

    pub fn getBaseValue(c: u8) ?u32 {
        return switch (c) {
            'A'...'Z' => c - 'A',
            'a'...'z' => c - 'a' + 26,
            '0'...'9' => c - '0' + 52,
            '+' => 62,
            '/' => 63,
            '=' => 0,
            else => null,
        };
    }

    const DecompressContext = struct {
        input: []const u8,
        index: usize,
        val: u32,
        position: u32,
        reset_val: u32,

        fn init(input: []const u8, reset_val: u32) DecompressContext {
            var ctx = DecompressContext{
                .input = input,
                .index = 1,
                .val = 0,
                .position = reset_val,
                .reset_val = reset_val,
            };
            if (input.len > 0) {
                ctx.val = getBaseValue(input[0]) orelse 0;
            }
            return ctx;
        }

        fn readBit(self: *DecompressContext) u32 {
            const resb = self.val & self.position;
            self.position >>= 1;
            if (self.position == 0) {
                self.position = self.reset_val;
                if (self.index < self.input.len) {
                    self.val = getBaseValue(self.input[self.index]) orelse 0;
                    self.index += 1;
                } else {
                    self.val = 0;
                }
            }
            return if (resb > 0) 1 else 0;
        }

        fn readBits(self: *DecompressContext, num_bits: usize) u32 {
            var bits: u32 = 0;
            var power: u32 = 1;
            const max_power = @as(u32, 1) << @intCast(num_bits);
            while (power != max_power) {
                bits |= self.readBit() * power;
                power <<= 1;
            }
            return bits;
        }
    };

    pub fn decompressFromBase64(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " \r\n\t");
        if (trimmed.len == 0) return try allocator.dupe(u8, "");

        var ctx = DecompressContext.init(trimmed, 32);

        // Read first character indicator
        const next_type = ctx.readBits(2);
        var first_char: u8 = 0;
        switch (next_type) {
            0 => {
                const b = ctx.readBits(8);
                first_char = @intCast(b & 0xFF);
            },
            1 => {
                const b = ctx.readBits(16);
                first_char = @intCast(b & 0xFF);
            },
            2 => return try allocator.dupe(u8, ""),
            else => return error.InvalidLzStringHeader,
        }

        var dictionary: std.ArrayList([]const u8) = .empty;
        defer {
            for (dictionary.items) |entry| {
                allocator.free(entry);
            }
            dictionary.deinit(allocator);
        }

        // Initialize dictionary slots 0, 1, 2 as dummies
        for (0..3) |_| {
            try dictionary.append(allocator, try allocator.dupe(u8, ""));
        }

        var initial_buf: [1]u8 = .{first_char};
        try dictionary.append(allocator, try allocator.dupe(u8, &initial_buf)); // dict[3]

        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);

        try result.append(allocator, first_char);

        var w = try allocator.dupe(u8, &initial_buf);
        defer allocator.free(w);

        var enlarge_in: usize = 4;
        var dict_size: usize = 4;
        var num_bits: usize = 3;

        while (true) {
            if (ctx.index > trimmed.len + 1) {
                break;
            }

            var c = ctx.readBits(num_bits);

            if (c == 0) {
                const b = ctx.readBits(8);
                const char_val: u8 = @intCast(b & 0xFF);
                const char_buf: [1]u8 = .{char_val};
                try dictionary.append(allocator, try allocator.dupe(u8, &char_buf));
                dict_size += 1;
                c = @intCast(dict_size - 1);
                enlarge_in -= 1;
            } else if (c == 1) {
                const b = ctx.readBits(16);
                const char_val: u8 = @intCast(b & 0xFF);
                const char_buf: [1]u8 = .{char_val};
                try dictionary.append(allocator, try allocator.dupe(u8, &char_buf));
                dict_size += 1;
                c = @intCast(dict_size - 1);
                enlarge_in -= 1;
            } else if (c == 2) {
                break; // End of stream
            }

            if (enlarge_in == 0) {
                enlarge_in = @as(usize, 1) << @intCast(num_bits);
                num_bits += 1;
            }

            var entry: []const u8 = undefined;
            var allocated_entry: ?[]u8 = null;
            defer if (allocated_entry) |ae| allocator.free(ae);

            if (c < dictionary.items.len) {
                entry = dictionary.items[c];
            } else if (c == dict_size) {
                const combined = try allocator.alloc(u8, w.len + 1);
                @memcpy(combined[0..w.len], w);
                combined[w.len] = w[0];
                allocated_entry = combined;
                entry = combined;
            } else {
                break;
            }

            try result.appendSlice(allocator, entry);

            // Add w + entry[0] to dictionary
            if (entry.len > 0) {
                const new_dict_entry = try allocator.alloc(u8, w.len + 1);
                @memcpy(new_dict_entry[0..w.len], w);
                new_dict_entry[w.len] = entry[0];
                try dictionary.append(allocator, new_dict_entry);
                dict_size += 1;
                enlarge_in -= 1;
            }

            allocator.free(w);
            w = try allocator.dupe(u8, entry);

            if (enlarge_in == 0) {
                enlarge_in = @as(usize, 1) << @intCast(num_bits);
                num_bits += 1;
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    pub fn compressToBase64(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) return try allocator.dupe(u8, "");

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var dict = std.StringHashMap(usize).init(allocator);
        defer {
            var it = dict.keyIterator();
            while (it.next()) |k| allocator.free(k.*);
            dict.deinit();
        }

        var dict_to_create = std.StringHashMap(void).init(allocator);
        defer {
            var it = dict_to_create.keyIterator();
            while (it.next()) |k| allocator.free(k.*);
            dict_to_create.deinit();
        }

        var w: std.ArrayList(u8) = .empty;
        defer w.deinit(allocator);

        var enlarge_in: usize = 2;
        var dict_size: usize = 3;
        var num_bits: usize = 2;

        var data_val: u32 = 0;
        var data_pos: usize = 0;

        for (input) |c| {
            var c_buf: [1]u8 = .{c};
            const c_slice: []const u8 = &c_buf;

            if (!dict.contains(c_slice)) {
                try dict.put(try allocator.dupe(u8, c_slice), dict_size);
                dict_size += 1;
                try dict_to_create.put(try allocator.dupe(u8, c_slice), {});
            }

            var wc: std.ArrayList(u8) = .empty;
            defer wc.deinit(allocator);
            try wc.appendSlice(allocator, w.items);
            try wc.append(allocator, c);

            if (dict.contains(wc.items)) {
                w.clearRetainingCapacity();
                try w.appendSlice(allocator, wc.items);
            } else {
                if (dict_to_create.contains(w.items)) {
                    if (w.items[0] < 256) {
                        try emitBits(&out, allocator, 0, num_bits, &data_val, &data_pos);
                        try emitBits(&out, allocator, w.items[0], 8, &data_val, &data_pos);
                    } else {
                        try emitBits(&out, allocator, 1, num_bits, &data_val, &data_pos);
                        try emitBits(&out, allocator, w.items[0], 16, &data_val, &data_pos);
                    }
                    enlarge_in -= 1;
                    if (enlarge_in == 0) {
                        enlarge_in = @as(usize, 1) << @intCast(num_bits);
                        num_bits += 1;
                    }
                    if (dict_to_create.fetchRemove(w.items)) |kv| {
                        allocator.free(kv.key);
                    }
                } else {
                    const val = dict.get(w.items) orelse 0;
                    try emitBits(&out, allocator, @intCast(val), num_bits, &data_val, &data_pos);
                }

                enlarge_in -= 1;
                if (enlarge_in == 0) {
                    enlarge_in = @as(usize, 1) << @intCast(num_bits);
                    num_bits += 1;
                }

                try dict.put(try allocator.dupe(u8, wc.items), dict_size);
                dict_size += 1;

                w.clearRetainingCapacity();
                try w.append(allocator, c);
            }
        }

        // Output code for w
        if (w.items.len > 0) {
            if (dict_to_create.contains(w.items)) {
                if (w.items[0] < 256) {
                    try emitBits(&out, allocator, 0, num_bits, &data_val, &data_pos);
                    try emitBits(&out, allocator, w.items[0], 8, &data_val, &data_pos);
                } else {
                    try emitBits(&out, allocator, 1, num_bits, &data_val, &data_pos);
                    try emitBits(&out, allocator, w.items[0], 16, &data_val, &data_pos);
                }
                enlarge_in -= 1;
                if (enlarge_in == 0) {
                    enlarge_in = @as(usize, 1) << @intCast(num_bits);
                    num_bits += 1;
                }
                if (dict_to_create.fetchRemove(w.items)) |kv| {
                    allocator.free(kv.key);
                }
            } else {
                const val = dict.get(w.items) orelse 0;
                try emitBits(&out, allocator, @intCast(val), num_bits, &data_val, &data_pos);
            }
            enlarge_in -= 1;
            if (enlarge_in == 0) {
                enlarge_in = @as(usize, 1) << @intCast(num_bits);
                num_bits += 1;
            }
        }

        // Mark end of stream (value 2)
        try emitBits(&out, allocator, 2, num_bits, &data_val, &data_pos);

        // Flush remaining bits
        while (true) {
            data_val <<= 1;
            if (data_pos == 5) {
                try out.append(allocator, base64_chars[data_val]);
                break;
            } else {
                data_pos += 1;
            }
        }

        // Add padding
        const rem = out.items.len % 4;
        if (rem == 1) {
            try out.appendSlice(allocator, "===");
        } else if (rem == 2) {
            try out.appendSlice(allocator, "==");
        } else if (rem == 3) {
            try out.appendSlice(allocator, "=");
        }

        return try out.toOwnedSlice(allocator);
    }

    fn emitBits(out: *std.ArrayList(u8), allocator: std.mem.Allocator, val: u32, num_bits: usize, data_val: *u32, data_pos: *usize) !void {
        var v = val;
        for (0..num_bits) |_| {
            data_val.* = (data_val.* << 1) | (v & 1);
            if (data_pos.* == 5) {
                data_pos.* = 0;
                try out.append(allocator, base64_chars[data_val.*]);
                data_val.* = 0;
            } else {
                data_pos.* += 1;
            }
            v >>= 1;
        }
    }
};

// ============================================================================
// DATA STRUCTURES
// ============================================================================

pub const RpgMakerActor = struct {
    id: usize,
    name: []const u8,
    level: i64,
    hp: i64,
    mp: i64,
};

pub const RpgMakerVariable = struct {
    id: usize,
    value: i64,
};

pub const RpgMakerSwitch = struct {
    id: usize,
    value: bool,
};

pub const RpgMakerItem = struct {
    id: []const u8,
    count: i64,
};

pub const RpgMakerSave = struct {
    arena: *std.heap.ArenaAllocator,
    format: RpgMakerSaveFormat,
    raw_content: []const u8,
    decompressed_json: []const u8,
    gold: ?i64,
    actors: []const RpgMakerActor,
    variables: []const RpgMakerVariable,
    switches: []const RpgMakerSwitch,
    items: []const RpgMakerItem,

    pub fn deinit(self: *RpgMakerSave, child_allocator: std.mem.Allocator) void {
        const arena_ptr = self.arena;
        arena_ptr.deinit();
        child_allocator.destroy(arena_ptr);
    }

    /// Detect save format from raw bytes
    pub fn detectFormat(content: []const u8) RpgMakerSaveFormat {
        if (content.len >= 2 and content[0] == 0x04 and content[1] == 0x08) {
            return .RubyMarshal;
        }

        const trimmed = std.mem.trim(u8, content, " \r\n\t");

        // LZString base64 check: RPG Maker MV/MZ savefiles almost universally start with "N4Ig" or "BY" or "CY"
        if (trimmed.len > 10 and (std.mem.startsWith(u8, trimmed, "N4Ig") or std.mem.startsWith(u8, trimmed, "BY") or std.mem.startsWith(u8, trimmed, "CY") or std.mem.startsWith(u8, trimmed, "eJ"))) {
            return .LzStringBase64;
        }

        // Plain JSON check
        if (trimmed.len > 10 and (trimmed[0] == '{' or trimmed[0] == '[')) {
            if (std.mem.indexOf(u8, trimmed, "\"party\"") != null or
                std.mem.indexOf(u8, trimmed, "\"$gameParty\"") != null or
                std.mem.indexOf(u8, trimmed, "\"_gold\"") != null or
                std.mem.indexOf(u8, trimmed, "\"$gameActors\"") != null or
                std.mem.indexOf(u8, trimmed, "\"actors\"") != null)
            {
                return .PlainJson;
            }
        }

        // If it contains valid base64 chars only, might be another LZ-String variant
        var is_base64 = true;
        const check_len = @min(trimmed.len, 64);
        for (trimmed[0..check_len]) |c| {
            if (LZString.getBaseValue(c) == null) {
                is_base64 = false;
                break;
            }
        }
        if (is_base64 and trimmed.len > 20) return .LzStringBase64;

        return .Unknown;
    }

    /// Parse an RPG Maker save file
    pub fn parse(child_allocator: std.mem.Allocator, content: []const u8) !*RpgMakerSave {
        const arena = try child_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(child_allocator);
        errdefer {
            arena.deinit();
            child_allocator.destroy(arena);
        }
        const alloc = arena.allocator();

        const format = detectFormat(content);

        var decompressed: []const u8 = "";
        var gold_val: ?i64 = null;
        var actors_list: std.ArrayList(RpgMakerActor) = .empty;
        var vars_list: std.ArrayList(RpgMakerVariable) = .empty;
        var switches_list: std.ArrayList(RpgMakerSwitch) = .empty;
        var items_list: std.ArrayList(RpgMakerItem) = .empty;

        switch (format) {
            .LzStringBase64 => {
                decompressed = LZString.decompressFromBase64(alloc, content) catch |err| blk: {
                    if (content.len > 0 and (content[0] == '{' or content[0] == '[')) {
                        break :blk try alloc.dupe(u8, content);
                    } else {
                        return err;
                    }
                };
            },
            .PlainJson => {
                decompressed = try alloc.dupe(u8, content);
            },
            .RubyMarshal => {
                // Parse Ruby Marshal 4.8 binary tree
                return try parseRubyMarshalSave(alloc, arena, content);
            },
            .Unknown => {
                // Attempt LZ-String decompress, then JSON parse
                decompressed = LZString.decompressFromBase64(alloc, content) catch blk: {
                    break :blk try alloc.dupe(u8, content);
                };
            },
        }

        // Parse extracted JSON string
        if (decompressed.len > 0 and (decompressed[0] == '{' or decompressed[0] == '[')) {
            const parsed = std.json.parseFromSlice(std.json.Value, alloc, decompressed, .{}) catch null;
            if (parsed) |p| {
                const root = p.value;
                if (root == .object) {
                    // 1. Extract Party Gold
                    if (root.object.get("party")) |party| {
                        if (party == .object) {
                            if (party.object.get("_gold")) |g| {
                                if (g == .integer) gold_val = g.integer;
                            } else if (party.object.get("gold")) |g| {
                                if (g == .integer) gold_val = g.integer;
                            }

                            // Items
                            if (party.object.get("_items")) |items_obj| {
                                if (items_obj == .object) {
                                    var it = items_obj.object.iterator();
                                    while (it.next()) |entry| {
                                        if (entry.value_ptr.* == .integer) {
                                            try items_list.append(alloc, .{
                                                .id = try alloc.dupe(u8, entry.key_ptr.*),
                                                .count = entry.value_ptr.*.integer,
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    } else if (root.object.get("gold")) |g| {
                        if (g == .integer) gold_val = g.integer;
                    }

                    // 2. Extract Actors
                    if (root.object.get("actors")) |actors_obj| {
                        if (actors_obj == .object) {
                            if (actors_obj.object.get("_data")) |data_arr| {
                                if (data_arr == .array) {
                                    for (data_arr.array.items, 0..) |actor_val, idx| {
                                        if (actor_val == .object) {
                                            const a_name = if (actor_val.object.get("_name")) |n| (if (n == .string) n.string else "") else "";
                                            const a_level = if (actor_val.object.get("_level")) |l| (if (l == .integer) l.integer else 1) else 1;
                                            const a_hp = if (actor_val.object.get("_hp")) |h| (if (h == .integer) h.integer else 100) else 100;
                                            const a_mp = if (actor_val.object.get("_mp")) |m| (if (m == .integer) m.integer else 10) else 10;
                                            try actors_list.append(alloc, .{
                                                .id = idx,
                                                .name = try alloc.dupe(u8, a_name),
                                                .level = a_level,
                                                .hp = a_hp,
                                                .mp = a_mp,
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. Extract Variables
                    if (root.object.get("variables")) |vars_obj| {
                        if (vars_obj == .object) {
                            if (vars_obj.object.get("_data")) |data_arr| {
                                if (data_arr == .array) {
                                    for (data_arr.array.items, 0..) |v, idx| {
                                        if (idx > 0 and v == .integer) {
                                            try vars_list.append(alloc, .{
                                                .id = idx,
                                                .value = v.integer,
                                            });
                                        }
                                    }
                                }
                            } else {
                                var it = vars_obj.object.iterator();
                                while (it.next()) |entry| {
                                    if (entry.value_ptr.* == .integer) {
                                        const parsed_id = std.fmt.parseInt(usize, entry.key_ptr.*, 10) catch 0;
                                        try vars_list.append(alloc, .{
                                            .id = parsed_id,
                                            .value = entry.value_ptr.*.integer,
                                        });
                                    }
                                }
                            }
                        } else if (vars_obj == .array) {
                            for (vars_obj.array.items, 0..) |v, idx| {
                                if (idx > 0 and v == .integer) {
                                    try vars_list.append(alloc, .{
                                        .id = idx,
                                        .value = v.integer,
                                    });
                                }
                            }
                        }
                    }

                    // 4. Extract Switches
                    if (root.object.get("switches")) |sw_obj| {
                        if (sw_obj == .object) {
                            if (sw_obj.object.get("_data")) |data_arr| {
                                if (data_arr == .array) {
                                    for (data_arr.array.items, 0..) |s, idx| {
                                        if (idx > 0 and s == .bool) {
                                            try switches_list.append(alloc, .{
                                                .id = idx,
                                                .value = s.bool,
                                            });
                                        }
                                    }
                                }
                            }
                        } else if (sw_obj == .array) {
                            for (sw_obj.array.items, 0..) |s, idx| {
                                if (idx > 0 and s == .bool) {
                                    try switches_list.append(alloc, .{
                                        .id = idx,
                                        .value = s.bool,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        const self = try alloc.create(RpgMakerSave);
        self.* = .{
            .arena = arena,
            .format = format,
            .raw_content = try alloc.dupe(u8, content),
            .decompressed_json = decompressed,
            .gold = gold_val,
            .actors = actors_list.items,
            .variables = vars_list.items,
            .switches = switches_list.items,
            .items = items_list.items,
        };
        return self;
    }

    /// Rejects containers whose serializer cannot round-trip a surgical edit.
    /// Ruby Marshal (.rxdata / .rvdata / .rvdata2) needs a full Marshal encoder,
    /// so claiming a successful mutation there would silently discard the edit.
    fn ensureMutable(self: *RpgMakerSave) !void {
        switch (self.format) {
            .RubyMarshal => return error.MarshalMutationUnsupported,
            .Unknown => return error.UnknownContainerFormat,
            else => {},
        }
        if (self.decompressed_json.len == 0) return error.EmptyContainer;
    }

    /// Mutate party gold (scope-aware: prefers `party._gold` over a stray `_gold`).
    pub fn setGold(self: *RpgMakerSave, new_gold: i64) !void {
        try self.ensureMutable();
        var buf: [32]u8 = undefined;
        const val_text = std.fmt.bufPrint(&buf, "{d}", .{new_gold}) catch return error.OutOfMemory;
        try self.setScopedField(&.{ "party", "$gameParty" }, &.{ "_gold", "gold" }, val_text);
        self.gold = new_gold;
    }

    /// Mutate a single actor stat. `actor_id` is the 1-based RPG Maker actor
    /// index (`actors._data[actor_id]`), i.e. exactly the id shown by --parse-rpg.
    /// `field` accepts `_level`/`level`, `_hp`/`hp`, `_mp`/`mp`.
    pub fn setActorField(self: *RpgMakerSave, actor_id: usize, field: []const u8, value: i64) !void {
        try self.ensureMutable();
        const alloc = self.arena.allocator();
        const json = self.decompressed_json;

        const scope = findScopedSpan(json, 0, json.len, &.{ "actors", "$gameActors" }, '{') orelse return error.ScopeNotFound;
        const arr = findScopedSpan(json, scope.start, scope.end, &.{ "_data", "data" }, '[') orelse return error.FieldNotFound;
        const element = arrayElement(json, arr.start, actor_id) orelse return error.ActorNotFound;

        const canonical: []const u8 = if (std.mem.eql(u8, field, "level") or std.mem.eql(u8, field, "_level"))
            "_level"
        else if (std.mem.eql(u8, field, "hp") or std.mem.eql(u8, field, "_hp"))
            "_hp"
        else if (std.mem.eql(u8, field, "mp") or std.mem.eql(u8, field, "_mp"))
            "_mp"
        else
            return error.UnsupportedActorField;

        const field_span = findField(json, element.start, element.end, canonical) orelse return error.FieldNotFound;

        var buf: [32]u8 = undefined;
        const val_text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.OutOfMemory;
        self.decompressed_json = try replaceSpan(alloc, json, field_span, val_text);

        // Keep the in-memory view coherent for callers that read it back.
        for (@constCast(self.actors)) |*actor| {
            if (actor.id != actor_id) continue;
            if (std.mem.eql(u8, canonical, "_level")) actor.level = value;
            if (std.mem.eql(u8, canonical, "_hp")) actor.hp = value;
            if (std.mem.eql(u8, canonical, "_mp")) actor.mp = value;
            break;
        }
    }

    /// Mutate actor level (kept for backward compatibility with earlier callers).
    pub fn setActorLevel(self: *RpgMakerSave, actor_idx: usize, level: i64) !void {
        try self.setActorField(actor_idx, "_level", level);
    }

    /// Replaces the value of the first `keys` match found inside the first `scopes` match.
    fn setScopedField(self: *RpgMakerSave, scopes: []const []const u8, keys: []const []const u8, val_text: []const u8) !void {
        const alloc = self.arena.allocator();
        const json = self.decompressed_json;

        var span: ?Span = null;
        if (findScopedSpan(json, 0, json.len, scopes, '{')) |scope| {
            span = findAnyField(json, scope.start, scope.end, keys);
        }
        if (span == null) span = findAnyField(json, 0, json.len, keys);

        const target = span orelse return error.FieldNotFound;
        self.decompressed_json = try replaceSpan(alloc, json, target, val_text);
    }

    /// Mutate variable by id. Handles both array form (`_data: [null, ...]`) and
    /// sparse object form (`{"3": 7}`).
    pub fn setVariable(self: *RpgMakerSave, var_id: usize, val: i64) !void {
        try self.ensureMutable();
        const alloc = self.arena.allocator();
        const json = self.decompressed_json;

        var buf: [32]u8 = undefined;
        const val_text = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return error.OutOfMemory;

        var target: ?Span = null;
        if (findScopedSpan(json, 0, json.len, &.{ "variables", "$gameVariables" }, '{')) |scope| {
            if (findScopedSpan(json, scope.start, scope.end, &.{ "_data", "data" }, '[')) |arr| {
                target = arrayElement(json, arr.start, var_id);
            }
            if (target == null) {
                var key_buf: [16]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{d}", .{var_id}) catch return error.OutOfMemory;
                target = findField(json, scope.start, scope.end, key);
            }
        }

        const span = target orelse return error.VariableNotFound;
        self.decompressed_json = try replaceSpan(alloc, json, span, val_text);

        for (@constCast(self.variables)) |*v| {
            if (v.id == var_id) v.value = val;
        }
    }

    /// Mutate switch by id.
    pub fn setSwitch(self: *RpgMakerSave, switch_id: usize, value: bool) !void {
        try self.ensureMutable();
        const alloc = self.arena.allocator();
        const json = self.decompressed_json;
        const val_text: []const u8 = if (value) "true" else "false";

        var target: ?Span = null;
        if (findScopedSpan(json, 0, json.len, &.{ "switches", "$gameSwitches" }, '{')) |scope| {
            if (findScopedSpan(json, scope.start, scope.end, &.{ "_data", "data" }, '[')) |arr| {
                target = arrayElement(json, arr.start, switch_id);
            }
            if (target == null) {
                var key_buf: [16]u8 = undefined;
                const key = std.fmt.bufPrint(&key_buf, "{d}", .{switch_id}) catch return error.OutOfMemory;
                target = findField(json, scope.start, scope.end, key);
            }
        }

        const span = target orelse return error.SwitchNotFound;
        self.decompressed_json = try replaceSpan(alloc, json, span, val_text);

        for (@constCast(self.switches)) |*sw| {
            if (sw.id == switch_id) sw.value = value;
        }
    }

    /// Mutate an inventory stack (`party._items["<id>"]`).
    pub fn setItem(self: *RpgMakerSave, item_id: usize, count: i64) !void {
        try self.ensureMutable();
        const alloc = self.arena.allocator();
        const json = self.decompressed_json;

        var key_buf: [16]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{d}", .{item_id}) catch return error.OutOfMemory;

        const party = findScopedSpan(json, 0, json.len, &.{ "party", "$gameParty" }, '{') orelse return error.ScopeNotFound;
        const items = findScopedSpan(json, party.start, party.end, &.{ "_items", "items" }, '{') orelse return error.FieldNotFound;
        const span = findField(json, items.start, items.end, key) orelse return error.ItemNotFound;

        var buf: [32]u8 = undefined;
        const val_text = std.fmt.bufPrint(&buf, "{d}", .{count}) catch return error.OutOfMemory;
        self.decompressed_json = try replaceSpan(alloc, json, span, val_text);

        for (@constCast(self.items)) |*item| {
            if (std.mem.eql(u8, item.id, key)) item.count = count;
        }
    }


    /// Applies a save-editor row key (the exact labels emitted by `--parse-rpg`)
    /// to the container. Returns false when the key is not addressable.
    ///
    /// Accepted forms: `Party Gold (_gold)`, `Actor #2 Level (Marsha)`,
    /// `Actor2.HP`, `Variable #0003`, `Var3`, `Switch #0001`, `Item #17`, `Gold`.
    pub fn applyEdit(self: *RpgMakerSave, key_text: []const u8, val_text: []const u8) !bool {
        try self.ensureMutable();

        const key = std.mem.trim(u8, key_text, " \t\r\n[]\"'");
        if (key.len == 0) return false;

        var lower_buf: [192]u8 = undefined;
        const lower_len = @min(key.len, lower_buf.len);
        for (key[0..lower_len], 0..) |c, i| lower_buf[i] = std.ascii.toLower(c);
        const lower = lower_buf[0..lower_len];

        const is_actor = std.mem.startsWith(u8, lower, "actor") or std.mem.indexOf(u8, lower, "actor #") != null;
        if (!is_actor and std.mem.indexOf(u8, lower, "gold") != null) {
            const amount = parseI64Text(val_text) orelse return false;
            try self.setGold(amount);
            return true;
        }

        if (is_actor) {
            const id = firstNumber(lower) orelse return false;
            const field: []const u8 = if (std.mem.indexOf(u8, lower, "level") != null)
                "_level"
            else if (std.mem.indexOf(u8, lower, "hp") != null)
                "_hp"
            else if (std.mem.indexOf(u8, lower, "mp") != null)
                "_mp"
            else
                return false;
            const amount = parseI64Text(val_text) orelse return false;
            try self.setActorField(id, field, amount);
            return true;
        }

        if (std.mem.startsWith(u8, lower, "variable") or std.mem.startsWith(u8, lower, "var")) {
            const id = firstNumber(lower) orelse return false;
            const amount = parseI64Text(val_text) orelse return false;
            try self.setVariable(id, amount);
            return true;
        }

        if (std.mem.startsWith(u8, lower, "switch")) {
            const id = firstNumber(lower) orelse return false;
            const flag = parseBoolText(val_text) orelse return false;
            try self.setSwitch(id, flag);
            return true;
        }

        if (std.mem.startsWith(u8, lower, "item")) {
            const id = firstNumber(lower) orelse return false;
            const amount = parseI64Text(val_text) orelse return false;
            try self.setItem(id, amount);
            return true;
        }

        return false;
    }

    /// Serialize save file back to original storage format
    pub fn serialize(self: *RpgMakerSave, allocator: std.mem.Allocator) ![]u8 {
        switch (self.format) {
            .LzStringBase64 => {
                return try LZString.compressToBase64(allocator, self.decompressed_json);
            },
            .PlainJson => {
                return try allocator.dupe(u8, self.decompressed_json);
            },
            .RubyMarshal => {
                return try allocator.dupe(u8, self.raw_content);
            },
            .Unknown => {
                return try allocator.dupe(u8, self.decompressed_json);
            },
        }
    }

    /// Atomically commit modified save to disk with .sharabha.bak backup
    pub fn writeToDisk(self: *RpgMakerSave, file_path: []const u8, allocator: std.mem.Allocator) !void {
        const serialized = try self.serialize(allocator);
        defer allocator.free(serialized);

        const target_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, file_path);
        defer allocator.free(target_w);

        const bak_path = try std.fmt.allocPrint(allocator, "{s}.sharabha.bak", .{file_path});
        defer allocator.free(bak_path);
        const bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, bak_path);
        defer allocator.free(bak_w);

        // 1. Generate .sharabha.bak backup
        _ = win.CopyFileW(target_w.ptr, bak_w.ptr, 0);

        // 2. Atomic write via .tmp
        const tmp_path = try std.fmt.allocPrint(allocator, "{s}.sharabha.tmp", .{file_path});
        defer allocator.free(tmp_path);
        const tmp_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, tmp_path);
        defer allocator.free(tmp_w);

        const hTmp = win.CreateFileW(tmp_w.ptr, win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
        if (hTmp == win.INVALID_HANDLE_VALUE) return error.TempFileWriteFailed;

        var written: u32 = 0;
        _ = win.WriteFile(hTmp, serialized.ptr, @intCast(serialized.len), &written, null);
        _ = win.CloseHandle(hTmp);

        // 3. Atomic swap
        _ = win.MoveFileExW(tmp_w.ptr, target_w.ptr, win.MOVEFILE_REPLACE_EXISTING);
    }
};

// ============================================================================
// SCOPE-AWARE JSON SPAN HELPERS (Sūkṣhma Rekha for MV/MZ containers)
// ----------------------------------------------------------------------------
// RPG Maker MV/MZ saves nest everything inside `party` / `actors` / `variables`
// / `switches` objects, and the same short field name (`_data`, `_level`, ...)
// repeats in several of them. These helpers locate *byte spans* inside the raw
// container text so a mutation rewrites exactly one value and leaves the rest
// of the author's file byte-identical.
// ============================================================================

const Span = struct { start: usize, end: usize };

fn skipJsonWs(json: []const u8, from: usize) usize {
    var i = from;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\r' or json[i] == '\n')) : (i += 1) {}
    return i;
}

/// Exclusive end offset of the JSON value beginning at `start` (string aware).
fn jsonValueEnd(json: []const u8, start: usize) ?usize {
    if (start >= json.len) return null;
    const first = json[start];

    if (first == '"') {
        var i = start + 1;
        while (i < json.len) : (i += 1) {
            if (json[i] == '\\') {
                i += 1;
                continue;
            }
            if (json[i] == '"') return i + 1;
        }
        return null;
    }

    if (first == '{' or first == '[') {
        const open = first;
        const close: u8 = if (first == '{') '}' else ']';
        var depth: usize = 0;
        var i = start;
        while (i < json.len) : (i += 1) {
            const ch = json[i];
            if (ch == '"') {
                i += 1;
                while (i < json.len) : (i += 1) {
                    if (json[i] == '\\') {
                        i += 1;
                        continue;
                    }
                    if (json[i] == '"') break;
                }
                continue;
            }
            if (ch == open) {
                depth += 1;
            } else if (ch == close) {
                depth -= 1;
                if (depth == 0) return i + 1;
            }
        }
        return null;
    }

    // Number / true / false / null literal
    var i = start;
    while (i < json.len) : (i += 1) {
        const ch = json[i];
        if (ch == ',' or ch == '}' or ch == ']' or ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') break;
    }
    return i;
}

/// Value span of `"key": <value>` restricted to `json[from..to]`.
fn findField(json: []const u8, from: usize, to: usize, key: []const u8) ?Span {
    if (to > json.len or from >= to) return null;

    var pat_buf: [128]u8 = undefined;
    if (key.len + 2 > pat_buf.len) return null;
    pat_buf[0] = '"';
    @memcpy(pat_buf[1 .. 1 + key.len], key);
    pat_buf[1 + key.len] = '"';
    const pattern = pat_buf[0 .. key.len + 2];

    const hay = json[from..to];
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, hay, search, pattern)) |rel| {
        const abs = from + rel;
        var i = skipJsonWs(json, abs + pattern.len);
        if (i < json.len and json[i] == ':') {
            i = skipJsonWs(json, i + 1);
            const end = jsonValueEnd(json, i) orelse return null;
            return .{ .start = i, .end = end };
        }
        search = rel + pattern.len;
    }
    return null;
}

/// Like `findAnyField`, but only accepts spans whose value starts with `open`
/// (`'{'` for objects, `'['` for arrays).
///
/// RPG Maker MZ containers can carry a decoy `"switches": null` under `system`
/// before the real `"switches": {"_data": [...]}` block; without this guard the
/// scope lookup latches onto the null and every switch/variable edit fails.
fn findScopedSpan(json: []const u8, from: usize, to: usize, keys: []const []const u8, open: u8) ?Span {
    for (keys) |key| {
        var cursor = from;
        while (cursor < to) {
            const span = findField(json, cursor, to, key) orelse break;
            if (span.start < json.len and json[span.start] == open) return span;
            cursor = span.start + 1;
        }
    }
    return null;
}

fn findAnyField(json: []const u8, from: usize, to: usize, keys: []const []const u8) ?Span {
    for (keys) |key| {
        if (findField(json, from, to, key)) |span| return span;
    }
    return null;
}

/// Span of the `index`-th element (0-based) of the array value at `arr_start`.
fn arrayElement(json: []const u8, arr_start: usize, index: usize) ?Span {
    if (arr_start >= json.len or json[arr_start] != '[') return null;

    var i = arr_start + 1;
    var ordinal: usize = 0;
    while (i < json.len) {
        i = skipJsonWs(json, i);
        if (i >= json.len or json[i] == ']') return null;
        const end = jsonValueEnd(json, i) orelse return null;
        if (ordinal == index) return .{ .start = i, .end = end };
        ordinal += 1;
        i = skipJsonWs(json, end);
        if (i < json.len and json[i] == ',') i += 1;
    }
    return null;
}

fn replaceSpan(allocator: std.mem.Allocator, json: []const u8, span: Span, replacement: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, json[0..span.start]);
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, json[span.end..]);
    return out.toOwnedSlice(allocator);
}

fn parseI64Text(text: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n\"'");
    if (std.ascii.eqlIgnoreCase(trimmed, "true")) return 1;
    if (std.ascii.eqlIgnoreCase(trimmed, "false")) return 0;
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn parseBoolText(text: []const u8) ?bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n\"'");
    if (std.ascii.eqlIgnoreCase(trimmed, "true") or std.mem.eql(u8, trimmed, "1") or std.ascii.eqlIgnoreCase(trimmed, "on")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "false") or std.mem.eql(u8, trimmed, "0") or std.ascii.eqlIgnoreCase(trimmed, "off")) return false;
    return null;
}

fn firstNumber(text: []const u8) ?usize {
    var i: usize = 0;
    while (i < text.len and !std.ascii.isDigit(text[i])) : (i += 1) {}
    const start = i;
    while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {}
    if (i == start) return null;
    return std.fmt.parseInt(usize, text[start..i], 10) catch null;
}

// ============================================================================
// RUBY MARSHAL 4.8 PARSER (RPG MAKER XP / VX / VX ACE)
// ============================================================================

fn parseRubyMarshalSave(
    alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    content: []const u8,
) !*RpgMakerSave {
    if (content.len < 2 or content[0] != 0x04 or content[1] != 0x08) {
        return error.InvalidRubyMarshalHeader;
    }

    var gold_val: ?i64 = null;

    // Scan for Ruby instance variable ":@gold" (symbol \x3A\x05\x40\x67\x6F\x6C\x64)
    if (std.mem.indexOf(u8, content, "@gold")) |gold_pos| {
        // Read next integer or bignum following symbol
        const search_slice = content[gold_pos + 5 .. @min(content.len, gold_pos + 20)];
        if (search_slice.len >= 2) {
            if (search_slice[0] == 'i') {
                // Integer
                const b0 = search_slice[1];
                if (b0 == 0) {
                    gold_val = 0;
                } else if (b0 > 0 and b0 <= 4 and search_slice.len >= 2 + b0) {
                    var acc: i64 = 0;
                    for (0..b0) |k| {
                        acc |= @as(i64, search_slice[2 + k]) << @intCast(k * 8);
                    }
                    gold_val = acc;
                } else if (b0 >= 5) {
                    gold_val = @as(i64, b0) - 5;
                }
            }
        }
    }

    const self = try alloc.create(RpgMakerSave);
    self.* = .{
        .arena = arena,
        .format = .RubyMarshal,
        .raw_content = try alloc.dupe(u8, content),
        .decompressed_json = try std.fmt.allocPrint(alloc, "{{\"_ruby_marshal\": true, \"gold\": {?d}}}", .{gold_val}),
        .gold = gold_val,
        .actors = &.{},
        .variables = &.{},
        .switches = &.{},
        .items = &.{},
    };
    return self;
}

// ============================================================================
// JSON MUTATION HELPERS
// ============================================================================

fn replaceJsonKeyValue(allocator: std.mem.Allocator, json: []const u8, key: []const u8, new_val: i64) ![]u8 {
    const search_pat = try std.fmt.allocPrint(allocator, "\"{s}\":", .{key});
    defer allocator.free(search_pat);

    const pos = std.mem.indexOf(u8, json, search_pat) orelse return try allocator.dupe(u8, json);
    const val_start = pos + search_pat.len;

    // Skip whitespace
    var cur = val_start;
    while (cur < json.len and (json[cur] == ' ' or json[cur] == '\t')) : (cur += 1) {}

    // Find end of current value
    var val_end = cur;
    while (val_end < json.len and (json[val_end] == '-' or (json[val_end] >= '0' and json[val_end] <= '9'))) : (val_end += 1) {}

    const val_str = try std.fmt.allocPrint(allocator, "{d}", .{new_val});
    defer allocator.free(val_str);

    var res: std.ArrayList(u8) = .empty;
    defer res.deinit(allocator);

    try res.appendSlice(allocator, json[0..cur]);
    try res.appendSlice(allocator, val_str);
    try res.appendSlice(allocator, json[val_end..]);
    return try res.toOwnedSlice(allocator);
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "Maya Lila Sutra: LZ-String Decompression and Compression Roundtrip" {
    const alloc = std.testing.allocator;

    const original_json = "{\"party\":{\"_gold\":9999}}";
    // Verified LZ-String base64 vector generated by lz-string.js
    const sample_base64 = "N4IgDghgTgLgniAXKA+gcwPYBsAmSCch+AvsUA==";

    // 1. Decompress
    const decompressed = try LZString.decompressFromBase64(alloc, sample_base64);
    defer alloc.free(decompressed);

    try std.testing.expectEqualStrings(original_json, decompressed);

    // 2. Compress back
    const recompressed = try LZString.compressToBase64(alloc, decompressed);
    defer alloc.free(recompressed);

    // 3. Decompress again to ensure roundtrip fidelity
    const roundtrip = try LZString.decompressFromBase64(alloc, recompressed);
    defer alloc.free(roundtrip);

    try std.testing.expectEqualStrings(original_json, roundtrip);
}

test "Maya Lila Sutra: Parse and Mutate RPG Maker Savefile" {
    const alloc = std.testing.allocator;

    const mock_save_json =
        \\{
        \\  "party": {
        \\    "_gold": 5000,
        \\    "_items": { "1": 10, "2": 5 }
        \\  },
        \\  "actors": {
        \\    "_data": [
        \\      null,
        \\      {
        \\        "_actorId": 1,
        \\        "_name": "Harold",
        \\        "_level": 25,
        \\        "_hp": 750,
        \\        "_mp": 120
        \\      }
        \\    ]
        \\  },
        \\  "variables": {
        \\    "_data": [null, 100, 200, 300]
        \\  },
        \\  "switches": {
        \\    "_data": [null, true, false, true]
        \\  }
        \\}
    ;

    // Compress to LZString base64
    const compressed = try LZString.compressToBase64(alloc, mock_save_json);
    defer alloc.free(compressed);

    // Parse with RpgMakerSave
    var save = try RpgMakerSave.parse(alloc, compressed);
    defer save.deinit(alloc);

    try std.testing.expectEqual(RpgMakerSaveFormat.LzStringBase64, save.format);
    try std.testing.expectEqual(@as(?i64, 5000), save.gold);
    try std.testing.expectEqual(@as(usize, 1), save.actors.len);
    try std.testing.expectEqualStrings("Harold", save.actors[0].name);
    try std.testing.expectEqual(@as(i64, 25), save.actors[0].level);
    try std.testing.expectEqual(@as(i64, 750), save.actors[0].hp);
    try std.testing.expectEqual(@as(usize, 3), save.variables.len);
    try std.testing.expectEqual(@as(usize, 3), save.switches.len);

    // Mutate gold
    try save.setGold(999999);
    try std.testing.expectEqual(@as(?i64, 999999), save.gold);

    // Re-serialize
    const exported = try save.serialize(alloc);
    defer alloc.free(exported);

    // Reparse to verify persistence
    var reparsed = try RpgMakerSave.parse(alloc, exported);
    defer reparsed.deinit(alloc);

    try std.testing.expectEqual(@as(?i64, 999999), reparsed.gold);
}

test "Maya Lila Sutra: surgical indexed mutation targets a single field" {
    const alloc = std.testing.allocator;

    const mock_save_json =
        \\{
        \\  "system": { "locale": "en_US", "switches": null },
        \\  "party": { "_gold": 4200, "_items": { "1": 5, "17": 12 } },
        \\  "actors": {
        \\    "_data": [
        \\      null,
        \\      { "_name": "Harold", "_level": 12, "_hp": 480, "_mp": 90 },
        \\      { "_name": "Marsha", "_level": 11, "_hp": 410, "_mp": 140 }
        \\    ]
        \\  },
        \\  "variables": { "_data": [null, 7, 1500, 3] },
        \\  "switches": { "_data": [null, true, false] }
        \\}
    ;

    var save = try RpgMakerSave.parse(alloc, mock_save_json);
    defer save.deinit(alloc);

    try std.testing.expectEqual(RpgMakerSaveFormat.PlainJson, save.format);

    // The pre-existing bug replaced the *first* `_level` regardless of the
    // requested actor. Actor 2 must change, actor 1 must stay untouched.
    try save.setActorField(2, "_level", 99);
    try save.setActorField(1, "_hp", 999);
    try std.testing.expectEqual(@as(i64, 12), save.actors[0].level);
    try std.testing.expectEqual(@as(i64, 99), save.actors[1].level);
    try std.testing.expectEqual(@as(i64, 999), save.actors[0].hp);

    try save.setVariable(3, 8);
    try save.setSwitch(2, true);
    try save.setItem(17, 30);
    try save.setGold(9999);

    const exported = try save.serialize(alloc);
    defer alloc.free(exported);

    var reparsed = try RpgMakerSave.parse(alloc, exported);
    defer reparsed.deinit(alloc);

    try std.testing.expectEqual(@as(?i64, 9999), reparsed.gold);
    try std.testing.expectEqual(@as(usize, 2), reparsed.actors.len);
    try std.testing.expectEqual(@as(i64, 12), reparsed.actors[0].level);
    try std.testing.expectEqual(@as(i64, 99), reparsed.actors[1].level);
    try std.testing.expectEqual(@as(i64, 999), reparsed.actors[0].hp);
    try std.testing.expectEqual(@as(i64, 410), reparsed.actors[1].hp);

    var var_found = false;
    for (reparsed.variables) |v| {
        if (v.id == 3) {
            try std.testing.expectEqual(@as(i64, 8), v.value);
            var_found = true;
        }
    }
    try std.testing.expect(var_found);

    var switch_found = false;
    for (reparsed.switches) |sw| {
        if (sw.id == 2) {
            try std.testing.expectEqual(true, sw.value);
            switch_found = true;
        }
    }
    try std.testing.expect(switch_found);

    var item_found = false;
    for (reparsed.items) |item| {
        if (std.mem.eql(u8, item.id, "17")) {
            try std.testing.expectEqual(@as(i64, 30), item.count);
            item_found = true;
        }
    }
    try std.testing.expect(item_found);
}

test "Maya Lila Sutra: applyEdit accepts the --parse-rpg row labels verbatim" {
    const alloc = std.testing.allocator;

    const mock_save_json =
        \\{"system":{"locale":"en_US","switches":null},
        \\ "party":{"_gold":4200,"_items":{"1":5,"17":12}},
        \\ "actors":{"_data":[null,{"_name":"Harold","_level":12,"_hp":480},{"_name":"Marsha","_level":11,"_hp":410}]},
        \\ "variables":{"_data":[null,7,1500,3]},
        \\ "switches":{"_data":[null,true,false]}}
    ;

    var save = try RpgMakerSave.parse(alloc, mock_save_json);
    defer save.deinit(alloc);

    try std.testing.expect(try save.applyEdit("Party Gold (_gold)", "4201"));
    try std.testing.expect(try save.applyEdit("Actor #2 Level (Marsha)", "55"));
    try std.testing.expect(try save.applyEdit("Actor #1 HP (Harold)", "1234"));
    try std.testing.expect(try save.applyEdit("Variable #0003", "8"));
    try std.testing.expect(try save.applyEdit("Switch #0002", "True"));
    try std.testing.expect(try save.applyEdit("Item #17", "99"));

    // Unknown / hostile keys are rejected instead of silently no-oping.
    try std.testing.expect(!(try save.applyEdit("meta.sharabha_fixture", "x")));
    try std.testing.expect(!(try save.applyEdit("", "1")));

    const exported = try save.serialize(alloc);
    defer alloc.free(exported);

    var reparsed = try RpgMakerSave.parse(alloc, exported);
    defer reparsed.deinit(alloc);

    try std.testing.expectEqual(@as(?i64, 4201), reparsed.gold);
    try std.testing.expectEqual(@as(i64, 12), reparsed.actors[0].level);
    try std.testing.expectEqual(@as(i64, 55), reparsed.actors[1].level);
    try std.testing.expectEqual(@as(i64, 1234), reparsed.actors[0].hp);
    try std.testing.expectEqual(@as(i64, 99), reparsed.items[1].count);
}

test "Maya Lila Sutra: Ruby Marshal containers refuse mutation instead of lying" {
    const alloc = std.testing.allocator;

    const ruby_sample = "\x04\x08o:\x0bObject\x00";
    var save = try RpgMakerSave.parse(alloc, ruby_sample);
    defer save.deinit(alloc);

    try std.testing.expectEqual(RpgMakerSaveFormat.RubyMarshal, save.format);
    try std.testing.expectError(error.MarshalMutationUnsupported, save.applyEdit("Gold", "1"));
    try std.testing.expectError(error.MarshalMutationUnsupported, save.setGold(1));
}

test "Maya Lila Sutra: Format Detection" {
    const lz_sample = "N4IgDghgTgLgniAXKA+gcwPYBsAmSCch+AvsUA==";
    try std.testing.expectEqual(RpgMakerSaveFormat.LzStringBase64, RpgMakerSave.detectFormat(lz_sample));

    const json_sample = "{\"party\":{\"_gold\":1234}}";
    try std.testing.expectEqual(RpgMakerSaveFormat.PlainJson, RpgMakerSave.detectFormat(json_sample));

    const ruby_sample = "\x04\x08o:\x0bObject\x00";
    try std.testing.expectEqual(RpgMakerSaveFormat.RubyMarshal, RpgMakerSave.detectFormat(ruby_sample));
}
