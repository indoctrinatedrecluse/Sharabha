//! ============================================================================
//! SHARABHA (शरभ) — CHITRAPATA (चित्रपट) VIDEO ENGINE
//! High-Efficiency Native Hardware Video Telemetry & Loop Frame Orchestrator
//! Optimized for High-End Intel Core Ultra 9 275HX Hardware Architectures
//! ============================================================================

const std = @import("std");

pub const ChitrapataMode = enum(u8) {
    SacredAltarStill = 0,
    AnimatedMotionLoop = 1,
    MinimalObsidianOff = 2,

    pub fn getEnglishName(self: ChitrapataMode) []const u8 {
        return switch (self) {
            .SacredAltarStill => "SACRED ALTAR (Still)",
            .AnimatedMotionLoop => "ANIMATED LOOP (Motion)",
            .MinimalObsidianOff => "MINIMAL OBSIDIAN (Off)",
        };
    }

    pub fn getSanskritName(self: ChitrapataMode) []const u8 {
        return switch (self) {
            .SacredAltarStill => "स्थिर वेदी (Sthira Vedi)",
            .AnimatedMotionLoop => "सजीव चित्रपट (Sajiva Chitrapata)",
            .MinimalObsidianOff => "निराकार ध्यान (Nirakara Dhyana)",
        };
    }
};

pub const VideoStreamTelemetry = struct {
    file_path: []const u8,
    total_frames: u32,
    target_fps: f32,
    duration_seconds: f32,
    frame_interval_ms: u32,
    width: u32,
    height: u32,
    is_cached: bool,

    pub fn init(file_path: []const u8, total_frames: u32, fps: f32, width: u32, height: u32) VideoStreamTelemetry {
        const dur = if (fps > 0) @as(f32, @floatFromInt(total_frames)) / fps else 0;
        const interval: u32 = if (fps > 0) @intFromFloat(1000.0 / fps) else 42;
        return .{
            .file_path = file_path,
            .total_frames = total_frames,
            .target_fps = fps,
            .duration_seconds = dur,
            .frame_interval_ms = interval,
            .width = width,
            .height = height,
            .is_cached = true,
        };
    }
};

pub const ChitrapataEngine = struct {
    allocator: std.mem.Allocator,
    current_mode: ChitrapataMode,
    canvas_opacity: f32,
    loop_telemetry: VideoStreamTelemetry,
    splash_telemetry: VideoStreamTelemetry,

    pub fn init(allocator: std.mem.Allocator) ChitrapataEngine {
        return .{
            .allocator = allocator,
            .current_mode = .SacredAltarStill,
            .canvas_opacity = 0.88,
            .loop_telemetry = VideoStreamTelemetry.init("assets/media/bg_canvas_loop.mp4", 239, 24.0, 1280, 720),
            .splash_telemetry = VideoStreamTelemetry.init("assets/media/splash_sharabha.mp4", 143, 24.0, 1280, 720),
        };
    }

    pub fn cycleMode(self: *ChitrapataEngine) ChitrapataMode {
        self.current_mode = switch (self.current_mode) {
            .SacredAltarStill => .AnimatedMotionLoop,
            .AnimatedMotionLoop => .MinimalObsidianOff,
            .MinimalObsidianOff => .SacredAltarStill,
        };
        self.canvas_opacity = switch (self.current_mode) {
            .SacredAltarStill => 0.88,
            .AnimatedMotionLoop => 0.92,
            .MinimalObsidianOff => 0.0,
        };
        return self.current_mode;
    }

    pub fn getStatusReport(self: *const ChitrapataEngine, buffer: []u8) ![]const u8 {
        return try std.fmt.bufPrint(
            buffer,
            "Chitrapata [{s}]: {d} loop frames @ {d:.1} fps ({d}ms tick) | Opacity: {d:.0}%",
            .{
                self.current_mode.getEnglishName(),
                self.loop_telemetry.total_frames,
                self.loop_telemetry.target_fps,
                self.loop_telemetry.frame_interval_ms,
                self.canvas_opacity * 100.0,
            },
        );
    }
};

test "ChitrapataEngine initialization and state cycle" {
    const allocator = std.testing.allocator;
    var engine = ChitrapataEngine.init(allocator);

    try std.testing.expectEqual(ChitrapataMode.SacredAltarStill, engine.current_mode);
    try std.testing.expectEqual(@as(u32, 239), engine.loop_telemetry.total_frames);
    try std.testing.expectEqual(@as(u32, 41), engine.loop_telemetry.frame_interval_ms); // 1000/24 = 41ms

    const mode2 = engine.cycleMode();
    try std.testing.expectEqual(ChitrapataMode.AnimatedMotionLoop, mode2);
    try std.testing.expectApproxEqAbs(@as(f32, 0.92), engine.canvas_opacity, 0.01);

    const mode3 = engine.cycleMode();
    try std.testing.expectEqual(ChitrapataMode.MinimalObsidianOff, mode3);

    const mode1_again = engine.cycleMode();
    try std.testing.expectEqual(ChitrapataMode.SacredAltarStill, mode1_again);

    var buf: [256]u8 = undefined;
    const report = try engine.getStatusReport(&buf);
    try std.testing.expect(report.len > 0);
}
