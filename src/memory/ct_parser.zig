//! ============================================================================
//! SHARABHA (शरभ) — CHEAT ENGINE (.CT) TABLE INQUEST PARSER
//! High-throughput XML parsing and object model for Cheat Engine (.CT) tables.
//! Handles nested cheat entries, multi-level pointer chains, user symbols,
//! Auto Assembler scripts, and embedded Lua scripts.
//!
//! ॐ नमः शरभाय — The divine bridge between Cheat Engine and Sharabha.
//! ============================================================================

const std = @import("std");
const table_mod = @import("table.zig");

pub const CtSymbol = struct {
    name: []const u8,
    address: usize,
    address_str: []const u8,
};

pub const CtEntry = struct {
    id: u32,
    description: []const u8,
    variable_type: []const u8,
    address: []const u8,
    offsets: []const usize,
    assembler_script: ?[]const u8 = null,
    has_lua: bool = false,
    show_as_signed: bool = false,
    color: ?u32 = null,
    is_active: bool = false,
    resolved_address: usize = 0,
    cached_value: []const u8 = "",
    children: []const CtEntry = &.{},

    pub fn isScript(self: *const CtEntry) bool {
        return std.mem.indexOf(u8, self.variable_type, "Script") != null or
            std.mem.indexOf(u8, self.variable_type, "Auto Assembler") != null or
            self.assembler_script != null;
    }

    pub fn extractScriptSections(self: *const CtEntry) struct { enable: ?[]const u8, disable: ?[]const u8 } {
        const script = self.assembler_script orelse return .{ .enable = null, .disable = null };
        var enable_code: ?[]const u8 = null;
        var disable_code: ?[]const u8 = null;

        const en_idx = std.mem.indexOf(u8, script, "[ENABLE]");
        const dis_idx = std.mem.indexOf(u8, script, "[DISABLE]");

        if (en_idx) |ei| {
            const start = ei + "[ENABLE]".len;
            if (dis_idx) |di| {
                if (di > start) {
                    enable_code = std.mem.trim(u8, script[start..di], " \r\n\t");
                }
            } else {
                enable_code = std.mem.trim(u8, script[start..], " \r\n\t");
            }
        }

        if (dis_idx) |di| {
            const start = di + "[DISABLE]".len;
            disable_code = std.mem.trim(u8, script[start..], " \r\n\t");
        }

        if (enable_code == null and disable_code == null) {
            enable_code = std.mem.trim(u8, script, " \r\n\t");
        }

        return .{ .enable = enable_code, .disable = disable_code };
    }
};

