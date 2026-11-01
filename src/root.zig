const std = @import("std");

pub const memory = @import("memory/process.zig");
pub const scanner = @import("memory/scanner.zig");
pub const freeze = @import("memory/freeze.zig");
pub const pointer = @import("memory/pointer.zig");

pub const entropy = @import("save/entropy.zig");
pub const fuzzy = @import("save/fuzzy.zig");
pub const rewrite = @import("save/rewrite.zig");
pub const switcher = @import("save/switcher.zig");
pub const knowledge = @import("knowledge/profiles.zig");
pub const security = @import("security/vault.zig");
pub const ai = @import("ai/analyzer.zig");

pub fn printBanner() void {
    std.debug.print(
        \\
        \\========================================================================
        \\  🦁🐦 SHARABHA (शरभेश्वर) — The Dual Aspect Engine (v0.1.0)
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
    _ = entropy;
    _ = fuzzy;
    _ = rewrite;
    _ = switcher;
    _ = knowledge;
    _ = security;
    _ = ai;
}
