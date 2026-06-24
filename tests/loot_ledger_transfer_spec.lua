local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local now = 2000
function time() return now end
function date() return "now" end
function UnitName() return "Nemazuve" end
function GetNormalizedRealmName() return "Spineshatter" end
function GetRealmName() return "Spineshatter" end
local instanceName, instanceType, difficultyId, instanceId = "Serpentshrine Cavern", "raid", 14, 548
function GetInstanceInfo()
    return instanceName, instanceType, difficultyId, nil, nil, nil, nil, instanceId
end
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

ns.modules.DB = { db = { raidLootLedger = { drops = {}, sessionCounter = 0 }, settings = { raidLootLedger = {} } } }

assert(loadfile(DIR .. "Modules/LootLedger/LootLedger.lua"))("iddqd", ns)
local Ledger = ns:GetModule("LootLedger")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

table.insert(Ledger:Drops(), {
    dropInstanceId = "test:29925",
    lootId = "test:29925",
    itemId = 29925,
    itemName = "Phoenix-Ring of Rebirth",
    firstHolder = "Nemazuve-Spineshatter",
    currentHolder = "Nemazuve-Spineshatter",
    status = "pending",
    droppedAt = now,
    events = {},
})

local message = "Gargul : I gave |cffa335ee|Hitem:29925::::::::|h[Phoenix-Ring of Rebirth]|h|r to Meowerick-Spineshatter"
local fromPlayer, itemLink, toPlayer = Ledger:ParseGargulHandout(message, "Nemazuve-Spineshatter")
check(fromPlayer == "Nemazuve-Spineshatter", "Gargul parser resolves announcer")
check(itemLink and itemLink:find("item:29925", 1, true), "Gargul parser resolves item link")
check(toPlayer == "Meowerick-Spineshatter", "Gargul parser resolves recipient")

check(Ledger:TrackGargulMessage(message, "Nemazuve-Spineshatter") == false, "Gargul handout is ignored by default")
local drop = Ledger:Drops()[1]
check(drop.currentHolder == "Nemazuve-Spineshatter", "Gargul fallback does not move loot while disabled")
ns.modules.DB.db.settings.raidLootLedger.allowGargulFallback = true
check(Ledger:TrackGargulMessage(message, "Nemazuve-Spineshatter") == true, "optional Gargul fallback can update tracked loot")
check(drop.currentHolder == "Meowerick-Spineshatter", "current holder moves to Gargul recipient")
check(drop.status == "traded", "Gargul handout marks loot as traded")
check(drop.events[#drop.events].type == "external_gargul_fallback", "Gargul fallback is auditable as external fallback")

local spoof = "Gargul : I gave |cffa335ee|Hitem:29925::::::::|h[Phoenix-Ring of Rebirth]|h|r to Someone-Spineshatter"
check(Ledger:TrackGargulMessage(spoof, "Random-Spineshatter") == false, "Gargul handout from non-holder is ignored")

drop.currentHolder = "Meowerick"
check(Ledger:ApplyTransfer(29925, nil, "Meowerick-Spineshatter", "Nemazuve-Spineshatter", now + 1, false, "trade_completed") == true, "transfer matching accepts stored short names")
check(drop.currentHolder == "Nemazuve-Spineshatter", "short-name transfer updates current holder")

drop.currentHolder = "Nemazuve-Spineshatter"
drop.status = "removed_unknown"
check(Ledger:ApplyTransfer(29925, nil, "Nemazuve-Spineshatter", "Meowerick-Spineshatter", now + 2, false, "trade_completed") == true, "completed trade recovers rows marked removed by bag audits")
check(drop.status == "traded", "recovered removed row is marked as traded")
check(drop.currentHolder == "Meowerick-Spineshatter", "recovered removed row moves to trade recipient")

table.insert(Ledger:Drops(), {
    dropInstanceId = "test:30236",
    lootId = "test:30236",
    itemGuid = "Item-Token-Guid",
    itemId = 30236,
    itemName = "Chestguard of the Vanquished Defender",
    firstHolder = "Nemazuve-Spineshatter",
    currentHolder = "Nemazuve-Spineshatter",
    status = "pending",
    droppedAt = now,
    events = {},
})
Ledger.CurrentBagGuids = function() return {} end
Ledger.lastNpcExchangeAt = now
Ledger:AuditMissingLocalTrackedGuids()
local token = Ledger:Drops()[2]
check(token.status == "obtained", "token turn-in marks missing tracked loot as obtained")
check(token.finalOwner == "Nemazuve-Spineshatter", "token turn-in keeps final owner on current holder")

table.insert(Ledger:Drops(), {
    dropInstanceId = "test:29996",
    lootId = "test:29996",
    itemGuid = "Item-Guild-Bank-Guid",
    itemId = 29996,
    itemName = "Rod of the Sun King",
    firstHolder = "Nemazuve-Spineshatter",
    currentHolder = "Nemazuve-Spineshatter",
    status = "pending",
    droppedAt = now,
    events = {},
})
Ledger.CurrentBagGuids = function() return {} end
Ledger.lastNpcExchangeAt = nil
Ledger:NoteGuildBankOpen()
Ledger:AuditMissingLocalTrackedGuids()
local banked = Ledger:Drops()[3]
check(banked.status == "guild_bank", "tracked loot missing while guild bank is open is marked as guild bank")
check(banked.currentHolder == "Guild Bank", "guild bank deposit moves current holder to Guild Bank")
check(banked.depositedBy == "Nemazuve-Spineshatter", "guild bank deposit records depositor")

table.insert(Ledger:Drops(), {
    dropInstanceId = "test:30237",
    lootId = "test:30237",
    itemGuid = "Item-Old-Token-Guid",
    itemId = 30237,
    itemName = "Chestguard of the Vanquished Defender",
    firstHolder = "Cylo-Spineshatter",
    currentHolder = "Cylo-Spineshatter",
    status = "removed_unknown",
    droppedAt = now,
    events = {
        { type = "removed_unknown", reason = "bag_guid_missing", at = now },
    },
})
Ledger:RepairTierTokenTurnIns()
local repaired = Ledger:Drops()[4]
check(repaired.status == "obtained", "old removed tier-token rows are repaired on init")
check(repaired.finalOwner == "Cylo-Spineshatter", "repaired tier-token rows keep the token holder")

C_Container = {
    GetContainerNumSlots = function() return 1 end,
    GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then
            return {
                itemID = 30319,
                hyperlink = "|cffff8000|Hitem:30319::::::::|h[Nether Spike]|h|r",
                iconFileID = 135753,
                stackCount = 1,
            }
        end
        return nil
    end,
}
Ledger.TradeableTooltipLine = function() return "May be traded" end
check(#Ledger:ActiveTradableItems() == 0, "ignored encounter items are hidden from active tradeable loot")

instanceName, instanceType, difficultyId, instanceId = "The Deadmines", "party", 1, 36
check(Ledger:IsRaidItem(5191, 3, { equipLoc = "INVTYPE_2HWEAPON", quality = 3 }) == true, "Deadmines equipment is allowed for loot-session testing")
instanceName, instanceType, difficultyId, instanceId = "The Stockade", "party", 1, 34
check(Ledger:IsRaidItem(5191, 3, { equipLoc = "INVTYPE_2HWEAPON", quality = 3 }) == false, "other dungeon equipment remains ignored")

print(("loot_ledger_transfer_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
