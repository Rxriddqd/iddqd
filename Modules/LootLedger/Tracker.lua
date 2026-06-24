local ADDON, ns = ...

-- LootTracker: IO module that detects loot-lifecycle events and records them into
-- the LootStore event log. All WoW-API access is inside functions (never at load),
-- so the file loadfile's cleanly with only the Store + a couple of ns stubs present.
local Tracker = ns:NewModule("LootTracker")

local function Store() return ns:GetModule("LootStore") end
local function Sync() return ns:GetModule("LootSync") end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function shortPlayerName(name)
    local players = Players()
    if players and players.ShortName then return players:ShortName(name) end
    name = tostring(name or "")
    name = name:match("^%s*(.-)%s*$") or name
    return name:match("^([^-]+)") or name
end

local function now()
    if ns.LootStoreNow then return ns.LootStoreNow() end
    return (time and time()) or (os and os.time and os.time()) or 0
end

local DISENCHANT_SPELL_ID = 13262
local ROLL_CAPTURE_RETRIES = 6
local ROLL_CAPTURE_RETRY_DELAY = 0.20

-- Fixed timestamp for 'looted' events. The looter + dropID already fully identify a loot, so
-- the timestamp adds nothing — and using wall-clock here would let two trackers (or the
-- window vs. chat vs. self-attribute paths) land in different 5s buckets and create duplicate
-- looted events. A constant makes the event key identical everywhere -> guaranteed dedup.
-- (looted is always the earliest event for a drop; a fixed low value keeps fold ordering.)
local LOOTED_AT = 1

--------------------------------------------------------------------------------
-- Pure helpers (defined at load; MUST NOT touch any WoW global)
--------------------------------------------------------------------------------

-- Strip a "-Realm" suffix and lowercase. Pure.
local function normalizeName(name)
    return shortPlayerName(name):lower()
end

-- Pure + unit-tested. Given a list of raid names (possibly "Name-Realm") and a
-- guildSet { [normalizedName]=true }, return guildCount, raidSize.
function Tracker:GuildRatioFromRosters(raidNames, guildSet)
    raidNames = raidNames or {}
    guildSet = guildSet or {}
    local guildCount = 0
    local raidSize = #raidNames
    for i = 1, raidSize do
        local norm = normalizeName(raidNames[i])
        if norm ~= "" and guildSet[norm] then
            guildCount = guildCount + 1
        end
    end
    return guildCount, raidSize
end

--------------------------------------------------------------------------------
-- IO helpers (WoW globals guarded; only ever called at runtime)
--------------------------------------------------------------------------------

-- Canonical player name used for EVERY actor/target stored in the event log. Strips any
-- "-Realm" suffix and trims, so the same player is spelled identically no matter which
-- code path (UnitName, loot-chat parse, trade target) produced the name — otherwise the
-- event log fragments across clients (e.g. "Cylo" vs "Cylo-Spineshatter") and dedup fails.
-- Case is preserved for display.
local function canonName(name)
    return shortPlayerName(name)
end

local function samePlayer(a, b)
    a = normalizeName(a)
    b = normalizeName(b)
    return a ~= "" and b ~= "" and a == b
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

local function containerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
    if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
    return nil
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

local function itemGuidFromEquipmentSlot(slot)
    if not C_Item or not C_Item.GetItemGUID then return nil end
    if not ItemLocation or not ItemLocation.CreateFromEquipmentSlot then return nil end
    local ok, loc = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
    if not ok or not loc then return nil end
    if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    local okg, guid = pcall(C_Item.GetItemGUID, loc)
    return okg and guid or nil
end

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

