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
assert(loadfile(DIR .. "Modules/LootLedger/Tracker.lua"))("iddqd", ns)
local Tracker = ns:GetModule("LootTracker")
local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local guildSet = { bob = true, alice = true, carol = true, dave = true, eve = true, frank = true }
local raid6of10 = { "Bob","Alice","Carol","Dave","Eve","Frank","Stranger1","Stranger2","Stranger3","Stranger4" }
local gc, rs = Tracker:GuildRatioFromRosters(raid6of10, guildSet)
check(gc == 6 and rs == 10, "6 of 10 guild members counted")

-- cross-realm name strips realm suffix and still matches
local gc2, rs2 = Tracker:GuildRatioFromRosters({ "Bob-OtherRealm", "Alice" }, guildSet)
check(gc2 == 2 and rs2 == 2, "cross-realm names strip realm and match guild set")

-- empty raid -> 0,0
local gc3, rs3 = Tracker:GuildRatioFromRosters({}, guildSet)
check(gc3 == 0 and rs3 == 0, "empty raid -> 0,0")

-- FindDropForItem must pick the SAME drop on every client when two drops share the same
-- itemId + droppedAt (convergence: pairs() order differs per client, so the tie-break must
-- be deterministic by dropID). Two drops, same itemId, same droppedAt, different dropIDs.
local Store = ns:GetModule("LootStore")
Store:Get()
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureSession("S", { scope = "guild" })
Tracker.activeSessionID = "S"
local dA = "Creature-AAA:777"
local dB = "Creature-BBB:777"
Store:EnsureDrop(dA, { sessionID = "S", itemId = 777 }); Store:Drops()[dA].droppedAt = 500
Store:EnsureDrop(dB, { sessionID = "S", itemId = 777 }); Store:Drops()[dB].droppedAt = 500
Store:AddEvent(dA, { type = "looted", actor = "X", at = 500 })
Store:AddEvent(dB, { type = "looted", actor = "X", at = 500 })
local pick1 = Tracker:FindDropForItem(777)
-- Re-run several times; pairs() order may vary, the answer must not.
local stable = true
for _ = 1, 20 do if Tracker:FindDropForItem(777) ~= pick1 then stable = false end end
check(stable, "FindDropForItem is deterministic across calls for tied drops")
check(pick1 == dB, "tie-break selects the lexicographically larger dropID (client-identical)")

-- Whitelist filter: only items that belong to the CURRENT instance are trackable.
local sources = {
    [7230] = { instance = "The Deadmines", boss = "Mr. Smite", instanceID = 36 },
    [5187] = { instance = "The Deadmines", boss = "Rhahk'Zor", instanceID = 36 },
    [22559] = { instance = "Karazhan", boss = "Moroes", instanceID = 532 },
    [99001] = { instance = "Dire Maul East", boss = "Pusillin" },  -- no instanceID (name fallback)
}
-- In Deadmines (id 36): Deadmines items pass, Karazhan items fail, unknown items fail.
check(Tracker:IsTrackableItem(7230, 36, "Deadmines", sources) == true, "Deadmines item tracked in Deadmines (by instanceID)")
check(Tracker:IsTrackableItem(22559, 36, "Deadmines", sources) == false, "Karazhan item NOT tracked in Deadmines")
check(Tracker:IsTrackableItem(123456, 36, "Deadmines", sources) == false, "unknown item (not in table) not tracked")
-- In Karazhan (id 532): Kara item passes, Deadmines item fails.
check(Tracker:IsTrackableItem(22559, 532, "Karazhan", sources) == true, "Karazhan item tracked in Karazhan")
check(Tracker:IsTrackableItem(7230, 532, "Karazhan", sources) == false, "Deadmines item NOT tracked in Karazhan")
-- Name fallback when the data entry has no instanceID (Dire Maul): match by instance name.
check(Tracker:IsTrackableItem(99001, nil, "Dire Maul East", sources) == true, "no-instanceID entry matches by instance name")
check(Tracker:IsTrackableItem(99001, nil, "Stormwind", sources) == false, "no-instanceID entry rejected for wrong instance name")

