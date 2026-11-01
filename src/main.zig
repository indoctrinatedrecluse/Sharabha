const std = @import("std");
const Sharabha = @import("Sharabha");

pub fn main() !void {
    Sharabha.printBanner();

    const allocator = std.heap.page_allocator;

    // =========================================================================
    // 1. RUDRA MEMORY ENGINE (Destructive / Active Aspect)
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [1] 🔥 RUDRA ENGINE — Process Enumeration & Memory Subsystem\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var iter = try Sharabha.memory.ProcessIterator.init();
    defer iter.deinit();

    var proc_count: usize = 0;
    while (iter.next()) |proc| {
        if (proc_count < 5) {
            std.debug.print("  • [PID {d: >6}] {s}\n", .{ proc.pid, proc.getName() });
        }
        proc_count += 1;
    }
    std.debug.print("  [✓] Win32 Toolhelp snapshot active: {d} running processes detected.\n\n", .{proc_count});

    // =========================================================================
    // 2. KALYANA SAVE FORGE (Calm / Heuristic Aspect)
    // =========================================================================
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [2] 🧊 SAVE FORGE — Fuzzy Heuristic & Entropy Analysis\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    // Synthetic mock save payload: header + player gold + health float + world coordinate
    var mock_save: [128]u8 = @splat(0);
    const gold_key = "HERO_GOLD";
    @memcpy(mock_save[0..gold_key.len], gold_key);
    mock_save[gold_key.len] = 0; // null terminator
    std.mem.writeInt(i32, mock_save[12..16], 750000, .little);

    const hp_key = "HP_FLOAT";
    @memcpy(mock_save[16 .. 16 + hp_key.len], hp_key);
    mock_save[16 + hp_key.len] = 0;
    const hp_val: f32 = 985.50;
    std.mem.writeInt(u32, mock_save[28..32], @as(u32, @bitCast(hp_val)), .little);

    // Calculate Shannon entropy
    const h = Sharabha.entropy.calculateShannonEntropy(&mock_save);
    const classification = Sharabha.entropy.classifyEntropy(h);
    std.debug.print("  • Save Buffer Entropy: {d:.3} bits/byte ({s})\n", .{
        h,
        @tagName(classification),
    });

    // Fuzzy parser inference
    var parser = Sharabha.fuzzy.FuzzyParser.init(allocator);
    defer parser.deinit();

    const inferred_fields = try parser.parse(&mock_save);
    std.debug.print("  • Inferred Key-Value Fields ({d} candidates detected):\n", .{inferred_fields.len});

    for (inferred_fields) |field| {
        std.debug.print("    [0x{X:0>4}] ({d: >2}% conf) {s: <20} => '{s}'\n", .{
            field.offset,
            field.confidence,
            field.inferred_type.name(),
            field.getDisplayValue(),
        });
    }

    // =========================================================================
    // 3. STHITI SAFE REWRITE ENGINE (Atomic Shadow Write & Backup)
    // =========================================================================
    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [3] 🛡️ SAFE REWRITE — Atomic Swap & .sharabha.bak Karma Shield\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var rewrite_engine = Sharabha.rewrite.SafeRewriteEngine.init(allocator);
    const demo_save_path = "sharabha_demo.sav";

    // Write initial
    try rewrite_engine.commitSafe(demo_save_path, mock_save[0..32]);
    std.debug.print("  • Initial save committed to '{s}'\n", .{demo_save_path});

    // Mutate and rewrite
    std.mem.writeInt(i32, mock_save[12..16], 9999999, .little);
    try rewrite_engine.commitSafe(demo_save_path, mock_save[0..32]);
    std.debug.print("  • Modified save atomically committed! Backup '{s}.sharabha.bak' verified.\n", .{demo_save_path});

    // Clean up demo files
    const demo_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, demo_save_path);
    defer allocator.free(demo_w);
    const demo_bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "sharabha_demo.sav.sharabha.bak");
    defer allocator.free(demo_bak_w);
    _ = Sharabha.memory.win.DeleteFileW(demo_w.ptr);
    _ = Sharabha.memory.win.DeleteFileW(demo_bak_w.ptr);

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("  OM NAMAH SHIVAYA — Sharabha Engine Subsystems Verified!\n", .{});
    std.debug.print("============================================================\n", .{});
}