pub const CtTable = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    version: u32 = 0,
    symbols: std.ArrayList(CtSymbol),
    entries: std.ArrayList(CtEntry),
    lua_script: ?[]const u8 = null,

    pub fn init(child_allocator: std.mem.Allocator) !*CtTable {
        const arena = try child_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(child_allocator);
        const alloc = arena.allocator();

        const tbl = try alloc.create(CtTable);
        tbl.* = .{
            .arena = arena,
            .allocator = alloc,
            .version = 0,
            .symbols = .empty,
            .entries = .empty,
            .lua_script = null,
        };
        return tbl;
    }

    pub fn deinit(self: *CtTable) void {
        const arena = self.arena;
        const child = arena.child_allocator;
        arena.deinit();
        child.destroy(arena);
    }

    pub fn findEntryById(self: *const CtTable, id: u32) ?CtEntry {
        return findEntryRecursive(self.entries.items, id);
    }

    fn findEntryRecursive(list: []const CtEntry, id: u32) ?CtEntry {
        for (list) |entry| {
            if (entry.id == id) return entry;
            if (entry.children.len > 0) {
                if (findEntryRecursive(entry.children, id)) |found| {
                    return found;
                }
            }
        }
        return null;
    }

    pub fn flattenEntries(self: *const CtTable, out_allocator: std.mem.Allocator) ![]CtEntry {
        var list: std.ArrayList(CtEntry) = .empty;
        for (self.entries.items) |entry| {
            try appendFlattened(&list, entry, out_allocator);
        }
        return list.toOwnedSlice(out_allocator);
    }

    fn appendFlattened(list: *std.ArrayList(CtEntry), entry: CtEntry, alloc: std.mem.Allocator) !void {
        try list.append(alloc, entry);
        for (entry.children) |child| {
            try appendFlattened(list, child, alloc);
        }
    }

    /// Converts parsed Cheat Engine entries into a native SharabhaTable
    pub fn toSharabhaTable(
        self: *const CtTable,
        child_allocator: std.mem.Allocator,
        title: []const u8,
        process_name: []const u8,
    ) !table_mod.SharabhaTable {
        var table = table_mod.SharabhaTable.init(child_allocator, title, process_name);

        // Add top-level Lua script if present
        if (self.lua_script) |ls| {
            try table.addScript(.{
                .name = "Cheat Table Master Script",
                .sanskrit_name = "प्रधान चेतना सूत्र",
                .script_body = ls,
                .auto_run = true,
            });
        }

        const flat = try self.flattenEntries(self.allocator);
        for (flat) |entry| {
            if (entry.isScript()) {
                const sec = entry.extractScriptSections();
                const script_body = sec.enable orelse entry.assembler_script orelse "";
                try table.addScript(.{
                    .name = entry.description,
                    .sanskrit_name = "उद्बोधन सूत्र",
                    .script_body = script_body,
                    .auto_run = false,
                });
            } else {
                var rec = table_mod.TableRecord{
                    .id = entry.id,
                    .description = entry.description,
                    .sanskrit_label = "स्मृति पद",
                    .address_type = if (entry.offsets.len > 0) .PointerChain else .StaticAddress,
                    .static_address = 0,
                    .module_name = "",
                    .base_offset = 0,
                    .level_offsets = @splat(0),
                    .level_count = @min(entry.offsets.len, 6),
                    .aob_pattern = "",
                    .value_type = mapCtTypeToSharabha(entry.variable_type),
                    .freeze_value = "",
                    .is_frozen = entry.is_active,
                    .hotkey = "",
                };

                // Parse address expr
                if (rec.address_type == .StaticAddress) {
                    rec.static_address = parseHexOrDec(entry.address);
                } else {
                    // Split base module if present (e.g. "game.exe+0x10")
                    if (std.mem.indexOf(u8, entry.address, "+")) |plus_idx| {
                        const mod = std.mem.trim(u8, entry.address[0..plus_idx], " \"'");
                        rec.module_name = table.allocator.dupe(u8, mod) catch mod;
                        const off_str = entry.address[plus_idx + 1 ..];
                        rec.base_offset = parseHexOrDec(off_str);
                    } else {
                        rec.static_address = parseHexOrDec(entry.address);
                    }

                    var i: usize = 0;
                    while (i < rec.level_count) : (i += 1) {
                        rec.level_offsets[i] = entry.offsets[i];
                    }
                }

                try table.addRecord(rec);
            }
        }

        return table;
    }
};

fn mapCtTypeToSharabha(ct_type: []const u8) table_mod.TableValueType {
    if (std.mem.indexOf(u8, ct_type, "8 Byte") != null or std.mem.indexOf(u8, ct_type, "8 Bytes") != null) return .Int64;
    if (std.mem.indexOf(u8, ct_type, "Float") != null) return .Float32;
    if (std.mem.indexOf(u8, ct_type, "Double") != null) return .Float64;
    if (std.mem.indexOf(u8, ct_type, "Byte") != null) return .Byte;
    if (std.mem.indexOf(u8, ct_type, "String") != null) return .TextString;
    return .Int32;
}

