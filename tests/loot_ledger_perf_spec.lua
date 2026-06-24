-- loot_ledger_perf_spec.lua
-- Tests for Fix 1 (MergeDuplicateDrops O(n) behavior & correctness)
-- and Fix 2 (OnInit history trim).

local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local now = 5000
function time() return now end
function date() return "now" end
function UnitName() return "TestPlayer" end
function GetNormalizedRealmName() return "TestRealm" end
function GetRealmName() return "TestRealm" end
function strsplit(sep, value, limit)
    value = tostring(value or "")
    local out = {}
    local start = 1
    while true do
        if limit and #out >= limit - 1 then
            out[#out + 1] = value:sub(start)
            break
        end
        local i, j = value:find(sep, start, true)
        if not i then
            out[#out + 1] = value:sub(start)
            break
        end
        out[#out + 1] = value:sub(start, i - 1)
        start = j + 1
    end
    return table.unpack(out)
end
function GetItemInfo() return nil end
function IsInRaid() return false end
function IsInGroup() return false end

local instanceName, instanceType, difficultyId, instanceId = "Serpentshrine Cavern", "raid", 14, 548
function GetInstanceInfo()
    return instanceName, instanceType, difficultyId, nil, nil, nil, nil, instanceId
end

-- Fresh DB per test run
local function makeDB()
    return { db = { raidLootLedger = { drops = {}, sessionCounter = 0 }, settings = { raidLootLedger = {} } } }
end

ns.modules.DB = makeDB()

assert(loadfile(DIR .. "Modules/LootLedger/LootLedger.lua"))("iddqd", ns)
local Ledger = ns:GetModule("LootLedger")

local pass, fail = 0, 0
local function check(c, m)
    if c then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. tostring(m))
    end
end

-- Helper: make a minimal drop that will match as a duplicate of another with the same dropInstanceId.
-- duplicateDropMatch(a,b) requires:
--   same duplicateDropKey (same itemId + same canonicalSource + same canonicalBoss)
--   not knownDifferentPhysicalItems (no conflicting itemGuids)
--   not knownDifferentConfirmedOwners
--   AND (sameKnownDropId OR matching itemGuid)
-- Simplest: same dropInstanceId satisfies sameKnownDropId.
local function makeDrop(itemId, dropInstanceId, sourceInstance, bossName, extraFields)
    local d = {
        itemId = itemId,
        dropInstanceId = dropInstanceId,
        lootId = dropInstanceId,
        sourceInstance = sourceInstance or "Serpentshrine Cavern",
        bossName = bossName or "Hydross the Unstable",
        firstHolder = "PlayerA-TestRealm",
        currentHolder = "PlayerA-TestRealm",
        status = "pending",
        droppedAt = now,
        updatedAt = now,
        events = {},
    }
    if extraFields then
        for k, v in pairs(extraFields) do d[k] = v end
    end
    return d
end

-- ---------------------------------------------------------------------------
-- TEST 1: Basic two-duplicate merge
-- Drop A (index 1) and Drop B (index 2) share same dropInstanceId -> duplicates.
-- After MergeDuplicateDrops, count should be 1 and removed count = 1.
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    local dropA = makeDrop(30001, "inst:30001:1", "Serpentshrine Cavern", "Hydross the Unstable")
    dropA.events = { { type = "chat_loot_received", at = now } }
    local dropB = makeDrop(30001, "inst:30001:1", "Serpentshrine Cavern", "Hydross the Unstable")
    dropB.events = { { type = "remote_drop_updated", at = now + 1 } }

    table.insert(drops, dropA)
    table.insert(drops, dropB)

    local removed = Ledger:MergeDuplicateDrops()
    check(removed == 1, "basic two-duplicate merge: removed count == 1 (got " .. tostring(removed) .. ")")
    check(#drops == 1, "basic two-duplicate merge: drops shrinks to 1 (got " .. tostring(#drops) .. ")")
    -- The surviving drop is the one at index 1 (dropA); dropB merged into it.
    check(drops[1] == dropA, "basic two-duplicate merge: lower-index drop (dropA) survives as merge target")
    -- Events from dropB should be merged into dropA.
    check(#drops[1].events == 2, "basic two-duplicate merge: events from source merged into target (got " .. tostring(#drops[1].events) .. ")")
end

-- ---------------------------------------------------------------------------
-- TEST 2: Three-duplicate chain collapses to ONE row
-- Drop A (index 1), Drop B (index 2), Drop C (index 3) all share the same dropInstanceId.
-- Old O(n^2) code scanned i=3 down to i=2:
--   i=3: FindDuplicateDrop(3) scans 1..2, finds index 1 -> merge C into A, remove C
--   i=2: FindDuplicateDrop(2) scans 1..1, finds index 1 -> merge B into A, remove B
-- Result: A survives with events from B and C merged. Count = 1.
-- New bucket code: bucket=[1,2,3].
--   a=2 (laterIdx=2), b=1 (earlierIdx=1): match(A,B)=true -> mergeInto[2]=1, removeFlag[2]=true
--   a=3 (laterIdx=3), removeFlag[3]=false, b=1: match(A,C)=true -> mergeInto[3]=1, removeFlag[3]=true
-- Apply high->low: laterIdx=3 -> merge C into A; laterIdx=2 -> merge B into A.
-- Result: same as old code.
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    local dropA = makeDrop(30002, "inst:30002:1", "Serpentshrine Cavern", "Lady Vashj")
    dropA.events = { { type = "event_A", at = now } }
    local dropB = makeDrop(30002, "inst:30002:1", "Serpentshrine Cavern", "Lady Vashj")
    dropB.events = { { type = "event_B", at = now + 1 } }
    local dropC = makeDrop(30002, "inst:30002:1", "Serpentshrine Cavern", "Lady Vashj")
    dropC.events = { { type = "event_C", at = now + 2 } }

    table.insert(drops, dropA)
    table.insert(drops, dropB)
    table.insert(drops, dropC)

    local removed = Ledger:MergeDuplicateDrops()
    check(removed == 2, "3-chain merge: removed count == 2 (got " .. tostring(removed) .. ")")
    check(#drops == 1, "3-chain merge: drops shrinks to 1 (got " .. tostring(#drops) .. ")")
    check(drops[1] == dropA, "3-chain merge: lowest-index drop (dropA) is the surviving merge target")
    -- All three event types should be present in dropA after merge.
    local types = {}
    for _, ev in ipairs(drops[1].events) do types[ev.type] = true end
    check(types["event_A"] == true, "3-chain merge: dropA's own event preserved")
    check(types["event_B"] == true, "3-chain merge: dropB's events merged into target")
    check(types["event_C"] == true, "3-chain merge: dropC's events merged into target")
end

-- ---------------------------------------------------------------------------
-- TEST 3: Non-matching drops are NOT merged (different items in same bucket shape)
-- Two drops with different itemId should not match (different key).
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    local dropX = makeDrop(11111, "inst:11111:1", "Serpentshrine Cavern", "Morogrim Tidewalker")
    local dropY = makeDrop(22222, "inst:22222:1", "Serpentshrine Cavern", "Morogrim Tidewalker")

    table.insert(drops, dropX)
    table.insert(drops, dropY)

    local removed = Ledger:MergeDuplicateDrops()
    check(removed == 0, "non-duplicate drops: nothing removed (got " .. tostring(removed) .. ")")
    check(#drops == 2, "non-duplicate drops: both drops survive (got " .. tostring(#drops) .. ")")
end

-- ---------------------------------------------------------------------------
-- TEST 4: knownDifferentPhysicalItems prevents merge
-- Same key and same dropInstanceId but DIFFERENT itemGuids -> not duplicates.
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    -- Same dropInstanceId but different itemGuids (two physically distinct items)
    local dropP = makeDrop(30003, "inst:30003:1", "Serpentshrine Cavern", "Hydross the Unstable",
        { itemGuid = "Item-GUID-AAAA" })
    local dropQ = makeDrop(30003, "inst:30003:1", "Serpentshrine Cavern", "Hydross the Unstable",
        { itemGuid = "Item-GUID-BBBB" })

    table.insert(drops, dropP)
    table.insert(drops, dropQ)

    local removed = Ledger:MergeDuplicateDrops()
    check(removed == 0, "different itemGuids: knownDifferentPhysicalItems blocks merge (got removed=" .. tostring(removed) .. ")")
    check(#drops == 2, "different itemGuids: both drops survive")
end

-- ---------------------------------------------------------------------------
-- TEST 5: MergeDuplicateDrops returns correct removed count
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    -- 4 duplicates (same dropInstanceId) -> 3 should be removed, 1 survives
    for j = 1, 4 do
        local d = makeDrop(40001, "inst:40001:dup", "Serpentshrine Cavern", "Leotheras the Blind")
        d.events = { { type = "ev" .. j, at = now + j } }
        table.insert(drops, d)
    end

    local removed = Ledger:MergeDuplicateDrops()
    check(removed == 3, "4-duplicate group: removed count == 3 (got " .. tostring(removed) .. ")")
    check(#drops == 1, "4-duplicate group: only 1 survives (got " .. tostring(#drops) .. ")")
end

-- ---------------------------------------------------------------------------
-- TEST 6: Perf sanity — 2000 non-duplicate drops with distinct keys, O(n) time
-- The old O(n^2) implementation on 2000 drops would do ~2M comparisons.
-- The new bucketed implementation does ~2000 (one per drop, no intra-bucket work
-- since all keys are distinct). Should complete in well under 1.0s.
-- ---------------------------------------------------------------------------
do
    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    for j = 1, 2000 do
        -- Each drop has a unique itemId so its duplicateDropKey is unique -> no bucket collision.
        local d = {
            itemId = 100000 + j,
            dropInstanceId = "perf:drop:" .. j,
            lootId = "perf:drop:" .. j,
            sourceInstance = "Serpentshrine Cavern",
            bossName = "PerfBoss",
            firstHolder = "PerfPlayer-TestRealm",
            currentHolder = "PerfPlayer-TestRealm",
            status = "pending",
            droppedAt = now,
            updatedAt = now,
            events = {},
        }
        table.insert(drops, d)
    end

    local t0 = os.clock()
    local removed = Ledger:MergeDuplicateDrops()
    local elapsed = os.clock() - t0

    check(removed == 0, "perf: no false merges on 2000 distinct drops (got " .. tostring(removed) .. ")")
    check(#drops == 2000, "perf: all 2000 drops survive (got " .. tostring(#drops) .. ")")
    check(elapsed < 1.0, ("perf: MergeDuplicateDrops on 2000 distinct drops completed in %.4fs (< 1.0s required)"):format(elapsed))
    print(("  perf: MergeDuplicateDrops(2000 distinct drops) took %.4fs"):format(elapsed))
end

-- ---------------------------------------------------------------------------
-- TEST 7: Fix 2 — OnInit trims bloated history (newest kept, oldest discarded)
-- MAX_DROPS = 600. Insert 700 drops, call OnInit, verify #drops <= 600.
-- Newest drops are at the FRONT (index 1) per the normal insert pattern.
-- OnInit trim removes from the END (table.remove with no index), keeping newest.
-- We mark drops with a stamp field to verify which are kept.
--
-- To ensure that drops survive the cleanup passes (PruneDungeonLootDrops removes
-- items not in the raid loot table), we populate ns.raidLootSources so our test
-- item IDs are recognized as known raid loot.
-- ---------------------------------------------------------------------------
do
    -- Reset DB for this test
    ns.modules.DB = makeDB()

    -- Register a contiguous block of test item IDs as known raid loot so they
    -- survive PruneDungeonLootDrops during OnInit.
    local byItemId = {}
    for j = 1, 700 do
        byItemId[60000 + j] = { instance = "Serpentshrine Cavern", source = "Hydross the Unstable" }
    end
    ns.raidLootSources = { byItemId = byItemId }

    -- Reload Ledger with fresh DB and the updated raidLootSources.
    assert(loadfile(DIR .. "Modules/LootLedger/LootLedger.lua"))("iddqd", ns)
    Ledger = ns:GetModule("LootLedger")

    local store = ns.modules.DB.db.raidLootLedger
    store.drops = {}
    local drops = store.drops

    -- Insert 700 drops; newest (stamp=700) at index 1, oldest (stamp=1) at index 700
    -- (mirrors table.insert(drops, 1, drop) pattern used in production).
    for j = 700, 1, -1 do
        -- stamp j: highest stamps are newest (inserted first in reverse order so index 1 = stamp 700)
        table.insert(drops, {
            stamp = j,
            itemId = 60000 + j,
            sourceInstance = "Serpentshrine Cavern",
            bossName = "Hydross the Unstable",
            instanceType = "raid",
            events = {},
            droppedAt = j,
            updatedAt = j,
        })
    end
    -- Verify our setup: index 1 should be stamp=700 (newest), index 700 = stamp=1 (oldest)
    assert(drops[1].stamp == 700, "setup: index 1 should be newest (stamp 700)")
    assert(drops[700].stamp == 1, "setup: index 700 should be oldest (stamp 1)")

    -- Call OnInit without C_Timer (so cleanup runs inline via the else branch).
    -- C_Timer is not defined in this test harness, so runCleanup() runs synchronously.
    Ledger:OnInit()

    local finalDrops = Ledger:Drops()
    check(#finalDrops <= 600, "Fix2 trim: #drops <= MAX_DROPS after OnInit (got " .. tostring(#finalDrops) .. ")")

    -- The 700-600=100 oldest drops (stamps 1..100, which were at the END of the array)
    -- should have been removed. The 600 newest (stamps 101..700, indices 1..600) survive.
    -- Check that the drop at index 1 is still the newest (stamp 700).
    check(finalDrops[1] and finalDrops[1].stamp == 700,
        "Fix2 trim: newest drop (stamp=700) is still at index 1 after trim (got stamp=" .. tostring(finalDrops[1] and finalDrops[1].stamp) .. ")")
    -- The drop that was at the end (oldest, stamp=1) should be gone.
    local foundOldest = false
    for _, d in ipairs(finalDrops) do
        if d.stamp and d.stamp <= 100 then foundOldest = true; break end
    end
    check(not foundOldest, "Fix2 trim: oldest drops (stamps 1-100) were removed, only newest 600 kept")
end

print(("loot_ledger_perf_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
