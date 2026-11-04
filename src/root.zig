const std = @import("std");

pub const memory = @import("memory/process.zig");
pub const scanner = @import("memory/scanner.zig");
pub const freeze = @import("memory/freeze.zig");
pub const pointer = @import("memory/pointer.zig");
pub const aob = @import("memory/aob.zig");
pub const disasm = @import("memory/disasm.zig");
pub const debugger = @import("memory/debugger.zig");
pub const engine_service = @import("memory/engine_service.zig");
pub const injector = @import("memory/injector.zig");
pub const table = @import("memory/table.zig");
pub const ct_parser = @import("memory/ct_parser.zig");
pub const breakpoint = @import("memory/breakpoint.zig");

pub const entropy = @import("save/entropy.zig");
pub const fuzzy = @import("save/fuzzy.zig");
pub const rewrite = @import("save/rewrite.zig");
pub const switcher = @import("save/switcher.zig");
pub const checksum = @import("save/checksum.zig");
pub const dual_mode = @import("save/dual_mode.zig");
pub const diff = @import("save/diff.zig");
pub const gvas = @import("save/gvas.zig");
pub const unity = @import("save/unity.zig");
pub const knowledge = @import("knowledge/profiles.zig");
pub const security = @import("security/vault.zig");
pub const ai = @import("ai/analyzer.zig");
pub const scripting = @import("scripting/engine.zig");
pub const ce_compat = @import("scripting/ce_compat.zig");
pub const jnanakosha = @import("knowledge/jnanakosha.zig");
pub const chitrapata = @import("media/chitrapata.zig");

pub fn printBanner() void {
    std.debug.print(
        \\
        \\========================================================================
        \\  🦁🐦 SHARABHA (शरभेश्वर) — The Dual Aspect Engine (v0.5.1)
        \\  [Kalyana Sthiti: Calm / शान्त]   │   [Rudra Tandava: Violent / उग्र]
        \\  ॐ नमः शरभाय — Subduing Narasimha & The Untamed Process
        \\========================================================================
        \\
    , .{});
}

test {
    _ = memory;
    _ = scanner;
    _ = freeze;
    _ = pointer;
    _ = aob;
    _ = disasm;
    _ = debugger;
    _ = engine_service;
    _ = injector;
    _ = table;
    _ = ct_parser;
    _ = breakpoint;
    _ = entropy;
    _ = fuzzy;
    _ = rewrite;
    _ = switcher;
    _ = checksum;
    _ = dual_mode;
    _ = diff;
    _ = gvas;
    _ = unity;
    _ = knowledge;
    _ = security;
    _ = ai;
    _ = scripting;
    _ = ce_compat;
    _ = jnanakosha;
    _ = chitrapata;
}
