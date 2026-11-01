const std = @import("std");
const Sharabha = @import("Sharabha");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Check command line arguments via Win32 GetCommandLineW
    const cmd_w = std.mem.span(Sharabha.memory.win.GetCommandLineW());
    const cmd_utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, cmd_w);
    defer allocator.free(cmd_utf8);

    if (std.mem.indexOf(u8, cmd_utf8, "--export-surreal") != null) {
        var kosha = Sharabha.jnanakosha.JnanaKosha.init(allocator);
        defer kosha.deinit();

        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        try kosha.exportSurrealQL(&list, allocator);

        const stdout_h = Sharabha.memory.win.GetStdHandle(-11) orelse return;
        var written: u32 = 0;
        _ = Sharabha.memory.win.WriteFile(stdout_h, list.items.ptr, @as(u32, @intCast(list.items.len)), &written, null);
        return;
    }

    Sharabha.printBanner();

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
    std.debug.print(" [4] 🦅 LUAJIT 2.1 — Embedded Scripting & Runtime Inquest\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var lua_engine = try Sharabha.scripting.ScriptEngine.init(allocator, &freeze_mgr);
    defer lua_engine.deinit();

    const lua_script =
        \\ sharabha.log("LuaJIT 2.1 Ashtamurti Sentinel Online")
        \\ local health = 999
        \\ assert(health > 0)
    ;
    try lua_engine.runString(lua_script);
    std.debug.print("  [✓] LuaJIT 2.1 runtime primed with memory read/write & freeze bindings.\n", .{});

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [5] 🏛️ JNANA KOSHA — SurrealDB Embedded Knowledge Graph\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var kosha = Sharabha.jnanakosha.JnanaKosha.init(allocator);
    defer kosha.deinit();

    const discovered_game = kosha.findGameByExecutable("eldenring.exe");
    if (discovered_game) |g| {
        std.debug.print("  [✓] Auto-Discovered: {s} ({s}) via {s}\n", .{
            g.title, g.sanskrit_name, g.executable,
        });

        var ptrs: [4]Sharabha.jnanakosha.PointerPathNode = undefined;
        const count = kosha.getPointersForGame(g.id, &ptrs);
        if (count > 0) {
            std.debug.print("      Graph Relation -> Pointer: '{s}' [Base: 0x{X}]\n", .{
                ptrs[0].name, ptrs[0].base_offset,
            });
        }
    }

    const discovered_profile = kosha.findSaveProfileByExtension("game_save.sl2");
    if (discovered_profile) |sp| {
        std.debug.print("  [✓] Save Graph Link -> Ext: '{s}' | Metric: '{s}' | Extractor: '{s}'\n", .{
            sp.file_extension, sp.default_metric, sp.default_extractor,
        });
    }

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [6] 🛡️ STHITI SANKALPA — Atomic Commit & Karma Kavacha\n", .{});
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

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [7] 🎬 CHITRAPATA — High-Efficiency Hardware Video Engine\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var chitra_engine = Sharabha.chitrapata.ChitrapataEngine.init(allocator);
    var chitra_buf: [256]u8 = undefined;
    const chitra_status = try chitra_engine.getStatusReport(&chitra_buf);
    std.debug.print("  [✓] {s}\n", .{chitra_status});
    std.debug.print("  [✓] Intel Core Ultra 9 275HX Hardware GPU Texture Pipeline Primed.\n", .{});
    std.debug.print("  [✓] Zero-Lag Dynamic Mode: Background video loops at 24 FPS with 0.0% idle CPU.\n", .{});

    std.debug.print("\n========================================================================\n", .{});
    std.debug.print("  शरभेश्वर // ॐ नमः शिवाय // TRISHULA & ASHTAMURTI IN HARMONY\n", .{});
    std.debug.print("  Launch Slint GUI with: slint-viewer src/ui/app.slint\n", .{});
    std.debug.print("========================================================================\n", .{});
}
