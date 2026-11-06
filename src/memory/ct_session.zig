//! ============================================================================
//! SHARABHA (शरभ) — CHETANA TALIKA SESSION (चेतना तालिका सत्र)
//! Persistent state for the Cheat Engine address list.
//!
//! Why a session exists: slint-viewer regenerates the whole UI from
//! `src/ui/live_table.slint` whenever a table mutates, so every row, its
//! enable/disable state and the active search filter must survive a process
//! restart *and* a merge of several `.CT` files. This module owns that state and
//! serialises it as tab-separated text (human-inspectable, tolerant of unknown
//! columns, and cheaper than a JSON DOM for 12k+ rows).
//!
//! ॐ नमः शरभाय — The ledger that survives the reload.
//! ============================================================================

const std = @import("std");
const ct_parser = @import("ct_parser.zig");

pub const SESSION_MAGIC = "#sharabha-ct-session-v1";

/// One address-list line. Mirrors `CheatTableRowData` in `src/ui/live_table.slint`.
pub const Row = struct {
    seq: u32 = 0,
    ce_id: u32 = 0,
    /// `.CT` this row came from — the script runner needs it after a merge.
    source: []const u8 = "",
    description: []const u8 = "",
    /// Raw Cheat Engine address expression (`bg3.exe+24A266F`, `statsPtr+8`, ...).
    addr_expr: []const u8 = "",
    /// Display form (adds the pointer-chain tail when offsets exist).
    address: []const u8 = "",
    val_type: []const u8 = "4 Bytes",
    value: []const u8 = "???",
    hotkey: []const u8 = "",
    offsets: []const usize = &.{},
    depth: u16 = 0,
    is_group: bool = false,
    is_script: bool = false,
    script_active: bool = false,
    is_frozen: bool = false,

    pub fn hasPointerChain(self: *const Row) bool {
        return self.offsets.len > 0;
    }
};

/// A `.CT` file contributing rows to the session.
pub const TableRef = struct {
    path: []const u8 = "",
    title: []const u8 = "",
    entry_count: u32 = 0,
};

/// Result of folding one `.CT` into the session.
pub const MergeStats = struct {
    added: usize = 0,
    replaced_rows: usize = 0,
    imported_tables: usize = 0,
};