local instanceName, instanceType, difficultyID, instanceID = "The Deadmines", "party", 1, 36
function GetInstanceInfo() return instanceName, instanceType, difficultyID, nil, nil, nil, nil, instanceID end
local r = Store:Get()
r.sessions = {}
r.instanceAnchors = {}
Tracker.wasInInstance = nil
Tracker.instanceEnterAt = nil
Tracker.currentInstanceAnchorKey = nil
Tracker.currentInstanceType = nil
Tracker.activeSessionID = nil
Tracker:OnWorldChanged(false, false)
local firstDungeonSession = Tracker.activeSessionID
Tracker:StartSessionNow(false)
check(Tracker.activeSessionID == firstDungeonSession, "party session is stable while continuously inside the instance")
instanceType = "none"
Tracker:OnWorldChanged(false, false)
testNow = testNow + 30
instanceType = "party"
Tracker:OnWorldChanged(false, false)
local secondDungeonSession = Tracker.activeSessionID
check(firstDungeonSession ~= secondDungeonSession, "party re-entry after leaving creates a fresh history session")
Tracker.instanceEnterAt = nil
Tracker.currentInstanceAnchorKey = nil
Tracker.currentInstanceType = nil
Tracker.activeSessionID = nil
Tracker.wasInInstance = nil
Tracker:OnWorldChanged(true, true)
check(Tracker.activeSessionID == secondDungeonSession, "party reload/login inside instance reuses the current history session")

-- Duplicate same-item drops from one corpse must remain separate history rows.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureSession("DUP", { scope = "guild", instance = "Serpentshrine Cavern" })
Tracker.activeSessionID = "DUP"
Tracker.nameByGUID = { ["Creature-SSC-Vashj"] = "Lady Vashj" }
Tracker.pendingLootByItem = nil
ns.lootSources = { byItemId = { [30245] = { instance = "Serpentshrine Cavern", boss = "Lady Vashj", instanceID = 548 } } }
function GetInstanceInfo() return "Serpentshrine Cavern", "raid", 14, nil, nil, nil, nil, 548 end
function GetNumLootItems() return 2 end
function GetLootSlotLink(slot) return slot <= 2 and "|cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r" or nil end
function GetLootSourceInfo(slot) return slot <= 2 and "Creature-SSC-Vashj" or nil end
function GetItemInfo() return "Chestguard of the Vanquished Hero", nil, 4, nil, nil, "Armor", nil, nil, nil, "icon", nil, 4 end
function UnitName(unit) return unit == "player" and "Alice" or nil end
Tracker:OnLootOpened()
Tracker:TrackLootMessage("Bob receives loot: |cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r.")
Tracker:TrackLootMessage("Cara receives loot: |cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r.")
local tokenDrops, owners = 0, {}
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "DUP" and drop.itemId == 30245 then
        tokenDrops = tokenDrops + 1
        local state = Store:ComputeState(drop)
        owners[state.finalOwner or "?"] = true
    end
end
check(tokenDrops == 2, "duplicate same-token loot slots create two history drops")
check(owners.Bob and owners.Cara, "duplicate same-token drops keep separate recipients")

for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureSession("CHATDUP", { scope = "guild", instance = "Serpentshrine Cavern" })
Tracker.activeSessionID = "CHATDUP"
Tracker.pendingLootByItem = nil
Tracker:TrackLootMessage("Bob receives loot: |cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r.")
Tracker:TrackLootMessage("Cara receives loot: |cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r.")
Tracker:TrackLootMessage("Cara receives loot: |cff0070dd|Hitem:30245::::::::|h[Chestguard of the Vanquished Hero]|h|r.")
tokenDrops, owners = 0, {}
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "CHATDUP" and drop.itemId == 30245 then
        tokenDrops = tokenDrops + 1
        local state = Store:ComputeState(drop)
        owners[state.finalOwner or "?"] = true
    end
end
check(tokenDrops == 2, "chat-only duplicate same-token recipients create two history drops")
check(owners.Bob and owners.Cara, "chat-only duplicate same-token drops keep separate recipients without duplicating repeated chat")

