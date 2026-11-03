//! ============================================================================
//! SHARABHA (शरभ) — MEMORY TABLE WORKSPACE (.sharabha Cheat Table)
//! Persistent workspace serialization for memory records, pointer chains,
//! freeze sentinels, hotkeys, and embedded Lua Altar scripts.
//! Equivalent to Cheat Engine (.CT) tables, adorned with Vedic duality.
//!
//! ॐ नमः शरभाय — The indelible registry of memory mutations.
//! ============================================================================

const std = @import("std");
const process = @import("process.zig");
const win = process.win;
const pointer = @import("pointer.zig");
const freeze = @import("freeze.zig");

pub const AddressType = enum {
    StaticAddress,
    PointerChain,
    AobSignature,

    pub fn toString(self: AddressType) []const u8 {
        return switch (self) {
            .StaticAddress => "StaticAddress",
            .PointerChain => "PointerChain",
            .AobSignature => "AobSignature",
        };
    }

    pub fn fromString(str: []const u8) AddressType {
        if (std.ascii.eqlIgnoreCase(str, "PointerChain") or std.ascii.eqlIgnoreCase(str, "pointer")) {
            return .PointerChain;
        } else if (std.ascii.eqlIgnoreCase(str, "AobSignature") or std.ascii.eqlIgnoreCase(str, "aob")) {
            return .AobSignature;
        }
        return .StaticAddress;
    }
};

pub const TableValueType = enum {
    Int32,
    UInt32,
    Int64,
    UInt64,
    Float32,
    Float64,
    Byte,
    TextString,

    pub fn toString(self: TableValueType) []const u8 {
        return switch (self) {
            .Int32 => "i32",
            .UInt32 => "u32",
            .Int64 => "i64",
            .UInt64 => "u64",
            .Float32 => "f32",
            .Float64 => "f64",
            .Byte => "byte",
            .TextString => "string",
        };
    }

    pub fn fromString(str: []const u8) TableValueType {
        if (std.ascii.eqlIgnoreCase(str, "u32")) return .UInt32;
        if (std.ascii.eqlIgnoreCase(str, "i64")) return .Int64;
        if (std.ascii.eqlIgnoreCase(str, "u64")) return .UInt64;
        if (std.ascii.eqlIgnoreCase(str, "f32") or std.ascii.eqlIgnoreCase(str, "float")) return .Float32;
        if (std.ascii.eqlIgnoreCase(str, "f64") or std.ascii.eqlIgnoreCase(str, "double")) return .Float64;
        if (std.ascii.eqlIgnoreCase(str, "byte") or std.ascii.eqlIgnoreCase(str, "u8")) return .Byte;
        if (std.ascii.eqlIgnoreCase(str, "string") or std.ascii.eqlIgnoreCase(str, "text")) return .TextString;
        return .Int32;
    }
};

pub const TableRecord = struct {
    id: u32,
    description: []const u8,
    sanskrit_label: []const u8,
    address_type: AddressType,
    static_address: usize = 0,
    module_name: []const u8 = "",
    base_offset: usize = 0,
    level_offsets: [6]usize = @splat(0),
    level_count: usize = 0,
    aob_pattern: []const u8 = "",
    value_type: TableValueType = .Int32,
    freeze_value: []const u8 = "",
    is_frozen: bool = false,
    hotkey: []const u8 = "",
};

pub const TableScript = struct {
    name: []const u8,
    sanskrit_name: []const u8 = "",
    script_body: []const u8,
    auto_run: bool = false,
};

