const std = @import("std");
const fuzzy = @import("fuzzy.zig");
const shannon = @import("metrics/shannon.zig");
const chisquare = @import("metrics/chisquare.zig");
const density = @import("metrics/density.zig");
const magic_header = @import("metrics/magic_header.zig");
const autocorr = @import("metrics/autocorr.zig");

const kv_delimited = @import("extractors/kv_delimited.zig");
const tlv = @import("extractors/tlv.zig");
const record_table = @import("extractors/record_table.zig");
const hybrid = @import("extractors/hybrid.zig");

pub const MetricChoice = enum {
    Auto,
    ShannonEntropy,
    ChiSquare,
    ByteDensity,
    MagicHeader,
    StrideAutocorr,

    pub fn displayName(self: MetricChoice) []const u8 {
        return switch (self) {
            .Auto => "Auto-Detect [सर्वज्ञ / Omni]",
            .ShannonEntropy => "Shannon Entropy [संशय मान]",
            .ChiSquare => "Chi-Square Test [साम्य परीक्षा]",
            .ByteDensity => "Byte Density & Nulls [घनत्व मान]",
            .MagicHeader => "Magic Signature Sniffer [लक्षण दर्शन]",
            .StrideAutocorr => "Stride Periodicity [आवर्तन परीक्षा]",
        };
    }
};

pub const ExtractorChoice = enum {
    Auto,
    HybridAgama,
    RecordTable,
    KvDelimited,
    BinaryTlv,

    pub fn displayName(self: ExtractorChoice) []const u8 {
        return switch (self) {
            .Auto => "Auto Heuristic [स्वयंसिद्ध]",
            .HybridAgama => "Agama Hybrid [आगम सम्मिश्र]",
            .RecordTable => "Binary Record Table [अभिलेख सारणी]",
            .KvDelimited => "Delimited Key-Value [परिसीमित तत्त्व]",
            .BinaryTlv => "Binary TLV [दैर्घ्य संपुट]",
        };
    }
};

pub const MetricAnalysisReport = struct {
    metric: MetricChoice,
    score_display: [64]u8,
    score_len: usize,
    verdict_display: [64]u8,
    verdict_len: usize,
    container: magic_header.ContainerType,
    stride: usize,

    pub fn getScore(self: *const MetricAnalysisReport) []const u8 {
        return self.score_display[0..self.score_len];
    }

    pub fn getVerdict(self: *const MetricAnalysisReport) []const u8 {
        return self.verdict_display[0..self.verdict_len];
    }
};

