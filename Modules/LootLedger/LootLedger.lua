local ADDON, ns = ...

local Ledger = ns:NewModule("LootLedger")

local COMM_PREFIX = "IDDQD_LOOT"
local EXPORT_VERSION = 1
local MAX_DROPS = 600
local MAX_EVENTS_PER_DROP = 40
local SESSION_REUSE_SECONDS = 6 * 60 * 60
local REPEAT_DROP_SPLIT_SECONDS = 90
local DUPLICATE_DROP_WINDOW_SECONDS = 90
local BOSS_LOOT_ATTRIBUTION_SECONDS = 180
local LOOT_SYNC_RECENT_SECONDS = 72 * 60 * 60
local LOOT_SYNC_MAX_ROWS = 120
local LOOT_SYNC_SEND_DELAY = 0.10
local LOOT_SYNC_REQUEST_THROTTLE = 5 * 60
local LOOT_SYNC_RESPONSE_THROTTLE = 3 * 60
local TEST_DUNGEON_INSTANCE_IDS = {
    [36] = "The Deadmines",
}
local TEST_DUNGEON_NAMES = {
    ["the deadmines"] = true,
    ["deadmines"] = true,
}
local IGNORED_LOOT_ITEM_IDS = {
    [30311] = "Warp Slicer",
    [30312] = "Infinity Blade",
    [30313] = "Staff of Disintegration",
    [30314] = "Phaseshift Bulwark",
    [30316] = "Devastation",
    [30317] = "Cosmic Infuser",
    [30318] = "Netherstrand Longbow",
    [30319] = "Nether Spike",
}
local TIER_TOKEN_ITEM_IDS = {
    [29753] = true, [29754] = true, [29755] = true, [29756] = true, [29757] = true,
    [29758] = true, [29759] = true, [29760] = true, [29761] = true, [29762] = true,
    [29763] = true, [29764] = true, [29765] = true, [29766] = true, [29767] = true,
    [30236] = true, [30237] = true, [30238] = true, [30239] = true, [30240] = true,
    [30241] = true, [30242] = true, [30243] = true, [30244] = true, [30245] = true,
    [30246] = true, [30247] = true, [30248] = true, [30249] = true, [30250] = true,
    [31089] = true, [31090] = true, [31091] = true, [31092] = true, [31093] = true,
    [31094] = true, [31095] = true, [31096] = true, [31097] = true, [31098] = true,
    [31099] = true, [31100] = true, [31101] = true, [31102] = true, [31103] = true,
    [34848] = true, [34851] = true, [34852] = true, [34853] = true, [34854] = true,
    [34855] = true, [34856] = true, [34857] = true, [34858] = true,
}

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function lower(s)
    return string.lower(tostring(s or ""))
end

local function playerService()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function resetMessageInfo(message)
    if not message then return nil, false end
    if INSTANCE_RESET_SUCCESS then
        local instance = string.match(message, string.gsub(INSTANCE_RESET_SUCCESS, "%%s", "(.+)"))
        if instance then return instance, true end
    end
    if INSTANCE_RESET_FAILED then
        local instance = string.match(message, string.gsub(INSTANCE_RESET_FAILED, "%%s", "(.+)"))
        if instance then return instance, true end
    end
    if INSTANCE_RESET_FAILED_ZONING then
        local instance = string.match(message, string.gsub(INSTANCE_RESET_FAILED_ZONING, "%%s", "(.+)"))
        if instance then return instance, false end
    end
    if INSTANCE_RESET_FAILED_OFFLINE then
        local instance = string.match(message, string.gsub(INSTANCE_RESET_FAILED_OFFLINE, "%%s", "(.+)"))
        if instance then return instance, false end
    end

    local text = lower(message)
    if text:find(" has been reset", 1, true) or text:find(" reset.", 1, true) then
        return message:gsub("%s+has been reset%.?$", ""), true
    end
    return nil, false
end

local function instanceZoneIdFromGuid(guid)
    if not guid or guid == "" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    local unitType, _, _, _, zoneID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" and unitType ~= "Cast" then return nil end
    zoneID = tonumber(zoneID)
    return zoneID and zoneID > 0 and zoneID or nil
end

local function currentRealm()
    local Players = playerService()
    if Players and Players.CurrentRealm then return Players:CurrentRealm() end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    return (realm or ""):gsub("%s+", "")
end

local function fullPlayerName(name, realm)
    local Players = playerService()
    if Players and Players.FullName then return Players:FullName(name, realm) end
    name = trim(name)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = trim(realm or currentRealm())
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function localPlayer()
    local Players = playerService()
    if Players and Players.LocalName then return Players:LocalName() end
    return fullPlayerName(UnitName("player"), currentRealm())
end

local function shortPlayerName(value)
    local Players = playerService()
    if Players and Players.ShortName then return Players:ShortName(value) end
    value = trim(value)
    return (strsplit("-", value))
end

local function samePlayer(a, b)
    local Players = playerService()
    if Players and Players.Same then return Players:Same(a, b) end
    a, b = trim(a), trim(b)
    if a == "" or b == "" then return false end
    if lower(a) == lower(b) then return true end
    return lower(shortPlayerName(a)) == lower(shortPlayerName(b))
end

local function splitPlayer(value)
    value = trim(value)
    local name, realm = strsplit("-", value)
    return {
        name = name or value,
        realm = realm or currentRealm(),
        realmSlug = realm or currentRealm(),
    }
end

local function utcNow()
    return date("!%Y-%m-%dT%H:%M:%SZ")
end

local function itemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function cleanItemLink(link)
    link = trim(link)
    return link:gsub("%.$", "")
end

local function itemDisplayName(request)
    if not request then return "Requested loot" end
    return request.itemName or (request.itemId and ("Item #" .. tostring(request.itemId))) or "Requested loot"
end

local function itemResponseEligible(request)
    local query = request and (request.itemLink or request.itemId)
    if not query then return false end

    if GetItemInfo and request and request.itemId then
        local name = GetItemInfo(request.itemId)
        if not name then
            if C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, request.itemId)
            end
            return true
        end
    end

    local usable
    if IsUsableItem then
        local ok, value = pcall(IsUsableItem, query)
        if ok then usable = value and true or false end
    end

    local equippable
    if IsEquippableItem then
        local ok, value = pcall(IsEquippableItem, query)
        if ok then equippable = value and true or false end
    end

    return usable or equippable or false
end

local function qualityName(q)
    q = tonumber(q)
    if q == 0 then return "poor" end
    if q == 1 then return "common" end
    if q == 2 then return "uncommon" end
    if q == 3 then return "rare" end
    if q == 4 then return "epic" end
    if q == 5 then return "legendary" end
    return q and tostring(q) or nil
end

local function itemInfo(linkOrId)
    if not GetItemInfo then
        return tonumber(linkOrId) and { quality = 2, equipLoc = "UNKNOWN" } or {}
    end
    local name, link, quality, itemLevel, reqLevel, className, subclassName, maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(linkOrId)
    return {
        name = name,
        link = link,
        quality = quality,
        className = className,
        subclassName = subclassName,
        equipLoc = equipLoc,
        icon = icon,
        classID = classID,
        subclassID = subclassID,
        bindType = bindType,
        isCraftingReagent = isCraftingReagent,
    }
end

local function isEquipmentItem(meta)
    if not meta then return false end
    return meta.equipLoc and meta.equipLoc ~= ""
end

local function isDisenchantOutput(meta)
    if not meta then return false end
    if meta.isCraftingReagent then return true end
    local className = lower(meta.className or "")
    local subclassName = lower(meta.subclassName or "")
    if meta.classID == 7 then return true end
    if className:find("trade", 1, true) or className:find("reagent", 1, true) then return true end
    if subclassName:find("enchant", 1, true) then return true end
    return false
end

local function isRecipeItem(meta)
    if not meta then return false end
    if meta.classID == 9 then return true end
    return lower(meta.className or "") == "recipe"
end

local function safeItemLocation(bag, slot)
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then return nil end
    local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if not ok then return nil end
    if C_Item and C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    return loc
end

local function itemGuidFromBagSlot(bag, slot)
    if not C_Item or not C_Item.GetItemGUID then return nil end
    local loc = safeItemLocation(bag, slot)
    if not loc then return nil end
    local ok, guid = pcall(C_Item.GetItemGUID, loc)
    return ok and guid or nil
end

local function safeEquipmentLocation(slot)
    if not ItemLocation or not ItemLocation.CreateFromEquipmentSlot then return nil end
    local ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
    if not ok then return nil end
    if C_Item and C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    return loc
end

local function itemGuidFromEquipmentSlot(slot)
    if not C_Item or not C_Item.GetItemGUID then return nil end
    local loc = safeEquipmentLocation(slot)
    if not loc then return nil end
    local ok, guid = pcall(C_Item.GetItemGUID, loc)
    return ok and guid or nil
end

local function containerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    local texture, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
    if not itemID then return nil end
    return { iconFileID = texture, stackCount = count, isLocked = locked, quality = quality, hyperlink = link, itemID = itemID }
end

