-- Headless guard for the auto-marking NPC dataset.
local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = {}
assert(loadfile(DIR .. "Data/Static/AutoMarkingNPCs.lua"))("iddqd", ns)

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local expected = {
    ssc = {
        [22055] = "Coilfang Elite",
        [21339] = "Coilfang Hate-Screamer",
        [21220] = "Coilfang Priestess",
        [21214] = "Fathom-Lord Karathress",
        [21230] = "Greyheart Nether-Mage",
        [21216] = "Hydross the Unstable",
        [21215] = "Leotheras the Blind",
        [21213] = "Morogrim Tidewalker",
        [21217] = "The Lurker Below",
        [21226] = "Tidewalker Shaman",
        [21873] = "Coilfang Guardian",
        [21301] = "Coilfang Shatterer",
        [22056] = "Coilfang Strider",
        [21964] = "Fathom-Guard Caribdis",
        [21806] = "Greyheart Spellbinder",
        [21229] = "Greyheart Tidecaller",
        [21246] = "Serpentshrine Sporebat",
        [22036] = "Tainted Spawn of Hydross",
        [21225] = "Tidewalker Warrior",
        [21865] = "Coilfang Ambusher",
        [21221] = "Coilfang Beast-Tamer",
        [21966] = "Fathom-Guard Sharkkis",
        [21857] = "Inner Demon",
        [22035] = "Pure Spawn of Hydross",
        [21224] = "Tidewalker Depth-Seer",
        [22140] = "Toxic Sporebat",
        [21218] = "Vashj'ir Honor Guard",
        [22236] = "Water Elemental Totem",
        [22120] = "Fathom Sporebat",
        [21263] = "Greyheart Technician",
        [22238] = "Serpentshrine Tidecaller",
        [21875] = "Shadow of Leotheras",
        [22009] = "Tainted Elemental",
        [21227] = "Tidewalker Harpooner",
        [21251] = "Underbog Colossus",
        [21298] = "Coilfang Serpentguard",
        [22352] = "Colossus Rager",
        [22119] = "Fathom Lurker",
        [21212] = "Lady Vashj",
        [21228] = "Tidewalker Hydromancer",
        [22347] = "Colossus Lurker",
        [21965] = "Fathom-Guard Tidalvess",
        [21232] = "Greyheart Skulker",
        [21299] = "Coilfang Fathom-Witch",
        [22091] = "Spitfire Totem",
        [21863] = "Serpentshrine Lurker",
        [22250] = "Rancid Mushroom",
        [21231] = "Greyheart Shield-Bearer",
    },
    tk = {
        [19514] = "Al'ar",
        [20046] = "Astromancer Lord",
        [21270] = "Cosmic Infuser",
        [20050] = "Crimson Hand Inquisitor",
        [20040] = "Crystalcore Devastator",
        [19622] = "Kael'thas Sunstrider",
        [18806] = "Solarium Priest",
        [20034] = "Star Scryer",
        [20064] = "Thaladred the Darkener",
        [19516] = "Void Reaver",
        [20033] = "Astromancer",
        [20047] = "Crimson Hand Battle Mage",
        [20041] = "Crystalcore Sentinel",
        [21269] = "Devastation",
        [19551] = "Ember of Al'ar",
        [18805] = "High Astromancer Solarian",
        [20060] = "Lord Sanguinar",
        [20045] = "Nether Scryer",
        [21362] = "Phoenix",
        [20032] = "Bloodwarder Vindicator",
        [20049] = "Crimson Hand Blood Knight",
        [20062] = "Grand Astromancer Capernian",
        [21271] = "Infinity Blades",
        [21364] = "Phoenix Egg",
        [20042] = "Tempest-Smith",
        [20031] = "Bloodwarder Legionnaire",
        [20048] = "Crimson Hand Centurion",
        [20052] = "Crystalcore Mechanic",
        [20063] = "Master Engineer Telonicus",
        [21268] = "Netherstrand Longbow",
        [20036] = "Bloodwarder Squire",
        [21273] = "Phaseshift Bulwark",
        [20035] = "Bloodwarder Marshal",
        [21274] = "Staff of Disintegration",
        [20037] = "Tempest Falconer",
        [21272] = "Warp Slicer",
        [20038] = "Phoenix-Hawk Hatchling",
        [20039] = "Phoenix-Hawk",
    },
    hyjal = {
        [17895] = "Ghoul",
        [17897] = "Crypt Fiend",
        [17899] = "Shadowy Necromancer",
        [17898] = "Abomination",
        [17905] = "Banshee",
        [17906] = "Gargoyle",
        [17908] = "Giant Infernal",
        [17916] = "Fel Stalker",
        [17907] = "Frost Wyrm",
        [17767] = "Rage Winterchill",
        [17808] = "Anetheron",
        [17888] = "Kaz'rogal",
        [17842] = "Azgalor",
        [17968] = "Archimonde",
    },
}

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

for raidKey, expectedRaid in pairs(expected) do
    local data = ns.autoMarkingNPCs and ns.autoMarkingNPCs[raidKey]
    check(type(data) == "table", raidKey .. " dataset exists")

    local actual = {}
    for _, npc in ipairs((data and data.npcs) or {}) do
        check(actual[npc.id] == nil, raidKey .. " has no duplicate npcID " .. tostring(npc.id))
        actual[npc.id] = npc.name
    end

    for npcID, name in pairs(expectedRaid) do
        check(actual[npcID] == name, ("%s npcID %d is %s"):format(raidKey, npcID, name))
    end
    check(countKeys(actual) == countKeys(expectedRaid), raidKey .. " has no unexpected NPC entries")
end

local hyjal = ns.autoMarkingNPCs and ns.autoMarkingNPCs.hyjal
check(type(hyjal.infoSections) == "table" and hyjal.infoSections[1] and hyjal.infoSections[1].title == "Trash Wave Info", "hyjal has collapsible trash wave info")
check(type(hyjal.infoSections[1].tables) == "table" and #hyjal.infoSections[1].tables == 4, "hyjal trash wave info has four boss tables")
check(hyjal.infoSections[1].tables[1].title == "Rage Winterchill" and #hyjal.infoSections[1].tables[1].rows == 8, "hyjal Rage Winterchill table has eight waves")

print(("automark_npc_dataset_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
