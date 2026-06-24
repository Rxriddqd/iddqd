local ADDON, ns = ...
local Store = ns:NewModule("LootDistStore")
local PROTOCOL_VERSION = 1

local function now() return (GetTime and GetTime()) or (time and time()) or (os and os.time and os.time()) or 0 end
local function Players() return ns.GetModule and ns:GetModule("Players") or nil end
local function pkey(player)
    local players = Players()
    if players and players.ShortName then return players:ShortName(player) end
    return tostring(player or ""):match("^([^-]+)") or tostring(player or "")
end
local function shortLower(name) return pkey(name):lower() end

function Store:DB() local db = ns:GetModule("DB"); return db and db.db or nil end

function Store:Get()
    local db = self:DB(); if not db then return nil end
    db.lootDistribution = db.lootDistribution or { protocolVersion = PROTOCOL_VERSION, entries = {} }
    local r = db.lootDistribution
    r.entries = r.entries or {}
    r.tombstones = r.tombstones or {}   -- [id] = deletedAt (epoch); blocks re-create, prunes by age
    r.protocolVersion = r.protocolVersion or PROTOCOL_VERSION
    return r
end

function Store:Entries() local r = self:Get(); return r and r.entries or {} end

-- Deterministic loot-list id. Item GUID is best (unique per physical item); else a
-- time-bucketed (30s) itemID:looter id so two officers converge on one entry.
function Store:ListId(itemGUID, itemID, looter, at)
    if itemGUID and itemGUID ~= "" then return tostring(itemGUID) end
    if not itemID then return nil end
    local bucket = math.floor((tonumber(at) or now()) / 30)
    return tostring(itemID) .. ":" .. shortLower(looter) .. ":" .. tostring(bucket)
end

function Store:EnsureEntry(id, meta)
    if not id then return nil end
    meta = meta or {}
    local entries = self:Entries()
    local e = entries[id]
    if not e then
        -- A deletion tombstone blocks re-creation: an in-flight create/update from another
        -- client must NOT resurrect an entry an officer removed. (Tombstones expire via Prune.)
        if self:IsTombstoned(id) then return nil end
        -- A loot entry must identify an item. Refuse to CREATE a nameless/itemId-less entry
        -- (that produced "Item nil" rows); updates to an existing entry are still allowed.
        if meta.itemId == nil then return nil end
        e = { id = id, responses = {}, addedAt = now(), traded = false, quantity = 1 }
        entries[id] = e
    end
    e.quantity = tonumber(e.quantity) or 1
    for _, f in ipairs({ "itemId","itemLink","itemName","quality","icon","holder","addedBy","source","tradeWindowEndsAt" }) do
        if e[f] == nil and meta[f] ~= nil then e[f] = meta[f] end
    end
    return e
end

-- Quantity helpers: adding the same item again bumps quantity (one row, "xN") rather than making
-- a second row. Decrement (on Remove) lowers it; the caller deletes the entry when it hits 0.
function Store:SetQuantity(id, q)
    local e = self:Entries()[id]; if not e then return end
    e.quantity = math.max(0, math.floor(tonumber(q) or 1))
end
function Store:IncrementQuantity(id, by)
    local e = self:Entries()[id]; if not e then return 1 end
    e.quantity = (tonumber(e.quantity) or 1) + (tonumber(by) or 1)
    return e.quantity
end
function Store:DecrementQuantity(id, by)
    local e = self:Entries()[id]; if not e then return 0 end
    e.quantity = math.max(0, (tonumber(e.quantity) or 1) - (tonumber(by) or 1))
    return e.quantity
end

-- Deletion is convergent: removing an entry drops the live record AND records a timestamped
-- tombstone so the delete wins over older create/update messages and survives re-sync (a bare
-- delete would be undone by the next BroadcastEntry from a client that still had the entry).
function Store:Tombstones()
    local r = self:Get(); if not r then return {} end
    r.tombstones = r.tombstones or {}
    return r.tombstones
end

function Store:IsTombstoned(id)
    if not id then return false end
    return self:Tombstones()[id] ~= nil
end

-- Forget a tombstone so the id can be (re-)created. Used by INTENTIONAL manual adds: an officer
-- deliberately re-adding an item must always succeed, even if that id was previously removed/
-- cleared (otherwise re-looting the same item next week stays blocked by the old tombstone).
function Store:ClearTombstone(id)
    if not id then return end
    self:Tombstones()[id] = nil
