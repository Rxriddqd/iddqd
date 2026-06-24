-- Headless test for the pure auto-mark engine (slot allocator + npcId + settings ops).
local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end

local E = assert(loadfile(DIR .. "Modules/AutoMarking/markEngine.lua"))("iddqd", ns)

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

-- npcIdFromGuid: creature GUID -> id; player GUID -> nil; malformed -> nil.
check(E.npcIdFromGuid("Creature-0-3133-532-7-16151-000A1B2C3D") == 16151, "npcId parses a creature GUID")
check(E.npcIdFromGuid("Player-4395-01234567") == nil, "npcId rejects a player GUID")
check(E.npcIdFromGuid("garbage") == nil, "npcId rejects garbage")
check(E.npcIdFromGuid(nil) == nil, "npcId nil-safe")

-- pickMarker: walk the priority list.
local function fresh() return { nil, nil, nil, nil, nil, nil, nil, nil } end
-- first free slot taken
local am = fresh()
local m = E.pickMarker({ 8, 7 }, am, "guidA", false)
check(m == 8, "pickMarker takes the first free marker")
-- already-ours dedupe: same guid holding marker 8 -> still 8
am[8] = "guidA"
check(E.pickMarker({ 8, 7 }, am, "guidA", false) == 8, "pickMarker returns our own marker (dedupe)")
-- second mob: 8 taken by guidA, so guidB gets 7
check(E.pickMarker({ 8, 7 }, am, "guidB", false) == 7, "pickMarker gives the next free marker to a new mob")
-- all taken, lockAfterUse=false -> wrap to slot 1 (frees the list)
am[8] = "x"; am[7] = "y"
local mw, wrapped = E.pickMarker({ 8, 7 }, am, "guidC", false)
check(mw == 8 and wrapped == true, "pickMarker wraps to slot 1 when all taken (lock off)")
-- all taken, lockAfterUse=true -> nil
am[8] = "x"; am[7] = "y"
check(E.pickMarker({ 8, 7 }, am, "guidD", true) == nil, "pickMarker refuses to wrap when locked")
-- malformed slot skipped
local am2 = fresh()
check(E.pickMarker({ 99, 5 }, am2, "g", false) == 5, "pickMarker skips a malformed slot")

-- Settings ops (pure, over a passed-in settings table).
local function S() return { version = 3, enabled = false, raids = { kara = {} } } end
local s = S()
E.setMarker(s, "kara", 16151, 1, 8)
check(E.getMarkerList(s, "kara", 16151)[1] == 8, "setMarker writes slot 1")
E.setMarker(s, "kara", 16151, 2, 7)
check(#E.getMarkerList(s, "kara", 16151) == 2, "setMarker appends slot 2")
-- dedupe: same marker twice in one NPC is rejected
E.setMarker(s, "kara", 16151, 3, 8)
check(E.getMarkerList(s, "kara", 16151)[3] == nil, "setMarker rejects a duplicate marker in one NPC")
-- clear a slot compacts the list (here the trailing slot 2)
E.setMarker(s, "kara", 16151, 2, nil)
check(#E.getMarkerList(s, "kara", 16151) == 1, "setMarker clearing compacts the list")
-- emptying drops the npcID key
E.setMarker(s, "kara", 16151, 1, nil)
check(s.raids.kara[16151] == nil, "setMarker dropping the last marker removes the npcID key")

-- COMPACTION: clearing a first/middle slot must leave a dense, hole-free list (so #list is
-- valid for the runtime pickMarker). {8,7,6}, clear slot 1 -> {7,6} (not {nil,7,6}).
local sc = S()
E.setMarker(sc, "kara", 99, 1, 8)
E.setMarker(sc, "kara", 99, 2, 7)
E.setMarker(sc, "kara", 99, 3, 6)
E.setMarker(sc, "kara", 99, 1, nil)  -- clear the FIRST slot
local cl = E.getMarkerList(sc, "kara", 99)
check(#cl == 2 and cl[1] == 7 and cl[2] == 6 and cl[3] == nil, "setMarker compacts a hole (clear slot 1 of {8,7,6} -> {7,6})")
-- clearRaid preserves the table reference
local s2 = S(); local ref = s2.raids.kara
E.setMarker(s2, "kara", 1, 1, 5); E.clearRaid(s2, "kara")
check(s2.raids.kara == ref and next(s2.raids.kara) == nil, "clearRaid empties but keeps the table ref")

-- migrate: v1 int -> v3 array; idempotent.
local old = { raids = { kara = { [16151] = 8 } } }  -- no version, single int
E.migrate(old)
check(old.version == 4, "migrate bumps to v4")
check(type(old.profiles[1].raids.kara[16151]) == "table" and old.profiles[1].raids.kara[16151][1] == 8, "migrate converts int -> profile array")
check(old.modifierEnabled == false and old.modifierKey == "ALT" and old.lockAfterUse == false, "migrate adds v2/v3 defaults")
local v3 = { version = 3, raids = {}, modifierEnabled = true, modifierKey = "SHIFT", lockAfterUse = true }
E.migrate(v3)
check(v3.version == 4 and v3.profiles[1].modifierKey == "SHIFT", "migrate upgrades v3 into a profile")

local gruulOld = {
    version = 3,
    raids = {
        gruul = {
            [21350] = { 8, 7 }, -- old mislabeled Lair Brute row
            [18847] = { 6 },    -- old mislabeled Gronn-Priest row
            [19389] = { 2 },    -- old mislabeled Wild Fel Stalker row
        },
    },
}
E.migrate(gruulOld)
local migratedGruul = gruulOld.profiles[1].raids.gruul
check(migratedGruul[19389][1] == 8 and migratedGruul[19389][2] == 7, "migrate moves saved Lair Brute marks to npcID 19389")
check(migratedGruul[21350][1] == 6, "migrate moves saved Gronn-Priest marks to npcID 21350")
check(migratedGruul[18847][1] == 2, "migrate moves saved Wild Fel Stalker marks to npcID 18847")
check(gruulOld.gruulNpcFixVersion == 1, "migrate records the Gruul npcID fix version")
E.migrate(gruulOld)
check(migratedGruul[19389][1] == 8 and migratedGruul[21350][1] == 6 and migratedGruul[18847][1] == 2, "Gruul npcID migration is idempotent")

local gruulV4 = {
    version = 4,
    activeProfileId = "default",
    profiles = {
        {
            id = "default",
            name = "Default",
            raids = { gruul = { [21350] = { 8 } } },
        },
    },
}
E.migrate(gruulV4)
check(gruulV4.profiles[1].raids.gruul[19389][1] == 8 and gruulV4.profiles[1].raids.gruul[21350] == nil, "migrate fixes existing v4 profile Gruul npcIDs")

print(("automark_engine_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