-- Tooltip scanner to read per-instance bind state from a bag slot. A looted item that is
-- soulbound (BoP, now bound to us) with no trade window has reached the end of its tradeable
-- life -> finalize it. Returns true if the bag slot's item shows a soulbound/BoP line.
local function isSoulbound(bag, slot)
    if not CreateFrame or not bag or not slot then return false end
    local tip = _G.IDDQDLootBindScanTooltip
    if not tip then
        tip = CreateFrame("GameTooltip", "IDDQDLootBindScanTooltip", UIParent, "GameTooltipTemplate")
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    local ok = pcall(function() tip:SetBagItem(bag, slot) end)
    if not ok then return false end
    local soulbound = (_G.ITEM_SOULBOUND or "Soulbound"):lower()
    local bop = (_G.ITEM_BIND_ON_PICKUP or "Binds when picked up"):lower()
    for i = 1, tip:NumLines() do
        local line = _G["IDDQDLootBindScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            local l = text:lower()
            if l:find(soulbound, 1, true) then return true end
            -- "Binds when picked up" alone isn't proof it's bound yet, but for a looted item
            -- sitting in our bags with no trade window it effectively is — treat as bound.
            if l:find(bop, 1, true) then return true end
        end
    end
    return false
end

local function itemInfoFor(linkOrId)
    if not GetItemInfo or not linkOrId then return nil, nil, nil, nil end
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(linkOrId)
    return name, quality, icon
end

-- What's worth recording in the loot ledger: only Rare (blue) and Epic (purple) gear. The loot
-- table whitelist also contains quest items (e.g. "Coilfang Armaments", "The Heart of
-- Quagmirran") and greens/whites, which aren't loot worth tracking — so we additionally require:
--   * quality >= Rare (3), AND
--   * NOT a Quest-class item (GetItemInfo classID 12 / itemType "Quest").
-- Returns true when uncached (so a not-yet-loaded blue/epic isn't silently dropped; a later
-- pass re-checks once GetItemInfo resolves).
local LEDGER_MIN_QUALITY = 3   -- Rare and above only
-- Pull a numeric itemID out of a link or id (for the blacklist check, which is id-based).
local function blItemId(linkOrId)
    if type(linkOrId) == "number" then return linkOrId end
    local s = tostring(linkOrId or "")
    return tonumber(s:match("item:(%d+)")) or tonumber(s)
end
local function shouldTrack(linkOrId)
    -- Explicit blacklist FIRST — heuristic-independent and authoritative. Kael'thas conjured
    -- legendaries + boss quest items (Vashj's Vial Remnant) are never recorded, regardless of
    -- their quality/class. (See ns.lootBlacklist in RaidLootSources.lua.)
    local id = blItemId(linkOrId)
    if id and ns.lootBlacklist and ns.lootBlacklist[id] then return false end
    if not GetItemInfo or not linkOrId then return true end
    -- GetItemInfo: name, link, quality, ..., itemType(6), itemSubType(7), ..., classID(12)
    local _, _, quality, _, _, itemType, _, _, _, _, _, classID = GetItemInfo(linkOrId)
    if quality == nil then return true end                 -- uncached: don't drop on a guess
    if ns.LOOT_DIST_TEST then
        if classID == 12 or itemType == "Quest" then return false end
        return quality >= 2
    end
    if quality < LEDGER_MIN_QUALITY then return false end   -- exclude poor/common/uncommon
    if classID == 12 or itemType == "Quest" then return false end   -- exclude quest items
    return true
end

local function isRecipeItem(linkOrId)
    if not GetItemInfo or not linkOrId then return false end
    local _, _, _, _, _, itemType, _, _, _, _, _, classID = GetItemInfo(linkOrId)
    local recipeLabel = (_G and _G.ITEM_CLASS_RECIPE) or "Recipe"
    local recipeClass = (_G and _G.LE_ITEM_CLASS_RECIPE) or LE_ITEM_CLASS_RECIPE or 9
    return classID == recipeClass or itemType == recipeLabel or itemType == "Recipe"
end

-- Capture filter (PRODUCTION): only record items that actually belong to the instance we're
-- in, per the AtlasLoot-derived loot table (ns.lootSources.byItemId). An item qualifies when
-- it's in the table AND its source instance matches the current one (by InstanceID, the most
-- reliable key; by instance-name as a fallback for the handful of entries with no InstanceID).
-- This drops EVERYTHING that isn't a real drop from this instance: trade goods, world-drop
-- BoEs, consumables, quest items, junk — none of it gets a record. Boss AND trash drops that
-- belong to the instance are kept.
--
-- `curInstanceID` / `curInstanceName` are the current instance's identifiers (passed in by the
-- caller from GetInstanceInfo). With no loot table loaded (e.g. unit tests), nothing is tracked.
-- Pure + unit-tested: exposed as a method (Tracker:IsTrackableItem) over a source table so the
-- whitelist logic can be tested without the live GetInstanceInfo / loaded data file.
function Tracker:IsTrackableItem(itemID, curInstanceID, curInstanceName, sources)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if ns.LOOT_DIST_TEST and ((curInstanceID and tonumber(curInstanceID) ~= 0) or (curInstanceName and curInstanceName ~= "")) then
        return true
    end
    sources = sources or (ns.lootSources and ns.lootSources.byItemId)
    local src = sources and sources[itemID]
    if not src then return false end                     -- not a known instance drop at all
    if src.instanceID and curInstanceID then
        return src.instanceID == curInstanceID           -- exact InstanceID match (preferred)
    end
    -- Fallback when one side lacks an InstanceID: compare instance display names loosely.
    if src.instance and curInstanceName and curInstanceName ~= "" then
        local a = src.instance:lower():gsub("^the ", "")
        local b = curInstanceName:lower():gsub("^the ", "")
        return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
    end
    return false
end

-- Thin file-local wrapper used by OnLootOpened (reads the loaded data table).
local function isTrackableItem(itemID, curInstanceID, curInstanceName)
    return Tracker:IsTrackableItem(itemID, curInstanceID, curInstanceName)
end

-- Snapshot of items currently in the local player's bags, keyed by GUID where
-- available, with a count fallback for items that have no resolvable GUID.
local function trackedBagSnapshot()
    local snap = { byGuid = {}, byItemId = {}, counts = {} }
    for bag = 0, 4 do
        for slot = 1, bagSlotCount(bag) do
            local itemId, link = containerItemID(bag, slot)
            if itemId then
                local guid = itemGuidFromBagSlot(bag, slot)
                local row = { bag = bag, slot = slot, itemId = itemId, itemGuid = guid, itemLink = link or containerItemLink(bag, slot) }
                if guid and guid ~= "" then snap.byGuid[guid] = row end
                snap.byItemId[itemId] = snap.byItemId[itemId] or {}
                table.insert(snap.byItemId[itemId], row)
                snap.counts[itemId] = (snap.counts[itemId] or 0) + 1
            end
        end
    end
    return snap
end

--------------------------------------------------------------------------------
-- Roster ratio (Task 9.2)
--------------------------------------------------------------------------------

function Tracker:CurrentRaidGuildRatio()
    local raidNames = {}
    local numRaid = (GetNumRaidMembers and GetNumRaidMembers())
        or (GetNumGroupMembers and IsInRaid and IsInRaid() and GetNumGroupMembers())
        or 0
    if numRaid and numRaid > 0 and GetRaidRosterInfo then
        for i = 1, numRaid do
            local name = GetRaidRosterInfo(i)
            if name then table.insert(raidNames, name) end
        end
    else
        -- party / solo fallback
        local numParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        local me = localPlayer() or (UnitName and UnitName("player"))
        if me then table.insert(raidNames, me) end
        for i = 1, (numParty or 0) do
            local n = UnitName and UnitName("party" .. i)
            if n then table.insert(raidNames, n) end
        end
    end

    local guildSet = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local gname = GetGuildRosterInfo(i)
            if gname then
                local norm = normalizeName(gname)
                if norm ~= "" then guildSet[norm] = true end
            end
        end
    end

    return self:GuildRatioFromRosters(raidNames, guildSet)
end

--------------------------------------------------------------------------------
-- Instance / session identity (Task 9.3)
--------------------------------------------------------------------------------

-- Returns instanceName, instanceType, difficultyID, instanceID (any may be nil).
local function instanceInfo()
    if not GetInstanceInfo then return nil, nil, nil, nil end
    local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    return name, instanceType, difficultyID, instanceID
end

local function inInstance()
    local _, instanceType = instanceInfo()
    return instanceType == "party" or instanceType == "raid"
end

-- The ONLY raids whose history sessions may be shared to the guild (by stable map/instanceID,
-- locale-independent): Karazhan(532), Hyjal Summit/MH(534), Magtheridon's Lair(544),
-- Serpentshrine Cavern(548), Tempest Keep(550), Black Temple(564), Gruul's Lair(565),
-- Zul'Aman(568), Sunwell Plateau(580). Anything else — and EVERY 5-man dungeon — stays personal.
local SHAREABLE_RAID_INSTANCE = {
    [532] = true, [534] = true, [544] = true, [548] = true, [550] = true,
    [564] = true, [565] = true, [568] = true, [580] = true,
}
-- Name fallback (only used if instanceID is unavailable). Normalised: lowercased, "the " dropped.
local SHAREABLE_RAID_NAME = {
    ["karazhan"] = true, ["hyjal summit"] = true, ["mount hyjal"] = true,
    ["magtheridon's lair"] = true, ["serpentshrine cavern"] = true,
    ["tempest keep"] = true, ["black temple"] = true, ["gruul's lair"] = true,
    ["zul'aman"] = true, ["sunwell plateau"] = true,
}

-- True only when the current session is a RAID in the shareable allow-list. 5-man dungeons
-- (instanceType "party") and any non-listed raid are NOT shareable -> their sessions stay personal.
local function sessionShareEligible(instanceType, instanceID, instanceName)
    if instanceType ~= "raid" then return false end          -- excludes 5-man dungeons
    if instanceID and SHAREABLE_RAID_INSTANCE[tonumber(instanceID) or -1] then return true end
    if instanceName and instanceName ~= "" then
        local key = instanceName:lower():gsub("^the ", "")
        if SHAREABLE_RAID_NAME[key] then return true end
    end
    return false
end

-- Session bucket width: a continuous run shares one id; a re-entry hours later gets a new
-- one. 6h comfortably covers any single raid/dungeon clear without merging next week's run.
local SESSION_BUCKET = 6 * 60 * 60

-- The session id MUST be derivable identically on every client (it is the sync key), so it
-- is a function of shared observable state only: instanceID + difficulty + a coarse shared
-- time bucket. NOT a per-client serial (those never agree across clients). The bucket is
-- anchored to when this client first entered the instance, snapped to the bucket grid, so
-- two players who entered the same run within the same window converge on one id.
function Tracker:CurrentSessionID()
    if not inInstance() then return nil end
    local _, instanceType, difficultyID, instanceID = instanceInfo()
    local anchor = self.instanceEnterAt or now()
    local bucket = instanceType == "party" and math.floor(anchor) or math.floor(anchor / SESSION_BUCKET)
    -- numeric-dash scheme: never contains ':' or ',' (manifest delimiters).
    return ("%s-%s-%s"):format(tostring(instanceID or 0), tostring(difficultyID or 0), tostring(bucket))
end

--------------------------------------------------------------------------------
-- Scope evaluation (Task 9.4)
--------------------------------------------------------------------------------

function Tracker:EvaluateSessionScope(sessionID)
    if not sessionID then return end
    local store = Store()
    if not store then return end
    local guildCount, raidSize = self:CurrentRaidGuildRatio()
    local settings = (store.Get and store:Get() and store:Get().settings) or nil
    local threshold = (settings and settings.guildRaidThreshold) or 0.60
    local sess = store:Sessions()[sessionID]
    local currentScope = sess and sess.scope or nil
    -- Re-check eligibility live (a 5-man dungeon or non-listed raid never promotes).
    local instanceName, instanceType, _, instanceID = instanceInfo()
    local eligible = sessionShareEligible(instanceType, instanceID, instanceName)
    local decided = store:DecideScope(guildCount, raidSize, threshold, currentScope, eligible)
    if decided == "guild" and currentScope ~= "guild" then
        store:PromoteSession(sessionID)
        local s = Sync()
        if s and s.OnSessionPromoted then s:OnSessionPromoted(sessionID) end
    end
end

-- Debounced wrapper to coalesce roster churn (RAID_ROSTER_UPDATE storms etc.).
function Tracker:ScheduleScopeEval()
    self._scopeToken = (self._scopeToken or 0) + 1
    local token = self._scopeToken
    local function fire()
        if token ~= self._scopeToken then return end
        self:EvaluateSessionScope(self.activeSessionID)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, fire)
    else
        fire()
    end
end

-- Refresh the loot panels if they're open, so the History/Active windows update live as
-- events happen instead of only when reopened. Cheap + debounced inside the panel.
local function refreshPanels()
    local p = ns:GetModule("LootPanel")
    if p and p.Refresh then p:Refresh() end
    local ap = ns:GetModule("LootActivePanel")
    if ap and ap.Refresh then ap:Refresh() end
end