end

-- Mark an id deleted at time `at`. Idempotent + last-write-wins by `at`. Returns true if the
-- tombstone is now the authority (i.e. the delete applied).
function Store:RemoveEntry(id, at)
    if not id then return false end
    at = tonumber(at) or now()
    local tombs = self:Tombstones()
    local prev = tonumber(tombs[id])
    if prev and prev >= at then
        -- An equal/newer tombstone already exists; just make sure the live entry is gone.
        self:Entries()[id] = nil
        return false
    end
    tombs[id] = at
    self:Entries()[id] = nil
    return true
end

-- Drop tombstones older than maxAge seconds (default 1 day) so the table can't grow forever.
-- An id this old is no longer at risk of a stale re-create racing in.
function Store:PruneTombstones(maxAge)
    maxAge = tonumber(maxAge) or 86400
    local cutoff = now() - maxAge
    local tombs = self:Tombstones()
    for id, at in pairs(tombs) do
        if (tonumber(at) or 0) < cutoff then tombs[id] = nil end
    end
end

function Store:SetResponse(id, player, classFile, response, note, at)
    local e = self:Entries()[id]; if not e or not player or not response then return false end
    e.responses = e.responses or {}
    e.responseClears = e.responseClears or {}
    local key = pkey(player):lower()
    at = tonumber(at) or now()
    if (tonumber(e.responseClears[key]) or 0) >= at then return false end
    local prev = e.responses[key]
    if prev and (tonumber(prev.at) or 0) >= at then return false end
    e.responses[key] = { player = player, classFile = classFile, response = response, note = note or "", at = at }
    return true
end

function Store:ClearResponse(id, player, at)
    local e = self:Entries()[id]; if not e or not player then return false end
    e.responses = e.responses or {}
    e.responseClears = e.responseClears or {}
    local key = pkey(player):lower()
    at = tonumber(at) or now()
    if (tonumber(e.responseClears[key]) or 0) >= at then return false end
    local prev = e.responses[key]
    if prev and (tonumber(prev.at) or 0) >= at then return false end
    e.responseClears[key] = at
    e.responses[key] = nil
    return true
end

