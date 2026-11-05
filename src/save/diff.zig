//! ============================================================================
//! SHARABHA (शरभ) — KALA CHAKRA: VISUAL SAVE DIFF & EVOLUTION INSPECTOR
//! (काल चक्र // The Wheel of Time)
//! High-Performance Binary Span Differencing & Structured Property Delta Engine
//! Computes Mutations, Numerical Deltas, Type Inferences, and Agama Promotions.
//! ============================================================================

const std = @import("std");
const fuzzy = @import("fuzzy.zig");
const gvas = @import("gvas.zig");
const unity = @import("unity.zig");
const rpgmaker = @import("rpgmaker.zig");

pub const MutationKind = enum {
    Modified,
    Added,
    Removed,
};

pub const DiffMutation = struct {
    offset: usize,
    length: usize,
    key_name: []const u8,
    kind: MutationKind,
    inferred_type: fuzzy.InferredType,
    old_val_str: []const u8,
    new_val_str: []const u8,
    delta_str: []const u8,
    confidence: u8, // 0 - 100%
    hex_preview: []const u8,
};

pub const SaveDiffReport = struct {
    arena: *std.heap.ArenaAllocator,
    file_a_name: []const u8,
    file_b_name: []const u8,
    total_mutations: usize,
    mutations: []const DiffMutation,

    pub fn deinit(self: *SaveDiffReport, child_allocator: std.mem.Allocator) void {
        const arena_ptr = self.arena;
        arena_ptr.deinit();
        child_allocator.destroy(arena_ptr);
    }
};