-- A successful trade in a later/different instance must update the original drop's session.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:Sessions().SSC = { sessionID = "SSC", scope = "guild", instance = "Serpentshrine Cavern" }
Store:Sessions().TK = { sessionID = "TK", scope = "guild", instance = "Tempest Keep" }
Store:EnsureDrop("SSC:30029", { sessionID = "SSC", itemId = 30029, itemName = "Boots of Courage Unending" })
Store:AddEvent("SSC:30029", { type = "looted", actor = "Dedajbt", at = 1 })
Tracker.activeSessionID = "TK"
function UnitName(unit) return unit == "player" and "Dedajbt" or nil end
_G = _G or {}
_G.TradeFrameRecipientNameText = { GetText = function() return "Winner" end }
local bagItems = { [1] = { itemID = 30029, hyperlink = "|cff0070dd|Hitem:30029::::::::|h[Boots of Courage Unending]|h|r" } }
C_Container = {
    GetContainerNumSlots = function() return #bagItems end,
    GetContainerItemInfo = function(_, slot) return bagItems[slot] end,
}
Tracker.pendingClose = nil
Tracker.tradeTarget = nil
Tracker:OnTradeShow()
Tracker:MarkTradeComplete()
bagItems = {}
Tracker:OnTradeClosed()
local tradedState = Store:ComputeState(Store:Drops()["SSC:30029"])
check(tradedState.status == "traded" and tradedState.finalOwner == "Winner", "trade in a later active session updates original loot session final owner")

-- The same trade must work after the raid/session has ended and activeSessionID is nil.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:30030", { sessionID = "SSC", itemId = 30030, itemName = "World-Breaker" })
Store:AddEvent("SSC:30030", { type = "looted", actor = "Dedajbt", at = 1 })
Tracker.activeSessionID = nil
_G.TradeFrameRecipientNameText = { GetText = function() return "Latewinner" end }
bagItems = { [1] = { itemID = 30030, hyperlink = "|cff0070dd|Hitem:30030::::::::|h[World-Breaker]|h|r" } }
Tracker.pendingClose = nil
Tracker.tradeTarget = nil
Tracker:OnTradeShow()
Tracker:MarkTradeComplete()
bagItems = {}
Tracker:OnTradeClosed()
tradedState = Store:ComputeState(Store:Drops()["SSC:30030"])
check(tradedState.status == "traded" and tradedState.finalOwner == "Latewinner", "trade after leaving the active session updates original loot session final owner")

-- Receiving the same physical item back must append a reverse trade to the original drop.
Tracker.activeSessionID = nil
function UnitName(unit) return unit == "player" and "Dedajbt" or nil end
_G.TradeFrameRecipientNameText = { GetText = function() return "Latewinner" end }
bagItems = {}
Tracker.pendingClose = nil
Tracker.tradeTarget = nil
Tracker:OnTradeShow()
Tracker:MarkTradeComplete()
bagItems = { [1] = { itemID = 30030, hyperlink = "|cff0070dd|Hitem:30030::::::::|h[World-Breaker]|h|r" } }
Tracker:OnTradeClosed()
tradedState = Store:ComputeState(Store:Drops()["SSC:30030"])
check(tradedState.status == "traded" and tradedState.currentHolder == "Dedajbt" and tradedState.finalOwner == "Dedajbt", "receiving a traded item back updates the original drop final owner")
function GetInventoryItemID() return 30030 end
Tracker:OnEquipmentChanged(16)
tradedState = Store:ComputeState(Store:Drops()["SSC:30030"])
check(tradedState.status == "finalized" and tradedState.currentHolder == "Dedajbt", "equipping a returned traded item finalizes the original drop")

