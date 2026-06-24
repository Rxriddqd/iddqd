local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local now = 1000
function time() return now end
function date() return "now" end
function UnitName() return "Tester" end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
function strsplit(sep, value)
    value = tostring(value or "")
    local out = {}
    for part in (value .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return table.unpack(out)
end

local instanceName, instanceType, difficultyId, instanceId = "Serpentshrine Cavern", "raid", 14, 548
function GetInstanceInfo()
    return instanceName, instanceType, difficultyId, nil, nil, nil, nil, instanceId
end

ns.modules.DB = { db = { raidLootLedger = { drops = {}, sessionCounter = 0 }, settings = { raidLootLedger = {} } } }
ns.raidLootSources = {
    byItemId = {
        [30029] = { instance = "Tempest Keep", source = "Trash" },
        [30022] = { instance = "Serpentshrine Cavern", source = "Trash" },
        [30075] = { instance = "Serpentshrine Cavern", source = "Morogrim" },
    },
}

assert(loadfile(DIR .. "Modules/LootLedger/LootLedger.lua"))("iddqd", ns)
local Ledger = ns:GetModule("LootLedger")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local raidCtx = Ledger:CurrentRaidContext()
local raidSession = Ledger:EnsureSessionForLoot(raidCtx, 30001, "Hydross the Unstable", now)
table.insert(Ledger:Drops(), {
    sessionKey = raidSession.id,
    itemId = 30001,
    bossName = "Hydross the Unstable",
    sourceInstance = instanceName,
    instanceType = instanceType,
    instanceId = instanceId,
    difficultyId = difficultyId,
    droppedAt = now,
})

now = now + 300
local sameRaidSession = Ledger:EnsureSessionForLoot(raidCtx, 30002, "Hydross the Unstable", now)
check(sameRaidSession.id == raidSession.id, "raid repeat boss loot stays in the same session")

Ledger.lastBossName = "Hydross the Unstable"
Ledger.lastBossAt = now
check(Ledger:BossAttributionName(now + 120) == "Hydross the Unstable", "boss attribution applies shortly after a kill")
check(Ledger:BossAttributionName(now + 240) == nil, "boss attribution expires before later trash loot")
local source = Ledger:RaidLootSource(30022, "Serpentshrine Cavern")
check(source == "Trash", "raid loot source table resolves known trash drops")
local bossSource = Ledger:RaidLootSource(30075, "Serpentshrine Cavern")
check(bossSource == "Morogrim", "raid loot source table resolves known boss drops")
check(Ledger:RaidLootSource(30075, "Coilfang Reservoir") == "Morogrim", "raid loot source table survives client instance label differences")
check(Ledger:IsRaidItem(30313, 5, { equipLoc = "INVTYPE_2HWEAPON" }) == false, "Kael'thas encounter weapons are ignored")
check(Ledger:IsRaidItem(30319, 5, { equipLoc = "INVTYPE_AMMO" }) == false, "Kael'thas encounter arrows are ignored")
check(Ledger:IsRaidItem(30022, 4, { equipLoc = "INVTYPE_CLOAK" }) == true, "known raid loot table items are tracked")
check(Ledger:IsRaidItem(99999, 4, { equipLoc = "INVTYPE_FINGER" }) == false, "unknown epic equipment is not tracked as raid loot")
check(Ledger:IsTrackedRaidDrop({ itemId = 99999, instanceType = "raid" }) == false, "unknown raid-context drops are not displayed as tracked raid loot")

table.insert(Ledger:Drops(), {
    itemId = 30029,
    itemName = "Bark-Gloves of Ancient Wisdom",
    bossName = "Void Reaver",
    sourceInstance = "Tempest Keep",
    currentHolder = "Cylo-Spineshatter",
    status = "pending",
    droppedAt = now,
    events = {},
})
Ledger:NormalizeKnownRaidSources()
local trashDrop = Ledger:Drops()[#Ledger:Drops()]
check(trashDrop.bossName == "Trash", "known trash drops are repaired away from stale boss labels")
check(trashDrop.bossSourceType == "loot_table", "repaired trash drops are marked as loot-table sourced")

table.insert(Ledger:Drops(), {
    itemId = 99999,
    itemName = "Random BOE Epic",
    bossName = "Leotheras the Blind",
    sourceInstance = "Serpentshrine Cavern",
    instanceType = "raid",
    instanceId = 548,
    status = "pending",
    droppedAt = now,
    events = {},
})
Ledger:PruneDungeonLootDrops()
local foundUnknownRaidDrop = false
for _, drop in ipairs(Ledger:Drops()) do
    if drop.itemId == 99999 then foundUnknownRaidDrop = true end
end
check(foundUnknownRaidDrop == false, "unknown BOE raid-context drops are pruned from history")

instanceName, instanceType, difficultyId, instanceId = "The Deadmines", "party", 1, 36
now = now + 1000
local partyCtx = Ledger:CurrentRaidContext()
local partySession = Ledger:EnsureSessionForLoot(partyCtx, 5191, "", now)
table.insert(Ledger:Drops(), {
    sessionKey = partySession.id,
    itemId = 5191,
    bossName = "",
    sourceInstance = instanceName,
    instanceType = instanceType,
    instanceId = instanceId,
    difficultyId = difficultyId,
    droppedAt = now,
})

now = now + 120
local splitPartySession = Ledger:EnsureSessionForLoot(partyCtx, 5191, "", now)
check(splitPartySession.id ~= partySession.id, "dungeon repeated unknown item can still create a new session")

ns.modules.DB.db.raidLootLedger.activeSession = nil
ns.modules.DB.db.raidLootLedger.sessionCounter = 41
Ledger.sessionKey = nil
local exported = Ledger:ExportPayload()
check(exported.raid ~= nil, "export includes passive current instance context")
check(ns.modules.DB.db.raidLootLedger.activeSession == nil, "export does not create an active session")
check(ns.modules.DB.db.raidLootLedger.sessionCounter == 41, "export does not increment session counter")

print(("loot_ledger_session_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
