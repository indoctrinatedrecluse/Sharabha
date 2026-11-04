//! ============================================================================
//! SHARABHA (शरभ) — AIKYA SUTRA: UNIVERSAL UNITY SAVE PARSER
//! (ऐक्य सूत्र // The Formula of Oneness & Integration)
//! Supports:
//!   1. Unity BinaryFormatter (NRBF - .NET Remoting Binary Format)
//!   2. Unity Easy Save 2 & 3 (ES3 JSON format with typed value dictionaries)
//!   3. Unity PlayerPrefs XML format (<unity_prefs> <pref name="..." type="...">)
//!
//! Provides deterministic property extraction, typed mutations (Int, Float,
//! Bool, String), and atomic binary repacking.
//! ============================================================================

const std = @import("std");

pub const UnitySaveFormat = enum {
    BinaryFormatter, // NRBF: 00 01 00 00 00 FF FF FF FF 01 00 00 00 ...
    EasySave3,       // ES3 JSON: { "key": { "__type": "...", "value": ... } }
    PlayerPrefsXml,  // XML: <unity_prefs><pref name="..." type="...">
    Unknown,
};

pub const UnityPropType = enum {
    Int32,
    Int64,
    Single,
    Double,
    Boolean,
    String,
    Raw,

    pub fn toString(self: UnityPropType) []const u8 {
        return switch (self) {
            .Int32 => "i32 (Int32)",
            .Int64 => "i64 (Int64)",
            .Single => "f32 (Single)",
            .Double => "f64 (Double)",
            .Boolean => "bool (Boolean)",
            .String => "String",
            .Raw => "Raw Bytes",
        };
    }
};

pub const UnityValue = union(enum) {
    Int: i32,
    Int64: i64,
    Float: f32,
    Double: f64,
    Bool: bool,
    Str: []const u8,
    Raw: []const u8,
};

pub const UnityProperty = struct {
    name: []const u8,
    prop_type: UnityPropType,
    value: UnityValue,
    offset: usize, // byte offset in raw buffer if known
    size: usize,   // byte length of serialized value
};

/// Reads a 7-bit encoded integer (used in .NET LengthPrefixedString)
pub fn read7BitEncodedInt(buf: []const u8, cursor: *usize) !u32 {
    var count: u32 = 0;
    var shift: u5 = 0;
    while (cursor.* < buf.len) {
        const b = buf[cursor.*];
        cursor.* += 1;
        count |= (@as(u32, b & 0x7F) << shift);
        shift += 7;
        if ((b & 0x80) == 0) {
            return count;
        }
        if (shift >= 35) return error.Malformed7BitInt;
    }
    return error.UnexpectedEof;
}

/// Writes a 7-bit encoded integer
pub fn write7BitEncodedInt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var v = value;
    while (v >= 0x80) {
        try list.append(allocator, @as(u8, @intCast(v | 0x80)));
        v >>= 7;
    }
    try list.append(allocator, @as(u8, @intCast(v)));
}