pub const Session = struct {
    /// Heap-owned so `Session` can be returned and copied by value without
    /// leaving `allocator` pointing at a dead stack slot.
    arena: *std.heap.ArenaAllocator,
    child: std.mem.Allocator,
    allocator: std.mem.Allocator,
    rows: std.ArrayList(Row),
    tables: std.ArrayList(TableRef),
    filter: []const u8 = "",

    pub fn init(child_allocator: std.mem.Allocator) !Session {
        const arena = try child_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(child_allocator);
        return .{
            .arena = arena,
            .child = child_allocator,
            .allocator = arena.allocator(),
            .rows = .empty,
            .tables = .empty,
            .filter = "",
        };
    }

    pub fn deinit(self: *Session) void {
        const arena = self.arena;
        const child = self.child;
        arena.deinit();
        child.destroy(arena);
        self.* = undefined;
    }

    fn dup(self: *Session, str: []const u8) []const u8 {
        return self.allocator.dupe(u8, str) catch str;
    }

    pub fn clearRows(self: *Session) void {
        self.rows.clearRetainingCapacity();
        self.tables.clearRetainingCapacity();
    }

    pub fn resize(self: *Session) void {
        for (self.rows.items, 0..) |*row, i| {
            row.seq = @intCast(i + 1);
        }
    }

    /// Drops every row that came from `path` — used before re-importing a table
    /// in merge mode so loading the same `.CT` twice stays idempotent.
    fn dropTable(self: *Session, path: []const u8) usize {
        var kept: usize = 0;
        var removed: usize = 0;
        for (self.rows.items) |row| {
            if (std.mem.eql(u8, row.source, path)) {
                removed += 1;
            } else {
                self.rows.items[kept] = row;
                kept += 1;
            }
        }
        self.rows.shrinkRetainingCapacity(kept);

        var kept_tables: usize = 0;
        for (self.tables.items) |tbl| {
            if (std.mem.eql(u8, tbl.path, path)) continue;
            self.tables.items[kept_tables] = tbl;
            kept_tables += 1;
        }
        self.tables.shrinkRetainingCapacity(kept_tables);
        return removed;
    }

    /// Formats the Cheat Engine address column: static bases stay verbatim,
    /// pointer records get their first hop appended like CE's tree view.
    fn displayAddress(self: *Session, entry: *const ct_parser.CtEntry) []const u8 {
        if (entry.offsets.len == 0) return self.dup(entry.address);
        var buf: [192]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s} -> +0x{X}", .{ entry.address, entry.offsets[0] }) catch entry.address;
        return self.dup(text);
    }

    /// Folds a parsed `.CT` into the session. `replace` wipes the current list
    /// (Cheat Engine's "Open"), otherwise rows are appended after the existing
    /// ones ("Merge") so the loaded process and every current row stay intact.
    pub fn importTable(
        self: *Session,
        path: []const u8,
        title: []const u8,
        flat: []const ct_parser.CtTable.FlatEntry,
        replace: bool,
    ) !MergeStats {
        var stats: MergeStats = .{};

        if (replace) {
            stats.replaced_rows = self.rows.items.len;
            self.clearRows();
        } else {
            // Same table loaded again via MERGE: refresh its rows instead of
            // duplicating 12k entries in the list.
            stats.replaced_rows = self.dropTable(path);
        }

        for (flat) |item| {
            const entry = item.entry;
            const is_group = entry.is_group or
                std.mem.indexOf(u8, entry.variable_type, "Group Header") != null;
            const is_script = !is_group and entry.isScript();

            var value: []const u8 = "???";
            if (is_group) {
                value = "";
            } else if (is_script) {
                value = if (entry.has_lua) "[Lua]" else "[Auto Assembler]";
            }

            try self.rows.append(self.allocator, .{
                .ce_id = entry.id,
                .source = self.dup(path),
                .description = self.dup(entry.description),
                .addr_expr = self.dup(entry.address),
                .address = if (is_group) "" else self.displayAddress(&entry),
                .val_type = if (is_group) "Group Header" else self.dup(entry.variable_type),
                .value = self.dup(value),
                .hotkey = self.dup(entry.hotkey),
                .offsets = entry.offsets,
                .depth = item.depth,
                .is_group = is_group,
                .is_script = is_script,
            });
            stats.added += 1;
        }

        try self.tables.append(self.allocator, .{
            .path = self.dup(path),
            .title = self.dup(title),
            .entry_count = @intCast(flat.len),
        });
        stats.imported_tables = self.tables.items.len;

        self.resize();
        return stats;
    }

    /// Flips a script row's stored enable state. Returns true when the row was
    /// found, so callers can report a meaningful status to the UI.
    pub fn setScriptActive(self: *Session, source: []const u8, ce_id: u32, active: bool) bool {
        for (self.rows.items) |*row| {
            if (row.ce_id != ce_id or !row.is_script) continue;
            if (source.len > 0 and row.source.len > 0 and !std.mem.eql(u8, row.source, source)) continue;
            row.script_active = active;
            return true;
        }
        return false;
    }

    pub fn findScriptRow(self: *Session, source: []const u8, ce_id: u32) ?*Row {
        for (self.rows.items) |*row| {
            if (row.ce_id != ce_id or !row.is_script) continue;
            if (source.len > 0 and row.source.len > 0 and !std.mem.eql(u8, row.source, source)) continue;
            return row;
        }
        return null;
    }

    /// Case-insensitive substring match across the columns a player searches by.
    pub fn rowMatches(row: *const Row, filter: []const u8) bool {
        if (filter.len == 0) return true;
        if (containsIgnoreCase(row.description, filter)) return true;
        if (containsIgnoreCase(row.address, filter)) return true;
        if (containsIgnoreCase(row.addr_expr, filter)) return true;
        if (containsIgnoreCase(row.val_type, filter)) return true;
        if (containsIgnoreCase(row.hotkey, filter)) return true;
        return false;
    }

    pub fn visibleRowCount(self: *Session) usize {
        if (self.filter.len == 0) return self.rows.items.len;
        var count: usize = 0;
        for (self.rows.items) |row| {
            if (rowMatches(&row, self.filter)) count += 1;
        }
        return count;
    }

    // ========================================================================
    // SERIALISATION
    // ========================================================================

    /// Serialises the session as tab-separated text. Caller owns the buffer.
    pub fn serialize(self: *Session, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        try out.appendSlice(allocator, SESSION_MAGIC);
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, "FILTER\t");
        try appendEscaped(&out, allocator, self.filter);
        try out.append(allocator, '\n');

        for (self.tables.items) |tbl| {
            try out.appendSlice(allocator, "TABLE\t");
            try appendEscaped(&out, allocator, tbl.path);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, tbl.title);
            try out.append(allocator, '\t');
            try out.print(allocator, "{d}\n", .{tbl.entry_count});
        }

        for (self.rows.items) |row| {
            try out.appendSlice(allocator, "ROW\t");
            try out.print(allocator, "{d}\t{d}\t{d}\t", .{ row.seq, row.ce_id, row.depth });

            var flags_buf: [4]u8 = undefined;
            var flags_len: usize = 0;
            if (row.is_group) {
                flags_buf[flags_len] = 'g';
                flags_len += 1;
            }
            if (row.is_script) {
                flags_buf[flags_len] = 's';
                flags_len += 1;
            }
            if (row.script_active) {
                flags_buf[flags_len] = 'a';
                flags_len += 1;
            }
            if (row.is_frozen) {
                flags_buf[flags_len] = 'f';
                flags_len += 1;
            }
            try out.appendSlice(allocator, flags_buf[0..flags_len]);
            try out.append(allocator, '\t');

            try appendEscaped(&out, allocator, row.hotkey);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.description);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.addr_expr);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.address);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.val_type);
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.value);
            try out.append(allocator, '\t');

            for (row.offsets, 0..) |off, i| {
                if (i > 0) try out.append(allocator, ',');
                try out.print(allocator, "{X}", .{off});
            }
            try out.append(allocator, '\t');
            try appendEscaped(&out, allocator, row.source);
            try out.append(allocator, '\n');
        }

        return out.toOwnedSlice(allocator);
    }

    /// Parses text produced by `serialize`. Unknown lines are ignored and
    /// missing trailing columns fall back to defaults, so a session written by
    /// an older build still loads after an upgrade.
    pub fn deserialize(self: *Session, text: []const u8) !void {
        self.clearRows();
        self.filter = "";

        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            if (line.len == 0 or line[0] == '#') continue;

            var cols = std.mem.splitScalar(u8, line, '\t');
            const kind = cols.next() orelse continue;

            if (std.mem.eql(u8, kind, "FILTER")) {
                self.filter = self.dup(unescape(self.allocator, cols.next() orelse ""));
                continue;
            }

            if (std.mem.eql(u8, kind, "TABLE")) {
                const path = unescape(self.allocator, cols.next() orelse "");
                const title = unescape(self.allocator, cols.next() orelse "");
                const count = std.fmt.parseInt(u32, std.mem.trim(u8, cols.next() orelse "0", " \r\n"), 10) catch 0;
                try self.tables.append(self.allocator, .{
                    .path = self.dup(path),
                    .title = self.dup(title),
                    .entry_count = count,
                });
                continue;
            }

            if (!std.mem.eql(u8, kind, "ROW")) continue;

            var row: Row = .{};
            row.seq = std.fmt.parseInt(u32, cols.next() orelse "0", 10) catch 0;
            row.ce_id = std.fmt.parseInt(u32, cols.next() orelse "0", 10) catch 0;
            row.depth = std.fmt.parseInt(u16, cols.next() orelse "0", 10) catch 0;

            const flags = cols.next() orelse "";
            for (flags) |f| switch (f) {
                'g' => row.is_group = true,
                's' => row.is_script = true,
                'a' => row.script_active = true,
                'f' => row.is_frozen = true,
                else => {},
            };

            row.hotkey = self.dup(unescape(self.allocator, cols.next() orelse ""));
            row.description = self.dup(unescape(self.allocator, cols.next() orelse ""));
            row.addr_expr = self.dup(unescape(self.allocator, cols.next() orelse ""));
            row.address = self.dup(unescape(self.allocator, cols.next() orelse ""));
            row.val_type = self.dup(unescape(self.allocator, cols.next() orelse "4 Bytes"));
            row.value = self.dup(unescape(self.allocator, cols.next() orelse "???"));

            row.offsets = try parseOffsets(self.allocator, cols.next() orelse "");
            row.source = self.dup(unescape(self.allocator, cols.next() orelse ""));

            try self.rows.append(self.allocator, row);
        }

        self.resize();
    }
};