/// Compares two binary buffers and generates a list of grouped mutations
pub fn diffBinaryBuffers(
    child_allocator: std.mem.Allocator,
    buf_a: []const u8,
    buf_b: []const u8,
    file_a_name: []const u8,
    file_b_name: []const u8,
) !*SaveDiffReport {
    const arena = try child_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(child_allocator);
    errdefer {
        arena.deinit();
        child_allocator.destroy(arena);
    }
    const alloc = arena.allocator();

    var mutation_list: std.ArrayList(DiffMutation) = .empty;

    const min_len = @min(buf_a.len, buf_b.len);
    var cursor: usize = 0;

    while (cursor < min_len) {
        if (buf_a[cursor] != buf_b[cursor]) {
            // Check if this falls inside a 4-byte aligned boundary
            const aligned_start = cursor & ~@as(usize, 3);
            if (aligned_start + 4 <= min_len and (cursor == aligned_start or cursor < aligned_start + 4)) {
                // Check if the change fits inside this 4-byte dword
                const a_slice = buf_a[aligned_start .. aligned_start + 4];
                const b_slice = buf_b[aligned_start .. aligned_start + 4];

                if (!std.mem.eql(u8, a_slice, b_slice)) {
                    // Check if next dword also differs (longer mutation)
                    var span_end = aligned_start + 4;
                    while (span_end + 4 <= min_len and !std.mem.eql(u8, buf_a[span_end .. span_end + 4], buf_b[span_end .. span_end + 4])) : (span_end += 4) {}

                    const span_len = span_end - aligned_start;

                    var key_buf: [48]u8 = undefined;
                    const key_str = try std.fmt.bufPrint(&key_buf, "0x{X:0>4}", .{aligned_start});
                    const key_dupe = try alloc.dupe(u8, key_str);

                    var old_val: []const u8 = "";
                    var new_val: []const u8 = "";
                    var delta: []const u8 = "";
                    var inf_type: fuzzy.InferredType = .Int32LE;
                    var conf: u8 = 75;

                    var hex_buf: [64]u8 = undefined;
                    var hex_str: []const u8 = "";

                    if (span_len == 4) {
                        const i_old = std.mem.readInt(i32, a_slice[0..4], .little);
                        const i_new = std.mem.readInt(i32, b_slice[0..4], .little);

                        const f_old = @as(f32, @bitCast(std.mem.readInt(u32, a_slice[0..4], .little)));
                        const f_new = @as(f32, @bitCast(std.mem.readInt(u32, b_slice[0..4], .little)));

                        if (std.math.isFinite(f_old) and std.math.isFinite(f_new) and f_old > 0.001 and f_old < 100000.0 and f_new > 0.001 and f_new < 100000.0) {
                            inf_type = .Float32LE;
                            old_val = try std.fmt.allocPrint(alloc, "{d:.2}", .{f_old});
                            new_val = try std.fmt.allocPrint(alloc, "{d:.2}", .{f_new});
                            const diff_f = f_new - f_old;
                            delta = try std.fmt.allocPrint(alloc, "{s}{d:.2}", .{ if (diff_f >= 0) "+" else "", diff_f });
                            conf = 88;
                        } else {
                            inf_type = .Int32LE;
                            old_val = try std.fmt.allocPrint(alloc, "{d}", .{i_old});
                            new_val = try std.fmt.allocPrint(alloc, "{d}", .{i_new});
                            const diff_i = @as(i64, i_new) - @as(i64, i_old);
                            delta = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff_i >= 0) "+" else "", diff_i });
                            conf = 92;
                        }

                        hex_str = try std.fmt.bufPrint(&hex_buf, "{X:0>2} {X:0>2} {X:0>2} {X:0>2}", .{
                            b_slice[0], b_slice[1], b_slice[2], b_slice[3],
                        });
                    } else {
                        inf_type = .RawBinary;
                        old_val = try std.fmt.allocPrint(alloc, "[{d} bytes]", .{span_len});
                        new_val = try std.fmt.allocPrint(alloc, "[{d} bytes]", .{span_len});
                        delta = "Mutated Block";
                        conf = 70;
                        hex_str = try std.fmt.bufPrint(&hex_buf, "{X:0>2} {X:0>2} {X:0>2} {X:0>2}...", .{
                            buf_b[aligned_start], buf_b[aligned_start + 1], buf_b[aligned_start + 2], buf_b[aligned_start + 3],
                        });
                    }

                    try mutation_list.append(alloc, .{
                        .offset = aligned_start,
                        .length = span_len,
                        .key_name = key_dupe,
                        .kind = .Modified,
                        .inferred_type = inf_type,
                        .old_val_str = old_val,
                        .new_val_str = new_val,
                        .delta_str = delta,
                        .confidence = conf,
                        .hex_preview = try alloc.dupe(u8, hex_str),
                    });

                    cursor = span_end;
                    continue;
                }
            }

            // Single unaligned byte change
            const b_old = buf_a[cursor];
            const b_new = buf_b[cursor];
            var key_buf: [48]u8 = undefined;
            const key_str = try std.fmt.bufPrint(&key_buf, "0x{X:0>4}", .{cursor});

            var hex_buf: [64]u8 = undefined;
            const hex_str = try std.fmt.bufPrint(&hex_buf, "{X:0>2}", .{b_new});
            const diff_b = @as(i16, b_new) - @as(i16, b_old);
            const delta = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff_b >= 0) "+" else "", diff_b });

            try mutation_list.append(alloc, .{
                .offset = cursor,
                .length = 1,
                .key_name = try alloc.dupe(u8, key_str),
                .kind = .Modified,
                .inferred_type = .RawBinary,
                .old_val_str = try std.fmt.allocPrint(alloc, "0x{X:0>2} ({d})", .{ b_old, b_old }),
                .new_val_str = try std.fmt.allocPrint(alloc, "0x{X:0>2} ({d})", .{ b_new, b_new }),
                .delta_str = delta,
                .confidence = 80,
                .hex_preview = try alloc.dupe(u8, hex_str),
            });
            cursor += 1;
        } else {
            cursor += 1;
        }
    }

    // Size delta check
    if (buf_a.len != buf_b.len) {
        const sz_diff = @as(i64, @intCast(buf_b.len)) - @as(i64, @intCast(buf_a.len));
        const delta_msg = try std.fmt.allocPrint(alloc, "{s}{d} bytes", .{ if (sz_diff >= 0) "+" else "", sz_diff });
        try mutation_list.append(alloc, .{
            .offset = min_len,
            .length = @abs(sz_diff),
            .key_name = try alloc.dupe(u8, "VESSEL_LENGTH"),
            .kind = if (sz_diff > 0) .Added else .Removed,
            .inferred_type = .RawBinary,
            .old_val_str = try std.fmt.allocPrint(alloc, "{d} bytes", .{buf_a.len}),
            .new_val_str = try std.fmt.allocPrint(alloc, "{d} bytes", .{buf_b.len}),
            .delta_str = delta_msg,
            .confidence = 100,
            .hex_preview = try alloc.dupe(u8, "CONTAINER_RESIZE"),
        });
    }

    const report = try alloc.create(SaveDiffReport);
    report.* = .{
        .arena = arena,
        .file_a_name = try alloc.dupe(u8, file_a_name),
        .file_b_name = try alloc.dupe(u8, file_b_name),
        .total_mutations = mutation_list.items.len,
        .mutations = mutation_list.items,
    };
    return report;
}

