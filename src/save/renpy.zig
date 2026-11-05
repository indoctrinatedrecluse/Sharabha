//! ============================================================================
//! SHARABHA (शरभ) — KAVYA SUTRA: REN'PY VISUAL NOVEL SAVE ENGINE (काव्य सूत्र)
//! (काव्य सूत्र // The Formula of the Poem / Story Thread)
//!
//! Ren'Py persists every save slot as:
//!
//!     "Ren'Py Save Game <version>\n"  ||  zlib(pickle.dumps(payload, 2))
//!
//! The pickle stream is a Python stack machine that routinely references game
//! classes (renpy.store objects), tuples, sets and memoised shared references.
//! Re-encoding such a stream from a generic tree is lossy and dangerous, so
//! Kavya Sutra never rebuilds the pickle. Instead it:
//!
//!   1. Inflates the zlib payload,
//!   2. Walks the pickle opcode stream (protocol 0-3, frame-aware reads for 4/5),
//!   3. Records the exact byte offset of every scalar (int / float / bool / str),
//!   4. Splices a re-encoded scalar region back into the *original* byte stream,
//!   5. Re-deflates and verifies the round trip by re-parsing the result.
//!
//! Everything the engine does not understand stays byte-identical, therefore
//! Ren'Py object graphs, rollback logs and store classes survive untouched.
//!
//! Engine ported from the Ren'Py parser of `paradoxie/saveeditor` (MIT), then
//! reworked into an offset-preserving surgical editor as described above.
//! ============================================================================

const std = @import("std");
const flate = std.compress.flate;

pub const HEADER_PREFIX = "Ren'Py Save Game";

/// Maximum nesting depth walked while flattening the pickle graph.
const max_depth: usize = 24;

/// Upper bound on flattened fields so a hostile save cannot exhaust memory.
pub const max_fields: usize = 8192;

pub const RenpyValue = union(enum) {
    Int: i64,
    Float: f64,
    Bool: bool,
    Str: []const u8,

    pub fn typeName(self: RenpyValue) []const u8 {
        return switch (self) {
            .Int => "i64 (Pickle Integer)",
            .Float => "f64 (Pickle Float)",
            .Bool => "bool (Pickle Boolean)",
            .Str => "String (Pickle Text)",
        };
    }

    pub fn typeTag(self: RenpyValue) []const u8 {
        return switch (self) {
            .Int => "RENPY_INT",
            .Float => "RENPY_FLOAT",
            .Bool => "RENPY_BOOL",
            .Str => "RENPY_STR",
        };
    }
};

/// How a scalar is currently encoded inside the pickle opcode stream.
/// Mutations re-encode within the same family so Ren'Py's `str` vs `unicode`
/// distinction (Ren'Py 7 / Python 2 vs Ren'Py 8 / Python 3) is preserved.
pub const RenpyEncoding = enum {
    none,
    binint, // 0x4A + i32 LE
    binint1, // 0x4B + u8
    binint2, // 0x4D + u16 LE
    long1, // 0x8A + len + little-endian two's complement
    long4, // 0x8B + u32 len + little-endian two's complement
    text_int, // "I123\n" / "I01\n" / "I00\n"
    binfloat, // 0x47 + f64 BE
    text_float, // "F1.5\n"
    newbool, // 0x88 NEWTRUE / 0x89 NEWFALSE
    binunicode, // 0x58 + u32 LE len + UTF-8
    short_binunicode, // 0x8C + u8 len + UTF-8
    binunicode8, // 0x8D + u64 LE len + UTF-8
    binstring, // 0x54 + u32 LE len (Python 2 `str`)
    short_binstring, // 0x55 + u8 len (Python 2 `str`)
    text_string, // "S'...'\n"
    text_unicode, // "V...\n"
};

pub const NodeKind = enum { scalar, dict, list, tuple, set, foreign };

const Entry = struct {
    key: []const u8,
    node: *Node,
};

/// A single parsed pickle value. Scalar nodes carry the byte window they were
/// decoded from so serialization can splice a re-encoded region in place.
pub const Node = struct {
    kind: NodeKind = .foreign,
    value: ?RenpyValue = null,
    enc: RenpyEncoding = .none,
    off: usize = 0,
    len: usize = 0,
    entries: std.ArrayList(Entry) = .empty,
    items: std.ArrayList(*Node) = .empty,
    dirty: bool = false,
};

/// A flattened, addressable scalar inside the pickle graph.
pub const RenpyField = struct {
    path: []const u8,
    name: []const u8,
    node: *Node,

    pub fn value(self: RenpyField) RenpyValue {
        return self.node.value orelse RenpyValue{ .Bool = false };
    }

    pub fn typeName(self: RenpyField) []const u8 {
        return (self.node.value orelse RenpyValue{ .Bool = false }).typeName();
    }

    pub fn typeTag(self: RenpyField) []const u8 {
        return (self.node.value orelse RenpyValue{ .Bool = false }).typeTag();
    }
};

pub const ParseError = error{
    NotRenpySave,
    MissingHeaderLine,
    EmptyPayload,
    UnexpectedEof,
    MalformedPickle,
    UnsupportedResize,
    KindMismatch,
    VerificationFailed,
    TooManyFields,
};

// ---------------------------------------------------------------------------
// Container helpers: zlib (RFC 1950) via std.compress.flate
// ---------------------------------------------------------------------------

/// Inflates a zlib stream (2-byte header + deflate body + adler32 footer).
pub fn zlibDecompress(allocator: std.mem.Allocator, compressed: []const u8) ![]u8 {
    if (compressed.len == 0) return ParseError.EmptyPayload;
    var in: std.Io.Reader = .fixed(compressed);
    var decompress: flate.Decompress = .init(&in, .zlib, &.{});
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    _ = try decompress.reader.streamRemaining(&aw.writer);
    return try aw.toOwnedSlice();
}

