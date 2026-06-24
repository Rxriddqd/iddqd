local ADDON, ns = ...
local Store = ns:NewModule("LootStore")
-- Local data-schema version. Bump on any breaking change to the drop/session/event shape so
-- MigrateOrReset wipes incompatible old data on load. v2 = 1.2.0 loot-format break (loot-table
-- dropIDs, name normalization, instance whitelist) — clears pre-1.2.0 records that used the old
-- slot-based dropIDs / un-normalized names.
local PROTOCOL_VERSION = 2
local LIFECYCLE_ACTIVITY_WINDOW = 72 * 60 * 60

local function now() return (time and time()) or os.time() end

function Store:DB()
    local db = ns:GetModule("DB")
    return db and db.db or nil
end

function Store:Get()
    local db = self:DB()
    if not db then return nil end
    db.raidLootLedger = db.raidLootLedger or { protocolVersion = PROTOCOL_VERSION, drops = {}, sessions = {}, settings = { guildRaidThreshold = 0.60 } }
    self:MigrateOrReset()
    local r = db.raidLootLedger
    r.drops = r.drops or {}
    r.sessions = r.sessions or {}
    r.hiddenSessions = r.hiddenSessions or {}
    r.settings = r.settings or { guildRaidThreshold = 0.60 }
    return r
end

function Store:MigrateOrReset()
    local db = self:DB()
    if not db or not db.raidLootLedger then return end
    local stored = tonumber(db.raidLootLedger.protocolVersion or 0) or 0
    if stored < PROTOCOL_VERSION then
        ns:Debug("LootStore reset", tostring(stored), "->", tostring(PROTOCOL_VERSION))
        db.raidLootLedger.drops = {}
        db.raidLootLedger.sessions = {}
        db.raidLootLedger.hiddenSessions = {}
        db.raidLootLedger.protocolVersion = PROTOCOL_VERSION
        db.raidLootLedger.settings = db.raidLootLedger.settings or { guildRaidThreshold = 0.60 }
    end
end

-- Legacy deterministic drop identity = bossGUID:itemID. New loot-window capture uses
-- Tracker:ResolveDropForItem instead, because it can append a copy index when one corpse
-- drops multiple copies of the same item/token. Keep this helper for older callers/tests.
function Store:DropID(bossGUID, itemID, lootSlot)
    if not bossGUID or bossGUID == "" or not itemID then return nil end
    return tostring(bossGUID) .. ":" .. tostring(itemID)
end

-- Loot-table identity: instanceID + boss + itemID, computed identically on every tracker
-- regardless of HOW the item was observed (own loot window vs. another player's loot chat
-- line). This is the PREFERRED id whenever the item is in the loot table — it lets two
-- trackers in the same raid converge on ONE record for a drop even though one looted it and
-- the other only saw the chat message. (Slot/GUID are NOT used: they differ per observer.)
function Store:LootTableDropID(instanceID, bossName, itemID)
    if not itemID then return nil end
    bossName = tostring(bossName or "?")
    return "LT:" .. tostring(instanceID or 0) .. ":" .. bossName .. ":" .. tostring(itemID)
end

-- Fallback identity when the boss GUID is unavailable: time-bucketed (30s) for clock-skew tolerance.
function Store:FallbackDropID(encounterName, serverTime, itemID)
    encounterName = tostring(encounterName or "?")
    local bucket = math.floor((tonumber(serverTime) or 0) / 30)
    return encounterName .. ":" .. tostring(bucket) .. ":" .. tostring(itemID)
end

function Store:Drops() local r = self:Get(); return r and r.drops or {} end
function Store:Sessions() local r = self:Get(); return r and r.sessions or {} end

-- Deterministic event key for idempotent dedup. coarseAt buckets the timestamp (5s)
-- so the same logical event reported by two clients with slightly different clocks collides.
function Store:EventKey(ev)
    local coarse = math.floor((tonumber(ev.at) or 0) / 5)
    return tostring(ev.type) .. ":" .. tostring(ev.actor or "") .. ":" .. tostring(ev.target or "") .. ":" .. tostring(coarse)
end

function Store:EnsureDrop(dropID, meta)
    if not dropID then return nil end
    local drops = self:Drops()
    local drop = drops[dropID]
    if not drop then
        local t = now()
        drop = { dropID = dropID, events = {}, droppedAt = t, lastActivityAt = t }
        drops[dropID] = drop
    end
    meta = meta or {}
    for _, field in ipairs({ "sessionID","itemId","itemLink","itemName","quality","icon","itemGUID","bossName" }) do
        if drop[field] == nil and meta[field] ~= nil then drop[field] = meta[field] end
    end
    return drop
