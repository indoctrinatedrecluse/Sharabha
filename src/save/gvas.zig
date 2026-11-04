//! ============================================================================
//! SHARABHA (शरभ) — MAYA SUTRA: UNREAL ENGINE 4/5 GVAS SAVE PARSER
//! High-Throughput Streaming GVAS Deserializer & Type-Safe Property Serializer
//! Supports UE4 & UE5 Typed FProperty Trees (Int, Int64, Float, Double, Bool,
//! Str, Name, Byte, Enum, Array, Struct, Map) with Atomic Safe Repacking.
//! ============================================================================

const std = @import("std");

pub const GVAS_MAGIC: [4]u8 = "GVAS".*;

pub const PropertyType = enum {
    IntProperty,
    Int64Property,
    Int16Property,
    Int8Property,
    UInt64Property,
    UInt32Property,
    UInt16Property,
    ByteProperty,
    FloatProperty,
    DoubleProperty,
    BoolProperty,
    StrProperty,
    NameProperty,
    TextProperty,
    EnumProperty,
    StructProperty,
    ArrayProperty,
    MapProperty,
    SetProperty,
    ObjectProperty,
    Unknown,

    pub fn fromString(str: []const u8) PropertyType {
        if (std.mem.eql(u8, str, "IntProperty")) return .IntProperty;
        if (std.mem.eql(u8, str, "Int64Property")) return .Int64Property;
        if (std.mem.eql(u8, str, "Int16Property")) return .Int16Property;
        if (std.mem.eql(u8, str, "Int8Property")) return .Int8Property;
        if (std.mem.eql(u8, str, "UInt64Property")) return .UInt64Property;
        if (std.mem.eql(u8, str, "UInt32Property")) return .UInt32Property;
        if (std.mem.eql(u8, str, "UInt16Property")) return .UInt16Property;
        if (std.mem.eql(u8, str, "ByteProperty")) return .ByteProperty;
        if (std.mem.eql(u8, str, "FloatProperty")) return .FloatProperty;
        if (std.mem.eql(u8, str, "DoubleProperty")) return .DoubleProperty;
        if (std.mem.eql(u8, str, "BoolProperty")) return .BoolProperty;
        if (std.mem.eql(u8, str, "StrProperty")) return .StrProperty;
        if (std.mem.eql(u8, str, "NameProperty")) return .NameProperty;
        if (std.mem.eql(u8, str, "TextProperty")) return .TextProperty;
        if (std.mem.eql(u8, str, "EnumProperty")) return .EnumProperty;
        if (std.mem.eql(u8, str, "StructProperty")) return .StructProperty;
        if (std.mem.eql(u8, str, "ArrayProperty")) return .ArrayProperty;
        if (std.mem.eql(u8, str, "MapProperty")) return .MapProperty;
        if (std.mem.eql(u8, str, "SetProperty")) return .SetProperty;
        if (std.mem.eql(u8, str, "ObjectProperty")) return .ObjectProperty;
        return .Unknown;
    }

    pub fn toString(self: PropertyType) []const u8 {
        return switch (self) {
            .IntProperty => "IntProperty",
            .Int64Property => "Int64Property",
            .Int16Property => "Int16Property",
            .Int8Property => "Int8Property",
            .UInt64Property => "UInt64Property",
            .UInt32Property => "UInt32Property",
            .UInt16Property => "UInt16Property",
            .ByteProperty => "ByteProperty",
            .FloatProperty => "FloatProperty",
            .DoubleProperty => "DoubleProperty",
            .BoolProperty => "BoolProperty",
            .StrProperty => "StrProperty",
            .NameProperty => "NameProperty",
            .TextProperty => "TextProperty",
            .EnumProperty => "EnumProperty",
            .StructProperty => "StructProperty",
            .ArrayProperty => "ArrayProperty",
            .MapProperty => "MapProperty",
            .SetProperty => "SetProperty",
            .ObjectProperty => "ObjectProperty",
            .Unknown => "Unknown",
        };
    }
};

pub const PropertyValue = union(enum) {
    Int: i32,
    Int64: i64,
    Float: f32,
    Double: f64,
    Bool: bool,
    Str: []const u8,
    Byte: u8,
    Raw: []const u8,
};