-- Removal events outside an active session must still notify sync for the original guild session.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:30031", { sessionID = "SSC", itemId = 30031, itemName = "Ring of Endless Coils" })
Store:AddEvent("SSC:30031", { type = "looted", actor = "Dedajbt", at = 1 })
Tracker.activeSessionID = nil
local changed = {}
ns.modules.LootSync = { OnLocalChange = function(_, sessionID) changed[#changed + 1] = sessionID end }
Tracker.merchantOpen = true
Tracker:DetectRemovals({ counts = { [30031] = 1 } }, { counts = {} }, "Dedajbt")
local removedState = Store:ComputeState(Store:Drops()["SSC:30031"])
check(removedState.status == "vendored" and changed[1] == "SSC", "vendored item outside active session syncs original loot session")
Tracker.merchantOpen = false
ns.modules.LootSync = nil

-- Opening a vendor after receiving a trade must use a fresh bag baseline, not an old snapshot.
-- Otherwise the received item is absent from the "before" snapshot and selling it is invisible.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:99911", { sessionID = "SSC", itemId = 99911, itemName = "Received Vendor Test", itemGUID = "TradeVendGUID" })
Store:AddEvent("SSC:99911", { type = "looted", actor = "Bob", at = 1 })
Store:AddEvent("SSC:99911", { type = "traded", actor = "Bob", target = "Dedajbt", at = 2 })
function UnitName(unit) return unit == "player" and "Dedajbt" or nil end
bagItems = { [0] = { [1] = { itemID = 99911, hyperlink = "|cff1eff00|Hitem:99911::::::::|h[Received Vendor Test]|h|r", guid = "TradeVendGUID" } } }
C_Container = {
    GetContainerNumSlots = function(bag) return bagItems[bag] and #bagItems[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return bagItems[bag] and bagItems[bag][slot] end,
}
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
}
C_Item = {
    DoesItemExist = function(loc) return loc and bagItems[loc.bag] and bagItems[loc.bag][loc.slot] ~= nil end,
    GetItemGUID = function(loc)
        local row = loc and bagItems[loc.bag] and bagItems[loc.bag][loc.slot]
        return row and row.guid or nil
    end,
}
Tracker.activeSessionID = nil
Tracker.lastBagSnapshot = { byGuid = {}, byItemId = {}, counts = {} }
Tracker:OnMerchantOpened()
bagItems = { [0] = {} }
Tracker:AuditBags()
local receivedVendorState = Store:ComputeState(Store:Drops()["SSC:99911"])
check(receivedVendorState.status == "vendored", "vendoring a received traded item is detected from a fresh merchant baseline")
Tracker.merchantOpen = false
Tracker.lastMerchantAt = nil
Tracker.lastBagSnapshot = nil
C_Item = nil
ItemLocation = nil
C_Container = {
    GetContainerNumSlots = function() return #bagItems end,
    GetContainerItemInfo = function(_, slot) return bagItems[slot] end,
}

-- If a client cannot resolve GUIDs, a traded item is still removable when the local player is
-- the current holder. The same fallback must not match items already traded away.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:99912", { sessionID = "SSC", itemId = 99912, itemName = "No GUID Local Trade" })
Store:AddEvent("SSC:99912", { type = "looted", actor = "Bob", at = 1 })
Store:AddEvent("SSC:99912", { type = "traded", actor = "Bob", target = "Dedajbt", at = 2 })
local localTradeDrop = Tracker:FindDropForItem(99912)
check(localTradeDrop == "SSC:99912", "traded item without GUID remains matchable when local player is current holder")
Store:EnsureDrop("SSC:99913", { sessionID = "SSC", itemId = 99913, itemName = "No GUID Away Trade" })
Store:AddEvent("SSC:99913", { type = "looted", actor = "Dedajbt", at = 1 })
Store:AddEvent("SSC:99913", { type = "traded", actor = "Dedajbt", target = "Other", at = 2 })
local awayTradeDrop = Tracker:FindDropForItem(99913)
check(awayTradeDrop == nil, "traded item without GUID is not matched after local player traded it away")

-- A recipe item that is consumed outside merchant/disenchant/guild-bank/NPC/delete contexts is
-- finalized as learned, not as an inactivity timeout.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:99914", { sessionID = "SSC", itemId = 99914, itemName = "Recipe: Test", itemGUID = "RecipeGUID" })
Store:AddEvent("SSC:99914", { type = "looted", actor = "Dedajbt", at = 1 })
Tracker.activeSessionID = nil
Tracker.merchantOpen = false
Tracker.lastMerchantAt = nil
Tracker.guildBankOpen = false
Tracker.lastGuildBankAt = nil
Tracker.disenchantPending = nil
Tracker.npcInteractionUntil = nil
function GetItemInfo(itemID)
    if itemID == 99914 then return "Recipe: Test", nil, 4, nil, nil, "Recipe", nil, nil, nil, "icon", nil, 9 end
    return "Unknown", nil, 4, nil, nil, "Armor", nil, nil, nil, "icon", nil, 4
end
Tracker:DetectRemovals({
    byGuid = { ["RecipeGUID"] = { itemId = 99914, itemGuid = "RecipeGUID" } },
    counts = { [99914] = 1 },
}, {
    byGuid = {},
    counts = {},
}, "Dedajbt")
local recipeState = Store:ComputeState(Store:Drops()["SSC:99914"])
check(recipeState.status == "finalized", "consumed recipe item is finalized as learned")

-- Duplicate same-item removals must prefer itemGUID so vendoring one token copy does not mark
-- the other player's identical token as vendored.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:TOKEN:A", { sessionID = "SSC", itemId = 30245, itemName = "Chestguard of the Vanquished Hero", itemGUID = "ItemGUID-A" })
Store:EnsureDrop("SSC:TOKEN:B", { sessionID = "SSC", itemId = 30245, itemName = "Chestguard of the Vanquished Hero", itemGUID = "ItemGUID-B" })
Store:AddEvent("SSC:TOKEN:A", { type = "looted", actor = "Bob", at = 1 })
Store:AddEvent("SSC:TOKEN:B", { type = "looted", actor = "Cara", at = 1 })
Tracker.activeSessionID = nil
Tracker.merchantOpen = true
Tracker:DetectRemovals({
    byGuid = {
        ["ItemGUID-A"] = { itemId = 30245, itemGuid = "ItemGUID-A" },
        ["ItemGUID-B"] = { itemId = 30245, itemGuid = "ItemGUID-B" },
    },
    counts = { [30245] = 2 },
}, {
    byGuid = {
        ["ItemGUID-A"] = { itemId = 30245, itemGuid = "ItemGUID-A" },
    },
    counts = { [30245] = 1 },
}, "Cara")
local tokenAState = Store:ComputeState(Store:Drops()["SSC:TOKEN:A"])
local tokenBState = Store:ComputeState(Store:Drops()["SSC:TOKEN:B"])
check(tokenAState.status == "obtained" and tokenBState.status == "vendored", "vendoring one duplicate token uses itemGUID and leaves the other token untouched")
Tracker.merchantOpen = false

-- Equipping one of two duplicate tokens must also use the equipment itemGUID.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
Store:EnsureDrop("SSC:EQTOKEN:A", { sessionID = "SSC", itemId = 30245, itemName = "Chestguard of the Vanquished Hero", itemGUID = "EquipGUID-A" })
Store:EnsureDrop("SSC:EQTOKEN:B", { sessionID = "SSC", itemId = 30245, itemName = "Chestguard of the Vanquished Hero", itemGUID = "EquipGUID-B" })
Store:AddEvent("SSC:EQTOKEN:A", { type = "looted", actor = "Bob", at = 1 })
Store:AddEvent("SSC:EQTOKEN:B", { type = "looted", actor = "Cara", at = 1 })
function GetInventoryItemID() return 30245 end
ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return "eq" .. tostring(slot) end }
C_Item = {
    DoesItemExist = function() return true end,
    GetItemGUID = function(loc) return loc == "eq16" and "EquipGUID-B" or nil end,
}
Tracker:OnEquipmentChanged(16)
local equipAState = Store:ComputeState(Store:Drops()["SSC:EQTOKEN:A"])
local equipBState = Store:ComputeState(Store:Drops()["SSC:EQTOKEN:B"])
check(equipAState.status == "obtained" and equipBState.status == "finalized", "equipping one duplicate token uses equipment itemGUID and leaves the other token untouched")
C_Item = nil
ItemLocation = nil

