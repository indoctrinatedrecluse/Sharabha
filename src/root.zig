const std = @import("std");

pub const memory = @import("memory/process.zig");
pub const scanner = @import("memory/scanner.zig");

pub const entropy = @import("save/entropy.zig");
pub const fuzzy = @import("save/fuzzy.zig");
pub const rewrite = @import("save/rewrite.zig");

pub fn printBanner() void {
    std.debug.print(
        \\
        \\============================================================
        \\  🦁🐦 SHARABHA — The Dual Aspect Engine (v0.1.0)
        \\  [Save Forge: Calm]   │   [Memory Engine: Destructive]
        \\============================================================
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
