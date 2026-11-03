//! ============================================================================
//! SHARABHA (शरभ) — AGAMA DETERMINISTIC KNOWLEDGE REGISTRY
//! Deterministic game-specific profiles with ground-truth variable schemas.
//! Features official Torpor Games Suzerain profile (Base Game Sordland & Rizia DLC).
//! Reference: D:\Projects\Suzerain-save-editor (by user)
//! ============================================================================

const std = @import("std");
const fuzzy = @import("../save/fuzzy.zig");

pub const KnownFieldRule = struct {
    offset: usize = 0,
    key_name: []const u8,
    display_title: []const u8,
    sanskrit_title: []const u8,
    category: []const u8 = "General",
    field_type: fuzzy.InferredType,
    min_value: i64 = 0,
    max_value: i64 = 999999,
    warning: ?[]const u8 = null,
};

pub const GameProfile = struct {
    id: []const u8,
    title: []const u8,
    sanskrit_title: []const u8,
    campaign_name: []const u8 = "",
    filename_pattern: []const u8 = "",
    magic_signature: ?[]const u8 = null,
    is_key_based: bool = false,
    rules: []const KnownFieldRule,

    pub fn matchesFile(self: *const GameProfile, filename: []const u8, content_or_header: []const u8) bool {
        // Capcom RE Engine recognition (DSSS container format, version 2, MurmurHash3_x86_32 footer)
        if (std.mem.startsWith(u8, self.id, "dd2") or std.mem.startsWith(u8, self.id, "re_") or std.mem.startsWith(u8, self.id, "re2") or std.mem.startsWith(u8, self.id, "re3") or std.mem.startsWith(u8, self.id, "re4") or std.mem.startsWith(u8, self.id, "re7") or std.mem.startsWith(u8, self.id, "re8")) {
            if (content_or_header.len < 8) return false;
            // Must begin with "DSSS"
            if (!std.mem.eql(u8, content_or_header[0..4], "DSSS")) return false;
            // Must have container version 2
            const ver = std.mem.readInt(u32, content_or_header[4..8], .little);
            if (ver != 2) return false;

            if (std.mem.eql(u8, self.id, "dd2")) {
                if (std.mem.indexOf(u8, filename, "2054970") != null or
                    std.mem.indexOf(u8, filename, "dd2") != null or
                    std.mem.indexOf(u8, filename, "dragonsdogma") != null or
                    std.mem.indexOf(u8, filename, "data001Slot") != null) {
                    return true;
                }
                // Default fallback if generic data000.bin / data001.bin without other game tags
                const has_other_tag = std.mem.indexOf(u8, filename, "re2") != null or
                    std.mem.indexOf(u8, filename, "re3") != null or
                    std.mem.indexOf(u8, filename, "re4") != null or
                    std.mem.indexOf(u8, filename, "re7") != null or
                    std.mem.indexOf(u8, filename, "re8") != null or
                    std.mem.indexOf(u8, filename, "mhw") != null or
                    std.mem.indexOf(u8, filename, "mhr") != null;
                return !has_other_tag and (std.mem.endsWith(u8, filename, ".bin") or std.mem.endsWith(u8, filename, ".BIN"));
            } else if (std.mem.eql(u8, self.id, "re4")) {
                return (std.mem.indexOf(u8, filename, "2050650") != null or std.mem.indexOf(u8, filename, "re4") != null);
            } else if (std.mem.eql(u8, self.id, "re2")) {
                return (std.mem.indexOf(u8, filename, "883710") != null or std.mem.indexOf(u8, filename, "re2") != null);
            } else if (std.mem.eql(u8, self.id, "re3")) {
                return (std.mem.indexOf(u8, filename, "952060") != null or std.mem.indexOf(u8, filename, "re3") != null);
            } else if (std.mem.eql(u8, self.id, "re8")) {
                return (std.mem.indexOf(u8, filename, "1196590") != null or std.mem.indexOf(u8, filename, "re8") != null or std.mem.indexOf(u8, filename, "village") != null);
            } else if (std.mem.eql(u8, self.id, "re7")) {
                return (std.mem.indexOf(u8, filename, "418370") != null or std.mem.indexOf(u8, filename, "re7") != null);
            } else if (std.mem.eql(u8, self.id, "re_mhw")) {
                return (std.mem.indexOf(u8, filename, "2246340") != null or std.mem.indexOf(u8, filename, "wilds") != null or std.mem.indexOf(u8, filename, "mhw") != null);
            } else if (std.mem.eql(u8, self.id, "re_mhr")) {
                return (std.mem.indexOf(u8, filename, "1446780") != null or std.mem.indexOf(u8, filename, "rise") != null or std.mem.indexOf(u8, filename, "mhr") != null);
            }
            return false;
        }

        // Mass Effect Legendary Edition recognition (LE1, LE2, LE3; strictly LE, explicitly rejecting mid-2000s & Andromeda)
        if (std.mem.startsWith(u8, self.id, "mele")) {
            const is_pcsav = std.mem.endsWith(u8, filename, ".pcsav") or std.mem.endsWith(u8, filename, ".PCSAV");
            if (!is_pcsav) return false;
            if (content_or_header.len < 4) return false;

            if (std.mem.eql(u8, self.id, "mele1")) {
                const me1_magic = [_]u8{ 0xC1, 0x83, 0x2A, 0x9E };
                return std.mem.eql(u8, content_or_header[0..4], &me1_magic);
            } else if (std.mem.eql(u8, self.id, "mele2")) {
                // Must be version 30 (0x0000001E). Note: original ME2 is 29 (0x0000001D), which must NOT match.
                const ver = std.mem.readInt(i32, content_or_header[0..4], .little);
                return ver == 30;
            } else if (std.mem.eql(u8, self.id, "mele3")) {
                // ME3 / MELE3 version is 59 (0x0000003B)
                const ver = std.mem.readInt(i32, content_or_header[0..4], .little);
                return ver == 59;
            }
            return false;
        }

        // Special recognition for Suzerain Torpor saves
        if (std.mem.startsWith(u8, self.id, "suzerain")) {
            const has_pack = std.mem.indexOf(u8, content_or_header, "\"currentStoryPack\"") != null;
            const has_vars = std.mem.indexOf(u8, content_or_header, "Variable={[\"") != null or
                std.mem.indexOf(u8, content_or_header, "\"variables\"") != null;
            if (!has_pack or !has_vars) return false;

            if (std.mem.eql(u8, self.id, "suzerain_rizia")) {
                return std.mem.indexOf(u8, content_or_header, "\"StoryPack_Rizia\"") != null;
            } else if (std.mem.eql(u8, self.id, "suzerain_sordland")) {
                return std.mem.indexOf(u8, content_or_header, "\"StoryPack_Rizia\"") == null;
            }
            return true;
        }

        if (self.magic_signature) |sig| {
            if (content_or_header.len < sig.len or !std.mem.eql(u8, content_or_header[0..sig.len], sig)) {
                return false;
            }
        }
        if (self.filename_pattern.len > 0) {
            if (std.mem.indexOf(u8, filename, self.filename_pattern) == null) {
                return false;
            }
        }
        return (self.magic_signature != null or self.filename_pattern.len > 0);
    }
};