pub const SharabhaTable = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    title: []const u8,
    sanskrit_title: []const u8,
    process_name: []const u8,
    architecture: []const u8,
    version: u32,
    records: std.ArrayList(TableRecord),
    scripts: std.ArrayList(TableScript),
    annotations: []const u8,

    pub fn init(
        child_allocator: std.mem.Allocator,
        title: []const u8,
        process_name: []const u8,
    ) SharabhaTable {
        const arena = child_allocator.create(std.heap.ArenaAllocator) catch @panic("OOM");
        arena.* = std.heap.ArenaAllocator.init(child_allocator);
        const alloc = arena.allocator();
        return SharabhaTable{
            .arena = arena,
            .allocator = alloc,
            .title = alloc.dupe(u8, title) catch title,
            .sanskrit_title = "रुद्र ताण्डव महासारिणी",
            .process_name = alloc.dupe(u8, process_name) catch process_name,
            .architecture = "x64",
            .version = 1,
            .records = .empty,
            .scripts = .empty,
            .annotations = "",
        };
    }

    pub fn deinit(self: *SharabhaTable) void {
        const child_alloc = self.arena.child_allocator;
        self.arena.deinit();
        child_alloc.destroy(self.arena);
    }

    pub fn addRecord(self: *SharabhaTable, record: TableRecord) !void {
        try self.records.append(self.allocator, record);
    }

    pub fn addScript(self: *SharabhaTable, script: TableScript) !void {
        try self.scripts.append(self.allocator, script);
    }

    /// Serializes the entire table into JSON format
    pub fn exportJson(self: *const SharabhaTable, list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        var buf: [1024]u8 = undefined;
        try list.appendSlice(allocator, "{\n");
        const h1 = try std.fmt.bufPrint(&buf, "  \"magic\": \"SHARABHA_TABLE_V1\",\n  \"version\": {d},\n  \"title\": \"{s}\",\n  \"sanskrit_title\": \"{s}\",\n  \"process_name\": \"{s}\",\n  \"architecture\": \"{s}\",\n  \"annotations\": \"{s}\",\n  \"records\": [\n", .{
            self.version,
            self.title,
            self.sanskrit_title,
            self.process_name,
            self.architecture,
            self.annotations,
        });
        try list.appendSlice(allocator, h1);

        // Records Array
        for (self.records.items, 0..) |rec, i| {
            try list.appendSlice(allocator, "    {\n");
            const r1 = try std.fmt.bufPrint(&buf, "      \"id\": {d},\n      \"description\": \"{s}\",\n      \"sanskrit_label\": \"{s}\",\n      \"address_type\": \"{s}\",\n      \"static_address\": \"0x{X}\",\n      \"module_name\": \"{s}\",\n      \"base_offset\": \"0x{X}\",\n", .{
                rec.id,
                rec.description,
                rec.sanskrit_label,
                rec.address_type.toString(),
                rec.static_address,
                rec.module_name,
                rec.base_offset,
            });
            try list.appendSlice(allocator, r1);

            // Offsets array
            try list.appendSlice(allocator, "      \"level_offsets\": [");
            var j: usize = 0;
            while (j < rec.level_count) : (j += 1) {
                if (j > 0) try list.appendSlice(allocator, ", ");
                const o_str = try std.fmt.bufPrint(&buf, "\"0x{X}\"", .{rec.level_offsets[j]});
                try list.appendSlice(allocator, o_str);
            }
            try list.appendSlice(allocator, "],\n");

            const r2 = try std.fmt.bufPrint(&buf, "      \"aob_pattern\": \"{s}\",\n      \"value_type\": \"{s}\",\n      \"freeze_value\": \"{s}\",\n      \"is_frozen\": {s},\n      \"hotkey\": \"{s}\"\n    {s}\n", .{
                rec.aob_pattern,
                rec.value_type.toString(),
                rec.freeze_value,
                if (rec.is_frozen) "true" else "false",
                rec.hotkey,
                if (i + 1 < self.records.items.len) "}," else "}",
            });
            try list.appendSlice(allocator, r2);
        }

        // Scripts Array
        try list.appendSlice(allocator, "  ],\n  \"scripts\": [\n");
        for (self.scripts.items, 0..) |sc, i| {
            try list.appendSlice(allocator, "    {\n");
            const s1 = try std.fmt.bufPrint(&buf, "      \"name\": \"{s}\",\n      \"sanskrit_name\": \"{s}\",\n      \"auto_run\": {s},\n      \"script_body\": \"", .{
                sc.name,
                sc.sanskrit_name,
                if (sc.auto_run) "true" else "false",
            });
            try list.appendSlice(allocator, s1);

            for (sc.script_body) |b| {
                if (b == '\n') {
                    try list.appendSlice(allocator, "\\n");
                } else if (b == '\r') {
                    // skip
                } else if (b == '"') {
                    try list.appendSlice(allocator, "\\\"");
                } else if (b == '\\') {
                    try list.appendSlice(allocator, "\\\\");
                } else {
                    const ch = [_]u8{b};
                    try list.appendSlice(allocator, &ch);
                }
            }
            const s2 = try std.fmt.bufPrint(&buf, "\"\n    {s}\n", .{if (i + 1 < self.scripts.items.len) "}," else "}"});
            try list.appendSlice(allocator, s2);
        }

        try list.appendSlice(allocator, "  ]\n}\n");
    }

    /// Saves the table to a `.sharabha` file on disk
    pub fn saveToFile(self: *const SharabhaTable, file_path: []const u8) !void {
        var path_buf: [512]u8 = undefined;
        var final_path = file_path;
        if (!std.mem.endsWith(u8, file_path, ".sharabha")) {
            final_path = try std.fmt.bufPrint(&path_buf, "{s}.sharabha", .{file_path});
        }

        const path_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, final_path);
        defer self.allocator.free(path_w);

        const hFile = process.win.OpenProcess(0, 0, 0); // dummy check
        _ = hFile;

        // Use standard Win32 CreateFileW via process.win
        const GENERIC_WRITE: u32 = 0x40000000;
        const CREATE_ALWAYS: u32 = 2;
        const FILE_ATTRIBUTE_NORMAL: u32 = 0x00000080;

        const CreateFileW_fn = struct {
            pub extern "kernel32" fn CreateFileW(
                lpFileName: [*:0]const u16,
                dwDesiredAccess: u32,
                dwShareMode: u32,
                lpSecurityAttributes: ?*anyopaque,
                dwCreationDistribution: u32,
                dwFlagsAndAttributes: u32,
                hTemplateFile: ?process.win.HANDLE,
            ) callconv(.winapi) process.win.HANDLE;
        }.CreateFileW;

        const handle = CreateFileW_fn(
            path_w.ptr,
            GENERIC_WRITE,
            0,
            null,
            CREATE_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            null,
        );

        if (handle == process.win.INVALID_HANDLE_VALUE) {
            return error.FileCreationFailed;
        }
        defer _ = process.win.CloseHandle(handle);

        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(self.allocator);
        try self.exportJson(&list, self.allocator);

        var written: u32 = 0;
        const write_res = process.win.WriteFile(
            handle,
            list.items.ptr,
            @as(u32, @intCast(list.items.len)),
            &written,
            null,
        );
        if (write_res == 0 or written != list.items.len) {
            return error.FileWriteFailed;
        }
    }

    /// Loads a table from a `.sharabha` file on disk
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !SharabhaTable {
        const path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, file_path);
        defer allocator.free(path_w);

        const GENERIC_READ: u32 = 0x80000000;
        const OPEN_EXISTING: u32 = 3;
        const FILE_ATTRIBUTE_NORMAL: u32 = 0x00000080;

        const CreateFileW_fn = struct {
            pub extern "kernel32" fn CreateFileW(
                lpFileName: [*:0]const u16,
                dwDesiredAccess: u32,
                dwShareMode: u32,
                lpSecurityAttributes: ?*anyopaque,
                dwCreationDistribution: u32,
                dwFlagsAndAttributes: u32,
                hTemplateFile: ?process.win.HANDLE,
            ) callconv(.winapi) process.win.HANDLE;
            pub extern "kernel32" fn ReadFile(
                hFile: process.win.HANDLE,
                lpBuffer: [*]u8,
                nNumberOfBytesToRead: u32,
                lpNumberOfBytesRead: ?*u32,
                lpOverlapped: ?*anyopaque,
            ) callconv(.winapi) i32;
            pub extern "kernel32" fn GetFileSize(hFile: process.win.HANDLE, lpFileSizeHigh: ?*u32) callconv(.winapi) u32;
        };

        const handle = CreateFileW_fn.CreateFileW(
            path_w.ptr,
            GENERIC_READ,
            1, // FILE_SHARE_READ
            null,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            null,
        );

        if (handle == process.win.INVALID_HANDLE_VALUE) {
            return error.FileNotFound;
        }
        defer _ = process.win.CloseHandle(handle);

        var high_size: u32 = 0;
        const file_size = CreateFileW_fn.GetFileSize(handle, &high_size);
        if (file_size == 0 or file_size == 0xFFFFFFFF) {
            return error.InvalidFileSize;
        }

        const buf = try allocator.alloc(u8, file_size);
        defer allocator.free(buf);

        var bytes_read: u32 = 0;
        const read_ok = CreateFileW_fn.ReadFile(handle, buf.ptr, file_size, &bytes_read, null);
        if (read_ok == 0 or bytes_read != file_size) {
            return error.FileReadFailed;
        }

        return importJson(allocator, buf);
    }

    /// Parses a JSON buffer into a `SharabhaTable`
    pub fn importJson(allocator: std.mem.Allocator, json_text: []const u8) !SharabhaTable {
        // Fast schema verification
        if (std.mem.indexOf(u8, json_text, "SHARABHA_TABLE_V1") == null) {
            return error.InvalidTableMagic;
        }

        // Extract Title
        var title: []const u8 = "Sharabha Cheat Table";
        if (extractJsonField(json_text, "\"title\"")) |t| {
            title = t;
        }

        // Extract Process Name
        var proc_name: []const u8 = "game.exe";
        if (extractJsonField(json_text, "\"process_name\"")) |p| {
            proc_name = p;
        }

        var table = SharabhaTable.init(allocator, title, proc_name);

        if (extractJsonField(json_text, "\"annotations\"")) |ann| {
            table.annotations = table.allocator.dupe(u8, ann) catch ann;
        }

        // Parse records iteratively
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, json_text, search_pos, "\"id\":")) |id_idx| {
            const next_rec_end = std.mem.indexOfPos(u8, json_text, id_idx, "}") orelse json_text.len;
            const rec_slice = json_text[id_idx..next_rec_end];

            var rec = TableRecord{
                .id = 1,
                .description = "Value",
                .sanskrit_label = "मूल्य",
                .address_type = .StaticAddress,
            };

            if (extractJsonField(rec_slice, "\"description\"")) |d| {
                rec.description = table.allocator.dupe(u8, d) catch d;
            }
            if (extractJsonField(rec_slice, "\"sanskrit_label\"")) |sl| {
                rec.sanskrit_label = table.allocator.dupe(u8, sl) catch sl;
            }
            if (extractJsonField(rec_slice, "\"address_type\"")) |at| {
                rec.address_type = AddressType.fromString(at);
            }
            if (extractJsonField(rec_slice, "\"static_address\"")) |sa| {
                rec.static_address = parseHexOrDec(sa);
            }
            if (extractJsonField(rec_slice, "\"module_name\"")) |mn| {
                rec.module_name = table.allocator.dupe(u8, mn) catch mn;
            }
            if (extractJsonField(rec_slice, "\"base_offset\"")) |bo| {
                rec.base_offset = parseHexOrDec(bo);
            }
            if (extractJsonField(rec_slice, "\"value_type\"")) |vt| {
                rec.value_type = TableValueType.fromString(vt);
            }
            if (extractJsonField(rec_slice, "\"freeze_value\"")) |fv| {
                rec.freeze_value = table.allocator.dupe(u8, fv) catch fv;
            }
            if (extractJsonField(rec_slice, "\"is_frozen\"")) |fz| {
                rec.is_frozen = std.mem.eql(u8, fz, "true");
            }
            if (extractJsonField(rec_slice, "\"hotkey\"")) |hk| {
                rec.hotkey = table.allocator.dupe(u8, hk) catch hk;
            }

            // Extract level_offsets
            if (std.mem.indexOf(u8, rec_slice, "\"level_offsets\":")) |lo_idx| {
                const arr_start = std.mem.indexOfPos(u8, rec_slice, lo_idx, "[");
                const arr_end = std.mem.indexOfPos(u8, rec_slice, lo_idx, "]");
                if (arr_start != null and arr_end != null and arr_end.? > arr_start.?) {
                    const arr_str = rec_slice[arr_start.? + 1 .. arr_end.?];
                    var off_tok = std.mem.tokenizeAny(u8, arr_str, ", \t\r\n\"");
                    var count: usize = 0;
                    while (off_tok.next()) |elem| {
                        if (count < 6) {
                            rec.level_offsets[count] = parseHexOrDec(elem);
                            count += 1;
                        }
                    }
                    rec.level_count = count;
                }
            }

            try table.addRecord(rec);
            search_pos = next_rec_end;
        }

        // Parse scripts
        if (std.mem.indexOf(u8, json_text, "\"scripts\":")) |scripts_idx| {
            var sc_pos: usize = scripts_idx;
            while (std.mem.indexOfPos(u8, json_text, sc_pos, "\"name\":")) |name_idx| {
                const next_sc_end = std.mem.indexOfPos(u8, json_text, name_idx, "}") orelse json_text.len;
                const sc_slice = json_text[name_idx..next_sc_end];

                var sc = TableScript{
                    .name = "Altar Script",
                    .script_body = "-- Altar Script",
                    .auto_run = false,
                };

                if (extractJsonField(sc_slice, "\"name\"")) |n| {
                    sc.name = table.allocator.dupe(u8, n) catch n;
                }
                if (extractJsonField(sc_slice, "\"sanskrit_name\"")) |sn| {
                    sc.sanskrit_name = table.allocator.dupe(u8, sn) catch sn;
                }
                if (extractJsonField(sc_slice, "\"script_body\"")) |sb| {
                    sc.script_body = table.allocator.dupe(u8, sb) catch sb;
                }
                if (extractJsonField(sc_slice, "\"auto_run\"")) |ar| {
                    sc.auto_run = std.mem.eql(u8, ar, "true");
                }

                try table.addScript(sc);
                sc_pos = next_sc_end;
            }
        }

        return table;
    }
};