pub fn parseOffsetHex(str: []const u8) usize {
    const trimmed = std.mem.trim(u8, str, " \"'\r\n\t");
    if (trimmed.len == 0) return 0;
    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return std.fmt.parseInt(usize, trimmed[2..], 16) catch 0;
    }
    return std.fmt.parseInt(usize, trimmed, 16) catch (std.fmt.parseInt(usize, trimmed, 10) catch 0);
}

pub fn parseHexOrDec(str: []const u8) usize {
    const trimmed = std.mem.trim(u8, str, " \"'\r\n\t");
    if (trimmed.len == 0) return 0;
    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return std.fmt.parseInt(usize, trimmed[2..], 16) catch 0;
    }
    // Check if it contains hex characters [a-fA-F]
    var has_hex = false;
    for (trimmed) |c| {
        if ((c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) {
            has_hex = true;
            break;
        }
    }
    if (has_hex) {
        return std.fmt.parseInt(usize, trimmed, 16) catch 0;
    }
    return std.fmt.parseInt(usize, trimmed, 10) catch (std.fmt.parseInt(usize, trimmed, 16) catch 0);
}

pub fn unescapeXml(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, input, "&") == null) {
        return input;
    }

    var result: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (std.mem.startsWith(u8, input[i..], "&quot;")) {
                try result.append(allocator, '"');
                i += 6;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&apos;")) {
                try result.append(allocator, '\'');
                i += 6;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&lt;")) {
                try result.append(allocator, '<');
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&gt;")) {
                try result.append(allocator, '>');
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&amp;")) {
                try result.append(allocator, '&');
                i += 5;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&#10;") or std.mem.startsWith(u8, input[i..], "&#x0A;") or std.mem.startsWith(u8, input[i..], "&#x0a;")) {
                try result.append(allocator, '\n');
                i += if (input[i + 2] == 'x' or input[i + 2] == 'X') 6 else 5;
                continue;
            } else if (std.mem.startsWith(u8, input[i..], "&#13;") or std.mem.startsWith(u8, input[i..], "&#x0D;") or std.mem.startsWith(u8, input[i..], "&#x0d;")) {
                try result.append(allocator, '\r');
                i += if (input[i + 2] == 'x' or input[i + 2] == 'X') 6 else 5;
                continue;
            }
        }
        try result.append(allocator, input[i]);
        i += 1;
    }
    return result.toOwnedSlice(allocator);
}

