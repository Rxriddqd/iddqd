local ADDON, ns = ...
-- LootDistDetect (IO): officer-received detection, auto-add, trade auto-open/auto-place,
-- traded flip, and reminders. Every WoW global is guarded so the file loads (and no-ops)
-- on any client (TBC + Era). Trade-window APIs return 0 on Era (no error).
local Detect = ns:NewModule("LootDistDetect")

local function Store() return ns:GetModule("LootDistStore") end
local function Sync() return ns:GetModule("LootDistSync") end
local function Council() return ns:GetModule("Council") end
local function Players() return ns.GetModule and ns:GetModule("Players") or nil end
local function now() return (time and time()) or 0 end

local function refreshPanel()
    local p = ns:GetModule("LootActivePanel")
    if p and p.Refresh then p:Refresh() end
end

local function refreshPopupEntry(id)
    local p = ns:GetModule("LootDistPopup")
    if p and p.OnEntryAdded then p:OnEntryAdded(id) end
end

--------------------------------------------------------------------------------
-- Helpers (WoW globals guarded + pcall'd)
--------------------------------------------------------------------------------

-- Strip "-Realm" suffix and trim; case preserved for display.
local function canonName(name)
    local players = Players()
    if players and players.ShortName then return players:ShortName(name) end
    name = tostring(name or "")
    name = name:match("^%s*(.-)%s*$") or name        -- trim
    return name:match("^([^-]+)") or name            -- drop -Realm
end

local function localPlayer()
    if not UnitName then return nil end
    return canonName(UnitName("player"))
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function bagSlotCount(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) end
    return 0
end

local function containerItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID, info and info.hyperlink
    end
    if GetContainerItemInfo then
        local _, _, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        return itemID, link
    end
    return nil, nil
end

local function itemGuidFromBagSlot(bag, slot)
    if not C_Item or not C_Item.GetItemGUID then return nil end
    if not ItemLocation or not ItemLocation.CreateFromBagAndSlot then return nil end
    local ok, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if not ok or not loc then return nil end
    if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    local okg, guid = pcall(C_Item.GetItemGUID, loc)
    return okg and guid or nil
end

-- Trade-window remaining seconds for a bag slot. Era has no such API -> returns 0.
local function tradeTimeRemaining(bag, slot)
    if C_Container and C_Container.GetContainerItemTradeTimeRemaining then
        local ok, secs = pcall(C_Container.GetContainerItemTradeTimeRemaining, bag, slot)
        if ok then return tonumber(secs) or 0 end
    end
    if GetContainerItemTradeTimeRemaining then
        local ok, secs = pcall(GetContainerItemTradeTimeRemaining, bag, slot)
        if ok then return tonumber(secs) or 0 end
    end
    return 0
end

-- Place an item into the OPEN trade window (Gargul's proven mechanic).
local function useContainerItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        pcall(C_Container.UseContainerItem, bag, slot)
    elseif UseContainerItem then
        pcall(UseContainerItem, bag, slot)
    end
end

-- Read the current trade frame recipient name (canon).
local function tradeTargetName()
    if _G and _G.TradeFrameRecipientNameText and _G.TradeFrameRecipientNameText.GetText then
        local t = _G.TradeFrameRecipientNameText:GetText()
        if t and t ~= "" then return canonName(t) end
    end
    if UnitExists and UnitExists("NPC") and UnitName then
        return canonName(UnitName("NPC"))
    end
    if GetUnitName then return canonName(GetUnitName("npc")) end
    return nil
end

-- Find an item in bags 0..4. Prefer an exact GUID match; else first slot whose itemId
-- matches. Returns bag, slot or nil.
local function findItemInBags(itemGUID, itemId)
    local fallbackBag, fallbackSlot
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local id = containerItemID(bag, slot)
            if id then
                if itemGUID and itemGuidFromBagSlot(bag, slot) == itemGUID then
                    return bag, slot
                end
                if itemId and id == itemId and not fallbackBag then
                    fallbackBag, fallbackSlot = bag, slot
                end
            end
        end
    end
    if fallbackBag then return fallbackBag, fallbackSlot end
    return nil
end

--------------------------------------------------------------------------------
-- Permission + assignment
--------------------------------------------------------------------------------

-- Low-level group-role primitive: is the local player the raid leader or a raid assist?
function Detect:IsRaidLeaderOrAssist()
    return (UnitIsGroupLeader and UnitIsGroupLeader("player"))
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        or false
end

local VALID_DISTRIBUTE_POLICIES = {
    leader = true,
    assist = true,
    guild = true,
    assist_and_guild = true,
    assist_or_guild = true,
}

local function normalizeDistributePolicy(policy)
    policy = tostring(policy or "assist")
    if VALID_DISTRIBUTE_POLICIES[policy] then return policy end
    return "assist"
end

local function guildRankThreshold(value)
    local n = math.floor(tonumber(value) or 2)
    if n < 0 then n = 0 end
    if n > 9 then n = 9 end
    return n
end

-- The raid-wide loot-distribution policy. Set by the raid leader and broadcast to the group
-- (LDPERM1) so everyone enforces the same rule.
function Detect:DistributePolicy()
    local db = ns:GetModule("DB"); db = db and db.db
    local s = db and db.settings and db.settings.lootSettings
    return normalizeDistributePolicy(s and s.distributePermission)
end

function Detect:DistributeGuildRank()
    local db = ns:GetModule("DB"); db = db and db.db
    local s = db and db.settings and db.settings.lootSettings
    return guildRankThreshold(s and s.distributeGuildRank)
end

function Detect:SetDistributePolicy(policy, guildRank)
    policy = normalizeDistributePolicy(policy)
    local db = ns:GetModule("DB"); db = db and db.db
    if not db then return end
    db.settings = db.settings or {}
    db.settings.lootSettings = db.settings.lootSettings or {}
    db.settings.lootSettings.distributePermission = policy
    if guildRank ~= nil then db.settings.lootSettings.distributeGuildRank = guildRankThreshold(guildRank) end
end

-- Is the local player the raid LEADER specifically?
function Detect:IsRaidLeader()
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) and true or false
end

function Detect:IsRaidAssistant()
    return (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) and true or false
end

function Detect:LocalGuildRankIndex()
    local me = localPlayer()
    if not me then return nil end
    if GetGuildInfo then
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex ~= nil then return tonumber(rankIndex) end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name and canonName(name):lower() == me:lower() then return tonumber(rankIndex) end
        end
    end
    return nil
end

function Detect:MeetsDistributeGuildRank()
    local rankIndex = self:LocalGuildRankIndex()
    return rankIndex ~= nil and rankIndex <= self:DistributeGuildRank()
end

-- AUTHORITATIVE loot-permission check. Every loot-distribution gate (Ask, Award, manual add,
-- auto-add, reminders, and the panel's officer-button enable) funnels through here, so the
-- rule for "who can distribute loot" lives in exactly one place. Honors the raid leader's
-- DistributePolicy.
--
-- NOTE: test mode (/iddqd loottest) deliberately does NOT bypass this. Test mode relaxes
-- WHAT/WHERE (greens flow, auto-add solo) and the popup gates so a 1-2 character setup can
-- exercise the flow — but WHO may distribute stays real, so the permission itself is testable.
-- (When truly solo you are leader of your own group, so this still passes for you.)
function Detect:CanDistributeLoot()
    local policy = self:DistributePolicy()
    if policy == "leader" then
        return self:IsRaidLeader()
    end
    if policy == "assist" then return self:IsRaidLeaderOrAssist() end

    local leader = self:IsRaidLeader()
    local assist = self:IsRaidAssistant()
    local guild = self:MeetsDistributeGuildRank()
    if policy == "guild" then return leader or guild end
    if policy == "assist_and_guild" then return leader or (assist and guild) end
    if policy == "assist_or_guild" then return leader or assist or guild end
    return self:IsRaidLeaderOrAssist()
end

-- True if `itemId` is a known RAID drop (boss, trash, or recipe) from the baked TBC raid loot
-- table (ns.raidLootSources, ~839 items across all TBC raids + world bosses). Used to keep the
-- Loot page to actual raid loot — a random dungeon/world green is NOT in this table and won't
-- auto-add. Returns true if the table is missing entirely (fail-open, so a data-load problem
-- can't silently block all loot).
function Detect:IsRaidDrop(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end
    local t = ns.raidLootSources and ns.raidLootSources.byItemId
    if not t then return true end          -- table absent: don't block everything
    return t[itemId] ~= nil
end

-- True if any character the council assigned this item to is currently in the raid roster.
function Detect:AssignedInRaid(itemId)
    local c = Council()
    if not c or not c.AssignmentsForItem then return false end
    local rows = c:AssignmentsForItem(itemId)
    if not rows or #rows == 0 then return false end

    -- Build a set of raid short-names (lowercased).
    local inRaid = {}
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if GetRaidRosterInfo then
        for i = 1, count do
            local ok, name = pcall(GetRaidRosterInfo, i)
            if ok and name then inRaid[canonName(name):lower()] = true end
        end
    end

    for _, row in ipairs(rows) do
        local ch = row and row.character
        if ch and inRaid[canonName(ch):lower()] then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Auto-add / manual add
--------------------------------------------------------------------------------

function Detect:TryAutoAdd(itemId, itemLink, itemGUID)
    local store = Store()
    if not store or not itemId then return end

    local id = store:ListId(itemGUID, itemId, localPlayer(), now())
    if not id then return end
    local existing = store:Entries()[id]

    local ctx = {
        -- Auto-add is gated by the same authoritative permission as Ask/Award: the loot list
        -- only populates for someone who can distribute loot. (Test mode makes this pass.)
        isLeaderAssist = self:CanDistributeLoot(),
        assignedInRaid = self:AssignedInRaid(itemId),
        alreadyPresent = existing ~= nil,
        alreadyAwarded = (existing and existing.award ~= nil) or false,
    }
    if not store:ShouldAutoAdd(ctx) then return end

    local name, quality, icon
    local itemType, equipLoc
    if GetItemInfo then
        local n, _, q, _, _, t, _, _, eq, ic = GetItemInfo(itemLink or itemId)
        name, quality, icon, itemType, equipLoc = n, q, ic, t, eq
    end

    -- Info not cached yet -> request it and skip this pass (avoids "Item ?" placeholder
    -- entries). It will be re-evaluated on a later loot/bag event once the cache fills.
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemId) end
        return
    end

    -- Relevance filter: only EQUIPPABLE gear of Uncommon (>=2) or better. Drops trade goods
    -- (Wool Cloth), consumables, quest items, junk. Applies in test mode too — test mode
    -- relaxes WHO/WHERE, not WHAT (we still only want gear in the list).
    local equippable = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" and equipLoc ~= "INVTYPE_BAG"
    if not equippable or (tonumber(quality) or 0) < 2 then return end

    -- Raid-loot whitelist: only items that can actually drop in a TBC raid (boss, trash, or
    -- recipe, per ns.raidLootSources) auto-add — so dungeon/world greens never land here. Test
    -- mode bypasses this so a 1-2 character setup can test with dungeon drops (it relaxes WHAT,
    -- the same way it relaxes WHERE).
    if not ns.LOOT_DIST_TEST and not self:IsRaidDrop(itemId) then return end

    -- BoP trade-window end time (Era-inert -> nil).
    local tradeWindowEndsAt
    local bag, slot = findItemInBags(itemGUID, itemId)
    if bag then
        local secs = tradeTimeRemaining(bag, slot)
        if secs and secs > 0 then tradeWindowEndsAt = now() + secs end
    end

    store:EnsureEntry(id, {
        itemId = itemId,
        itemLink = itemLink,
        itemName = name,
        quality = quality,
        icon = icon,
        holder = localPlayer(),
        addedBy = localPlayer(),
        source = "auto",
        tradeWindowEndsAt = tradeWindowEndsAt,
    })

    local s = Sync()
    if s and s.BroadcastEntry then s:BroadcastEntry(id) end
    refreshPopupEntry(id)
    refreshPanel()
end

-- Extract every item hyperlink from a string. Shift-clicking several items into one box
-- concatenates their |Hitem:...|h[Name]|h|r escapes; this returns each as its own link so
-- they become separate entries (a plain "item:12345" with no escape is returned as-is).
local function itemLinksFrom(text)
    local links = {}
    if type(text) ~= "string" then return links end
    -- Full hyperlinks first: |c...|Hitem:...|h[Name]|h|r
    for link in text:gmatch("|%x+|Hitem:.-|h.-|h|r") do links[#links + 1] = link end
    if #links == 0 then
        -- Bare item references with no display escape (e.g. pasted "item:12345").
        for bare in text:gmatch("item:%d[%d:%-]*") do links[#links + 1] = bare end
    end
    return links
end

-- Add ONE resolved item link as a manual entry. Returns the entry id or nil.
function Detect:AddOneLink(itemLink)
    local store = Store()
    if not store or type(itemLink) ~= "string" then return nil end

    local itemId = itemIdFromLink(itemLink)
    if not itemId then return nil end

    -- Manual add dedups to ONE row per item (by item id, day-bucketed). Adding the SAME item again
    -- BUMPS its quantity ("xN") instead of making a second row — so one token row can be awarded to
    -- N different players. A stable per-item id (no time bucket) keeps repeated adds on one entry.
    local id = ("m:%s:%d"):format((localPlayer() or "?"):lower(), itemId)

    -- A manual add is an INTENTIONAL officer action — clear any prior tombstone for this id.
    if store.ClearTombstone then store:ClearTombstone(id) end

    -- If the entry already exists, this is a duplicate add -> bump quantity and re-broadcast.
    if store:Entries()[id] then
        store:IncrementQuantity(id)
        local s = Sync()
        if s and s.BroadcastEntry then s:BroadcastEntry(id) end
        refreshPopupEntry(id)
        return id
    end

    local name, quality, icon
    if GetItemInfo then
        local n, _, q, _, _, _, _, _, _, ic = GetItemInfo(itemLink or itemId)
        name, quality, icon = n, q, ic
    end
    -- Manual add is intentional; never store a nameless entry. Fall back to the link itself.
    if not name then name = itemLink end

    -- Trade-window time if a copy is in our bags (Era-inert -> nil).
    local tradeWindowEndsAt
    local bag, slot = findItemInBags(nil, itemId)
    if bag then
        local secs = tradeTimeRemaining(bag, slot)
        if secs and secs > 0 then tradeWindowEndsAt = now() + secs end
    end

    store:EnsureEntry(id, {
        itemId = itemId,
        itemLink = itemLink,
        itemName = name,
        quality = quality,
        icon = icon,
        holder = localPlayer(),
        addedBy = localPlayer(),
        source = "manual",
        tradeWindowEndsAt = tradeWindowEndsAt,
    })

    local s = Sync()
    if s and s.BroadcastEntry then s:BroadcastEntry(id) end
    refreshPopupEntry(id)
    return id
end

-- Officer-only intentional add (panel "Add Item"). No assigned-in-raid exclusion. Handles
-- one OR several item links pasted/shift-clicked into the box (each becomes its own entry).
function Detect:ManualAdd(text)
    if not self:CanDistributeLoot() then return nil end
    if type(text) ~= "string" then return nil end

    local links = itemLinksFrom(text)
    -- No recognisable hyperlink? Fall back to treating the whole string as one link (covers
    -- a lone "item:12345" that the patterns above still catch, and keeps prior behaviour).
    if #links == 0 then links = { text } end

    local lastId, added = nil, 0
    for _, link in ipairs(links) do
        local id = self:AddOneLink(link)
        if id then lastId = id; added = added + 1 end
    end

    if added > 0 then refreshPanel() end
    return lastId
end

--------------------------------------------------------------------------------
-- Award + trade open/place
--------------------------------------------------------------------------------

-- Best-effort class file for a player name: prefer their recorded response, else the
-- raid/party roster, else (if it's us) our own class.
function Detect:WinnerClass(e, winner)
    local key = canonName(winner):lower()
    -- 1. From a response they submitted on this item.
    for _, r in pairs(e and e.responses or {}) do
        if r.player and canonName(r.player):lower() == key and r.classFile then
            return r.classFile
        end
    end
    -- 2. Ourselves. (Select the 2nd return explicitly — `local _, c = X and X()` truncates
    -- via `and` and yields nil.)
    if winner and canonName(winner):lower() == (localPlayer() or ""):lower() then
        if UnitClass then local _, classFile = UnitClass("player"); if classFile then return classFile end end
    end
    -- 3. Raid/party roster scan.
    if GetNumGroupMembers then
        local n = GetNumGroupMembers() or 0
        if IsInRaid and IsInRaid() and GetRaidRosterInfo then
            for i = 1, n do
                -- GetRaidRosterInfo: name(1), rank(2), subgroup(3), level(4), class(5),
                -- fileName/classFile(6), ... — the English class file is the 6th return.
                local ok, name, _, _, _, _, classFile = pcall(GetRaidRosterInfo, i)
                if ok and name and canonName(name):lower() == key and classFile then return classFile end
            end
        elseif UnitClass then
            for i = 1, n do
                local unit = "party" .. i
                if UnitExists and UnitExists(unit) and UnitName and canonName(UnitName(unit)):lower() == key then
                    local _, classFile = UnitClass(unit)
                    if classFile then return classFile end
                end
            end
        end
    end
    return nil
end

function Detect:Award(id, winner)
    if not self:CanDistributeLoot() then return end
    local store = Store()
    local e = store and store:Entries()[id]
    if not e or not winner then return end

    local winnerClass = self:WinnerClass(e, winner)
    store:SetAward(id, winner, localPlayer(), now(), winnerClass)

    -- Smart "Traded": awarding an item to YOURSELF needs no trade (it's already in your
    -- bags, and you keep it), so mark it traded immediately. The user asked for this even
    -- though "self-traded" is a slight abuse of the term.
    local me = localPlayer()
    if me and canonName(winner):lower() == me:lower() then
        store:SetTraded(id, true)
    end

    local s = Sync()
    if s and s.BroadcastEntry then s:BroadcastEntry(id) end

    -- Announce (single source of truth: council announce channel, else group chat). The
    -- council path adds the [iddqd] tag itself; the direct fallback must add it here.
    local msg = ("Awarded %s to %s."):format(e.itemLink or e.itemName or "item", winner)
    local c = Council()
    if c and c.SendToAnnounceChannel then
        c:SendToAnnounceChannel(msg)
    elseif SendChatMessage then
        pcall(SendChatMessage, "[iddqd] " .. msg, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    end

    -- Record the outstanding award keyed by the winner's short name (lowercased).
    self.outstanding = self.outstanding or {}
    self.outstanding[canonName(winner):lower()] = {
        id = id, itemId = e.itemId, itemLink = e.itemLink,
    }

    -- Attempt to auto-open the trade (Gargul calls InitiateTrade directly; out-of-range
    -- just no-ops).
    if InitiateTrade then pcall(InitiateTrade, winner) end
    refreshPanel()
end

function Detect:OnTradeShow()
    local target = tradeTargetName()
    if not target then return end
    local key = canonName(target):lower()
    local pending = self.outstanding and self.outstanding[key]
    if not pending then return end
    -- Defer slightly so the trade window is fully open before placing.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() self:PlacePending(key) end)
    else
        self:PlacePending(key)
    end
end

function Detect:PlacePending(key)
    local pending = self.outstanding and self.outstanding[key]
    if not pending then return end
    -- Only place while a trade frame is open (if TradeFrame absent, just attempt).
    if _G and _G.TradeFrame and _G.TradeFrame.IsShown and not _G.TradeFrame:IsShown() then return end
    -- We don't persist the awarded item's GUID; match by itemId.
    local bag, slot = findItemInBags(nil, pending.itemId)
    if bag then useContainerItem(bag, slot) end
    -- Do NOT clear outstanding here; only on a completed trade.
end

function Detect:OnTradeComplete()
    local key = self.lastTradeTarget and canonName(self.lastTradeTarget):lower()
    local pending = key and self.outstanding and self.outstanding[key]
    if not pending then return end
    local store = Store()
    if store then store:SetTraded(pending.id, true) end
    local s = Sync()
    if s and s.BroadcastEntry then s:BroadcastEntry(pending.id) end
    self.outstanding[key] = nil
    refreshPanel()
end

--------------------------------------------------------------------------------
-- Reminders
--------------------------------------------------------------------------------

function Detect:Remind(id)
    if not self:CanDistributeLoot() then return end
    local store = Store()
    local e = store and store:Entries()[id]
    if not e or not e.award then return end

    local mins
    if e.tradeWindowEndsAt then
        mins = math.max(0, math.floor((e.tradeWindowEndsAt - now()) / 60))
    end
    local s = Sync()
    if s and s.Reminder then s:Reminder(e.award.winner, e.itemLink, mins) end
end

--------------------------------------------------------------------------------
-- Removal (convergent: tombstone locally + broadcast so it clears everywhere)
--------------------------------------------------------------------------------

-- Officer removes one entry. Tombstones it locally and broadcasts the delete so every other
-- client (officers' Loot tabs + raiders' popups) drops it too and can't re-create it.
function Detect:Remove(id)
    if not self:CanDistributeLoot() or not id then return false end
    local store = Store(); if not store then return false end
    local at = now()
    store:RemoveEntry(id, at)
    local s = Sync()
    if s and s.BroadcastRemove then s:BroadcastRemove(id, at) end
    refreshPanel()
    return true
end

-- Remove ONE copy: decrement quantity (x2 -> x1). At the last copy, delete the whole entry.
-- Also pops the most recent award if we're decrementing below the award count. Broadcasts either
-- the updated entry (still has copies) or the delete (last copy gone).
function Detect:RemoveOne(id)
    if not self:CanDistributeLoot() or not id then return false end
    local store = Store(); if not store then return false end
    local e = store:Entries()[id]
    if not e then return false end
    local qty = tonumber(e.quantity) or 1
    if qty <= 1 then
        return self:Remove(id)   -- last copy -> full delete + tombstone
    end
    store:DecrementQuantity(id)
    -- If we now have more awards than copies, drop the newest award.
    if store.AwardCount and store.PopAward and store:AwardCount(id) > (tonumber(e.quantity) or 1) then
        store:PopAward(id)
    end
    local s = Sync()
    if s and s.BroadcastEntry then s:BroadcastEntry(id) end
    refreshPanel()
    return true
end

-- True when the player is in no party/raid at all.
function Detect:NotInGroup()
    local inGroup = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0)
    return not inGroup
end

-- Local-only wipe of the loot-distribution list when the player leaves the group. The list
-- is raid-scoped shared state; once you're out it no longer applies. This does NOT broadcast
-- (you're no longer in the channel) and does NOT tombstone (others keep their own copies);
-- it just clears YOUR view. On rejoin, an officer's join-rebroadcast repopulates it.
function Detect:OnLeftGroup()
    local store = Store(); if not store then return end
    local r = store:Get(); if not r then return end
    r.entries = {}
    self.outstanding = {}            -- drop any pending auto-place from the old raid
    refreshPanel()
end

-- Clear any stale loot if we're no longer grouped. Used on login/reload/reconnect, where the
-- "you left the group" GROUP_ROSTER_UPDATE never fires for us (we come back already out of the
-- group), so entries added in a previous session would otherwise stay stuck in the Loot tab.
function Detect:ClearLootIfUngrouped()
    if self:NotInGroup() then self:OnLeftGroup() end
end

--------------------------------------------------------------------------------
-- Self-loot parse (model on Council:OnChatLoot)
--------------------------------------------------------------------------------

function Detect:OnChatLoot(message)
    if type(message) ~= "string" then return end
    local selfPat = _G and _G.LOOT_ITEM_SELF
    local selfMulti = _G and _G.LOOT_ITEM_SELF_MULTIPLE
    local link
    for _, fmt in ipairs({ selfMulti, selfPat }) do
        if fmt then
            local pat = "^" .. fmt:gsub("%%s", "(.+)"):gsub("%%d", "%%d+") .. "$"
            local cap = message:match(pat)
            if cap then link = cap; break end
        end
    end
    if not link then link = message:match("^You receive loot: (.+)%.?$") end
    if not link then return end
    self:TryAutoAdd(itemIdFromLink(link), link, nil)
end

--------------------------------------------------------------------------------
-- OnEnable (idempotent)
--------------------------------------------------------------------------------

function Detect:OnEnable()
    if self._enabled then return end
    local e = ns:GetModule("Events")
    if not e then return end
    self._enabled = true

    -- Self-received loot -> auto-add.
    e:On("CHAT_MSG_LOOT", function(message) self:OnChatLoot(message) end, "LootDistDetect")

    -- Trade window opened -> remember partner + attempt auto-place.
    e:On("TRADE_SHOW", function()
        self.lastTradeTarget = tradeTargetName()
        self:OnTradeShow()
    end, "LootDistDetect")

    -- Trade completion. ERR_TRADE_COMPLETE may arrive before OR after the trade close, so
    -- treat completion independently (lesson from Tracker).
    e:On("UI_INFO_MESSAGE", function(...)
        if _G and select(2, ...) == _G.ERR_TRADE_COMPLETE then self:OnTradeComplete() end
    end, "LootDistDetect")
    e:On("CHAT_MSG_SYSTEM", function(message)
        if _G and message == _G.ERR_TRADE_COMPLETE then self:OnTradeComplete() end
    end, "LootDistDetect")

    -- Leaving the group clears the (raid-scoped) loot list from this client's Loot tab.
    e:On("GROUP_ROSTER_UPDATE", function()
        if self:NotInGroup() then self:OnLeftGroup() end
    end, "LootDistDetect")

    -- Login / reload / reconnect: GROUP_ROSTER_UPDATE for "you left" never fires when you come
    -- back already out of the group, so loot added in a prior session can stay stuck. Re-check
    -- on entering the world. Defer briefly — group APIs can report stale/empty values for a
    -- moment right after login before the roster finishes loading.
    e:On("PLAYER_ENTERING_WORLD", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() self:ClearLootIfUngrouped() end)
        else
            self:ClearLootIfUngrouped()
        end
    end, "LootDistDetect")
end

return Detect