local function notifyLocalChange(sessionID)
    if not sessionID then return end
    -- Live UI update for ANY local change (guild or personal) — your own loot should show
    -- immediately regardless of scope.
    refreshPanels()
    -- Sync notification is guild-only (personal sessions are never shared).
    local store = Store()
    if store and store.IsGuildSession and not store:IsGuildSession(sessionID) then return end
    local s = Sync()
    if s and s.OnLocalChange then s:OnLocalChange(sessionID) end
end

--------------------------------------------------------------------------------
-- Session start (Task 9.5)
--------------------------------------------------------------------------------

-- Establish (or reuse) the instance-enter anchor used by the session-time bucket. Raid
-- anchors persist briefly so a /reload or difficulty flicker reuses the same session.
-- Party-instance anchors are reset after leaving so repeated dungeon resets create new
-- History sessions instead of dumping every run into one card.
local function instanceAnchorKey(instanceID, difficultyID)
    return tostring(instanceID or 0) .. ":" .. tostring(difficultyID or 0)
end

function Tracker:AnchorForInstance(store, instanceID, difficultyID, instanceType, preserveAnchor)
    local r = store.Get and store:Get()
    if not r then self.instanceEnterAt = self.instanceEnterAt or now(); return end
    r.instanceAnchors = r.instanceAnchors or {}
    local key = instanceAnchorKey(instanceID, difficultyID)
    local existing = r.instanceAnchors[key]
    local sameLiveInstance = self.currentInstanceAnchorKey == key and self.instanceEnterAt
    -- Party instances are resettable and personal. Reuse while we are continuously inside
    -- the same run, or after a reload/login that happened inside the instance, but mint a
    -- fresh anchor after an actual leave/re-enter so repeat dungeon resets become new sessions.
    if instanceType == "party" and sameLiveInstance then
        self.instanceEnterAt = sameLiveInstance
    elseif instanceType == "party" and preserveAnchor and existing and (now() - existing) < SESSION_BUCKET then
        self.instanceEnterAt = existing
    elseif instanceType ~= "party" and existing and (now() - existing) < SESSION_BUCKET then
        self.instanceEnterAt = existing
    else
        self.instanceEnterAt = now()
        r.instanceAnchors[key] = self.instanceEnterAt
    end
    self.currentInstanceAnchorKey = key
    self.currentInstanceType = instanceType
    self.currentInstanceID = instanceID
    self.currentDifficultyID = difficultyID
end

function Tracker:OnWorldChanged(isInitialLogin, isReloadingUi)
    local store = Store()
    if not store then return end
    if not inInstance() then
        if self.wasInInstance and self.currentInstanceType == "party" then
            local r = store.Get and store:Get()
            if r and r.instanceAnchors and self.currentInstanceAnchorKey then
                r.instanceAnchors[self.currentInstanceAnchorKey] = nil
            end
            self.instanceEnterAt = nil
            self.currentInstanceAnchorKey = nil
            self.currentInstanceType = nil
            self.currentInstanceID = nil
            self.currentDifficultyID = nil
        end
        self.wasInInstance = false
        self.activeSessionID = nil
        return
    end
    self.wasInInstance = true
    local preserveAnchor = isInitialLogin or isReloadingUi

    -- GetInstanceInfo() returns a transient difficulty (often 0) during the zone-in
    -- transition, then settles. Defer session creation briefly so we key the session on
    -- the SETTLED difficulty — otherwise one run splits into a "<id>-0-…" and "<id>-1-…".
    if C_Timer and C_Timer.After then
        self._sessionStartToken = (self._sessionStartToken or 0) + 1
        local token = self._sessionStartToken
        C_Timer.After(1.0, function()
            if token == self._sessionStartToken and inInstance() then
                self:StartSessionNow(preserveAnchor)
            end
        end)
    else
        self:StartSessionNow(preserveAnchor)
    end
end

function Tracker:StartSessionNow(preserveAnchor)
    local store = Store()
    if not store or not inInstance() then return end
    local instanceName, instanceType, difficultyID, instanceID = instanceInfo()
    self:AnchorForInstance(store, instanceID, difficultyID, instanceType, preserveAnchor)

    local sessionID = self:CurrentSessionID()
    if not sessionID then return end

    local guildCount, raidSize = self:CurrentRaidGuildRatio()
    local settings = (store.Get and store:Get() and store:Get().settings) or nil
    local threshold = (settings and settings.guildRaidThreshold) or 0.60
    -- Only shareable raids (allow-list) can ever go guild scope; 5-man dungeons stay personal.
    local eligible = sessionShareEligible(instanceType, instanceID, instanceName)
    local decided = store:DecideScope(guildCount, raidSize, threshold, nil, eligible)

    store:EnsureSession(sessionID, {
        scope = decided,
        instance = instanceName,
        instanceType = instanceType,
        instanceId = instanceID,
        difficultyId = difficultyID,
        guildRatioAtStart = raidSize > 0 and (guildCount / raidSize) or 0,
        startedAt = now(),
    })
    self.activeSessionID = sessionID
    if decided == "guild" then
        local s = Sync()
        if s and s.OnSessionPromoted then s:OnSessionPromoted(sessionID) end
    end
end

--------------------------------------------------------------------------------
-- Boss attribution (Task 9.6)
--------------------------------------------------------------------------------

function Tracker:OnCombatLogEvent()
    if not CombatLogGetCurrentEventInfo then return end
    local _, subEvent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if subEvent == "UNIT_DIED" and destGUID and type(destGUID) == "string" then
        -- Only creatures, not players/pets we don't care about. Creature/Vehicle GUIDs.
        if destGUID:find("^Creature") or destGUID:find("^Vehicle") then
            -- Remember the name of EVERY creature we kill, keyed by its GUID. Loot is then
            -- attributed by the GUID of the corpse actually being looted (GetLootSourceInfo),
            -- NOT by "last kill" — so killing trash adds after a boss doesn't mis-attribute
            -- the boss's loot. Bounded to avoid unbounded growth over a long session.
            self.nameByGUID = self.nameByGUID or {}
            if destName and destName ~= "" then
                self.nameByGUID[destGUID] = destName
                self._guidCount = (self._guidCount or 0) + 1
                if self._guidCount > 400 then self.nameByGUID = { [destGUID] = destName }; self._guidCount = 1 end
            end
            -- Keep last-kill as a soft fallback only (used when GetLootSourceInfo is unavailable).
            self.lastBossGUID = destGUID
            self.lastBossName = destName
            self.lastBossAt = now()
        end
    end
end

function Tracker:NoteBossKill(name)
    if name and name ~= "" then
        self.lastBossName = name
        self.lastBossAt = now()
    end
end

local function bossRecent(self)
    return self.lastBossAt and (now() - self.lastBossAt) <= 60
end

--------------------------------------------------------------------------------
-- Loot capture (Task 9.7)
--------------------------------------------------------------------------------

-- First GUID encoded in a GetLootSourceInfo return (can encode multiple sources).
local function firstLootSourceGUID(slot)
    if not GetLootSourceInfo then return nil end
    local ok, guid = pcall(GetLootSourceInfo, slot)
    if not ok then return nil end
    if type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

