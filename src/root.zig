const std = @import("std");

pub const memory = @import("memory/process.zig");
pub const scanner = @import("memory/scanner.zig");

pub const entropy = @import("save/entropy.zig");
pub const fuzzy = @import("save/fuzzy.zig");
pub const rewrite = @import("save/rewrite.zig");

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
    _ = entropy;
    _ = fuzzy;
    _ = rewrite;
}