fn parseHexOrDec(str: []const u8) usize {
    const trimmed = std.mem.trim(u8, str, " \"'\r\n\t");
    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return std.fmt.parseInt(usize, trimmed[2..], 16) catch 0;
    }
    return std.fmt.parseInt(usize, trimmed, 10) catch 0;
}

fn extractJsonField(json_slice: []const u8, field_key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, json_slice, field_key) orelse return null;
    const colon_pos = std.mem.indexOfPos(u8, json_slice, key_pos + field_key.len, ":") orelse return null;
    var val_start = colon_pos + 1;
    while (val_start < json_slice.len and (json_slice[val_start] == ' ' or json_slice[val_start] == '\t')) : (val_start += 1) {}

    if (val_start >= json_slice.len) return null;

    if (json_slice[val_start] == '"') {
        val_start += 1;
        var val_end = val_start;
        while (val_end < json_slice.len) : (val_end += 1) {
            if (json_slice[val_end] == '"' and json_slice[val_end - 1] != '\\') {
                return json_slice[val_start..val_end];
            }
        }
        return json_slice[val_start..val_end];
    } else {
        var val_end = val_start;
        while (val_end < json_slice.len and json_slice[val_end] != ',' and json_slice[val_end] != '\n' and json_slice[val_end] != '}') : (val_end += 1) {}
        return std.mem.trim(u8, json_slice[val_start..val_end], " \r\t\n");
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "SharabhaTable creation, export, and import round-trip" {
    var table = SharabhaTable.init(
        std.testing.allocator,
        "Elden Ring Divine Inquest",
        "eldenring.exe",
    );
    defer table.deinit();

    table.annotations = "Target: Elden Ring v1.12. All pointers relative to eldenring.exe.";

    // Add static address record
    try table.addRecord(.{
        .id = 1,
        .description = "Player Health / Amrita",
        .sanskrit_label = "प्राण शक्ति (HP)",
        .address_type = .StaticAddress,
        .static_address = 0x7FF74A8014E0,
        .value_type = .Int32,
        .freeze_value = "9999",
        .is_frozen = true,
        .hotkey = "NUMPAD1",
    });

    // Add pointer chain record
    try table.addRecord(.{
        .id = 2,
        .description = "Hero Runes (नायक धन)",
        .sanskrit_label = "सुवर्ण मुद्रा",
        .address_type = .PointerChain,
        .module_name = "eldenring.exe",
        .base_offset = 0x03C5A810,
        .level_offsets = .{ 0x10, 0x68, 0x18, 0, 0, 0 },
        .level_count = 3,
        .value_type = .Int32,
        .freeze_value = "99999999",
        .is_frozen = false,
        .hotkey = "NUMPAD2",
    });

    // Add embedded Lua script
    try table.addScript(.{
        .name = "Infinite Health Godmode",
        .sanskrit_name = "अमृत्व विधान",
        .script_body = "sharabha.write_u32(0x7FF74A8014E0, 9999)\nsharabha.log('Godmode armed')",
        .auto_run = true,
    });

    var export_buf: std.ArrayList(u8) = .empty;
    defer export_buf.deinit(std.testing.allocator);
    try table.exportJson(&export_buf, std.testing.allocator);

    const json_str = export_buf.items;
    try std.testing.expect(std.mem.indexOf(u8, json_str, "SHARABHA_TABLE_V1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "Elden Ring Divine Inquest") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "0x7FF74A8014E0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_str, "eldenring.exe") != null);

    // Import back from JSON
    var imported = try SharabhaTable.importJson(std.testing.allocator, json_str);
    defer imported.deinit();

    try std.testing.expectEqualStrings("Elden Ring Divine Inquest", imported.title);
    try std.testing.expectEqualStrings("eldenring.exe", imported.process_name);
    try std.testing.expectEqual(@as(usize, 2), imported.records.items.len);
    try std.testing.expectEqual(@as(usize, 1), imported.scripts.items.len);

    const r1 = imported.records.items[0];
    try std.testing.expectEqual(@as(usize, 0x7FF74A8014E0), r1.static_address);
    try std.testing.expect(r1.is_frozen);
    try std.testing.expectEqualStrings("NUMPAD1", r1.hotkey);

    const r2 = imported.records.items[1];
    try std.testing.expectEqual(AddressType.PointerChain, r2.address_type);
    try std.testing.expectEqual(@as(usize, 3), r2.level_count);
    try std.testing.expectEqual(@as(usize, 0x10), r2.level_offsets[0]);
    try std.testing.expectEqual(@as(usize, 0x68), r2.level_offsets[1]);
    try std.testing.expectEqual(@as(usize, 0x18), r2.level_offsets[2]);

    const sc1 = imported.scripts.items[0];
    try std.testing.expectEqualStrings("Infinite Health Godmode", sc1.name);
    try std.testing.expect(sc1.auto_run);
}