local function bagSlotCount(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots(bag)
end

local function useBagItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then return C_Container.UseContainerItem(bag, slot) end
    return UseContainerItem(bag, slot)
end

local function cleanAddonField(value)
    value = tostring(value or "")
    value = value:gsub("[|\n\r]", " ")
    return trim(value)
end

local function canonicalSource(drop)
    if not drop then return "" end
    local source = ns.raidLootSources and ns.raidLootSources.byItemId and ns.raidLootSources.byItemId[tonumber(drop.itemId or 0)]
    return lower((source and source.instance) or drop.sourceInstance or drop.lootSourceInstance or "")
end

local function canonicalBoss(drop)
    if not drop then return "" end
    local source = ns.raidLootSources and ns.raidLootSources.byItemId and ns.raidLootSources.byItemId[tonumber(drop.itemId or 0)]
    return lower((source and source.source) or drop.bossName or drop.lootSource or "")
end

local function duplicateDropKey(drop)
    if not drop or not drop.itemId then return nil end
    return table.concat({
        tostring(drop.itemId or 0),
        canonicalSource(drop),
        canonicalBoss(drop),
    }, ":")
end

local function knownDifferentPhysicalItems(a, b)
    return a and b and a.itemGuid and b.itemGuid and a.itemGuid ~= b.itemGuid
end

local function sameKnownDropId(a, b)
    if not a or not b then return false end
    if a.dropInstanceId and b.dropInstanceId and a.dropInstanceId == b.dropInstanceId then return true end
    if a.lootId and b.lootId and a.lootId == b.lootId then return true end
    return false
end

local function effectiveOwner(drop)
    if not drop then return nil end
    return drop.finalOwner or drop.currentHolder or drop.firstHolder
end

local function confirmedOwner(drop)
    if not drop then return nil end
    if drop.finalOwner then return drop.finalOwner end
    if drop.status == "traded" or drop.status == "final_owner_confirmed" or drop.status == "obtained" then
        return drop.currentHolder
    end
    return nil
end

local function knownDifferentConfirmedOwners(a, b)
    local aOwner = confirmedOwner(a)
    local bOwner = confirmedOwner(b)
    return aOwner and bOwner and not samePlayer(aOwner, bOwner)
end

local function duplicateDropMatch(a, b)
    if not a or not b then return false end
    if duplicateDropKey(a) ~= duplicateDropKey(b) then return false end
    if knownDifferentPhysicalItems(a, b) then return false end
    if knownDifferentConfirmedOwners(a, b) then return false end
    if sameKnownDropId(a, b) then return true end
    if a.itemGuid and b.itemGuid and a.itemGuid == b.itemGuid then return true end
    return false
end

function Ledger:Store()
    local db = ns:GetModule("DB")
    db = db and db.db
    if not db then return nil end
    db.raidLootLedger = db.raidLootLedger or { drops = {}, eventLimit = 1200 }
    db.raidLootLedger.drops = db.raidLootLedger.drops or {}
    db.raidLootLedger.sessionCounter = db.raidLootLedger.sessionCounter or 0
    return db.raidLootLedger
end

function Ledger:Settings()
    local db = ns:GetModule("DB")
    local settings = db and db.db and db.db.settings
    return (settings and settings.raidLootLedger) or {}
end

function Ledger:Drops()
    local store = self:Store()
    return store and store.drops or {}
end

function Ledger:Requests()
    local store = self:Store()
    if not store then return {} end
    store.requests = store.requests or {}
    return store.requests
end

function Ledger:PruneDisenchantOutputDrops()
    local drops = self:Drops()
    local removed = 0
    for i = #drops, 1, -1 do
        local drop = drops[i]
        if drop and drop.itemId
            and not (ns.RAID_LOOT_WHITELIST and ns.RAID_LOOT_WHITELIST[drop.itemId])
            and isDisenchantOutput(itemInfo(drop.itemLink or drop.itemId)) then
            table.remove(drops, i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns:Debug("LootLedger pruned disenchant output rows", removed)
        self:NotifyChanged()
    end
end

function Ledger:IsIgnoredLootItem(itemId)
    return IGNORED_LOOT_ITEM_IDS[tonumber(itemId or 0)] ~= nil
end

function Ledger:IsKnownRaidLootItem(itemId)
    itemId = tonumber(itemId or 0)
    if not itemId or itemId <= 0 then return false end
    if self:IsIgnoredLootItem(itemId) then return false end
    if ns.RAID_LOOT_WHITELIST and ns.RAID_LOOT_WHITELIST[itemId] then return true end
    return ns.raidLootSources
        and ns.raidLootSources.byItemId
        and ns.raidLootSources.byItemId[itemId] ~= nil
end

function Ledger:IsTestDungeonContext(ctxOrDrop)
    if not ctxOrDrop then return false end
    if ctxOrDrop.instanceType ~= "party" then return false end
    local instanceId = tonumber(ctxOrDrop.instanceId or 0)
    if TEST_DUNGEON_INSTANCE_IDS[instanceId] then return true end
    local name = lower(ctxOrDrop.raidName or ctxOrDrop.sourceInstance or ctxOrDrop.lootSourceInstance or "")
    return TEST_DUNGEON_NAMES[name] == true
end

function Ledger:IsAllowedTestDungeonLoot(itemId, quality, meta, ctxOrDrop)
    itemId = tonumber(itemId or 0)
    if not itemId or itemId <= 0 then return false end
    if self:IsIgnoredLootItem(itemId) then return false end
    if not self:IsTestDungeonContext(ctxOrDrop) then return false end
    if meta and isDisenchantOutput(meta) then return false end
    -- Deadmines is intentionally opened up as a loot-ledger test dungeon. Track all
    -- actual drops here, including common/uncommon trash, while still excluding
    -- disenchant output and ignored encounter helper items.
    return true
end

function Ledger:IsTrackedLootItem(itemId, quality, meta, ctxOrDrop)
    return self:IsKnownRaidLootItem(itemId) or self:IsAllowedTestDungeonLoot(itemId, quality, meta, ctxOrDrop)
end

function Ledger:IsTierTokenItem(itemId)
    return TIER_TOKEN_ITEM_IDS[tonumber(itemId or 0)] == true
end

function Ledger:WasRemovedByMissingBagAudit(drop)
    for i = #(drop and drop.events or {}), 1, -1 do
        local ev = drop.events[i]
        if ev and ev.type == "removed_unknown" then
            return ev.reason == "bag_guid_missing"
        end
    end
    return false
end

function Ledger:PruneIgnoredLootDrops()
    local drops = self:Drops()
    local removed = 0
    for i = #drops, 1, -1 do
        local drop = drops[i]
        if drop and self:IsIgnoredLootItem(drop.itemId) then
            table.remove(drops, i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns:Debug("LootLedger pruned ignored encounter items", removed)
        self:NotifyChanged()
    end
end

function Ledger:PruneDungeonLootDrops()
    local drops = self:Drops()
    local removed = 0
    for i = #drops, 1, -1 do
        local drop = drops[i]
        if drop and not self:IsTrackedLootItem(drop.itemId, drop.itemQuality, nil, drop) then
            table.remove(drops, i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns:Debug("LootLedger pruned dungeon loot rows", removed)
        self:NotifyChanged()
    end
end

function Ledger:RepairTierTokenTurnIns()
    local repaired = 0
    for _, drop in ipairs(self:Drops()) do
        if drop
            and drop.status == "removed_unknown"
            and self:IsTierTokenItem(drop.itemId)
            and self:WasRemovedByMissingBagAudit(drop) then
            drop.status = "obtained"
            drop.finalOwner = drop.currentHolder or drop.finalOwner or drop.firstHolder
            self:AppendEvent(drop, "obtained", { by = localPlayer(), owner = drop.finalOwner, reason = "repair_removed_tier_token" })
            repaired = repaired + 1
        end
    end
    if repaired > 0 then
        ns:Debug("LootLedger repaired tier token turn-ins", repaired)
        self:NotifyChanged()
    end
end

local function statusRank(status)
    if status == "disenchanted" or status == "removed_unknown" or status == "guild_bank" then return 5 end
    if status == "traded" then return 4 end
    if status == "final_owner_confirmed" or status == "obtained" then return 3 end
    if status == "assigned" then return 2 end
    return 1
end

function Ledger:MergeDropData(target, source)
    if not target or not source then return end
    target.itemGuid = target.itemGuid or source.itemGuid
    target.itemName = target.itemName or source.itemName
    target.itemLink = target.itemLink or source.itemLink
    target.itemQuality = target.itemQuality or source.itemQuality
    target.itemIcon = target.itemIcon or source.itemIcon
    target.sourceInstance = target.sourceInstance or source.sourceInstance
    target.instanceType = target.instanceType or source.instanceType
    target.instanceId = target.instanceId or source.instanceId
    target.difficultyId = target.difficultyId or source.difficultyId
    target.sessionKey = target.sessionKey or source.sessionKey
    target.sessionStartedAt = target.sessionStartedAt or source.sessionStartedAt
    target.sessionReason = target.sessionReason or source.sessionReason
    target.sessionZoneID = target.sessionZoneID or source.sessionZoneID
    target.entrySerial = target.entrySerial or source.entrySerial
    target.bossName = target.bossName or source.bossName
    target.bossAttributionAt = target.bossAttributionAt or source.bossAttributionAt
    target.bossSourceType = target.bossSourceType or source.bossSourceType
    target.lootSource = target.lootSource or source.lootSource
    target.lootSourceInstance = target.lootSourceInstance or source.lootSourceInstance

    if statusRank(source.status) > statusRank(target.status)
        or ((source.updatedAt or 0) > (target.updatedAt or 0)
            and not (target.status == "traded" and (source.status == "obtained" or source.status == "final_owner_confirmed"))) then
        target.status = source.status or target.status
        target.currentHolder = source.currentHolder or target.currentHolder
        target.finalOwner = source.finalOwner or target.finalOwner
        target.tradedAt = source.tradedAt or target.tradedAt
        target.finalizedAt = source.finalizedAt or target.finalizedAt
        target.finalizedBy = source.finalizedBy or target.finalizedBy
        target.disenchantedAt = source.disenchantedAt or target.disenchantedAt
        target.disenchantedBy = source.disenchantedBy or target.disenchantedBy
        target.depositedAt = source.depositedAt or target.depositedAt
        target.depositedBy = source.depositedBy or target.depositedBy
        target.removedAt = source.removedAt or target.removedAt
        target.removedBy = source.removedBy or target.removedBy
    end

    target.events = target.events or {}
    for _, event in ipairs(source.events or {}) do
        table.insert(target.events, event)
        while #target.events > MAX_EVENTS_PER_DROP do table.remove(target.events, 1) end
    end
    target.updatedAt = math.max(target.updatedAt or 0, source.updatedAt or 0, time())
end

function Ledger:FindDuplicateDrop(targetIndex)
    local drops = self:Drops()
    local drop = drops[targetIndex]
    if not drop or not drop.itemId then return nil end
    for i = 1, targetIndex - 1 do
        local candidate = drops[i]
        if duplicateDropMatch(candidate, drop) then
            return i, candidate
        end
    end
    return nil
end

function Ledger:MergeDuplicateDrops()
    local drops = self:Drops()
    local n = #drops
    if n < 2 then return 0 end
    -- Bucket indices by duplicateDropKey so we only compare drops that could match,
    -- instead of every pair (was O(n^2)). Within a bucket we still run the precise
    -- duplicateDropMatch to preserve exact semantics.
    local buckets = {}
    for i = 1, n do
        local d = drops[i]
        if d then
            local k = duplicateDropKey(d)
            local b = buckets[k]
            if not b then b = {}; buckets[k] = b end
            b[#b + 1] = i
        end
    end
    -- Decide removals: for each drop (scanning ascending within its bucket), find the
    -- earliest earlier drop in the same bucket it duplicates; merge into that target.
    -- A drop already marked removed cannot be a merge target.
    local removeFlag = {}
    local mergeInto = {}   -- laterIndex -> targetIndex
    for _, idxs in pairs(buckets) do
        -- idxs is ascending (built in 1..n order)
        for a = 1, #idxs do
            local laterIdx = idxs[a]
            if not removeFlag[laterIdx] then
                for b = 1, a - 1 do
                    local earlierIdx = idxs[b]
                    if not removeFlag[earlierIdx]
                        and duplicateDropMatch(drops[earlierIdx], drops[laterIdx]) then
                        mergeInto[laterIdx] = earlierIdx
                        removeFlag[laterIdx] = true
                        break
                    end
                end
            end
        end
    end
    -- Apply merges into targets, then remove flagged rows high->low so indices stay valid.
    local removed = 0
    for laterIdx = n, 1, -1 do
        local target = mergeInto[laterIdx]
        if target then
            self:MergeDropData(drops[target], drops[laterIdx])
            table.remove(drops, laterIdx)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns:Debug("LootLedger merged duplicate drop rows", removed)
        self:NotifyChanged()
    end
    return removed
end

function Ledger:OfficerRankLimit()
    local db = ns:GetModule("DB")
    local settings = db and db.db and db.db.settings and db.db.settings.permissionSettings
    return (settings and settings.canBroadcastMaxRank) or 2
end

function Ledger:GuildRankIndexForName(name)
    local target = lower(shortPlayerName(name or ""))
    if target == "" then return nil end
    if GetGuildInfo then
        local _, _, rankIndex = GetGuildInfo("player")
        if target == lower(UnitName("player") or "") then return rankIndex end
    end
    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, count do
        local guildName, _, rankIndex = GetGuildRosterInfo(i)
        if guildName and lower(shortPlayerName(guildName)) == target then return rankIndex end
    end
    return nil
end

function Ledger:IsRaidLeaderName(name)
    local target = lower(shortPlayerName(name or ""))
    if target == "" then return false end
    if target == lower(UnitName("player") or "") then return UnitIsGroupLeader and UnitIsGroupLeader("player") end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local raidName, rank = GetRaidRosterInfo and GetRaidRosterInfo(i)
        if raidName and lower(shortPlayerName(raidName)) == target then return rank == 2 end
    end
    return false
end

function Ledger:IsOfficerName(name)
    local rankIndex = self:GuildRankIndexForName(name)
    return rankIndex ~= nil and rankIndex <= self:OfficerRankLimit()
end

function Ledger:CanManageLoot()
    return self:IsRaidLeaderName(UnitName("player")) or self:IsOfficerName(UnitName("player"))
end

function Ledger:PrintThrottled(key, message, tone, seconds)
    local at = time()
    self.printThrottle = self.printThrottle or {}
    key = tostring(key or message or "message")
    seconds = seconds or 10
    if self.printThrottle[key] and at - self.printThrottle[key] < seconds then return end
    self.printThrottle[key] = at
    ns:Print(message, tone)
end

function Ledger:IsTrustedLootManagerName(name)
    return self:IsRaidLeaderName(name) or self:IsOfficerName(name)
end

function Ledger:CanAnswerOfficerLootSyncRequest(sender)
    return self:IsTrustedLootManagerName(sender)
end

function Ledger:IsLocalPlayerInDrop(drop)
    local me = localPlayer()
    return samePlayer(drop and drop.firstHolder, me)
        or samePlayer(drop and drop.currentHolder, me)
        or samePlayer(drop and drop.finalOwner, me)
        or samePlayer(drop and drop.finalizedBy, me)
        or samePlayer(drop and drop.disenchantedBy, me)
        or samePlayer(drop and drop.depositedBy, me)
end

function Ledger:DropSyncStamp(drop)
    if not drop then return 0 end
    return math.max(
        drop.updatedAt or 0,
        drop.finalizedAt or 0,
        drop.disenchantedAt or 0,
        drop.depositedAt or 0,
        drop.removedAt or 0,
        drop.droppedAt or 0)
end

function Ledger:AppendEvent(drop, eventType, fields)
    if not drop then return end
    drop.events = drop.events or {}
    local ev = fields or {}
    ev.type = eventType
    ev.at = ev.at or time()
    ev.actor = ev.actor or localPlayer()
    table.insert(drop.events, ev)
    while #drop.events > MAX_EVENTS_PER_DROP do table.remove(drop.events, 1) end
    drop.updatedAt = time()
end

function Ledger:NotifyChanged()
    local panel = self.panel
    if panel and panel.Refresh then panel:Refresh() end
end

function Ledger:InstanceContext()
    local instanceName, instanceType, difficultyId, _, _, _, _, instanceId = GetInstanceInfo()
    if instanceType ~= "raid" and instanceType ~= "party" then return nil end
    return {
        raidName = instanceName,
        instanceType = instanceType,
        instanceId = instanceId,
        difficultyId = difficultyId,
    }
end

function Ledger:SessionSignature(ctx)
    if not ctx then return nil end
    return ("%s:%s:%s"):format(ctx.raidName or "unknown", ctx.instanceId or 0, ctx.difficultyId or 0)
end

function Ledger:ShouldAutoSplitSession(ctx)
    return ctx and ctx.instanceType == "party"
end

function Ledger:BossAttributionName(at)
    if not self.lastBossName or self.lastBossName == "" then return nil end
    if self.lastBossAt and math.abs((at or time()) - self.lastBossAt) <= BOSS_LOOT_ATTRIBUTION_SECONDS then
        return self.lastBossName
    end
    return nil
end

function Ledger:RaidLootSource(itemId, instanceName)
    local byItemId = ns.raidLootSources and ns.raidLootSources.byItemId
    local source = byItemId and byItemId[tonumber(itemId or 0)]
    if not source then return nil end
    return source.source, source.instance
end

function Ledger:NormalizeKnownRaidSources()
    local changed = 0
    for _, drop in ipairs(self:Drops()) do
        local source, sourceInstance = self:RaidLootSource(drop and drop.itemId, drop and drop.sourceInstance)
        if source and source ~= "" then
            if drop.bossName ~= source
                or drop.lootSource ~= source
                or drop.lootSourceInstance ~= sourceInstance
                or drop.bossSourceType ~= "loot_table" then
                drop.bossName = source
                drop.lootSource = source
                drop.lootSourceInstance = sourceInstance
                drop.bossSourceType = "loot_table"
                drop.bossAttributionAt = drop.bossAttributionAt or drop.droppedAt
                self:AppendEvent(drop, "loot_source_normalized", {
                    source = source,
                    sourceInstance = sourceInstance,
                    reason = "raid_loot_table",
                })
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        ns:Debug("LootLedger normalized raid loot sources", changed)
        self:NotifyChanged()
    end
end

function Ledger:CreateSession(ctx, reason)
    local store = self:Store()
    if not store or not ctx then return nil end
    local now = time()
    store.sessionCounter = (store.sessionCounter or 0) + 1
    store.activeSession = {
        id = ("%d-%d-%d-%d"):format(ctx.instanceId or 0, ctx.difficultyId or 0, now, store.sessionCounter),
        signature = self:SessionSignature(ctx),
        sourceInstance = ctx.raidName,
        instanceType = ctx.instanceType,
        instanceId = ctx.instanceId,
        difficultyId = ctx.difficultyId,
        zoneID = ctx.zoneID,
        entrySerial = ctx.entrySerial or self.instanceEntrySerial,
        startedAt = now,
        updatedAt = now,
        reason = reason,
        bossKills = {},
    }
    self.sessionInstanceId = ctx.instanceId
    self.sessionDifficultyId = ctx.difficultyId
    self.sessionKey = store.activeSession.id
    ns:Debug("LootLedger session", store.activeSession.id, reason or "unknown", ctx.raidName or "?")
    self:NotifyChanged()
    return store.activeSession
end

function Ledger:ActiveSession(ctx)
    local store = self:Store()
    if not store or not ctx then return nil end
    local active = store.activeSession
    local signature = self:SessionSignature(ctx)
    local now = time()
    if active
        and active.id
        and active.signature == signature
        and math.abs(now - (active.updatedAt or active.startedAt or now)) <= SESSION_REUSE_SECONDS then
        self.sessionInstanceId = ctx.instanceId
        self.sessionDifficultyId = ctx.difficultyId
        self.sessionKey = active.id
        return active
    end
    return self:CreateSession(ctx, active and "instance_changed" or "first_seen")
end

function Ledger:SessionKey()
    local ctx = self:InstanceContext()
    local session = self:ActiveSession(ctx)
    return session and session.id or nil
end

function Ledger:CurrentRaidContext()
    local ctx = self:InstanceContext()
    if not ctx then return nil end
    local session = self:ActiveSession(ctx)
    return {
        raidName = ctx.raidName,
        instanceType = ctx.instanceType,
        instanceId = ctx.instanceId,
        difficultyId = ctx.difficultyId,
        zoneID = session and session.zoneID or nil,
        entrySerial = self.instanceEntrySerial,
        sessionKey = session and session.id or nil,
        sessionStartedAt = session and session.startedAt or nil,
        sessionReason = session and session.reason or nil,
    }
end

function Ledger:CurrentRaidContextSnapshot()
    local ctx = self:InstanceContext()
    if not ctx then return nil end
    local store = self:Store()
    local active = store and store.activeSession
    local signature = self:SessionSignature(ctx)
    local session = active and active.signature == signature and active or nil
    return {
        raidName = ctx.raidName,
        instanceType = ctx.instanceType,
        instanceId = ctx.instanceId,
        difficultyId = ctx.difficultyId,
        zoneID = session and session.zoneID or nil,
        entrySerial = self.instanceEntrySerial,
        sessionKey = session and session.id or self.sessionKey,
        sessionStartedAt = session and session.startedAt or nil,
        sessionReason = session and session.reason or nil,
    }
end

function Ledger:EnsureSessionForLoot(ctx, itemId, bossName, at)
    if not ctx then return nil end
    local baseCtx = {
        raidName = ctx.raidName,
        instanceType = ctx.instanceType,
        instanceId = ctx.instanceId,
        difficultyId = ctx.difficultyId,
        zoneID = ctx.zoneID,
        entrySerial = ctx.entrySerial or self.instanceEntrySerial,
    }
    local session = self:ActiveSession(baseCtx)
    if not session then return nil end
    if self.forceNewSessionOnNextLoot and self:ShouldAutoSplitSession(baseCtx) then
        session = self:CreateSession(baseCtx, self.forceNewSessionReason or "reset_detected")
        self.forceNewSessionOnNextLoot = false
        self.forceNewSessionReason = nil
        self.pendingResetInstanceName = nil
        ns:Print("New loot session started: instance reset detected.", "success")
        return session
    elseif self.forceNewSessionOnNextLoot and not self:ShouldAutoSplitSession(baseCtx) then
        self.forceNewSessionOnNextLoot = false
        self.forceNewSessionReason = nil
        self.pendingResetInstanceName = nil
    end

    if self:ShouldAutoSplitSession(baseCtx) then
        local bossKey = lower(bossName or "")
        local repeatItemMeta = bossKey == "" and itemInfo(itemId) or nil
        local canSplitRepeatedUnknownItem = repeatItemMeta
            and isEquipmentItem(repeatItemMeta)
            and tonumber(repeatItemMeta.quality or 0) >= 2
        for _, drop in ipairs(self:Drops()) do
            local sameBoss = bossKey ~= "" and lower(drop.bossName or "") == bossKey
            local repeatedUnknownItem = canSplitRepeatedUnknownItem and lower(drop.bossName or "") == "" and drop.itemId == itemId
            local differentEntry = baseCtx.entrySerial
                and ((drop.entrySerial and drop.entrySerial ~= baseCtx.entrySerial)
                    or (not drop.entrySerial and session.entrySerial and session.entrySerial ~= baseCtx.entrySerial))
            if drop.sessionKey == session.id
                and (sameBoss or repeatedUnknownItem)
                and (differentEntry or math.abs((at or time()) - (drop.droppedAt or 0)) > REPEAT_DROP_SPLIT_SECONDS) then
                session = self:CreateSession(baseCtx, differentEntry and "instance_reentry_repeat" or (bossKey ~= "" and "repeat_boss" or "repeat_item"))
                local label = bossKey ~= "" and bossName or ("item #" .. tostring(itemId))
                ns:Print(("New loot session started: repeated %s loot detected."):format(label), "success")
                ns:Debug("LootLedger repeat drop split", itemId, bossName or "", "entry", tostring(drop.entrySerial), tostring(baseCtx.entrySerial))
                break
            end
        end
    end

    return session
end

function Ledger:StartManualSession()
    if not self:CanManageLoot() then
        ns:Print("Only the raid leader or guild officers can start loot sessions.", "warning")
        return nil
    end
    local ctx = self:InstanceContext()
    if not ctx then
        ns:Print("Enter a dungeon or raid before starting a loot session.", "warning")
        return nil
    end
    local session = self:CreateSession(ctx, "manual")
    if session then ns:Print("New loot session started.", "success") end
    return session
end

function Ledger:NoteBossKill(name)
    name = trim(name)
    if name == "" then return end
    self.lastBossName = name
    self.lastBossAt = time()
    ns:Debug("LootLedger boss kill", name)
    local now = time()
    local bossKey = lower(name)
    if self.lastBossEventKey == bossKey and math.abs(now - (self.lastBossEventAt or 0)) <= 10 then
        return
    end
    self.lastBossEventKey = bossKey
    self.lastBossEventAt = now

    local ctx = self:InstanceContext()
    if not ctx then return end
    local session = self:ActiveSession(ctx)
    if not session then return end
    session.bossKills = session.bossKills or {}
    if session.bossKills[bossKey] and self:ShouldAutoSplitSession(ctx) then
        session = self:CreateSession(ctx, "repeat_boss")
        if not session then return end
        session.bossKills = session.bossKills or {}
        ns:Print(("New loot session started: %s was killed again."):format(name), "success")
    end
    session.bossKills[bossKey] = now
    session.updatedAt = now
    self:NotifyChanged()
end

function Ledger:OnWorldChanged(isInitialLogin, isReloadingUi)
    local ctx = self:InstanceContext()
    if not ctx then
        self.wasInManagedInstance = false
        self.awaitingInstanceProof = false
        self.leftManagedInstanceAt = time()
        return
    end

    local signature = self:SessionSignature(ctx)
    if isInitialLogin or isReloadingUi then
        self.wasInManagedInstance = true
        self.lastInstanceSignature = signature
        self:ActiveSession(ctx)
        self.awaitingInstanceProof = false
        return
    end

    if self.wasInManagedInstance == false then
        self.instanceEntrySerial = (self.instanceEntrySerial or 0) + 1
        ctx.entrySerial = self.instanceEntrySerial
        ns:Debug("LootLedger entered instance", ctx.raidName or "?", "entry", self.instanceEntrySerial)
        self:ActiveSession(ctx)
        self.awaitingInstanceProof = true
    else
        ctx.entrySerial = self.instanceEntrySerial
        self:ActiveSession(ctx)
    end
    self.wasInManagedInstance = true
    self.lastInstanceSignature = signature
end

function Ledger:OnSystemMessage(message)
    if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
        self:CompleteTradeFromSystemMessage()
        return
    end

    local instanceName, success = resetMessageInfo(message)
    if success then
        local ctx = self:InstanceContext()
        if ctx and ctx.instanceType == "raid" then return end
        self.forceNewSessionOnNextLoot = true
        self.forceNewSessionReason = "system_reset_message"
        self.pendingResetInstanceName = instanceName
        ns:Debug("LootLedger reset system message", instanceName or "?", message or "")
    end
end

function Ledger:CompleteTradeFromSystemMessage()
    self.tradeComplete = true
    ns:Debug("LootLedger trade complete message", self.tradeTarget or (self.lastClosedTrade and self.lastClosedTrade.target) or "unknown")
    if self.tradeTarget then
        self:SnapshotTrade()
        self:CommitTrade()
        return
    end

    local closed = self.lastClosedTrade
    if not closed or not closed.target or math.abs(time() - (closed.closedAt or 0)) > 5 then
        ns:Debug("LootLedger late trade complete ignored: no recent closed trade")
        self.tradeComplete = false
        return
    end

    local previousTarget = self.tradeTarget
    local previousSnapshot = self.tradeSnapshot
    local previousCommitted = self.tradeCommitted
    self.tradeTarget = closed.target
    self.tradeSnapshot = closed.frameSnapshot
    self.tradeCommitted = false
    ns:Debug("LootLedger replaying cached closed trade", closed.target)
    if closed.frameSnapshot then
        self:CommitTrade()
    else
        ns:Debug("LootLedger cached trade has no frame snapshot; using bag diff")
    end
    if closed.bagSnapshot and C_Timer then
        C_Timer.After(0.10, function() self:CommitTradeBagDiff(closed.target, closed.bagSnapshot, closed.openedAt or closed.closedAt) end)
        C_Timer.After(0.80, function() self:CommitTradeBagDiff(closed.target, closed.bagSnapshot, closed.openedAt or closed.closedAt) end)
    elseif closed.bagSnapshot then
        self:CommitTradeBagDiff(closed.target, closed.bagSnapshot, closed.openedAt or closed.closedAt)
    end
    self.tradeTarget = previousTarget
    self.tradeSnapshot = previousSnapshot
    self.tradeCommitted = previousCommitted
    self.tradeComplete = false
    self.lastClosedTrade = nil
end

function Ledger:CaptureInstanceGuid(guid, source)
    local zoneID = instanceZoneIdFromGuid(guid)
    if not zoneID then return end
    local ctx = self:InstanceContext()
    if not ctx then return end

    local session = self:ActiveSession(ctx)
    if not session then return end

    if session.zoneID and session.zoneID ~= zoneID and (self.awaitingInstanceProof or self.forceNewSessionOnNextLoot) and self:ShouldAutoSplitSession(ctx) then
        ctx.zoneID = zoneID
        session = self:CreateSession(ctx, self.forceNewSessionReason or "instance_zone_changed")
        self.forceNewSessionOnNextLoot = false
        self.forceNewSessionReason = nil
        self.pendingResetInstanceName = nil
        ns:Print("New loot session started: fresh instance detected.", "success")
    end

    if not session.zoneID then
        session.zoneID = zoneID
        session.zoneSource = source
        session.entrySerial = self.instanceEntrySerial
        session.updatedAt = time()
        ns:Debug("LootLedger instance zoneID", zoneID, source or "?")
        self:NotifyChanged()
    end
    self.awaitingInstanceProof = false
end

function Ledger:OnCombatLogEvent()
    if not self.awaitingInstanceProof and not self.forceNewSessionOnNextLoot then
        local store = self:Store()
        local active = store and store.activeSession
        if active and active.zoneID then return end
    end

    local _, subEvent, _, sourceGUID, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent == "SWING_DAMAGE"
        or subEvent == "SPELL_DAMAGE"
        or subEvent == "RANGE_DAMAGE"
        or subEvent == "SPELL_CAST_SUCCESS"
        or subEvent == "UNIT_DIED" then
        self:CaptureInstanceGuid(sourceGUID, "combat_source")
        self:CaptureInstanceGuid(destGUID, "combat_dest")
    end
end

function Ledger:ParseLootMessage(message)
    if not message or message:find("|HlootHistory") then return nil, nil end
    local itemLink = message:match("^You receive loot: (.+)$")
    if itemLink then return localPlayer(), cleanItemLink(itemLink) end

    local playerName
    playerName, itemLink = message:match("^(.+) receives? loot: (.+)$")
    if playerName and itemLink then return fullPlayerName(strsplit("-", playerName)), cleanItemLink(itemLink) end

    itemLink = message:match("^You won: (.+)$")
    if itemLink then return localPlayer(), cleanItemLink(itemLink) end

    playerName, itemLink = message:match("^(.+) won: (.+)$")
    if playerName and itemLink then return fullPlayerName(strsplit("-", playerName)), cleanItemLink(itemLink) end
    return nil, nil
end

function Ledger:IsRaidItem(itemId, quality, meta)
    if not itemId then return false end
    local ctx = self:InstanceContext()
    if not ctx then return false end
    if ctx.instanceType == "raid" then return self:IsKnownRaidLootItem(itemId) end
    return self:IsAllowedTestDungeonLoot(itemId, quality, meta, ctx)
end

function Ledger:IsTrackedRaidDrop(drop)
    if not drop or not drop.itemId then return false end
    return self:IsTrackedLootItem(drop.itemId, drop.itemQuality, nil, drop)
end

function Ledger:DropId(itemId, holder, at)
    return ("%s:%d:%s:%d"):format(self:SessionKey() or "world", itemId or 0, lower(holder or "unknown"), at or time())
end

function Ledger:NextDropId(itemId, holder, at)
    local store = self:Store()
    if store then
        store.dropCounter = (store.dropCounter or 0) + 1
        return ("%s:%d:%s:%d:%d"):format(self:SessionKey() or "world", itemId or 0, lower(holder or "unknown"), at or time(), store.dropCounter)
    end
    return self:DropId(itemId, holder, at)
end

function Ledger:FindDropBySignature(itemId, holder, timestamp)
    for _, drop in ipairs(self:Drops()) do
        if drop.itemId == itemId
            and samePlayer(drop.firstHolder, holder)
            and math.abs((drop.droppedAt or 0) - (timestamp or time())) <= 3 then
            return drop
        end
    end
    return nil
end

function Ledger:CanBroadcastObservedDrop(holder)
    return samePlayer(holder, localPlayer()) or self:CanManageLoot()
end

function Ledger:MostRecentOpenLocalDrop(maxAge)
    local me = localPlayer()
    local now = time()
    local best
    for _, drop in ipairs(self:Drops()) do
        local status = drop.status or "pending"
        if samePlayer(drop.currentHolder, me)
            and status ~= "disenchanted"
            and status ~= "removed_unknown"
            and status ~= "guild_bank"
            and status ~= "final_owner_confirmed"
            and status ~= "obtained"
            and math.abs(now - (drop.droppedAt or now)) <= (maxAge or 120)
            and (not best or (drop.droppedAt or 0) > (best.droppedAt or 0)) then
            best = drop
        end
    end
    return best
end

function Ledger:TrackResolvedLoot(holder, itemLink, itemId, itemName, itemQuality, itemIcon, meta)
    meta = meta or itemInfo(itemLink or itemId)
    local recentDisenchant = self.lastDisenchantAt and math.abs(time() - self.lastDisenchantAt) <= 12
    if recentDisenchant and isDisenchantOutput(meta) and samePlayer(holder, localPlayer()) then
        local drop = self:MostRecentOpenLocalDrop(180)
        if drop then
            self:MarkDisenchanted(drop, localPlayer(), "disenchant_material_looted", true)
            ns:Debug("LootLedger ignored disenchant output", itemName or itemId)
        end
        return
    end

    if not self:IsRaidItem(itemId, itemQuality, meta) then return end

    local at = time()
    local ctx = self:CurrentRaidContext()
    if not ctx then return end
    local lootSource, lootSourceInstance = self:RaidLootSource(itemId, ctx.raidName)
    local bossName = lootSource or self:BossAttributionName(at)
    local session = self:EnsureSessionForLoot(ctx, itemId, bossName, at)
    if session then
        ctx.sessionKey = session.id
        ctx.sessionStartedAt = session.startedAt
        ctx.sessionReason = session.reason
        ctx.zoneID = session.zoneID
        ctx.entrySerial = session.entrySerial or ctx.entrySerial
    end
    local bossAttributionAt = lootSource and at or (bossName and self.lastBossAt or nil)
    local bossSourceType = lootSource and "loot_table" or (bossName and "boss_event" or nil)
    local dropId = self:NextDropId(itemId, holder, at)

    local drop = {
        dropInstanceId = dropId,
        lootId = dropId,
        itemGuid = nil,
        itemId = itemId,
        itemName = itemName,
        itemLink = itemLink,
        itemQuality = itemQuality,
        itemIcon = itemIcon,
        firstHolder = holder,
        currentHolder = holder,
        assignedTo = nil,
        finalOwner = nil,
        status = "pending",
        bossName = bossName,
        bossAttributionAt = bossAttributionAt,
        bossSourceType = bossSourceType,
        lootSource = lootSource,
        lootSourceInstance = lootSourceInstance,
        sourceInstance = ctx.raidName,
        instanceType = ctx.instanceType,
        instanceId = ctx.instanceId,
        difficultyId = ctx.difficultyId,
        sessionKey = ctx.sessionKey,
        sessionStartedAt = ctx.sessionStartedAt,
        sessionReason = ctx.sessionReason,
        sessionZoneID = ctx.zoneID,
        entrySerial = ctx.entrySerial,
        droppedAt = at,
        updatedAt = at,
        events = {},
    }
    self:AppendEvent(drop, "chat_loot_received", { holder = holder, itemId = itemId })
    if session then session.updatedAt = at end
    table.insert(self:Drops(), 1, drop)
    while #self:Drops() > MAX_DROPS do table.remove(self:Drops()) end

    if samePlayer(holder, localPlayer()) then
        self:ScheduleGuidAttach(itemId)
        self:ScheduleBagAudit()
        self:ScheduleShortFinalizationAudit()
        self:ScheduleTradeWindowAudit()
    end

    if self:CanBroadcastObservedDrop(holder) then
        self:BroadcastDrop(drop)
    end
    self:NotifyChanged()
end

function Ledger:TrackLootMessage(message)
    local holder, itemLink = self:ParseLootMessage(message)
    if not holder or not itemLink then return end
    local itemId = itemIdFromLink(itemLink)
    if not itemId then return end

    local meta = itemInfo(itemLink)
    local itemName, itemQuality, itemIcon = meta.name, meta.quality, meta.icon
    itemName = itemName or itemLink:gsub("|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[", ""):gsub("%]|h|r", "")
    if not itemQuality and C_Timer then
        C_Timer.After(0.5, function()
            local resolvedMeta = itemInfo(itemLink)
            self:TrackResolvedLoot(holder, itemLink, itemId, resolvedMeta.name or itemName, resolvedMeta.quality, resolvedMeta.icon or itemIcon, resolvedMeta)
        end)
        return
    end

    self:TrackResolvedLoot(holder, itemLink, itemId, itemName, itemQuality, itemIcon, meta)
end

function Ledger:ScheduleGuidAttach(itemId)
    C_Timer.After(0.25, function() self:AttachLocalBagGuid(itemId) end)
    C_Timer.After(1.25, function() self:AttachLocalBagGuid(itemId) end)
end

function Ledger:FindBagGuidsForItem(itemId)
    local found = {}
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local info = containerInfo(bag, slot)
            if info and info.itemID == itemId then
                local guid = itemGuidFromBagSlot(bag, slot)
                table.insert(found, {
                    bag = bag,
                    slot = slot,
                    itemGuid = guid,
                    itemId = itemId,
                    itemLink = info.hyperlink,
                    itemIcon = info.iconFileID,
                })
            end
        end
    end
    return found
end

function Ledger:TradeEligibilityContext()
    local ctx = self:CurrentRaidContextSnapshot()
    if ctx then return ctx end
    local store = self:Store()
    local active = store and store.activeSession
    if not active then return nil end
    return {
        raidName = active.sourceInstance,
        sourceInstance = active.sourceInstance,
        lootSourceInstance = active.sourceInstance,
        instanceType = active.instanceType,
        instanceId = active.instanceId,
        difficultyId = active.difficultyId,
        sessionKey = active.id,
        sessionStartedAt = active.startedAt,
        sessionReason = active.reason,
        zoneID = active.zoneID,
        entrySerial = active.entrySerial,
    }
end

function Ledger:TrackedBagSnapshot()
    local snapshot = { byGuid = {}, noGuidCounts = {}, noGuidRows = {} }
    local ctx = self:TradeEligibilityContext()
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local info = containerInfo(bag, slot)
            local itemId = info and info.itemID
            if itemId and not self:IsIgnoredLootItem(itemId) then
                local link = info.hyperlink or (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or GetContainerItemLink(bag, slot)
                local guid = itemGuidFromBagSlot(bag, slot)
                local drop = self:FindDropForBagItem(itemId, guid)
                local meta = itemInfo(link or itemId)
                local quality = info.quality or meta.quality
                if drop or self:IsTrackedLootItem(itemId, quality, meta, ctx) then
                    local row = {
                        itemId = itemId,
                        itemGuid = guid,
                        itemLink = link,
                        itemName = (drop and drop.itemName) or meta.name,
                        itemQuality = (drop and drop.itemQuality) or quality,
                    }
                    if guid and guid ~= "" then
                        snapshot.byGuid[guid] = row
                    else
                        snapshot.noGuidCounts[itemId] = (snapshot.noGuidCounts[itemId] or 0) + 1
                        snapshot.noGuidRows[itemId] = snapshot.noGuidRows[itemId] or row
                    end
                end
            end
        end
    end
    return snapshot
end

function Ledger:AttachLocalBagGuid(itemId)
    local me = localPlayer()
    local guids = self:FindBagGuidsForItem(itemId)
    if #guids == 0 then return end
    local used = {}
    for _, drop in ipairs(self:Drops()) do
        if drop.itemGuid then used[drop.itemGuid] = true end
    end
    for _, drop in ipairs(self:Drops()) do
        if drop.itemId == itemId and samePlayer(drop.currentHolder, me) and not drop.itemGuid then
            local assigned
            for _, candidate in ipairs(guids) do
                if candidate.itemGuid and not used[candidate.itemGuid] then
                    assigned = candidate.itemGuid
                    break
                end
            end
            drop.itemGuid = assigned or guids[1].itemGuid
            if drop.itemGuid then
                used[drop.itemGuid] = true
                self:AppendEvent(drop, "bag_guid_seen", { itemGuid = drop.itemGuid })
                self:BroadcastUpdate(drop, "GUID")
                self:NotifyChanged()
            end
            return
        end
    end
end

function Ledger:AttachPendingLocalGuids()
    local me = localPlayer()
    local wanted = {}
    for _, drop in ipairs(self:Drops()) do
        if not drop.itemGuid and drop.itemId and samePlayer(drop.currentHolder, me) then
            wanted[drop.itemId] = true
        end
    end
    for itemId in pairs(wanted) do
        self:AttachLocalBagGuid(itemId)
    end
end

function Ledger:CurrentBagGuids()
    local guids = {}
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local guid = itemGuidFromBagSlot(bag, slot)
            if guid then guids[guid] = true end
        end
    end
    return guids
end

function Ledger:CurrentEquippedTrackedItems()
    local equipped = { byGuid = {}, byItemId = {} }
    for slot = 1, 19 do
        local itemId = GetInventoryItemID and GetInventoryItemID("player", slot)
        if itemId then
            local guid = itemGuidFromEquipmentSlot(slot)
            if guid then equipped.byGuid[guid] = { itemId = itemId, slot = slot } end
            equipped.byItemId[itemId] = equipped.byItemId[itemId] or {}
            table.insert(equipped.byItemId[itemId], { itemGuid = guid, slot = slot })
        end
    end
    return equipped
end

function Ledger:IsOpenLocalDrop(drop)
    if not drop or not drop.itemGuid then return false end
    if not samePlayer(drop.currentHolder, localPlayer()) then return false end
    local status = drop.status or "pending"
    return status ~= "disenchanted"
        and status ~= "removed_unknown"
        and status ~= "guild_bank"
        and status ~= "final_owner_confirmed"
        and status ~= "obtained"
end

function Ledger:ScheduleBagAudit()
    if self.bagAuditPending or not C_Timer then return end
    self.bagAuditPending = true
    C_Timer.After(0.8, function()
        self.bagAuditPending = false
        self:AttachPendingLocalGuids()
        self:AuditLocalBoundTrackedItems()
        self:AuditMissingLocalTrackedGuids()
        self:NotifyChanged()
    end)
end

function Ledger:ScheduleShortFinalizationAudit()
    if self.shortFinalizationAuditPending or not C_Timer then return end
    self.shortFinalizationAuditPending = true
    C_Timer.After(4, function()
        self.shortFinalizationAuditPending = false
        self:ScheduleBagAudit()
    end)
end

function Ledger:ScheduleTradeWindowAudit()
    if self.tradeWindowAuditPending or not C_Timer then return end
    self.tradeWindowAuditPending = true
    C_Timer.After(60, function()
        self.tradeWindowAuditPending = false
        self:AuditLocalBoundTrackedItems()
        for _, drop in ipairs(self:Drops()) do
            if self:IsOpenLocalDrop(drop) then
                self:ScheduleTradeWindowAudit()
                break
            end
        end
    end)
end

function Ledger:AuditLocalBoundTrackedItems()
    if self.tradeTarget or self.tradeSnapshot or self.tradeComplete or (TradeFrame and TradeFrame:IsShown()) then return end
    local now = time()
    local changed = false
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local info = containerInfo(bag, slot)
            local itemId = info and info.itemID
            if itemId and not self:IsIgnoredLootItem(itemId) then
                local guid = itemGuidFromBagSlot(bag, slot)
                local drop = self:FindDropForBagItem(itemId, guid)
                if self:IsOpenLocalDrop(drop) and math.abs(now - (drop.droppedAt or now)) >= 3 then
                    local link = info.hyperlink or (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or GetContainerItemLink(bag, slot)
                    local meta = itemInfo(link or itemId)
                    if meta.bindType == 1 and not self:TradeableTooltipLine(bag, slot) then
                        if self:ApplyStatusUpdate(drop, "final_owner_confirmed", localPlayer(), now, false, "bop_not_tradeable", true) then
                            ns:Debug("LootLedger finalized BoP item with no trade window", drop.itemName or itemId)
                            changed = true
                        end
                    end
                end
            end
        end
    end
    if changed then self:NotifyChanged() end
end

function Ledger:AuditMissingLocalTrackedGuids()
    if self.tradeTarget or self.tradeSnapshot or self.tradeComplete or (TradeFrame and TradeFrame:IsShown()) then return end
    local seen = self:CurrentBagGuids()
    local equipped = self:CurrentEquippedTrackedItems()
    local now = time()
    local recentDisenchant = self.lastDisenchantAt and math.abs(now - self.lastDisenchantAt) <= 8
    local recentPlayerSpell = self.lastPlayerSpellSucceededAt and math.abs(now - self.lastPlayerSpellSucceededAt) <= 8
    local recentNpcExchange = self.lastNpcExchangeAt and math.abs(now - self.lastNpcExchangeAt) <= 30
    local recentGuildBank = self.guildBankOpen or (self.lastGuildBankAt and math.abs(now - self.lastGuildBankAt) <= 8)
    for _, drop in ipairs(self:Drops()) do
        if self:IsOpenLocalDrop(drop) and not seen[drop.itemGuid] then
            local meta = itemInfo(drop.itemLink or drop.itemId)
            local equippedMatch = (drop.itemGuid and equipped.byGuid[drop.itemGuid]) or (drop.itemId and equipped.byItemId[drop.itemId] and equipped.byItemId[drop.itemId][1])
            if equippedMatch then
                self:ApplyStatusUpdate(drop, "final_owner_confirmed", localPlayer(), now, false, "equipped_by_holder", true)
            elseif recentDisenchant then
                self:MarkDisenchanted(drop, localPlayer(), "bag_guid_missing_after_disenchant", true)
            elseif recentPlayerSpell and isRecipeItem(meta) then
                self:MarkObtained(drop, "recipe_learned_by_holder", true)
            elseif recentNpcExchange and self:IsTierTokenItem(drop.itemId) then
                self:MarkObtained(drop, "npc_exchange_or_token_redeem", true)
            elseif recentGuildBank then
                self:MarkGuildBank(drop, "bag_guid_missing_while_guild_bank_open", true)
            else
                self:MarkRemovedUnknown(drop, "bag_guid_missing", true)
            end
        end
    end
end

function Ledger:FindTransferDrop(itemId, itemGuid, fromPlayer, allowRemovedUnknown)
    for _, drop in ipairs(self:Drops()) do
        local status = drop.status or "pending"
        if itemGuid and drop.itemGuid == itemGuid
            and status ~= "disenchanted"
            and status ~= "guild_bank"
            and (allowRemovedUnknown or status ~= "removed_unknown") then
            return drop
        end
    end
    local best
    local bestRank = 0
    for _, drop in ipairs(self:Drops()) do
        local status = drop.status or "pending"
        if drop.itemId == itemId
            and samePlayer(drop.currentHolder, fromPlayer)
            and status ~= "disenchanted"
            and status ~= "guild_bank"
            and (allowRemovedUnknown or status ~= "removed_unknown") then
            local rank = status == "pending" and 4
                or status == "traded" and 3
                or status == "removed_unknown" and 2
                or 1
            if not best
                or rank > bestRank
                or (rank == bestRank and (drop.droppedAt or 0) > (best.droppedAt or 0)) then
                best = drop
                bestRank = rank
            end
        end
    end
    return best
end

function Ledger:RemoteDrop(itemId, itemGuid, dropId)
    local at = time()
    local meta = itemInfo(itemId)
    local holder = "Unknown"
    local fallbackDropId = self:NextDropId(itemId, holder, at)
    local drop = {
        dropInstanceId = dropId and dropId ~= "" and dropId or fallbackDropId,
        lootId = dropId and dropId ~= "" and dropId or fallbackDropId,
        itemGuid = itemGuid,
        itemId = itemId,
        itemName = meta.name or nil,
        itemLink = meta.link,
        itemQuality = meta.quality,
        itemIcon = meta.icon,
        firstHolder = holder,
        currentHolder = holder,
        status = "pending",
        droppedAt = at,
        updatedAt = at,
        events = {},
    }
    self:AppendEvent(drop, "remote_transfer_placeholder", { itemGuid = itemGuid })
    table.insert(self:Drops(), 1, drop)
    while #self:Drops() > MAX_DROPS do table.remove(self:Drops()) end
    return drop
end

function Ledger:CreateLocalTradeDrop(itemId, itemGuid, fromPlayer, at, reason)
    at = at or time()
    local meta = itemInfo(itemId)
    local lootSource, lootSourceInstance = self:RaidLootSource(itemId)
    local ctx = self:CurrentRaidContextSnapshot()
    local store = self:Store()
    local active = store and store.activeSession
    local eligibilityCtx = ctx or active
    if not itemId or not self:IsTrackedLootItem(itemId, meta and meta.quality, meta, eligibilityCtx) then return nil end
    local sessionKey, sessionStartedAt, sessionReason, sessionZoneID, entrySerial

    if ctx and (not lootSourceInstance or ctx.raidName == lootSourceInstance) then
        sessionKey = ctx.sessionKey
        sessionStartedAt = ctx.sessionStartedAt
        sessionReason = ctx.sessionReason
        sessionZoneID = ctx.zoneID
        entrySerial = ctx.entrySerial
    elseif active and active.sourceInstance == lootSourceInstance and math.abs(at - (active.updatedAt or active.startedAt or at)) <= SESSION_REUSE_SECONDS then
        sessionKey = active.id
        sessionStartedAt = active.startedAt
        sessionReason = active.reason
        sessionZoneID = active.zoneID
        entrySerial = active.entrySerial
    end

    local dropId = self:NextDropId(itemId, fromPlayer, at)
    local drop = {
        dropInstanceId = dropId,
        lootId = dropId,
        itemGuid = itemGuid,
        itemId = itemId,
        itemName = meta.name or nil,
        itemLink = meta.link,
        itemQuality = meta.quality,
        itemIcon = meta.icon,
        firstHolder = fromPlayer,
        currentHolder = fromPlayer,
        finalOwner = nil,
        status = "pending",
        bossName = lootSource,
        bossAttributionAt = at,
        bossSourceType = lootSource and "loot_table" or "trade_observed",
        lootSource = lootSource,
        lootSourceInstance = lootSourceInstance,
        sourceInstance = (ctx and ctx.raidName) or lootSourceInstance,
        instanceType = (ctx and ctx.instanceType) or (lootSourceInstance and "raid" or nil),
        instanceId = ctx and ctx.instanceId or nil,
        difficultyId = ctx and ctx.difficultyId or nil,
        sessionKey = sessionKey,
        sessionStartedAt = sessionStartedAt,
        sessionReason = sessionReason,
        sessionZoneID = sessionZoneID,
        entrySerial = entrySerial,
        droppedAt = at,
        updatedAt = at,
        events = {},
    }
    self:AppendEvent(drop, reason or "local_trade_placeholder", { holder = fromPlayer, itemGuid = itemGuid })
    table.insert(self:Drops(), 1, drop)
    while #self:Drops() > MAX_DROPS do table.remove(self:Drops()) end
    return drop
end

function Ledger:ApplyTransfer(itemId, itemGuid, fromPlayer, toPlayer, at, remote, reason, dropId, transferContext)
    if samePlayer(fromPlayer, toPlayer) then
        ns:Debug("LootLedger ignored no-op transfer", itemId or "?", fromPlayer or "?", "->", toPlayer or "?")
        return false
    end
    local drop = dropId and dropId ~= "" and self:FindDropById(dropId) or nil
    if not drop then drop = self:FindTransferDrop(itemId, itemGuid, fromPlayer, true) end
    if not drop and not remote then
        drop = self:CreateLocalTradeDrop(itemId, itemGuid, fromPlayer, at, "trade_missing_original_drop")
    end
    if not drop and remote and itemId and not self:IsTrackedLootItem(itemId, transferContext and transferContext.itemQuality, nil, transferContext) then
        return false
    end
    if not drop and remote and itemId then
        drop = self:RemoteDrop(itemId, itemGuid, dropId)
        drop.firstHolder = fromPlayer
        drop.currentHolder = fromPlayer
    end
    if not drop then return false end
    if samePlayer(drop.currentHolder, toPlayer)
        and drop.status == "traded"
        and math.abs((drop.tradedAt or 0) - (at or time())) <= 30 then
        return false, drop
    end
    local oldHolder = drop.currentHolder
    drop.currentHolder = toPlayer
    drop.finalOwner = toPlayer
    drop.status = "traded"
    drop.tradedAt = at or time()
    if itemGuid and not drop.itemGuid then drop.itemGuid = itemGuid end
    if dropId and dropId ~= "" then
        drop.dropInstanceId = drop.dropInstanceId or dropId
        drop.lootId = drop.lootId or dropId
    end
    self:AppendEvent(drop, reason or "trade_completed", {
        from = fromPlayer,
        to = toPlayer,
        itemGuid = itemGuid,
        remote = remote and true or nil,
    })
    ns:Debug("LootLedger transfer", drop.itemName or itemId, oldHolder or "?", "->", toPlayer)
    if samePlayer(toPlayer, localPlayer()) then
        self:ScheduleBagAudit()
        self:ScheduleShortFinalizationAudit()
        self:ScheduleTradeWindowAudit()
    end
    self:NotifyChanged()
    return true, drop
end

function Ledger:CommitTradeBagDiff(target, before, at)
    if not target or not before then
        ns:Debug("LootLedger trade bag diff skipped: missing target or before snapshot")
        return false
    end
    local after = self:TrackedBagSnapshot()
    local me = localPlayer()
    local changed = false
    local beforeGuidCount, afterGuidCount = 0, 0
    for _ in pairs(before.byGuid or {}) do beforeGuidCount = beforeGuidCount + 1 end
    for _ in pairs(after.byGuid or {}) do afterGuidCount = afterGuidCount + 1 end
    ns:Debug("LootLedger trade bag diff", target, "beforeGuid", beforeGuidCount, "afterGuid", afterGuidCount)

    for guid, row in pairs(before.byGuid or {}) do
        if not after.byGuid[guid] then
            local ok, drop = self:ApplyTransfer(row.itemId, guid, me, target, at or time(), false, "trade_bag_diff")
            if ok then
                self:BroadcastTransfer(row.itemId, guid, me, target, at or time(), "trade_bag_diff", drop)
                changed = true
            end
        end
    end

    for guid, row in pairs(after.byGuid or {}) do
        if not before.byGuid[guid] then
            local ok, drop = self:ApplyTransfer(row.itemId, guid, target, me, at or time(), false, "trade_bag_diff")
            if ok then
                self:BroadcastTransfer(row.itemId, guid, target, me, at or time(), "trade_bag_diff", drop)
                self:ScheduleGuidAttach(row.itemId)
                changed = true
            end
        end
    end

    for itemId, beforeCount in pairs(before.noGuidCounts or {}) do
        local afterCount = after.noGuidCounts[itemId] or 0
        for _ = 1, math.max(0, beforeCount - afterCount) do
            local row = before.noGuidRows[itemId] or { itemId = itemId }
            local ok, drop = self:ApplyTransfer(row.itemId, nil, me, target, at or time(), false, "trade_bag_diff")
            if ok then
                self:BroadcastTransfer(row.itemId, nil, me, target, at or time(), "trade_bag_diff", drop)
                changed = true
            end
        end
    end

    for itemId, afterCount in pairs(after.noGuidCounts or {}) do
        local beforeCount = before.noGuidCounts[itemId] or 0
        for _ = 1, math.max(0, afterCount - beforeCount) do
            local row = after.noGuidRows[itemId] or { itemId = itemId }
            local ok, drop = self:ApplyTransfer(row.itemId, nil, target, me, at or time(), false, "trade_bag_diff")
            if ok then
                self:BroadcastTransfer(row.itemId, nil, target, me, at or time(), "trade_bag_diff", drop)
                self:ScheduleGuidAttach(row.itemId)
                changed = true
            end
        end
    end

    if changed then
        ns:Print("Raid loot trade recorded.", "success")
        self:NotifyChanged()
    else
        ns:Debug("LootLedger trade bag diff found no tracked changes", target)
    end
    return changed
end

function Ledger:CanAcceptRemoteTransfer(sender, fromPlayer, toPlayer)
    if self:IsTrustedLootManagerName(sender) then return true end
    return samePlayer(sender, fromPlayer) or samePlayer(sender, toPlayer)
end

function Ledger:CanAcceptRemoteDrop(sender, holder)
    if self:IsTrustedLootManagerName(sender) then return true end
    return samePlayer(sender, holder)
end

function Ledger:ParseGargulHandout(message, sender)
    if not message or not message:find("Gargul", 1, true) then return nil end
    if not message:find("I gave", 1, true) then return nil end
    local itemLink = message:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
    if not itemLink then return nil end
    local target = message:match("Gargul%s*:%s*I gave%s+.-%s+to%s+([^%s%.!]+)")
    if not target or target == "" then return nil end
    return fullPlayerName(sender), cleanItemLink(itemLink), fullPlayerName(target)
end

function Ledger:TrackGargulMessage(message, sender)
    if self:Settings().allowGargulFallback ~= true then return false end
    local fromPlayer, itemLink, toPlayer = self:ParseGargulHandout(message, sender)
    if not fromPlayer or not itemLink or not toPlayer then return false end
    local itemId = itemIdFromLink(itemLink)
    if not itemId then return false end
    local at = time()
    local ok, drop = self:ApplyTransfer(itemId, nil, fromPlayer, toPlayer, at, false, "external_gargul_fallback")
    if ok then
        self:BroadcastTransfer(itemId, nil, fromPlayer, toPlayer, at, "external_gargul_fallback", drop)
        ns:Debug("LootLedger external Gargul fallback", itemId, fromPlayer, "->", toPlayer)
        return true
    end
    return false
end

function Ledger:TradeTargetName()
    if TradeFrameRecipientNameText then
        local text = TradeFrameRecipientNameText:GetText()
        if text and text ~= "" then return fullPlayerName((strsplit(" ", text))) end
    end
    if UnitExists("npc") then return fullPlayerName(UnitName("npc")) end
    return nil
end

function Ledger:SnapshotTrade()
    local target = self.tradeTarget or self:TradeTargetName()
    if not target then
        ns:Debug("LootLedger trade snapshot skipped: no target")
        return
    end
    local gave = {}
    local received = {}
    local usedGuid = {}

    for slot = 1, 6 do
        local link = GetTradePlayerItemLink(slot)
        local itemId = itemIdFromLink(link)
        if itemId then
            local matches = self:FindBagGuidsForItem(itemId)
            local guid
            for _, m in ipairs(matches) do
                if m.itemGuid and not usedGuid[m.itemGuid] then
                    guid = m.itemGuid
                    usedGuid[guid] = true
                    break
                end
            end
            table.insert(gave, { itemId = itemId, itemGuid = guid, itemLink = link })
        end

        link = GetTradeTargetItemLink(slot)
        itemId = itemIdFromLink(link)
        if itemId then table.insert(received, { itemId = itemId, itemLink = link }) end
    end

    if #gave > 0 or #received > 0 then
        self.tradeSnapshot = { target = target, gave = gave, received = received, at = time() }
        ns:Debug("LootLedger trade snapshot", target, "gave", #gave, "received", #received)
    else
        ns:Debug("LootLedger trade snapshot empty", target)
    end
end

function Ledger:ScheduleTradeSnapshot()
    self:SnapshotTrade()
    if not C_Timer then return end
    C_Timer.After(0.05, function() self:SnapshotTrade() end)
    C_Timer.After(0.25, function() self:SnapshotTrade() end)
    C_Timer.After(0.50, function() self:SnapshotTrade() end)
end

function Ledger:CommitTrade()
    if self.tradeCommitted then return end
    local snap = self.tradeSnapshot
    if not snap then
        ns:Debug("LootLedger trade commit skipped: no trade-frame snapshot")
        return
    end
    self.tradeCommitted = true
    local me = localPlayer()
    local changed = false

    for _, item in ipairs(snap.gave or {}) do
        local ok, drop = self:ApplyTransfer(item.itemId, item.itemGuid, me, snap.target, snap.at, false, "trade_completed")
        if ok then
            self:BroadcastTransfer(item.itemId, item.itemGuid, me, snap.target, snap.at, "trade_completed", drop)
            changed = true
        end
    end

    for _, item in ipairs(snap.received or {}) do
        local ok, drop = self:ApplyTransfer(item.itemId, nil, snap.target, me, snap.at, false, "trade_completed")
        if ok then
            self:BroadcastTransfer(item.itemId, nil, snap.target, me, snap.at, "trade_completed", drop)
            changed = true
            self:ScheduleGuidAttach(item.itemId)
        end
    end

    self.tradeSnapshot = nil
    if changed then ns:Print("Raid loot trade recorded.", "success") end
    ns:Debug("LootLedger trade commit", snap.target or "?", "changed", changed and "yes" or "no", "gave", #(snap.gave or {}), "received", #(snap.received or {}))
end

function Ledger:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX or sender == UnitName("player") or sender == localPlayer() then return end
    local op, rest = strsplit("|", message, 2)
    if op == "DR2" then
        self:ReceiveDropBroadcast(rest, sender, true)
    elseif op == "DR" then
        self:ReceiveDropBroadcast(rest, sender)
    elseif op == "TL3" then
        local dropId, itemId, guid, fromPlayer, toPlayer, at, reason, itemName, quality, sessionKey, sourceInstance, bossName = strsplit("|", rest or "", 12)
        if not self:CanAcceptRemoteTransfer(sender, fromPlayer, toPlayer) then return end
        local inferredInstanceType = TEST_DUNGEON_NAMES[lower(sourceInstance or "")] and "party" or nil
        local ok, drop = self:ApplyTransfer(tonumber(itemId), guid ~= "" and guid or nil, fromPlayer, toPlayer, tonumber(at) or time(), true, reason ~= "" and reason or "trade_completed", dropId, {
            itemQuality = tonumber(quality),
            sourceInstance = sourceInstance ~= "" and sourceInstance or nil,
            lootSourceInstance = sourceInstance ~= "" and sourceInstance or nil,
            instanceType = inferredInstanceType,
        })
        if ok and drop then
            quality = tonumber(quality)
            if itemName and itemName ~= "" and (not drop.itemName or drop.itemName:find("^Item #")) then drop.itemName = itemName end
            drop.itemQuality = drop.itemQuality or quality
            drop.sessionKey = drop.sessionKey or (sessionKey ~= "" and sessionKey or nil)
            drop.sourceInstance = drop.sourceInstance or (sourceInstance ~= "" and sourceInstance or nil)
            drop.bossName = drop.bossName or (bossName ~= "" and bossName or nil)
            drop.lootSource = drop.lootSource or (bossName ~= "" and bossName or nil)
            drop.lootSourceInstance = drop.lootSourceInstance or (sourceInstance ~= "" and sourceInstance or nil)
            if bossName and bossName ~= "" and not drop.bossSourceType then drop.bossSourceType = "remote_transfer" end
            self:NotifyChanged()
        end
    elseif op == "TL2" then
        local dropId, itemId, guid, fromPlayer, toPlayer, at, reason, itemName = strsplit("|", rest or "", 8)
        if not self:CanAcceptRemoteTransfer(sender, fromPlayer, toPlayer) then return end
        local ok, drop = self:ApplyTransfer(tonumber(itemId), guid ~= "" and guid or nil, fromPlayer, toPlayer, tonumber(at) or time(), true, reason ~= "" and reason or "trade_completed", dropId)
        if ok and drop then
            if itemName and itemName ~= "" and (not drop.itemName or drop.itemName:find("^Item #")) then drop.itemName = itemName end
        end
    elseif op == "TL" then
        local itemId, guid, fromPlayer, toPlayer, at, reason = strsplit("|", rest or "")
        if not self:CanAcceptRemoteTransfer(sender, fromPlayer, toPlayer) then return end
        self:ApplyTransfer(tonumber(itemId), guid ~= "" and guid or nil, fromPlayer, toPlayer, tonumber(at) or time(), true, reason ~= "" and reason or "trade_completed")
    elseif op == "ST" then
        local dropId, status, actor, at = strsplit("|", rest or "")
        if not self:FindDropById(dropId) then
            self:QueuePendingRemoteStatus(dropId, status, actor, tonumber(at) or time(), sender)
            return
        end
        if not self:CanAcceptRemoteStatus(sender, dropId, actor) then return end
        self:ApplyStatusUpdate(dropId, status, actor, tonumber(at) or time(), true)
    elseif op == "LS1" then
        self:ReceiveLootSyncState(rest, sender)
    elseif op == "LSREQ" then
        self:ReceiveLootSyncRequest(rest, sender)
    elseif op == "GUID" then
        local dropId, guid = strsplit("|", rest or "")
        for _, drop in ipairs(self:Drops()) do
            if drop.dropInstanceId == dropId and guid and guid ~= "" then
                drop.itemGuid = guid
                self:AppendEvent(drop, "remote_guid_seen", { itemGuid = guid, actor = sender })
                self:NotifyChanged()
                break
            end
        end
    elseif op == "RR" then
        self:ReceiveResponseRequest(rest, sender)
    elseif op == "RP" then
        self:ReceiveLootResponse(rest)
    end
end

function Ledger:SendAddonMessage(message, channel, target)
    if channel == "WHISPER" and (not target or target == "") then return end
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, message, channel, target, "NORMAL") end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, message, channel, target)
end

function Ledger:Broadcast(message, preferGuild)
    local channel
    if preferGuild and IsInGuild and IsInGuild() then
        channel = "GUILD"
    else
        local inRaid = IsInRaid and IsInRaid()
        local inGroup = IsInGroup and IsInGroup()
        channel = inRaid and "RAID" or (inGroup and "PARTY" or nil)
    end
    if not channel then return end
    self:SendAddonMessage(message, channel)
end

function Ledger:BroadcastRequest(request)
    if not request then return end
    self:Broadcast(("RR|%s|%s|%d|%s"):format(
        cleanAddonField(request.requestId),
        cleanAddonField(request.dropId),
        request.itemId or 0,
        cleanAddonField(request.itemName)))
end

function Ledger:BroadcastResponse(requestId, response)
    local _, classFile = UnitClass("player")
    self:Broadcast(("RP|%s|%s|%s|%s|%d"):format(
        cleanAddonField(requestId),
        cleanAddonField(localPlayer()),
        cleanAddonField(classFile),
        cleanAddonField(response),
        time()))
end

function Ledger:BroadcastTransfer(itemId, guid, fromPlayer, toPlayer, at, reason, drop)
    local dropId = drop and (drop.dropInstanceId or drop.lootId) or ""
    local itemName = drop and drop.itemName or ""
    self:Broadcast(("TL3|%s|%d|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s"):format(
        cleanAddonField(dropId),
        itemId or 0,
        cleanAddonField(guid or ""),
        cleanAddonField(fromPlayer or ""),
        cleanAddonField(toPlayer or ""),
        at or time(),
        cleanAddonField(reason or ""),
        cleanAddonField(itemName),
        cleanAddonField(drop and drop.itemQuality or ""),
        cleanAddonField(drop and drop.sessionKey or ""),
        cleanAddonField(drop and (drop.sourceInstance or drop.lootSourceInstance) or ""),
        cleanAddonField(drop and (drop.bossName or drop.lootSource) or "")), true)
end

function Ledger:BroadcastStatus(drop, status, actor, at, target)
    if not drop or not drop.dropInstanceId then return end
    local message = ("ST|%s|%s|%s|%d"):format(drop.dropInstanceId or "", status or "", actor or localPlayer(), at or time())
    if target then
        self:SendAddonMessage(message, "WHISPER", target)
    else
        self:Broadcast(message, true)
    end
end

function Ledger:BroadcastUpdate(drop, kind, target)
    if kind == "GUID" and drop and drop.itemGuid then
        local message = ("GUID|%s|%s"):format(drop.dropInstanceId or "", drop.itemGuid or "")
        if target then
            self:SendAddonMessage(message, "WHISPER", target)
        else
            self:Broadcast(message, true)
        end
    end
end

function Ledger:FindDropForBagItem(itemId, itemGuid)
    local me = localPlayer()
    if itemGuid then
        for _, drop in ipairs(self:Drops()) do
            if drop.itemGuid == itemGuid then return drop end
        end
    end
    local best
    for _, drop in ipairs(self:Drops()) do
        local status = drop.status or "pending"
        if drop.itemId == itemId
            and samePlayer(drop.currentHolder, me)
            and status ~= "disenchanted"
            and status ~= "removed_unknown"
            and status ~= "guild_bank"
            and status ~= "final_owner_confirmed"
            and status ~= "obtained"
            and (not best or (drop.droppedAt or 0) > (best.droppedAt or 0)) then
            best = drop
        end
    end
    return best
end

function Ledger:TradeableTooltipLine(bag, slot)
    if not bag or not slot then return nil end
    self.tradeScanTooltip = self.tradeScanTooltip or CreateFrame("GameTooltip", "IDDQDLootTradeScanTooltip", UIParent, "GameTooltipTemplate")
    local tooltip = self.tradeScanTooltip
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetBagItem(bag, slot)

    local tradePrefix, tradeSuffix
    if BIND_TRADE_TIME_REMAINING then
        tradePrefix, tradeSuffix = strsplit("%%s", BIND_TRADE_TIME_REMAINING)
    end

    for i = 1, tooltip:NumLines() do
        local line = _G["IDDQDLootTradeScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        local lowered = lower(text or "")
        local localizedMatch = text
            and tradePrefix and tradePrefix ~= ""
            and text:find(tradePrefix, 1, true)
            and (not tradeSuffix or tradeSuffix == "" or text:find(tradeSuffix, 1, true))
        if text and (
            localizedMatch
            or lowered:find("may trade", 1, true)
            or lowered:find("trade this item", 1, true)
            or lowered:find("eligible to loot", 1, true)) then
            return text
        end
    end
    return nil
end

function Ledger:ActiveTradableItems()
    local items = {}
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local info = containerInfo(bag, slot)
            local itemId = info and info.itemID
            if itemId and not self:IsIgnoredLootItem(itemId) then
                local tradeLine = self:TradeableTooltipLine(bag, slot)
                if tradeLine then
                    local link = info.hyperlink or (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or GetContainerItemLink(bag, slot)
                    local guid = itemGuidFromBagSlot(bag, slot)
                    local drop = self:FindDropForBagItem(itemId, guid)
                    if not self:IsTrackedRaidDrop(drop) then
                        -- Only tracked raid drops and explicitly enabled test-dungeon drops
                        -- are surfaced here.
                    else
                    local meta = itemInfo(link or itemId)
                    local dropId = drop and (drop.dropInstanceId or drop.lootId) or ("%d:%d:%d"):format(itemId, bag, slot)
                    local request = self:Requests()[dropId]
                    table.insert(items, {
                        bag = bag,
                        slot = slot,
                        itemId = itemId,
                        itemGuid = guid,
                        itemLink = link,
                        itemName = (drop and drop.itemName) or meta.name or ("Item #" .. tostring(itemId)),
                        itemQuality = (drop and drop.itemQuality) or meta.quality,
                        itemIcon = info.iconFileID or meta.icon,
                        count = info.stackCount or 1,
                        tradeLine = tradeLine,
                        drop = drop,
                        dropId = dropId,
                        request = request,
                    })
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b)
        local atA = a.drop and a.drop.droppedAt or 0
        local atB = b.drop and b.drop.droppedAt or 0
        if atA == atB then return (a.itemName or "") < (b.itemName or "") end
        return atA > atB
    end)
    return items
end

function Ledger:StartResponseRequest(activeItem, silent)
    if not self:CanManageLoot() then
        ns:Print("Only the raid leader or guild officers can request loot responses.", "warning")
        return nil
    end
    if not activeItem then return nil end
    local dropId = activeItem.dropId
    local requestId = ("%s:%d"):format(dropId or tostring(activeItem.itemId or 0), time())
    local request = {
        requestId = requestId,
        dropId = dropId,
        itemId = activeItem.itemId,
        itemName = activeItem.itemName,
        itemLink = activeItem.itemLink,
        itemQuality = activeItem.itemQuality,
        itemIcon = activeItem.itemIcon,
        requester = localPlayer(),
        startedAt = time(),
        responses = {},
    }
    self:Requests()[dropId] = request
    if activeItem.drop then
        activeItem.drop.responseRequestId = requestId
        activeItem.drop.responses = activeItem.drop.responses or {}
    end
    self:BroadcastRequest(request)
    if not silent then
        ns:Print(("Loot response request opened for %s."):format(activeItem.itemName or "item"), "success")
        self:NotifyChanged()
    end
    return request
end

function Ledger:StartResponseRequests(items)
    if not self:CanManageLoot() then
        ns:Print("Only the raid leader or guild officers can request loot responses.", "warning")
        return 0
    end
    items = items or self:ActiveTradableItems()
    local count = 0
    for _, item in ipairs(items or {}) do
        if self:StartResponseRequest(item, true) then count = count + 1 end
    end
    if count > 0 then
        ns:Print(("Loot response requests opened for %d tradeable item%s."):format(count, count == 1 and "" or "s"), "success")
        self:NotifyChanged()
    else
        ns:Print("No tradeable raid loot found to ask for.", "warning")
    end
    return count
end

function Ledger:ApplyLootResponse(requestId, playerName, classFile, response, at)
    if not requestId or not playerName or not response then return false end
    local requests = self:Requests()
    local request
    for _, candidate in pairs(requests) do
        if candidate.requestId == requestId then request = candidate; break end
    end
    if not request then
        request = {
            requestId = requestId,
            dropId = requestId,
            itemName = "Requested loot",
            startedAt = at or time(),
            responses = {},
        }
        requests[request.dropId] = request
    end
    request.responses = request.responses or {}
    request.responses[playerName] = {
        response = response,
        classFile = classFile,
        at = at or time(),
    }

    for _, drop in ipairs(self:Drops()) do
        if drop.responseRequestId == requestId or drop.dropInstanceId == request.dropId or drop.lootId == request.dropId then
            drop.responses = drop.responses or {}
            drop.responses[playerName] = request.responses[playerName]
            break
        end
    end
    self:NotifyChanged()
    return true
end

function Ledger:ReceiveResponseRequest(data, sender)
    if not self:IsTrustedLootManagerName(sender) then return end
    local requestId, dropId, itemId, itemName = strsplit("|", data or "", 4)
    if not requestId or requestId == "" then return end
    local request = {
        requestId = requestId,
        dropId = dropId,
        itemId = tonumber(itemId),
        itemName = itemName ~= "" and itemName or "Requested loot",
        requester = sender,
        startedAt = time(),
        responses = {},
    }
    self:Requests()[dropId or requestId] = request
    self:ShowResponsePopup(request)
    self:NotifyChanged()
end

function Ledger:ReceiveLootResponse(data)
    local requestId, playerName, classFile, response, at = strsplit("|", data or "", 5)
    if classFile == "" then classFile = nil end
    self:ApplyLootResponse(requestId, playerName, classFile, response, tonumber(at) or time())
end

function Ledger:ActiveResponseRequests()
    local requests = {}
    local cutoff = time() - 2 * 60 * 60
    for _, request in pairs(self:Requests()) do
        if request and request.requestId and ((request.startedAt or 0) >= cutoff) then
            requests[#requests + 1] = request
        end
    end
    table.sort(requests, function(a, b)
        local atA, atB = tonumber(a.startedAt) or 0, tonumber(b.startedAt) or 0
        if atA ~= atB then return atA > atB end
        return tostring(a.itemName or "") < tostring(b.itemName or "")
    end)
    return requests
end

function Ledger:ShowResponsePopup(request)
    if not request or not request.requestId then return end

    local Theme = ns:GetModule("Theme")
    local W = ns:GetModule("Widgets")
    if not Theme or not W then return end

    local f = self.responsePopup or CreateFrame("Frame", "IDDQDLootResponsePopup", UIParent, "BackdropTemplate")
    self.responsePopup = f
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(400)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Theme:Surface(f, "raised")
    W:CardEdge(f, 0.16)

    if not f.title then
        f:SetSize(640, 360)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)

        f.title = W:Title(f, "Loot Responses")
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.close = W:Button(f, "Close", 58, 22)
        f.close:SetPoint("TOPRIGHT", -12, -12)
        f.close:SetScript("OnClick", function() f:Hide() end)

        f.sub = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(f.sub, "caption", "dim")
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
        f.sub:SetText("Select a response for each requested item.")

        f.header = CreateFrame("Frame", nil, f)
        f.header:SetPoint("TOPLEFT", 14, -62)
        f.header:SetPoint("TOPRIGHT", -14, -62)
        f.header:SetHeight(18)
        f.header.bg = f.header:CreateTexture(nil, "BACKGROUND")
        f.header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.header.bg:SetAllPoints(f.header)
        f.header.bg:SetVertexColor(1, 1, 1, 0.025)

        local cols = {
            { "Item", 42, 230 },
            { "Status", 278, 82 },
            { "Response", 374, 170 },
        }
        for _, col in ipairs(cols) do
            local label = f.header:CreateFontString(nil, "OVERLAY")
            Theme:Text(label, "eyebrow", "warm")
            label:SetPoint("LEFT", col[2], 1)
            label:SetWidth(col[3])
            label:SetJustifyH("LEFT")
            label:SetText(col[1])
        end

        f.scroll, f.content = W:ScrollHost(f)
        f.scroll:SetPoint("TOPLEFT", 14, -82)
        f.scroll:SetPoint("BOTTOMRIGHT", -24, 14)
        f.scrollBar = W:ScrollBar(f.scroll, f.content)
        f.rows = {}
    end

    local function setButtonState(button, enabled)
        if enabled then button:Enable() else button:Disable() end
    end

    local function localResponse(req)
        local me = localPlayer()
        for player, response in pairs((req and req.responses) or {}) do
            if samePlayer(player, me) then return response and response.response end
        end
        return nil
    end

    local function ensureRow(i)
        local row = f.rows[i]
        if row then return row end
        row = W:ListRow(f.content)
        row:SetHeight(36)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 8, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconBorder = W:IconBorder(row.icon)

        row.name = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.name, "caption", "ink")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(214)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.status = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.status, "caption", "dim")
        row.status:SetPoint("LEFT", 278, 0)
        row.status:SetWidth(82)
        row.status:SetJustifyH("LEFT")
        row.status:SetWordWrap(false)

        row.buttons = {}
        local defs = {
            { "NEED", "Need", 374, 52 },
            { "GREED", "Greed", 430, 58 },
            { "OFFSPEC", "OS", 492, 42 },
            { "PASS", "Pass", 538, 52 },
        }
        for _, def in ipairs(defs) do
            local b = W:Button(row, def[2], def[4], 22)
            b:SetPoint("LEFT", def[3], 0)
            b.response = def[1]
            b:SetScript("OnClick", function(self)
                local req = row.request
                if not req then return end
                Ledger:ApplyLootResponse(req.requestId, localPlayer(), select(2, UnitClass("player")), self.response, time())
                Ledger:BroadcastResponse(req.requestId, self.response)
                if f.Refresh then f:Refresh() end
            end)
            row.buttons[def[1]] = b
        end

        f.rows[i] = row
        return row
    end

    function f:Refresh()
        local requests = Ledger:ActiveResponseRequests()
        for _, row in ipairs(self.rows) do row:Hide() end
        local contentW = math.max(590, (self.scroll:GetWidth() or 0) - 8)
        self.content:SetWidth(contentW)

        if #requests == 0 then
            local row = ensureRow(1)
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetSize(contentW, 36)
            row:SetRowVisual(1, false)
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText("No active loot requests")
            row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            row.status:SetText("-")
            for _, button in pairs(row.buttons) do button:Hide() end
            row.request = nil
            row:Show()
            self.content:SetHeight(36)
            self.scrollBar:Update()
            return
        end

        local y = 0
        for i, req in ipairs(requests) do
            local row = ensureRow(i)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(contentW, 36)
            row:SetRowVisual(i, false)
            local icon = req.itemIcon
            local quality
            if req.itemId and GetItemInfo then
                local _, _, cachedQuality, _, _, _, _, _, _, cachedIcon = GetItemInfo(req.itemId)
                quality = cachedQuality
                icon = icon or cachedIcon
            end
            local r, g, b = qualityColor(req.itemQuality or quality)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            if row.iconBorder then row.iconBorder:SetQuality(req.itemQuality or quality) end
            row.name:SetText(itemDisplayName(req))
            row.name:SetTextColor(r, g, b, 1)

            local answered = localResponse(req)
            local eligible = itemResponseEligible(req)
            if answered then
                row.status:SetText("|cff5fbf8a" .. answered:sub(1, 1) .. string.lower(answered:sub(2)) .. "|r")
            elseif eligible then
                row.status:SetText("|ffcaa65aOpen|r")
            else
                row.status:SetText("|cff646a76Cannot use|r")
            end

            for _, button in pairs(row.buttons) do button:Show() end
            setButtonState(row.buttons.NEED, eligible)
            setButtonState(row.buttons.GREED, eligible)
            setButtonState(row.buttons.OFFSPEC, eligible)
            setButtonState(row.buttons.PASS, true)
            row.request = req
            row:Show()
            y = y - 38
        end
        self.content:SetHeight(math.max(self.scroll:GetHeight() or 1, -y))
        self.scrollBar:Update()
    end

    f:Refresh()
    f:Show()
end

function Ledger:BroadcastDrop(drop, target)
    if not drop or not drop.dropInstanceId or not drop.itemId then return end
    local message = ("DR2|%s|%d|%s|%s|%d|%s|%s|%s|%s|%s|%s"):format(
        cleanAddonField(drop.dropInstanceId),
        drop.itemId or 0,
        cleanAddonField(drop.itemGuid or ""),
        cleanAddonField(drop.currentHolder or drop.firstHolder or ""),
        drop.droppedAt or time(),
        cleanAddonField(drop.itemQuality or ""),
        cleanAddonField(drop.sessionKey or ""),
        cleanAddonField(drop.sourceInstance or drop.lootSourceInstance or ""),
        cleanAddonField(drop.bossName or drop.lootSource or ""),
        cleanAddonField(drop.instanceType or ""),
        cleanAddonField(drop.itemName or ""))
    if target then
        self:SendAddonMessage(message, "WHISPER", target)
    else
        self:Broadcast(message, true)
    end
end

function Ledger:FindDropById(dropId)
    if not dropId then return nil end
    for _, drop in ipairs(self:Drops()) do
        if drop.dropInstanceId == dropId or drop.lootId == dropId then return drop end
    end
    return nil
end

function Ledger:ReceiveDropBroadcast(data, sender, hasInstanceType)
    local dropId, itemId, guid, holder, at, quality, sessionKey, sourceInstance, bossName, instanceType, itemName
    if hasInstanceType then
        dropId, itemId, guid, holder, at, quality, sessionKey, sourceInstance, bossName, instanceType, itemName = strsplit("|", data or "", 11)
    else
        dropId, itemId, guid, holder, at, quality, sessionKey, sourceInstance, bossName, itemName = strsplit("|", data or "", 10)
    end
    itemId = tonumber(itemId)
    at = tonumber(at) or time()
    quality = tonumber(quality)
    guid = guid ~= "" and guid or nil
    holder = holder ~= "" and holder or nil
    sessionKey = sessionKey ~= "" and sessionKey or nil
    sourceInstance = sourceInstance ~= "" and sourceInstance or nil
    bossName = bossName ~= "" and bossName or nil
    itemName = itemName ~= "" and itemName or nil
    if not dropId or dropId == "" or not itemId then return end
    if not self:CanAcceptRemoteDrop(sender, holder) then return end
    if not self:IsTrackedLootItem(itemId, quality, nil, {
        instanceType = instanceType ~= "" and instanceType or nil,
        sourceInstance = sourceInstance,
        lootSourceInstance = sourceInstance,
    }) then return end

    local drop = self:FindDropById(dropId)
    if not drop and guid then
        for _, candidate in ipairs(self:Drops()) do
            if candidate.itemGuid == guid then drop = candidate; break end
        end
    end
    local meta = itemInfo(itemId)
    if not meta.name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end
    if drop then
        drop.itemGuid = drop.itemGuid or guid
        drop.itemName = drop.itemName or itemName or meta.name or nil
        drop.itemQuality = drop.itemQuality or quality or meta.quality
        drop.itemIcon = drop.itemIcon or meta.icon
        drop.firstHolder = drop.firstHolder or holder
        drop.currentHolder = drop.currentHolder or holder
        drop.sourceInstance = drop.sourceInstance or sourceInstance
        drop.instanceType = drop.instanceType or (instanceType ~= "" and instanceType or nil)
        drop.bossName = drop.bossName or bossName
        drop.sessionKey = drop.sessionKey or sessionKey
        self:AppendEvent(drop, "remote_drop_updated", { actor = sender, itemGuid = guid })
    else
        drop = {
            dropInstanceId = dropId,
            lootId = dropId,
            itemGuid = guid,
            itemId = itemId,
            itemName = itemName or meta.name or nil,
            itemLink = meta.link,
            itemQuality = quality or meta.quality,
            itemIcon = meta.icon,
            firstHolder = holder,
            currentHolder = holder,
            status = "pending",
            sourceInstance = sourceInstance,
            instanceType = instanceType ~= "" and instanceType or nil,
            bossName = bossName,
            lootSource = bossName,
            lootSourceInstance = sourceInstance,
            bossSourceType = bossName and "remote_drop" or nil,
            sessionKey = sessionKey,
            droppedAt = at,
            updatedAt = at,
            events = {},
        }
        self:AppendEvent(drop, "remote_drop_seen", { actor = sender, itemGuid = guid })
        table.insert(self:Drops(), 1, drop)
        while #self:Drops() > MAX_DROPS do table.remove(self:Drops()) end
    end
    self:MergeDuplicateDrops()
    self:ApplyPendingRemoteStatuses(drop)
    self:NotifyChanged()
end

function Ledger:SendLootSyncState(drop, target)
    if not drop or not drop.dropInstanceId or not drop.itemId or not target then return end
    local message = ("LS1|%s|%d|%s|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%s"):format(
        cleanAddonField(drop.dropInstanceId),
        drop.itemId or 0,
        cleanAddonField(drop.itemGuid or ""),
        cleanAddonField(drop.firstHolder or ""),
        cleanAddonField(drop.currentHolder or ""),
        cleanAddonField(drop.status or "pending"),
        cleanAddonField(drop.finalOwner or ""),
        self:DropSyncStamp(drop),
        drop.droppedAt or 0,
        cleanAddonField(drop.itemQuality or ""),
        cleanAddonField(drop.sessionKey or ""),
        cleanAddonField(drop.sourceInstance or drop.lootSourceInstance or ""),
        cleanAddonField(drop.bossName or drop.lootSource or ""),
        cleanAddonField(drop.instanceType or ""))
    self:SendAddonMessage(message, "WHISPER", target)
end

function Ledger:ReceiveLootSyncState(data, sender)
    local dropId, itemId, guid, firstHolder, currentHolder, status, finalOwner, updatedAt, droppedAt, quality, sessionKey, sourceInstance, bossName, instanceType =
        strsplit("|", data or "", 14)
    itemId = tonumber(itemId)
    updatedAt = tonumber(updatedAt) or 0
    droppedAt = tonumber(droppedAt) or updatedAt or time()
    quality = tonumber(quality)
    guid = guid ~= "" and guid or nil
    firstHolder = firstHolder ~= "" and firstHolder or nil
    currentHolder = currentHolder ~= "" and currentHolder or firstHolder
    finalOwner = finalOwner ~= "" and finalOwner or nil
    status = status ~= "" and status or "pending"
    sessionKey = sessionKey ~= "" and sessionKey or nil
    sourceInstance = sourceInstance ~= "" and sourceInstance or nil
    bossName = bossName ~= "" and bossName or nil
    instanceType = instanceType ~= "" and instanceType or nil
    if not dropId or dropId == "" or not itemId then return end
    if not self:IsTrackedLootItem(itemId, quality, nil, {
        instanceType = instanceType,
        sourceInstance = sourceInstance,
        lootSourceInstance = sourceInstance,
    }) then return end

    local drop = self:FindDropById(dropId)
    if not drop and guid then
        for _, candidate in ipairs(self:Drops()) do
            if candidate.itemGuid == guid then drop = candidate; break end
        end
    end

    local localStamp = self:DropSyncStamp(drop)
    local desiredStamp = math.max(localStamp or 0, updatedAt or 0, droppedAt or 0)
    local meta = itemInfo(itemId)
    if not meta.name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end

    local incomingTerminal = status ~= "pending" and status ~= "traded"
    local localTerminal = drop and drop.status and drop.status ~= "pending" and drop.status ~= "traded"
    local shouldApplyState = updatedAt >= localStamp or (incomingTerminal and not localTerminal)

    if not drop then
        drop = {
            dropInstanceId = dropId,
            lootId = dropId,
            itemGuid = guid,
            itemId = itemId,
            itemName = meta.name or nil,
            itemLink = meta.link,
            itemQuality = quality or meta.quality,
            itemIcon = meta.icon,
            firstHolder = firstHolder,
            currentHolder = currentHolder,
            status = "pending",
            sourceInstance = sourceInstance,
            instanceType = instanceType,
            bossName = bossName,
            lootSource = bossName,
            lootSourceInstance = sourceInstance,
            bossSourceType = bossName and "remote_sync" or nil,
            sessionKey = sessionKey,
            droppedAt = droppedAt,
            updatedAt = updatedAt,
            events = {},
        }
        table.insert(self:Drops(), 1, drop)
        while #self:Drops() > MAX_DROPS do table.remove(self:Drops()) end
        self:AppendEvent(drop, "remote_sync_seen", { actor = sender, at = updatedAt > 0 and updatedAt or time() })
    else
        drop.itemGuid = drop.itemGuid or guid
        drop.itemName = drop.itemName or meta.name or nil
        drop.itemLink = drop.itemLink or meta.link
        drop.itemQuality = drop.itemQuality or quality or meta.quality
        drop.itemIcon = drop.itemIcon or meta.icon
        drop.firstHolder = drop.firstHolder or firstHolder
        drop.sourceInstance = drop.sourceInstance or sourceInstance
        drop.instanceType = drop.instanceType or instanceType
        drop.bossName = drop.bossName or bossName
        drop.lootSource = drop.lootSource or bossName
        drop.lootSourceInstance = drop.lootSourceInstance or sourceInstance
        drop.sessionKey = drop.sessionKey or sessionKey
        if shouldApplyState then
            drop.currentHolder = currentHolder or drop.currentHolder
        end
        if shouldApplyState then
            self:AppendEvent(drop, "remote_sync_updated", { actor = sender, at = updatedAt > 0 and updatedAt or time() })
        end
    end

    if shouldApplyState then
        if status == "pending" or status == "traded" then
            drop.status = status
            drop.finalOwner = finalOwner
        else
            self:ApplyStatusUpdate(drop, status, sender, updatedAt > 0 and updatedAt or time(), true)
            if finalOwner then drop.finalOwner = finalOwner end
        end
    end
    if desiredStamp > 0 then drop.updatedAt = desiredStamp end

    self:MergeDuplicateDrops()
    self:ApplyPendingRemoteStatuses(drop)
    self:NotifyChanged()
end

function Ledger:RecentDropsForSync(requester)
    local rows = {}
    local now = time()
    local requesterIsManager = self:CanAnswerOfficerLootSyncRequest(requester)
    for _, drop in ipairs(self:Drops()) do
        local stamp = self:DropSyncStamp(drop)
        if drop and drop.dropInstanceId and drop.itemId and stamp >= now - LOOT_SYNC_RECENT_SECONDS and self:IsTrackedRaidDrop(drop) then
            if requesterIsManager or self:CanManageLoot() or self:IsLocalPlayerInDrop(drop) then
                table.insert(rows, drop)
            end
        end
    end
    table.sort(rows, function(a, b) return self:DropSyncStamp(a) > self:DropSyncStamp(b) end)
    while #rows > LOOT_SYNC_MAX_ROWS do table.remove(rows) end
    return rows
end

function Ledger:SendRecentLootSync(target)
    if not target or target == "" then return end
    local rows = self:RecentDropsForSync(target)
    if #rows == 0 then return end
    ns:Debug("LootLedger sync sending", #rows, "rows to", target)
    for i, drop in ipairs(rows) do
        if C_Timer then
            C_Timer.After((i - 1) * LOOT_SYNC_SEND_DELAY, function()
                self:SendLootSyncState(drop, target)
            end)
        else
            self:SendLootSyncState(drop, target)
        end
    end
end

function Ledger:ReceiveLootSyncRequest(data, sender)
    sender = fullPlayerName(sender or "")
    if not sender then return end
    self.lootSyncResponseThrottle = self.lootSyncResponseThrottle or {}
    local now = time()
    if self.lootSyncResponseThrottle[sender] and now - self.lootSyncResponseThrottle[sender] < LOOT_SYNC_RESPONSE_THROTTLE then
        ns:Debug("LootLedger sync request throttled", sender)
        return
    end
    self.lootSyncResponseThrottle[sender] = now
    local delay = C_Timer and (2 + math.random(0, 40) / 10) or 0
    if delay > 0 then
        C_Timer.After(delay, function() self:SendRecentLootSync(sender) end)
    else
        self:SendRecentLootSync(sender)
    end
end

function Ledger:RequestRecentLootSync(reason)
    if not IsInGuild or not IsInGuild() then return end
    local now = time()
    if self.lastLootSyncRequestAt and now - self.lastLootSyncRequestAt < LOOT_SYNC_REQUEST_THROTTLE then return end
    self.lastLootSyncRequestAt = now
    self:Broadcast(("LSREQ|%s|%d|%s"):format(cleanAddonField(localPlayer()), now - LOOT_SYNC_RECENT_SECONDS, cleanAddonField(reason or "")), true)
    ns:Debug("LootLedger sync requested", reason or "")
end

function Ledger:QueuePendingRemoteStatus(dropId, status, actor, at, sender)
    if not dropId or dropId == "" then return end
    self.pendingRemoteStatuses = self.pendingRemoteStatuses or {}
    self.pendingRemoteStatuses[dropId] = self.pendingRemoteStatuses[dropId] or {}
    table.insert(self.pendingRemoteStatuses[dropId], {
        status = status,
        actor = actor,
        at = at,
        sender = sender,
        receivedAt = time(),
    })
    ns:Debug("LootLedger queued pending status", dropId, status or "?", sender or "?")
end

function Ledger:ApplyPendingRemoteStatuses(drop)
    if not drop or not drop.dropInstanceId or not self.pendingRemoteStatuses then return end
    local pending = self.pendingRemoteStatuses[drop.dropInstanceId]
    if not pending then return end
    self.pendingRemoteStatuses[drop.dropInstanceId] = nil
    for _, row in ipairs(pending) do
        if self:CanAcceptRemoteStatus(row.sender, drop.dropInstanceId, row.actor) then
            self:ApplyStatusUpdate(drop, row.status, row.actor, row.at or time(), true)
        end
    end
end

function Ledger:CanAcceptRemoteStatus(sender, dropId, actor)
    if self:IsTrustedLootManagerName(sender) then return true end
    local drop = self:FindDropById(dropId)
    if not drop then return false end
    return samePlayer(sender, actor) and samePlayer(drop.currentHolder, sender)
end

function Ledger:ApplyStatusUpdate(dropOrId, status, actor, at, remote, reason, trustedLocal)
    if not remote and not trustedLocal and not self:CanManageLoot() then
        self:PrintThrottled("loot_ownership_permission", "Only the raid leader or guild officers can update loot ownership.", "warning", 15)
        return false
    end
    local drop = type(dropOrId) == "table" and dropOrId or self:FindDropById(dropOrId)
    if not drop then return false end
    at = at or time()
    actor = actor or localPlayer()
    if status == "final_owner_confirmed" then
        drop.status = "final_owner_confirmed"
        drop.finalOwner = drop.currentHolder or drop.finalOwner or drop.firstHolder
        drop.finalizedBy = actor
        drop.finalizedAt = at
        self:AppendEvent(drop, "final_owner_confirmed", { by = actor, owner = drop.finalOwner, remote = remote and true or nil, reason = reason })
    elseif status == "obtained" then
        drop.status = "obtained"
        drop.finalOwner = drop.currentHolder or drop.finalOwner or drop.firstHolder
        drop.finalizedBy = actor
        drop.finalizedAt = at
        self:AppendEvent(drop, "obtained", { by = actor, owner = drop.finalOwner, remote = remote and true or nil, reason = reason })
    elseif status == "disenchanted" then
        drop.status = "disenchanted"
        drop.finalOwner = nil
        drop.disenchantedBy = actor
        drop.disenchantedAt = at
        self:AppendEvent(drop, "disenchanted", { by = actor, remote = remote and true or nil, reason = reason })
    elseif status == "guild_bank" then
        drop.status = "guild_bank"
        drop.currentHolder = "Guild Bank"
        drop.finalOwner = nil
        drop.depositedBy = actor
        drop.depositedAt = at
        self:AppendEvent(drop, "guild_bank", { by = actor, remote = remote and true or nil, reason = reason })
    elseif status == "removed_unknown" then
        drop.status = "removed_unknown"
        drop.finalOwner = nil
        drop.removedBy = actor
        drop.removedAt = at
        self:AppendEvent(drop, "removed_unknown", { by = actor, remote = remote and true or nil, reason = reason })
    else
        return false
    end
    self:NotifyChanged()
    if not remote and (not trustedLocal or status ~= "removed_unknown" or self:CanManageLoot()) then
        self:BroadcastDrop(drop)
        self:BroadcastStatus(drop, drop.status, actor, at)
    end
    return true
end

function Ledger:FinalizeToCurrent(drop)
    return self:ApplyStatusUpdate(drop, "final_owner_confirmed", localPlayer(), time(), false, "manual")
end

function Ledger:MarkDisenchanted(drop, disenchanter, reason, trustedLocal)
    if not drop then return end
    return self:ApplyStatusUpdate(drop, "disenchanted", disenchanter or localPlayer(), time(), false, reason or "manual", trustedLocal)
end

function Ledger:MarkGuildBank(drop, reason, trustedLocal)
    if not drop then return end
    return self:ApplyStatusUpdate(drop, "guild_bank", localPlayer(), time(), false, reason or "manual", trustedLocal)
end

function Ledger:MarkObtained(drop, reason, trustedLocal)
    if not drop then return end
    return self:ApplyStatusUpdate(drop, "obtained", localPlayer(), time(), false, reason or "manual", trustedLocal)
end

function Ledger:MarkRemovedUnknown(drop, reason, trustedLocal)
    if not drop then return end
    return self:ApplyStatusUpdate(drop, "removed_unknown", localPlayer(), time(), false, reason or "manual", trustedLocal)
end

function Ledger:NoteNpcExchangeInteraction()
    self.lastNpcExchangeAt = time()
end

function Ledger:NoteGuildBankOpen()
    self.guildBankOpen = true
    self.lastGuildBankAt = time()
end

function Ledger:NoteGuildBankClosed()
    self.guildBankOpen = false
    self.lastGuildBankAt = time()
    self:ScheduleBagAudit()
end

local function spellNameFromId(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellId)
        if ok then return name end
    end
    if GetSpellInfo then return GetSpellInfo(spellId) end
    return nil
end

function Ledger:OnSpellSucceeded(unit, castGuid, spellId)
    self:CaptureInstanceGuid(castGuid, "cast")
    if unit ~= "player" then return end
    local name = spellNameFromId(spellId)
    self.lastPlayerSpellSucceededAt = time()
    self.lastPlayerSpellSucceededName = name
    if spellId == 13262 or lower(name or "") == "disenchant" then
        self.lastDisenchantAt = time()
        self:ScheduleBagAudit()
    elseif C_Timer then
        C_Timer.After(0.35, function() self:ScheduleBagAudit() end)
    end
end

function Ledger:ExportPayload()
    self:NormalizeKnownRaidSources()
    local ctx = self:CurrentRaidContextSnapshot()
    local payload = {
        version = EXPORT_VERSION,
        exportedAt = utcNow(),
        sessionId = (ctx and ctx.sessionKey) or self.sessionKey,
        raid = ctx and {
            raidName = ctx.raidName,
            instanceType = ctx.instanceType,
            instanceId = ctx.instanceId,
            difficultyId = ctx.difficultyId,
            sessionKey = ctx.sessionKey,
            sessionStartedAt = ctx.sessionStartedAt,
        } or nil,
        drops = {},
    }

    for i = #self:Drops(), 1, -1 do
        local d = self:Drops()[i]
        if not self:IsIgnoredLootItem(d.itemId) then
            table.insert(payload.drops, {
                dropInstanceId = d.dropInstanceId,
                lootId = d.lootId,
                itemGuid = d.itemGuid,
                itemId = d.itemId,
                itemName = d.itemName,
                itemLink = d.itemLink,
                itemQuality = qualityName(d.itemQuality),
                bossName = d.bossName,
                bossAttributionAt = d.bossAttributionAt,
                bossSourceType = d.bossSourceType,
                lootSource = d.lootSource,
                lootSourceInstance = d.lootSourceInstance,
                sourceInstance = d.sourceInstance,
                instanceType = d.instanceType,
                sessionKey = d.sessionKey,
                sessionStartedAt = d.sessionStartedAt,
                sessionReason = d.sessionReason,
                sessionZoneID = d.sessionZoneID,
                entrySerial = d.entrySerial,
                firstHolder = d.firstHolder and splitPlayer(d.firstHolder) or nil,
                currentHolder = d.currentHolder and splitPlayer(d.currentHolder) or nil,
                assignedTo = d.assignedTo and splitPlayer(d.assignedTo) or nil,
                finalOwner = d.finalOwner and splitPlayer(d.finalOwner) or nil,
                depositedBy = d.depositedBy and splitPlayer(d.depositedBy) or nil,
                depositedAt = d.depositedAt,
                status = d.status or "pending",
                events = d.events or {},
            })
        end
    end
    return payload
end

function Ledger:ExportJson()
    local json = ns.raid_assignments_json
    if not json or not json.encode then
        return nil, "JSON encoder is not loaded."
    end
    return json.encode(self:ExportPayload()), "Raid Loot Ledger Export"
end

function Ledger:DeleteSession(sessionKey, dropIds)
    if not self:CanManageLoot() then
        ns:Print("Only the raid leader or guild officers can delete loot sessions.", "warning")
        return 0
    end

    local idSet = {}
    for _, id in ipairs(dropIds or {}) do
        if id then idSet[id] = true end
    end

    local store = self:Store()
    local drops = store and store.drops
    if not drops then return 0 end

    local removed = 0
    for i = #drops, 1, -1 do
        local drop = drops[i]
        local id = drop and (drop.dropInstanceId or drop.lootId)
        if (sessionKey and drop and drop.sessionKey == sessionKey) or (id and idSet[id]) then
            table.remove(drops, i)
            removed = removed + 1
        end
    end

    if store.activeSession and store.activeSession.id == sessionKey then
        store.activeSession = nil
    end
    if removed > 0 then
        self.selectedDropId = nil
        self:NotifyChanged()
    end
    return removed
end

function Ledger:Clear()
    local store = self:Store()
    if store then
        store.drops = {}
        store.activeSession = nil
    end
    self:NotifyChanged()
end

function Ledger:OnInit()
    local store = self:Store()
    if store then
        store.drops = store.drops or {}
        store.eventLimit = store.eventLimit or 1200
        -- (a) Trim a bloated history (e.g. legacy saves that exceeded MAX_DROPS) before
        -- the cleanup passes, so load cost is bounded regardless of saved size.
        -- Newest drops are at the FRONT (index 1); table.remove() with no index removes
        -- from the END (oldest), matching the eviction direction used when recording drops.
        local drops = store.drops
        if #drops > MAX_DROPS then
            local excess = #drops - MAX_DROPS
            for _ = 1, excess do table.remove(drops) end
            ns:Debug("LootLedger trimmed legacy history to cap", MAX_DROPS, "removed", excess)
        end
        -- (b) Defer the cleanup passes off the critical login frame so even the one-time
        -- trim+merge doesn't stutter the loading screen. Tests stub C_Timer away so the
        -- else branch runs inline, keeping existing specs green.
        local self_ = self
        local function runCleanup()
            self_:PruneIgnoredLootDrops()
            self_:PruneDungeonLootDrops()
            self_:NormalizeKnownRaidSources()
            self_:RepairTierTokenTurnIns()
            self_:PruneDisenchantOutputDrops()
            self_:MergeDuplicateDrops()
        end
        if C_Timer then C_Timer.After(0, runCleanup) else runCleanup() end
    end
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix(COMM_PREFIX)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    end
end

function Ledger:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Events = ns:GetModule("Events")
    if not Events then return end
    local guildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if IsInGuild and IsInGuild() and guildRoster then guildRoster() end
    local store = self:Store()
    self.instanceEntrySerial = (store and store.activeSession and store.activeSession.entrySerial) or 1
    self.wasInManagedInstance = self:InstanceContext() ~= nil
    if self.wasInManagedInstance then
        local ctx = self:InstanceContext()
        self.lastInstanceSignature = self:SessionSignature(ctx)
    end
    if C_Timer then
        C_Timer.After(2, function()
            self:ScheduleBagAudit()
            self:ScheduleTradeWindowAudit()
        end)
        C_Timer.After(12, function()
            if self:CanManageLoot() then
                self:RequestRecentLootSync("login")
            end
        end)
    end
    Events:On("CHAT_MSG_LOOT", function(message) self:TrackLootMessage(message) end, "LootLedger")
    Events:On("CHAT_MSG_SYSTEM", function(message) self:OnSystemMessage(message) end, "LootLedger")
    Events:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi) self:OnWorldChanged(isInitialLogin, isReloadingUi) end, "LootLedger")
    Events:On("ZONE_CHANGED_NEW_AREA", function() self:OnWorldChanged(false, false) end, "LootLedger")
    Events:On("COMBAT_LOG_EVENT_UNFILTERED", function() self:OnCombatLogEvent() end, "LootLedger")
    Events:On("BAG_UPDATE_DELAYED", function() self:ScheduleBagAudit() end, "LootLedger")
    Events:On("PLAYER_EQUIPMENT_CHANGED", function() self:ScheduleBagAudit() end, "LootLedger")
    Events:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGuid, spellId) self:OnSpellSucceeded(unit, castGuid, spellId) end, "LootLedger")
    Events:On("GOSSIP_SHOW", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("GUILDBANKFRAME_OPENED", function() self:NoteGuildBankOpen() end, "LootLedger")
    Events:On("GUILDBANKFRAME_CLOSED", function() self:NoteGuildBankClosed() end, "LootLedger")
    Events:On("GUILDBANKBAGSLOTS_CHANGED", function() self:ScheduleBagAudit() end, "LootLedger")
    Events:On("GUILDBANK_ITEM_LOCK_CHANGED", function() self:ScheduleBagAudit() end, "LootLedger")
    Events:On("QUEST_GREETING", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("QUEST_DETAIL", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("QUEST_PROGRESS", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("QUEST_COMPLETE", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("QUEST_FINISHED", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("QUEST_TURNED_IN", function() self:NoteNpcExchangeInteraction() end, "LootLedger")
    Events:On("ENCOUNTER_END", function(_, name, _, _, success)
        if success == 1 then self:NoteBossKill(name) end
    end, "LootLedger")
    Events:On("BOSS_KILL", function(_, name) self:NoteBossKill(name) end, "LootLedger")
    Events:On("TRADE_SHOW", function()
        self.tradeTarget = self:TradeTargetName()
        self.tradeSnapshot = nil
        self.tradeBagSnapshot = self:TrackedBagSnapshot()
        self.tradeOpenedAt = time()
        self.tradeComplete = false
        self.tradeCommitted = false
        ns:Debug("LootLedger trade opened", self.tradeTarget or "unknown")
        self:ScheduleTradeSnapshot()
    end, "LootLedger")
    Events:On("TRADE_PLAYER_ITEM_CHANGED", function() self:ScheduleTradeSnapshot() end, "LootLedger")
    Events:On("TRADE_TARGET_ITEM_CHANGED", function() self:ScheduleTradeSnapshot() end, "LootLedger")
    Events:On("TRADE_ACCEPT_UPDATE", function(playerAccepted, targetAccepted)
        self:ScheduleTradeSnapshot()
    end, "LootLedger")
    Events:On("UI_INFO_MESSAGE", function(_, message)
        if message == ERR_TRADE_COMPLETE then
            self:CompleteTradeFromSystemMessage()
        end
    end, "LootLedger")
    Events:On("TRADE_CLOSED", function()
        local target = self.tradeTarget
        local frameSnapshot = self.tradeSnapshot
        local bagBefore = self.tradeBagSnapshot
        local tradeCompleted = self.tradeComplete
        local tradeAt = self.tradeOpenedAt or time()
        ns:Debug("LootLedger trade closed", target or "unknown", "complete", tradeCompleted and "yes" or "no")
        if self.tradeComplete then self:CommitTrade() end
        if tradeCompleted and target and bagBefore and C_Timer then
            C_Timer.After(0.25, function() self:CommitTradeBagDiff(target, bagBefore, tradeAt) end)
            C_Timer.After(0.90, function() self:CommitTradeBagDiff(target, bagBefore, tradeAt) end)
        elseif tradeCompleted and target and bagBefore then
            self:CommitTradeBagDiff(target, bagBefore, tradeAt)
        elseif not tradeCompleted and target and (frameSnapshot or bagBefore) then
            self.lastClosedTrade = {
                target = target,
                frameSnapshot = frameSnapshot,
                bagSnapshot = bagBefore,
                openedAt = tradeAt,
                closedAt = time(),
            }
            ns:Debug("LootLedger cached closed trade awaiting complete", target)
        end
        self.tradeTarget = nil
        self.tradeSnapshot = nil
        self.tradeBagSnapshot = nil
        self.tradeOpenedAt = nil
        self.tradeComplete = false
        self.tradeCommitted = false
    end, "LootLedger")
    Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
        self:OnAddonMessage(prefix, message, channel, sender)
    end, "LootLedger")
    Events:On("CHAT_MSG_RAID", function(message, sender) self:TrackGargulMessage(message, sender) end, "LootLedger")
    Events:On("CHAT_MSG_RAID_LEADER", function(message, sender) self:TrackGargulMessage(message, sender) end, "LootLedger")
    Events:On("CHAT_MSG_PARTY", function(message, sender) self:TrackGargulMessage(message, sender) end, "LootLedger")
    Events:On("CHAT_MSG_PARTY_LEADER", function(message, sender) self:TrackGargulMessage(message, sender) end, "LootLedger")

    local slash = ns:GetModule("Slash")
    if slash then
        slash:Register("lootexport", function()
            local text, desc = self:ExportJson()
            if not text then ns:Print(desc or "Raid loot export failed.", "error"); return end
            local panel = self.panel
            if panel and panel.ShowExport then panel:ShowExport(text, desc) else ns:Print(text) end
        end)
    end
end