fn parseOffsets(allocator: std.mem.Allocator, text: []const u8) ![]const usize {
    if (text.len == 0) return &.{};
    var list: std.ArrayList(usize) = .empty;
    var it = std.mem.splitScalar(u8, text, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \r\n");
        if (trimmed.len == 0) continue;
        const value = std.fmt.parseInt(usize, trimmed, 16) catch continue;
        try list.append(allocator, value);
    }
    return list.toOwnedSlice(allocator);
}

/// Escapes tabs / newlines / backslashes so a row survives the TSV round-trip.
fn appendEscaped(out: *std.ArrayList(u8), allocator: std.mem.Allocator, str: []const u8) !void {
    for (str) |ch| switch (ch) {
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => {},
        else => try out.append(allocator, ch),
    };
}

fn unescape(allocator: std.mem.Allocator, str: []const u8) []const u8 {
    if (std.mem.indexOf(u8, str, "\\") == null) return str;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (str[i] == '\\' and i + 1 < str.len) {
            i += 1;
            switch (str[i]) {
                't' => out.append(allocator, '\t') catch {},
                'n' => out.append(allocator, '\n') catch {},
                '\\' => out.append(allocator, '\\') catch {},
                else => out.append(allocator, str[i]) catch {},
            }
        } else {
            out.append(allocator, str[i]) catch {};
        }
    }
    return out.toOwnedSlice(allocator) catch str;
}

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        for (needle, 0..) |n, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(n)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

