const std = @import("std");
const Sharabha = @import("Sharabha");

pub fn main() !void {
    Sharabha.printBanner();

    const allocator = std.heap.page_allocator;

    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [1] 🔥 RUDRA TANDAVA — Process Inquest & Stambhana Freeze\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    // 1. Enumerate active processes
    var iter = try Sharabha.memory.ProcessIterator.init();
    defer iter.deinit();

    var proc_count: usize = 0;
    while (iter.next()) |proc| {
        if (proc_count < 4) {
            std.debug.print("  • [PID {d: >6}] {s}\n", .{ proc.pid, proc.getName() });
        }
        proc_count += 1;
    }
    std.debug.print("  [✓] Win32 Netra active: {d} running processes detected in samsara.\n", .{proc_count});

    // 2. Test Stambhana Freeze Sentinel
    var freeze_mgr = Sharabha.freeze.FreezeManager.init(allocator, 25);
    defer freeze_mgr.deinit();
    const mock_freeze_val: i32 = 999999;
    try freeze_mgr.addOrUpdate(0x00401000, std.mem.asBytes(&mock_freeze_val), "HP_LOCK");
    std.debug.print("  [✓] Stambhana Goraksha initialized: 1 sentinel freeze entry primed.\n\n", .{});

    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [2] 🧊 KALYANA STHITI — Multi-Metric Engine & Heuristic Switcher\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var switching_engine = Sharabha.switcher.SwitchingEngine.init(allocator);

    // Mock save buffer: Header + Hero Gold + Health float
    var mock_save: [128]u8 = @splat(0);
    const gold_key = "HERO_GOLD";
    @memcpy(mock_save[0..gold_key.len], gold_key);
    std.mem.writeInt(i32, mock_save[12..16], 750000, .little);

    const hp_key = "HP_FLOAT";
    @memcpy(mock_save[16 .. 16 + hp_key.len], hp_key);
    const hp_val: f32 = 985.50;
    std.mem.writeInt(u32, mock_save[28..32], @as(u32, @bitCast(hp_val)), .little);

    // Evaluate across multiple metrics:
    const shannon_rep = switching_engine.evaluateMetric(.ShannonEntropy, &mock_save);
    std.debug.print("  • Metric 1 [Shannon Entropy]: {s} => {s}\n", .{
        shannon_rep.getScore(),
        shannon_rep.getVerdict(),
    });

    const chi_rep = switching_engine.evaluateMetric(.ChiSquare, &mock_save);
    std.debug.print("  • Metric 2 [Chi-Square Test]: {s} => {s}\n", .{
        chi_rep.getScore(),
        chi_rep.getVerdict(),
    });

    const density_rep = switching_engine.evaluateMetric(.ByteDensity, &mock_save);
    std.debug.print("  • Metric 3 [Byte Density]:    {s} => {s}\n", .{
        density_rep.getScore(),
        density_rep.getVerdict(),
    });

    // Extract fields via Auto Heuristic
    var extracted_fields = try switching_engine.extractFields(.Auto, &mock_save, "hero.sav");
    defer extracted_fields.deinit(allocator);

    std.debug.print("  [✓] Extracted Fields ({d} candidates detected):\n", .{extracted_fields.items.len});
    for (extracted_fields.items[0..@min(extracted_fields.items.len, 4)]) |field| {
        std.debug.print("    - [0x{X:0>4}] ({d: >2}% conf) {s: <20} => '{s}'\n", .{
            field.offset,
            field.confidence,
            field.inferred_type.name(),
            field.getDisplayValue(),
        });
    }

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [3] 🔐 GUPTA KOSHA — Windows DPAPI Encrypted Vault & Divya AI\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var vault = Sharabha.security.EncryptedVault.init();
    const vault_path = "sharabha_vault.bin";
    vault.load(vault_path) catch {
        // First run or uninitialized
    };
    std.debug.print("  [✓] Hardware DPAPI Vault active. Provider: {s}\n", .{
        vault.config.selected_provider.displayName(),
    });

    // Test AI Pre-Analysis prompt construction
    const prompt = try Sharabha.ai.buildAnalysisPrompt(allocator, "hero.sav", &mock_save, shannon_rep);
    defer allocator.free(prompt);
    std.debug.print("  [✓] Divya Drishti (AI Oracle) prompt generated ({d} bytes).\n", .{prompt.len});

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [4] 🛡️ STHITI SANKALPA — Atomic Commit & Karma Kavacha\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var rewrite_engine = Sharabha.rewrite.SafeRewriteEngine.init(allocator);
    const demo_save = "sharabha_demo.sav";
    try rewrite_engine.commitSafe(demo_save, mock_save[0..32]);

    // Mutate and rewrite atomically
    std.mem.writeInt(i32, mock_save[12..16], 9999999, .little);
    try rewrite_engine.commitSafe(demo_save, mock_save[0..32]);
    std.debug.print("  [✓] Atomic Swap verified. Backup created: '{s}.sharabha.bak'\n", .{demo_save});

    // Clean up demo files
    const demo_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, demo_save);
    defer allocator.free(demo_w);
    const demo_bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "sharabha_demo.sav.sharabha.bak");
    defer allocator.free(demo_bak_w);
    _ = Sharabha.memory.win.DeleteFileW(demo_w.ptr);
    _ = Sharabha.memory.win.DeleteFileW(demo_bak_w.ptr);

    std.debug.print("\n========================================================================\n", .{});
    std.debug.print("  शरभेश्वर // ॐ नमः शिवाय // TRISHULA & ASHTAMURTI IN HARMONY\n", .{});
    std.debug.print("  Launch Slint GUI with: slint-viewer src/ui/app.slint\n", .{});
    std.debug.print("========================================================================\n", .{});
}
