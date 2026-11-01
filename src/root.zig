const std = @import("std");

pub const memory = @import("memory/process.zig");

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
}