end

local LIFECYCLE_EVENTS = {
    traded = true,
    trade_window = true,
    window_expired = true,
    bop_finalized = true,
    equipped_finalized = true,
    deleted = true,
    disenchanted = true,
    vendored = true,
    guild_bank = true,
    tier_turnin = true,
    recipe_learned = true,
}

function Store:LifecycleWindowSeconds()
    local r = self:Get()
    local n = r and r.settings and tonumber(r.settings.lifecycleActivityWindowSeconds)
    return (n and n > 0) and n or LIFECYCLE_ACTIVITY_WINDOW
end

function Store:ShouldAcceptEvent(drop, ev)
    if not drop or type(ev) ~= "table" or not ev.type then return false end
    if not LIFECYCLE_EVENTS[ev.type] then return true end
    local t = now()
    local last = tonumber(drop.lastActivityAt or drop.droppedAt or t) or t
    return (t - last) <= self:LifecycleWindowSeconds()
end

-- Append an immutable event. Returns true if newly added, false if duplicate / unknown drop.
function Store:AddEvent(dropID, ev)
    local drop = self:Drops()[dropID]
    if not drop or type(ev) ~= "table" or not ev.type then return false end
    if not self:ShouldAcceptEvent(drop, ev) then return false end
    drop.events = drop.events or {}
    local key = self:EventKey(ev)
    if drop.events[key] then return false end
    ev._key = key   -- stable, client-identical tiebreaker for ComputeState's sort
    drop.events[key] = ev
    drop.lastActivityAt = now()
    return true
end

-- Terminal event precedence (higher wins when multiple terminal events exist).
-- Specific dispositions (deleted/disenchanted/vendored) outrank a plain finalize so that,
-- e.g., a no-window BoP item that is finalized-on-loot and LATER disenchanted shows
-- "disenchanted", not "finalized".
local TERMINAL_RANK = {
    deleted = 5, disenchanted = 5, vendored = 5, guild_bank = 4,
    bop_finalized = 3, equipped_finalized = 3, recipe_learned = 3, tier_turnin = 3, window_expired = 1,
}
local TERMINAL_STATUS = {
    deleted = "deleted", disenchanted = "disenchanted", vendored = "vendored",
    guild_bank = "guild_bank",
    bop_finalized = "finalized", equipped_finalized = "finalized", recipe_learned = "finalized", tier_turnin = "finalized", window_expired = "finalized",
}