pub const CtParser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) CtParser {
        return .{
            .allocator = allocator,
            .source = source,
            .pos = 0,
        };
    }

    pub fn parse(self: *CtParser) !*CtTable {
        var table = try CtTable.init(self.allocator);
        errdefer table.deinit();

        // 1. Detect CheatEngineTableVersion
        if (std.mem.indexOf(u8, self.source, "CheatEngineTableVersion")) |v_idx| {
            const quote_start = std.mem.indexOfPos(u8, self.source, v_idx, "\"");
            if (quote_start) |qs| {
                const quote_end = std.mem.indexOfPos(u8, self.source, qs + 1, "\"");
                if (quote_end) |qe| {
                    table.version = std.fmt.parseInt(u32, self.source[qs + 1 .. qe], 10) catch 0;
                }
            }
        }

        // 2. Extract Top-level <LuaScript> if present
        if (self.extractTagContent(0, "LuaScript")) |ls| {
            table.lua_script = try unescapeXml(table.allocator, std.mem.trim(u8, ls, " \r\n\t"));
        }

        // 3. Extract UserdefinedSymbols
        if (self.extractTagSlice(0, "UserdefinedSymbols")) |symbols_slice| {
            var s_parser = CtParser.init(table.allocator, symbols_slice);
            while (s_parser.findNextTag("SymbolEntry")) |se_slice| {
                var sym_parser = CtParser.init(table.allocator, se_slice);
                const name = sym_parser.extractTagContent(0, "Name") orelse "";
                const addr_str = sym_parser.extractTagContent(0, "Address") orelse "";
                if (name.len > 0 and addr_str.len > 0) {
                    const addr = parseHexOrDec(addr_str);
                    try table.symbols.append(table.allocator, .{
                        .name = try table.allocator.dupe(u8, name),
                        .address = addr,
                        .address_str = try table.allocator.dupe(u8, addr_str),
                    });
                }
            }
        }

        // 4. Extract CheatEntries
        if (self.extractTagSlice(0, "CheatEntries")) |entries_slice| {
            var e_parser = CtParser.init(table.allocator, entries_slice);
            table.entries = try e_parser.parseEntriesList(table.allocator);
        }

        return table;
    }

    fn parseEntriesList(self: *CtParser, alloc: std.mem.Allocator) anyerror!std.ArrayList(CtEntry) {
        var list: std.ArrayList(CtEntry) = .empty;

        while (true) {
            const entry_start = self.findTagStart(self.pos, "CheatEntry") orelse break;
            const entry_end = self.findMatchingTagEnd(entry_start, "CheatEntry") orelse break;

            const entry_slice = self.source[entry_start..entry_end];
            self.pos = entry_end;

            const entry = try self.parseSingleEntry(alloc, entry_slice);
            try list.append(alloc, entry);
        }

        return list;
    }

    fn parseSingleEntry(self: *CtParser, alloc: std.mem.Allocator, slice: []const u8) !CtEntry {
        _ = self;
        var p = CtParser.init(alloc, slice);

        // ID
        const id_str = p.extractTagContent(0, "ID") orelse "0";
        const id = std.fmt.parseInt(u32, id_str, 10) catch 0;

        // Description
        var desc: []const u8 = "Cheat Entry";
        if (p.extractTagContent(0, "Description")) |d| {
            var trimmed = std.mem.trim(u8, d, " \r\n\t");
            if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
                trimmed = trimmed[1 .. trimmed.len - 1];
            }
            desc = try unescapeXml(alloc, trimmed);
        }

        // VariableType
        const var_type = p.extractTagContent(0, "VariableType") orelse "4 Bytes";

        // Address
        const address = p.extractTagContent(0, "Address") orelse "";

        // ShowAsSigned
        const signed_str = p.extractTagContent(0, "ShowAsSigned") orelse "0";
        const show_as_signed = std.mem.eql(u8, signed_str, "1");

        // Color
        var color: ?u32 = null;
        if (p.extractTagContent(0, "Color")) |c_str| {
            color = std.fmt.parseInt(u32, c_str, 16) catch null;
        }

        // Offsets
        var offsets_list: std.ArrayList(usize) = .empty;
        if (p.extractTagSlice(0, "Offsets")) |off_slice| {
            var off_p = CtParser.init(alloc, off_slice);
            var o_pos: usize = 0;
            while (off_p.extractTagContent(o_pos, "Offset")) |o_str| {
                const off_val = parseOffsetHex(o_str);
                try offsets_list.append(alloc, off_val);
                if (std.mem.indexOfPos(u8, off_slice, o_pos, "</Offset>")) |end_o| {
                    o_pos = end_o + "</Offset>".len;
                } else break;
            }
        }

        // AssemblerScript
        var asm_script: ?[]const u8 = null;
        var has_lua = false;
        if (p.extractTagContent(0, "AssemblerScript")) |script_raw| {
            const unesc = try unescapeXml(alloc, script_raw);
            asm_script = unesc;
            has_lua = std.mem.indexOf(u8, unesc, "{$lua}") != null or std.mem.indexOf(u8, unesc, "LuaCall") != null;
        }

        // Children entries
        var children: []const CtEntry = &.{};
        if (p.extractTagSlice(0, "CheatEntries")) |child_slice| {
            var child_p = CtParser.init(alloc, child_slice);
            const child_list = try child_p.parseEntriesList(alloc);
            children = child_list.items;
        }

        return CtEntry{
            .id = id,
            .description = desc,
            .variable_type = var_type,
            .address = address,
            .offsets = offsets_list.items,
            .assembler_script = asm_script,
            .has_lua = has_lua,
            .show_as_signed = show_as_signed,
            .color = color,
            .children = children,
        };
    }

    fn findTagStart(self: *const CtParser, from: usize, tag: []const u8) ?usize {
        var cur = from;
        while (cur < self.source.len) {
            const next_lt = std.mem.indexOfPos(u8, self.source, cur, "<") orelse return null;
            if (next_lt + 1 + tag.len <= self.source.len) {
                const sub = self.source[next_lt + 1 .. next_lt + 1 + tag.len];
                if (std.mem.eql(u8, sub, tag)) {
                    // Check if followed by '>', ' ', or '/'
                    const after = next_lt + 1 + tag.len;
                    if (after < self.source.len) {
                        const ch = self.source[after];
                        if (ch == '>' or ch == ' ' or ch == '/' or ch == '\t' or ch == '\r' or ch == '\n') {
                            return next_lt;
                        }
                    }
                }
            }
            cur = next_lt + 1;
        }
        return null;
    }

    fn findMatchingTagEnd(self: *const CtParser, start_idx: usize, tag: []const u8) ?usize {
        // Tag end may be self closing e.g. <CheatEntry ... />
        const close_gt = std.mem.indexOfPos(u8, self.source, start_idx, ">") orelse return null;
        if (close_gt > start_idx and self.source[close_gt - 1] == '/') {
            return close_gt + 1;
        }

        var depth: usize = 1;
        var cur = close_gt + 1;

        while (cur < self.source.len and depth > 0) {
            const next_lt = std.mem.indexOfPos(u8, self.source, cur, "<") orelse return null;
            if (next_lt + 1 >= self.source.len) return null;

            if (self.source[next_lt + 1] == '/') {
                // Closing tag
                const closing_sub = self.source[next_lt + 2 ..];
                if (std.mem.startsWith(u8, closing_sub, tag)) {
                    const tag_close = next_lt + 2 + tag.len;
                    if (tag_close < self.source.len and self.source[tag_close] == '>') {
                        depth -= 1;
                        if (depth == 0) {
                            return tag_close + 1;
                        }
                        cur = tag_close + 1;
                        continue;
                    }
                }
            } else {
                // Potential nested opening tag
                const opening_sub = self.source[next_lt + 1 ..];
                if (std.mem.startsWith(u8, opening_sub, tag)) {
                    const after = next_lt + 1 + tag.len;
                    if (after < self.source.len) {
                        const ch = self.source[after];
                        if (ch == '>' or ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n') {
                            const nested_close_gt = std.mem.indexOfPos(u8, self.source, after, ">");
                            if (nested_close_gt) |ncg| {
                                if (self.source[ncg - 1] != '/') {
                                    depth += 1;
                                }
                                cur = ncg + 1;
                                continue;
                            }
                        }
                    }
                }
            }
            cur = next_lt + 1;
        }

        return null;
    }

    fn extractTagContent(self: *const CtParser, from: usize, tag: []const u8) ?[]const u8 {
        const start = self.findTagStart(from, tag) orelse return null;
        const gt = std.mem.indexOfPos(u8, self.source, start, ">") orelse return null;
        if (self.source[gt - 1] == '/') return ""; // self-closing tag

        var close_tag_buf: [64]u8 = undefined;
        const close_tag = std.fmt.bufPrint(&close_tag_buf, "</{s}>", .{tag}) catch return null;
        const close_idx = std.mem.indexOfPos(u8, self.source, gt + 1, close_tag) orelse return null;
        return self.source[gt + 1 .. close_idx];
    }

    fn extractTagSlice(self: *const CtParser, from: usize, tag: []const u8) ?[]const u8 {
        const start = self.findTagStart(from, tag) orelse return null;
        const end = self.findMatchingTagEnd(start, tag) orelse return null;
        return self.source[start..end];
    }

    fn findNextTag(self: *CtParser, tag: []const u8) ?[]const u8 {
        const start = self.findTagStart(self.pos, tag) orelse return null;
        const end = self.findMatchingTagEnd(start, tag) orelse return null;
        self.pos = end;
        return self.source[start..end];
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "CtParser parses basic cheat entries and auto assembler script" {
    const xml =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<CheatTable CheatEngineTableVersion="45">
        \\  <UserdefinedSymbols>
        \\    <SymbolEntry>
        \\      <Name>playerBase</Name>
        \\      <Address>14023A10</Address>
        \\    </SymbolEntry>
        \\  </UserdefinedSymbols>
        \\  <CheatEntries>
        \\    <CheatEntry>
        \\      <ID>1001</ID>
        \\      <Description>"Hero Health (प्राण शक्ति)"</Description>
        \\      <VariableType>4 Bytes</VariableType>
        \\      <Address>playerBase</Address>
        \\      <Offsets>
        \\        <Offset>18</Offset>
        \\        <Offset>40</Offset>
        \\      </Offsets>
        \\    </CheatEntry>
        \\    <CheatEntry>
        \\      <ID>1002</ID>
        \\      <Description>"God Mode [Lua]"</Description>
        \\      <VariableType>Auto Assembler Script</VariableType>
        \\      <AssemblerScript>[ENABLE]
        \\{$lua}
        \\if syntaxcheck then return end
        \\writeInteger("playerBase", 99999)
        \\print("God mode activated")
        \\{$asm}
        \\[DISABLE]
        \\</AssemblerScript>
        \\    </CheatEntry>
        \\  </CheatEntries>
        \\</CheatTable>
    ;

    var parser = CtParser.init(std.testing.allocator, xml);
    var table = try parser.parse();
    defer table.deinit();

    try std.testing.expectEqual(@as(u32, 45), table.version);
    try std.testing.expectEqual(@as(usize, 1), table.symbols.items.len);
    try std.testing.expectEqualStrings("playerBase", table.symbols.items[0].name);
    try std.testing.expectEqual(@as(usize, 0x14023A10), table.symbols.items[0].address);

    try std.testing.expectEqual(@as(usize, 2), table.entries.items.len);

    const e1 = table.entries.items[0];
    try std.testing.expectEqual(@as(u32, 1001), e1.id);
    try std.testing.expectEqualStrings("Hero Health (प्राण शक्ति)", e1.description);
    try std.testing.expectEqualStrings("4 Bytes", e1.variable_type);
    try std.testing.expectEqualStrings("playerBase", e1.address);
    try std.testing.expectEqual(@as(usize, 2), e1.offsets.len);
    try std.testing.expectEqual(@as(usize, 0x18), e1.offsets[0]);
    try std.testing.expectEqual(@as(usize, 0x40), e1.offsets[1]);

    const e2 = table.entries.items[1];
    try std.testing.expectEqual(@as(u32, 1002), e2.id);
    try std.testing.expect(e2.isScript());
    try std.testing.expect(e2.has_lua);

    const sec = e2.extractScriptSections();
    try std.testing.expect(sec.enable != null);
    try std.testing.expect(std.mem.indexOf(u8, sec.enable.?, "God mode activated") != null);

    // Test conversion to SharabhaTable
    var sh_table = try table.toSharabhaTable(std.testing.allocator, "Test Table", "game.exe");
    defer sh_table.deinit();

    try std.testing.expectEqual(@as(usize, 1), sh_table.records.items.len);
    try std.testing.expectEqual(@as(usize, 1), sh_table.scripts.items.len);
}

/// Normalises a raw `.CT` payload into UTF-8 text.
///
/// Cheat Engine writes tables as XML and still emits them as UTF-8 + BOM, and
/// older / "Unicode" tables are UTF-16LE or UTF-16BE with a BOM. The tag scanner
/// below matches ASCII tag names, so a UTF-16 table would otherwise parse as
/// zero entries ("table loaded" but nothing to show). Returns an owned buffer;
/// on the UTF-16 path the input buffer is freed.
pub fn normalizeCtBytes(allocator: std.mem.Allocator, raw: []u8) ![]u8 {
    // UTF-8 BOM: strip in place.
    if (raw.len >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF) {
        std.mem.copyForwards(u8, raw[0 .. raw.len - 3], raw[3..]);
        return try allocator.realloc(raw, raw.len - 3);
    }

    const has_le_bom = raw.len >= 2 and raw[0] == 0xFF and raw[1] == 0xFE;
    const has_be_bom = raw.len >= 2 and raw[0] == 0xFE and raw[1] == 0xFF;
    if (!has_le_bom and !has_be_bom) return raw;

    const little = has_le_bom;
    const unit_count = (raw.len - 2) / 2;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < unit_count) : (i += 1) {
        const b0: u16 = raw[2 + i * 2];
        const b1: u16 = raw[2 + i * 2 + 1];
        var cp: u21 = @intCast(if (little) (b0 | (b1 << 8)) else ((b0 << 8) | b1));

        // Combine UTF-16 surrogate pairs; lone surrogates become U+FFFD.
        if (cp >= 0xD800 and cp <= 0xDBFF and i + 1 < unit_count) {
            const lb0: u16 = raw[2 + (i + 1) * 2];
            const lb1: u16 = raw[2 + (i + 1) * 2 + 1];
            const low: u21 = @intCast(if (little) (lb0 | (lb1 << 8)) else ((lb0 << 8) | lb1));
            if (low >= 0xDC00 and low <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                i += 1;
            } else {
                cp = 0xFFFD;
            }
        } else if (cp >= 0xDC00 and cp <= 0xDFFF) {
            cp = 0xFFFD;
        }

        if (cp == 0) continue; // NUL padding between units - drop it
        if (cp < 0x80) {
            try out.append(allocator, @intCast(cp));
        } else if (cp < 0x800) {
            try out.append(allocator, @intCast(0xC0 | (cp >> 6)));
            try out.append(allocator, @intCast(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            try out.append(allocator, @intCast(0xE0 | (cp >> 12)));
            try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3F)));
            try out.append(allocator, @intCast(0x80 | (cp & 0x3F)));
        } else {
            try out.append(allocator, @intCast(0xF0 | (cp >> 18)));
            try out.append(allocator, @intCast(0x80 | ((cp >> 12) & 0x3F)));
            try out.append(allocator, @intCast(0x80 | ((cp >> 6) & 0x3F)));
            try out.append(allocator, @intCast(0x80 | (cp & 0x3F)));
        }
    }

    const normalized = try out.toOwnedSlice(allocator);
    allocator.free(raw);
    return normalized;
}

