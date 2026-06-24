--[[
    iddqd - Auto Marking NPC Dataset

    Schema (v1.1):
        ns.autoMarkingNPCs[raidKey] = {
            groups = {                          -- optional; UI grouping/collapsibles
                { id, name, order, children? }, -- children = nested sub-groups
                ...
            },
            npcs = {
                { id, name, boss, order, groupId? }, -- groupId references a group OR sub-group id
                ...
            },
        }

    UI-only: marking logic does NOT consume this file. Rendered three levels:
    group -> sub-group -> npc. NPCs whose groupId matches a top-level group
    render at level 1, above any sub-group headers within that group.

    Sort within each level: order ASC, then name ASC.
]]

local ADDON, ns = ...

ns.autoMarkingNPCs = {
    -- =========================================================================
    -- Karazhan (full v1.1 expansion: groups + sub-groups + 49 NPCs)
    -- =========================================================================
    kara = {
        groups = {
            { id = "stables",      name = "Servants Quarters / Stables",        order =   5 },
            { id = "attumen",      name = "Attumen Encounter",                  order =  10 },
            { id = "moroes",       name = "Moroes",                             order =  20 },
            { id = "maiden",       name = "Maiden of Virtue",                   order =  35 },
            { id = "opera",        name = "Opera Event",                        order =  50,
              children = {
                  { id = "opera_oz",  name = "Wizard of Oz",          order = 1 },
                  { id = "opera_rrh", name = "Red Riding Hood",       order = 2 },
                  { id = "opera_rj",  name = "Romulo and Julianne",   order = 3 },
              },
            },
            { id = "nightbane",    name = "Nightbane",                          order =  80 },
            { id = "curator",      name = "The Curator",                        order =  90 },
            { id = "illhoof_aran", name = "Terestian Illhoof / Shade of Aran",  order = 100 },
            { id = "netherspite",  name = "Netherspite",                        order = 120 },
            { id = "malchezaar",   name = "Prince Malchezaar",                  order = 130 },
        },
        npcs = {
            -- Stables (Servants Quarters rares omitted: NPC IDs unverified)
            { id = 15547, name = "Spectral Charger",            boss = false, order = 5,  groupId = "stables" },
            { id = 15548, name = "Spectral Stallion",           boss = false, order = 5,  groupId = "stables" },
            { id = 16407, name = "Spectral Servant",            boss = false, order = 6,  groupId = "stables" },

            -- Attumen Encounter (one fight, two NPCs share the header)
            { id = 16151, name = "Midnight",                    boss = true,  order = 1,  groupId = "attumen" },
            { id = 15550, name = "Attumen the Huntsman",        boss = true,  order = 2,  groupId = "attumen" },

            -- Moroes (banquet trash + Moroes himself + 6 dinner-party guests)
            { id = 16408, name = "Phantom Valet",               boss = false, order = 1,  groupId = "moroes" },
            { id = 16409, name = "Phantom Guest",               boss = false, order = 2,  groupId = "moroes" },
            { id = 16415, name = "Skeletal Waiter",             boss = false, order = 3,  groupId = "moroes" },
            { id = 15687, name = "Moroes",                      boss = true,  order = 5,  groupId = "moroes" },
            { id = 17007, name = "Lady Keira Berrybuck",        boss = false, order = 6,  groupId = "moroes" },
            { id = 19872, name = "Lady Catriona Von'Indi",      boss = false, order = 7,  groupId = "moroes" },
            { id = 19873, name = "Lord Crispin Ference",        boss = false, order = 8,  groupId = "moroes" },
            { id = 19874, name = "Baron Rafe Dreuger",          boss = false, order = 9,  groupId = "moroes" },
            { id = 19875, name = "Baroness Dorothea Millstipe", boss = false, order = 10, groupId = "moroes" },
            { id = 19876, name = "Lord Robin Daris",            boss = false, order = 11, groupId = "moroes" },

            -- Maiden of Virtue (pre-Maiden trash + Maiden)
            { id = 16424, name = "Spectral Sentry",             boss = false, order = 1,  groupId = "maiden" },
            { id = 16425, name = "Phantom Guardsman",           boss = false, order = 2,  groupId = "maiden" },
            { id = 16457, name = "Maiden of Virtue",            boss = true,  order = 5,  groupId = "maiden" },

            -- Opera Event: pre-Opera trash sits at the top-level "opera"
            -- group, above the three roster sub-groups.
            { id = 16471, name = "Skeletal Usher",              boss = false, order = 1,  groupId = "opera" },
            { id = 16472, name = "Phantom Stagehand",           boss = false, order = 2,  groupId = "opera" },
            { id = 16473, name = "Spectral Performer",          boss = false, order = 3,  groupId = "opera" },

            -- Opera roster: Wizard of Oz
            { id = 17535, name = "Dorothee",                    boss = true,  order = 1,  groupId = "opera_oz" },
            { id = 17548, name = "Tito",                        boss = true,  order = 2,  groupId = "opera_oz" },
            { id = 17543, name = "Strawman",                    boss = true,  order = 3,  groupId = "opera_oz" },
            { id = 17547, name = "Tinhead",                     boss = true,  order = 4,  groupId = "opera_oz" },
            { id = 17546, name = "Roar",                        boss = true,  order = 5,  groupId = "opera_oz" },
            { id = 18168, name = "The Crone",                   boss = true,  order = 6,  groupId = "opera_oz" },

            -- Opera roster: Red Riding Hood (single NPC)
            { id = 17521, name = "The Big Bad Wolf",            boss = true,  order = 1,  groupId = "opera_rrh" },

            -- Opera roster: Romulo and Julianne (paired under one sub-group)
            { id = 17533, name = "Romulo",                      boss = true,  order = 1,  groupId = "opera_rj" },
            { id = 17534, name = "Julianne",                    boss = true,  order = 2,  groupId = "opera_rj" },

            -- Nightbane (library trash on the path + Nightbane summon)
            { id = 16470, name = "Ghostly Philanthropist",      boss = false, order = 1,  groupId = "nightbane" },
            { id = 16481, name = "Ghastly Haunt",               boss = false, order = 2,  groupId = "nightbane" },
            { id = 16482, name = "Trapped Soul",                boss = false, order = 3,  groupId = "nightbane" },
            { id = 17225, name = "Nightbane",                   boss = true,  order = 5,  groupId = "nightbane" },

            -- The Curator (pre-Curator CC trash + Curator)
            { id = 16485, name = "Arcane Watchman",             boss = false, order = 1,  groupId = "curator" },
            { id = 16488, name = "Arcane Anomaly",              boss = false, order = 2,  groupId = "curator" },
            { id = 15691, name = "The Curator",                 boss = true,  order = 5,  groupId = "curator" },

            -- Illhoof / Aran (shared library/study path; both bosses share group)
            { id = 16504, name = "Arcane Protector",            boss = false, order = 1,  groupId = "illhoof_aran" },
            { id = 16491, name = "Mana Feeder",                 boss = false, order = 2,  groupId = "illhoof_aran" },
            { id = 16529, name = "Magical Horror",              boss = false, order = 3,  groupId = "illhoof_aran" },
            { id = 16525, name = "Spell Shade",                 boss = false, order = 4,  groupId = "illhoof_aran" },
            { id = 16540, name = "Shadow Pillager",             boss = false, order = 5,  groupId = "illhoof_aran" },
            { id = 15688, name = "Terestian Illhoof",           boss = true,  order = 10, groupId = "illhoof_aran" },
            { id = 16524, name = "Shade of Aran",               boss = true,  order = 11, groupId = "illhoof_aran" },

            -- Netherspite (astronomer trash + Netherspite)
            { id = 16526, name = "Sorcerous Shade",             boss = false, order = 1,  groupId = "netherspite" },
            { id = 16544, name = "Ethereal Thief",              boss = false, order = 2,  groupId = "netherspite" },
            { id = 16545, name = "Ethereal Spellfilcher",       boss = false, order = 3,  groupId = "netherspite" },
            { id = 15689, name = "Netherspite",                 boss = true,  order = 5,  groupId = "netherspite" },

            -- Prince Malchezaar (pre-Prince fleshbeast trash + Prince)
            { id = 16596, name = "Greater Fleshbeast",          boss = false, order = 1,  groupId = "malchezaar" },
            { id = 16595, name = "Fleshbeast",                  boss = false, order = 2,  groupId = "malchezaar" },
            { id = 15690, name = "Prince Malchezaar",           boss = true,  order = 5,  groupId = "malchezaar" },
        },
    },

    -- =========================================================================
    -- Other 8 raids: v1.0 flat NPC lists migrated to {groups, npcs} shape with
    -- groupId = nil. UI renders these under a synthetic single bucket.
    -- =========================================================================
    -- =========================================================================
    -- Gruul's Lair (boss + Maulgar council + trash/adds)
    -- IDs verified by Wowhead spot-checks (June 2026).
    -- =========================================================================
    gruul = {
        groups = {
            { id = "general", name = "General Gruul's Lair trash", order =  5 },
            { id = "maulgar", name = "High King Maulgar",          order = 10 },
            { id = "gruul",   name = "Gruul the Dragonkiller",     order = 20 },
        },
        npcs = {
            -- General trash
            { id = 19389, name = "Lair Brute",               boss = false, order = 2, groupId = "general" },
            { id = 21350, name = "Gronn-Priest",             boss = false, order = 3, groupId = "general" },

            -- High King Maulgar + 4 council members + Wild Fel Stalker add
            { id = 18831, name = "High King Maulgar",        boss = true,  order = 5, groupId = "maulgar" },
            { id = 18832, name = "Krosh Firehand",           boss = false, order = 6, groupId = "maulgar" },
            { id = 18834, name = "Olm the Summoner",         boss = false, order = 7, groupId = "maulgar" },
            { id = 18835, name = "Kiggler the Crazed",       boss = false, order = 8, groupId = "maulgar" },
            { id = 18836, name = "Blindeye the Seer",        boss = false, order = 9, groupId = "maulgar" },
            { id = 18847, name = "Wild Fel Stalker",         boss = false, order = 10, groupId = "maulgar" },

            -- Gruul the Dragonkiller
            { id = 19044, name = "Gruul the Dragonkiller",   boss = true,  order = 5, groupId = "gruul" },
        },
    },

    -- =========================================================================
    -- Magtheridon's Lair (boss + P1 channelers + Burning Abyssal adds + trash)
    -- IDs verified by Wowhead spot-checks (May 2026).
    -- =========================================================================
    mag = {
        groups = {
            { id = "general", name = "General Magtheridon's Lair trash", order =  5 },
            { id = "mag",     name = "Magtheridon",                       order = 10 },
        },
        npcs = {
            -- General trash
            { id = 18829, name = "Hellfire Warder",          boss = false, order = 1, groupId = "general" },

            -- Magtheridon + P1 channelers + P2 Burning Abyssal adds
            { id = 17256, name = "Hellfire Channeler",       boss = false, order = 1, groupId = "mag" },
            { id = 17257, name = "Magtheridon",              boss = true,  order = 5, groupId = "mag" },
            { id = 17454, name = "Burning Abyssal",          boss = false, order = 6, groupId = "mag" },
        },
    },
    -- =========================================================================
    -- Serpentshrine Cavern (trash placed by raid progression path, not by
    -- Wowhead listing). All NPC IDs verified by position-pairing the Wowhead
    -- zone NPC table's "Copy Name" + "Copy ID" output (May 2026). Trash
    -- placement follows raid clearing order, not just where Wowhead lists.
    -- "General" group is gone -- every mob now belongs to the boss whose
    -- approach path it occupies.
    -- =========================================================================
    ssc = {
        groups = {
            { id = "hydross",    name = "Hydross the Unstable",   order = 10 },
            { id = "lurker",     name = "The Lurker Below",       order = 20 },
            { id = "leo",        name = "Leotheras the Blind",    order = 30 },
            { id = "karathress", name = "Fathom-Lord Karathress", order = 40 },
            { id = "morogrim",   name = "Morogrim Tidewalker",    order = 50 },
            { id = "vashj",      name = "Lady Vashj",             order = 60 },
        },
        npcs = {
            -- Hydross the Unstable. Trash, then (gap) boss + spawns.
            { id = 21339, name = "Coilfang Hate-Screamer",   boss = false, order = 1, groupId = "hydross" },
            { id = 21246, name = "Serpentshrine Sporebat",   boss = false, order = 2, groupId = "hydross" },
            { id = 21221, name = "Coilfang Beast-Tamer",     boss = false, order = 3, groupId = "hydross" },
            { id = 21251, name = "Underbog Colossus",        boss = false, order = 4, groupId = "hydross" },
            { id = 22352, name = "Colossus Rager",           boss = false, order = 5, groupId = "hydross" },
            { id = 22347, name = "Colossus Lurker",          boss = false, order = 6, groupId = "hydross" },
            { id = 21216, name = "Hydross the Unstable",     boss = true,  fight = true, order = 1, groupId = "hydross" },
            { id = 22036, name = "Tainted Spawn of Hydross", boss = false, fight = true, order = 2, groupId = "hydross" },
            { id = 22035, name = "Pure Spawn of Hydross",    boss = false, fight = true, order = 3, groupId = "hydross" },

            -- The Lurker Below. Trash, then (gap) boss + the two Coilfang adds.
            { id = 21220, name = "Coilfang Priestess",       boss = false, order = 1, groupId = "lurker" },
            { id = 21301, name = "Coilfang Shatterer",       boss = false, order = 2, groupId = "lurker" },
            { id = 21218, name = "Vashj'ir Honor Guard",     boss = false, order = 3, groupId = "lurker" },
            { id = 21263, name = "Greyheart Technician",     boss = false, order = 4, groupId = "lurker" },
            { id = 21217, name = "The Lurker Below",         boss = true,  fight = true, order = 1, groupId = "lurker" },
            { id = 21873, name = "Coilfang Guardian",        boss = false, fight = true, order = 2, groupId = "lurker" },
            { id = 21865, name = "Coilfang Ambusher",        boss = false, fight = true, order = 3, groupId = "lurker" },

            -- Leotheras the Blind. Trash (incl. the Tidecaller's totem), then (gap) boss + adds.
            { id = 21230, name = "Greyheart Nether-Mage",    boss = false, order = 1,  groupId = "leo" },
            { id = 21229, name = "Greyheart Tidecaller",     boss = false, order = 2,  groupId = "leo" },
            { id = 22236, name = "Water Elemental Totem",    boss = false, order = 3,  groupId = "leo" },
            { id = 22238, name = "Serpentshrine Tidecaller", boss = false, order = 4,  groupId = "leo" },
            { id = 21298, name = "Coilfang Serpentguard",    boss = false, order = 5,  groupId = "leo" },
            { id = 21232, name = "Greyheart Skulker",        boss = false, order = 6,  groupId = "leo" },
            { id = 21299, name = "Coilfang Fathom-Witch",    boss = false, order = 7,  groupId = "leo" },
            { id = 21863, name = "Serpentshrine Lurker",     boss = false, order = 8,  groupId = "leo" },
            { id = 22250, name = "Rancid Mushroom",          boss = false, order = 9,  groupId = "leo" },
            { id = 21231, name = "Greyheart Shield-Bearer",  boss = false, order = 10, groupId = "leo" },
            { id = 21215, name = "Leotheras the Blind",      boss = true,  fight = true, order = 1, groupId = "leo" },
            { id = 21806, name = "Greyheart Spellbinder",    boss = false, fight = true, order = 2, groupId = "leo" },
            { id = 21857, name = "Inner Demon",              boss = false, fight = true, order = 3, groupId = "leo" },
            { id = 21875, name = "Shadow of Leotheras",      boss = false, fight = true, order = 4, groupId = "leo" },

            -- Fathom-Lord Karathress. All fight (no trash): boss + 3 advisors + their pets/totem.
            { id = 21214, name = "Fathom-Lord Karathress",   boss = true,  fight = true, order = 1, groupId = "karathress" },
            { id = 21964, name = "Fathom-Guard Caribdis",    boss = false, fight = true, order = 2, groupId = "karathress" },
            { id = 21966, name = "Fathom-Guard Sharkkis",    boss = false, fight = true, order = 3, groupId = "karathress" },
            { id = 22120, name = "Fathom Sporebat",          boss = false, fight = true, order = 4, groupId = "karathress" },
            { id = 22119, name = "Fathom Lurker",            boss = false, fight = true, order = 5, groupId = "karathress" },
            { id = 21965, name = "Fathom-Guard Tidalvess",   boss = false, fight = true, order = 6, groupId = "karathress" },
            { id = 22091, name = "Spitfire Totem",           boss = false, fight = true, order = 7, groupId = "karathress" },

            -- Morogrim Tidewalker. Trash, then (gap) boss.
            { id = 21226, name = "Tidewalker Shaman",        boss = false, order = 1, groupId = "morogrim" },
            { id = 21225, name = "Tidewalker Warrior",       boss = false, order = 2, groupId = "morogrim" },
            { id = 21224, name = "Tidewalker Depth-Seer",    boss = false, order = 3, groupId = "morogrim" },
            { id = 21227, name = "Tidewalker Harpooner",     boss = false, order = 4, groupId = "morogrim" },
            { id = 21228, name = "Tidewalker Hydromancer",   boss = false, order = 5, groupId = "morogrim" },
            { id = 21213, name = "Morogrim Tidewalker",      boss = true,  fight = true, order = 1, groupId = "morogrim" },

            -- Lady Vashj. All fight (no trash): corridor elites + P2/P3 adds + boss.
            { id = 22055, name = "Coilfang Elite",           boss = false, fight = true, order = 1, groupId = "vashj" },
            { id = 22056, name = "Coilfang Strider",         boss = false, fight = true, order = 2, groupId = "vashj" },
            { id = 22140, name = "Toxic Sporebat",           boss = false, fight = true, order = 3, groupId = "vashj" },
            { id = 22009, name = "Tainted Elemental",        boss = false, fight = true, order = 4, groupId = "vashj" },
            { id = 21212, name = "Lady Vashj",               boss = true,  fight = true, order = 5, groupId = "vashj" },
        },
    },

    -- =========================================================================
    -- Tempest Keep (trash placed by raid progression path, not by Wowhead
    -- listing). NPC IDs verified by position-pairing the Wowhead zone NPC
    -- table. Cross-zone mobs (Doomguard, Mr. Pinchy, Imp, etc.) excluded.
    -- "General" group is gone -- every mob now belongs to the boss whose
    -- approach path it occupies.
    -- =========================================================================
    tk = {
        groups = {
            { id = "alar",       name = "Al'ar",                     order = 10 },
            { id = "voidreaver", name = "Void Reaver",               order = 20 },
            { id = "solarian",   name = "High Astromancer Solarian", order = 30 },
            { id = "kael",       name = "Kael'thas Sunstrider",      order = 40,
              children = {
                  { id = "kael_advisors", name = "Advisors",       order = 1 },
                  { id = "kael_weapons",  name = "Kael's Weapons",  order = 2 },
              },
            },
        },
        npcs = {
            -- Al'ar. Trash, then (gap) boss + Ember.
            { id = 20034, name = "Star Scryer",                boss = false, order = 1, groupId = "alar" },
            { id = 20033, name = "Astromancer",                boss = false, order = 2, groupId = "alar" },
            { id = 20032, name = "Bloodwarder Vindicator",     boss = false, order = 3, groupId = "alar" },
            { id = 20031, name = "Bloodwarder Legionnaire",    boss = false, order = 4, groupId = "alar" },
            { id = 20036, name = "Bloodwarder Squire",         boss = false, order = 5, groupId = "alar" },
            { id = 20035, name = "Bloodwarder Marshal",        boss = false, order = 6, groupId = "alar" },
            { id = 20037, name = "Tempest Falconer",           boss = false, order = 7, groupId = "alar" },
            { id = 20038, name = "Phoenix-Hawk Hatchling",     boss = false, order = 8, groupId = "alar" },
            { id = 20039, name = "Phoenix-Hawk",               boss = false, order = 9, groupId = "alar" },
            { id = 19514, name = "Al'ar",                      boss = true,  fight = true, order = 1, groupId = "alar" },
            { id = 19551, name = "Ember of Al'ar",             boss = false, fight = true, order = 2, groupId = "alar" },

            -- Void Reaver. Trash, then (gap) boss.
            { id = 20040, name = "Crystalcore Devastator",     boss = false, order = 1, groupId = "voidreaver" },
            { id = 20041, name = "Crystalcore Sentinel",       boss = false, order = 2, groupId = "voidreaver" },
            { id = 20042, name = "Tempest-Smith",              boss = false, order = 3, groupId = "voidreaver" },
            { id = 20052, name = "Crystalcore Mechanic",       boss = false, order = 4, groupId = "voidreaver" },
            { id = 19516, name = "Void Reaver",                boss = true,  fight = true, order = 1, groupId = "voidreaver" },

            -- High Astromancer Solarian. Trash, then (gap) Solarium Priest + boss.
            { id = 20046, name = "Astromancer Lord",           boss = false, order = 1, groupId = "solarian" },
            { id = 20045, name = "Nether Scryer",              boss = false, order = 2, groupId = "solarian" },
            { id = 18806, name = "Solarium Priest",            boss = false, fight = true, order = 1, groupId = "solarian" },
            { id = 18805, name = "High Astromancer Solarian",  boss = true,  fight = true, order = 2, groupId = "solarian" },

            -- Kael'thas Sunstrider. Crimson Hand trash, then (gap) boss + phoenixes (direct),
            -- with the Advisors + Weapons sub-groups below.
            { id = 20050, name = "Crimson Hand Inquisitor",    boss = false, order = 1, groupId = "kael" },
            { id = 20047, name = "Crimson Hand Battle Mage",   boss = false, order = 2, groupId = "kael" },
            { id = 20049, name = "Crimson Hand Blood Knight",  boss = false, order = 3, groupId = "kael" },
            { id = 20048, name = "Crimson Hand Centurion",     boss = false, order = 4, groupId = "kael" },
            { id = 19622, name = "Kael'thas Sunstrider",       boss = true,  fight = true, order = 1, groupId = "kael" },
            { id = 21362, name = "Phoenix",                    boss = false, fight = true, order = 2, groupId = "kael" },
            { id = 21364, name = "Phoenix Egg",                boss = false, fight = true, order = 3, groupId = "kael" },

            -- Advisors (P2 sequence) — sub-group under Kael.
            { id = 20064, name = "Thaladred the Darkener",     boss = false, fight = true, order = 1, groupId = "kael_advisors" },
            { id = 20060, name = "Lord Sanguinar",             boss = false, fight = true, order = 2, groupId = "kael_advisors" },
            { id = 20062, name = "Grand Astromancer Capernian",boss = false, fight = true, order = 3, groupId = "kael_advisors" },
            { id = 20063, name = "Master Engineer Telonicus",  boss = false, fight = true, order = 4, groupId = "kael_advisors" },

            -- Kael's Weapons (P3 legendary throw) — sub-group under Kael.
            { id = 21270, name = "Cosmic Infuser",             boss = false, fight = true, order = 1, groupId = "kael_weapons" },
            { id = 21269, name = "Devastation",                boss = false, fight = true, order = 2, groupId = "kael_weapons" },
            { id = 21271, name = "Infinity Blades",            boss = false, fight = true, order = 3, groupId = "kael_weapons" },
            { id = 21268, name = "Netherstrand Longbow",       boss = false, fight = true, order = 4, groupId = "kael_weapons" },
            { id = 21273, name = "Phaseshift Bulwark",         boss = false, fight = true, order = 5, groupId = "kael_weapons" },
            { id = 21274, name = "Staff of Disintegration",    boss = false, fight = true, order = 6, groupId = "kael_weapons" },
            { id = 21272, name = "Warp Slicer",                boss = false, fight = true, order = 7, groupId = "kael_weapons" },
        },
    },
    hyjal = {
        infoSections = {
            {
                id = "hyjal_wave_info",
                title = "Trash Wave Info",
                order = 1,
                tables = {
                    {
                        title = "Rage Winterchill",
                        rows = {
                            { "W1", "10 Ghoul" },
                            { "W2", "10 Ghoul, 2 Crypt Fiend" },
                            { "W3", "6 Ghoul, 6 Crypt Fiend" },
                            { "W4", "6 Ghoul, 4 Crypt Fiend, 2 Necromancer" },
                            { "W5", "2 Ghoul, 6 Crypt Fiend, 4 Necromancer" },
                            { "W6", "6 Ghoul, 6 Abomination" },
                            { "W7", "4 Ghoul, 4 Necromancer, 4 Abomination" },
                            { "W8", "6 Ghoul, 4 Crypt Fiend, 2 Abomination, 2 Necromancer" },
                        },
                    },
                    {
                        title = "Anetheron",
                        rows = {
                            { "W1", "10 Ghoul" },
                            { "W2", "8 Ghoul, 4 Abomination" },
                            { "W3", "4 Ghoul, 4 Crypt Fiend, 4 Necromancer" },
                            { "W4", "4 Necromancer, 6 Crypt Fiend, 2 Banshee" },
                            { "W5", "6 Ghoul, 2 Necromancer, 4 Banshee" },
                            { "W6", "6 Ghoul, 2 Abomination, 4 Necromancer" },
                            { "W7", "4 Crypt Fiend, 4 Abomination, 4 Banshee, 2 Ghoul" },
                            { "W8", "3 Ghoul, 4 Abomination, 3 Crypt Fiend, 2 Banshee, 2 Necromancer" },
                        },
                    },
                    {
                        title = "Kaz'rogal",
                        rows = {
                            { "W1", "4 Ghoul, 4 Abomination, 2 Banshee, 2 Necromancer" },
                            { "W2", "4 Ghoul, 10 Gargoyle" },
                            { "W3", "6 Ghoul, 6 Crypt Fiend, 2 Necromancer" },
                            { "W4", "6 Crypt Fiend, 2 Necromancer, 6 Gargoyle" },
                            { "W5", "4 Ghoul, 6 Abomination, 4 Necromancer" },
                            { "W6", "8 Gargoyle, 1 Frost Wyrm" },
                            { "W7", "6 Ghoul, 4 Abomination, 1 Frost Wyrm" },
                            { "W8", "6 Ghoul, 4 Abomination, 2 Crypt Fiend, 2 Banshee, 2 Necromancer" },
                        },
                    },
                    {
                        title = "Azgalor",
                        rows = {
                            { "W1", "6 Abomination, 6 Necromancer" },
                            { "W2", "5 Ghoul, 8 Gargoyle, 1 Frost Wyrm" },
                            { "W3", "6 Ghoul, 8 Giant Infernal" },
                            { "W4", "6 Fel Stalker, 8 Giant Infernal" },
                            { "W5", "4 Abomination, 6 Fel Stalker, 4 Necromancer" },
                            { "W6", "6 Necromancer, 6 Banshee" },
                            { "W7", "2 Ghoul, 2 Crypt Fiend, 2 Fel Stalker, 8 Giant Infernal" },
                            { "W8", "4 Abomination, 4 Crypt Fiend, 4 Banshee, 2 Necromancer, 2 Fel Stalker" },
                        },
                    },
                },
            },
        },
        groups = {
            { id = "trash", name = "Trash",  order = 10 },
            { id = "boss",  name = "Bosses", order = 20 },
        },
        npcs = {
            -- Wave trash
            { id = 17895, name = "Ghoul",                boss = false, order = 1, groupId = "trash" },
            { id = 17897, name = "Crypt Fiend",          boss = false, order = 2, groupId = "trash" },
            { id = 17899, name = "Shadowy Necromancer",  boss = false, order = 3, groupId = "trash" },
            { id = 17898, name = "Abomination",          boss = false, order = 4, groupId = "trash" },
            { id = 17905, name = "Banshee",              boss = false, order = 5, groupId = "trash" },
            { id = 17906, name = "Gargoyle",             boss = false, order = 6, groupId = "trash" },
            { id = 17908, name = "Giant Infernal",       boss = false, order = 7, groupId = "trash" },
            { id = 17916, name = "Fel Stalker",          boss = false, order = 8, groupId = "trash" },
            { id = 17907, name = "Frost Wyrm",           boss = false, order = 9, groupId = "trash" },

            -- Bosses
            { id = 17767, name = "Rage Winterchill",     boss = true,  order = 1, groupId = "boss" },
            { id = 17808, name = "Anetheron",            boss = true,  order = 2, groupId = "boss" },
            { id = 17888, name = "Kaz'rogal",            boss = true,  order = 3, groupId = "boss" },
            { id = 17842, name = "Azgalor",              boss = true,  order = 4, groupId = "boss" },
            { id = 17968, name = "Archimonde",           boss = true,  order = 5, groupId = "boss" },
        },
    },
    bt = {
        groups = {},
        npcs = {
            { id = 22887, name = "High Warlord Naj'entus",      boss = true, order = 1 },
            { id = 22898, name = "Supremus",                    boss = true, order = 2 },
            { id = 22841, name = "Shade of Akama",              boss = true, order = 3 },
            { id = 22871, name = "Teron Gorefiend",             boss = true, order = 4 },
            { id = 22948, name = "Gurtogg Bloodboil",           boss = true, order = 5 },
            { id = 23418, name = "Essence of Suffering",        boss = true, order = 6 },
            { id = 23419, name = "Essence of Desire",           boss = true, order = 7 },
            { id = 23420, name = "Essence of Anger",            boss = true, order = 8 },
            { id = 22947, name = "Mother Shahraz",              boss = true, order = 9 },
            { id = 22949, name = "Gathios the Shatterer",       boss = true, order = 10 },
            { id = 22950, name = "High Nethermancer Zerevor",   boss = true, order = 11 },
            { id = 22951, name = "Lady Malande",                boss = true, order = 12 },
            { id = 22952, name = "Veras Darkshadow",            boss = true, order = 13 },
            { id = 22917, name = "Illidan Stormrage",           boss = true, order = 14 },
        },
    },
    za = {
        groups = {},
        npcs = {
            { id = 23576, name = "Nalorakk",                boss = true, order = 1 },
            { id = 23574, name = "Akil'zon",                boss = true, order = 2 },
            { id = 23578, name = "Jan'alai",                boss = true, order = 3 },
            { id = 23577, name = "Halazzi",                 boss = true, order = 4 },
            { id = 24239, name = "Hex Lord Malacrass",      boss = true, order = 5 },
            { id = 23863, name = "Zul'jin",                 boss = true, order = 6 },
        },
    },
    swp = {
        groups = {},
        npcs = {
            { id = 24850, name = "Kalecgos",                boss = true, order = 1 },
            { id = 24882, name = "Brutallus",               boss = true, order = 2 },
            { id = 25038, name = "Felmyst",                 boss = true, order = 3 },
            { id = 25166, name = "Grand Warlock Alythess",  boss = true, order = 4 },
            { id = 25165, name = "Lady Sacrolash",          boss = true, order = 5 },
            { id = 25741, name = "M'uru",                   boss = true, order = 6 },
            { id = 25315, name = "Kil'jaeden",              boss = true, order = 7 },
        },
    },
}

-- One-time sort at load: order ASC, name ASC. Applied to groups, sub-groups,
-- and npcs at every level.
local function sortByOrderThenName(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return tostring(a.name or a.title or "") < tostring(b.name or b.title or "")
end

for _, raid in pairs(ns.autoMarkingNPCs) do
    if raid.groups then
        table.sort(raid.groups, sortByOrderThenName)
        for _, group in ipairs(raid.groups) do
            if group.children then
                table.sort(group.children, sortByOrderThenName)
            end
        end
    end
    if raid.infoSections then
        table.sort(raid.infoSections, sortByOrderThenName)
    end
    if raid.npcs then
        table.sort(raid.npcs, sortByOrderThenName)
    end
end