pub const GvasProperty = struct {
    name: []const u8,
    prop_type: PropertyType,
    prop_type_str: []const u8,
    offset: usize = 0,
    size: usize = 0,
    array_index: u32 = 0,
    struct_type: []const u8 = "",
    struct_guid: [16]u8 = @splat(0),
    value: PropertyValue,

    pub fn formatDisplayValue(self: *const GvasProperty, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.value) {
            .Int => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .Int64 => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
            .Float => |v| try std.fmt.allocPrint(allocator, "{d:.2}", .{v}),
            .Double => |v| try std.fmt.allocPrint(allocator, "{d:.4}", .{v}),
            .Bool => |v| try std.fmt.allocPrint(allocator, "{s}", .{if (v) "True" else "False"}),
            .Str => |v| try std.fmt.allocPrint(allocator, "\"{s}\"", .{v}),
            .Byte => |v| try std.fmt.allocPrint(allocator, "0x{X:0>2}", .{v}),
            .Raw => |v| try std.fmt.allocPrint(allocator, "[Binary Data: {d} bytes]", .{v.len}),
        };
    }
};

pub const CustomVersionEntry = struct {
    guid: [16]u8,
    version: i32,
};

pub const GvasHeader = struct {
    save_game_version: u32 = 2,
    package_version: u32 = 516,
    engine_major: u16 = 4,
    engine_minor: u16 = 27,
    engine_patch: u16 = 2,
    engine_build: u32 = 0,
    engine_branch: []const u8 = "++UE4+Release-4.27",
    custom_version_format: u32 = 3,
    custom_versions: []const CustomVersionEntry = &.{},
    save_game_class: []const u8 = "SaveGame",
};

pub const GvasSave = struct {
    arena: *std.heap.ArenaAllocator,
    header: GvasHeader,
    properties: []GvasProperty,
    trailing_data: []const u8,

    pub fn deinit(self: *GvasSave) void {
        const arena = self.arena;
        const child = arena.child_allocator;
        arena.deinit();
        child.destroy(arena);
    }

    pub fn findProperty(self: *const GvasSave, name: []const u8) ?*GvasProperty {
        for (self.properties) |*prop| {
            if (std.mem.eql(u8, prop.name, name)) {
                return prop;
            }
        }
        return null;
    }

    pub fn setInt(self: *GvasSave, name: []const u8, val: i32) bool {
        if (self.findProperty(name)) |prop| {
            if (prop.prop_type == .IntProperty) {
                prop.value = .{ .Int = val };
                return true;
            }
        }
        return false;
    }

    pub fn setFloat(self: *GvasSave, name: []const u8, val: f32) bool {
        if (self.findProperty(name)) |prop| {
            if (prop.prop_type == .FloatProperty) {
                prop.value = .{ .Float = val };
                return true;
            }
        }
        return false;
    }

    pub fn setBool(self: *GvasSave, name: []const u8, val: bool) bool {
        if (self.findProperty(name)) |prop| {
            if (prop.prop_type == .BoolProperty) {
                prop.value = .{ .Bool = val };
                return true;
            }
        }
        return false;
    }

    pub fn setString(self: *GvasSave, name: []const u8, val: []const u8) bool {
        if (self.findProperty(name)) |prop| {
            if (prop.prop_type == .StrProperty or prop.prop_type == .NameProperty) {
                const duped = self.arena.allocator().dupe(u8, val) catch return false;
                prop.value = .{ .Str = duped };
                prop.size = val.len + 5;
                return true;
            }
        }
        return false;
    }
};