-- /iddqd loottest must make dungeon green/blue items usable for History tracking tests.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "TESTSTOCKS"
Store:EnsureSession("TESTSTOCKS", { scope = "personal", instance = "The Stockade" })
ns.lootSources = { byItemId = {} }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetNumLootItems() return 1 end
function GetLootSlotLink(slot) return slot == 1 and "|cff1eff00|Hitem:99901::::::::|h[Test Green Boots]|h|r" or nil end
function GetLootSourceInfo() return "Creature-Stockades-Test" end
function GetItemInfo() return "Test Green Boots", nil, 2, nil, nil, "Armor", nil, nil, nil, "icon", nil, 4 end
Tracker.nameByGUID = { ["Creature-Stockades-Test"] = "Stockades Test Mob" }
Tracker.pendingLootByItem = nil
Tracker:OnLootOpened()
local trackedTestDrop = false
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "TESTSTOCKS" and drop.itemId == 99901 then trackedTestDrop = true end
end
check(trackedTestDrop, "loottest lets History track unknown green dungeon items for controlled trade testing")
ns.LOOT_DIST_TEST = nil

-- /iddqd loottest must also capture party-visible loot chat for items won by another character.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "CHATSTOCKS"
Store:EnsureSession("CHATSTOCKS", { scope = "personal", instance = "The Stockade" })
ns.lootSources = { byItemId = {} }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetItemInfo() return "Chat Test Axe", nil, 2, nil, nil, "Weapon", nil, nil, nil, "icon", nil, 2 end
Tracker.pendingLootByItem = nil
Tracker:TrackLootMessage("Sylo receives loot: |cff1eff00|Hitem:99903::::::::|h[Chat Test Axe]|h|r.")
local chatDrop
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "CHATSTOCKS" and drop.itemId == 99903 then chatDrop = drop end
end
local chatState = Store:ComputeState(chatDrop)
check(chatState.finalOwner == "Sylo", "loottest captures unknown green items won by another party member from loot chat")
ns.LOOT_DIST_TEST = nil