/// Compares two Unreal Engine GVAS saves by structured FProperty keys
pub fn diffGvasSaves(
    child_allocator: std.mem.Allocator,
    gvas_a: *const gvas.GvasSave,
    gvas_b: *const gvas.GvasSave,
    file_a_name: []const u8,
    file_b_name: []const u8,
) !*SaveDiffReport {
    const arena = try child_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(child_allocator);
    errdefer {
        arena.deinit();
        child_allocator.destroy(arena);
    }
    const alloc = arena.allocator();

    var mutation_list: std.ArrayList(DiffMutation) = .empty;

    // Check all properties in B against A
    for (gvas_b.properties) |prop_b| {
        if (gvas_a.findProperty(prop_b.name)) |prop_a| {
            // Check if values differ
            var old_str: []const u8 = "";
            var new_str: []const u8 = "";
            var delta_str: []const u8 = "";
            var changed = false;

            switch (prop_b.value) {
                .Int => |iv_b| {
                    if (prop_a.value == .Int) {
                        const iv_a = prop_a.value.Int;
                        if (iv_a != iv_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_b});
                            const diff = @as(i64, iv_b) - @as(i64, iv_a);
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Int64 => |i64v_b| {
                    if (prop_a.value == .Int64) {
                        const i64v_a = prop_a.value.Int64;
                        if (i64v_a != i64v_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d}", .{i64v_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d}", .{i64v_b});
                            const diff = i64v_b - i64v_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Float => |fv_b| {
                    if (prop_a.value == .Float) {
                        const fv_a = prop_a.value.Float;
                        if (@abs(fv_a - fv_b) > 0.0001) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d:.2}", .{fv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d:.2}", .{fv_b});
                            const diff = fv_b - fv_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d:.2}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Double => |dv_b| {
                    if (prop_a.value == .Double) {
                        const dv_a = prop_a.value.Double;
                        if (@abs(dv_a - dv_b) > 0.00001) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d:.4}", .{dv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d:.4}", .{dv_b});
                            const diff = dv_b - dv_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d:.4}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Bool => |bv_b| {
                    if (prop_a.value == .Bool) {
                        const bv_a = prop_a.value.Bool;
                        if (bv_a != bv_b) {
                            changed = true;
                            old_str = if (bv_a) "true" else "false";
                            new_str = if (bv_b) "true" else "false";
                            delta_str = if (bv_b) "Toggled TRUE" else "Toggled FALSE";
                        }
                    }
                },
                .Str => |sv_b| {
                    if (prop_a.value == .Str) {
                        const sv_a = prop_a.value.Str;
                        if (!std.mem.eql(u8, sv_a, sv_b)) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "'{s}'", .{sv_a});
                            new_str = try std.fmt.allocPrint(alloc, "'{s}'", .{sv_b});
                            delta_str = "String Mutated";
                        }
                    }
                },
                else => {},
            }

            if (changed) {
                try mutation_list.append(alloc, .{
                    .offset = 0,
                    .length = prop_b.size,
                    .key_name = try alloc.dupe(u8, prop_b.name),
                    .kind = .Modified,
                    .inferred_type = switch (prop_b.prop_type) {
                        .IntProperty => .Int32LE,
                        .Int64Property => .Int64LE,
                        .FloatProperty => .Float32LE,
                        .DoubleProperty => .Float64LE,
                        .StrProperty, .NameProperty => .StringAscii,
                        else => .RawBinary,
                    },
                    .old_val_str = old_str,
                    .new_val_str = new_str,
                    .delta_str = delta_str,
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "GVAS_PROPERTY"),
                });
            }
        } else {
            // Added property in B
            try mutation_list.append(alloc, .{
                .offset = 0,
                .length = prop_b.size,
                .key_name = try alloc.dupe(u8, prop_b.name),
                .kind = .Added,
                .inferred_type = .RawBinary,
                .old_val_str = "(unset)",
                .new_val_str = "[New Property]",
                .delta_str = "+New Property",
                .confidence = 100,
                .hex_preview = try alloc.dupe(u8, "GVAS_NEW"),
            });
        }
    }

    const report = try alloc.create(SaveDiffReport);
    report.* = .{
        .arena = arena,
        .file_a_name = try alloc.dupe(u8, file_a_name),
        .file_b_name = try alloc.dupe(u8, file_b_name),
        .total_mutations = mutation_list.items.len,
        .mutations = mutation_list.items,
    };
    return report;
}

