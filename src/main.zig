const std = @import("std");
const Sharabha = @import("Sharabha");

pub fn main() !void {
    Sharabha.printBanner();

    std.debug.print("Enumerating active processes via Win32 Toolhelp snapshot...\n", .{});

    var iter = try Sharabha.memory.ProcessIterator.init();
    defer iter.deinit();

    var count: usize = 0;
    while (iter.next()) |proc| {
        if (count < 15) {
            std.debug.print("  [PID {d: >6}] {s}\n", .{ proc.pid, proc.getName() });
        }
        count += 1;
    }

    std.debug.print("\nTotal running processes detected: {d}\n", .{count});
    std.debug.print("Process enumeration & Win32 subsystem verified successfully!\n", .{});
}