pub fn readCtFile(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, file_path);
    defer allocator.free(path_w);

    const win = @import("process.zig").win;
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
            hTemplateFile: ?win.HANDLE,
        ) callconv(.winapi) win.HANDLE;
        pub extern "kernel32" fn ReadFile(
            hFile: win.HANDLE,
            lpBuffer: [*]u8,
            nNumberOfBytesToRead: u32,
            lpNumberOfBytesRead: ?*u32,
            lpOverlapped: ?*anyopaque,
        ) callconv(.winapi) i32;
        pub extern "kernel32" fn GetFileSize(hFile: win.HANDLE, lpFileSizeHigh: ?*u32) callconv(.winapi) u32;
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

    if (handle == win.INVALID_HANDLE_VALUE) {
        return error.FileNotFound;
    }
    defer _ = win.CloseHandle(handle);

    var high_size: u32 = 0;
    const file_size = CreateFileW_fn.GetFileSize(handle, &high_size);
    if (file_size == 0 or file_size == 0xFFFFFFFF) {
        return error.InvalidFileSize;
    }

    const buf = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buf);

    var bytes_read: u32 = 0;
    const read_ok = CreateFileW_fn.ReadFile(handle, buf.ptr, file_size, &bytes_read, null);
    if (read_ok == 0 or bytes_read != file_size) {
        return error.FileReadFailed;
    }

    // UTF-8 + BOM and UTF-16LE/BE tables are common in the wild; normalise once
    // here so every consumer (CLI inquest, Slint bridge, entry runner) sees UTF-8.
    return try normalizeCtBytes(allocator, buf);
}