/// Deflates into a zlib stream, mirroring `zlib.compress(payload, 9)`.
pub fn zlibCompress(allocator: std.mem.Allocator, plain: []const u8) ![]u8 {
    const window = try allocator.alloc(u8, flate.max_window_len * 2);
    defer allocator.free(window);

    var aw: std.Io.Writer.Allocating = try .initCapacity(allocator, plain.len + 1024);
    errdefer aw.deinit();

    var compress: flate.Compress = try .init(&aw.writer, window, .zlib, .level_9);
    try compress.writer.writeAll(plain);
    try compress.finish();
    return try aw.toOwnedSlice();
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// True when the buffer carries the Ren'Py save header line.
pub fn isRenpySave(buffer: []const u8) bool {
    if (buffer.len < HEADER_PREFIX.len + 2) return false;
    if (!std.mem.startsWith(u8, buffer, HEADER_PREFIX)) return false;
    return std.mem.indexOfScalar(u8, buffer[0..@min(buffer.len, 64)], '\n') != null;
}

/// Extracts the header line (inclusive of '\n') and the zlib body offset.
pub const PayloadLocation = struct { header: []const u8, offset: usize };

pub fn locatePayload(buffer: []const u8) !PayloadLocation {
    if (!std.mem.startsWith(u8, buffer, HEADER_PREFIX)) return ParseError.NotRenpySave;
    const nl = std.mem.indexOfScalar(u8, buffer[0..@min(buffer.len, 64)], '\n') orelse return ParseError.MissingHeaderLine;
    if (nl + 1 >= buffer.len) return ParseError.EmptyPayload;
    return .{ .header = buffer[0 .. nl + 1], .offset = nl + 1 };
}

// ---------------------------------------------------------------------------
// Pickle opcode stream parser (protocol 0-5, offset preserving)
// ---------------------------------------------------------------------------

const OP_MARK: u8 = 0x28;
const OP_STOP: u8 = 0x2E;
const OP_POP: u8 = 0x30;
const OP_POP_MARK: u8 = 0x31;
const OP_DUP: u8 = 0x32;
const OP_FLOAT: u8 = 0x46;
const OP_INT: u8 = 0x49;
const OP_BININT: u8 = 0x4A;
const OP_BININT1: u8 = 0x4B;
const OP_LONG: u8 = 0x4C;
const OP_BININT2: u8 = 0x4D;
const OP_NONE: u8 = 0x4E;
const OP_PERSID: u8 = 0x50;
const OP_BINPERSID: u8 = 0x51;
const OP_REDUCE: u8 = 0x52;
const OP_STRING: u8 = 0x53;
const OP_BINSTRING: u8 = 0x54;
const OP_SHORT_BINSTRING: u8 = 0x55;
const OP_UNICODE: u8 = 0x56;
const OP_BINUNICODE: u8 = 0x58;
const OP_APPEND: u8 = 0x61;
const OP_BUILD: u8 = 0x62;
const OP_GLOBAL: u8 = 0x63;
const OP_DICT: u8 = 0x64;
const OP_APPENDS: u8 = 0x65;
const OP_GET: u8 = 0x67;
const OP_BINGET: u8 = 0x68;
const OP_INST: u8 = 0x69;
const OP_LONG_BINGET: u8 = 0x6A;
const OP_LIST: u8 = 0x6C;
const OP_OBJ: u8 = 0x6F;
const OP_PUT: u8 = 0x70;
const OP_BINPUT: u8 = 0x71;
const OP_LONG_BINPUT: u8 = 0x72;
const OP_SETITEM: u8 = 0x73;
const OP_TUPLE: u8 = 0x74;
const OP_SETITEMS: u8 = 0x75;
const OP_EMPTY_LIST: u8 = 0x5D;
const OP_EMPTY_DICT: u8 = 0x7D;
const OP_EMPTY_TUPLE: u8 = 0x29;
const OP_BINFLOAT: u8 = 0x47;
const OP_PROTO: u8 = 0x80;
const OP_NEWOBJ: u8 = 0x81;
const OP_TUPLE1: u8 = 0x85;
const OP_TUPLE2: u8 = 0x86;
const OP_TUPLE3: u8 = 0x87;
const OP_NEWTRUE: u8 = 0x88;
const OP_NEWFALSE: u8 = 0x89;
const OP_LONG1: u8 = 0x8A;
const OP_LONG4: u8 = 0x8B;
const OP_SHORT_BINUNICODE: u8 = 0x8C;
const OP_BINUNICODE8: u8 = 0x8D;
const OP_BINBYTES8: u8 = 0x8E;
const OP_EMPTY_SET: u8 = 0x8F;
const OP_ADDITEMS: u8 = 0x90;
const OP_FROZENSET: u8 = 0x91;
const OP_NEWOBJ_EX: u8 = 0x92;
const OP_STACK_GLOBAL: u8 = 0x93;
const OP_MEMOIZE: u8 = 0x94;
const OP_FRAME: u8 = 0x95;
const OP_BYTEARRAY8: u8 = 0x96;
const OP_BINBYTES: u8 = 0x42;
const OP_SHORT_BINBYTES: u8 = 0x43;

const StackItem = union(enum) {
    mark,
    node: *Node,
};

const PickleParser = struct {
    a: std.mem.Allocator,
    buf: []const u8,
    pos: usize = 0,
    stack: std.ArrayList(StackItem) = .empty,
    memo: std.ArrayList(*Node) = .empty,
    scratch: std.ArrayList(*Node) = .empty,
    roots: std.ArrayList(*Node) = .empty,
    protocol: u8 = 0,
    has_frames: bool = false,

    fn newNode(p: *PickleParser) !*Node {
        const n = try p.a.create(Node);
        n.* = .{};
        return n;
    }

    fn push(p: *PickleParser, n: *Node) !void {
        try p.stack.append(p.a, .{ .node = n });
    }

    fn popNode(p: *PickleParser) !*Node {
        if (p.stack.items.len == 0) return ParseError.MalformedPickle;
        const top = p.stack.items[p.stack.items.len - 1];
        p.stack.items.len -= 1;
        return switch (top) {
            .node => |n| n,
            .mark => ParseError.MalformedPickle,
        };
    }

    fn peekNode(p: *PickleParser) !*Node {
        if (p.stack.items.len == 0) return ParseError.MalformedPickle;
        return switch (p.stack.items[p.stack.items.len - 1]) {
            .node => |n| n,
            .mark => ParseError.MalformedPickle,
        };
    }

    /// Pops every entry above the topmost MARK into `scratch`, in stream order.
    /// The MARK itself is discarded, so the container stays on top of the stack.
    fn popToMark(p: *PickleParser) !void {
        p.scratch.clearRetainingCapacity();
        while (p.stack.items.len > 0) {
            const top = p.stack.items[p.stack.items.len - 1];
            p.stack.items.len -= 1;
            switch (top) {
                .node => |n| try p.scratch.append(p.a, n),
                .mark => {
                    std.mem.reverse(*Node, p.scratch.items);
                    return;
                },
            }
        }
        return ParseError.MalformedPickle;
    }

    fn memoPutAt(p: *PickleParser, idx: usize, n: *Node) !void {
        while (p.memo.items.len <= idx) try p.memo.append(p.a, n);
        p.memo.items[idx] = n;
    }

    fn memoPut(p: *PickleParser, idx: usize) !void {
        const n = try p.peekNode();
        try p.memoPutAt(idx, n);
    }

    fn memoGet(p: *PickleParser, idx: usize) !*Node {
        if (idx >= p.memo.items.len) return ParseError.MalformedPickle;
        return p.memo.items[idx];
    }

    // -- primitive readers --------------------------------------------------

    fn readByte(p: *PickleParser) !u8 {
        if (p.pos >= p.buf.len) return ParseError.UnexpectedEof;
        const b = p.buf[p.pos];
        p.pos += 1;
        return b;
    }

    fn readBytes(p: *PickleParser, n: usize) ![]const u8 {
        if (n > p.buf.len or p.pos + n > p.buf.len) return ParseError.UnexpectedEof;
        const s = p.buf[p.pos .. p.pos + n];
        p.pos += n;
        return s;
    }

    fn readU32le(p: *PickleParser) !u32 {
        const b: *const [4]u8 = (try p.readBytes(4))[0..4];
        return std.mem.readInt(u32, b, .little);
    }

    fn readU64le(p: *PickleParser) !u64 {
        const b: *const [8]u8 = (try p.readBytes(8))[0..8];
        return std.mem.readInt(u64, b, .little);
    }

    /// Reads a newline terminated text token (protocol 0/1 opcodes).
    fn readLine(p: *PickleParser) ![]const u8 {
        const start = p.pos;
        while (p.pos < p.buf.len) : (p.pos += 1) {
            if (p.buf[p.pos] == '\n') {
                const line = p.buf[start..p.pos];
                p.pos += 1;
                return line;
            }
        }
        return ParseError.UnexpectedEof;
    }

    // -- scalar constructors ------------------------------------------------

    fn pushScalar(p: *PickleParser, value: RenpyValue, enc: RenpyEncoding, off: usize, len: usize) !*Node {
        const n = try p.newNode();
        n.kind = .scalar;
        n.value = value;
        n.enc = enc;
        n.off = off;
        n.len = len;
        try p.push(n);
        return n;
    }

    fn pushOpaque(p: *PickleParser) !*Node {
        const n = try p.newNode();
        n.kind = .foreign;
        try p.push(n);
        return n;
    }

    /// Builds a container node from everything above the last MARK.
    fn buildContainer(p: *PickleParser, kind: NodeKind) !*Node {
        try p.popToMark();
        const n = try p.newNode();
        n.kind = kind;
        switch (kind) {
            .dict => try p.fillDict(n),
            else => try n.items.appendSlice(p.a, p.scratch.items),
        }
        try p.push(n);
        return n;
    }

    /// Appends MARK separated items to the container already on the stack.
    fn appendToContainer(p: *PickleParser, pairs: bool) !void {
        try p.popToMark();
        const container = try p.peekNode();
        if (container.kind == .scalar) return ParseError.KindMismatch;
        if (pairs) {
            try p.fillDict(container);
        } else {
            try container.items.appendSlice(p.a, p.scratch.items);
        }
    }

    fn fillDict(p: *PickleParser, n: *Node) !void {
        var i: usize = 0;
        while (i + 1 < p.scratch.items.len) : (i += 2) {
            const key = try keyOf(p, p.scratch.items[i], i / 2);
            try n.entries.append(p.a, .{ .key = key, .node = p.scratch.items[i + 1] });
        }
    }

};

// ---------------------------------------------------------------------------
// Scalar codec helpers (shared by the parser and the encoder)
// ---------------------------------------------------------------------------

/// Decodes a little-endian two's complement integer of arbitrary width,
/// saturating at the i64 range (Ren'Py uses LONG1 for small ints only).
fn decodeLittleInt(bytes: []const u8) i64 {
    if (bytes.len == 0) return 0;
    const n = @min(bytes.len, 8);
    var acc: u64 = 0;
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        acc = (acc << 8) | @as(u64, bytes[i]);
    }
    if (bytes.len >= 8) return @bitCast(acc);
    const negative = (bytes[bytes.len - 1] & 0x80) != 0;
    if (!negative) return @intCast(acc);
    const bits: u6 = @intCast(n * 8);
    const mask: u64 = (@as(u64, 1) << bits) - 1;
    return @bitCast(acc | ~mask);
}

