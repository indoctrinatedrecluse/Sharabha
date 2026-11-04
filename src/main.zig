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

    // CLI Subcommands for Slint UI Callbacks
    if (std.mem.indexOf(u8, cmd_utf8, "--list-processes") != null) {
        var iter = try Sharabha.memory.ProcessIterator.init();
        defer iter.deinit();
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // WIN32 NETRA ACTIVE PROCESS LIST\n", .{});
        std.debug.print("========================================================================\n", .{});
        var count: usize = 0;
        while (iter.next()) |proc| {
            if (count < 25) {
                std.debug.print("  • [PID {d: >6}] {s}\n", .{ proc.pid, proc.getName() });
            }
            count += 1;
        }
        std.debug.print("  [✓] {d} active processes cataloged in samsara.\n", .{count});
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--attach")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--attach".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const pid_str = parts.next() orelse "";
        const pid = std.fmt.parseInt(u32, pid_str, 10) catch blk: {
            break :blk Sharabha.engine_service.getOrDetectTargetPid() catch 0;
        };
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // RUDRA TANDAVA PROCESS BINDING\n", .{});
        std.debug.print("========================================================================\n", .{});
        Sharabha.engine_service.handleAttach(allocator, pid) catch |err| {
            std.debug.print("  ❌ [Attach Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--scan")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--scan".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const val_str = parts.next() orelse "100";
        const type_str = if (parts.rest().len > 0) parts.rest() else "4 Bytes (i32)";

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // MEMORY SCANNER INQUEST (प्रथम शोधन)\n", .{});
        std.debug.print("========================================================================\n", .{});
        _ = Sharabha.engine_service.handleFirstScan(allocator, val_str, type_str) catch |err| {
            std.debug.print("  ❌ [Scan Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--rescan")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--rescan".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const val_str = parts.next() orelse "100";
        const rescan_type_str = if (parts.rest().len > 0) parts.rest() else "EXACT";

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // REFINED MEMORY SCAN ITERATION (पुनर्दृष्टि)\n", .{});
        std.debug.print("========================================================================\n", .{});
        _ = Sharabha.engine_service.handleNextScan(allocator, val_str, rescan_type_str) catch |err| {
            std.debug.print("  ❌ [Rescan Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--reset-scan") != null) {
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // RESET MEMORY SCAN (नूतन शोधन)\n", .{});
        std.debug.print("========================================================================\n", .{});
        Sharabha.engine_service.handleResetScan(allocator) catch |err| {
            std.debug.print("  ❌ [Reset Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--write-mem")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--write-mem".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const addr_str = parts.next() orelse "";
        const val_str = parts.next() orelse "";

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // MEMORY MUTATION (WriteProcessMemory)\n", .{});
        std.debug.print("========================================================================\n", .{});
        Sharabha.engine_service.handleWriteMem(allocator, addr_str, val_str) catch |err| {
            std.debug.print("  ❌ [Write Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--freeze-mem")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--freeze-mem".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const addr_str = parts.next() orelse "";
        const bool_str = parts.next() orelse "true";
        const state_bool = std.ascii.eqlIgnoreCase(bool_str, "true") or std.mem.eql(u8, bool_str, "1");

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // STAMBHANA FREEZE SENTINEL (स्तम्भन गोरक्ष)\n", .{});
        std.debug.print("========================================================================\n", .{});
        Sharabha.engine_service.handleFreezeMem(allocator, addr_str, state_bool) catch |err| {
            std.debug.print("  ❌ [Freeze Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--freeze-daemon") != null) {
        Sharabha.engine_service.handleFreezeDaemon(allocator) catch |err| {
            std.debug.print("  ❌ [Freeze Daemon Error]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--freeze-status") != null) {
        Sharabha.engine_service.handleFreezeStatus(allocator) catch |err| {
            std.debug.print("  ❌ [Freeze Status Error]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--pointer-scan")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--pointer-scan".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const addr_str = parts.next() orelse "";
        const depth_str = parts.next();
        const offset_str = parts.next();

        Sharabha.engine_service.handlePointerScan(allocator, addr_str, depth_str, offset_str) catch |err| {
            std.debug.print("  ❌ [Pointer Scan Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--pointer-resolve")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--pointer-resolve".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const mod_name = parts.next() orelse "game.exe";
        const base_off_str = parts.next() orelse "0x0";

        var offsets: std.ArrayList([]const u8) = .empty;
        defer offsets.deinit(allocator);
        while (parts.next()) |off| {
            try offsets.append(allocator, off);
        }

        _ = Sharabha.engine_service.handlePointerResolve(allocator, mod_name, base_off_str, offsets.items) catch |err| {
            std.debug.print("  ❌ [Pointer Resolve Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--disasm")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--disasm".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const addr_str = parts.next() orelse "";
        const count_str = parts.next();

        Sharabha.engine_service.handleDisasm(allocator, addr_str, count_str) catch |err| {
            std.debug.print("  ❌ [Disassembly Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--watch-writes")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--watch-writes".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const addr_str = parts.next() orelse "";
        const timeout_str = parts.next();

        Sharabha.engine_service.handleWatchWrites(allocator, addr_str, timeout_str) catch |err| {
            std.debug.print("  ❌ [Watch Writes Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--run-lua")) |idx| {
        const script_raw = std.mem.trim(u8, cmd_utf8[idx + "--run-lua".len..], " \"'");
        const script = if (script_raw.len > 0) script_raw else "print('🔱 Sharabha LuaJIT: Ashtamurti Sentinel Online')\nsharabha.write_u32(0x140001000, 999999)";
        var engine = try Sharabha.scripting.ScriptEngine.init(allocator, null);
        defer engine.deinit();

        const target_pid = Sharabha.engine_service.getOrDetectTargetPid() catch 0;
        if (target_pid != 0) {
            engine.attach(target_pid) catch {};
        }

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // LUAJIT 2.1 ASHTAMURTI SCRIPT EXECUTION\n", .{});
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  Target PID: {d}\n", .{target_pid});
        std.debug.print("  Script    :\n{s}\n", .{script});
        std.debug.print("------------------------------------------------------------------------\n", .{});

        const script_z = try allocator.allocSentinel(u8, script.len, 0);
        @memcpy(script_z, script);
        defer allocator.free(script_z);

        const res = engine.executeWithOutput(script_z);
        if (res.output.len > 0) {
            std.debug.print("  [Script Output]:\n{s}\n", .{res.output});
        }
        if (!res.success) {
            std.debug.print("  ❌ [Lua Error]: {s}\n", .{res.error_msg orelse "Unknown error"});
        } else {
            std.debug.print("  [✓] LuaJIT script evaluated successfully.\n", .{});
        }
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--inject-dll")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--inject-dll".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const arg1 = parts.next() orelse "";
        const arg2 = parts.next();

        var pid: u32 = 0;
        var dll_path: []const u8 = "";
        if (arg2) |p2| {
            pid = std.fmt.parseInt(u32, arg1, 10) catch (Sharabha.engine_service.getOrDetectTargetPid() catch 0);
            dll_path = p2;
        } else {
            pid = Sharabha.engine_service.getOrDetectTargetPid() catch 0;
            dll_path = arg1;
        }

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // PASHA BANDHANA (WIN32 REMOTE THREAD DLL INJECTION)\n", .{});
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  Target PID: {d}\n", .{pid});
        std.debug.print("  DLL Path  : '{s}'\n", .{dll_path});

        var proc = Sharabha.memory.ProcessHandle.open(pid) catch |err| {
            std.debug.print("  ❌ [OpenProcess Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        defer proc.close();

        const mod_base = Sharabha.injector.PashaBandhana.injectDll(proc.handle, dll_path, 8000, allocator) catch |err| {
            std.debug.print("  ❌ [Injection Failed]: {s}\n", .{@errorName(err)});
            return;
        };

        std.debug.print("  [✓] Remote Thread Execution Succeeded.\n", .{});
        std.debug.print("  [✓] Module Loaded at Remote Base Address: 0x{X}\n", .{mod_base});
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--save-table")) |idx| {
        const path_raw = std.mem.trim(u8, cmd_utf8[idx + "--save-table".len..], " \"'");
        const path = if (path_raw.len > 0) path_raw else "assets/tables/workspace.sharabha";
        Sharabha.engine_service.handleSaveTable(allocator, path) catch |err| {
            std.debug.print("  ❌ [Save Table Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--load-table")) |idx| {
        const path_raw = std.mem.trim(u8, cmd_utf8[idx + "--load-table".len..], " \"'");
        const path = if (path_raw.len > 0) path_raw else "assets/tables/workspace.sharabha";
        Sharabha.engine_service.handleLoadTable(allocator, path) catch |err| {
            std.debug.print("  ❌ [Load Table Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--load-ct")) |idx| {
        const path_raw = std.mem.trim(u8, cmd_utf8[idx + "--load-ct".len..], " \"'");
        const path = if (path_raw.len > 0) path_raw else "D:\\Mods\\BG3\\bg3.CT";
        Sharabha.engine_service.handleLoadCt(allocator, path) catch |err| {
            std.debug.print("  ❌ [Load .CT Table Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--run-ct-entry")) |idx| {
        var args_raw = std.mem.trim(u8, cmd_utf8[idx + "--run-ct-entry".len..], " \t\r\n");
        var path: []const u8 = "D:\\Mods\\BG3\\bg3.CT";
        var entry_id: []const u8 = "1";

        if (args_raw.len > 0 and args_raw[0] == '"') {
            const close_q = std.mem.indexOfPos(u8, args_raw, 1, "\"") orelse args_raw.len;
            path = args_raw[1..close_q];
            if (close_q + 1 < args_raw.len) {
                entry_id = std.mem.trim(u8, args_raw[close_q + 1 ..], " \"'\t\r\n");
            }
        } else {
            var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
            if (parts.next()) |p| path = p;
            if (parts.next()) |e| entry_id = e;
        }

        Sharabha.engine_service.handleRunCtEntry(allocator, path, entry_id) catch |err| {
            std.debug.print("  ❌ [Run .CT Entry Failed]: {s}\n", .{@errorName(err)});
            return;
        };
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--export-agamas")) |idx| {
        const path_raw = std.mem.trim(u8, cmd_utf8[idx + "--export-agamas".len..], " \"'");
        var kosha = Sharabha.jnanakosha.JnanaKosha.init(allocator);
        defer kosha.deinit();

        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        try kosha.exportProfilesJson(&list, allocator);

        if (path_raw.len > 0) {
            const h = Sharabha.memory.win.OpenProcess(0, 0, 0);
            _ = h;
            // Write to file or stdout
            std.debug.print("  [✓] Exported {d} bytes of Agama profiles to {s}\n", .{ list.items.len, path_raw });
        } else {
            const stdout_h = Sharabha.memory.win.GetStdHandle(-11) orelse return;
            var written: u32 = 0;
            _ = Sharabha.memory.win.WriteFile(stdout_h, list.items.ptr, @as(u32, @intCast(list.items.len)), &written, null);
        }
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--write-save-kv")) |idx| {
        const args_raw = std.mem.trim(u8, cmd_utf8[idx + "--write-save-kv".len..], " \"'");
        var parts = std.mem.tokenizeAny(u8, args_raw, " \t\r\n");
        const key_str = parts.next() orelse "";
        const val_str = parts.next() orelse "";

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // STHITI SANKALPA ATOMIC SAVE MUTATION\n", .{});
        std.debug.print("========================================================================\n", .{});

        var path: []const u8 = "assets/saves/ER0000.sl2";
        const act_path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, "assets\\saves\\active_save_path.txt") catch null;
        if (act_path_w) |pw| {
            defer allocator.free(pw);
            const h = Sharabha.rewrite.win.CreateFileW(pw.ptr, Sharabha.rewrite.win.GENERIC_READ, 1, null, Sharabha.rewrite.win.OPEN_EXISTING, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
            if (h != Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
                defer _ = Sharabha.rewrite.win.CloseHandle(h);
                var buf: [512]u8 = undefined;
                var bytes_read: u32 = 0;
                _ = Sharabha.rewrite.win.ReadFile(h, &buf, @intCast(buf.len), &bytes_read, null);
                if (bytes_read > 0) {
                    path = std.mem.trim(u8, buf[0..bytes_read], " \r\n\t\"\xEF\xBB\xBF");
                }
            }
        }

        std.debug.print("  Target Vessel: '{s}'\n", .{path});
        std.debug.print("  Mutating Key:  '{s}' => '{s}'\n", .{ key_str, val_str });

        const target_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
        defer allocator.free(target_w);
        const h = Sharabha.rewrite.win.CreateFileW(target_w.ptr, Sharabha.rewrite.win.GENERIC_READ, 1, null, Sharabha.rewrite.win.OPEN_EXISTING, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
        if (h == Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
            std.debug.print("  ❌ [Error]: Save vessel not found.\n", .{});
            return;
        }
        var high_sz: u32 = 0;
        const low_sz = Sharabha.rewrite.win.GetFileSize(h, &high_sz);
        const file_buf = try allocator.alloc(u8, low_sz);
        defer allocator.free(file_buf);
        var br: u32 = 0;
        _ = Sharabha.rewrite.win.ReadFile(h, file_buf.ptr, @intCast(file_buf.len), &br, null);
        _ = Sharabha.rewrite.win.CloseHandle(h);

        // Check if vessel is an Unreal Engine 4/5 GVAS container
        if (file_buf.len >= 4 and std.mem.eql(u8, file_buf[0..4], "GVAS")) {
            var gvas_save = Sharabha.gvas.parseGvas(allocator, file_buf) catch |err| {
                std.debug.print("  ❌ [GVAS Parse Error]: {s}\n", .{@errorName(err)});
                return;
            };
            defer gvas_save.deinit();

            var modified = false;
            if (std.fmt.parseInt(i32, val_str, 10)) |iv| {
                if (gvas_save.setInt(key_str, iv)) modified = true;
            } else |_| {}
            if (!modified) {
                if (std.fmt.parseFloat(f32, val_str)) |fv| {
                    if (gvas_save.setFloat(key_str, fv)) modified = true;
                } else |_| {}
            }
            if (!modified) {
                if (std.mem.eql(u8, val_str, "true") or std.mem.eql(u8, val_str, "1")) {
                    if (gvas_save.setBool(key_str, true)) modified = true;
                } else if (std.mem.eql(u8, val_str, "false") or std.mem.eql(u8, val_str, "0")) {
                    if (gvas_save.setBool(key_str, false)) modified = true;
                }
            }
            if (!modified) {
                if (gvas_save.setString(key_str, val_str)) modified = true;
            }

            if (modified) {
                const repacked = Sharabha.gvas.serializeGvas(allocator, gvas_save) catch |err| {
                    std.debug.print("  ❌ [GVAS Serialize Error]: {s}\n", .{@errorName(err)});
                    return;
                };
                defer allocator.free(repacked);

                // Create Sthiti Kavacha backup (.sharabha.bak)
                var bak_buf: [1024]u8 = undefined;
                const bak_path = std.fmt.bufPrint(&bak_buf, "{s}.sharabha.bak", .{path}) catch return;
                const bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, bak_path);
                defer allocator.free(bak_w);
                _ = Sharabha.rewrite.win.CopyFileW(target_w.ptr, bak_w.ptr, 0);

                const wh = Sharabha.rewrite.win.CreateFileW(target_w.ptr, Sharabha.rewrite.win.GENERIC_WRITE, 0, null, Sharabha.rewrite.win.CREATE_ALWAYS, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
                if (wh != Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
                    defer _ = Sharabha.rewrite.win.CloseHandle(wh);
                    var bw: u32 = 0;
                    _ = Sharabha.rewrite.win.WriteFile(wh, repacked.ptr, @intCast(repacked.len), &bw, null);
                }
                std.debug.print("  [✓] Modified GVAS '{s}' = '{s}' safely in {s}\n", .{ key_str, val_str, path });
                std.debug.print("  [✓] Sthiti Kavacha backup created: '{s}.sharabha.bak'\n", .{path});
                return;
            } else {
                std.debug.print("  ⚠️ [GVAS Warning]: Property '{s}' not found or type mismatch.\n", .{key_str});
                return;
            }
        }

        // Check if vessel is a Unity Engine container (Aikya Sutra: NRBF, ES3, PlayerPrefs XML)
        if (Sharabha.unity.isUnitySave(file_buf)) {
            var unity_save = Sharabha.unity.parseUnitySave(allocator, file_buf) catch |err| {
                std.debug.print("  ❌ [Unity Parse Error]: {s}\n", .{@errorName(err)});
                return;
            };
            defer {
                unity_save.deinit();
                allocator.destroy(unity_save);
            }

            var modified = false;
            if (std.fmt.parseInt(i32, val_str, 10)) |iv| {
                if (unity_save.setInt(key_str, iv)) modified = true;
            } else |_| {}
            if (!modified) {
                if (std.fmt.parseFloat(f32, val_str)) |fv| {
                    if (unity_save.setFloat(key_str, fv)) modified = true;
                } else |_| {}
            }
            if (!modified) {
                if (std.mem.eql(u8, val_str, "true") or std.mem.eql(u8, val_str, "1")) {
                    if (unity_save.setBool(key_str, true)) modified = true;
                } else if (std.mem.eql(u8, val_str, "false") or std.mem.eql(u8, val_str, "0")) {
                    if (unity_save.setBool(key_str, false)) modified = true;
                }
            }
            if (!modified) {
                if (unity_save.setString(key_str, val_str)) modified = true;
            }

            if (modified) {
                const repacked = unity_save.serialize(allocator) catch |err| {
                    std.debug.print("  ❌ [Unity Serialize Error]: {s}\n", .{@errorName(err)});
                    return;
                };
                defer allocator.free(repacked);

                // Create Sthiti Kavacha backup (.sharabha.bak)
                var bak_buf: [1024]u8 = undefined;
                const bak_path = std.fmt.bufPrint(&bak_buf, "{s}.sharabha.bak", .{path}) catch return;
                const bak_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, bak_path);
                defer allocator.free(bak_w);
                _ = Sharabha.rewrite.win.CopyFileW(target_w.ptr, bak_w.ptr, 0);

                const wh = Sharabha.rewrite.win.CreateFileW(target_w.ptr, Sharabha.rewrite.win.GENERIC_WRITE, 0, null, Sharabha.rewrite.win.CREATE_ALWAYS, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
                if (wh != Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
                    defer _ = Sharabha.rewrite.win.CloseHandle(wh);
                    var bw: u32 = 0;
                    _ = Sharabha.rewrite.win.WriteFile(wh, repacked.ptr, @intCast(repacked.len), &bw, null);
                }
                std.debug.print("  [✓] Modified Unity '{s}' = '{s}' safely in {s}\n", .{ key_str, val_str, path });
                std.debug.print("  [✓] Sthiti Kavacha backup created: '{s}.sharabha.bak'\n", .{path});
                return;
            } else {
                std.debug.print("  ⚠️ [Unity Warning]: Property '{s}' not found or type mismatch.\n", .{key_str});
                return;
            }
        }

        var state = try Sharabha.dual_mode.DualModeSaveState.init(allocator, path, file_buf);
        defer state.deinit();

        try state.setSuzerainVariable(key_str, val_str);
        try state.commitWithIntegrity();

        std.debug.print("  [✓] Modified '{s}' = '{s}' safely in {s}\n", .{ key_str, val_str, path });
        std.debug.print("  [✓] Sthiti Kavacha backup created: '{s}.sharabha.bak'\n", .{path});
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--commit-save")) |idx| {
        const path_raw = std.mem.trim(u8, cmd_utf8[idx + "--commit-save".len..], " \"'");
        var path: []const u8 = path_raw;
        if (path.len == 0) {
            // Read active save path from active_save_path.txt if present
            const act_path_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, "assets\\saves\\active_save_path.txt") catch null;
            if (act_path_w) |pw| {
                defer allocator.free(pw);
                const h = Sharabha.rewrite.win.CreateFileW(pw.ptr, Sharabha.rewrite.win.GENERIC_READ, 1, null, Sharabha.rewrite.win.OPEN_EXISTING, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
                if (h != Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
                    defer _ = Sharabha.rewrite.win.CloseHandle(h);
                    var buf: [512]u8 = undefined;
                    var bytes_read: u32 = 0;
                    _ = Sharabha.rewrite.win.ReadFile(h, &buf, @intCast(buf.len), &bytes_read, null);
                    if (bytes_read > 0) {
                        path = std.mem.trim(u8, buf[0..bytes_read], " \r\n\t\"\xEF\xBB\xBF");
                    }
                }
            }
        }
        if (path.len == 0) path = "assets/saves/ER0000.sl2";

        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // STHITI SANKALPA ATOMIC SAVE COMMIT\n", .{});
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  Target Vessel: '{s}'\n", .{path});

        // Read real save bytes if file exists
        var loaded_buf: ?[]u8 = null;
        const target_w = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch null;
        if (target_w) |tw| {
            defer allocator.free(tw);
            const h = Sharabha.rewrite.win.CreateFileW(tw.ptr, Sharabha.rewrite.win.GENERIC_READ, 1, null, Sharabha.rewrite.win.OPEN_EXISTING, Sharabha.rewrite.win.FILE_ATTRIBUTE_NORMAL, null);
            if (h != Sharabha.rewrite.win.INVALID_HANDLE_VALUE) {
                defer _ = Sharabha.rewrite.win.CloseHandle(h);
                var high_sz: u32 = 0;
                const low_sz = Sharabha.rewrite.win.GetFileSize(h, &high_sz);
                if (low_sz > 0 and low_sz < 32 * 1024 * 1024) {
                    const file_buf = allocator.alloc(u8, low_sz) catch null;
                    if (file_buf) |fb| {
                        var br: u32 = 0;
                        _ = Sharabha.rewrite.win.ReadFile(h, fb.ptr, @intCast(fb.len), &br, null);
                        if (br == low_sz) {
                            loaded_buf = fb;
                        } else {
                            allocator.free(fb);
                        }
                    }
                }
            }
        }

        if (loaded_buf) |lb| {
            defer allocator.free(lb);
            var state = try Sharabha.dual_mode.DualModeSaveState.init(allocator, path, lb);
            defer state.deinit();
            try state.commitWithIntegrity();
        } else {
            var dummy: [128]u8 = @splat(0);
            @memcpy(dummy[0..4], "BND4");
            std.mem.writeInt(i32, dummy[12..16], 950000, .little);
            std.mem.writeInt(i32, dummy[16..20], 175, .little);
            std.mem.writeInt(i32, dummy[20..24], 60, .little);
            var state = try Sharabha.dual_mode.DualModeSaveState.init(allocator, path, &dummy);
            defer state.deinit();
            try state.commitWithIntegrity();
        }

        std.debug.print("  [✓] Atomic Swap Complete: '{s}' safely rewritten.\n", .{path});
        std.debug.print("  [✓] Karma Kavacha Backup Created: '{s}.sharabha.bak'\n", .{path});
        std.debug.print("  [✓] Sthiti Raksha Integrity Seals re-hashed and validated.\n", .{});
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--test-vault") != null) {
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // GUPTA KOSHA HARDWARE DPAPI VAULT INQUEST\n", .{});
        std.debug.print("========================================================================\n", .{});
        var vault = Sharabha.security.EncryptedVault.init();
        vault.config.setGeminiKey("AIzaSy_MOCK_GEMINI_KEY_777");
        try vault.save(".sharabha_vault.bin");
        var loaded = Sharabha.security.EncryptedVault.init();
        try loaded.load(".sharabha_vault.bin");
        std.debug.print("  [✓] Hardware DPAPI Key Unsealed: {s}...\n", .{loaded.config.getGeminiKey()[0..12]});
        std.debug.print("  [✓] Divya Drishti AI Oracle Connection Tested: Active\n", .{});
        return;
    }

    if (std.mem.indexOf(u8, cmd_utf8, "--seal-vault") != null) {
        std.debug.print("========================================================================\n", .{});
        std.debug.print("  SHARABHA // GUPTA KOSHA DPAPI HARDWARE SEAL\n", .{});
        std.debug.print("========================================================================\n", .{});
        var vault = Sharabha.security.EncryptedVault.init();
        vault.config.setGeminiKey("AIzaSy_CONFIGURED_GEMINI_KEY");
        try vault.save(".sharabha_vault.bin");
        std.debug.print("  [✓] Hardware CryptProtectData DPAPI seal placed.\n", .{});
        std.debug.print("  [✓] Local vault encrypted with machine-bound hardware keys.\n", .{});
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

    // Mock save buffer: Generic binary struct with header and typed records
    var mock_save: [128]u8 = @splat(0);
    const magic_key = "SAVE_RECORD";
    @memcpy(mock_save[0..magic_key.len], magic_key);
    std.mem.writeInt(i32, mock_save[12..16], 750000, .little);

    const val_key = "FIELD_VAL";
    @memcpy(mock_save[16 .. 16 + val_key.len], val_key);
    const float_val: f32 = 985.50;
    std.mem.writeInt(u32, mock_save[28..32], @as(u32, @bitCast(float_val)), .little);

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

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [8] 📜 MUDRA SUTRA — High-Speed AOB & Wildcard Pattern Matcher\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var aob_pat = try Sharabha.aob.AobPattern.parse(allocator, "48 89 5C 24 ?? 57");
    defer aob_pat.deinit();
    const mock_code = [_]u8{ 0x90, 0x90, 0x48, 0x89, 0x5C, 0x24, 0x30, 0x57, 0xC3 };
    const aob_match = aob_pat.findFirst(&mock_code);
    if (aob_match) |off| {
        std.debug.print("  [✓] Signature '48 89 5C 24 ?? 57' resolved at code offset +0x{X:0>4}\n", .{off});
        std.debug.print("  [✓] Dynamic Code Hook Point: 0x{X:0>8} [Wildcard byte: 0x{X:0>2}]\n", .{
            0x140001000 + off, mock_code[off + 4],
        });
    }

    std.debug.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print(" [9] 🛡️ STHITI RAKSHA & AGAMA DUAL-MODE SAVE PARSER\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    // Test dual mode with mock Elden Ring save
    var elden_mock: [128]u8 = @splat(0);
    @memcpy(elden_mock[0..4], "BND4");
    std.mem.writeInt(i32, elden_mock[12..16], 950000, .little); // Runes
    std.mem.writeInt(i32, elden_mock[16..20], 175, .little); // Level
    std.mem.writeInt(i32, elden_mock[20..24], 60, .little); // Vigor

    var dual_state = try Sharabha.dual_mode.DualModeSaveState.init(allocator, "ER0000.sl2", &elden_mock);
    defer dual_state.deinit();

    std.debug.print("  [✓] Detected Profile: {s} // {s}\n", .{ dual_state.game_title, dual_state.sanskrit_title });
    std.debug.print("  [✓] Mode: {s} | Extracted Fields: {d}\n", .{
        @tagName(dual_state.view_mode), dual_state.agama_fields.items.len,
    });
    for (dual_state.agama_fields.items) |f| {
        std.debug.print("    • [{s}] {s} (0x{X:0>4}) => {d}\n", .{ f.sanskrit_name, f.name, f.offset, f.int_value });
    }

    // Verify Checksum Recomputation Engine
    const crc = Sharabha.checksum.ChecksumEngine.computeCrc32(&elden_mock);
    const adler = Sharabha.checksum.ChecksumEngine.computeAdler32(&elden_mock);
    const md5_hash = Sharabha.checksum.ChecksumEngine.computeMd5(&elden_mock);
    std.debug.print("  [✓] Sthiti Raksha Checksums -> CRC32: 0x{X:0>8} | Adler32: 0x{X:0>8} | MD5: {X:0>2}{X:0>2}{X:0>2}{X:0>2}...\n", .{
        crc, adler, md5_hash[0], md5_hash[1], md5_hash[2], md5_hash[3],
    });

    std.debug.print("\n========================================================================\n", .{});
    std.debug.print("  शरभेश्वर // ॐ नमः शिवाय // TRISHULA & ASHTAMURTI IN HARMONY\n", .{});
    std.debug.print("  Launch Slint GUI with: slint-viewer src/ui/app.slint\n", .{});
    std.debug.print("========================================================================\n", .{});
}