// ============================================================================
// SUZERAIN — BASE GAME SORDLAND (PRESIDENT ANTON RAYNE)
// ============================================================================
pub const SUZERAIN_SORDLAND_RULES = [_]KnownFieldRule{
    // Core & Opinion
    .{
        .key_name = "BaseGame.GovernmentBudget",
        .display_title = "Government Budget",
        .sanskrit_title = "राजकोष (Budget)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = -15,
        .max_value = 50,
        .warning = "Warning: Setting budget > 3 before Turn 4 can trigger Black Tuesday!",
    },
    .{
        .key_name = "BaseGame.PersonalWealth",
        .display_title = "Personal Wealth",
        .sanskrit_title = "व्यक्तिगत धन (Wealth)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "BaseGame.Country_Unrest",
        .display_title = "Country Unrest",
        .sanskrit_title = "देश अशान्ति (Unrest)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "BaseGame.Public_Opinion",
        .display_title = "Public Opinion",
        .sanskrit_title = "जनता मत (Public Opinion)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "BaseGame.Bludish_Opinion",
        .display_title = "Bludish Opinion",
        .sanskrit_title = "ब्लूडिश मत (Bludish Opinion)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "Game.Turn",
        .display_title = "Current Turn",
        .sanskrit_title = "वर्तमान काल (Turn)",
        .category = "Core",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 11,
    },

    // Events & Market
    .{
        .key_name = "BaseGame.BlackTuesdayHappened",
        .display_title = "Black Tuesday Happened",
        .sanskrit_title = "कृष्ण मङ्गलवार (Black Tuesday)",
        .category = "Events",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "Game.IsMarketCrashing",
        .display_title = "Market Crashing",
        .sanskrit_title = "विपणि पतन (Market Crash)",
        .category = "Events",
        .field_type = .StringAscii,
    },

    // Politics & Reform
    .{
        .key_name = "BaseGame.Reform_Assembly_Vote",
        .display_title = "Reform Assembly Vote",
        .sanskrit_title = "संसद् मत (Assembly Vote)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 250,
    },
    .{
        .key_name = "BaseGame.Reform_Court_Vote",
        .display_title = "Reform Court Vote",
        .sanskrit_title = "न्यायालय मत (Court Vote)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 11,
    },
    .{
        .key_name = "Albin_Convinced",
        .display_title = "Albin Convinced",
        .sanskrit_title = "अल्बिन सहमति (Albin)",
        .category = "Politics",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "Gloria_Convinced",
        .display_title = "Gloria Convinced",
        .sanskrit_title = "ग्लोरिया सहमति (Gloria)",
        .category = "Politics",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "GameCondition.Turn04_A_Convince_Gloria",
        .display_title = "Turn 4 Convince Gloria",
        .sanskrit_title = "ग्लोरिया संवाद ४",
        .category = "Politics",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "GameCondition.Turn04_A_Convince_Albin",
        .display_title = "Turn 4 Convince Albin",
        .sanskrit_title = "अल्बिन संवाद ४",
        .category = "Politics",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Amendment_USP_Gloria_Convinced",
        .display_title = "USP Gloria Convinced (Art 6&7)",
        .sanskrit_title = "यूएसपी संशोधन सहमति",
        .category = "Politics",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Faction_USP_AgainstProposal",
        .display_title = "USP Against Proposal",
        .sanskrit_title = "यूएसपी विरोध",
        .category = "Politics",
        .field_type = .StringAscii,
    },

    // Economy & Regional Development
    .{
        .key_name = "BaseGame.Economy_Agnland",
        .display_title = "Agnland Economy",
        .sanskrit_title = "अग्नलाण्ड अर्थ",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 15,
    },
    .{
        .key_name = "BaseGame.Economy_Bergia",
        .display_title = "Bergia Economy",
        .sanskrit_title = "बेर्गिया अर्थ",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 15,
    },
    .{
        .key_name = "BaseGame.Economy_Lorren",
        .display_title = "Lorren Economy",
        .sanskrit_title = "लोरेन अर्थ",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 15,
    },
    .{
        .key_name = "BaseGame.Economy_Gruni",
        .display_title = "Gruni Economy",
        .sanskrit_title = "ग्रुनी अर्थ",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 15,
    },
    .{
        .key_name = "BaseGame.TradeAmount",
        .display_title = "Trade Amount Modifier",
        .sanskrit_title = "व्यापार राशि (Trade)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },

    // Relations & Prologue
    .{
        .key_name = "BaseGame.Relations_Franc_Opinion",
        .display_title = "Franc Opinion",
        .sanskrit_title = "फ्राङ्क सम्बन्ध (Franc)",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "BaseGame.Relations_Monica_Opinion",
        .display_title = "Monica Opinion",
        .sanskrit_title = "मोनिका सम्बन्ध (Monica)",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "BaseGame.Relations_Lucian_Opinion",
        .display_title = "Lucian Opinion",
        .sanskrit_title = "लुसियन सम्बन्ध (Lucian)",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "BaseGame.Prologue_Studyplace_Deyr_History",
        .display_title = "Prologue Study: Deyr History",
        .sanskrit_title = "देयर इतिहास विद्या",
        .category = "Relations",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Prologue_Studyplace_Holsord_Law",
        .display_title = "Prologue Study: Holsord Law",
        .sanskrit_title = "होल्सोर्ड विधि विद्या",
        .category = "Relations",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Prologue_Studyplace_Lachaven_Economics",
        .display_title = "Prologue Study: Lachaven Economics",
        .sanskrit_title = "लाचावेन अर्थ विद्या",
        .category = "Relations",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.LeakedScandals_Severity",
        .display_title = "Leaked Scandals Severity",
        .sanskrit_title = "रहस्योद्घाटन तीव्रता",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "BaseGameIsolated.Turn09_A_TelevisionInterview_International_Empathy_Gained",
        .display_title = "TV Interview International Empathy",
        .sanskrit_title = "दूरदर्शन सहानुभूति लाभ",
        .category = "Relations",
        .field_type = .StringAscii,
    },

    // Military Expansion (Paired)
    .{
        .key_name = "BaseGame.Turn06_SnO_Expansion_Army",
        .display_title = "Expanded Army (Turn 6 Flag)",
        .sanskrit_title = "थलसेना विस्तार संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ExpandedArmy",
        .display_title = "Expanded Army (Situation Flag)",
        .sanskrit_title = "थलसेना विस्तार स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Turn06_SnO_Expansion_Navy",
        .display_title = "Expanded Navy (Turn 6 Flag)",
        .sanskrit_title = "नौसेना विस्तार संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ExpandedNavy",
        .display_title = "Expanded Navy (Situation Flag)",
        .sanskrit_title = "नौसेना विस्तार स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Turn06_SnO_Expansion_Airforce",
        .display_title = "Expanded Air Force (Turn 6 Flag)",
        .sanskrit_title = "वायुसेना विस्तार संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ExpandedAirForce",
        .display_title = "Expanded Air Force (Situation Flag)",
        .sanskrit_title = "वायुसेना विस्तार स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },

    // Military Modernisation (Paired)
    .{
        .key_name = "BaseGame.Turn06_SnO_Modernisation_Army",
        .display_title = "Modernised Army (Turn 6 Flag)",
        .sanskrit_title = "थलसेना आधुनिकीकरण संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ModernisedArmy",
        .display_title = "Modernised Army (Situation Flag)",
        .sanskrit_title = "थलसेना आधुनिकीकरण स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Turn06_SnO_Modernisation_Navy",
        .display_title = "Modernised Navy (Turn 6 Flag)",
        .sanskrit_title = "नौसेना आधुनिकीकरण संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ModernisedNavy",
        .display_title = "Modernised Navy (Situation Flag)",
        .sanskrit_title = "नौसेना आधुनिकीकरण स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Turn06_SnO_Modernisation_Airforce",
        .display_title = "Modernised Air Force (Turn 6 Flag)",
        .sanskrit_title = "वायुसेना आधुनिकीकरण संकल्प",
        .category = "Military",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "BaseGame.Situation_Military_ModernisedAirForce",
        .display_title = "Modernised Air Force (Situation Flag)",
        .sanskrit_title = "वायुसेना आधुनिकीकरण स्थिति",
        .category = "Military",
        .field_type = .StringAscii,
    },
};

// ============================================================================
// SUZERAIN — RIZIA DLC (KING ROMUS TORAS)
// ============================================================================
pub const SUZERAIN_RIZIA_RULES = [_]KnownFieldRule{
    // Economy & Royal Resources
    .{
        .key_name = "RiziaDLC.Resources_Budget",
        .display_title = "Royal Budget (Max 25)",
        .sanskrit_title = "राजकोष (Budget)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 25,
    },
    .{
        .key_name = "RiziaDLC.Resources_Authority",
        .display_title = "Royal Authority (Max 15)",
        .sanskrit_title = "राजसत्ता (Authority)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 15,
    },
    .{
        .key_name = "RiziaDLC.Resources_Energy",
        .display_title = "Energy Reserves (Max 25)",
        .sanskrit_title = "ऊर्जा संचय (Energy)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 25,
    },
    .{
        .key_name = "RiziaDLC.Budget_Modifier_IncomeTax",
        .display_title = "Income Tax Modifier per Turn",
        .sanskrit_title = "आयकर गुणक",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Energy_Modifier_BaseEnergy",
        .display_title = "Base Energy Modifier per Turn",
        .sanskrit_title = "मूल ऊर्जा गुणक",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Authority_Modifier_BaseMonarchRomus",
        .display_title = "Monarch Romus Authority Modifier",
        .sanskrit_title = "सम्राट सत्ता गुणक",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },

    // Military Deployable Units
    .{
        .key_name = "RiziaDLC.Army_Unit_Infantry_Total",
        .display_title = "Infantry Units Total",
        .sanskrit_title = "पदाति सैन्य दल",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Army_Unit_Tank_Total",
        .display_title = "Tank Units Total",
        .sanskrit_title = "टैङ्क सैन्य दल",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Army_Unit_Submarine_Total",
        .display_title = "Submarine Fleet Total",
        .sanskrit_title = "पनडुब्बी बेड़ा",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Army_Unit_Support_Total",
        .display_title = "Support Units Total",
        .sanskrit_title = "सहायक सैन्य दल",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "RiziaDLC.Army_Unit_Ship_Total",
        .display_title = "Capital Ships Total",
        .sanskrit_title = "युद्धपोत बेड़ा",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },

    // Military Stockpiles
    .{
        .key_name = "RiziaDLC.Resources_Military_Trucks",
        .display_title = "Trucks Stockpile",
        .sanskrit_title = "ट्रक भण्डार",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_Ships",
        .display_title = "Ships Stockpile",
        .sanskrit_title = "पोत भण्डार",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_Tanks",
        .display_title = "Tanks Stockpile",
        .sanskrit_title = "टैङ्क भण्डार",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_Submarines",
        .display_title = "Submarines Stockpile",
        .sanskrit_title = "पनडुब्बी भण्डार",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_Manpower",
        .display_title = "Manpower Reserve",
        .sanskrit_title = "सैन्य जनशक्ति",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 1000000,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_Equipment",
        .display_title = "Equipment Stockpile",
        .sanskrit_title = "सैन्य उपकरण भण्डार",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 50000,
    },

    // War & Operations
    .{
        .key_name = "RiziaDLC.War_ActionPoints",
        .display_title = "War Action Points",
        .sanskrit_title = "युद्ध क्रिया बिन्दु (AP)",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 100,
    },
    .{
        .key_name = "RiziaDLC.Resources_Military_AirStrikeRefillPerFragment",
        .display_title = "Air Strike Refill per Fragment",
        .sanskrit_title = "वायु प्रहार पुनर्भरण",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 50,
    },
    .{
        .key_name = "RiziaDLC.War_Pales_PublicWarSupport",
        .display_title = "Pales War Public Support",
        .sanskrit_title = "पेल्स युद्ध जनसमर्थन",
        .category = "Military",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 100,
    },

    // Welfare & Royal Houses
    .{
        .key_name = "RiziaDLC.Country_ProductionCapacity",
        .display_title = "Country Production Capacity",
        .sanskrit_title = "उत्पादन क्षमता",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_LivingStandards",
        .display_title = "Living Standards",
        .sanskrit_title = "जीवन स्तर",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_PublicOpinion",
        .display_title = "Public Opinion (Rizia)",
        .sanskrit_title = "जनता सम्मति (Public)",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_HouseToras",
        .display_title = "House Toras Standing",
        .sanskrit_title = "तोरास घराना",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_HouseSazon",
        .display_title = "House Sazon Standing",
        .sanskrit_title = "साज़ोन घराना",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_HouseAzaro",
        .display_title = "House Azaro Standing",
        .sanskrit_title = "अज़ारो घराना",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },

    // Religions
    .{
        .key_name = "RiziaDLC.Country_GolcondistOpinion",
        .display_title = "Golcondist Opinion",
        .sanskrit_title = "गोलकोण्ड मत",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_WruhecistOpinion",
        .display_title = "Wruhecist Opinion",
        .sanskrit_title = "व्रुहेक मत",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Country_DastnuristOpinion",
        .display_title = "Dastnurist Opinion",
        .sanskrit_title = "दस्तनूर मत",
        .category = "Politics",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },

    // Diplomacy & Negotiating Power
    .{
        .key_name = "RiziaDLC.Diplomacy_Derdia_NegotiatingPower",
        .display_title = "Derdia Negotiating Power",
        .sanskrit_title = "देर्दिया वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Morella_NegotiatingPower",
        .display_title = "Morella Negotiating Power",
        .sanskrit_title = "मोरेल्ला वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Sordland_NegotiatingPower",
        .display_title = "Sordland Negotiating Power",
        .sanskrit_title = "सोर्डलैण्ड वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Zille_ReferendumPower",
        .display_title = "Zille Referendum Power",
        .sanskrit_title = "ज़िले जनमत शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Lespia_NegotiatingPower",
        .display_title = "Lespia Negotiating Power",
        .sanskrit_title = "लेस्पिया वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.CountryRelation_Lespia_Friendly",
        .display_title = "Lespia Friendly Relation",
        .sanskrit_title = "लेस्पिया मैत्री सम्बन्ध",
        .category = "Diplomacy",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Valgsland_NegotiatingPower",
        .display_title = "Valgsland Negotiating Power",
        .sanskrit_title = "वाल्ग्सलैण्ड वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Pales_NegotiatingPower",
        .display_title = "Pales Negotiating Power",
        .sanskrit_title = "पेल्स वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Rumburg_NegotiatingPower",
        .display_title = "Rumburg Negotiating Power",
        .sanskrit_title = "रुम्बर्ग वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },
    .{
        .key_name = "RiziaDLC.Diplomacy_Wehlen_NegotiatingPower",
        .display_title = "Wehlen Negotiating Power",
        .sanskrit_title = "वेहलेन वार्ता शक्ति",
        .category = "Diplomacy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 20,
    },

    // Council Relations
    .{
        .key_name = "RiziaDLC.Relations_Sal",
        .display_title = "Arch-Priest Sal Relation",
        .sanskrit_title = "प्रधान याजक साल सम्बन्ध",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "RiziaDLC.Relations_Vina",
        .display_title = "Princess Vina Relation",
        .sanskrit_title = "राजकुमारी वीना सम्बन्ध",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "RiziaDLC.Relations_Estela",
        .display_title = "Queen Mother Estela Relation",
        .sanskrit_title = "राजमाता एस्तेला सम्बन्ध",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "RiziaDLC.Relations_Pabel",
        .display_title = "Pabel Relation",
        .sanskrit_title = "पाबेल सम्बन्ध",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "RiziaDLC.Relations_Hugo",
        .display_title = "Uncle Hugo Relation",
        .sanskrit_title = "पितृव्य ह्यूगो सम्बन्ध",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "RiziaDLC.Relations_Lucita_Romance",
        .display_title = "Lucita Romance (Max 3)",
        .sanskrit_title = "लुसिता प्रणय",
        .category = "Relations",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 3,
    },
};

// ============================================================================
// MASS EFFECT LEGENDARY EDITION — CURATED AGAMA PROFILES
// Format specifications and field structures reverse-engineered based on the
// work of Karlitos (KarlitosVII/trilogy-save-editor):
// MELE1 (zlib chunk package 0x9E2A83C1, version 50)
// MELE2 (uncompressed Unreal package stream, version 30)
// MELE3 (uncompressed Unreal package stream, version 59)
// ============================================================================

pub const MELE1_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Player.Credits",
        .display_title = "Credits",
        .sanskrit_title = "धन (Credits)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Player.Medigel",
        .display_title = "Medi-Gel",
        .sanskrit_title = "औषधि (Medi-Gel)",
        .category = "Supplies",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Player.Grenades",
        .display_title = "Grenades",
        .sanskrit_title = "विस्फोटक (Grenades)",
        .category = "Supplies",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 99,
    },
    .{
        .key_name = "Player.Omnigel",
        .display_title = "Omni-Gel",
        .sanskrit_title = "सर्वौषध (Omni-Gel)",
        .category = "Supplies",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Plot.Paragon",
        .display_title = "Paragon Points (Plot Int 47)",
        .sanskrit_title = "धर्म / आदर्श (Paragon)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 350,
    },
    .{
        .key_name = "Plot.Renegade",
        .display_title = "Renegade Points (Plot Int 46)",
        .sanskrit_title = "क्रोध / विद्रोही (Renegade)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 350,
    },
    .{
        .key_name = "Player.Level",
        .display_title = "Character Level (Max 60)",
        .sanskrit_title = "स्तर (Level)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 60,
    },
    .{
        .key_name = "Player.CurrentXP",
        .display_title = "Experience Points (XP)",
        .sanskrit_title = "अनुभव (XP)",
        .category = "Progression",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 10000000,
    },
    .{
        .key_name = "Player.TalentPoints",
        .display_title = "Talent Points",
        .sanskrit_title = "कौशल बिन्दु (Talent Points)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Player.FirstName",
        .display_title = "Character First Name",
        .sanskrit_title = "नाम (First Name)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "Player.FaceCode",
        .display_title = "Identity / Face Code",
        .sanskrit_title = "मुख रेखा (Face Code)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
};

pub const MELE2_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Player.Credits",
        .display_title = "Credits",
        .sanskrit_title = "धन (Credits)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Player.Medigel",
        .display_title = "Medi-Gel",
        .sanskrit_title = "औषधि (Medi-Gel)",
        .category = "Supplies",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99,
    },
    .{
        .key_name = "Player.Eezo",
        .display_title = "Element Zero (Eezo)",
        .sanskrit_title = "शून्य तत्त्व (Eezo)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Player.Iridium",
        .display_title = "Iridium",
        .sanskrit_title = "इरीडियम (Iridium)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Player.Palladium",
        .display_title = "Palladium",
        .sanskrit_title = "पैलेडियम (Palladium)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Player.Platinum",
        .display_title = "Platinum",
        .sanskrit_title = "प्लैटिनम (Platinum)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Player.Probes",
        .display_title = "Planetary Probes",
        .sanskrit_title = "अन्वेषक (Probes)",
        .category = "Supplies",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 100,
    },
    .{
        .key_name = "Player.CurrentFuel",
        .display_title = "Normandy Fuel",
        .sanskrit_title = "इन्धन (Fuel)",
        .category = "Supplies",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "Plot.Paragon",
        .display_title = "Paragon Points (Plot Int 2)",
        .sanskrit_title = "धर्म / आदर्श (Paragon)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 1950,
    },
    .{
        .key_name = "Plot.Renegade",
        .display_title = "Renegade Points (Plot Int 3)",
        .sanskrit_title = "क्रोध / विद्रोही (Renegade)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 1950,
    },
    .{
        .key_name = "Player.Level",
        .display_title = "Character Level (Max 30)",
        .sanskrit_title = "स्तर (Level)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 30,
    },
    .{
        .key_name = "Player.CurrentXP",
        .display_title = "Experience Points (XP)",
        .sanskrit_title = "अनुभव (XP)",
        .category = "Progression",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 10000000,
    },
    .{
        .key_name = "Player.TalentPoints",
        .display_title = "Talent Points",
        .sanskrit_title = "कौशल बिन्दु (Talent Points)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Player.FirstName",
        .display_title = "Character First Name",
        .sanskrit_title = "नाम (First Name)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "Player.FaceCode",
        .display_title = "Identity / Face Code",
        .sanskrit_title = "मुख रेखा (Face Code)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
};

pub const MELE3_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Player.Credits",
        .display_title = "Credits",
        .sanskrit_title = "धन (Credits)",
        .category = "Resources",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Player.Medigel",
        .display_title = "Medi-Gel",
        .sanskrit_title = "औषधि (Medi-Gel)",
        .category = "Supplies",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99,
    },
    .{
        .key_name = "Player.Grenades",
        .display_title = "Grenades",
        .sanskrit_title = "विस्फोटक (Grenades)",
        .category = "Supplies",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99,
    },
    .{
        .key_name = "Player.CurrentFuel",
        .display_title = "Normandy Fuel",
        .sanskrit_title = "इन्धन (Fuel)",
        .category = "Supplies",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 5000,
    },
    .{
        .key_name = "Plot.Paragon",
        .display_title = "Paragon Points (Plot Key 10159)",
        .sanskrit_title = "धर्म / आदर्श (Paragon)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 2000,
    },
    .{
        .key_name = "Plot.Renegade",
        .display_title = "Renegade Points (Plot Key 10160)",
        .sanskrit_title = "क्रोध / विद्रोही (Renegade)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 2000,
    },
    .{
        .key_name = "Plot.Reputation",
        .display_title = "Reputation Bars (Plot Key 10297)",
        .sanskrit_title = "कीर्ति (Reputation)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 10,
    },
    .{
        .key_name = "Plot.ReputationPoints",
        .display_title = "Reputation Total Points (Plot Key 10380)",
        .sanskrit_title = "कीर्ति बिन्दु (Reputation Points)",
        .category = "Morality",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 2000,
    },
    .{
        .key_name = "Player.WarAssetsCount",
        .display_title = "War Assets Registered Count",
        .sanskrit_title = "युद्ध सम्पत्ति गणना (War Assets)",
        .category = "War Assets",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 500,
    },
    .{
        .key_name = "Player.Level",
        .display_title = "Character Level (Max 60)",
        .sanskrit_title = "स्तर (Level)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 60,
    },
    .{
        .key_name = "Player.CurrentXP",
        .display_title = "Experience Points (XP)",
        .sanskrit_title = "अनुभव (XP)",
        .category = "Progression",
        .field_type = .Float32LE,
        .min_value = 0,
        .max_value = 10000000,
    },
    .{
        .key_name = "Player.TalentPoints",
        .display_title = "Talent Points",
        .sanskrit_title = "कौशल बिन्दु (Talent Points)",
        .category = "Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Player.FirstName",
        .display_title = "Character First Name",
        .sanskrit_title = "नाम (First Name)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
    .{
        .key_name = "Player.FaceCode",
        .display_title = "Identity / Face Code",
        .sanskrit_title = "मुख रेखा (Face Code)",
        .category = "Identity",
        .field_type = .StringAscii,
    },
};

