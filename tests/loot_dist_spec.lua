local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"
local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 1000 end
ns.modules.DB = { db = {} }
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Store.lua"))("iddqd", ns)
local Store = ns:GetModule("LootDistStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local s = Store:Get()
check(type(s) == "table" and s.protocolVersion == 1, "Get initialises protocolVersion 1")
check(type(s.entries) == "table", "Get creates entries table")

-- ListId: GUID preferred; else itemID:looter:bucket(30s)
check(Store:ListId("Item-0-0-x", 30029, "Bob", 1000) == "Item-0-0-x", "ListId prefers item GUID")
check(Store:ListId(nil, 30029, "Bob-Realm", 1000) == "30029:bob:33", "ListId fallback itemID:looterShortLower:floor(at/30)")
check(Store:ListId(nil, 30029, "Bob", 1000) == Store:ListId(nil, 30029, "bob", 1015), "fallback id stable within 30s bucket + case/realm-insensitive")

-- EnsureEntry creates + fills meta once
Store:EnsureEntry("E1", { itemId = 30029, itemName = "Boots", quality = 4, holder = "Bob", source = "auto" })
check(Store:Entries()["E1"] ~= nil and Store:Entries()["E1"].responses ~= nil and Store:Entries()["E1"].itemId == 30029, "EnsureEntry creates entry with responses table")
Store:EnsureEntry("E1", { itemName = "OVERWRITE?" })
check(Store:Entries()["E1"].itemName == "Boots", "EnsureEntry does not overwrite existing fields")

Store:RemoveEntry("E1")
check(Store:Entries()["E1"] == nil, "RemoveEntry deletes")

-- Convergent delete: a tombstone blocks re-creation by a stale create, and survives re-sync.
Store:EnsureEntry("DEL1", { itemId = 30029, itemName = "Boots" })
check(Store:Entries()["DEL1"] ~= nil, "DEL1 created")
check(Store:RemoveEntry("DEL1", 200) == true, "RemoveEntry tombstones at t=200")
check(Store:Entries()["DEL1"] == nil, "DEL1 removed from live entries")
check(Store:IsTombstoned("DEL1") == true, "DEL1 is tombstoned")
-- A create arriving AFTER the delete must NOT resurrect it.
check(Store:EnsureEntry("DEL1", { itemId = 30029, itemName = "Boots" }) == nil, "tombstone blocks re-create")
check(Store:Entries()["DEL1"] == nil, "DEL1 stays gone after stale re-create")
-- Tombstone LWW by at: an older delete does not override a newer one.
check(Store:RemoveEntry("DEL1", 150) == false, "older delete (t=150) does not override newer tombstone (t=200)")
check(Store:Tombstones()["DEL1"] == 200, "tombstone keeps newest deletedAt")
-- Pruning drops old tombstones (maxAge tiny so t=200 is older than now-cutoff).
Store:PruneTombstones(0)
check(Store:IsTombstoned("DEL1") == false, "PruneTombstones removes aged tombstone")
-- After pruning, the id can be created again (genuinely new drop reusing the bucket id).
check(Store:EnsureEntry("DEL1", { itemId = 30029 }) ~= nil, "id can be re-created once tombstone pruned")
Store:Entries()["DEL1"] = nil

-- ClearTombstone: an intentional manual re-add can clear a tombstone so the id is creatable
-- again WITHOUT waiting for the prune window (re-looting the same item next week).
Store:EnsureEntry("RE1", { itemId = 100 })
Store:RemoveEntry("RE1", 300)
check(Store:IsTombstoned("RE1") == true, "RE1 tombstoned after remove")
check(Store:EnsureEntry("RE1", { itemId = 100 }) == nil, "tombstone blocks plain re-create")
Store:ClearTombstone("RE1")
check(Store:IsTombstoned("RE1") == false, "ClearTombstone forgets the tombstone")
check(Store:EnsureEntry("RE1", { itemId = 100 }) ~= nil, "manual re-add succeeds after ClearTombstone")
Store:Entries()["RE1"] = nil; Store:Tombstones()["RE1"] = nil

-- EnsureEntry refuses to CREATE an entry with no itemId (prevents "Item nil" rows)
check(Store:EnsureEntry("NOITEM", { quality = 4 }) == nil, "EnsureEntry rejects creating a nil-itemId entry")
check(Store:Entries()["NOITEM"] == nil, "no nil-itemId entry was stored")
-- ...but updating an EXISTING entry without itemId is still allowed
Store:EnsureEntry("UP1", { itemId = 99 })
check(Store:EnsureEntry("UP1", { holder = "Bob" }) ~= nil and Store:Entries()["UP1"].holder == "Bob", "EnsureEntry updates existing entry without re-requiring itemId")

-- Responses: last-write-wins by at
Store:EnsureEntry("R1", { itemId = 1, source = "auto" })
check(Store:SetResponse("R1", "Bob", "WARRIOR", "upgrade", "", 10) == true, "first response recorded")
Store:SetResponse("R1", "Bob", "WARRIOR", "minor", "tank set", 20)
check(Store:Entries()["R1"].responses["bob"].response == "minor", "later response replaces earlier")
check(Store:Entries()["R1"].responses["bob"].note == "tank set", "note travels with response")
check(Store:SetResponse("R1", "Bob", "WARRIOR", "pvp", "", 5) == false and Store:Entries()["R1"].responses["bob"].response == "minor", "older response does not override")
Store:SetResponse("R1", "Alice", "MAGE", "upgrade", "", 12)
local n = 0; for _ in pairs(Store:Entries()["R1"].responses) do n = n + 1 end
check(n == 2, "two distinct responders")
check(Store:ClearResponse("R1", "Bob", 25) == true, "response clear removes responder")
check(Store:Entries()["R1"].responses["bob"] == nil, "cleared response is gone")
check(Store:SetResponse("R1", "Bob", "WARRIOR", "bis", "", 20) == false, "older response cannot resurrect after clear")
check(Store:Entries()["R1"].responses["bob"] == nil, "older response stays blocked after clear")
check(Store:SetResponse("R1", "Bob", "WARRIOR", "bis", "", 30) == true, "newer response after clear is accepted")
check(Store:Entries()["R1"].responses["bob"].response == "bis", "newer response after clear is stored")
check(Store:ClearResponse("R1", "Bob", 28) == false, "older clear does not remove newer response")
check(Store:Entries()["R1"].responses["bob"].response == "bis", "newer response survives older clear")

-- Award model: quantity 1 -> one award; a second (different) winner is rejected (capped at qty).
check(Store:SetAward("R1", "Alice", "OfficerA", 100, "MAGE") == true, "award set")
check(Store:Entries()["R1"].award.winner == "Alice", "award winner recorded")
check(Store:Entries()["R1"].award.winnerClass == "MAGE", "award stores winnerClass for class colour")
check(Store:SetAward("R1", "Bob", "OfficerB", 110) == false, "second award rejected at quantity 1")
check(Store:Entries()["R1"].award.winner == "Alice", "first award stands (quantity 1)")
check(Store:AwardCount("R1") == 1 and Store:IsFullyAwarded("R1"), "R1 fully awarded at qty 1")

-- Multi-copy award: quantity 2 -> awardable to TWO different players, not a third.
Store:EnsureEntry("Q2", { itemId = 29753, quality = 4 })
Store:SetQuantity("Q2", 2)
check(Store:SetAward("Q2", "Alice", "O", 200, "MAGE") == true, "Q2 first award")
check(Store:IsFullyAwarded("Q2") == false, "Q2 not full after 1/2")
check(Store:SetAward("Q2", "Alice", "O", 201) == false, "same player can't be awarded twice")
check(Store:SetAward("Q2", "Bob", "O", 202, "WARRIOR") == true, "Q2 second award (different player)")
check(Store:AwardCount("Q2") == 2 and Store:IsFullyAwarded("Q2"), "Q2 fully awarded at 2/2")
check(Store:SetAward("Q2", "Cara", "O", 203) == false, "third award rejected (over quantity)")
Store:DecrementQuantity("Q2")   -- back to qty 1; one award is now over -> caller pops
Store:PopAward("Q2")
check(Store:AwardCount("Q2") == 1 and (tonumber(Store:Entries()["Q2"].quantity) == 1), "decrement + pop award")

-- Traded flag
Store:SetTraded("R1", true)
check(Store:Entries()["R1"].traded == true, "traded flag set")

-- Sort: un-awarded first, awarded sink to bottom, newest-relevant within group
for k in pairs(Store:Entries()) do Store:Entries()[k] = nil end
Store:EnsureEntry("A", { itemId = 1, source="auto" }); Store:Entries()["A"].addedAt = 50
Store:EnsureEntry("B", { itemId = 2, source="auto" }); Store:Entries()["B"].addedAt = 60
Store:EnsureEntry("C", { itemId = 3, source="auto" }); Store:Entries()["C"].addedAt = 70
Store:SetAward("B", "X", "O", 100)   -- B awarded -> goes to bottom
local order = Store:SortedEntries()
check(order[#order].id == "B", "awarded entry sinks to bottom")
check(order[1].id == "C" and order[2].id == "A", "un-awarded sorted newest addedAt first")

-- Class filter (subtype x class)
check(Store:ArmorUsable("Cloth", "MAGE") == true, "mage cloth")
check(Store:ArmorUsable("Plate", "MAGE") == false, "mage not plate")
check(Store:ArmorUsable("Plate", "WARRIOR") == true, "warrior plate")
check(Store:ArmorUsable("Miscellaneous", "MAGE") == true, "rings/etc usable by all")
check(Store:ArmorUsable("Shields", "PRIEST") == false, "priest no shields")
check(Store:ArmorUsable("Frobnicate", "MAGE") == true, "unknown armor subtype -> usable")
check(Store:WeaponUsable("Bows", "HUNTER") == true, "hunter bows")
check(Store:WeaponUsable("Bows", "MAGE") == false, "mage no bows")
check(Store:WeaponUsable("Staves", "MAGE") == true, "mage staves")
check(Store:WeaponUsable("Frobnicate", "MAGE") == true, "unknown weapon subtype -> usable")

-- Auto-add decision
check(Store:ShouldAutoAdd({ isLeaderAssist = false }) == false, "non-officer never auto-adds")
check(Store:ShouldAutoAdd({ isLeaderAssist = true, assignedInRaid = true }) == false, "assigned-in-raid item not auto-added")
check(Store:ShouldAutoAdd({ isLeaderAssist = true, assignedInRaid = false, alreadyPresent = true }) == false, "already-present not re-added")
check(Store:ShouldAutoAdd({ isLeaderAssist = true, assignedInRaid = false, alreadyAwarded = true }) == false, "already-awarded not re-added")
check(Store:ShouldAutoAdd({ isLeaderAssist = true, assignedInRaid = false }) == true, "officer + unassigned + new -> auto-add")

print(("loot_dist_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