/// Compares two Unity saves (NRBF, ES3, PlayerPrefs XML) by structured property keys
pub fn diffUnitySaves(
    child_allocator: std.mem.Allocator,
    unity_a: *const unity.UnitySave,
    unity_b: *const unity.UnitySave,
    file_a_name: []const u8,
    file_b_name: []const u8,
) !*SaveDiffReport {
    const arena = try child_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(child_allocator);
    errdefer {
        arena.deinit();
        child_allocator.destroy(arena);
    }
    const alloc = arena.allocator();

    var mutation_list: std.ArrayList(DiffMutation) = .empty;

    // Check all properties in B against A
    for (unity_b.properties.items) |prop_b| {
        var found_a: ?unity.UnityProperty = null;
        for (unity_a.properties.items) |pa| {
            if (std.mem.eql(u8, pa.name, prop_b.name)) {
                found_a = pa;
                break;
            }
        }

        if (found_a) |prop_a| {
            var old_str: []const u8 = "";
            var new_str: []const u8 = "";
            var delta_str: []const u8 = "";
            var changed = false;

            switch (prop_b.value) {
                .Int => |iv_b| {
                    if (prop_a.value == .Int) {
                        const iv_a = prop_a.value.Int;
                        if (iv_a != iv_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_b});
                            const diff = @as(i64, iv_b) - @as(i64, iv_a);
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Int64 => |iv_b| {
                    if (prop_a.value == .Int64) {
                        const iv_a = prop_a.value.Int64;
                        if (iv_a != iv_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d}", .{iv_b});
                            const diff = iv_b - iv_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Float => |fv_b| {
                    if (prop_a.value == .Float) {
                        const fv_a = prop_a.value.Float;
                        if (fv_a != fv_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d:.2}", .{fv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d:.2}", .{fv_b});
                            const diff = fv_b - fv_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d:.2}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Double => |dv_b| {
                    if (prop_a.value == .Double) {
                        const dv_a = prop_a.value.Double;
                        if (dv_a != dv_b) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "{d:.4}", .{dv_a});
                            new_str = try std.fmt.allocPrint(alloc, "{d:.4}", .{dv_b});
                            const diff = dv_b - dv_a;
                            delta_str = try std.fmt.allocPrint(alloc, "{s}{d:.4}", .{ if (diff >= 0) "+" else "", diff });
                        }
                    }
                },
                .Bool => |bv_b| {
                    if (prop_a.value == .Bool) {
                        const bv_a = prop_a.value.Bool;
                        if (bv_a != bv_b) {
                            changed = true;
                            old_str = if (bv_a) "true" else "false";
                            new_str = if (bv_b) "true" else "false";
                            delta_str = if (bv_b) "Toggled TRUE" else "Toggled FALSE";
                        }
                    }
                },
                .Str => |sv_b| {
                    if (prop_a.value == .Str) {
                        const sv_a = prop_a.value.Str;
                        if (!std.mem.eql(u8, sv_a, sv_b)) {
                            changed = true;
                            old_str = try std.fmt.allocPrint(alloc, "'{s}'", .{sv_a});
                            new_str = try std.fmt.allocPrint(alloc, "'{s}'", .{sv_b});
                            delta_str = "String Mutated";
                        }
                    }
                },
                else => {},
            }

            if (changed) {
                try mutation_list.append(alloc, .{
                    .offset = prop_b.offset,
                    .length = prop_b.size,
                    .key_name = try alloc.dupe(u8, prop_b.name),
                    .kind = .Modified,
                    .inferred_type = switch (prop_b.prop_type) {
                        .Int32 => .Int32LE,
                        .Int64 => .Int64LE,
                        .Single => .Float32LE,
                        .Double => .Float64LE,
                        .String => .StringAscii,
                        else => .RawBinary,
                    },
                    .old_val_str = old_str,
                    .new_val_str = new_str,
                    .delta_str = delta_str,
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "UNITY_PROPERTY"),
                });
            }
        } else {
            // Added property in B
            try mutation_list.append(alloc, .{
                .offset = prop_b.offset,
                .length = prop_b.size,
                .key_name = try alloc.dupe(u8, prop_b.name),
                .kind = .Added,
                .inferred_type = .RawBinary,
                .old_val_str = "<absent>",
                .new_val_str = "<present>",
                .delta_str = "+New Property",
                .confidence = 100,
                .hex_preview = try alloc.dupe(u8, "UNITY_NEW"),
            });
        }
    }

    const report = try alloc.create(SaveDiffReport);
    report.* = .{
        .arena = arena,
        .file_a_name = try alloc.dupe(u8, file_a_name),
        .file_b_name = try alloc.dupe(u8, file_b_name),
        .total_mutations = mutation_list.items.len,
        .mutations = mutation_list.items,
    };
    return report;
}