// ============================================================================
// DRAGON'S DOGMA 2 — CAPCOM RE ENGINE (व्याघ्रेश्वर आगम)
// Reference: dd2-content-editor (kagenocookie) & ree-save-editor (kvasszn)
// Steam AppID: 2054970 | win64_save/data001Slot.bin
// ============================================================================
pub const DD2_RULES = [_]KnownFieldRule{
    // Economy
    .{
        .key_name = "Base.Gold",
        .display_title = "Gold (G) // सुवर्ण धनम्",
        .sanskrit_title = "सुवर्ण धनम् (Gold)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Base.RC",
        .display_title = "Rift Crystals (RC) // रिफ्ट मणयः",
        .sanskrit_title = "रिफ्ट स्फटिक (Rift Crystals)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    // Arisen Progression
    .{
        .key_name = "Arisen.Level",
        .display_title = "Arisen Level (Max 999)",
        .sanskrit_title = "जाग्रत स्तर (Arisen Level)",
        .category = "Arisen Progression",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 999,
    },
    .{
        .key_name = "Arisen.Experience",
        .display_title = "Arisen Total Experience (EXP)",
        .sanskrit_title = "जाग्रत अनुभव (Arisen Exp)",
        .category = "Arisen Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999999999,
    },
    .{
        .key_name = "Arisen.Dcp",
        .display_title = "Arisen Discipline Points (DCP)",
        .sanskrit_title = "जाग्रत अनुशासन बिन्दु (Arisen DCP)",
        .category = "Arisen Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Arisen.Vocation",
        .display_title = "Arisen Active Vocation (Job ID 0..9)",
        .sanskrit_title = "जाग्रत वृत्ति (Arisen Vocation)",
        .category = "Arisen Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9,
        .warning = "0: Fighter, 1: Archer, 2: Mage, 3: Thief, 4: Warrior, 5: Sorcerer, 6: Magick Archer, 7: Mystic Spearhand, 8: Trickster, 9: Warfarer",
    },
    // Arisen Attributes
    .{
        .key_name = "Arisen.CurrentHP",
        .display_title = "Arisen Current Health (HP)",
        .sanskrit_title = "जाग्रत प्राण शक्ति (Current HP)",
        .category = "Arisen Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    .{
        .key_name = "Arisen.MaxHP",
        .display_title = "Arisen Max Health",
        .sanskrit_title = "जाग्रत परम प्राण (Max HP)",
        .category = "Arisen Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    .{
        .key_name = "Arisen.LossGauge",
        .display_title = "Arisen Loss Gauge (Unrecoverable HP)",
        .sanskrit_title = "जाग्रत क्षत सीमा (Loss Gauge)",
        .category = "Arisen Attributes",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999,
    },
    .{
        .key_name = "Arisen.CurrentStamina",
        .display_title = "Arisen Current Stamina",
        .sanskrit_title = "जाग्रत धैर्य शक्ति (Current Stamina)",
        .category = "Arisen Attributes",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999,
    },
    .{
        .key_name = "Arisen.MaxStamina",
        .display_title = "Arisen Max Stamina",
        .sanskrit_title = "जाग्रत परम धैर्य (Max Stamina)",
        .category = "Arisen Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    // Main Pawn Progression
    .{
        .key_name = "MainPawn.Level",
        .display_title = "Main Pawn Level (Max 999)",
        .sanskrit_title = "पौन स्तर (Main Pawn Level)",
        .category = "Main Pawn Progression",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 999,
    },
    .{
        .key_name = "MainPawn.Experience",
        .display_title = "Main Pawn Total Experience (EXP)",
        .sanskrit_title = "पौन अनुभव (Main Pawn Exp)",
        .category = "Main Pawn Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999999999,
    },
    .{
        .key_name = "MainPawn.Dcp",
        .display_title = "Main Pawn Discipline Points (DCP)",
        .sanskrit_title = "पौन अनुशासन बिन्दु (Pawn DCP)",
        .category = "Main Pawn Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "MainPawn.Vocation",
        .display_title = "Main Pawn Active Vocation (Job ID 0..5)",
        .sanskrit_title = "पौन वृत्ति (Pawn Vocation)",
        .category = "Main Pawn Progression",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 5,
        .warning = "Pawns can only use core vocations: 0: Fighter, 1: Archer, 2: Mage, 3: Thief, 4: Warrior, 5: Sorcerer",
    },
    // Main Pawn Attributes
    .{
        .key_name = "MainPawn.CurrentHP",
        .display_title = "Main Pawn Current Health (HP)",
        .sanskrit_title = "पौन प्राण शक्ति (Pawn HP)",
        .category = "Main Pawn Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    .{
        .key_name = "MainPawn.MaxHP",
        .display_title = "Main Pawn Max Health",
        .sanskrit_title = "पौन परम प्राण (Pawn Max HP)",
        .category = "Main Pawn Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    .{
        .key_name = "MainPawn.LossGauge",
        .display_title = "Main Pawn Loss Gauge",
        .sanskrit_title = "पौन क्षत सीमा (Pawn Loss Gauge)",
        .category = "Main Pawn Attributes",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999,
    },
    .{
        .key_name = "MainPawn.CurrentStamina",
        .display_title = "Main Pawn Current Stamina",
        .sanskrit_title = "पौन धैर्य शक्ति (Pawn Stamina)",
        .category = "Main Pawn Attributes",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999,
    },
    .{
        .key_name = "MainPawn.MaxStamina",
        .display_title = "Main Pawn Max Stamina",
        .sanskrit_title = "पौन परम धैर्य (Pawn Max Stamina)",
        .category = "Main Pawn Attributes",
        .field_type = .Int32LE,
        .min_value = 1,
        .max_value = 99999,
    },
    // Critical Items
    .{
        .key_name = "Items.Ferrystones",
        .display_title = "Ferrystones (Teleportation // Item 81)",
        .sanskrit_title = "सेतु प्रस्तर (Ferrystone)",
        .category = "Key Items",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Items.Wakestones",
        .display_title = "Wakestones (Resurrection // Item 82)",
        .sanskrit_title = "पुनरुज्जीवन प्रस्तर (Wakestone)",
        .category = "Key Items",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
    .{
        .key_name = "Items.AllhealElixirs",
        .display_title = "Allheal Elixirs (Full Recovery // Item 3)",
        .sanskrit_title = "सर्वसंजीवनी रस (Allheal Elixir)",
        .category = "Consumables",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 999,
    },
};

// ============================================================================
// RESIDENT EVIL 4 REMAKE — CAPCOM RE ENGINE (भैरव आगम)
// Steam AppID: 2050650
// ============================================================================
pub const RE4_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Player.Pesetas",
        .display_title = "Pesetas (PTAS // मुद्रा)",
        .sanskrit_title = "सुवर्ण मुद्रा (Pesetas)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Player.Spinels",
        .display_title = "Spinel Jewels (स्पिनेल)",
        .sanskrit_title = "रत्न मुद्रा (Spinels)",
        .category = "Trade",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999,
    },
    .{
        .key_name = "Player.CP",
        .display_title = "Completion Points (CP)",
        .sanskrit_title = "सिद्धि बिन्दु (CP)",
        .category = "Extra Content",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
    .{
        .key_name = "Leon.CurrentHP",
        .display_title = "Leon Current Health",
        .sanskrit_title = "लियोन प्राण शक्ति (Current HP)",
        .category = "Player Stats",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 2500,
    },
    .{
        .key_name = "Leon.MaxHP",
        .display_title = "Leon Max Health",
        .sanskrit_title = "लियोन परम प्राण (Max HP)",
        .category = "Player Stats",
        .field_type = .Int32LE,
        .min_value = 1000,
        .max_value = 2500,
    },
};

// ============================================================================
// MONSTER HUNTER WILDS — CAPCOM RE ENGINE (महिषमर्दिनी आगम)
// Steam AppID: 2246340
// ============================================================================
pub const RE_MHW_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Hunter.Zenny",
        .display_title = "Zenny (z // ज़ेनी मुद्रा)",
        .sanskrit_title = "शिकारी धनम् (Zenny)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Hunter.ResearchPoints",
        .display_title = "Research Points (RP)",
        .sanskrit_title = "अनुसन्धान बिन्दु (Research Points)",
        .category = "Research",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
};

// ============================================================================
// MONSTER HUNTER RISE — CAPCOM RE ENGINE (कामरूप आगम)
// Steam AppID: 1446780
// ============================================================================
pub const RE_MHR_RULES = [_]KnownFieldRule{
    .{
        .key_name = "Hunter.Zenny",
        .display_title = "Zenny (z // ज़ेनी मुद्रा)",
        .sanskrit_title = "शिकारी धनम् (Zenny)",
        .category = "Economy",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 99999999,
    },
    .{
        .key_name = "Hunter.KamuraPoints",
        .display_title = "Kamura Points (कमूरा बिन्दु)",
        .sanskrit_title = "कमूरा बिन्दु (Kamura Points)",
        .category = "Village",
        .field_type = .Int32LE,
        .min_value = 0,
        .max_value = 9999999,
    },
};

pub const BUILTIN_PROFILES = [_]GameProfile{
    .{
        .id = "suzerain_rizia",
        .title = "SUZERAIN // Rizia DLC (King Romus Toras)",
        .sanskrit_title = "सुज़ेरैन — रिज़िया साम्राज्य (प्रमाण आगम)",
        .campaign_name = "StoryPack_Rizia",
        .filename_pattern = "",
        .magic_signature = null,
        .is_key_based = true,
        .rules = &SUZERAIN_RIZIA_RULES,
    },
    .{
        .id = "suzerain_sordland",
        .title = "SUZERAIN // Sordland (President Anton Rayne)",
        .sanskrit_title = "सुज़ेरैन — सोर्डलैण्ड प्रजातन्त्र (प्रमाण आगम)",
        .campaign_name = "StoryPack_Main",
        .filename_pattern = "",
        .magic_signature = null,
        .is_key_based = true,
        .rules = &SUZERAIN_SORDLAND_RULES,
    },
    .{
        .id = "mele1",
        .title = "MASS EFFECT 1 // Legendary Edition (BioWare Unreal // प्रमाण आगम)",
        .sanskrit_title = "महा प्रभाव १ — लीजेंडरी संस्करण (प्रमाण आगम)",
        .campaign_name = "MELE1_Main",
        .filename_pattern = ".pcsav",
        .magic_signature = &[_]u8{ 0xC1, 0x83, 0x2A, 0x9E },
        .is_key_based = false,
        .rules = &MELE1_RULES,
    },
    .{
        .id = "mele2",
        .title = "MASS EFFECT 2 // Legendary Edition (BioWare Unreal // प्रमाण आगम)",
        .sanskrit_title = "महा प्रभाव २ — लीजेंडरी संस्करण (प्रमाण आगम)",
        .campaign_name = "MELE2_Main",
        .filename_pattern = ".pcsav",
        .magic_signature = null,
        .is_key_based = false,
        .rules = &MELE2_RULES,
    },
    .{
        .id = "mele3",
        .title = "MASS EFFECT 3 // Legendary Edition (BioWare Unreal // प्रमाण आगम)",
        .sanskrit_title = "महा प्रभाव ३ — लीजेंडरी संस्करण (प्रमाण आगम)",
        .campaign_name = "MELE3_Main",
        .filename_pattern = ".pcsav",
        .magic_signature = null,
        .is_key_based = false,
        .rules = &MELE3_RULES,
    },
    .{
        .id = "dd2",
        .title = "DRAGON'S DOGMA 2 // Capcom RE Engine (व्याघ्रेश्वर आगम)",
        .sanskrit_title = "व्याघ्रेश्वर आगम — ड्रैगन्स डोग्मा २ (Capcom RE Engine)",
        .campaign_name = "DD2_MainSlot",
        .filename_pattern = "data001Slot.bin",
        .magic_signature = "DSSS",
        .is_key_based = false,
        .rules = &DD2_RULES,
    },
    .{
        .id = "re4",
        .title = "RESIDENT EVIL 4 REMAKE // Capcom RE Engine (भैरव आगम)",
        .sanskrit_title = "भैरव आगम — रेजिडेंट ईविल ४ (Capcom RE Engine)",
        .campaign_name = "RE4_Main",
        .filename_pattern = ".bin",
        .magic_signature = "DSSS",
        .is_key_based = false,
        .rules = &RE4_RULES,
    },
    .{
        .id = "re_mhw",
        .title = "MONSTER HUNTER WILDS // Capcom RE Engine (महिषमर्दिनी आगम)",
        .sanskrit_title = "महिषमर्दिनी आगम — मॉन्स्टर हंटर वाइल्ड्स (Capcom RE Engine)",
        .campaign_name = "MHW_Main",
        .filename_pattern = ".bin",
        .magic_signature = "DSSS",
        .is_key_based = false,
        .rules = &RE_MHW_RULES,
    },
    .{
        .id = "re_mhr",
        .title = "MONSTER HUNTER RISE // Capcom RE Engine (कामरूप आगम)",
        .sanskrit_title = "कामरूप आगम — मॉन्स्टर हंटर राइज़ (Capcom RE Engine)",
        .campaign_name = "MHR_Main",
        .filename_pattern = ".bin",
        .magic_signature = "DSSS",
        .is_key_based = false,
        .rules = &RE_MHR_RULES,
    },
};

/// Returns a matching profile if one has been registered in the Agama temple registry.
pub fn findMatchingProfile(filename: []const u8, content_or_header: []const u8) ?*const GameProfile {
    for (&BUILTIN_PROFILES) |*prof| {
        if (prof.matchesFile(filename, content_or_header)) {
            return prof;
        }
    }
    return null;
}

test "Agama Profiles - Suzerain Detection and Differentiation" {
    // 1. Mock Suzerain Rizia Save
    const rizia_mock =
        \\{
        \\    "currentStoryPack": "StoryPack_Rizia",
        \\    "campaignName": "NG1",
        \\    "variables": "Variable={[\"RiziaDLC.Resources_Budget\"]=25, [\"RiziaDLC.Resources_Authority\"]=15}"
        \\}
    ;

    const rizia_prof = findMatchingProfile("FinalSave.json", rizia_mock);
    try std.testing.expect(rizia_prof != null);
    try std.testing.expectEqualStrings("suzerain_rizia", rizia_prof.?.id);
    try std.testing.expect(rizia_prof.?.is_key_based);
    try std.testing.expectEqual(@as(usize, 45), rizia_prof.?.rules.len);

    // 2. Mock Suzerain Sordland Save
    const sordland_mock =
        \\{
        \\    "currentStoryPack": "StoryPack_Main",
        \\    "campaignName": "BaseGame",
        \\    "variables": "Variable={[\"BaseGame.GovernmentBudget\"]=10, [\"BaseGame.PersonalWealth\"]=5}"
        \\}
    ;

    const sordland_prof = findMatchingProfile("ActiveSave.json", sordland_mock);
    try std.testing.expect(sordland_prof != null);
    try std.testing.expectEqualStrings("suzerain_sordland", sordland_prof.?.id);
    try std.testing.expect(sordland_prof.?.is_key_based);
    try std.testing.expectEqual(@as(usize, 41), sordland_prof.?.rules.len);

    // 3. Generic unknown file must NOT match
    const unknown_mock = "DATA_STREAM_HEADER_RAW_BYTES";
    const unknown_prof = findMatchingProfile("unknown.dat", unknown_mock);
    try std.testing.expect(unknown_prof == null);

    // 4. Mass Effect 1 Legendary Edition (.pcsav + 0x9E2A83C1)
    const mele1_header = [_]u8{ 0xC1, 0x83, 0x2A, 0x9E, 0x00, 0x00, 0x04, 0x00 };
    const mele1_prof = findMatchingProfile("Save_0001.pcsav", &mele1_header);
    try std.testing.expect(mele1_prof != null);
    try std.testing.expectEqualStrings("mele1", mele1_prof.?.id);
    try std.testing.expectEqual(@as(usize, 11), mele1_prof.?.rules.len);

    // 5. Mass Effect 2 Legendary Edition (.pcsav + version 30)
    const mele2_header = [_]u8{ 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const mele2_prof = findMatchingProfile("Save_0002.pcsav", &mele2_header);
    try std.testing.expect(mele2_prof != null);
    try std.testing.expectEqualStrings("mele2", mele2_prof.?.id);
    try std.testing.expectEqual(@as(usize, 15), mele2_prof.?.rules.len);

    // 6. Mass Effect 3 Legendary Edition (.pcsav + version 59)
    const mele3_header = [_]u8{ 0x3B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const mele3_prof = findMatchingProfile("Save_0003.pcsav", &mele3_header);
    try std.testing.expect(mele3_prof != null);
    try std.testing.expectEqualStrings("mele3", mele3_prof.?.id);
    try std.testing.expectEqual(@as(usize, 14), mele3_prof.?.rules.len);

    // 7. Non-LE original Mass Effect 2 (version 29): MUST NOT MATCH MELE
    const orig_me2_header = [_]u8{ 0x1D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const orig_me2_prof = findMatchingProfile("Save_0002.pcsav", &orig_me2_header);
    try std.testing.expect(orig_me2_prof == null);

    // 8. Non-pcsav file with MELE header must NOT match
    const non_pcsav_prof = findMatchingProfile("Save_0001.dat", &mele1_header);
    try std.testing.expect(non_pcsav_prof == null);

    // 9. Dragon's Dogma 2 (DSSS + version 2 + data001Slot.bin)
    const dd2_header = [_]u8{ 'D', 'S', 'S', 'S', 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const dd2_prof = findMatchingProfile("data001Slot.bin", &dd2_header);
    try std.testing.expect(dd2_prof != null);
    try std.testing.expectEqualStrings("dd2", dd2_prof.?.id);
    try std.testing.expectEqual(@as(usize, 23), dd2_prof.?.rules.len);

    // 10. Resident Evil 4 Remake (DSSS + version 2 + re4 in path)
    const re4_prof = findMatchingProfile("re4_data000.bin", &dd2_header);
    try std.testing.expect(re4_prof != null);
    try std.testing.expectEqualStrings("re4", re4_prof.?.id);
    try std.testing.expectEqual(@as(usize, 5), re4_prof.?.rules.len);

    // 11. Monster Hunter Wilds (DSSS + version 2 + wilds / mhw in path)
    const mhw_prof = findMatchingProfile("mhw_data001.bin", &dd2_header);
    try std.testing.expect(mhw_prof != null);
    try std.testing.expectEqualStrings("re_mhw", mhw_prof.?.id);

    // 12. Non-DSSS file must NOT match RE Engine
    const fake_re_header = [_]u8{ 'X', 'S', 'S', 'S', 0x02, 0x00, 0x00, 0x00 };
    const fake_re_prof = findMatchingProfile("data001Slot.bin", &fake_re_header);
    try std.testing.expect(fake_re_prof == null);

    // 13. DSSS container with unsupported version (e.g., version 1) must NOT match
    const fake_ver_header = [_]u8{ 'D', 'S', 'S', 'S', 0x01, 0x00, 0x00, 0x00 };
    const fake_ver_prof = findMatchingProfile("data001Slot.bin", &fake_ver_header);
    try std.testing.expect(fake_ver_prof == null);
}