// ============================================================================
// TESTS
// ============================================================================

fn sampleEntry(id: u32, desc: []const u8, addr: []const u8, kind: []const u8) ct_parser.CtEntry {
    return .{
        .id = id,
        .description = desc,
        .variable_type = kind,
        .address = addr,
        .offsets = &.{},
    };
}

test "ct_session round-trips rows, filter and script state through TSV" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator);
    defer session.deinit();

    const flat = [_]ct_parser.CtTable.FlatEntry{
        .{ .entry = sampleEntry(1, "God Mode\t[tab]", "", "Auto Assembler Script"), .depth = 0 },
        .{ .entry = sampleEntry(2, "Health\nBroken", "statsPtr+8", "4 Bytes"), .depth = 1 },
        .{ .entry = sampleEntry(3, "Character 1", "", "Group Header"), .depth = 0 },
    };
    const stats = try session.importTable("D:\\Mods\\BG3\\bg3.CT", "bg3", &flat, true);
    try std.testing.expectEqual(@as(usize, 3), stats.added);
    try std.testing.expectEqual(@as(usize, 3), session.rows.items.len);

    // Group detection + script detection
    try std.testing.expect(session.rows.items[2].is_group);
    try std.testing.expect(session.rows.items[0].is_script);
    try std.testing.expectEqual(@as(u16, 1), session.rows.items[1].depth);

    // Script state survives serialisation (this is what the UI toggles)
    try std.testing.expect(session.setScriptActive("D:\\Mods\\BG3\\bg3.CT", 1, true));
    session.filter = "health";
    try std.testing.expectEqual(@as(usize, 1), session.visibleRowCount());

    const blob = try session.serialize(allocator);
    defer allocator.free(blob);

    var restored = try Session.init(allocator);
    defer restored.deinit();
    try restored.deserialize(blob);

    try std.testing.expectEqual(@as(usize, 3), restored.rows.items.len);
    try std.testing.expectEqualStrings("health", restored.filter);
    try std.testing.expect(restored.rows.items[0].script_active);
    try std.testing.expectEqualStrings("God Mode\t[tab]", restored.rows.items[0].description);
    try std.testing.expectEqualStrings("Health\nBroken", restored.rows.items[1].description);
    try std.testing.expectEqualStrings("D:\\Mods\\BG3\\bg3.CT", restored.rows.items[1].source);
    try std.testing.expectEqual(@as(usize, 1), restored.tables.items.len);
}

