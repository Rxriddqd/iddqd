local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"
local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
local testNow = 1000
function time() return testNow end
ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Modules/LootLedger/Store.lua"))("iddqd", ns)
local Store = ns:GetModule("LootStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local s = Store:Get()
check(type(s) == "table" and s.protocolVersion == 2, "Get initialises protocolVersion 2")
check(type(s.drops) == "table" and type(s.sessions) == "table", "Get creates drops + sessions tables")

ns.modules.DB.db.raidLootLedger = { protocolVersion = 0, drops = { old = {} }, sessions = { o = {} } }
Store:MigrateOrReset()
check(ns.modules.DB.db.raidLootLedger.protocolVersion == 2, "MigrateOrReset bumps to 2")
check(next(ns.modules.DB.db.raidLootLedger.drops) == nil, "MigrateOrReset wipes old drops")

-- v1 (pre-1.2.0 loot-format) local data is also wiped — old slot-based dropIDs / un-normalized
-- names must not survive into the new format.
ns.modules.DB.db.raidLootLedger = { protocolVersion = 1, drops = { ["x:1930:2"] = {} }, sessions = { s1 = {} } }
Store:MigrateOrReset()
check(ns.modules.DB.db.raidLootLedger.protocolVersion == 2, "MigrateOrReset bumps v1 -> 2")
check(next(ns.modules.DB.db.raidLootLedger.drops) == nil, "MigrateOrReset wipes v1 (pre-1.2.0) drops")

check(Store:DropID("Creature-0-1-2-3-44-000", 30029, 1) == "Creature-0-1-2-3-44-000:30029", "DropID composes bossGUID:itemID (slot excluded: unstable across clients)")
check(Store:DropID("Creature-0-1-2-3-44-000", 30029, 7) == Store:DropID("Creature-0-1-2-3-44-000", 30029, 1), "DropID ignores slot (same id regardless of loot slot)")
check(Store:DropID(nil, 30029, 1) == nil, "DropID nil without boss GUID (caller uses fallback)")
check(Store:FallbackDropID("Lady Vashj", 1200, 30029) == "Lady Vashj:40:30029", "FallbackDropID buckets serverTime/30")
-- LootTableDropID is deterministic from (instanceID, boss, itemID) — identical for a tracker
-- who opens the loot window and one who only sees the chat line, so they converge on ONE drop.
check(Store:LootTableDropID(36, "Mr. Smite", 7230) == "LT:36:Mr. Smite:7230", "LootTableDropID composes LT:instanceID:boss:itemID")
check(Store:LootTableDropID(36, "Mr. Smite", 7230) == Store:LootTableDropID(36, "Mr. Smite", 7230), "LootTableDropID deterministic (window vs chat observers converge)")
check(Store:LootTableDropID(36, "Mr. Smite", 7230) ~= Store:LootTableDropID(36, "Gilnid", 7230), "LootTableDropID differs by boss")

-- EventKey: deterministic, idempotent
local ev = { type = "traded", actor = "A-Realm", target = "B-Realm", at = 1000 }
local k1 = Store:EventKey(ev)
local k2 = Store:EventKey({ type = "traded", actor = "A-Realm", target = "B-Realm", at = 1000 })
check(k1 == k2, "EventKey deterministic for same event")
check(Store:EventKey({ type="looted", actor="A-Realm", at=1000 }) ~= k1, "EventKey differs by type/actor")

Store:EnsureDrop("D1", { sessionID="S1", itemId=30029, itemName="Boots", quality=4 })
check(Store:Drops()["D1"] ~= nil, "EnsureDrop creates the drop")
local added1 = Store:AddEvent("D1", { type="looted", actor="A-Realm", at=1000 })
local added2 = Store:AddEvent("D1", { type="looted", actor="A-Realm", at=1000 })
check(added1 == true, "first AddEvent returns true (new)")
check(added2 == false, "duplicate AddEvent returns false (idempotent no-op)")
local count = 0; for _ in pairs(Store:Drops()["D1"].events) do count = count + 1 end
check(count == 1, "duplicate event not double-stored")
check(Store:AddEvent("NOPE", { type="looted", actor="X", at=1 }) == false, "AddEvent on unknown drop is a safe no-op")

local function freshDrop(id) Store:Drops()[id] = nil; Store:EnsureDrop(id, { itemId = 100 }); return id end

freshDrop("C1"); Store:AddEvent("C1", { type="looted", actor="Looter-Realm", at=10 })
local st = Store:ComputeState(Store:Drops()["C1"])
check(st.status == "obtained" and st.currentHolder == "Looter-Realm", "looted -> obtained by looter")

Store:AddEvent("C1", { type="traded", actor="Looter-Realm", target="Buyer-Realm", at=20 })
st = Store:ComputeState(Store:Drops()["C1"])
check(st.currentHolder == "Buyer-Realm" and st.finalOwner == "Buyer-Realm", "traded -> holder/finalOwner = target")

Store:AddEvent("C1", { type="disenchanted", actor="Buyer-Realm", at=30 })
st = Store:ComputeState(Store:Drops()["C1"])
check(st.status == "disenchanted", "disenchanted after traded -> disenchanted status")

freshDrop("C2"); Store:AddEvent("C2", { type="looted", actor="X-Realm", at=10 }); Store:AddEvent("C2", { type="guild_bank", actor="X-Realm", at=15 })
check(Store:ComputeState(Store:Drops()["C2"]).status == "guild_bank", "guild_bank terminal")

freshDrop("C3"); Store:AddEvent("C3", { type="looted", actor="Y-Realm", at=10 }); Store:AddEvent("C3", { type="trade_window", actor="Y-Realm", at=12, remaining=3600 })
local st3 = Store:ComputeState(Store:Drops()["C3"])
check(st3.tradeWindow and st3.tradeWindow > 0, "trade_window -> remaining > 0")
Store:AddEvent("C3", { type="window_expired", actor="Y-Realm", at=9999 })
check(Store:ComputeState(Store:Drops()["C3"]).status == "finalized", "window_expired -> finalized")

-- bop_finalized: a BoP item with no trade window is finalized on loot, holder retained.
freshDrop("BF1"); Store:AddEvent("BF1", { type="looted", actor="Z-Realm", at=10 }); Store:AddEvent("BF1", { type="bop_finalized", actor="Z-Realm", at=10 })
local bf = Store:ComputeState(Store:Drops()["BF1"])
check(bf.status == "finalized" and bf.currentHolder == "Z-Realm", "bop_finalized -> finalized, holder retained")

-- recipe_learned: a learned recipe is a real finalizing ownership event.
freshDrop("RL1"); Store:AddEvent("RL1", { type="looted", actor="Crafter-Realm", at=10 }); Store:AddEvent("RL1", { type="recipe_learned", actor="Crafter-Realm", at=20 })
local rl = Store:ComputeState(Store:Drops()["RL1"])
check(rl.status == "finalized" and rl.currentHolder == "Crafter-Realm", "recipe_learned -> finalized, holder retained")

-- vendored: terminal, clears finalOwner; OUTRANKS a prior bop_finalized.
freshDrop("VN1"); Store:AddEvent("VN1", { type="looted", actor="Z-Realm", at=10 }); Store:AddEvent("VN1", { type="bop_finalized", actor="Z-Realm", at=10 })
Store:AddEvent("VN1", { type="vendored", actor="Z-Realm", at=20 })
local vn = Store:ComputeState(Store:Drops()["VN1"])
check(vn.status == "vendored" and vn.finalOwner == nil, "vendored -> vendored status, finalOwner cleared, outranks bop_finalized")

-- disenchant outranks bop_finalized too (DE after a no-window BoP item).
freshDrop("DB1"); Store:AddEvent("DB1", { type="looted", actor="Z-Realm", at=10 }); Store:AddEvent("DB1", { type="bop_finalized", actor="Z-Realm", at=10 })
Store:AddEvent("DB1", { type="disenchanted", actor="Z-Realm", at=20 })
check(Store:ComputeState(Store:Drops()["DB1"]).status == "disenchanted", "disenchant outranks bop_finalized")

-- delete a FINALIZED item: deleted (rank 5) must override bop_finalized (rank 3).
freshDrop("DF1"); Store:AddEvent("DF1", { type="looted", actor="Z-Realm", at=10 }); Store:AddEvent("DF1", { type="bop_finalized", actor="Z-Realm", at=10 })
Store:AddEvent("DF1", { type="deleted", actor="Z-Realm", at=30 })
check(Store:ComputeState(Store:Drops()["DF1"]).status == "deleted", "delete outranks bop_finalized (finalized item still deletable)")

freshDrop("C4")
Store:AddEvent("C4", { type="traded", actor="A-Realm", target="B-Realm", at=20 })
Store:AddEvent("C4", { type="looted", actor="A-Realm", at=10 })
check(Store:ComputeState(Store:Drops()["C4"]).finalOwner == "B-Realm", "out-of-order events fold to correct state")

-- Convergence: two conflicting events at the SAME timestamp fold identically regardless of insertion order.
-- (Simulates two clients whose pairs() order differs.) Two trades to different targets at at=50.
local function buildSameAt(id, firstTarget, secondTarget)
    Store:Drops()[id] = nil
    Store:EnsureDrop(id, { itemId = 100 })
    Store:AddEvent(id, { type="looted", actor="L-Realm", at=10 })
    Store:AddEvent(id, { type="traded", actor="L-Realm", target=firstTarget, at=50 })
    Store:AddEvent(id, { type="traded", actor="L-Realm", target=secondTarget, at=50 })
    return Store:ComputeState(Store:Drops()[id]).finalOwner
end
-- Insert in both orders; the deterministic tiebreaker must yield the SAME finalOwner.
local fo1 = buildSameAt("SA1", "P-Realm", "Q-Realm")
local fo2 = buildSameAt("SA2", "Q-Realm", "P-Realm")
check(fo1 == fo2, "same-timestamp events fold to identical state regardless of insertion order (got " .. tostring(fo1) .. " vs " .. tostring(fo2) .. ")")

-- tier_turnin sets currentHolder
Store:Drops()["TT1"] = nil; Store:EnsureDrop("TT1", { itemId = 200 })
Store:AddEvent("TT1", { type="tier_turnin", actor="Tank-Realm", at=10 })
local tt = Store:ComputeState(Store:Drops()["TT1"])
check(tt.status == "finalized" and tt.currentHolder == "Tank-Realm" and tt.finalOwner == "Tank-Realm", "tier_turnin finalizes to current holder")

-- DecideScope: ratio threshold, promote-only
check(Store:DecideScope(6, 10, 0.60, nil) == "guild", "60% -> guild")
check(Store:DecideScope(5, 10, 0.60, nil) == "personal", "50% -> personal")
check(Store:DecideScope(6, 10, 0.60, "personal") == "guild", "personal crossing -> guild (promote)")
check(Store:DecideScope(1, 10, 0.60, "guild") == "guild", "guild never demotes")
check(Store:DecideScope(0, 0, 0.60, nil) == "personal", "empty/solo -> personal")
-- eligibility gate: a non-eligible session (5-man dungeon / non-listed raid) is ALWAYS personal,
-- even at 100% guild ratio. eligible omitted/true keeps the legacy ratio behaviour.
check(Store:DecideScope(10, 10, 0.60, nil, false) == "personal", "ineligible session -> personal even at 100% guild")
check(Store:DecideScope(10, 10, 0.60, nil, true) == "guild", "eligible + ratio met -> guild")
check(Store:DecideScope(5, 10, 0.60, nil, true) == "personal", "eligible but ratio short -> personal")
check(Store:DecideScope(1, 10, 0.60, "guild", false) == "guild", "guild never demotes even if now ineligible")

Store:Sessions()["SX"] = nil
local sess = Store:EnsureSession("SX", { scope = "personal", instance = "SSC", startedAt = 1000 })
check(sess.scope == "personal", "EnsureSession stores scope")
Store:PromoteSession("SX")
check(Store:Sessions()["SX"].scope == "guild" and Store:Sessions()["SX"].promotedAt ~= nil, "PromoteSession -> guild + promotedAt")
check(Store:IsGuildSession("SX") == true, "promoted session is a guild session")
Store:Sessions()["SP"] = { sessionID="SP", scope="personal" }
check(Store:IsGuildSession("SP") == false, "personal session is not a guild session")

Store:Sessions()["HS1"] = nil
Store:EnsureSession("HS1", { scope = "guild" })
Store:EnsureDrop("HD1", { sessionID = "HS1", itemId = 101 })
Store:AddEvent("HD1", { type = "looted", actor = "A-Realm", at = 10 })
local hiddenRemoved = Store:HideSession("HS1", false)
check(hiddenRemoved == 0 and Store:IsSessionHidden("HS1") == true and Store:Sessions()["HS1"] ~= nil and Store:Drops()["HD1"] ~= nil, "HideSession without purge hides locally but retains data")
Store:UnhideSession("HS1")
check(Store:IsSessionHidden("HS1") == false, "UnhideSession clears local hide tombstone")
hiddenRemoved = Store:HideSession("HS1", true)
check(hiddenRemoved == 1 and Store:Sessions()["HS1"] == nil and Store:Drops()["HD1"] == nil, "HideSession with purge removes local session data")

Store:Sessions()["LATE1"] = nil
Store:Drops()["LATE-D1"] = nil
testNow = 2000
Store:EnsureSession("LATE1", { scope = "guild", startedAt = testNow })
Store:EnsureDrop("LATE-D1", { sessionID = "LATE1", itemId = 102 })
Store:AddEvent("LATE-D1", { type = "looted", actor = "A-Realm", at = 1 })
testNow = testNow + (73 * 60 * 60)
check(Store:AddEvent("LATE-D1", { type = "vendored", actor = "A-Realm", at = testNow }) == false, "late lifecycle event after 72h activity window is ignored")
check(Store:ComputeState(Store:Drops()["LATE-D1"]).status == "obtained", "inactive obtained item does not auto-finalize without a concrete finalizing event")
testNow = 1000

Store:Drops()["MD1"] = nil; Store:Sessions()["MS1"] = nil; Store:Sessions()["MS2"] = nil
Store:EnsureSession("MS1", { scope = "guild" })
Store:EnsureSession("MS2", { scope = "personal" })
Store:EnsureDrop("MD1", { sessionID = "MS1", itemId = 100 })
Store:AddEvent("MD1", { type="looted", actor="A-Realm", at=10 })
local man = Store:Manifest()
check(man.MS1 ~= nil, "Manifest includes guild session")
check(man.MS2 == nil, "Manifest excludes personal session")
local h1 = man.MS1
Store:AddEvent("MD1", { type="traded", actor="A-Realm", target="B-Realm", at=20 })
local h2 = Store:Manifest().MS1
check(h1 ~= h2, "session hash changes when an event is added")
-- HasCachedSession: true iff guild session at matching hash (used by Sync relay in Task 8)
check(Store:HasCachedSession("MS1", h2) == true, "HasCachedSession true at matching hash")
check(Store:HasCachedSession("MS1", "wrong") == false, "HasCachedSession false at wrong hash")
check(Store:HasCachedSession("MS2", h2) == false, "HasCachedSession false for personal session")

print(("loot_store_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