-- Fold the append-only event log into display state. Deterministic + order-independent.
function Store:ComputeState(drop)
    local state = { status = "pending", currentHolder = nil, finalOwner = nil, tradeWindow = nil }
    if not drop or not drop.events then return state end
    local evs = {}
    for _, e in pairs(drop.events) do evs[#evs + 1] = e end
    table.sort(evs, function(a, b)
        local ta, tb = (tonumber(a.at) or 0), (tonumber(b.at) or 0)
        if ta ~= tb then return ta < tb end
        return tostring(a._key or "") < tostring(b._key or "")   -- stable, identical across clients
    end)
    local terminal, terminalRank, terminalActor
    for _, e in ipairs(evs) do
        if e.type == "looted" then
            state.status = "obtained"; state.currentHolder = e.actor; state.finalOwner = state.finalOwner or e.actor
        elseif e.type == "traded" then
            state.currentHolder = e.target or state.currentHolder; state.finalOwner = e.target or state.finalOwner; state.status = "traded"
        elseif e.type == "trade_window" then
            state.tradeWindow = tonumber(e.remaining) or state.tradeWindow
        elseif e.type == "tier_turnin" then
            state.status = "finalized"; state.currentHolder = e.actor or state.currentHolder; state.finalOwner = e.actor or state.finalOwner
        elseif e.type == "response" then
            -- voting; does not change ownership state
        else
            local rank = TERMINAL_RANK[e.type]
            if rank and (not terminalRank or rank >= terminalRank) then
                terminal = e; terminalRank = rank; terminalActor = e.actor
            end
        end
    end
    if terminal then
        state.status = TERMINAL_STATUS[terminal.type] or state.status
        if terminal.type == "guild_bank" then state.currentHolder = "Guild Bank"; state.finalOwner = nil
        elseif terminal.type == "disenchanted" or terminal.type == "deleted" or terminal.type == "vendored" then state.finalOwner = nil end
        state.terminalActor = terminalActor
    end
    return state
end

-- Pure: decide a session's share scope. Never demotes an existing guild session.
--
-- `eligible` (optional, default true for backward-compat) gates guild scope on the SESSION TYPE:
-- only eligible sessions (an allowed raid zone — never a 5-man dungeon) may ever be shared. When
-- a session is not eligible it is ALWAYS personal, regardless of guild ratio, so 5-man dungeon
-- loot stays private to the player. The caller (Tracker) computes eligibility from the instance.
function Store:DecideScope(guildCount, raidSize, threshold, currentScope, eligible)
    if currentScope == "guild" then return "guild" end
    if eligible == false then return "personal" end   -- not a shareable raid -> never shared
    guildCount = tonumber(guildCount) or 0
    raidSize = tonumber(raidSize) or 0
    threshold = tonumber(threshold) or 0.60
    if raidSize <= 0 then return "personal" end
    return (guildCount / raidSize) >= threshold and "guild" or "personal"
end

function Store:EnsureSession(sessionID, meta)
    if not sessionID then return nil end
    local sessions = self:Sessions()
    local sess = sessions[sessionID]
    if not sess then
        sess = { sessionID = sessionID, scope = "personal", startedAt = now() }
        sessions[sessionID] = sess
    end
    meta = meta or {}
    for _, field in ipairs({ "scope","instance","instanceType","instanceId","difficulty","difficultyId","startedAt","guildRatioAtStart" }) do
        if meta[field] ~= nil then sess[field] = meta[field] end
    end
    return sess
end

function Store:HiddenSessions()
    local r = self:Get()
    r.hiddenSessions = r.hiddenSessions or {}
    return r.hiddenSessions
end

function Store:IsSessionHidden(sessionID)
    return self:HiddenSessions()[sessionID] ~= nil
end

function Store:UnhideSession(sessionID)
    self:HiddenSessions()[sessionID] = nil
end

-- Hide a session locally so sync will not pull it back into the UI. With purge=true, also
-- remove the retained drops/session shell. Without purge, data remains available for lifecycle
-- tracking and for serving guildmates who request the session.
function Store:HideSession(sessionID, purge)
    if not sessionID then return 0 end
    self:HiddenSessions()[sessionID] = now()
    local removed = 0
    if purge then
        local drops = self:Drops()
        for dropID, drop in pairs(drops) do
            if drop.sessionID == sessionID then
                drops[dropID] = nil
                removed = removed + 1
            end
        end
        self:Sessions()[sessionID] = nil
    end
    return removed
end

function Store:PromoteSession(sessionID)
    local sess = self:Sessions()[sessionID]
    if not sess then return false end
    if sess.scope ~= "guild" then sess.scope = "guild"; sess.promotedAt = now() end
    return true
end

function Store:IsGuildSession(sessionID)
    local sess = self:Sessions()[sessionID]
    return (sess and sess.scope == "guild") and true or false
end

local function shortHash(value)
    value = tostring(value or "")
    local hash = 5381
    for i = 1, #value do hash = ((hash * 33) + value:byte(i)) % 2147483647 end
    return tostring(hash)
end
ns.LootStoreShortHash = shortHash  -- shared with Sync for checksum agreement

-- Per guild-session hash over its drops + each drop's event-key set (sorted for determinism).
function Store:SessionHash(sessionID)
    local parts = {}
    for dropID, drop in pairs(self:Drops()) do
        if drop.sessionID == sessionID then
            local keys = {}
            for k in pairs(drop.events or {}) do keys[#keys + 1] = k end
            table.sort(keys)
            parts[#parts + 1] = dropID .. "=" .. table.concat(keys, ",")
        end
    end
    table.sort(parts)
    return shortHash(table.concat(parts, "|"))
end

-- Manifest = { [guildSessionID] = sessionHash } (personal sessions excluded).
function Store:Manifest()
    local out = {}
    for sessionID, sess in pairs(self:Sessions()) do
        if sess.scope == "guild" then out[sessionID] = self:SessionHash(sessionID) end
    end
    return out
end

-- True if we hold this session as a guild session at exactly `hash` (relay candidacy, Task 8).
function Store:HasCachedSession(sessionID, hash)
    if not self:IsGuildSession(sessionID) then return false end
    return self:SessionHash(sessionID) == hash
end

ns.LootStoreNow = now