/// Compares two RPG Maker Saves and produces typed property deltas (Gold, Actors, Variables, Switches)
pub fn diffRpgMakerSaves(
    child_allocator: std.mem.Allocator,
    save_a: *const rpgmaker.RpgMakerSave,
    save_b: *const rpgmaker.RpgMakerSave,
    file_a_name: []const u8,
    file_b_name: []const u8,
) !*SaveDiffReport {
    const arena = try child_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(child_allocator);
    errdefer {
        arena.deinit();
        child_allocator.destroy(arena);
    }
    const alloc = arena.allocator();

    var mutation_list: std.ArrayList(DiffMutation) = .empty;

    // 1. Gold Diff
    if (save_a.gold != null or save_b.gold != null) {
        const ga = save_a.gold orelse 0;
        const gb = save_b.gold orelse 0;
        if (ga != gb) {
            const diff = gb - ga;
            try mutation_list.append(alloc, .{
                .offset = 0,
                .length = 4,
                .key_name = try alloc.dupe(u8, "Party Gold (_gold)"),
                .kind = .Modified,
                .inferred_type = .Int32LE,
                .old_val_str = try std.fmt.allocPrint(alloc, "{d}", .{ga}),
                .new_val_str = try std.fmt.allocPrint(alloc, "{d}", .{gb}),
                .delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff }),
                .confidence = 100,
                .hex_preview = try alloc.dupe(u8, "RPG_GOLD"),
            });
        }
    }

    // 2. Actor Stats Diff
    for (save_b.actors) |actor_b| {
        var found_a: ?rpgmaker.RpgMakerActor = null;
        for (save_a.actors) |actor_a| {
            if (actor_a.id == actor_b.id) {
                found_a = actor_a;
                break;
            }
        }

        if (found_a) |actor_a| {
            if (actor_a.level != actor_b.level) {
                const diff = actor_b.level - actor_a.level;
                const name = try std.fmt.allocPrint(alloc, "Actor #{d} Level ({s})", .{ actor_b.id, actor_b.name });
                try mutation_list.append(alloc, .{
                    .offset = 0,
                    .length = 4,
                    .key_name = name,
                    .kind = .Modified,
                    .inferred_type = .Int32LE,
                    .old_val_str = try std.fmt.allocPrint(alloc, "{d}", .{actor_a.level}),
                    .new_val_str = try std.fmt.allocPrint(alloc, "{d}", .{actor_b.level}),
                    .delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff }),
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "RPG_LEVEL"),
                });
            }
            if (actor_a.hp != actor_b.hp) {
                const diff = actor_b.hp - actor_a.hp;
                const name = try std.fmt.allocPrint(alloc, "Actor #{d} HP ({s})", .{ actor_b.id, actor_b.name });
                try mutation_list.append(alloc, .{
                    .offset = 0,
                    .length = 4,
                    .key_name = name,
                    .kind = .Modified,
                    .inferred_type = .Int32LE,
                    .old_val_str = try std.fmt.allocPrint(alloc, "{d}", .{actor_a.hp}),
                    .new_val_str = try std.fmt.allocPrint(alloc, "{d}", .{actor_b.hp}),
                    .delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff }),
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "RPG_HP"),
                });
            }
        }
    }

    // 3. Variables Diff
    for (save_b.variables) |var_b| {
        for (save_a.variables) |var_a| {
            if (var_a.id == var_b.id and var_a.value != var_b.value) {
                const diff = var_b.value - var_a.value;
                const name = try std.fmt.allocPrint(alloc, "Variable #{d}", .{var_b.id});
                try mutation_list.append(alloc, .{
                    .offset = 0,
                    .length = 4,
                    .key_name = name,
                    .kind = .Modified,
                    .inferred_type = .Int32LE,
                    .old_val_str = try std.fmt.allocPrint(alloc, "{d}", .{var_a.value}),
                    .new_val_str = try std.fmt.allocPrint(alloc, "{d}", .{var_b.value}),
                    .delta_str = try std.fmt.allocPrint(alloc, "{s}{d}", .{ if (diff >= 0) "+" else "", diff }),
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "RPG_VAR"),
                });
            }
        }
    }

    // 4. Switches Diff
    for (save_b.switches) |sw_b| {
        for (save_a.switches) |sw_a| {
            if (sw_a.id == sw_b.id and sw_a.value != sw_b.value) {
                const name = try std.fmt.allocPrint(alloc, "Switch #{d}", .{sw_b.id});
                try mutation_list.append(alloc, .{
                    .offset = 0,
                    .length = 1,
                    .key_name = name,
                    .kind = .Modified,
                    .inferred_type = .RawBinary,
                    .old_val_str = if (sw_a.value) "true" else "false",
                    .new_val_str = if (sw_b.value) "true" else "false",
                    .delta_str = if (sw_b.value) "Toggled TRUE" else "Toggled FALSE",
                    .confidence = 100,
                    .hex_preview = try alloc.dupe(u8, "RPG_SWITCH"),
                });
            }
        }
    }

    const report = try alloc.create(SaveDiffReport);
    report.* = .{
        .arena = arena,
        .file_a_name = try alloc.dupe(u8, file_a_name),
        .file_b_name = try alloc.dupe(u8, file_b_name),
        .total_mutations = mutation_list.items.len,
        .mutations = mutation_list.items,
    };
    return report;
}