pub const SwitchingEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SwitchingEngine {
        return SwitchingEngine{ .allocator = allocator };
    }

    /// Evaluates the save buffer with the chosen metric and produces the analysis report
    pub fn evaluateMetric(self: *SwitchingEngine, choice: MetricChoice, buffer: []const u8) MetricAnalysisReport {
        _ = self;
        var report = MetricAnalysisReport{
            .metric = choice,
            .score_display = @splat(0),
            .score_len = 0,
            .verdict_display = @splat(0),
            .verdict_len = 0,
            .container = magic_header.detectMagicHeader(buffer),
            .stride = 0,
        };

        const effective_metric = if (choice == .Auto) MetricChoice.ShannonEntropy else choice;

        switch (effective_metric) {
            .ShannonEntropy, .Auto => {
                const h = shannon.calculateShannonEntropy(buffer);
                const class = shannon.classifyEntropy(h);
                const score_str = std.fmt.bufPrint(&report.score_display, "{d:.3} bits/byte", .{h}) catch "ERR";
                report.score_len = score_str.len;

                const verdict_str = switch (class) {
                    .SparseOrText => "SparseOrText (शुद्ध पाठ/रिक्त)",
                    .StructuredBinary => "StructuredBinary (प्रपत्र द्वि-आधारी)",
                    .CompressedOrEncrypted => "CompressedOrEncrypted (संकोच/गूढ़)",
                };
                const v_len = @min(verdict_str.len, 64);
                @memcpy(report.verdict_display[0..v_len], verdict_str[0..v_len]);
                report.verdict_len = v_len;
            },
            .ChiSquare => {
                const chi = chisquare.calculateChiSquare(buffer);
                const class = chisquare.classifyChiSquare(chi, buffer.len);
                const score_str = std.fmt.bufPrint(&report.score_display, "χ² = {d:.1}", .{chi}) catch "ERR";
                report.score_len = score_str.len;

                const verdict_str = switch (class) {
                    .UniformRandomOrEncrypted => "UniformRandom (गूढ़ या संकुचित)",
                    .StructuredBinary => "StructuredBinary (प्रपत्र)",
                    .HighlyStructuredOrText => "HighlyStructured (अत्यन्त व्यवस्थित)",
                };
                const v_len = @min(verdict_str.len, 64);
                @memcpy(report.verdict_display[0..v_len], verdict_str[0..v_len]);
                report.verdict_len = v_len;
            },
            .ByteDensity => {
                const profile = density.analyzeByteDensity(buffer);
                const score_str = std.fmt.bufPrint(&report.score_display, "Ascii:{d:.0}% Null:{d:.0}%", .{
                    profile.ascii_ratio * 100.0,
                    profile.null_ratio * 100.0,
                }) catch "ERR";
                report.score_len = score_str.len;

                const verdict_str = switch (profile.format_verdict) {
                    .PureTextKV => "PureTextKV (JSON/XML/INI)",
                    .PaddedBinaryStruct => "PaddedStruct (संतुलित संरचना)",
                    .HighDensityBinary => "PackedBinary (सघन द्वि-आधारी)",
                    .EncryptedOrCompressed => "Encrypted/Packed (गुप्त संपुट)",
                    .SparseBuffer => "SparseZeroPadded (रिक्त बाहुल्य)",
                };
                const v_len = @min(verdict_str.len, 64);
                @memcpy(report.verdict_display[0..v_len], verdict_str[0..v_len]);
                report.verdict_len = v_len;
            },
            .MagicHeader => {
                const container = magic_header.detectMagicHeader(buffer);
                report.container = container;
                const d_name = container.displayName();
                const score_str = std.fmt.bufPrint(&report.score_display, "Sig: {s}", .{d_name}) catch "ERR";
                report.score_len = score_str.len;

                const v_len = @min(d_name.len, 64);
                @memcpy(report.verdict_display[0..v_len], d_name[0..v_len]);
                report.verdict_len = v_len;
            },
            .StrideAutocorr => {
                const stride_info = autocorr.detectStridePeriodicity(buffer);
                report.stride = stride_info.detected_stride;
                const score_str = if (stride_info.detected_stride > 0)
                    std.fmt.bufPrint(&report.score_display, "Stride: {d}B ({d:.0}%)", .{
                        stride_info.detected_stride,
                        stride_info.confidence * 100.0,
                    }) catch "ERR"
                else
                    std.fmt.bufPrint(&report.score_display, "No Periodic Stride", .{}) catch "ERR";
                report.score_len = score_str.len;

                const verdict_str = if (stride_info.detected_stride > 0)
                    "RepeatingStructArray (आवृत्त सारणी)"
                else
                    "Aperiodic (अनियमित)";
                const v_len = @min(verdict_str.len, 64);
                @memcpy(report.verdict_display[0..v_len], verdict_str[0..v_len]);
                report.verdict_len = v_len;
            },
        }

        return report;
    }

    /// Executes field extraction according to selected or auto-detected extractor strategy
    pub fn extractFields(
        self: *SwitchingEngine,
        extractor_choice: ExtractorChoice,
        buffer: []const u8,
        filename: []const u8,
    ) !std.ArrayList(fuzzy.InferredField) {
        var effective_choice = extractor_choice;

        if (effective_choice == .Auto) {
            const container = magic_header.detectMagicHeader(buffer);
            const dens = density.analyzeByteDensity(buffer);

            if (container == .PlainText or dens.format_verdict == .PureTextKV) {
                effective_choice = .KvDelimited;
            } else if (container == .UnrealEngineGVAS) {
                effective_choice = .BinaryTlv;
            } else {
                effective_choice = .HybridAgama;
            }
        }

        return switch (effective_choice) {
            .HybridAgama, .Auto => {
                var extractor = hybrid.HybridExtractor.init(self.allocator);
                return extractor.extract(buffer, filename);
            },
            .RecordTable => {
                var extractor = record_table.RecordTableExtractor.init(self.allocator);
                return extractor.extract(buffer);
            },
            .KvDelimited => {
                var extractor = kv_delimited.KvDelimitedExtractor.init(self.allocator);
                return extractor.extract(buffer);
            },
            .BinaryTlv => {
                var extractor = tlv.TlvExtractor.init(self.allocator);
                return extractor.extract(buffer);
            },
        };
    }
};

test "SwitchingEngine multi-metric evaluation and auto-extraction" {
    const allocator = std.testing.allocator;
    var engine = SwitchingEngine.init(allocator);

    // Mock save buffer
    var buf: [128]u8 = @splat(0);
    @memcpy(buf[0..4], "HERO");
    std.mem.writeInt(i32, buf[12..16], 9999, .little);

    const report_shannon = engine.evaluateMetric(.ShannonEntropy, &buf);
    try std.testing.expect(report_shannon.score_len > 0);

    const report_density = engine.evaluateMetric(.ByteDensity, &buf);
    try std.testing.expect(report_density.score_len > 0);

    var fields = try engine.extractFields(.Auto, &buf, "test.sav");
    defer fields.deinit(allocator);

    try std.testing.expect(fields.items.len > 0);
}