test "ct_session merge keeps the previous address list and dedupes by source" {
    const allocator = std.testing.allocator;

    var session = try Session.init(allocator);
    defer session.deinit();

    const table_a = [_]ct_parser.CtTable.FlatEntry{
        .{ .entry = sampleEntry(10, "Table A row", "0x1000", "4 Bytes"), .depth = 0 },
    };
    const table_b = [_]ct_parser.CtTable.FlatEntry{
        .{ .entry = sampleEntry(20, "Table B row", "0x2000", "Float"), .depth = 0 },
        .{ .entry = sampleEntry(21, "Table B second", "0x2004", "Float"), .depth = 0 },
    };

    _ = try session.importTable("A.CT", "A", &table_a, true);
    const merged = try session.importTable("B.CT", "B", &table_b, false);

    // MERGE must not destroy what was already loaded.
    try std.testing.expectEqual(@as(usize, 2), merged.added);
    try std.testing.expectEqual(@as(usize, 0), merged.replaced_rows);
    try std.testing.expectEqual(@as(usize, 3), session.rows.items.len);
    try std.testing.expectEqualStrings("Table A row", session.rows.items[0].description);
    try std.testing.expectEqualStrings("Table B row", session.rows.items[1].description);

    // Re-merging B refreshes its rows instead of duplicating them.
    const again = try session.importTable("B.CT", "B", &table_b, false);
    try std.testing.expectEqual(@as(usize, 2), again.replaced_rows);
    try std.testing.expectEqual(@as(usize, 3), session.rows.items.len);

    // Replace mode still wipes everything (Cheat Engine's "Open").
    const replaced = try session.importTable("A.CT", "A", &table_a, true);
    try std.testing.expectEqual(@as(usize, 3), replaced.replaced_rows);
    try std.testing.expectEqual(@as(usize, 1), session.rows.items.len);
}

test "ct_session filter matches descriptions, addresses and hotkeys case-insensitively" {
    var row: Row = .{ .description = "Infinite Health", .address = "bg3.exe+24A266F", .hotkey = "CTRL+H" };
    try std.testing.expect(Session.rowMatches(&row, "health"));
    try std.testing.expect(Session.rowMatches(&row, "BG3.EXE"));
    try std.testing.expect(Session.rowMatches(&row, "ctrl+h"));
    try std.testing.expect(!Session.rowMatches(&row, "mana"));
    try std.testing.expect(Session.rowMatches(&row, ""));
}