test "Kala Chakra: Binary Save Diff Detects Mutations and Deltas" {
    const alloc = std.testing.allocator;

    var save_a: [64]u8 = @splat(0);
    var save_b: [64]u8 = @splat(0);

    // Baseline: Gold = 1000 at offset 16
    std.mem.writeInt(i32, save_a[16..20], 1000, .little);
    // Evolution: Gold = 5500 at offset 16
    std.mem.writeInt(i32, save_b[16..20], 5500, .little);

    // Baseline: Level = 1 at offset 32
    save_a[32] = 1;
    // Evolution: Level = 5 at offset 32
    save_b[32] = 5;

    const report = try diffBinaryBuffers(alloc, &save_a, &save_b, "SaveA.bin", "SaveB.bin");
    defer report.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), report.total_mutations);

    // Mutation 1: Gold change
    const m1 = report.mutations[0];
    try std.testing.expectEqual(@as(usize, 16), m1.offset);
    try std.testing.expectEqualStrings("1000", m1.old_val_str);
    try std.testing.expectEqualStrings("5500", m1.new_val_str);
    try std.testing.expectEqualStrings("+4500", m1.delta_str);

    // Mutation 2: Level change
    const m2 = report.mutations[1];
    try std.testing.expectEqual(@as(usize, 32), m2.offset);
    try std.testing.expectEqualStrings("+4", m2.delta_str);
}