-- Award one copy to `winner`. With quantity>1 an item can be awarded multiple times (one per
-- copy, to different players). Awards accumulate in e.awards; e.award mirrors the FIRST award so
-- existing single-award sync/display keeps working. Returns true if an award was recorded.
function Store:SetAward(id, winner, awardedBy, at, winnerClass)
    local e = self:Entries()[id]; if not e or not winner then return false end
    at = tonumber(at) or now()
    e.awards = e.awards or {}
    -- Don't award the same player twice for one entry, and don't exceed the quantity.
    local wkey = pkey(winner):lower()
    for _, a in ipairs(e.awards) do
        if pkey(a.winner):lower() == wkey then return false end
    end
    if #e.awards >= (tonumber(e.quantity) or 1) then return false end
    e.awards[#e.awards + 1] = { winner = winner, awardedBy = awardedBy, awardedAt = at, winnerClass = winnerClass }
    e.award = e.awards[1]   -- mirror first award (back-compat with single-award sync/display)
    return true
end

function Store:AwardCount(id)
    local e = self:Entries()[id]; if not e then return 0 end
    return e.awards and #e.awards or (e.award and 1 or 0)
end

-- True when every copy has been awarded.
function Store:IsFullyAwarded(id)
    local e = self:Entries()[id]; if not e then return false end
    return self:AwardCount(id) >= (tonumber(e.quantity) or 1)
end

-- Remove the most recent award (used if Remove decrements an awarded copy). Keeps e.award synced.
function Store:PopAward(id)
    local e = self:Entries()[id]; if not e or not e.awards or #e.awards == 0 then return end
    table.remove(e.awards)
    e.award = e.awards[1]
end

function Store:SetTraded(id, v) local e = self:Entries()[id]; if e then e.traded = v and true or false end end

-- Items with copies still to award stay on top; FULLY-awarded items sink to the bottom. Within
-- each group, newest first. (An x2 item with 1 award stays on top so the 2nd copy is visible.)
function Store:SortedEntries()
    local list = {}
    for _, e in pairs(self:Entries()) do list[#list + 1] = e end
    local function full(e) return self:AwardCount(e.id) >= (tonumber(e.quantity) or 1) and self:AwardCount(e.id) > 0 end
    table.sort(list, function(a, b)
        local af, bf = full(a), full(b)
        if af ~= bf then return (not af) end                        -- not-fully-awarded first
        local aat = (a.award and a.award.awardedAt) or a.addedAt or 0
        local bat = (b.award and b.award.awardedAt) or b.addedAt or 0
        if aat ~= bat then return aat > bat end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

local ARMOR_BY_CLASS = {
    ["Cloth"]   = { MAGE=true, PRIEST=true, WARLOCK=true, DRUID=true, SHAMAN=true, PALADIN=true, WARRIOR=true, ROGUE=true, HUNTER=true, DEATHKNIGHT=true },
    ["Leather"] = { DRUID=true, ROGUE=true, SHAMAN=true, PALADIN=true, WARRIOR=true, HUNTER=true, DEATHKNIGHT=true, MONK=true },
    ["Mail"]    = { HUNTER=true, SHAMAN=true, PALADIN=true, WARRIOR=true, DEATHKNIGHT=true },
    ["Plate"]   = { WARRIOR=true, PALADIN=true, DEATHKNIGHT=true },
    ["Shields"] = { WARRIOR=true, PALADIN=true, SHAMAN=true },
    ["Miscellaneous"] = "ALL", ["Sigils"] = "ALL", ["Librams"] = "ALL", ["Idols"] = "ALL", ["Totems"] = "ALL", ["Relics"] = "ALL",
}
local WEAPON_BY_CLASS = {
    ["One-Handed Swords"] = { WARRIOR=true, PALADIN=true, ROGUE=true, HUNTER=true, MAGE=true, WARLOCK=true, DEATHKNIGHT=true },
    ["Two-Handed Swords"] = { WARRIOR=true, PALADIN=true, HUNTER=true, DEATHKNIGHT=true },
    ["One-Handed Axes"]   = { WARRIOR=true, PALADIN=true, ROGUE=true, HUNTER=true, SHAMAN=true, DEATHKNIGHT=true },
    ["Two-Handed Axes"]   = { WARRIOR=true, PALADIN=true, HUNTER=true, SHAMAN=true, DEATHKNIGHT=true },
    ["One-Handed Maces"]  = { WARRIOR=true, PALADIN=true, ROGUE=true, SHAMAN=true, PRIEST=true, DRUID=true, DEATHKNIGHT=true },
    ["Two-Handed Maces"]  = { WARRIOR=true, PALADIN=true, SHAMAN=true, DRUID=true, DEATHKNIGHT=true },
    ["Daggers"]           = { ROGUE=true, WARRIOR=true, HUNTER=true, MAGE=true, PRIEST=true, WARLOCK=true, SHAMAN=true, DRUID=true },
    ["Fist Weapons"]      = { WARRIOR=true, ROGUE=true, HUNTER=true, SHAMAN=true, DRUID=true },
    ["Polearms"]          = { WARRIOR=true, PALADIN=true, HUNTER=true, DEATHKNIGHT=true, DRUID=true },
    ["Staves"]            = { MAGE=true, PRIEST=true, WARLOCK=true, DRUID=true, SHAMAN=true, HUNTER=true, WARRIOR=true },
    ["Bows"]={HUNTER=true,WARRIOR=true,ROGUE=true}, ["Crossbows"]={HUNTER=true,WARRIOR=true,ROGUE=true}, ["Guns"]={HUNTER=true,WARRIOR=true,ROGUE=true},
    ["Wands"]={MAGE=true,PRIEST=true,WARLOCK=true}, ["Thrown"]={WARRIOR=true,ROGUE=true,HUNTER=true},
}
local function classUpper(c) return tostring(c or ""):upper() end
function Store:ArmorUsable(subType, classFile)
    local set = ARMOR_BY_CLASS[subType]; if set == nil then return true end
    if set == "ALL" then return true end
    return set[classUpper(classFile)] == true
end
function Store:WeaponUsable(subType, classFile)
    local set = WEAPON_BY_CLASS[subType]; if set == nil then return true end
    return set[classUpper(classFile)] == true
end

-- Pure auto-add gate. ctx predicates resolved by Detect (IO).
function Store:ShouldAutoAdd(ctx)
    ctx = ctx or {}
    if ctx.isLeaderAssist ~= true then return false end
    if ctx.assignedInRaid == true then return false end
    if ctx.alreadyPresent == true then return false end
    if ctx.alreadyAwarded == true then return false end
    return true
end

ns.LootDistStoreNow = now