-- Set of known BOSS names (lowercased), built lazily from the raid loot table's `source` values
-- (everything that isn't "Trash"/"Recipes"). Lets us classify a looted creature: if the corpse's
-- name is a known boss -> attribute to that boss; otherwise it's TRASH. This is how a Nether
-- Vortex looted off a trash mob lands under "Trash" while the 2 off Lady Vashj land under her.
local _bossNameSet
local function bossNameSet()
    if _bossNameSet then return _bossNameSet end
    _bossNameSet = {}
    local t = ns.raidLootSources and ns.raidLootSources.byItemId
    if t then
        for _, src in pairs(t) do
            local s = src and src.source
            if s and s ~= "" then
                local low = s:lower()
                if low ~= "trash" and low ~= "recipes" then _bossNameSet[low] = s end
            end
        end
    end
    -- Also fold in the Vanilla/other table's boss field.
    local t2 = ns.lootSources and ns.lootSources.byItemId
    if t2 then
        for _, src in pairs(t2) do
            local s = src and src.boss
            if s and s ~= "" then
                local low = s:lower()
                if low ~= "trash" and low ~= "recipes" and low ~= "unknown" and not low:find("tier") then
                    _bossNameSet[low] = s
                end
            end
        end
    end
    return _bossNameSet
end

-- Is this looted-creature name a known raid boss? (case-insensitive, fuzzy on the leading word so
-- "Lady Vashj" matches a corpse literally named "Lady Vashj").
local function isKnownBoss(creatureName)
    if not creatureName or creatureName == "" then return false end
    return bossNameSet()[creatureName:lower()] ~= nil
end

-- Authoritative boss/instance lookup from the baked AtlasLoot-derived data (itemID -> source).
-- Deterministic and identical on every client — far more reliable than combat-log timing.
local function sourceForItem(itemID)
    local src = ns.lootSources and ns.lootSources.byItemId and ns.lootSources.byItemId[itemID]
    if src then return src.boss, src.instance end
    return nil, nil
end

-- Resolve (or create) the drop record for a whitelisted instance item, computing a
-- deterministic dropID that is IDENTICAL across all trackers regardless of how the item was
-- observed (own loot window vs another player's loot chat line). Returns dropID, drop.
-- `sourceGUID` is optional (only available when WE open the loot window). Used by both
-- OnLootOpened and TrackLootMessage so the two paths converge on ONE record.
function Tracker:ResolveDropForItem(itemID, link, curInstanceID, instanceName, sourceGUID, copyIndex)
    local store = Store()
    if not store or not self.activeSessionID then return nil end
    self.nameByGUID = self.nameByGUID or {}
    local tableBoss = sourceForItem(itemID)

    -- ATTRIBUTION BY ACTUAL CORPSE (not the loot table). When we looted the item ourselves we know
    -- the GUID of the corpse it came from; its creature name is the truth:
    --   * corpse is a known boss  -> that boss
    --   * corpse is anything else -> "Trash"
    -- This is what puts a Nether Vortex looted off a trash mob under "Trash" while the copies off
    -- Lady Vashj go under her — even though the loot table lists the item under Vashj for both.
    -- The loot-table boss is used ONLY as a fallback when we have no corpse GUID (item seen via
    -- someone else's chat line). "recent kill" is a last resort.
    local corpseName = sourceGUID and sourceGUID ~= "" and self.nameByGUID[sourceGUID] or nil
    local bossName
    if corpseName then
        bossName = isKnownBoss(corpseName) and corpseName or "Trash"
    else
        bossName = tableBoss or (bossRecent(self) and self.lastBossName) or "Trash"
    end

    -- Identity. Prefer the loot-source GUID — it's the per-physical-drop id, identical across all
    -- observers of that copy, so distinct copies (and trash-vs-boss copies of the same item) get
    -- distinct records while two observers of ONE copy still converge. Without a GUID we fall back
    -- to the loot-table id (chat-only; may merge copies, the unavoidable limit) or a time bucket.
    local dropID
    if sourceGUID and sourceGUID ~= "" then
        dropID = "LT:" .. tostring(curInstanceID or 0) .. ":" .. tostring(bossName)
            .. ":" .. tostring(itemID) .. ":" .. sourceGUID
        if tonumber(copyIndex or 1) > 1 then dropID = dropID .. "#" .. tostring(math.floor(tonumber(copyIndex) or 1)) end
    elseif tableBoss then
        dropID = store:LootTableDropID(curInstanceID, tableBoss, itemID)
        if tonumber(copyIndex or 1) > 1 then dropID = dropID .. "#chat" .. tostring(math.floor(tonumber(copyIndex) or 1)) end
    else
        dropID = store:FallbackDropID(bossName or instanceName, now(), itemID)
        if tonumber(copyIndex or 1) > 1 then dropID = dropID .. "#chat" .. tostring(math.floor(tonumber(copyIndex) or 1)) end
    end
    if not dropID then return nil end
    local name, quality, icon = itemInfoFor(link or itemID)
    local drop = store:EnsureDrop(dropID, {
        sessionID = self.activeSessionID,
        itemId = itemID,
        itemLink = link,
        itemName = name,
        quality = quality,
        icon = icon,
        bossName = bossName,
    })
    return dropID, drop
end

local function dropHasLootedEvent(drop)
    for _, ev in pairs((drop and drop.events) or {}) do
        if ev.type == "looted" then return true end
    end
    return false
end

function Tracker:NextPendingLootDrop(itemID)
    local queue = self.pendingLootByItem and self.pendingLootByItem[itemID]
    if type(queue) ~= "table" then return nil end
    local store = Store()
    while #queue > 0 do
        local pending = table.remove(queue, 1)
        local dropID = pending and pending.dropID
        local drop = store and dropID and store:Drops()[dropID]
        if drop and not dropHasLootedEvent(drop) then return dropID, drop end
    end
    self.pendingLootByItem[itemID] = nil
    return nil
end

function Tracker:QueuePendingLootDrop(itemID, dropID, meta)
    if not itemID or not dropID then return false end
    self.pendingLootByItem = self.pendingLootByItem or {}
    local queue = self.pendingLootByItem[itemID]
    if type(queue) ~= "table" then
        queue = {}
        self.pendingLootByItem[itemID] = queue
    end
    for i = 1, #queue do
        if queue[i] and queue[i].dropID == dropID then
            if meta and meta.rollID then queue[i].rollID = meta.rollID end
            return false
        end
    end
    queue[#queue + 1] = {
        dropID = dropID,
        at = now(),
        rollID = meta and meta.rollID or nil,
    }
    return true
end

function Tracker:FindUnlootedActiveDrop(itemID, exclude)
    local store = Store()
    if not store or not itemID then return nil end
    local bestID, bestAt
    for dropID, drop in pairs(store:Drops()) do
        if drop.itemId == itemID and drop.sessionID == self.activeSessionID
            and not (exclude and exclude[dropID])
            and not dropHasLootedEvent(drop) then
            local at = drop.droppedAt or 0
            if not bestID or at < bestAt or (at == bestAt and tostring(dropID) < tostring(bestID)) then
                bestID, bestAt = dropID, at
            end
        end
    end
    return bestID, bestID and store:Drops()[bestID] or nil
end

function Tracker:FindActiveLootedDropByActor(itemID, actor)
    local store = Store()
    if not store or not itemID or not actor then return nil end
    for dropID, drop in pairs(store:Drops()) do
        if drop.itemId == itemID and drop.sessionID == self.activeSessionID then
            for _, ev in pairs(drop.events or {}) do
                if ev.type == "looted" and ev.actor == actor then return dropID, drop end
            end
        end
    end
    return nil
end

function Tracker:ActiveDropCountForItem(itemID)
    local store = Store()
    if not store or not itemID then return 0 end
    local count = 0
    for _, drop in pairs(store:Drops()) do
        if drop.itemId == itemID and drop.sessionID == self.activeSessionID then count = count + 1 end
    end
    return count
end

function Tracker:OnLootOpened()
    if not self.activeSessionID then return end
    local store = Store()
    if not store then return end
    local numItems = (GetNumLootItems and GetNumLootItems()) or 0
    local instanceName, _, _, curInstanceID = instanceInfo()
    local captured = false
    local copies = {}
    local reused = {}
    for slot = 1, numItems do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local itemID = itemIdFromLink(link)
        if itemID and isTrackableItem(itemID, curInstanceID, instanceName)
            and shouldTrack(link or itemID) then   -- whitelist + Rare/Epic gear only (no greens/quest items)
            local sourceGUID = firstLootSourceGUID(slot)
            local copyKey = tostring(curInstanceID or 0) .. "\031" .. tostring(sourceGUID or "") .. "\031" .. tostring(itemID)
            copies[copyKey] = (copies[copyKey] or 0) + 1
            -- If the roll frame arrived first, it already created an unlooted active row.
            -- Attach the corpse-window observation to that row instead of creating a second row
            -- for the same physical drop. `reused` keeps two same-item copies distinct.
            local dropID, drop = self:FindUnlootedActiveDrop(itemID, reused)
            if not dropID then
                dropID, drop = self:ResolveDropForItem(itemID, link, curInstanceID, instanceName, sourceGUID, copies[copyKey])
            end
            if dropID then
                reused[dropID] = true
                -- Remember a hint so CHAT_MSG_LOOT / LOOT_SLOT_CLEARED can attach a looter.
                self:QueuePendingLootDrop(itemID, dropID)
                captured = true
            end
        end
    end
    -- Newly captured drops should show immediately (even before their looted event lands).
    if captured then refreshPanels() end
end

function Tracker:OnStartLootRoll(rollID, attempt)
    if not self.activeSessionID or not rollID then return end
    self.rollDrops = self.rollDrops or {}
    if self.rollDrops[rollID] then return end
    attempt = tonumber(attempt) or 1

    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    if not link and GetLootRollItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, itemLink = GetLootRollItemInfo(rollID)
        link = itemLink
    end
    local itemID = itemIdFromLink(link)
    if not itemID then
        if C_Timer and C_Timer.After and attempt < ROLL_CAPTURE_RETRIES then
            C_Timer.After(ROLL_CAPTURE_RETRY_DELAY, function() self:OnStartLootRoll(rollID, attempt + 1) end)
        end
        return
    end

    local instanceName, _, _, curInstanceID = instanceInfo()
    if not isTrackableItem(itemID, curInstanceID, instanceName) then return end
    if not shouldTrack(link or itemID) then return end

    -- A roll frame is often the same physical drop already seen through LOOT_OPENED by the
    -- looter. Reuse that unassigned row so the later winner chat updates ONE record instead of
    -- creating a second fallback "Trash" record for the roll frame.
    local dropID = self:FindUnlootedActiveDrop(itemID)
    if not dropID then
        local copyIndex = self:ActiveDropCountForItem(itemID) + 1
        dropID = self:ResolveDropForItem(itemID, link, curInstanceID, instanceName, nil, copyIndex)
    end
    if not dropID then return end

    self.rollDrops[rollID] = dropID
    self:QueuePendingLootDrop(itemID, dropID, { rollID = rollID })
    refreshPanels()
end

-- Find the drop for a physical item by itemId (+optional GUID). A traded / disenchanted /
-- equipped item is the same physical object no matter WHICH session it was looted in
-- (instance resets create new sessions), so we search ALL sessions — preferring (1) an
-- exact GUID match, then (2) the active session, then (3) the most-recent drop anywhere.
-- We skip drops that have genuinely LEFT the player's hands so we don't re-attribute them.
-- NOTE: 'finalized' is NOT in this set — a finalized (bound) item is still in the player's
-- bags and can still be deleted / disenchanted / vendored / (re)traded; those terminal
-- events outrank the finalize in ComputeState. Skipping finalized here was why deleting a
-- finalized item never registered.
function Tracker:FindDropForItem(itemID, itemGUID)
    local store = Store()
    if not store or not itemID then return nil end
    local GONE = { disenchanted = true, deleted = true, guild_bank = true, vendored = true }
    local me = localPlayer()
    -- Deterministic "better" test: higher droppedAt wins; on a TIE, the lexicographically
    -- larger dropID wins. The tie-break is critical — without it, two clients pick DIFFERENT
    -- drops for the same itemId (pairs() order differs) and attach a removal event to
    -- different records, diverging the session forever.
    local function better(at, id, bestAt, bestId)
        if not bestId then return true end
        if at ~= bestAt then return at > bestAt end
        return tostring(id) > tostring(bestId)
    end
    local bestActive, bestActiveAt, bestAny, bestAnyAt
    for dropID, drop in pairs(store:Drops()) do
        if drop.itemId == itemID then
            -- Exact physical-item match wins immediately.
            if itemGUID and drop.itemGUID == itemGUID then return dropID, drop end
            local st = store:ComputeState(drop)
            local tradedAway = st.status == "traded" and me and not samePlayer(st.currentHolder, me)
            if not GONE[st.status] and not tradedAway then
                local at = drop.droppedAt or 0
                if drop.sessionID == self.activeSessionID then
                    if better(at, dropID, bestActiveAt, bestActive) then bestActive, bestActiveAt = dropID, at end
                end
                if better(at, dropID, bestAnyAt, bestAny) then bestAny, bestAnyAt = dropID, at end
            end
        end
    end
    local best = bestActive or bestAny
    if best then
        local drop = store:Drops()[best]
        -- Anchor this physical item's GUID on first resolution (the loot window has no
        -- bag GUID, so it's learned here) — later lookups hit the fast path above.
        if itemGUID and drop and not drop.itemGUID then drop.itemGUID = itemGUID end
        return best, drop
    end
    return nil
end

function Tracker:FindDropForIncomingTrade(itemID, itemGUID, fromPlayer)
    local store = Store()
    if not store or not itemID then return nil end
    local function better(at, id, bestAt, bestId)
        if not bestId then return true end
        if at ~= bestAt then return at > bestAt end
        return tostring(id) > tostring(bestId)
    end
    local best, bestAt
    for dropID, drop in pairs(store:Drops()) do
        if drop.itemId == itemID then
            if itemGUID and drop.itemGUID == itemGUID then return dropID, drop end
            local st = store:ComputeState(drop)
            if samePlayer(st.currentHolder, fromPlayer) or samePlayer(st.finalOwner, fromPlayer) then
                local at = drop.droppedAt or 0
                if better(at, dropID, bestAt, best) then best, bestAt = dropID, at end
            end
        end
    end
    if best then
        local drop = store:Drops()[best]
        if itemGUID and drop and not drop.itemGUID then drop.itemGUID = itemGUID end
        return best, drop
    end
    return nil
end

function Tracker:CreateTestTradePlaceholder(itemID, itemGUID, itemLink, fromPlayer)
    if not (ns.LOOT_DIST_TEST and self.activeSessionID and itemID) then return nil end
    if not shouldTrack(itemLink or itemID) then return nil end
    local instanceName, _, _, curInstanceID = instanceInfo()
    local dropID, drop = self:ResolveDropForItem(itemID, itemLink, curInstanceID, instanceName, nil)
    local store = Store()
    if not (store and dropID and drop) then return nil end
    if itemGUID and not drop.itemGUID then drop.itemGUID = itemGUID end
    store:AddEvent(dropID, { type = "looted", actor = fromPlayer, at = LOOTED_AT })
    return dropID, drop
end

-- Port of the loot-message parse: returns looterName, itemLink.
local function parseLootMessage(message)
    if type(message) ~= "string" then return nil, nil end
    if message:find("|HlootHistory") then return nil, nil end
    local selfPat = _G and _G.LOOT_ITEM_SELF       -- "You receive loot: %s."
    local selfMultiPat = _G and _G.LOOT_ITEM_SELF_MULTIPLE
    local otherPat = _G and _G.LOOT_ITEM            -- "%s receives loot: %s."
    local otherMultiPat = _G and _G.LOOT_ITEM_MULTIPLE

    local function toLua(fmt)
        if not fmt then return nil end
        return "^" .. fmt:gsub("%%s", "(.+)"):gsub("%%d", "%%d+"):gsub("x%d+", "") .. "$"
    end

    -- Self patterns -> looter is the local player.
    for _, fmt in ipairs({ selfMultiPat, selfPat }) do
        local pat = toLua(fmt)
        if pat then
            local link = message:match(pat)
            if link then return "__self__", link end
        end
    end
    -- Other-player patterns -> first capture = name, last = link.
    for _, fmt in ipairs({ otherMultiPat, otherPat }) do
        local pat = toLua(fmt)
        if pat then
            local a, b = message:match(pat)
            if a and b then return a, b end
        end
    end
    -- Conservative English fallbacks.
    local link = message:match("^You receive loot: (.+)%.?$")
    if link then return "__self__", link end
    local who, lnk = message:match("^(.+) receives? loot: (.+)%.?$")
    if who and lnk then return who, lnk end
    return nil, nil
end

function Tracker:TrackLootMessage(message)
    if not self.activeSessionID then return end
    local looter, link = parseLootMessage(message)
    if not link then return end
    local itemID = itemIdFromLink(link)
    if not itemID then return end
    if looter == "__self__" then looter = localPlayer() else looter = canonName(looter) end
    if not looter or looter == "" then return end

    local dropID, drop = self:NextPendingLootDrop(itemID)
    if not dropID then dropID, drop = self:FindUnlootedActiveDrop(itemID) end
    if not dropID then dropID, drop = self:FindActiveLootedDropByActor(itemID, looter) end
    if not dropID then dropID, drop = self:FindDropForItem(itemID) end
    if not dropID then
        -- We never opened a loot window for this item — it was won by another player and we
        -- only see the chat line. Still capture it (whole-raid accountability): create the
        -- drop from the chat line IF it's a whitelisted drop of the instance we're in. The
        -- loot-table dropID is deterministic, so this converges with any tracker who DID open
        -- the window. Without the loot table (unknown item), we can't make a stable id, so skip
        -- in production. /iddqd loottest intentionally relaxes this so dungeon trade tests can
        -- build local history from visible party loot chat.
        local instanceName, _, _, curInstanceID = instanceInfo()
        if not isTrackableItem(itemID, curInstanceID, instanceName) then return end
        if not shouldTrack(link or itemID) then return end   -- Rare/Epic gear only (no greens/quest items)
        if not ns.LOOT_DIST_TEST and not (sourceForItem(itemID)) then return end   -- needs a loot-table boss for a stable id
        dropID, drop = self:ResolveDropForItem(itemID, link, curInstanceID, instanceName, nil)
        if not dropID then return end
    elseif dropHasLootedEvent(drop) then
        local existingForLooter = self:FindActiveLootedDropByActor(itemID, looter)
        if existingForLooter ~= dropID then
            local instanceName, _, _, curInstanceID = instanceInfo()
            if isTrackableItem(itemID, curInstanceID, instanceName) and shouldTrack(link or itemID) and sourceForItem(itemID) then
                local copyIndex = self:ActiveDropCountForItem(itemID) + 1
                dropID, drop = self:ResolveDropForItem(itemID, link, curInstanceID, instanceName, nil, copyIndex)
                if not dropID then return end
            end
        end
    end
    local store = Store()
    if store:AddEvent(dropID, { type = "looted", actor = looter, at = LOOTED_AT }) then
        notifyLocalChange(self.activeSessionID)
    end
end

-- LOOT_SLOT_CLEARED fires when the local player takes a slot. The slot index is
-- no longer queryable here (the loot row is gone), so looter attribution is left
-- to CHAT_MSG_LOOT (which carries the looter name). Kept as a registered no-op
-- hook so the lifecycle stays robust if the chat message is suppressed.
function Tracker:OnLootSlotCleared(_slot)
    -- intentionally best-effort / no-op; see TrackLootMessage for attribution.
end

--------------------------------------------------------------------------------
-- TASK 10 — lifecycle detectors
--------------------------------------------------------------------------------

local function isGuildSession(sessionID)
    local store = Store()
    return store and store.IsGuildSession and store:IsGuildSession(sessionID)
end

-- Generic: emit an event for the drop matching itemID (+optional GUID) held in the
-- active session, then notify sync if guild. Returns true if a new event was added.
-- Emit an event for the physical item identified by itemID (+optional GUID). Works even
-- when not in an instance (you can trade/DE a looted item back in town), and notifies sync
-- for the DROP's own session (which may differ from the current active session).
function Tracker:EmitForItem(itemID, itemGUID, ev)
    local store = Store()
    if not store then return false end
    local dropID, drop = self:FindDropForItem(itemID, itemGUID)
    if not dropID and ev and ev.actor then
        dropID, drop = self:FindDropForIncomingTrade(itemID, itemGUID, ev.actor)
    end
    if not dropID then return false end
    if store:AddEvent(dropID, ev) then
        notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
        return true
    end
    return false
end

function Tracker:EmitIncomingTrade(itemID, itemGUID, itemLink, fromPlayer, toPlayer, at)
    local store = Store()
    if not store then return false end
    local dropID, drop = self:FindDropForIncomingTrade(itemID, itemGUID, fromPlayer)
    if not dropID then
        dropID, drop = self:CreateTestTradePlaceholder(itemID, itemGUID, itemLink, fromPlayer)
    end
    if not dropID then return false end
    if store:AddEvent(dropID, { type = "traded", actor = fromPlayer, target = toPlayer, at = at }) then
        notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Trade (traded)
--------------------------------------------------------------------------------

local function tradeTargetName()
    if _G and _G.TradeFrameRecipientNameText and _G.TradeFrameRecipientNameText.GetText then
        local t = _G.TradeFrameRecipientNameText:GetText()
        if t and t ~= "" then return canonName(t) end
    end
    if TradeTargetName and TradeTargetName.GetText then
        local t = TradeTargetName:GetText()
        if t and t ~= "" then return canonName(t) end
    end
    if UnitExists and UnitName then
        if UnitExists("NPC") then return canonName(UnitName("NPC")) end
        if UnitExists("npc") then return canonName(UnitName("npc")) end
    end
    if GetUnitName then return canonName(GetUnitName("NPC") or GetUnitName("npc")) end
    return nil
end

function Tracker:SnapshotTrade()
    local gave = {}
    if GetTradePlayerItemLink then
        for slot = 1, 6 do
            local link = GetTradePlayerItemLink(slot)
            local itemID = itemIdFromLink(link)
            if itemID then table.insert(gave, { itemId = itemID, itemLink = link }) end
        end
    end
    self.tradeGave = gave
end

function Tracker:ScheduleTradeSnapshot()
    self:SnapshotTrade()
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(0.1, function() self:SnapshotTrade() end)
    C_Timer.After(0.4, function() self:SnapshotTrade() end)
end

function Tracker:OnTradeShow()
    self.tradeTarget = tradeTargetName()
    self.tradeBagSnapshot = trackedBagSnapshot()
    self.tradeOpenedAt = now()
    self.tradeComplete = false
    self.tradeGave = {}
    self:ScheduleTradeSnapshot()
end

-- ERR_TRADE_COMPLETE can arrive EITHER before or AFTER TRADE_CLOSED depending on the
-- client. We therefore never gate on a complete flag being set at close time. Instead,
-- TRADE_CLOSED caches a pending trade and MarkTradeComplete (or an immediate complete)
-- triggers the commit. The bag diff only emits when the item ACTUALLY left our bags, so a
-- cancelled trade is self-correcting even if we attempt a commit.
function Tracker:MarkTradeComplete()
    self.tradeComplete = true
    if self.pendingClose then
        self:CommitPendingTrade()
    end
end

function Tracker:OnTradeClosed()
    -- Guard the duplicate TRADE_CLOSED (second fire arrives with state already cleared).
    if not self.tradeTarget and not self.pendingClose then
        return
    end
    if not self.tradeTarget then
        -- Duplicate close after we already captured the pending trade.
        return
    end
    local pending = {
        target = self.tradeTarget,
        before = self.tradeBagSnapshot,
        gave = self.tradeGave or {},
        at = self.tradeOpenedAt or now(),
    }
    local complete = self.tradeComplete
    self.tradeTarget = nil
    self.tradeBagSnapshot = nil
    self.tradeGave = nil
    self.tradeComplete = false
    self.pendingClose = pending
    if complete then
        -- Complete already arrived (complete-before-close client): commit now.
        self:CommitPendingTrade()
    elseif C_Timer and C_Timer.After then
        -- Wait briefly for ERR_TRADE_COMPLETE (close-before-complete client). If it never
        -- comes (cancelled trade), the bag diff will show nothing left and emit nothing.
        C_Timer.After(1.5, function()
            if self.pendingClose == pending then self:CommitPendingTrade() end
        end)
    else
        self:CommitPendingTrade()
    end
end

-- Commit the cached closed trade via bag-diff (+ frame-snapshot fallback). Idempotent:
-- the diff only emits 'traded' for items that genuinely left our bags.
function Tracker:CommitPendingTrade()
    local pending = self.pendingClose
    if not pending then return end
    self.pendingClose = nil
    local target, before, gave, at = pending.target, pending.before, pending.gave or {}, pending.at
    local me = localPlayer()

    local function commit()
        local handled = {}
        local received = {}
        if before then
            local after = trackedBagSnapshot()
            for guid, row in pairs(before.byGuid or {}) do
                if not after.byGuid[guid] then
                    if self:EmitForItem(row.itemId, guid, { type = "traded", actor = me, target = target, at = at }) then
                        handled[row.itemId] = (handled[row.itemId] or 0) + 1
                    end
                end
            end
            for itemId, beforeCount in pairs(before.counts or {}) do
                local afterCount = (after.counts and after.counts[itemId]) or 0
                local lost = math.max(0, beforeCount - afterCount - (handled[itemId] or 0))
                for _ = 1, lost do
                    self:EmitForItem(itemId, nil, { type = "traded", actor = me, target = target, at = at })
                end
            end
            for guid, row in pairs(after.byGuid or {}) do
                if not before.byGuid[guid] then
                    if self:EmitIncomingTrade(row.itemId, guid, row.itemLink, target, me, at) then
                        received[row.itemId] = (received[row.itemId] or 0) + 1
                    end
                end
            end
            for itemId, afterCount in pairs(after.counts or {}) do
                local beforeCount = (before.counts and before.counts[itemId]) or 0
                local gained = math.max(0, afterCount - beforeCount - (received[itemId] or 0))
                local rows = after.byItemId and after.byItemId[itemId] or {}
                for i = 1, gained do
                    local row = rows[i]
                    self:EmitIncomingTrade(itemId, row and row.itemGuid, row and row.itemLink, target, me, at)
                end
            end
        end
        -- Frame snapshot fallback for items not seen in the bag diff.
        for _, item in ipairs(gave) do
            if not handled[item.itemId] then
                self:EmitForItem(item.itemId, nil, { type = "traded", actor = me, target = target, at = at })
            end
        end
    end

    -- Defer so the item has actually moved out of the bag before we diff.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, commit)
        C_Timer.After(0.90, commit)
    else
        commit()
    end
end

--------------------------------------------------------------------------------
-- Trade window (trade_window / window_expired)
--------------------------------------------------------------------------------

function Tracker:ScheduleBagAudit()
    self._bagToken = (self._bagToken or 0) + 1
    local token = self._bagToken
    local function fire()
        if token ~= self._bagToken then return end
        self:AuditBags()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.8, fire) else fire() end
end

-- Bag audit handles: trade windows, disenchant confirm, guild-bank confirm,
-- tier turn-in confirm. Uses a before/after diff captured opportunistically.
function Tracker:AuditBags()
    local store = Store()
    if not store then return end
    local me = localPlayer()
    local current = trackedBagSnapshot()
    local previous = self.lastBagSnapshot

    -- Removal detection (sold / deleted / disenchanted / guild-banked) must run REGARDLESS of an
    -- active session: a player vendors/DEs raid loot AFTER the raid ends and they've left the
    -- group, when activeSessionID is nil. FindDropForItem searches ALL sessions (by itemId, with
    -- the anchored itemGUID), so the removal is attributed to the correct drop and synced to the
    -- guild. The trade-window/finalize loop below still requires an active session (it only
    -- concerns the CURRENT raid's in-bags items), so it's guarded separately.
    if not self.activeSessionID then
        if previous then self:DetectRemovals(previous, current, me) end
        self.lastBagSnapshot = current
        return
    end

    -- Trade-window detection (+ BoP-finalize) per tracked drop still held in our bags.
    self.windowState = self.windowState or {}   -- [dropID] = true if window was open
    local usedBagGuids = {}
    for dropID, drop in pairs(store:Drops()) do
        if drop.sessionID == self.activeSessionID and drop.itemId then
            local rows
            if drop.itemGUID and current.byGuid[drop.itemGUID] then
                rows = { current.byGuid[drop.itemGUID] }
                usedBagGuids[drop.itemGUID] = true
            else
                local candidates = current.byItemId[drop.itemId]
                if candidates and #candidates > 0 then
                    rows = {}
                    for _, row in ipairs(candidates) do
                        if not row.itemGuid or not usedBagGuids[row.itemGuid] then
                            rows[#rows + 1] = row
                            if row.itemGuid then usedBagGuids[row.itemGuid] = true end
                            break
                        end
                    end
                end
            end
            if rows and #rows > 0 then
                local anchorRow = rows[1]
                if anchorRow and anchorRow.itemGuid and not drop.itemGUID then
                    drop.itemGUID = anchorRow.itemGuid
                end
                local secs, boundRow = 0, nil
                for _, row in ipairs(rows) do
                    local t = tradeTimeRemaining(row.bag, row.slot)
                    if t and t > secs then secs = t end
                    boundRow = boundRow or row
                end
                -- Holding the item in our bags is authoritative proof WE are the holder. If the
                -- looted event never landed (chat-parse miss / auto-loot), self-attribute now so
                -- the drop reaches 'obtained' instead of being stuck 'pending'. Idempotent.
                local st = store:ComputeState(drop)
                if st.status == "pending" then
                    if store:AddEvent(dropID, { type = "looted", actor = me, at = LOOTED_AT }) then
                        notifyLocalChange(self.activeSessionID)
                        st = store:ComputeState(drop)
                    end
                end
                if secs and secs > 0 then
                    if store:AddEvent(dropID, { type = "trade_window", actor = me, remaining = secs, at = now() }) then
                        notifyLocalChange(self.activeSessionID)
                    end
                    self.windowState[dropID] = true
                elseif self.windowState[dropID] then
                    -- Previously had a window, now reads 0 while still owned -> expired.
                    if store:AddEvent(dropID, { type = "window_expired", actor = me, at = now() }) then
                        notifyLocalChange(self.activeSessionID)
                    end
                    self.windowState[dropID] = nil
                else
                    -- No trade window observed. If the item is BoP (soulbound to us), its
                    -- tradeable life is over -> finalize. BoE items stay 'obtained' (still
                    -- tradeable/sellable). ComputeState's terminal precedence lets a later
                    -- disenchant/vendor/delete override this finalize.
                    if st.status == "obtained" and boundRow and isSoulbound(boundRow.bag, boundRow.slot) then
                        if store:AddEvent(dropID, { type = "bop_finalized", actor = me, at = now() }) then
                            notifyLocalChange(self.activeSessionID)
                        end
                    end
                end
            end
        end
    end

    -- Diff-driven detectors (item disappeared from bags).
    if previous then
        self:DetectRemovals(previous, current, me)
    end

    self.lastBagSnapshot = current
end

-- An item leaving the local player's bags, attributed to whatever heuristic flag
-- is currently active (disenchant / guild-bank / tier turn-in). Best-effort.
function Tracker:DetectRemovals(before, after, me)
    local store = Store()
    if not store then return end
    local t = now()
    local recentDisenchant = self.disenchantPending and (t - self.disenchantPending) <= 3
    local merchantActive = self.merchantOpen or (self.lastMerchantAt and (t - self.lastMerchantAt) <= 3)
    local guildBankActive = self.guildBankOpen or (self.lastGuildBankAt and (t - self.lastGuildBankAt) <= 5)
    local npcActive = self.npcInteractionUntil and t <= self.npcInteractionUntil

    local function emitRemoval(itemId, itemGuid)
        local dropID, drop = self:FindDropForItem(itemId, itemGuid)
        if not dropID then return false end
        if recentDisenchant then
            if store:AddEvent(dropID, { type = "disenchanted", actor = me, at = t }) then
                notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
                return true
            end
        elseif merchantActive then
            -- Sold to a vendor (merchant window open + item left bags).
            if store:AddEvent(dropID, { type = "vendored", actor = me, at = t }) then
                notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
                return true
            end
        elseif guildBankActive then
            if store:AddEvent(dropID, { type = "guild_bank", actor = me, at = t }) then
                notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
                return true
            end
        elseif npcActive then
            -- Tier turn-in: a token disappeared during NPC interaction.
            if store:AddEvent(dropID, { type = "tier_turnin", actor = me, at = t }) then
                notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
                return true
            end
        elseif isRecipeItem(itemId) then
            -- Recipe learned: the recipe item is consumed without going through a merchant,
            -- disenchant, guild bank, delete dialog, or tier-token NPC turn-in flow.
            if store:AddEvent(dropID, { type = "recipe_learned", actor = me, at = t }) then
                notifyLocalChange(drop and drop.sessionID or self.activeSessionID)
                return true
            end
        end
        return false
    end

    -- Prefer exact physical-item GUID removals. This is critical for duplicate tier tokens:
    -- two rows can share itemID, but the removed bag slot's itemGUID identifies which copy left.
    local handledByItem = {}
    for guid, row in pairs(before.byGuid or {}) do
        if guid and row and row.itemId and not ((after.byGuid or {})[guid]) then
            if emitRemoval(row.itemId, guid) then
                handledByItem[row.itemId] = (handledByItem[row.itemId] or 0) + 1
            end
        end
    end

    -- Fallback for clients/items where bag GUIDs are unavailable: track which itemIDs had a
    -- count drop. This remains necessarily ambiguous for duplicate identical items.
    for itemId, beforeCount in pairs(before.counts or {}) do
        local afterCount = (after.counts and after.counts[itemId]) or 0
        local missing = math.max(0, (beforeCount or 0) - afterCount - (handledByItem[itemId] or 0))
        for _ = 1, missing do
            emitRemoval(itemId, nil)
        end
    end
    if recentDisenchant then self.disenchantPending = nil end
end

--------------------------------------------------------------------------------
-- Vendor (vendored)
--------------------------------------------------------------------------------

function Tracker:OnMerchantOpened()
    self.merchantOpen = true
    self.lastMerchantAt = now()
    -- Always capture a fresh baseline. A stale snapshot from before an incoming trade may not
    -- contain the item being sold, which would hide the vendored transition.
    self.lastBagSnapshot = trackedBagSnapshot()
end

function Tracker:OnMerchantClosed()
    self.merchantOpen = false
    self.lastMerchantAt = now()   -- keep a short grace window for the final BAG_UPDATE
end

--------------------------------------------------------------------------------
-- Disenchant (disenchanted)
--------------------------------------------------------------------------------

local function spellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellId)
        if ok then return n end
    end
    if GetSpellInfo then return (GetSpellInfo(spellId)) end
    return nil
end

function Tracker:OnSpellSucceeded(unit, _, spellId)
    if unit ~= "player" then return end
    local n = spellName(spellId)
    if spellId == DISENCHANT_SPELL_ID or (n and n:lower() == "disenchant") then
        self.disenchantPending = now()
        self:ScheduleBagAudit()
    end
end

--------------------------------------------------------------------------------
-- Guild bank (guild_bank)
--------------------------------------------------------------------------------

function Tracker:OnGuildBankOpened()
    self.guildBankOpen = true
    self.lastGuildBankAt = now()
    self.lastBagSnapshot = trackedBagSnapshot()
end

function Tracker:OnGuildBankClosed()
    self.guildBankOpen = false
    self.lastGuildBankAt = now()
    self:ScheduleBagAudit()
end

--------------------------------------------------------------------------------
-- Tier turn-in (tier_turnin) — NPC interaction window
--------------------------------------------------------------------------------

function Tracker:NoteNpcInteraction()
    self.npcInteractionUntil = now() + 5
    self:ScheduleBagAudit()
end

--------------------------------------------------------------------------------
-- Deletion (deleted) — hook the static delete dialogs
--------------------------------------------------------------------------------

function Tracker:HookDeleteDialogs()
    if self._deleteHooked then return end
    if type(StaticPopupDialogs) ~= "table" then return end
    self._deleteHooked = true
    for _, key in ipairs({ "DELETE_GOOD_ITEM", "DELETE_ITEM" }) do
        local dlg = StaticPopupDialogs[key]
        if type(dlg) == "table" then
            local orig = dlg.OnAccept
            dlg.OnAccept = function(...)
                -- Capture the item being deleted from the cursor before confirm.
                local link
                if GetCursorInfo then
                    local kind, _, l = GetCursorInfo()
                    if kind == "item" then link = l end
                end
                self.pendingDeleteItem = itemIdFromLink(link)
                self.pendingDeleteAt = now()
                self.pendingDeleteBefore = trackedBagSnapshot()
                self:ScheduleBagAudit()
                if type(orig) == "function" then return orig(...) end
            end
        end
    end
end

-- A pending deletion is confirmed by the bag diff in AuditBags; but deletion has
-- no heuristic flag there, so handle it directly: if the pending item is gone, emit.
function Tracker:ConfirmDelete()
    if not self.pendingDeleteItem then return end
    if self.pendingDeleteAt and (now() - self.pendingDeleteAt) > 5 then
        self.pendingDeleteItem = nil
        self.pendingDeleteBefore = nil
        return
    end
    local itemID = self.pendingDeleteItem
    local before = self.pendingDeleteBefore
    local snap = trackedBagSnapshot()
    local missingGuid
    if before then
        for guid, row in pairs(before.byGuid or {}) do
            if row and row.itemId == itemID and not snap.byGuid[guid] then
                missingGuid = guid
                break
            end
        end
    end
    if missingGuid or ((snap.counts[itemID] or 0) < ((before and before.counts and before.counts[itemID]) or 1)) then
        local me = localPlayer()
        self:EmitForItem(itemID, missingGuid, { type = "deleted", actor = me, at = now() })
        self.pendingDeleteItem = nil
        self.pendingDeleteBefore = nil
    end
end

--------------------------------------------------------------------------------
-- Equip (equipped_finalized)
--------------------------------------------------------------------------------

function Tracker:OnEquipmentChanged(slot)
    if not GetInventoryItemID then return end
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return end
    local me = localPlayer()
    self:EmitForItem(itemID, itemGuidFromEquipmentSlot(slot), { type = "equipped_finalized", actor = me, at = now() })
end

--------------------------------------------------------------------------------
-- OnEnable (Tasks 9.8 + 10 registration)
--------------------------------------------------------------------------------

function Tracker:OnInit()
    -- Session identity is derived from shared observable state (instanceID + difficulty +
    -- time bucket), so there is no per-client serial to seed here.
end

function Tracker:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Events = ns:GetModule("Events")
    if not Events then return end
    local owner = "LootTracker"

    self:HookDeleteDialogs()

    -- Session lifecycle / scope.
    Events:On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
        self:OnWorldChanged(isInitialLogin, isReloadingUi)
    end, owner)
    Events:On("ZONE_CHANGED_NEW_AREA", function() self:OnWorldChanged(false, false) end, owner)
    Events:On("RAID_ROSTER_UPDATE", function() self:ScheduleScopeEval() end, owner)
    Events:On("GROUP_ROSTER_UPDATE", function() self:ScheduleScopeEval() end, owner)
    Events:On("GUILD_ROSTER_UPDATE", function() self:ScheduleScopeEval() end, owner)

    -- Boss attribution.
    Events:On("COMBAT_LOG_EVENT_UNFILTERED", function() self:OnCombatLogEvent() end, owner)
    Events:On("ENCOUNTER_END", function(_, name, _, _, success)
        if success == 1 then self:NoteBossKill(name) end
    end, owner)
    Events:On("BOSS_KILL", function(_, name) self:NoteBossKill(name) end, owner)

    -- Loot capture.
    Events:On("LOOT_OPENED", function() self:OnLootOpened() end, owner)
    Events:On("LOOT_SLOT_CLEARED", function(slot) self:OnLootSlotCleared(slot) end, owner)
    Events:On("START_LOOT_ROLL", function(rollID) self:OnStartLootRoll(rollID) end, owner)
    Events:On("CHAT_MSG_LOOT", function(message) self:TrackLootMessage(message) end, owner)

    -- Bag-driven detectors (trade window / disenchant / guild bank / tier / delete).
    Events:On("BAG_UPDATE_DELAYED", function()
        self:ScheduleBagAudit()
        self:ConfirmDelete()
    end, owner)
    Events:On("PLAYER_EQUIPMENT_CHANGED", function(slot) self:OnEquipmentChanged(slot) end, owner)
    Events:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGuid, spellId)
        self:OnSpellSucceeded(unit, castGuid, spellId)
    end, owner)

    -- NPC interaction (tier turn-in window).
    Events:On("GOSSIP_SHOW", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_GREETING", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_DETAIL", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_PROGRESS", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_COMPLETE", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_FINISHED", function() self:NoteNpcInteraction() end, owner)
    Events:On("QUEST_TURNED_IN", function() self:NoteNpcInteraction() end, owner)

    -- Guild bank.
    Events:On("GUILDBANKFRAME_OPENED", function() self:OnGuildBankOpened() end, owner)
    Events:On("GUILDBANKFRAME_CLOSED", function() self:OnGuildBankClosed() end, owner)
    Events:On("GUILDBANKBAGSLOTS_CHANGED", function() self:ScheduleBagAudit() end, owner)

    -- Vendor (sell to NPC).
    Events:On("MERCHANT_SHOW", function() self:OnMerchantOpened() end, owner)
    Events:On("MERCHANT_CLOSED", function() self:OnMerchantClosed() end, owner)

    -- Trade.
    Events:On("TRADE_SHOW", function() self:OnTradeShow() end, owner)
    Events:On("TRADE_PLAYER_ITEM_CHANGED", function() self:ScheduleTradeSnapshot() end, owner)
    Events:On("TRADE_TARGET_ITEM_CHANGED", function() self:ScheduleTradeSnapshot() end, owner)
    Events:On("TRADE_ACCEPT_UPDATE", function() self:ScheduleTradeSnapshot() end, owner)
    Events:On("UI_INFO_MESSAGE", function(_, message)
        if _G and message == _G.ERR_TRADE_COMPLETE then self:MarkTradeComplete() end
    end, owner)
    Events:On("CHAT_MSG_SYSTEM", function(message)
        if _G and message == _G.ERR_TRADE_COMPLETE then self:MarkTradeComplete() end
    end, owner)
    Events:On("TRADE_CLOSED", function() self:OnTradeClosed() end, owner)

    -- Establish an initial session if we logged in inside an instance.
    self:OnWorldChanged(true, false)
end

return Tracker