/// Minimal little-endian two's complement encoding, shortest form (1..8 bytes).
fn encodeLittleInt(buf: *[8]u8, value: i64) usize {
    var len: usize = 1;
    while (len < 8) : (len += 1) {
        const bits: u6 = @intCast(len * 8);
        const min: i64 = -(@as(i64, 1) << @intCast(bits - 1));
        const max: i64 = (@as(i64, 1) << @intCast(bits - 1)) - 1;
        if (value >= min and value <= max) break;
    }
    const raw: u64 = @bitCast(value);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        buf[i] = @truncate(raw >> @intCast(i * 8));
    }
    return len;
}

fn parseInt64(text: []const u8) !i64 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return ParseError.MalformedPickle;
    if (std.mem.eql(u8, trimmed, "True")) return 1;
    if (std.mem.eql(u8, trimmed, "False")) return 0;
    return std.fmt.parseInt(i64, trimmed, 10);
}

fn stripQuote(raw: []const u8) []const u8 {
    if (raw.len >= 2 and (raw[0] == '\'' or raw[0] == '"') and raw[raw.len - 1] == raw[0]) {
        return raw[1 .. raw.len - 1];
    }
    return raw;
}


/// Dispatches a single opcode. `op_off` is the offset of the opcode byte.
fn step(p: *PickleParser, op: u8, op_off: usize) !void {
    switch (op) {
        OP_PROTO => p.protocol = try p.readByte(),
        OP_FRAME => {
            _ = try p.readU64le();
            p.has_frames = true;
        },
        OP_MARK => try p.stack.append(p.a, .mark),
        OP_POP => {
            if (p.stack.items.len == 0) return ParseError.MalformedPickle;
            p.stack.items.len -= 1;
        },
        OP_POP_MARK => try p.popToMark(),
        OP_DUP => {
            const n = try p.peekNode();
            try p.push(n);
        },
        OP_NONE => _ = try p.pushOpaque(),
        OP_NEWTRUE, OP_NEWFALSE => {
            _ = try p.pushScalar(.{ .Bool = op == OP_NEWTRUE }, .newbool, op_off, 1);
        },
        OP_BININT => {
            const v: i32 = @bitCast(try p.readU32le());
            _ = try p.pushScalar(.{ .Int = v }, .binint, op_off, p.pos - op_off);
        },
        OP_BININT1 => {
            const v = try p.readByte();
            _ = try p.pushScalar(.{ .Int = @intCast(v) }, .binint1, op_off, p.pos - op_off);
        },
        OP_BININT2 => {
            const b: *const [2]u8 = (try p.readBytes(2))[0..2];
            const v = std.mem.readInt(u16, b, .little);
            _ = try p.pushScalar(.{ .Int = @intCast(v) }, .binint2, op_off, p.pos - op_off);
        },
        OP_LONG1 => {
            const n = try p.readByte();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Int = decodeLittleInt(raw) }, .long1, op_off, p.pos - op_off);
        },
        OP_LONG4 => {
            const n = try p.readU32le();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Int = decodeLittleInt(raw) }, .long4, op_off, p.pos - op_off);
        },
        OP_INT => {
            const line = try p.readLine();
            if (std.mem.eql(u8, line, "01")) {
                _ = try p.pushScalar(.{ .Bool = true }, .text_int, op_off, p.pos - op_off);
            } else if (std.mem.eql(u8, line, "00")) {
                _ = try p.pushScalar(.{ .Bool = false }, .text_int, op_off, p.pos - op_off);
            } else {
                _ = try p.pushScalar(.{ .Int = try parseInt64(line) }, .text_int, op_off, p.pos - op_off);
            }
        },
        OP_LONG => {
            var line = try p.readLine();
            if (line.len > 0 and (line[line.len - 1] == 'L' or line[line.len - 1] == 'l')) line = line[0 .. line.len - 1];
            _ = try p.pushScalar(.{ .Int = try parseInt64(line) }, .text_int, op_off, p.pos - op_off);
        },
        OP_BINFLOAT => {
            const b: *const [8]u8 = (try p.readBytes(8))[0..8];
            const bits = std.mem.readInt(u64, b, .big);
            _ = try p.pushScalar(.{ .Float = @bitCast(bits) }, .binfloat, op_off, p.pos - op_off);
        },
        OP_FLOAT => {
            const line = try p.readLine();
            const v = std.fmt.parseFloat(f64, std.mem.trim(u8, line, " \t")) catch 0.0;
            _ = try p.pushScalar(.{ .Float = v }, .text_float, op_off, p.pos - op_off);
        },
        OP_BINUNICODE => {
            const n = try p.readU32le();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Str = raw }, .binunicode, op_off, p.pos - op_off);
        },
        OP_SHORT_BINUNICODE => {
            const n = try p.readByte();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Str = raw }, .short_binunicode, op_off, p.pos - op_off);
        },
        OP_BINUNICODE8 => {
            const n = try p.readU64le();
            if (n > p.buf.len) return ParseError.UnexpectedEof;
            const raw = try p.readBytes(@intCast(n));
            _ = try p.pushScalar(.{ .Str = raw }, .binunicode8, op_off, p.pos - op_off);
        },
        OP_BINSTRING => {
            const n = try p.readU32le();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Str = raw }, .binstring, op_off, p.pos - op_off);
        },
        OP_SHORT_BINSTRING => {
            const n = try p.readByte();
            const raw = try p.readBytes(n);
            _ = try p.pushScalar(.{ .Str = raw }, .short_binstring, op_off, p.pos - op_off);
        },
        OP_STRING, OP_UNICODE => {
            const raw = try p.readLine();
            // Protocol 0 strings are quoted (`S'...'` / `V...`); strip the quotes.
            const enc: RenpyEncoding = if (op == OP_STRING) .text_string else .text_unicode;
            _ = try p.pushScalar(.{ .Str = stripQuote(raw) }, enc, op_off, p.pos - op_off);
        },
        else => try stepComposite(p, op),
    }
}

/// Copies the reachable contents of `src` onto `dst` so opaque wrappers such as
/// REDUCE / BUILD / NEWOBJ stay transparent while flattening.
fn attachContents(a: std.mem.Allocator, dst: *Node, src: *const Node) !void {
    if (src.entries.items.len == 0 and src.items.items.len == 0) return;
    try dst.entries.appendSlice(a, src.entries.items);
    try dst.items.appendSlice(a, src.items.items);
}