test "CtParser parses real-world BG3.CT if available" {
    const file_path = "D:\\Mods\\BG3\\bg3.CT";
    const bytes = readCtFile(std.testing.allocator, file_path) catch return;
    defer std.testing.allocator.free(bytes);

    var parser = CtParser.init(std.testing.allocator, bytes);
    var table = try parser.parse();
    defer table.deinit();

    try std.testing.expect(table.entries.items.len > 0);
    const flat = try table.flattenEntries(std.testing.allocator);
    defer std.testing.allocator.free(flat);

    try std.testing.expect(flat.len > 10);
    // Verify symbols
    try std.testing.expect(table.symbols.items.len > 0);
}

test "CtParser: UTF-8 BOM and UTF-16LE tables normalise into parseable UTF-8" {
    const allocator = std.testing.allocator;

    const xml =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<CheatTable CheatEngineTableVersion="46">
        \\  <CheatEntries>
        \\    <CheatEntry>
        \\      <ID>1</ID>
        \\      <Description>"Player Gold"</Description>
        \\      <VariableType>4 Bytes</VariableType>
        \\      <Address>game.exe+1234</Address>
        \\    </CheatEntry>
        \\  </CheatEntries>
        \\</CheatTable>
    ;

    // 1. UTF-8 + BOM (what Cheat Engine writes by default) is stripped.
    const utf8_bom = try allocator.alloc(u8, xml.len + 3);
    utf8_bom[0] = 0xEF;
    utf8_bom[1] = 0xBB;
    utf8_bom[2] = 0xBF;
    @memcpy(utf8_bom[3..], xml);
    const stripped = try normalizeCtBytes(allocator, utf8_bom);
    defer allocator.free(stripped);
    try std.testing.expectEqualStrings(xml, stripped);

    // 2. UTF-16LE + BOM ("Unicode" table) is transcoded, not silently ignored.
    const wide = try allocator.alloc(u8, 2 + xml.len * 2);
    wide[0] = 0xFF;
    wide[1] = 0xFE;
    for (xml, 0..) |c, i| {
        wide[2 + i * 2] = c;
        wide[2 + i * 2 + 1] = 0;
    }
    const narrow = try normalizeCtBytes(allocator, wide);
    defer allocator.free(narrow);
    try std.testing.expectEqualStrings(xml, narrow);

    var parser = CtParser.init(allocator, narrow);
    var table = try parser.parse();
    defer table.deinit();

    try std.testing.expectEqual(@as(u32, 46), table.version);
    try std.testing.expectEqual(@as(usize, 1), table.entries.items.len);
    try std.testing.expect(std.mem.indexOf(u8, table.entries.items[0].description, "Player Gold") != null);
    try std.testing.expectEqualStrings("game.exe+1234", table.entries.items[0].address);

    // 3. UTF-16BE is handled too.
    const wide_be = try allocator.alloc(u8, 2 + xml.len * 2);
    wide_be[0] = 0xFE;
    wide_be[1] = 0xFF;
    for (xml, 0..) |c, i| {
        wide_be[2 + i * 2] = 0;
        wide_be[2 + i * 2 + 1] = c;
    }
    const narrow_be = try normalizeCtBytes(allocator, wide_be);
    defer allocator.free(narrow_be);
    try std.testing.expectEqualStrings(xml, narrow_be);
}