pub const UnitySave = struct {
    allocator: std.mem.Allocator,
    format: UnitySaveFormat,
    class_name: []const u8,
    properties: std.ArrayList(UnityProperty),
    raw_buffer: []u8,

    pub fn init(allocator: std.mem.Allocator, format: UnitySaveFormat, class_name: []const u8, raw: []const u8) !UnitySave {
        const owned_raw = try allocator.dupe(u8, raw);
        const owned_class = try allocator.dupe(u8, class_name);
        return UnitySave{
            .allocator = allocator,
            .format = format,
            .class_name = owned_class,
            .properties = .empty,
            .raw_buffer = owned_raw,
        };
    }

    pub fn deinit(self: *UnitySave) void {
        self.allocator.free(self.class_name);
        self.allocator.free(self.raw_buffer);
        for (self.properties.items) |prop| {
            self.allocator.free(prop.name);
            switch (prop.value) {
                .Str => |s| self.allocator.free(s),
                .Raw => |r| self.allocator.free(r),
                else => {},
            }
        }
        self.properties.deinit(self.allocator);
    }

    pub fn findProperty(self: *UnitySave, name: []const u8) ?*UnityProperty {
        for (self.properties.items) |*p| {
            if (std.mem.eql(u8, p.name, name)) return p;
        }
        return null;
    }

    pub fn getInt(self: *const UnitySave, name: []const u8) ?i32 {
        for (self.properties.items) |p| {
            if (std.mem.eql(u8, p.name, name)) {
                return switch (p.value) {
                    .Int => |v| v,
                    .Int64 => |v| @as(i32, @truncate(v)),
                    .Float => |v| @as(i32, @intFromFloat(v)),
                    .Bool => |v| if (v) 1 else 0,
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getFloat(self: *const UnitySave, name: []const u8) ?f32 {
        for (self.properties.items) |p| {
            if (std.mem.eql(u8, p.name, name)) {
                return switch (p.value) {
                    .Float => |v| v,
                    .Double => |v| @as(f32, @floatCast(v)),
                    .Int => |v| @as(f32, @floatFromInt(v)),
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getBool(self: *const UnitySave, name: []const u8) ?bool {
        for (self.properties.items) |p| {
            if (std.mem.eql(u8, p.name, name)) {
                return switch (p.value) {
                    .Bool => |v| v,
                    .Int => |v| (v != 0),
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getString(self: *const UnitySave, name: []const u8) ?[]const u8 {
        for (self.properties.items) |p| {
            if (std.mem.eql(u8, p.name, name)) {
                return switch (p.value) {
                    .Str => |v| v,
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn setInt(self: *UnitySave, name: []const u8, new_val: i32) bool {
        if (self.findProperty(name)) |p| {
            p.value = .{ .Int = new_val };
            if (self.format == .BinaryFormatter and p.offset + 4 <= self.raw_buffer.len) {
                std.mem.writeInt(i32, self.raw_buffer[p.offset..][0..4], new_val, .little);
            }
            return true;
        }
        return false;
    }

    pub fn setFloat(self: *UnitySave, name: []const u8, new_val: f32) bool {
        if (self.findProperty(name)) |p| {
            p.value = .{ .Float = new_val };
            if (self.format == .BinaryFormatter and p.offset + 4 <= self.raw_buffer.len) {
                const bits: u32 = @bitCast(new_val);
                std.mem.writeInt(u32, self.raw_buffer[p.offset..][0..4], bits, .little);
            }
            return true;
        }
        return false;
    }

    pub fn setBool(self: *UnitySave, name: []const u8, new_val: bool) bool {
        if (self.findProperty(name)) |p| {
            p.value = .{ .Bool = new_val };
            if (self.format == .BinaryFormatter and p.offset + 1 <= self.raw_buffer.len) {
                self.raw_buffer[p.offset] = if (new_val) 1 else 0;
            }
            return true;
        }
        return false;
    }

    pub fn setString(self: *UnitySave, name: []const u8, new_val: []const u8) bool {
        if (self.findProperty(name)) |p| {
            const owned = self.allocator.dupe(u8, new_val) catch return false;
            switch (p.value) {
                .Str => |old| self.allocator.free(old),
                else => {},
            }
            p.value = .{ .Str = owned };
            return true;
        }
        return false;
    }

    /// Serializes the entire save state to a fresh buffer
    pub fn serialize(self: *const UnitySave, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.format) {
            .BinaryFormatter => {
                // If in-place mutations occurred within raw_buffer, return duplicate of raw_buffer
                return allocator.dupe(u8, self.raw_buffer);
            },
            .EasySave3 => {
                return self.serializeEasySave3(allocator);
            },
            .PlayerPrefsXml => {
                return self.serializePlayerPrefs(allocator);
            },
            .Unknown => {
                return allocator.dupe(u8, self.raw_buffer);
            },
        }
    }

    fn serializeEasySave3(self: *const UnitySave, allocator: std.mem.Allocator) ![]const u8 {
        var list: std.ArrayList(u8) = .empty;
        try list.appendSlice(allocator, "{\n");

        for (self.properties.items, 0..) |p, i| {
            const comma = if (i + 1 < self.properties.items.len) "," else "";
            switch (p.value) {
                .Int => |iv| {
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"int\",\n    \"value\": {d}\n  }}{s}\n", .{ p.name, iv, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Int64 => |iv| {
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"long\",\n    \"value\": {d}\n  }}{s}\n", .{ p.name, iv, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Float => |fv| {
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"float\",\n    \"value\": {d:.2}\n  }}{s}\n", .{ p.name, fv, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Double => |dv| {
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"double\",\n    \"value\": {d:.4}\n  }}{s}\n", .{ p.name, dv, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Bool => |bv| {
                    const b_str = if (bv) "true" else "false";
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"bool\",\n    \"value\": {s}\n  }}{s}\n", .{ p.name, b_str, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Str => |sv| {
                    const line = try std.fmt.allocPrint(allocator, "  \"{s}\": {{\n    \"__type\": \"string\",\n    \"value\": \"{s}\"\n  }}{s}\n", .{ p.name, sv, comma });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Raw => {},
            }
        }
        try list.appendSlice(allocator, "}\n");
        return list.toOwnedSlice(allocator);
    }

    fn serializePlayerPrefs(self: *const UnitySave, allocator: std.mem.Allocator) ![]const u8 {
        var list: std.ArrayList(u8) = .empty;
        try list.appendSlice(allocator, "<unity_prefs>\n");

        for (self.properties.items) |p| {
            switch (p.value) {
                .Int => |iv| {
                    const line = try std.fmt.allocPrint(allocator, "  <pref name=\"{s}\" type=\"int\">{d}</pref>\n", .{ p.name, iv });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Float => |fv| {
                    const line = try std.fmt.allocPrint(allocator, "  <pref name=\"{s}\" type=\"float\">{d:.2}</pref>\n", .{ p.name, fv });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Bool => |bv| {
                    const iv: i32 = if (bv) 1 else 0;
                    const line = try std.fmt.allocPrint(allocator, "  <pref name=\"{s}\" type=\"int\">{d}</pref>\n", .{ p.name, iv });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                .Str => |sv| {
                    const line = try std.fmt.allocPrint(allocator, "  <pref name=\"{s}\" type=\"string\">{s}</pref>\n", .{ p.name, sv });
                    defer allocator.free(line);
                    try list.appendSlice(allocator, line);
                },
                else => {},
            }
        }
        try list.appendSlice(allocator, "</unity_prefs>\n");
        return list.toOwnedSlice(allocator);
    }
};

/// Check if buffer is a recognized Unity save container
pub fn isUnitySave(buffer: []const u8) bool {
    if (buffer.len < 10) return false;

    // 1. BinaryFormatter NRBF
    if (buffer.len >= 17 and buffer[0] == 0x00 and buffer[1] == 0x01 and buffer[2] == 0x00 and buffer[3] == 0x00 and buffer[4] == 0x00 and buffer[5] == 0xFF and buffer[6] == 0xFF and buffer[7] == 0xFF and buffer[8] == 0xFF) {
        return true;
    }

    // 2. PlayerPrefs XML
    const check_len = @min(buffer.len, 256);
    if (std.mem.indexOf(u8, buffer[0..check_len], "<unity_prefs") != null or std.mem.indexOf(u8, buffer[0..check_len], "<pref name=") != null) {
        return true;
    }

    // 3. Easy Save 3 JSON
    if (std.mem.indexOf(u8, buffer[0..check_len], "\"__type\"") != null) {
        return true;
    }

    // 4. UnityFS / UnityRaw
    if (buffer.len >= 7 and (std.mem.eql(u8, buffer[0..7], "UnityFS") or std.mem.eql(u8, buffer[0..7], "UnityRa"))) {
        return true;
    }

    return false;
}

/// Detects the specific format of a Unity save buffer
pub fn detectUnityFormat(buffer: []const u8) UnitySaveFormat {
    if (buffer.len >= 17 and buffer[0] == 0x00 and buffer[1] == 0x01 and buffer[2] == 0x00 and buffer[3] == 0x00 and buffer[4] == 0x00 and buffer[5] == 0xFF and buffer[6] == 0xFF and buffer[7] == 0xFF and buffer[8] == 0xFF) {
        return .BinaryFormatter;
    }

    const check_len = @min(buffer.len, 256);
    if (std.mem.indexOf(u8, buffer[0..check_len], "<unity_prefs") != null or std.mem.indexOf(u8, buffer[0..check_len], "<pref name=") != null) {
        return .PlayerPrefsXml;
    }

    if (std.mem.indexOf(u8, buffer[0..check_len], "\"__type\"") != null) {
        return .EasySave3;
    }

    return .Unknown;
}

/// Main parser entrypoint for Unity saves
pub fn parseUnitySave(allocator: std.mem.Allocator, buffer: []const u8) !*UnitySave {
    const fmt = detectUnityFormat(buffer);
    const save_ptr = try allocator.create(UnitySave);
    errdefer allocator.destroy(save_ptr);

    switch (fmt) {
        .BinaryFormatter => {
            save_ptr.* = try parseBinaryFormatter(allocator, buffer);
        },
        .EasySave3 => {
            save_ptr.* = try parseEasySave3(allocator, buffer);
        },
        .PlayerPrefsXml => {
            save_ptr.* = try parsePlayerPrefsXml(allocator, buffer);
        },
        .Unknown => {
            save_ptr.* = try UnitySave.init(allocator, .Unknown, "GenericUnitySave", buffer);
        },
    }

    return save_ptr;
}

/// Parses .NET Remoting Binary Format (NRBF / BinaryFormatter)
fn parseBinaryFormatter(allocator: std.mem.Allocator, buffer: []const u8) !UnitySave {
    var cursor: usize = 0;
    if (buffer.len < 17) return error.BufferTooSmall;

    // Header record (Type 0)
    cursor += 17;

    const class_name: []const u8 = "UnityGameSave";
    var save = try UnitySave.init(allocator, .BinaryFormatter, class_name, buffer);
    errdefer save.deinit();

    while (cursor < buffer.len) {
        const record_type = buffer[cursor];
        cursor += 1;

        if (record_type == 0x0B) { // MessageEnd
            break;
        } else if (record_type == 0x0C) { // BinaryLibrary
            cursor += 4; // LibraryId
            const lib_len = try read7BitEncodedInt(buffer, &cursor);
            cursor += lib_len;
        } else if (record_type == 0x04 or record_type == 0x05) { // SystemClassWithMembersAndTypes (4) or ClassWithMembersAndTypes (5)
            cursor += 4; // ObjectId
            const name_len = try read7BitEncodedInt(buffer, &cursor);
            if (cursor + name_len > buffer.len) break;
            const parsed_class = buffer[cursor .. cursor + name_len];
            cursor += name_len;

            allocator.free(save.class_name);
            save.class_name = try allocator.dupe(u8, parsed_class);

            if (cursor + 4 > buffer.len) break;
            const member_count = std.mem.readInt(i32, buffer[cursor..][0..4], .little);
            cursor += 4;
            if (member_count <= 0 or member_count > 500) break;

            const u_count: usize = @intCast(member_count);

            // Read Member Names
            var member_names = try allocator.alloc([]const u8, u_count);
            defer allocator.free(member_names);

            for (0..u_count) |i| {
                const m_len = try read7BitEncodedInt(buffer, &cursor);
                if (cursor + m_len > buffer.len) return error.UnexpectedEof;
                member_names[i] = buffer[cursor .. cursor + m_len];
                cursor += m_len;
            }

            // Read BinaryTypeEnums
            if (cursor + u_count > buffer.len) return error.UnexpectedEof;
            const binary_types = buffer[cursor .. cursor + u_count];
            cursor += u_count;

            // Read AdditionalTypeInfo
            var primitive_types = try allocator.alloc(u8, u_count);
            defer allocator.free(primitive_types);
            @memset(primitive_types, 0);

            for (0..u_count) |i| {
                const b_type = binary_types[i];
                if (b_type == 0) { // Primitive
                    if (cursor >= buffer.len) return error.UnexpectedEof;
                    primitive_types[i] = buffer[cursor];
                    cursor += 1;
                } else if (b_type == 3) { // SystemClass
                    const sc_len = try read7BitEncodedInt(buffer, &cursor);
                    cursor += sc_len;
                } else if (b_type == 4) { // Class
                    const c_len = try read7BitEncodedInt(buffer, &cursor);
                    cursor += c_len + 4; // Name + LibraryId
                } else if (b_type == 7) { // PrimitiveArray
                    cursor += 1;
                }
            }

            if (record_type == 0x05) {
                cursor += 4; // LibraryId
            }

            // Read Values sequentially!
            for (0..u_count) |i| {
                const m_name = member_names[i];
                const b_type = binary_types[i];
                const p_type = primitive_types[i];
                const val_offset = cursor;

                if (b_type == 0) { // Primitive
                    switch (p_type) {
                        1 => { // Boolean (1 byte)
                            if (cursor >= buffer.len) break;
                            const bv = (buffer[cursor] != 0);
                            cursor += 1;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .Boolean,
                                .value = .{ .Bool = bv },
                                .offset = val_offset,
                                .size = 1,
                            });
                        },
                        8 => { // Int32 (4 bytes)
                            if (cursor + 4 > buffer.len) break;
                            const iv = std.mem.readInt(i32, buffer[cursor..][0..4], .little);
                            cursor += 4;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .Int32,
                                .value = .{ .Int = iv },
                                .offset = val_offset,
                                .size = 4,
                            });
                        },
                        9 => { // Int64 (8 bytes)
                            if (cursor + 8 > buffer.len) break;
                            const iv = std.mem.readInt(i64, buffer[cursor..][0..8], .little);
                            cursor += 8;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .Int64,
                                .value = .{ .Int64 = iv },
                                .offset = val_offset,
                                .size = 8,
                            });
                        },
                        11 => { // Single (Float - 4 bytes)
                            if (cursor + 4 > buffer.len) break;
                            const bits = std.mem.readInt(u32, buffer[cursor..][0..4], .little);
                            const fv: f32 = @bitCast(bits);
                            cursor += 4;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .Single,
                                .value = .{ .Float = fv },
                                .offset = val_offset,
                                .size = 4,
                            });
                        },
                        6 => { // Double (8 bytes)
                            if (cursor + 8 > buffer.len) break;
                            const bits = std.mem.readInt(u64, buffer[cursor..][0..8], .little);
                            const dv: f64 = @bitCast(bits);
                            cursor += 8;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .Double,
                                .value = .{ .Double = dv },
                                .offset = val_offset,
                                .size = 8,
                            });
                        },
                        else => {
                            cursor += 4; // default skip
                        },
                    }
                } else if (b_type == 1) { // String
                    if (cursor < buffer.len and buffer[cursor] == 0x06) { // BinaryObjectString
                        cursor += 5; // record_type (1) + ObjectId (4)
                        const s_len = try read7BitEncodedInt(buffer, &cursor);
                        if (cursor + s_len <= buffer.len) {
                            const str_slice = buffer[cursor .. cursor + s_len];
                            cursor += s_len;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .String,
                                .value = .{ .Str = try allocator.dupe(u8, str_slice) },
                                .offset = val_offset,
                                .size = s_len,
                            });
                        }
                    } else {
                        const s_len = read7BitEncodedInt(buffer, &cursor) catch 0;
                        if (cursor + s_len <= buffer.len) {
                            const str_slice = buffer[cursor .. cursor + s_len];
                            cursor += s_len;
                            try save.properties.append(allocator, UnityProperty{
                                .name = try allocator.dupe(u8, m_name),
                                .prop_type = .String,
                                .value = .{ .Str = try allocator.dupe(u8, str_slice) },
                                .offset = val_offset,
                                .size = s_len,
                            });
                        }
                    }
                }
            }
        } else {
            // Unrecognized record type, step forward
            cursor += 1;
        }
    }

    return save;
}

/// Parses Unity Easy Save 3 JSON format
fn parseEasySave3(allocator: std.mem.Allocator, buffer: []const u8) !UnitySave {
    var save = try UnitySave.init(allocator, .EasySave3, "EasySave3Vessel", buffer);
    errdefer save.deinit();

    // Iterate through lines looking for `"key": { ... "__type": "...", "value": ... }`
    // or standard JSON fields
    var pos: usize = 0;
    while (pos < buffer.len) {
        const next_q = std.mem.indexOfScalarPos(u8, buffer, pos, '"') orelse break;
        const end_q = std.mem.indexOfScalarPos(u8, buffer, next_q + 1, '"') orelse break;
        const key = buffer[next_q + 1 .. end_q];

        if (std.mem.eql(u8, key, "__type") or std.mem.eql(u8, key, "value") or std.mem.eql(u8, key, "_values")) {
            pos = end_q + 1;
            continue;
        }

        // Check if colon follows
        var colon_pos = end_q + 1;
        while (colon_pos < buffer.len and (buffer[colon_pos] == ' ' or buffer[colon_pos] == '\t' or buffer[colon_pos] == '\r' or buffer[colon_pos] == '\n')) : (colon_pos += 1) {}
        if (colon_pos >= buffer.len or buffer[colon_pos] != ':') {
            pos = end_q + 1;
            continue;
        }

        // Look for "__type" within next 200 bytes
        const search_limit = @min(buffer.len, colon_pos + 250);
        const type_idx = std.mem.indexOf(u8, buffer[colon_pos..search_limit], "\"__type\"");

        if (type_idx) |ti| {
            const type_block = buffer[colon_pos + ti .. search_limit];
            const type_val_start = if (std.mem.indexOf(u8, type_block, ":")) |colon_t| colon_t + 1 else 0;
            const t_q1 = if (std.mem.indexOfScalar(u8, type_block[type_val_start..], '"')) |q| type_val_start + q + 1 else 0;
            const t_q2 = if (std.mem.indexOfScalar(u8, type_block[t_q1..], '"')) |q| t_q1 + q else 0;
            const detected_type_str = if (t_q1 > 0 and t_q2 > t_q1) type_block[t_q1..t_q2] else "";

            // Extract "value"
            if (std.mem.indexOf(u8, type_block, "\"value\"")) |vi| {
                var v_colon = colon_pos + ti + vi + 7;
                while (v_colon < search_limit and (buffer[v_colon] == ' ' or buffer[v_colon] == '\t' or buffer[v_colon] == ':')) : (v_colon += 1) {}
                const v_start = v_colon;
                var v_end = v_start;
                while (v_end < search_limit and buffer[v_end] != '\r' and buffer[v_end] != '\n' and buffer[v_end] != ',' and buffer[v_end] != '}') : (v_end += 1) {}
                const raw_val = std.mem.trim(u8, buffer[v_start..v_end], " \"'\t");

                if (std.mem.indexOf(u8, detected_type_str, "int") != null or std.mem.indexOf(u8, detected_type_str, "Int") != null) {
                    const iv = std.fmt.parseInt(i32, raw_val, 10) catch 0;
                    try save.properties.append(allocator, UnityProperty{
                        .name = try allocator.dupe(u8, key),
                        .prop_type = .Int32,
                        .value = .{ .Int = iv },
                        .offset = v_start,
                        .size = raw_val.len,
                    });
                } else if (std.mem.indexOf(u8, detected_type_str, "float") != null or std.mem.indexOf(u8, detected_type_str, "Single") != null) {
                    const fv = std.fmt.parseFloat(f32, raw_val) catch 0.0;
                    try save.properties.append(allocator, UnityProperty{
                        .name = try allocator.dupe(u8, key),
                        .prop_type = .Single,
                        .value = .{ .Float = fv },
                        .offset = v_start,
                        .size = raw_val.len,
                    });
                } else if (std.mem.indexOf(u8, detected_type_str, "bool") != null) {
                    const bv = std.mem.eql(u8, raw_val, "true") or std.mem.eql(u8, raw_val, "1");
                    try save.properties.append(allocator, UnityProperty{
                        .name = try allocator.dupe(u8, key),
                        .prop_type = .Boolean,
                        .value = .{ .Bool = bv },
                        .offset = v_start,
                        .size = raw_val.len,
                    });
                } else {
                    try save.properties.append(allocator, UnityProperty{
                        .name = try allocator.dupe(u8, key),
                        .prop_type = .String,
                        .value = .{ .Str = try allocator.dupe(u8, raw_val) },
                        .offset = v_start,
                        .size = raw_val.len,
                    });
                }
            }
        }
        pos = end_q + 1;
    }

    return save;
}

/// Parses Unity PlayerPrefs XML format
fn parsePlayerPrefsXml(allocator: std.mem.Allocator, buffer: []const u8) !UnitySave {
    var save = try UnitySave.init(allocator, .PlayerPrefsXml, "PlayerPrefsVessel", buffer);
    errdefer save.deinit();

    var pos: usize = 0;
    while (pos < buffer.len) {
        const pref_idx = std.mem.indexOfPos(u8, buffer, pos, "<pref") orelse break;
        const tag_end = std.mem.indexOfPos(u8, buffer, pref_idx, ">") orelse break;
        const close_tag = std.mem.indexOfPos(u8, buffer, tag_end, "</pref>") orelse break;

        const tag_header = buffer[pref_idx..tag_end];
        const val_slice = std.mem.trim(u8, buffer[tag_end + 1 .. close_tag], " \t\r\n");

        // Parse name="..."
        var name: []const u8 = "";
        if (std.mem.indexOf(u8, tag_header, "name=\"")) |ni| {
            const n_start = ni + 6;
            if (std.mem.indexOfScalar(u8, tag_header[n_start..], '"')) |n_end| {
                name = tag_header[n_start .. n_start + n_end];
            }
        }

        // Parse type="..."
        var type_str: []const u8 = "int";
        if (std.mem.indexOf(u8, tag_header, "type=\"")) |ti| {
            const t_start = ti + 6;
            if (std.mem.indexOfScalar(u8, tag_header[t_start..], '"')) |t_end| {
                type_str = tag_header[t_start .. t_start + t_end];
            }
        }

        if (name.len > 0) {
            if (std.mem.eql(u8, type_str, "int")) {
                const iv = std.fmt.parseInt(i32, val_slice, 10) catch 0;
                try save.properties.append(allocator, UnityProperty{
                    .name = try allocator.dupe(u8, name),
                    .prop_type = .Int32,
                    .value = .{ .Int = iv },
                    .offset = tag_end + 1,
                    .size = val_slice.len,
                });
            } else if (std.mem.eql(u8, type_str, "float")) {
                const fv = std.fmt.parseFloat(f32, val_slice) catch 0.0;
                try save.properties.append(allocator, UnityProperty{
                    .name = try allocator.dupe(u8, name),
                    .prop_type = .Single,
                    .value = .{ .Float = fv },
                    .offset = tag_end + 1,
                    .size = val_slice.len,
                });
            } else {
                try save.properties.append(allocator, UnityProperty{
                    .name = try allocator.dupe(u8, name),
                    .prop_type = .String,
                    .value = .{ .Str = try allocator.dupe(u8, val_slice) },
                    .offset = tag_end + 1,
                    .size = val_slice.len,
                });
            }
        }

        pos = close_tag + 7;
    }

    return save;
}

// =============================================================================
// TESTS
// =============================================================================

test "Aikya Sutra: Unity EasySave3 parsing and mutation" {
    const alloc = std.testing.allocator;
    const mock_es3 =
        \\{
        \\  "PlayerGold": {
        \\    "__type": "int",
        \\    "value": 50000
        \\  },
        \\  "PlayerHealth": {
        \\    "__type": "float",
        \\    "value": 100.0
        \\  },
        \\  "PlayerName": {
        \\    "__type": "string",
        \\    "value": "Sharabha"
        \\  },
        \\  "IsHardcore": {
        \\    "__type": "bool",
        \\    "value": false
        \\  }
        \\}
    ;

    var save = try parseUnitySave(alloc, mock_es3);
    defer {
        save.deinit();
        alloc.destroy(save);
    }

    try std.testing.expectEqual(UnitySaveFormat.EasySave3, save.format);
    try std.testing.expectEqual(@as(usize, 4), save.properties.items.len);

    try std.testing.expectEqual(@as(i32, 50000), save.getInt("PlayerGold").?);
    try std.testing.expectEqual(@as(f32, 100.0), save.getFloat("PlayerHealth").?);
    try std.testing.expectEqualStrings("Sharabha", save.getString("PlayerName").?);
    try std.testing.expectEqual(false, save.getBool("IsHardcore").?);

    // Test Mutation
    try std.testing.expect(save.setInt("PlayerGold", 999999));
    try std.testing.expectEqual(@as(i32, 999999), save.getInt("PlayerGold").?);

    try std.testing.expect(save.setFloat("PlayerHealth", 250.5));
    try std.testing.expectEqual(@as(f32, 250.5), save.getFloat("PlayerHealth").?);

    try std.testing.expect(save.setBool("IsHardcore", true));
    try std.testing.expectEqual(true, save.getBool("IsHardcore").?);

    // Test Repacking
    const repacked = try save.serialize(alloc);
    defer alloc.free(repacked);

    try std.testing.expect(std.mem.indexOf(u8, repacked, "\"value\": 999999") != null);
    try std.testing.expect(std.mem.indexOf(u8, repacked, "\"value\": true") != null);
}

test "Aikya Sutra: Unity PlayerPrefs XML parsing and mutation" {
    const alloc = std.testing.allocator;
    const mock_xml =
        \\<unity_prefs>
        \\  <pref name="PlayerGold" type="int">77777</pref>
        \\  <pref name="PlayerHealth" type="float">88.5</pref>
        \\  <pref name="PlayerName" type="string">Rudra</pref>
        \\</unity_prefs>
    ;

    var save = try parseUnitySave(alloc, mock_xml);
    defer {
        save.deinit();
        alloc.destroy(save);
    }

    try std.testing.expectEqual(UnitySaveFormat.PlayerPrefsXml, save.format);
    try std.testing.expectEqual(@as(usize, 3), save.properties.items.len);

    try std.testing.expectEqual(@as(i32, 77777), save.getInt("PlayerGold").?);
    try std.testing.expectEqual(@as(f32, 88.5), save.getFloat("PlayerHealth").?);
    try std.testing.expectEqualStrings("Rudra", save.getString("PlayerName").?);

    // Mutate and repack
    try std.testing.expect(save.setInt("PlayerGold", 123456));
    const repacked = try save.serialize(alloc);
    defer alloc.free(repacked);

    try std.testing.expect(std.mem.indexOf(u8, repacked, "<pref name=\"PlayerGold\" type=\"int\">123456</pref>") != null);
}

test "Aikya Sutra: Unity BinaryFormatter NRBF stream creation & mutation" {
    const alloc = std.testing.allocator;

    // Create a mock NRBF stream
    var nrbf_buf = std.ArrayList(u8).empty;
    defer nrbf_buf.deinit(alloc);

    // SerializationHeaderRecord (17 bytes)
    try nrbf_buf.appendSlice(alloc, &[_]u8{
        0x00,                               // RecordTypeEnum.SerializedStreamHeader
        0x01, 0x00, 0x00, 0x00,             // RootId = 1
        0xFF, 0xFF, 0xFF, 0xFF,             // HeaderId = -1
        0x01, 0x00, 0x00, 0x00,             // MajorVersion = 1
        0x00, 0x00, 0x00, 0x00,             // MinorVersion = 0
    });

    // SystemClassWithMembersAndTypes (RecordType 4)
    try nrbf_buf.append(alloc, 0x04);
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x01, 0x00, 0x00, 0x00 }); // ObjectId = 1
    // Class name: "GameSaveData"
    try write7BitEncodedInt(&nrbf_buf, alloc, 12);
    try nrbf_buf.appendSlice(alloc, "GameSaveData");
    // Member count: 2
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x02, 0x00, 0x00, 0x00 });
    // Member 1 name: "PlayerGold"
    try write7BitEncodedInt(&nrbf_buf, alloc, 10);
    try nrbf_buf.appendSlice(alloc, "PlayerGold");
    // Member 2 name: "PlayerHealth"
    try write7BitEncodedInt(&nrbf_buf, alloc, 12);
    try nrbf_buf.appendSlice(alloc, "PlayerHealth");
    // BinaryTypeEnums: Primitive (0), Primitive (0)
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x00, 0x00 });
    // AdditionalTypeInfo: Int32 (8), Single (11)
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x08, 0x0B });

    // Values:
    // PlayerGold = 88888 (0x00015B38)
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x38, 0x5B, 0x01, 0x00 });
    // PlayerHealth = 100.0f (0x42C80000)
    try nrbf_buf.appendSlice(alloc, &[_]u8{ 0x00, 0x00, 0xC8, 0x42 });

    // MessageEnd (0x0B)
    try nrbf_buf.append(alloc, 0x0B);

    var save = try parseUnitySave(alloc, nrbf_buf.items);
    defer {
        save.deinit();
        alloc.destroy(save);
    }

    try std.testing.expectEqual(UnitySaveFormat.BinaryFormatter, save.format);
    try std.testing.expectEqualStrings("GameSaveData", save.class_name);
    try std.testing.expectEqual(@as(usize, 2), save.properties.items.len);

    try std.testing.expectEqual(@as(i32, 88888), save.getInt("PlayerGold").?);
    try std.testing.expectEqual(@as(f32, 100.0), save.getFloat("PlayerHealth").?);

    // Mutate in-place
    try std.testing.expect(save.setInt("PlayerGold", 999999));
    try std.testing.expectEqual(@as(i32, 999999), save.getInt("PlayerGold").?);

    const repacked = try save.serialize(alloc);
    defer alloc.free(repacked);

    // Verify raw bytes were modified in-place
    const gold_offset = save.findProperty("PlayerGold").?.offset;
    const val_in_buf = std.mem.readInt(i32, repacked[gold_offset..][0..4], .little);
    try std.testing.expectEqual(@as(i32, 999999), val_in_buf);
}