fn pushEmptyContainer(p: *PickleParser, kind: NodeKind) !void {
    const n = try p.newNode();
    n.kind = kind;
    try p.push(n);
}

fn pushOpaqueFrom(p: *PickleParser, src: *const Node) !void {
    const n = try p.newNode();
    n.kind = .foreign;
    try attachContents(p.a, n, src);
    try p.push(n);
}

fn pushOpaqueFromMany(p: *PickleParser, nodes: []const *Node) !void {
    const n = try p.newNode();
    n.kind = .foreign;
    for (nodes) |src| try attachContents(p.a, n, src);
    try p.push(n);
}

fn keyOf(p: *PickleParser, key_node: *Node, index: usize) ![]const u8 {
    const v = key_node.value orelse return std.fmt.allocPrint(p.a, "[key{d}]", .{index});
    return switch (v) {
        .Str => |s| s,
        .Int => |i| try std.fmt.allocPrint(p.a, "{d}", .{i}),
        .Bool => |b| if (b) "True" else "False",
        .Float => |f| try std.fmt.allocPrint(p.a, "{d}", .{f}),
    };
}

fn pushTupleOf(p: *PickleParser, count: usize) !void {
    const n = try p.newNode();
    n.kind = .tuple;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try p.popNode();
        try n.items.append(p.a, item);
    }
    std.mem.reverse(*Node, n.items.items);
    try p.push(n);
}

/// Handles container / reference / object opcodes.
fn stepComposite(p: *PickleParser, op: u8) !void {
    switch (op) {
        OP_EMPTY_DICT => try pushEmptyContainer(p, .dict),
        OP_EMPTY_LIST => try pushEmptyContainer(p, .list),
        OP_EMPTY_TUPLE => try pushEmptyContainer(p, .tuple),
        OP_EMPTY_SET => try pushEmptyContainer(p, .set),
        OP_DICT => _ = try p.buildContainer(.dict),
        OP_LIST => _ = try p.buildContainer(.list),
        OP_TUPLE => _ = try p.buildContainer(.tuple),
        OP_FROZENSET => _ = try p.buildContainer(.set),
        OP_TUPLE1 => try pushTupleOf(p, 1),
        OP_TUPLE2 => try pushTupleOf(p, 2),
        OP_TUPLE3 => try pushTupleOf(p, 3),
        OP_SETITEM => {
            const value = try p.popNode();
            const key_node = try p.popNode();
            const container = try p.peekNode();
            const key = try keyOf(p, key_node, container.entries.items.len);
            try container.entries.append(p.a, .{ .key = key, .node = value });
        },
        OP_SETITEMS => try p.appendToContainer(true),
        OP_APPEND => {
            const value = try p.popNode();
            const container = try p.peekNode();
            try container.items.append(p.a, value);
        },
        OP_APPENDS, OP_ADDITEMS => try p.appendToContainer(false),
        OP_BINPUT => try p.memoPut(try p.readByte()),
        OP_LONG_BINPUT => try p.memoPut(try p.readU32le()),
        OP_MEMOIZE => {
            const idx = p.memo.items.len;
            try p.memoPut(idx);
        },
        OP_PUT => {
            const line = try p.readLine();
            const idx = std.fmt.parseInt(usize, std.mem.trim(u8, line, " \t"), 10) catch return ParseError.MalformedPickle;
            try p.memoPut(idx);
        },
        OP_BINGET => {
            const n = try p.memoGet(try p.readByte());
            try p.push(n);
        },
        OP_LONG_BINGET => {
            const n = try p.memoGet(try p.readU32le());
            try p.push(n);
        },
        OP_GET => {
            const line = try p.readLine();
            const idx = std.fmt.parseInt(usize, std.mem.trim(u8, line, " \t"), 10) catch return ParseError.MalformedPickle;
            const n = try p.memoGet(idx);
            try p.push(n);
        },
        OP_GLOBAL => {
            _ = try p.readLine();
            _ = try p.readLine();
            _ = try p.pushOpaque();
        },
        OP_STACK_GLOBAL => {
            _ = try p.popNode();
            _ = try p.popNode();
            _ = try p.pushOpaque();
        },
        OP_REDUCE => {
            const args = try p.popNode();
            _ = try p.popNode();
            try pushOpaqueFrom(p, args);
        },
        OP_BUILD => {
            const state = try p.popNode();
            const instance = try p.peekNode();
            try attachContents(p.a, instance, state);
        },
        OP_NEWOBJ => {
            const args = try p.popNode();
            _ = try p.popNode();
            try pushOpaqueFrom(p, args);
        },
        OP_NEWOBJ_EX => {
            const kwargs = try p.popNode();
            const args = try p.popNode();
            _ = try p.popNode();
            const pair = [_]*Node{ args, kwargs };
            try pushOpaqueFromMany(p, &pair);
        },
        OP_OBJ, OP_INST => {
            try p.popToMark();
            const nodes = p.scratch.items;
            try pushOpaqueFromMany(p, nodes);
            if (op == OP_INST) {
                _ = try p.readLine();
                _ = try p.readLine();
            }
        },
        OP_PERSID => {
            _ = try p.readLine();
            _ = try p.pushOpaque();
        },
        OP_BINPERSID => {
            _ = try p.popNode();
            _ = try p.pushOpaque();
        },
        0x82, 0x83, 0x84 => { // EXT1 / EXT2 / EXT4
            const n: usize = switch (op) {
                0x82 => 1,
                0x83 => 2,
                else => 4,
            };
            _ = try p.readBytes(n);
            _ = try p.pushOpaque();
        },
        OP_SHORT_BINBYTES => {
            const n = try p.readByte();
            _ = try p.readBytes(n);
            _ = try p.pushOpaque();
        },
        OP_BINBYTES => {
            const n = try p.readU32le();
            _ = try p.readBytes(n);
            _ = try p.pushOpaque();
        },
        OP_BINBYTES8, OP_BYTEARRAY8 => {
            const n = try p.readU64le();
            if (n > p.buf.len) return ParseError.UnexpectedEof;
            _ = try p.readBytes(@intCast(n));
            _ = try p.pushOpaque();
        },
        0x97, 0x98 => { // NEXT_BUFFER / READONLY_BUFFER
            const n = try p.popNode();
            try p.push(n);
        },
        else => return ParseError.MalformedPickle,
    }
}

/// Parses a whole pickle stream, leaving every top-level object in `roots`.
fn parseStream(p: *PickleParser) !void {
    while (p.pos < p.buf.len) {
        const op_off = p.pos;
        const op = p.buf[p.pos];
        p.pos += 1;
        if (op == OP_STOP) break;
        try step(p, op, op_off);
    }
    while (p.stack.items.len > 0) {
        const top = p.stack.items[p.stack.items.len - 1];
        p.stack.items.len -= 1;
        switch (top) {
            .node => |n| try p.roots.append(p.a, n),
            .mark => {},
        }
    }
    if (p.roots.items.len == 0) return ParseError.MalformedPickle;
    std.mem.reverse(*Node, p.roots.items);
}

// ---------------------------------------------------------------------------
// RenpySave — public save document
// ---------------------------------------------------------------------------

