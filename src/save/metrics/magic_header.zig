const std = @import("std");

pub const ContainerType = enum {
    RawCustomBinary,
    PlainText,
    GzipCompressed,
    ZlibCompressed,
    ZipContainer,
    SQLiteDatabase,
    UnrealEngineGVAS,
    UnitySerialized,
    RpgMakerSave,
    RenpySave,
    BsonFormat,
    Unknown,

    pub fn displayName(self: ContainerType) []const u8 {
        return switch (self) {
            .RawCustomBinary => "Raw Binary (प्राकृतिक द्वि-आधारी)",
            .PlainText => "Plain Text / JSON / XML (शुद्ध पाठ)",
            .GzipCompressed => "Gzip Stream [1F 8B] (संकोच)",
            .ZlibCompressed => "Zlib Stream [78 9C/DA] (संकोच)",
            .ZipContainer => "ZIP Container [PK..] (कोशिका)",
            .SQLiteDatabase => "SQLite 3 Engine (आधार स्तम्भ)",
            .UnrealEngineGVAS => "Unreal Engine GVAS (माया संपुट)",
            .UnitySerialized => "Unity Engine Serialization (एकीकृत प्रारूप)",
            .RpgMakerSave => "RPG Maker Save / Maya Lila Sutra (माया लीला सूत्र)",
            .RenpySave => "Ren'Py Visual Novel Save (काव्य सूत्र)",
            .BsonFormat => "BSON Binary Document (बीसॉन)",
            .Unknown => "Unrecognized Container (अविज्ञात)",
        };
    }
};

pub fn detectMagicHeader(buffer: []const u8) ContainerType {
    if (buffer.len < 4) return .Unknown;

    // Unreal Engine GVAS
    if (buffer.len >= 4 and std.mem.eql(u8, buffer[0..4], "GVAS")) {
        return .UnrealEngineGVAS;
    }

    // SQLite
    if (buffer.len >= 16 and std.mem.eql(u8, buffer[0..15], "SQLite format 3")) {
        return .SQLiteDatabase;
    }

    // ZIP / PK
    if (buffer[0] == 0x50 and buffer[1] == 0x4B and buffer[2] == 0x03 and buffer[3] == 0x04) {
        return .ZipContainer;
    }

    // GZIP
    if (buffer[0] == 0x1F and buffer[1] == 0x8B) {
        return .GzipCompressed;
    }

    // ZLIB
    if (buffer[0] == 0x78 and (buffer[1] == 0x01 or buffer[1] == 0x9C or buffer[1] == 0xDA or buffer[1] == 0x5E)) {
        return .ZlibCompressed;
    }

    // Unity Engine Containers (ऐक्य सूत्र // Aikya Sutra)
    // 1. Unity BinaryFormatter NRBF
    if (buffer.len >= 17 and buffer[0] == 0x00 and buffer[1] == 0x01 and buffer[2] == 0x00 and buffer[3] == 0x00 and buffer[4] == 0x00 and buffer[5] == 0xFF and buffer[6] == 0xFF and buffer[7] == 0xFF and buffer[8] == 0xFF) {
        return .UnitySerialized;
    }

    // 2. Unity PlayerPrefs XML
    const unity_xml_check = @min(buffer.len, 128);
    if (std.mem.indexOf(u8, buffer[0..unity_xml_check], "<unity_prefs") != null or std.mem.indexOf(u8, buffer[0..unity_xml_check], "<pref name=") != null) {
        return .UnitySerialized;
    }

    // 3. Unity Easy Save 3 (ES3 JSON)
    const es3_check = @min(buffer.len, 256);
    if (std.mem.indexOf(u8, buffer[0..es3_check], "\"__type\"") != null) {
        return .UnitySerialized;
    }

    // 4. UnityFS / UnityRaw
    if (buffer.len >= 7 and (std.mem.eql(u8, buffer[0..7], "UnityFS") or std.mem.eql(u8, buffer[0..7], "UnityRa"))) {
        return .UnitySerialized;
    }

    // Ren'Py Visual Novel Save (काव्य सूत्र)
    if (buffer.len >= 16 and std.mem.startsWith(u8, buffer, "Ren'Py Save Game")) {
        return .RenpySave;
    }

    // RPG Maker Ruby Marshal 4.8 (.rxdata, .rvdata, .rvdata2)
    if (buffer.len >= 2 and buffer[0] == 0x04 and buffer[1] == 0x08) {
        return .RpgMakerSave;
    }

    // RPG Maker LZ-String Base64 ("N4Ig", "BY", "CY")
    const trimmed_head = std.mem.trim(u8, buffer[0..@min(buffer.len, 64)], " \r\n\t");
    if (trimmed_head.len >= 4 and (std.mem.startsWith(u8, trimmed_head, "N4Ig") or std.mem.startsWith(u8, trimmed_head, "BY") or std.mem.startsWith(u8, trimmed_head, "CY"))) {
        return .RpgMakerSave;
    }

    // RPG Maker JSON
    const json_check_len = @min(buffer.len, 512);
    if (std.mem.indexOf(u8, buffer[0..json_check_len], "\"$gameParty\"") != null or
        (std.mem.indexOf(u8, buffer[0..json_check_len], "\"party\"") != null and std.mem.indexOf(u8, buffer[0..json_check_len], "\"_gold\"") != null))
    {
        return .RpgMakerSave;
    }

    // Plain text check
    var is_text = true;
    const check_len = @min(buffer.len, 64);
    for (buffer[0..check_len]) |b| {
        if (b < 0x09 or (b > 0x0D and b < 0x20) or b > 0x7E) {
            is_text = false;
            break;
        }
    }
    if (is_text) return .PlainText;

    return .RawCustomBinary;
}

test "Magic header detection" {
    const gvas = "GVAS\x03\x00\x00\x00";
    try std.testing.expectEqual(ContainerType.UnrealEngineGVAS, detectMagicHeader(gvas));

    const zlib = "\x78\x9C\x01\x00";
    try std.testing.expectEqual(ContainerType.ZlibCompressed, detectMagicHeader(zlib));

    const zip = "\x50\x4B\x03\x04\x14\x00";
    try std.testing.expectEqual(ContainerType.ZipContainer, detectMagicHeader(zip));

    const text = "{\"hero\": \"Rudra\"}";
    try std.testing.expectEqual(ContainerType.PlainText, detectMagicHeader(text));

    const rpg_lz = "N4IgDghgTgLgniAXKA+gcwPYBsAmSCch+AvsUA==";
    try std.testing.expectEqual(ContainerType.RpgMakerSave, detectMagicHeader(rpg_lz));

    const ruby_marshal = "\x04\x08o:\x0bObject\x00";
    try std.testing.expectEqual(ContainerType.RpgMakerSave, detectMagicHeader(ruby_marshal));

    const renpy = "Ren'Py Save Game\n\x78\x9c...";
    try std.testing.expectEqual(ContainerType.RenpySave, detectMagicHeader(renpy));
}