test "Kala Chakra: GVAS Structured Property Diff" {
    const alloc = std.testing.allocator;

    var props_a: [2]gvas.GvasProperty = .{
        .{ .name = "PlayerGold", .prop_type = .IntProperty, .prop_type_str = "IntProperty", .size = 4, .array_index = 0, .value = .{ .Int = 99999 } },
        .{ .name = "IsHardcore", .prop_type = .BoolProperty, .prop_type_str = "BoolProperty", .size = 0, .array_index = 0, .value = .{ .Bool = true } },
    };

    var props_b: [2]gvas.GvasProperty = .{
        .{ .name = "PlayerGold", .prop_type = .IntProperty, .prop_type_str = "IntProperty", .size = 4, .array_index = 0, .value = .{ .Int = 777777 } },
        .{ .name = "IsHardcore", .prop_type = .BoolProperty, .prop_type_str = "BoolProperty", .size = 0, .array_index = 0, .value = .{ .Bool = false } },
    };

    var gvas_a = gvas.GvasSave{
        .arena = undefined,
        .header = .{},
        .properties = &props_a,
        .trailing_data = &.{},
    };

    var gvas_b = gvas.GvasSave{
        .arena = undefined,
        .header = .{},
        .properties = &props_b,
        .trailing_data = &.{},
    };

    const report = try diffGvasSaves(alloc, &gvas_a, &gvas_b, "SaveA.sav", "SaveB.sav");
    defer report.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), report.total_mutations);
    try std.testing.expectEqualStrings("+677778", report.mutations[0].delta_str);
    try std.testing.expectEqualStrings("Toggled FALSE", report.mutations[1].delta_str);
}

test "Kala Chakra: Unity Save Diff Detects Mutations and Deltas" {
    const alloc = std.testing.allocator;

    const mock_es3_a =
        \\{
        \\  "PlayerGold": {
        \\    "__type": "int",
        \\    "value": 50000
        \\  },
        \\  "PlayerHealth": {
        \\    "__type": "float",
        \\    "value": 100.0
        \\  }
        \\}
    ;

    const mock_es3_b =
        \\{
        \\  "PlayerGold": {
        \\    "__type": "int",
        \\    "value": 999999
        \\  },
        \\  "PlayerHealth": {
        \\    "__type": "float",
        \\    "value": 250.5
        \\  }
        \\}
    ;

    var unity_a = try unity.parseUnitySave(alloc, mock_es3_a);
    defer {
        unity_a.deinit();
        alloc.destroy(unity_a);
    }

    var unity_b = try unity.parseUnitySave(alloc, mock_es3_b);
    defer {
        unity_b.deinit();
        alloc.destroy(unity_b);
    }

    const report = try diffUnitySaves(alloc, unity_a, unity_b, "SaveA.es3", "SaveB.es3");
    defer report.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), report.total_mutations);
    try std.testing.expectEqualStrings("+949999", report.mutations[0].delta_str);
    try std.testing.expectEqualStrings("+150.50", report.mutations[1].delta_str);
}

test "Kala Chakra: RPG Maker Save Diff Detects Mutations and Deltas" {
    const alloc = std.testing.allocator;

    const json_a =
        \\{
        \\  "party": { "_gold": 5000 },
        \\  "actors": { "_data": [null, { "_actorId": 1, "_name": "Harold", "_level": 10, "_hp": 500, "_mp": 100 }] },
        \\  "variables": { "_data": [null, 42] },
        \\  "switches": { "_data": [null, false] }
        \\}
    ;

    const json_b =
        \\{
        \\  "party": { "_gold": 99999 },
        \\  "actors": { "_data": [null, { "_actorId": 1, "_name": "Harold", "_level": 25, "_hp": 850, "_mp": 100 }] },
        \\  "variables": { "_data": [null, 999] },
        \\  "switches": { "_data": [null, true] }
        \\}
    ;

    var save_a = try rpgmaker.RpgMakerSave.parse(alloc, json_a);
    defer save_a.deinit(alloc);

    var save_b = try rpgmaker.RpgMakerSave.parse(alloc, json_b);
    defer save_b.deinit(alloc);

    const report = try diffRpgMakerSaves(alloc, save_a, save_b, "SaveA.rpgsave", "SaveB.rpgsave");
    defer report.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 5), report.total_mutations);
    try std.testing.expectEqualStrings("+94999", report.mutations[0].delta_str); // Gold
    try std.testing.expectEqualStrings("+15", report.mutations[1].delta_str);    // Level
    try std.testing.expectEqualStrings("+350", report.mutations[2].delta_str);   // HP
    try std.testing.expectEqualStrings("+957", report.mutations[3].delta_str);   // Var 1
    try std.testing.expectEqualStrings("Toggled TRUE", report.mutations[4].delta_str); // Switch 1
}