-- Group-loot roll frames should create the pending drop; the later loot chat assigns the winner.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "ROLLSTOCKS"
Store:EnsureSession("ROLLSTOCKS", { scope = "personal", instance = "The Stockade" })
ns.lootSources = { byItemId = {} }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetLootRollItemLink(rollID) return rollID == 77 and "|cff1eff00|Hitem:99905::::::::|h[Rolled Test Ring]|h|r" or nil end
function GetItemInfo() return "Rolled Test Ring", nil, 2, nil, nil, "Armor", nil, nil, "INVTYPE_FINGER", "icon", nil, 4 end
Tracker.pendingLootByItem = nil
Tracker.rollDrops = nil
Tracker:OnStartLootRoll(77)
Tracker:TrackLootMessage("Cylo receives loot: |cff1eff00|Hitem:99905::::::::|h[Rolled Test Ring]|h|r.")
local rollDrop
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "ROLLSTOCKS" and drop.itemId == 99905 then rollDrop = drop end
end
local rollState = Store:ComputeState(rollDrop)
check(rollState.finalOwner == "Cylo", "loottest roll frame plus winner loot chat records the group-loot recipient")
ns.LOOT_DIST_TEST = nil

-- Loot-window capture and group-loot roll capture are two observations of the same physical
-- drop. They must converge to one row, with the final winner coming from loot chat.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "ROLLWINDOWSTOCKS"
Store:EnsureSession("ROLLWINDOWSTOCKS", { scope = "personal", instance = "The Stockade" })
ns.lootSources = { byItemId = {} }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetNumLootItems() return 1 end
function GetLootSlotLink(slot) return slot == 1 and "|cff1eff00|Hitem:99906::::::::|h[Window Roll Test Axe]|h|r" or nil end
function GetLootSourceInfo() return "Creature-Stockades-Captive" end
function GetLootRollItemLink(rollID) return rollID == 88 and "|cff1eff00|Hitem:99906::::::::|h[Window Roll Test Axe]|h|r" or nil end
function GetItemInfo() return "Window Roll Test Axe", nil, 2, nil, nil, "Weapon", nil, nil, "INVTYPE_2HWEAPON", "icon", nil, 2 end
Tracker.pendingLootByItem = nil
Tracker.rollDrops = nil
Tracker.nameByGUID = { ["Creature-Stockades-Captive"] = "Defias Captive" }
Tracker:OnLootOpened()
Tracker:OnStartLootRoll(88)
Tracker:TrackLootMessage("Cylo receives loot: |cff1eff00|Hitem:99906::::::::|h[Window Roll Test Axe]|h|r.")
local convergedDrop, convergedCount
convergedCount = 0
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "ROLLWINDOWSTOCKS" and drop.itemId == 99906 then
        convergedDrop = drop
        convergedCount = convergedCount + 1
    end