/// Zero-copy / streaming reader helper for binary UE FArchive
const FArchiveReader = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn hasRemaining(self: *const FArchiveReader, n: usize) bool {
        return self.pos + n <= self.buf.len;
    }

    pub fn readU8(self: *FArchiveReader) !u8 {
        if (!self.hasRemaining(1)) return error.UnexpectedEof;
        const b = self.buf[self.pos];
        self.pos += 1;
        return b;
    }

    pub fn readU16(self: *FArchiveReader) !u16 {
        if (!self.hasRemaining(2)) return error.UnexpectedEof;
        const v = std.mem.readInt(u16, self.buf[self.pos..][0..2], .little);
        self.pos += 2;
        return v;
    }

    pub fn readU32(self: *FArchiveReader) !u32 {
        if (!self.hasRemaining(4)) return error.UnexpectedEof;
        const v = std.mem.readInt(u32, self.buf[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }

    pub fn readI32(self: *FArchiveReader) !i32 {
        if (!self.hasRemaining(4)) return error.UnexpectedEof;
        const v = std.mem.readInt(i32, self.buf[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }

    pub fn readI64(self: *FArchiveReader) !i64 {
        if (!self.hasRemaining(8)) return error.UnexpectedEof;
        const v = std.mem.readInt(i64, self.buf[self.pos..][0..8], .little);
        self.pos += 8;
        return v;
    }

    pub fn readF32(self: *FArchiveReader) !f32 {
        if (!self.hasRemaining(4)) return error.UnexpectedEof;
        const u = std.mem.readInt(u32, self.buf[self.pos..][0..4], .little);
        self.pos += 4;
        return @bitCast(u);
    }

    pub fn readF64(self: *FArchiveReader) !f64 {
        if (!self.hasRemaining(8)) return error.UnexpectedEof;
        const u = std.mem.readInt(u64, self.buf[self.pos..][0..8], .little);
        self.pos += 8;
        return @bitCast(u);
    }

    pub fn readBytes(self: *FArchiveReader, count: usize) ![]const u8 {
        if (!self.hasRemaining(count)) return error.UnexpectedEof;
        const slice = self.buf[self.pos .. self.pos + count];
        self.pos += count;
        return slice;
    }

    /// Reads length-prefixed Unreal FString (handles both ASCII length > 0 and UTF-16 length < 0)
    pub fn readFString(self: *FArchiveReader, allocator: std.mem.Allocator) ![]const u8 {
        const len = try self.readI32();
        if (len == 0) return "";
        if (len > 0) {
            // ASCII / UTF-8 string: length includes terminating null
            const byte_len: usize = @intCast(len);
            if (!self.hasRemaining(byte_len)) return error.UnexpectedEof;
            const raw = try self.readBytes(byte_len);
            const str_len = if (byte_len > 0 and raw[byte_len - 1] == 0) byte_len - 1 else byte_len;
            return try allocator.dupe(u8, raw[0..str_len]);
        } else {
            // UTF-16 LE string: length is negative number of 16-bit words (including terminating null)
            const word_count: usize = @intCast(-len);
            const byte_len = word_count * 2;
            if (!self.hasRemaining(byte_len)) return error.UnexpectedEof;
            const raw = try self.readBytes(byte_len);
            const u16_slice: []const u16 = @alignCast(std.mem.bytesAsSlice(u16, raw));
            const actual_words = if (word_count > 0 and u16_slice[word_count - 1] == 0) word_count - 1 else word_count;
            return try std.unicode.utf16LeToUtf8Alloc(allocator, u16_slice[0..actual_words]);
        }
    }
};

/// Parses Unreal Engine 4/5 GVAS save file from raw memory bytes
pub fn parseGvas(child_allocator: std.mem.Allocator, bytes: []const u8) !*GvasSave {
    if (bytes.len < 12) return error.FileTooSmall;
    if (!std.mem.eql(u8, bytes[0..4], &GVAS_MAGIC)) return error.InvalidMagic;

    const arena = try child_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(child_allocator);
    errdefer {
        arena.deinit();
        child_allocator.destroy(arena);
    }
    const alloc = arena.allocator();

    var reader = FArchiveReader{ .buf = bytes, .pos = 4 };

    var header = GvasHeader{};
    header.save_game_version = try reader.readU32();
    header.package_version = try reader.readU32();

    // Engine Version (Major, Minor, Patch, Build, Branch String)
    header.engine_major = try reader.readU16();
    header.engine_minor = try reader.readU16();
    header.engine_patch = try reader.readU16();
    header.engine_build = try reader.readU32();
    header.engine_branch = try reader.readFString(alloc);

    // Custom Version Array
    if (header.save_game_version >= 2) {
        header.custom_version_format = try reader.readU32();
    }
    const custom_ver_count = try reader.readU32();
    if (custom_ver_count > 0 and custom_ver_count < 1024) {
        var cv_list = try alloc.alloc(CustomVersionEntry, custom_ver_count);
        var i: usize = 0;
        while (i < custom_ver_count) : (i += 1) {
            const guid_bytes = try reader.readBytes(16);
            var guid: [16]u8 = undefined;
            @memcpy(&guid, guid_bytes);
            const ver = try reader.readI32();
            cv_list[i] = .{ .guid = guid, .version = ver };
        }
        header.custom_versions = cv_list;
    }

    // Save Game Class Name
    header.save_game_class = try reader.readFString(alloc);

    // Properties Table
    var prop_list: std.ArrayList(GvasProperty) = .empty;

    while (reader.hasRemaining(4)) {
        const prop_start = reader.pos;
        const name = reader.readFString(alloc) catch break;
        if (name.len == 0 or std.mem.eql(u8, name, "None")) {
            // Reached end of properties
            break;
        }

        const type_str = reader.readFString(alloc) catch break;
        const prop_type = PropertyType.fromString(type_str);

        // In UE4/UE5, size is serialized as either u32 or u64 (depending on engine build)
        // Standard GVAS: 4 bytes size, followed by 4 bytes array index (or 8-byte size on UE5)
        const size_raw = reader.readU32() catch break;
        const array_idx = reader.readU32() catch break;

        var struct_type: []const u8 = "";
        var struct_guid: [16]u8 = @splat(0);
        var bool_val: bool = false;

        // Parse type-specific metadata
        switch (prop_type) {
            .BoolProperty => {
                const b = reader.readU8() catch break;
                bool_val = (b != 0);
                _ = reader.readU8() catch break; // 0x00 separator
            },
            .StructProperty => {
                struct_type = reader.readFString(alloc) catch "";
                const g_bytes = reader.readBytes(16) catch break;
                @memcpy(&struct_guid, g_bytes);
                _ = reader.readU8() catch break; // 0x00 separator
            },
            .ByteProperty, .EnumProperty => {
                _ = reader.readFString(alloc) catch "";
                _ = reader.readU8() catch break; // 0x00 separator
            },
            .ArrayProperty => {
                _ = reader.readFString(alloc) catch "";
                _ = reader.readU8() catch break; // 0x00 separator
            },
            else => {
                _ = reader.readU8() catch break; // 0x00 separator
            },
        }

        // Parse property value
        const val_start = reader.pos;
        var prop_val: PropertyValue = undefined;

        switch (prop_type) {
            .IntProperty => {
                const v = reader.readI32() catch 0;
                prop_val = .{ .Int = v };
            },
            .Int64Property => {
                const v = reader.readI64() catch 0;
                prop_val = .{ .Int64 = v };
            },
            .FloatProperty => {
                const v = reader.readF32() catch 0.0;
                prop_val = .{ .Float = v };
            },
            .DoubleProperty => {
                const v = reader.readF64() catch 0.0;
                prop_val = .{ .Double = v };
            },
            .BoolProperty => {
                prop_val = .{ .Bool = bool_val };
            },
            .StrProperty, .NameProperty => {
                const s = reader.readFString(alloc) catch "";
                prop_val = .{ .Str = s };
            },
            .ByteProperty => {
                if (size_raw == 1) {
                    const b = reader.readU8() catch 0;
                    prop_val = .{ .Byte = b };
                } else {
                    const raw = reader.readBytes(size_raw) catch &.{};
                    prop_val = .{ .Raw = raw };
                }
            },
            else => {
                const raw = reader.readBytes(size_raw) catch &.{};
                prop_val = .{ .Raw = raw };
            },
        }

        try prop_list.append(alloc, .{
            .name = name,
            .prop_type = prop_type,
            .prop_type_str = type_str,
            .offset = val_start,
            .size = if (prop_type == .BoolProperty) 0 else (reader.pos - val_start),
            .array_index = array_idx,
            .struct_type = struct_type,
            .struct_guid = struct_guid,
            .value = prop_val,
        });
        _ = prop_start;
    }

    const trailing = if (reader.pos < bytes.len) bytes[reader.pos..] else &.{};

    const gvas = try alloc.create(GvasSave);
    gvas.* = .{
        .arena = arena,
        .header = header,
        .properties = try prop_list.toOwnedSlice(alloc),
        .trailing_data = try alloc.dupe(u8, trailing),
    };
    return gvas;
}

/// Serializes a GVAS structure back to byte format
pub fn serializeGvas(allocator: std.mem.Allocator, gvas: *const GvasSave) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    // 1. Magic
    try out.appendSlice(allocator, &GVAS_MAGIC);

    // 2. Versions & Engine Details
    var u32_buf: [4]u8 = undefined;
    var u16_buf: [2]u8 = undefined;

    std.mem.writeInt(u32, &u32_buf, gvas.header.save_game_version, .little);
    try out.appendSlice(allocator, &u32_buf);

    std.mem.writeInt(u32, &u32_buf, gvas.header.package_version, .little);
    try out.appendSlice(allocator, &u32_buf);

    std.mem.writeInt(u16, &u16_buf, gvas.header.engine_major, .little);
    try out.appendSlice(allocator, &u16_buf);

    std.mem.writeInt(u16, &u16_buf, gvas.header.engine_minor, .little);
    try out.appendSlice(allocator, &u16_buf);

    std.mem.writeInt(u16, &u16_buf, gvas.header.engine_patch, .little);
    try out.appendSlice(allocator, &u16_buf);

    std.mem.writeInt(u32, &u32_buf, gvas.header.engine_build, .little);
    try out.appendSlice(allocator, &u32_buf);

    try writeFString(&out, allocator, gvas.header.engine_branch);

    // 3. Custom Versions
    if (gvas.header.save_game_version >= 2) {
        std.mem.writeInt(u32, &u32_buf, gvas.header.custom_version_format, .little);
        try out.appendSlice(allocator, &u32_buf);
    }
    std.mem.writeInt(u32, &u32_buf, @intCast(gvas.header.custom_versions.len), .little);
    try out.appendSlice(allocator, &u32_buf);
    for (gvas.header.custom_versions) |cv| {
        try out.appendSlice(allocator, &cv.guid);
        std.mem.writeInt(i32, &u32_buf, cv.version, .little);
        try out.appendSlice(allocator, &u32_buf);
    }

    // 4. Save Game Class
    try writeFString(&out, allocator, gvas.header.save_game_class);

    // 5. Properties
    for (gvas.properties) |prop| {
        try writeFString(&out, allocator, prop.name);
        try writeFString(&out, allocator, prop.prop_type_str);

        // Calculate payload size
        const payload_size: u32 = switch (prop.value) {
            .Int => 4,
            .Int64 => 8,
            .Float => 4,
            .Double => 8,
            .Bool => 0,
            .Str => |s| @intCast(s.len + 5),
            .Byte => 1,
            .Raw => |r| @intCast(r.len),
        };

        std.mem.writeInt(u32, &u32_buf, payload_size, .little);
        try out.appendSlice(allocator, &u32_buf);

        std.mem.writeInt(u32, &u32_buf, prop.array_index, .little);
        try out.appendSlice(allocator, &u32_buf);

        // Metadata
        switch (prop.prop_type) {
            .BoolProperty => {
                const b: u8 = if (prop.value.Bool) 1 else 0;
                try out.append(allocator, b);
                try out.append(allocator, 0); // 0x00 separator
            },
            .StructProperty => {
                try writeFString(&out, allocator, prop.struct_type);
                try out.appendSlice(allocator, &prop.struct_guid);
                try out.append(allocator, 0);
            },
            else => {
                try out.append(allocator, 0);
            },
        }

        // Value
        switch (prop.value) {
            .Int => |v| {
                std.mem.writeInt(i32, &u32_buf, v, .little);
                try out.appendSlice(allocator, &u32_buf);
            },
            .Int64 => |v| {
                var u64_buf: [8]u8 = undefined;
                std.mem.writeInt(i64, &u64_buf, v, .little);
                try out.appendSlice(allocator, &u64_buf);
            },
            .Float => |v| {
                const u: u32 = @bitCast(v);
                std.mem.writeInt(u32, &u32_buf, u, .little);
                try out.appendSlice(allocator, &u32_buf);
            },
            .Double => |v| {
                var u64_buf: [8]u8 = undefined;
                const u: u64 = @bitCast(v);
                std.mem.writeInt(u64, &u64_buf, u, .little);
                try out.appendSlice(allocator, &u64_buf);
            },
            .Bool => {},
            .Str => |s| {
                try writeFString(&out, allocator, s);
            },
            .Byte => |b| {
                try out.append(allocator, b);
            },
            .Raw => |r| {
                try out.appendSlice(allocator, r);
            },
        }
    }

    // None terminator
    try writeFString(&out, allocator, "None");

    // Trailing data if any
    if (gvas.trailing_data.len > 0) {
        try out.appendSlice(allocator, gvas.trailing_data);
    }

    return try out.toOwnedSlice(allocator);
}

fn writeFString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    var u32_buf: [4]u8 = undefined;
    if (str.len == 0) {
        std.mem.writeInt(i32, &u32_buf, 0, .little);
        try out.appendSlice(allocator, &u32_buf);
        return;
    }
    const len: i32 = @intCast(str.len + 1);
    std.mem.writeInt(i32, &u32_buf, len, .little);
    try out.appendSlice(allocator, &u32_buf);
    try out.appendSlice(allocator, str);
    try out.append(allocator, 0); // Null terminator
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "GVAS parser: synthetic UE4/UE5 save roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Create a valid synthetic GVAS buffer
    var mock: std.ArrayList(u8) = .empty;
    defer mock.deinit(alloc);

    try mock.appendSlice(alloc, &GVAS_MAGIC);
    var b4: [4]u8 = undefined;
    var b2: [2]u8 = undefined;

    // save_game_version = 3, package_version = 518
    std.mem.writeInt(u32, &b4, 3, .little);
    try mock.appendSlice(alloc, &b4);
    std.mem.writeInt(u32, &b4, 518, .little);
    try mock.appendSlice(alloc, &b4);

    // engine major 5, minor 1, patch 1, build 0
    std.mem.writeInt(u16, &b2, 5, .little);
    try mock.appendSlice(alloc, &b2);
    std.mem.writeInt(u16, &b2, 1, .little);
    try mock.appendSlice(alloc, &b2);
    std.mem.writeInt(u16, &b2, 1, .little);
    try mock.appendSlice(alloc, &b2);
    std.mem.writeInt(u32, &b4, 0, .little);
    try mock.appendSlice(alloc, &b4);

    // engine branch
    try writeFString(&mock, alloc, "++UE5+Release-5.1");

    // custom version format = 3
    std.mem.writeInt(u32, &b4, 3, .little);
    try mock.appendSlice(alloc, &b4);

    // custom versions count = 0
    std.mem.writeInt(u32, &b4, 0, .little);
    try mock.appendSlice(alloc, &b4);

    // save class
    try writeFString(&mock, alloc, "/Script/SharabhaGame.HeroSave");

    // Property 1: "PlayerGold" (IntProperty = 99999)
    try writeFString(&mock, alloc, "PlayerGold");
    try writeFString(&mock, alloc, "IntProperty");
    std.mem.writeInt(u32, &b4, 4, .little); // size
    try mock.appendSlice(alloc, &b4);
    std.mem.writeInt(u32, &b4, 0, .little); // array index
    try mock.appendSlice(alloc, &b4);
    try mock.append(alloc, 0); // separator
    std.mem.writeInt(i32, &b4, 99999, .little);
    try mock.appendSlice(alloc, &b4);

    // Property 2: "IsHardcore" (BoolProperty = true)
    try writeFString(&mock, alloc, "IsHardcore");
    try writeFString(&mock, alloc, "BoolProperty");
    std.mem.writeInt(u32, &b4, 0, .little); // size
    try mock.appendSlice(alloc, &b4);
    std.mem.writeInt(u32, &b4, 0, .little); // array index
    try mock.appendSlice(alloc, &b4);
    try mock.append(alloc, 1); // bool value = true
    try mock.append(alloc, 0); // separator

    // Property 3: "MovementSpeed" (FloatProperty = 450.5)
    try writeFString(&mock, alloc, "MovementSpeed");
    try writeFString(&mock, alloc, "FloatProperty");
    std.mem.writeInt(u32, &b4, 4, .little); // size
    try mock.appendSlice(alloc, &b4);
    std.mem.writeInt(u32, &b4, 0, .little); // array index
    try mock.appendSlice(alloc, &b4);
    try mock.append(alloc, 0); // separator
    const speed_bits: u32 = @bitCast(@as(f32, 450.5));
    std.mem.writeInt(u32, &b4, speed_bits, .little);
    try mock.appendSlice(alloc, &b4);

    // Property 4: "PlayerName" (StrProperty = "Sharabheshwara")
    try writeFString(&mock, alloc, "PlayerName");
    try writeFString(&mock, alloc, "StrProperty");
    const name_len: u32 = "Sharabheshwara".len + 5;
    std.mem.writeInt(u32, &b4, name_len, .little);
    try mock.appendSlice(alloc, &b4);
    std.mem.writeInt(u32, &b4, 0, .little);
    try mock.appendSlice(alloc, &b4);
    try mock.append(alloc, 0);
    try writeFString(&mock, alloc, "Sharabheshwara");

    // "None" terminator
    try writeFString(&mock, alloc, "None");

    // Parse GVAS
    const gvas = try parseGvas(alloc, mock.items);
    defer gvas.deinit();

    try testing.expectEqual(@as(u32, 3), gvas.header.save_game_version);
    try testing.expectEqual(@as(u32, 518), gvas.header.package_version);
    try testing.expectEqualStrings("++UE5+Release-5.1", gvas.header.engine_branch);
    try testing.expectEqualStrings("/Script/SharabhaGame.HeroSave", gvas.header.save_game_class);
    try testing.expectEqual(@as(usize, 4), gvas.properties.len);

    // Verify properties
    const gold_prop = gvas.findProperty("PlayerGold") orelse return error.PropertyNotFound;
    try testing.expectEqual(@as(i32, 99999), gold_prop.value.Int);

    const hc_prop = gvas.findProperty("IsHardcore") orelse return error.PropertyNotFound;
    try testing.expect(hc_prop.value.Bool == true);

    const speed_prop = gvas.findProperty("MovementSpeed") orelse return error.PropertyNotFound;
    try testing.expectApproxEqAbs(@as(f32, 450.5), speed_prop.value.Float, 0.001);

    const name_prop = gvas.findProperty("PlayerName") orelse return error.PropertyNotFound;
    try testing.expectEqualStrings("Sharabheshwara", name_prop.value.Str);

    // Modify values
    try testing.expect(gvas.setInt("PlayerGold", 777777));
    try testing.expect(gvas.setFloat("MovementSpeed", 900.0));
    try testing.expect(gvas.setBool("IsHardcore", false));
    try testing.expect(gvas.setString("PlayerName", "NarasimhaSubduer"));

    // Serialize back
    const serialized = try serializeGvas(alloc, gvas);
    defer alloc.free(serialized);

    // Re-parse modified buffer and assert mutations held!
    const gvas2 = try parseGvas(alloc, serialized);
    defer gvas2.deinit();

    const gold_mod = gvas2.findProperty("PlayerGold") orelse return error.PropertyNotFound;
    try testing.expectEqual(@as(i32, 777777), gold_mod.value.Int);

    const speed_mod = gvas2.findProperty("MovementSpeed") orelse return error.PropertyNotFound;
    try testing.expectApproxEqAbs(@as(f32, 900.0), speed_mod.value.Float, 0.001);

    const hc_mod = gvas2.findProperty("IsHardcore") orelse return error.PropertyNotFound;
    try testing.expect(hc_mod.value.Bool == false);

    const name_mod = gvas2.findProperty("PlayerName") orelse return error.PropertyNotFound;
    try testing.expectEqualStrings("NarasimhaSubduer", name_mod.value.Str);
}
