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
}