end
local convergedState = Store:ComputeState(convergedDrop)
check(convergedCount == 1 and convergedState.finalOwner == "Cylo", "loot window plus roll frame converge to one history drop with the winner from loot chat")
ns.LOOT_DIST_TEST = nil

-- The inverse event order is common live: roll frame first, corpse loot window later.
-- That must also converge to one row instead of creating fallback + corpse duplicates.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "ROLLFIRSTSTOCKS"
Store:EnsureSession("ROLLFIRSTSTOCKS", { scope = "personal", instance = "The Stockade" })
ns.lootSources = { byItemId = {} }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetNumLootItems() return 1 end
function GetLootSlotLink(slot) return slot == 1 and "|cff1eff00|Hitem:99907::::::::|h[Roll First Test Sword]|h|r" or nil end
function GetLootSourceInfo() return "Creature-Stockades-Captive" end
function GetLootRollItemLink(rollID) return rollID == 89 and "|cff1eff00|Hitem:99907::::::::|h[Roll First Test Sword]|h|r" or nil end
function GetItemInfo() return "Roll First Test Sword", nil, 2, nil, nil, "Weapon", nil, nil, "INVTYPE_WEAPON", "icon", nil, 2 end
Tracker.pendingLootByItem = nil
Tracker.rollDrops = nil
Tracker.nameByGUID = { ["Creature-Stockades-Captive"] = "Defias Captive" }
Tracker:OnStartLootRoll(89)
Tracker:OnLootOpened()
Tracker:TrackLootMessage("Cylo receives loot: |cff1eff00|Hitem:99907::::::::|h[Roll First Test Sword]|h|r.")
local rollFirstDrop, rollFirstCount
rollFirstCount = 0
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "ROLLFIRSTSTOCKS" and drop.itemId == 99907 then
        rollFirstDrop = drop
        rollFirstCount = rollFirstCount + 1
    end
end
local rollFirstState = Store:ComputeState(rollFirstDrop)
check(rollFirstCount == 1 and rollFirstState.finalOwner == "Cylo", "roll frame before loot window still converges to one history drop")
ns.LOOT_DIST_TEST = nil

-- In test mode, a receiver who lacks the original personal session gets a local placeholder.
for k in pairs(Store:Drops()) do Store:Drops()[k] = nil end
r.sessions = {}
ns.LOOT_DIST_TEST = true
Tracker.activeSessionID = "RECEIVERTEST"
Store:EnsureSession("RECEIVERTEST", { scope = "personal", instance = "The Stockade" })
function UnitName(unit) return unit == "player" and "Winner" or nil end
_G.TradeFrameRecipientNameText = { GetText = function() return "Dedajbt" end }
function GetInstanceInfo() return "The Stockade", "party", 1, nil, nil, nil, nil, 34 end
function GetItemInfo() return "Received Test Sword", nil, 2, nil, nil, "Weapon", nil, nil, nil, "icon", nil, 2 end
bagItems = {}
Tracker.pendingClose = nil
Tracker.tradeTarget = nil
Tracker:OnTradeShow()
Tracker:MarkTradeComplete()
bagItems = { [1] = { itemID = 99902, hyperlink = "|cff1eff00|Hitem:99902::::::::|h[Received Test Sword]|h|r" } }
Tracker:OnTradeClosed()
local receiverDrop
for _, drop in pairs(Store:Drops()) do
    if drop.sessionID == "RECEIVERTEST" and drop.itemId == 99902 then receiverDrop = drop end
end
local receiverState = Store:ComputeState(receiverDrop)
check(receiverState.status == "traded" and receiverState.currentHolder == "Winner" and receiverState.finalOwner == "Winner", "loottest receiver creates a visible placeholder for unknown received trade items")
ns.LOOT_DIST_TEST = nil

print(("loot_tracker_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