pub const RenpySave = struct {
    child_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    /// Header line, e.g. "Ren'Py Save Game 8.2.3\n" (arena owned).
    header: []const u8,
    /// Inflated pickle bytes (arena owned). Scalar offsets index into this.
    inflated: []const u8,
    /// Verbatim copy of the source `.save` file (child allocator).
    source: []u8,
    roots: std.ArrayList(*Node) = .empty,
    fields: std.ArrayList(RenpyField) = .empty,
    protocol: u8 = 0,
    has_frames: bool = false,
    fields_truncated: bool = false,

    pub fn parse(child_allocator: std.mem.Allocator, buffer: []const u8) !RenpySave {
        const loc = try locatePayload(buffer);
        var arena: std.heap.ArenaAllocator = .init(child_allocator);
        var arena_owned = true;
        errdefer if (arena_owned) arena.deinit();
        const a = arena.allocator();

        const inflated = try zlibDecompress(a, buffer[loc.offset..]);

        var parser: PickleParser = .{ .a = a, .buf = inflated };
        try parseStream(&parser);

        const owned_header = try a.dupe(u8, loc.header);
        const owned_source = try child_allocator.dupe(u8, buffer);

        var save: RenpySave = .{
            .child_allocator = child_allocator,
            .arena = arena,
            .header = owned_header,
            .inflated = inflated,
            .source = owned_source,
            .roots = parser.roots,
            .protocol = parser.protocol,
            .has_frames = parser.has_frames,
        };
        arena_owned = false;
        errdefer save.deinit();
        try save.flatten();
        return save;
    }

    pub fn deinit(self: *RenpySave) void {
        self.child_allocator.free(self.source);
        self.arena.deinit();
    }

    /// Ren'Py version string carried by the header, e.g. "8.2.3".
    pub fn renpyVersion(self: *const RenpySave) []const u8 {
        var body = self.header;
        if (std.mem.startsWith(u8, body, HEADER_PREFIX)) body = body[HEADER_PREFIX.len..];
        return std.mem.trim(u8, body, " \t\r\n");
    }

    pub fn findField(self: *RenpySave, path: []const u8) ?*RenpyField {
        for (self.fields.items) |*f| {
            if (std.mem.eql(u8, f.path, path)) return f;
        }
        for (self.fields.items) |*f| {
            if (std.mem.eql(u8, f.name, path)) return f;
        }
        return null;
    }

    pub fn countScalars(self: *const RenpySave) usize {
        return self.fields.items.len;
    }

    pub fn getInt(self: *const RenpySave, path: []const u8) ?i64 {
        for (self.fields.items) |f| {
            if (std.mem.eql(u8, f.path, path) or std.mem.eql(u8, f.name, path)) {
                return switch (f.value()) {
                    .Int => |v| v,
                    .Bool => |b| if (b) 1 else 0,
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getFloat(self: *const RenpySave, path: []const u8) ?f64 {
        for (self.fields.items) |f| {
            if (std.mem.eql(u8, f.path, path) or std.mem.eql(u8, f.name, path)) {
                return switch (f.value()) {
                    .Float => |v| v,
                    .Int => |v| @floatFromInt(v),
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getBool(self: *const RenpySave, path: []const u8) ?bool {
        for (self.fields.items) |f| {
            if (std.mem.eql(u8, f.path, path) or std.mem.eql(u8, f.name, path)) {
                return switch (f.value()) {
                    .Bool => |v| v,
                    .Int => |v| v != 0,
                    else => null,
                };
            }
        }
        return null;
    }

    pub fn getString(self: *const RenpySave, path: []const u8) ?[]const u8 {
        for (self.fields.items) |f| {
            if (std.mem.eql(u8, f.path, path) or std.mem.eql(u8, f.name, path)) {
                return switch (f.value()) {
                    .Str => |v| v,
                    else => null,
                };
            }
        }
        return null;
    }

    // -- mutation ----------------------------------------------------------

    pub fn setInt(self: *RenpySave, path: []const u8, value: i64) bool {
        const f = self.findField(path) orelse return false;
        f.node.value = .{ .Int = value };
        f.node.dirty = true;
        return true;
    }

    pub fn setFloat(self: *RenpySave, path: []const u8, value: f64) bool {
        const f = self.findField(path) orelse return false;
        f.node.value = .{ .Float = value };
        f.node.dirty = true;
        return true;
    }

    pub fn setBool(self: *RenpySave, path: []const u8, value: bool) bool {
        const f = self.findField(path) orelse return false;
        f.node.value = .{ .Bool = value };
        f.node.dirty = true;
        return true;
    }

    pub fn setString(self: *RenpySave, path: []const u8, value: []const u8) bool {
        const f = self.findField(path) orelse return false;
        const owned = self.arena.allocator().dupe(u8, value) catch return false;
        f.node.value = .{ .Str = owned };
        f.node.dirty = true;
        return true;
    }

    /// Applies a text edit, coercing to the field's existing scalar type.
    pub fn applyEdit(self: *RenpySave, path: []const u8, text: []const u8) !void {
        const f = self.findField(path) orelse return ParseError.KindMismatch;
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        switch (f.value()) {
            .Int => {
                const v = std.fmt.parseInt(i64, trimmed, 10) catch return ParseError.KindMismatch;
                f.node.value = .{ .Int = v };
            },
            .Float => {
                const v = std.fmt.parseFloat(f64, trimmed) catch return ParseError.KindMismatch;
                f.node.value = .{ .Float = v };
            },
            .Bool => {
                const v = parseBoolText(trimmed) orelse return ParseError.KindMismatch;
                f.node.value = .{ .Bool = v };
            },
            .Str => {
                f.node.value = .{ .Str = try self.arena.allocator().dupe(u8, text) };
            },
        }
        f.node.dirty = true;
    }

    pub fn hasEdits(self: *const RenpySave) bool {
        for (self.fields.items) |f| {
            if (f.node.dirty) return true;
        }
        return false;
    }

    // -- graph flattening --------------------------------------------------

    fn flatten(self: *RenpySave) !void {
        var visiting: std.ArrayList(*Node) = .empty;
        defer visiting.deinit(self.child_allocator);
        const a = self.arena.allocator();
        for (self.roots.items, 0..) |root, i| {
            const prefix: []const u8 = if (self.roots.items.len == 1)
                ""
            else
                try std.fmt.allocPrint(a, "root[{d}]", .{i});
            try self.walk(root, prefix, 0, &visiting);
        }
    }

    fn walk(self: *RenpySave, node: *Node, path: []const u8, depth: usize, visiting: *std.ArrayList(*Node)) !void {
        if (depth > max_depth) return;
        if (self.fields.items.len >= max_fields) {
            self.fields_truncated = true;
            return;
        }
        for (visiting.items) |seen| {
            if (seen == node) return; // cycle guard (pickle memo can encode cycles)
        }
        const a = self.arena.allocator();
        switch (node.kind) {
            .scalar => {
                if (node.value == null) return;
                const full = if (path.len == 0) try a.dupe(u8, "root") else path;
                try self.fields.append(a, .{ .path = full, .name = lastSegment(full), .node = node });
            },
            .dict, .foreign => {
                try visiting.append(self.child_allocator, node);
                defer _ = visiting.pop();
                for (node.entries.items) |e| {
                    const child_path = try joinPath(a, path, e.key);
                    try self.walk(e.node, child_path, depth + 1, visiting);
                }
                for (node.items.items, 0..) |child, i| {
                    const child_path = try indexPath(a, path, i);
                    try self.walk(child, child_path, depth + 1, visiting);
                }
            },
            .list, .tuple, .set => {
                try visiting.append(self.child_allocator, node);
                defer _ = visiting.pop();
                for (node.items.items, 0..) |child, i| {
                    const child_path = try indexPath(a, path, i);
                    try self.walk(child, child_path, depth + 1, visiting);
                }
            },
        }
    }

    // -- serialization -----------------------------------------------------

    /// Splices edited scalars back into the original pickle and re-deflates it.
    /// The candidate is verified (zlib round trip, structural re-parse and
    /// value read-back at the spliced offsets) before it is returned.
    pub fn serialize(self: *RenpySave, allocator: std.mem.Allocator) ![]u8 {
        var tmp: std.heap.ArenaAllocator = .init(allocator);
        defer tmp.deinit();
        const a = tmp.allocator();

        var dirty: std.ArrayList(*Node) = .empty;
        var visiting: std.ArrayList(*Node) = .empty;
        for (self.roots.items) |root| try collectDirty(a, root, &dirty, &visiting);
        if (dirty.items.len == 0) return allocator.dupe(u8, self.source);

        std.mem.sort(*Node, dirty.items, {}, lessByOffset);

        var plain: std.ArrayList(u8) = .empty;
        try plain.ensureTotalCapacity(a, self.inflated.len + 512);
        var new_offsets: std.ArrayList(usize) = .empty;
        var encoded: std.ArrayList(u8) = .empty;

        var cursor: usize = 0;
        for (dirty.items) |node| {
            if (node.off < cursor or node.off + node.len > self.inflated.len) return ParseError.UnsupportedResize;
            try plain.appendSlice(a, self.inflated[cursor..node.off]);
            try new_offsets.append(a, plain.items.len);
            encoded.clearRetainingCapacity();
            try encodeScalar(&encoded, a, node);
            try plain.appendSlice(a, encoded.items);
            cursor = node.off + node.len;
        }
        try plain.appendSlice(a, self.inflated[cursor..]);

        const compressed = try zlibCompress(a, plain.items);

        // 1. the zlib round trip must reproduce the exact spliced pickle bytes
        const recheck = try zlibDecompress(a, compressed);
        if (!std.mem.eql(u8, recheck, plain.items)) return ParseError.VerificationFailed;

        // 2. the edited stream must still walk as a valid pickle
        var varena: std.heap.ArenaAllocator = .init(a);
        defer varena.deinit();
        var vp: PickleParser = .{ .a = varena.allocator(), .buf = recheck };
        try parseStream(&vp);

        // 3. every edit must read back with the intended value
        for (dirty.items, 0..) |node, i| {
            const dec = decodeScalarAt(recheck, new_offsets.items[i]) catch return ParseError.VerificationFailed;
            if (!valueEql(dec.value, node.value.?)) return ParseError.VerificationFailed;
        }

        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(a, self.header);
        try out.appendSlice(a, compressed);
        return allocator.dupe(u8, out.items);
    }
};

// ---------------------------------------------------------------------------
// Paths, dirty collection and value helpers
// ---------------------------------------------------------------------------

fn parseBoolText(text: []const u8) ?bool {
    if (text.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(text, "true") or std.mem.eql(u8, text, "1")) return true;
    if (std.ascii.eqlIgnoreCase(text, "false") or std.mem.eql(u8, text, "0")) return false;
    return null;
}

fn lastSegment(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| {
        if (dot + 1 < path.len) return path[dot + 1 ..];
    }
    return path;
}

fn joinPath(a: std.mem.Allocator, path: []const u8, key: []const u8) ![]const u8 {
    if (path.len == 0) return key;
    if (key.len == 0) return path;
    return std.fmt.allocPrint(a, "{s}.{s}", .{ path, key });
}

fn indexPath(a: std.mem.Allocator, path: []const u8, index: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}[{d}]", .{ path, index });
}

fn lessByOffset(_: void, lhs: *Node, rhs: *Node) bool {
    return lhs.off < rhs.off;
}

fn collectDirty(a: std.mem.Allocator, node: *Node, out: *std.ArrayList(*Node), visiting: *std.ArrayList(*Node)) !void {
    for (out.items) |seen| {
        if (seen == node) return;
    }
    for (visiting.items) |seen| {
        if (seen == node) return; // cycle guard
    }
    try visiting.append(a, node);
    defer _ = visiting.pop();

    if (node.dirty) try out.append(a, node);
    for (node.entries.items) |e| try collectDirty(a, e.node, out, visiting);
    for (node.items.items) |child| try collectDirty(a, child, out, visiting);
}

fn valueEql(lhs: RenpyValue, rhs: RenpyValue) bool {
    return switch (lhs) {
        .Int => |v| switch (rhs) {
            .Int => |w| v == w,
            else => false,
        },
        .Float => |v| switch (rhs) {
            .Float => |w| v == w or (std.math.isNan(v) and std.math.isNan(w)),
            else => false,
        },
        .Bool => |v| switch (rhs) {
            .Bool => |w| v == w,
            else => false,
        },
        .Str => |v| switch (rhs) {
            .Str => |w| std.mem.eql(u8, v, w),
            else => false,
        },
    };
}

/// Parses a Ren'Py `.save` file into a heap allocated document.
pub fn parseRenpySave(allocator: std.mem.Allocator, buffer: []const u8) !*RenpySave {
    const save = try allocator.create(RenpySave);
    errdefer allocator.destroy(save);
    save.* = try RenpySave.parse(allocator, buffer);
    return save;
}

/// Convenience: inflate the payload only (used by dialogs / diagnostics).
pub fn inflatePayload(allocator: std.mem.Allocator, buffer: []const u8) ![]u8 {
    const loc = try locatePayload(buffer);
    return zlibDecompress(allocator, buffer[loc.offset..]);
}

// ---------------------------------------------------------------------------
// Scalar encoding / decoding (offset splices)
// ---------------------------------------------------------------------------

fn appendU32le(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, value, .little);
    try out.appendSlice(a, &b);
}

fn appendU64le(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) !void {
    var b: [8]u8 = undefined;
    std.mem.writeInt(u64, &b, value, .little);
    try out.appendSlice(a, &b);
}

fn encodeInt(out: *std.ArrayList(u8), a: std.mem.Allocator, enc: RenpyEncoding, value: i64) !void {
    switch (enc) {
        .binint1 => if (value >= 0 and value <= 0xFF) {
            try out.append(a, OP_BININT1);
            try out.append(a, @intCast(value));
            return;
        },
        .binint2 => if (value >= 0 and value <= 0xFFFF) {
            try out.append(a, OP_BININT2);
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, @intCast(value), .little);
            try out.appendSlice(a, &b);
            return;
        },
        .binint => if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
            try out.append(a, OP_BININT);
            const narrowed: i32 = @intCast(value);
            try appendU32le(out, a, @bitCast(narrowed));
            return;
        },
        .text_int => {
            var tmp: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&tmp, "I{d}\n", .{value});
            try out.appendSlice(a, text);
            return;
        },
        else => {},
    }
    // Promotion path: LONG1 (shortest two's complement, at most 8 bytes).
    var payload: [8]u8 = undefined;
    const n = encodeLittleInt(&payload, value);
    try out.append(a, OP_LONG1);
    try out.append(a, @intCast(n));
    try out.appendSlice(a, payload[0..n]);
}

fn encodeString(out: *std.ArrayList(u8), a: std.mem.Allocator, enc: RenpyEncoding, value: []const u8) !void {
    switch (enc) {
        .short_binunicode => if (value.len <= 255) {
            try out.append(a, OP_SHORT_BINUNICODE);
            try out.append(a, @intCast(value.len));
            try out.appendSlice(a, value);
            return;
        },
        .short_binstring, .binstring, .text_string => {
            // Python 2 `str` payloads stay byte strings: never re-encode as unicode.
            if (value.len > std.math.maxInt(u32)) return ParseError.UnsupportedResize;
            if (enc == .short_binstring and value.len <= 255) {
                try out.append(a, OP_SHORT_BINSTRING);
                try out.append(a, @intCast(value.len));
            } else {
                try out.append(a, OP_BINSTRING);
                try appendU32le(out, a, @intCast(value.len));
            }
            try out.appendSlice(a, value);
            return;
        },
        .binunicode => if (value.len <= std.math.maxInt(u32)) {
            try out.append(a, OP_BINUNICODE);
            try appendU32le(out, a, @intCast(value.len));
            try out.appendSlice(a, value);
            return;
        },
        .binunicode8 => {
            try out.append(a, OP_BINUNICODE8);
            try appendU64le(out, a, value.len);
            try out.appendSlice(a, value);
            return;
        },
        else => {},
    }
    // Default (text protocol / unknown): UTF-8 unicode string.
    if (value.len <= std.math.maxInt(u32)) {
        try out.append(a, OP_BINUNICODE);
        try appendU32le(out, a, @intCast(value.len));
    } else {
        try out.append(a, OP_BINUNICODE8);
        try appendU64le(out, a, value.len);
    }
    try out.appendSlice(a, value);
}

fn encodeScalar(out: *std.ArrayList(u8), a: std.mem.Allocator, node: *Node) !void {
    const value = node.value orelse return ParseError.KindMismatch;
    switch (value) {
        .Int => |v| try encodeInt(out, a, node.enc, v),
        .Float => |v| {
            if (node.enc == .text_float) {
                var tmp: [64]u8 = undefined;
                const text = try std.fmt.bufPrint(&tmp, "F{d}\n", .{v});
                try out.appendSlice(a, text);
            } else {
                try out.append(a, OP_BINFLOAT);
                var b: [8]u8 = undefined;
                std.mem.writeInt(u64, &b, @bitCast(v), .big);
                try out.appendSlice(a, &b);
            }
        },
        .Bool => |v| {
            if (node.enc == .text_int) {
                try out.appendSlice(a, if (v) "I01\n" else "I00\n");
            } else {
                try out.append(a, if (v) OP_NEWTRUE else OP_NEWFALSE);
            }
        },
        .Str => |s| try encodeString(out, a, node.enc, s),
    }
}

// ---------------------------------------------------------------------------
// Scalar decoding (used by the post-serialization read-back verification)
// ---------------------------------------------------------------------------

pub const DecodedScalar = struct {
    value: RenpyValue,
    len: usize,
};

fn readU32At(buf: []const u8, pos: usize) !u32 {
    if (pos + 4 > buf.len) return ParseError.UnexpectedEof;
    const b: *const [4]u8 = buf[pos..][0..4];
    return std.mem.readInt(u32, b, .little);
}

fn readU64At(buf: []const u8, pos: usize) !u64 {
    if (pos + 8 > buf.len) return ParseError.UnexpectedEof;
    const b: *const [8]u8 = buf[pos..][0..8];
    return std.mem.readInt(u64, b, .little);
}

fn readN(buf: []const u8, pos: usize, n: usize) ![]const u8 {
    if (n > buf.len or pos + n > buf.len) return ParseError.UnexpectedEof;
    return buf[pos .. pos + n];
}

fn findByte(buf: []const u8, from: usize, needle: u8) ?usize {
    var i = from;
    while (i < buf.len) : (i += 1) {
        if (buf[i] == needle) return i;
    }
    return null;
}

pub fn decodeScalarAt(buf: []const u8, off: usize) !DecodedScalar {
    if (off >= buf.len) return ParseError.UnexpectedEof;
    const op = buf[off];
    const pos = off + 1;
    switch (op) {
        OP_NEWTRUE => return .{ .value = .{ .Bool = true }, .len = 1 },
        OP_NEWFALSE => return .{ .value = .{ .Bool = false }, .len = 1 },
        OP_BININT => {
            const v: i32 = @bitCast(try readU32At(buf, pos));
            return .{ .value = .{ .Int = v }, .len = 5 };
        },
        OP_BININT1 => {
            if (pos >= buf.len) return ParseError.UnexpectedEof;
            return .{ .value = .{ .Int = @intCast(buf[pos]) }, .len = 2 };
        },
        OP_BININT2 => {
            if (pos + 2 > buf.len) return ParseError.UnexpectedEof;
            const b: *const [2]u8 = buf[pos..][0..2];
            return .{ .value = .{ .Int = @intCast(std.mem.readInt(u16, b, .little)) }, .len = 3 };
        },
        OP_LONG1 => {
            if (pos >= buf.len) return ParseError.UnexpectedEof;
            const n = buf[pos];
            const raw = try readN(buf, pos + 1, n);
            return .{ .value = .{ .Int = decodeLittleInt(raw) }, .len = 2 + @as(usize, n) };
        },
        OP_LONG4 => {
            const n = try readU32At(buf, pos);
            const raw = try readN(buf, pos + 4, n);
            return .{ .value = .{ .Int = decodeLittleInt(raw) }, .len = 5 + @as(usize, n) };
        },
        OP_INT, OP_LONG => {
            const end = findByte(buf, pos, '\n') orelse return ParseError.UnexpectedEof;
            var text = buf[pos..end];
            if (op == OP_LONG and text.len > 0) text = text[0 .. text.len - 1];
            const value: RenpyValue = if (std.mem.eql(u8, text, "01"))
                .{ .Bool = true }
            else if (std.mem.eql(u8, text, "00"))
                .{ .Bool = false }
            else
                .{ .Int = try parseInt64(text) };
            return .{ .value = value, .len = end + 1 - off };
        },
        OP_BINFLOAT => {
            if (pos + 8 > buf.len) return ParseError.UnexpectedEof;
            const b: *const [8]u8 = buf[pos..][0..8];
            const bits = std.mem.readInt(u64, b, .big);
            return .{ .value = .{ .Float = @bitCast(bits) }, .len = 9 };
        },
        OP_FLOAT => {
            const end = findByte(buf, pos, '\n') orelse return ParseError.UnexpectedEof;
            const v = std.fmt.parseFloat(f64, std.mem.trim(u8, buf[pos..end], " \t")) catch return ParseError.MalformedPickle;
            return .{ .value = .{ .Float = v }, .len = end + 1 - off };
        },
        OP_BINUNICODE, OP_BINSTRING => {
            const n = try readU32At(buf, pos);
            const raw = try readN(buf, pos + 4, n);
            return .{ .value = .{ .Str = raw }, .len = 5 + @as(usize, n) };
        },
        OP_SHORT_BINUNICODE, OP_SHORT_BINSTRING => {
            if (pos >= buf.len) return ParseError.UnexpectedEof;
            const n = buf[pos];
            const raw = try readN(buf, pos + 1, n);
            return .{ .value = .{ .Str = raw }, .len = 2 + @as(usize, n) };
        },
        OP_BINUNICODE8 => {
            const n = try readU64At(buf, pos);
            if (n > buf.len) return ParseError.UnexpectedEof;
            const slice_len: usize = @intCast(n);
            const raw = try readN(buf, pos + 8, slice_len);
            return .{ .value = .{ .Str = raw }, .len = 9 + slice_len };
        },
        else => return ParseError.KindMismatch,
    }
}

// ============================================================================
// UNIT TESTS
// ============================================================================

fn tStr(out: *std.ArrayList(u8), a: std.mem.Allocator, text: []const u8) !void {
    try out.append(a, OP_BINUNICODE);
    try appendU32le(out, a, @intCast(text.len));
    try out.appendSlice(a, text);
}

fn tInt(out: *std.ArrayList(u8), a: std.mem.Allocator, value: i32) !void {
    try out.append(a, OP_BININT);
    try appendU32le(out, a, @bitCast(value));
}

fn tFloat(out: *std.ArrayList(u8), a: std.mem.Allocator, value: f64) !void {
    try out.append(a, OP_BINFLOAT);
    var b: [8]u8 = undefined;
    std.mem.writeInt(u64, &b, @bitCast(value), .big);
    try out.appendSlice(a, &b);
}

/// Protocol-2 payload shaped like `renpy.save`: a dict of store variables.
fn buildSyntheticPickle(a: std.mem.Allocator) !std.ArrayList(u8) {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, &.{ OP_PROTO, 2, OP_EMPTY_DICT, OP_MARK });
    try tStr(&out, a, "gold");
    try tInt(&out, a, 1000);
    try tStr(&out, a, "player_name");
    try tStr(&out, a, "Arjun");
    try tStr(&out, a, "unlocked");
    try out.append(a, OP_NEWTRUE);
    try tStr(&out, a, "affection");
    try tFloat(&out, a, 12.5);
    try out.append(a, OP_SETITEMS);
    try out.append(a, OP_STOP);
    return out;
}

fn buildSyntheticSave(a: std.mem.Allocator) ![]u8 {
    var pickle = try buildSyntheticPickle(a);
    defer pickle.deinit(a);
    const body = try zlibCompress(a, pickle.items);
    defer a.free(body);
    var save: std.ArrayList(u8) = .empty;
    try save.appendSlice(a, "Ren'Py Save Game 8.2.3\n");
    try save.appendSlice(a, body);
    return save.toOwnedSlice(a);
}

/// Pickle that references itself through the memo (legal in protocol 2).
fn buildCyclicSave(a: std.mem.Allocator) ![]u8 {
    var pickle: std.ArrayList(u8) = .empty;
    defer pickle.deinit(a);
    try pickle.appendSlice(a, &.{ OP_PROTO, 2, OP_EMPTY_DICT, OP_BINPUT, 0, OP_MARK });
    try tStr(&pickle, a, "hp");
    try tInt(&pickle, a, 50);
    try tStr(&pickle, a, "self");
    try pickle.appendSlice(a, &.{ OP_BINGET, 0, OP_SETITEMS, OP_STOP });
    const body = try zlibCompress(a, pickle.items);
    defer a.free(body);
    var save: std.ArrayList(u8) = .empty;
    try save.appendSlice(a, "Ren'Py Save Game 7.6.3\n");
    try save.appendSlice(a, body);
    return save.toOwnedSlice(a);
}

test "Ren'Py parser: zlib container roundtrip and header detection" {
    const alloc = std.testing.allocator;
    const plain = "sharabha narasimha sharabha";

    const deflated = try zlibCompress(alloc, plain);
    defer alloc.free(deflated);
    const unpacked = try zlibDecompress(alloc, deflated);
    defer alloc.free(unpacked);
    try std.testing.expectEqualStrings(plain, unpacked);

    try std.testing.expect(isRenpySave("Ren'Py Save Game 8.2.3\nxxxx"));
    try std.testing.expect(!isRenpySave("PK\x03\x04 not a renpy save"));
    try std.testing.expectError(ParseError.NotRenpySave, locatePayload("not a renpy save"));
    try std.testing.expectError(ParseError.EmptyPayload, locatePayload("Ren'Py Save Game 8.2.3\n"));
}

test "Ren'Py parser: synthetic save decodes typed scalars" {
    const alloc = std.testing.allocator;
    const bytes = try buildSyntheticSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();

    try std.testing.expectEqual(@as(u8, 2), save.protocol);
    try std.testing.expectEqualStrings("8.2.3", save.renpyVersion());
    try std.testing.expectEqual(@as(usize, 4), save.countScalars());
    try std.testing.expectEqual(@as(i64, 1000), save.getInt("gold").?);
    try std.testing.expectEqualStrings("Arjun", save.getString("player_name").?);
    try std.testing.expect(save.getBool("unlocked").?);
    try std.testing.expectEqual(@as(f64, 12.5), save.getFloat("affection").?);

    const field = save.findField("gold").?;
    try std.testing.expectEqualStrings("i64 (Pickle Integer)", field.typeName());
    try std.testing.expectEqualStrings("RENPY_INT", field.typeTag());
}

test "Ren'Py parser: unedited save serializes byte-identically" {
    const alloc = std.testing.allocator;
    const bytes = try buildSyntheticSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();
    try std.testing.expect(!save.hasEdits());

    const out = try save.serialize(alloc);
    defer alloc.free(out);
    try std.testing.expectEqualSlices(u8, bytes, out);
}

test "Ren'Py parser: surgical edits survive verification" {
    const alloc = std.testing.allocator;
    const bytes = try buildSyntheticSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();

    try std.testing.expect(save.setInt("gold", 999_999));
    try std.testing.expect(save.setString("player_name", "अर्जुन"));
    try std.testing.expect(save.setBool("unlocked", false));
    try std.testing.expect(save.setFloat("affection", 42.75));
    try std.testing.expect(save.hasEdits());

    const out = try save.serialize(alloc);
    defer alloc.free(out);

    try std.testing.expect(std.mem.startsWith(u8, out, "Ren'Py Save Game 8.2.3\n"));

    var re = try RenpySave.parse(alloc, out);
    defer re.deinit();
    try std.testing.expectEqual(@as(i64, 999_999), re.getInt("gold").?);
    try std.testing.expectEqualStrings("अर्जुन", re.getString("player_name").?);
    try std.testing.expect(!re.getBool("unlocked").?);
    try std.testing.expectEqual(@as(f64, 42.75), re.getFloat("affection").?);
    try std.testing.expectEqual(@as(usize, 4), re.countScalars());
}

test "Ren'Py parser: integer promotion and long string resize" {
    const alloc = std.testing.allocator;
    const bytes = try buildSyntheticSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();

    // 3_000_000_000 does not fit BININT (i32): the splice promotes to LONG1.
    try std.testing.expect(save.setInt("gold", 3_000_000_000));
    // 600 bytes no longer fit a short length prefix (0x8C + u8 len).
    var long_buf: [600]u8 = undefined;
    for (0..200) |i| @memcpy(long_buf[i * 3 ..][0..3], "क");
    const long_name = long_buf[0..];
    try std.testing.expect(save.setString("player_name", long_name));

    const out = try save.serialize(alloc);
    defer alloc.free(out);

    var re = try RenpySave.parse(alloc, out);
    defer re.deinit();
    try std.testing.expectEqual(@as(i64, 3_000_000_000), re.getInt("gold").?);
    try std.testing.expectEqualStrings(long_name, re.getString("player_name").?);
    try std.testing.expectEqual(@as(usize, long_name.len), re.getString("player_name").?.len);
}

test "Ren'Py parser: applyEdit coerces by existing type" {
    const alloc = std.testing.allocator;
    const bytes = try buildSyntheticSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();

    try save.applyEdit("gold", " 4242 ");
    try save.applyEdit("affection", "7.25");
    try save.applyEdit("unlocked", "false");
    try save.applyEdit("player_name", "Karna");
    try std.testing.expectError(ParseError.KindMismatch, save.applyEdit("gold", "not-a-number"));
    try std.testing.expectError(ParseError.KindMismatch, save.applyEdit("missing_key", "1"));

    const out = try save.serialize(alloc);
    defer alloc.free(out);

    var re = try RenpySave.parse(alloc, out);
    defer re.deinit();
    try std.testing.expectEqual(@as(i64, 4242), re.getInt("gold").?);
    try std.testing.expectEqual(@as(f64, 7.25), re.getFloat("affection").?);
    try std.testing.expect(!re.getBool("unlocked").?);
    try std.testing.expectEqualStrings("Karna", re.getString("player_name").?);
}

test "Ren'Py parser: cyclic memo graph terminates" {
    const alloc = std.testing.allocator;
    const bytes = try buildCyclicSave(alloc);
    defer alloc.free(bytes);

    var save = try RenpySave.parse(alloc, bytes);
    defer save.deinit();

    try std.testing.expectEqualStrings("7.6.3", save.renpyVersion());
    try std.testing.expectEqual(@as(usize, 1), save.countScalars());
    try std.testing.expectEqual(@as(i64, 50), save.getInt("hp").?);

    try std.testing.expect(save.setInt("hp", 75));
    const out = try save.serialize(alloc);
    defer alloc.free(out);

    var re = try RenpySave.parse(alloc, out);
    defer re.deinit();
    try std.testing.expectEqual(@as(i64, 75), re.getInt("hp").?);
}

test "Ren'Py parser: rejects foreign and corrupt payloads" {
    const alloc = std.testing.allocator;

    try std.testing.expectError(ParseError.NotRenpySave, RenpySave.parse(alloc, "not a save file at all"));

    // Header present but the body is not a zlib stream: parsing must fail.
    var rejected = false;
    if (RenpySave.parse(alloc, "Ren'Py Save Game 8.0\nplain text body")) |value| {
        var leaked_save = value;
        leaked_save.deinit();
    } else |_| {
        rejected = true;
    }
    try std.testing.expect(rejected);
}
