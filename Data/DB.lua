local ADDON, ns = ...

local DB = ns:NewModule("DB")

local format = string.format
local strlower = string.lower
local now = _G.time or os.time
local migrate

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepcopy(v) end
    return out
end

-- Backfill any default key the live DB is missing. Additive only — never
-- overwrites an existing value, since renames/restructures are migrations.
local function ensure(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ensure(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function firstNonEmpty(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and v ~= "" then return tostring(v) end
    end
    return nil
end

local function mergeMissing(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = deepcopy(v)
            else
                mergeMissing(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function lootHistoryKey(e)
    if type(e) ~= "table" then return nil end
    return firstNonEmpty(e.lootId, e.id)
        or format("%s:%s:%s:%s", tostring(e.itemId or 0), strlower(tostring(e.player or "")), tostring(e.timestamp or 0), tostring(e.sessionKey or ""))
end

local function ledgerDropKey(drop)
    if type(drop) ~= "table" then return nil end
    return firstNonEmpty(drop.dropInstanceId, drop.lootId, drop.itemGuid)
        or format("%s:%s:%s:%s", tostring(drop.itemId or 0), strlower(tostring(drop.firstHolder or drop.currentHolder or "")), tostring(drop.droppedAt or 0), tostring(drop.sessionKey or ""))
end

local function genericEntryKey(entry)
    if type(entry) ~= "table" then return nil end
    return firstNonEmpty(entry.id, entry.uuid, entry.importId, entry.shareCode, entry.createdAt, entry.timestamp)
        or tostring(entry)
end

local function mergeArray(dst, src, keyFn, mergeHit)
    if type(dst) ~= "table" or type(src) ~= "table" then return 0 end
    local seen = {}
    for i, entry in ipairs(dst) do
        local key = keyFn(entry)
        if key then seen[key] = i end
    end
    local added = 0
    for _, entry in ipairs(src) do
        local key = keyFn(entry)
        local hit = key and seen[key]
        if hit then
            if mergeHit then mergeHit(dst[hit], entry) end
        else
            dst[#dst + 1] = deepcopy(entry)
            if key then seen[key] = #dst end
            added = added + 1
        end
    end
    return added
end

local function mergeLedgerDrop(dst, src)
    mergeMissing(dst, src)
    dst.events = dst.events or {}
    mergeArray(dst.events, src.events or {}, function(ev)
        if type(ev) ~= "table" then return nil end
        return format("%s:%s:%s:%s", tostring(ev.type or ev.kind or ""), tostring(ev.at or ev.time or ""), tostring(ev.by or ""), tostring(ev.to or ev.owner or ""))
    end)
end

local function mergeLegacyDb(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" or dst == src then return end

    migrate(src)
    dst.settings = dst.settings or {}
    mergeMissing(dst.settings, src.settings or {})

    dst.assignments = dst.assignments or {}
    mergeArray(dst.assignments, src.assignments or {}, genericEntryKey)

    dst.lootHistory = dst.lootHistory or {}
    mergeArray(dst.lootHistory, src.lootHistory or {}, lootHistoryKey, mergeMissing)

    dst.raidLootLedger = dst.raidLootLedger or { drops = {}, eventLimit = 1200 }
    src.raidLootLedger = src.raidLootLedger or { drops = {} }
    dst.raidLootLedger.drops = dst.raidLootLedger.drops or {}
    mergeArray(dst.raidLootLedger.drops, src.raidLootLedger.drops or {}, ledgerDropKey, mergeLedgerDrop)
    dst.raidLootLedger.eventLimit = dst.raidLootLedger.eventLimit or src.raidLootLedger.eventLimit
    dst.raidLootLedger.sessionCounter = math.max(tonumber(dst.raidLootLedger.sessionCounter) or 0, tonumber(src.raidLootLedger.sessionCounter) or 0)

    if count(dst.council or {}) == 0 and type(src.council) == "table" then
        dst.council = deepcopy(src.council)
    elseif type(dst.council) == "table" and type(src.council) == "table" then
        dst.council.settings = dst.council.settings or {}
        mergeMissing(dst.council.settings, src.council.settings or {})
        dst.council.history = dst.council.history or {}
        mergeArray(dst.council.history, src.council.history or {}, genericEntryKey)
        dst.council.received = dst.council.received or {}
        mergeArray(dst.council.received, src.council.received or {}, genericEntryKey)
        if dst.council.active == nil and src.council.active ~= nil then dst.council.active = deepcopy(src.council.active) end
    end

    if count(dst.gamba or {}) == 0 and type(src.gamba) == "table" then
        dst.gamba = deepcopy(src.gamba)
    elseif type(dst.gamba) == "table" and type(src.gamba) == "table" then
        dst.gamba.settings = dst.gamba.settings or {}
        mergeMissing(dst.gamba.settings, src.gamba.settings or {})
        dst.gamba.sessions = dst.gamba.sessions or {}
        mergeArray(dst.gamba.sessions, src.gamba.sessions or {}, genericEntryKey)
        dst.gamba.balances = dst.gamba.balances or {}
        mergeMissing(dst.gamba.balances, src.gamba.balances or {})
        dst.gamba.debts = dst.gamba.debts or {}
        mergeMissing(dst.gamba.debts, src.gamba.debts or {})
    end

    dst.lastSync = math.max(tonumber(dst.lastSync) or 0, tonumber(src.lastSync) or 0)
    dst.migrations = dst.migrations or {}
    dst.migrations.legacyDbMergedAt = now()
end

-- Version ladder ported from the shipped addon. Each block is idempotent and
-- only runs when the on-disk version predates it. Existing users are already at
-- the target (7), so for them this is a no-op; the blocks exist to upgrade any
-- older DB still on disk.
migrate = function(db)
    local v = db.version or 0

    if v < 1 then
        db.assignments = db.assignments or {}
        db.lootHistory = db.lootHistory or {}
        db.settings = db.settings or {}
        db.lastSync = db.lastSync or 0
        db.version = 1
    end

    -- v2 dropped the old lootSessions container and folded its items into the
    -- flat lootHistory; legacy session data is discarded after the fold.
    if v < 2 then
        local existing = {}
        for _, e in ipairs(db.lootHistory or {}) do
            if e.itemId and e.player and e.timestamp then
                existing[format("%d-%s-%d", e.itemId, strlower(e.player), e.timestamp)] = e
            end
        end
        for _, session in pairs(db.lootSessions or {}) do
            for _, item in ipairs(session.loot or {}) do
                local itemId = item.itemId or 0
                local player = item.lootedBy or ""
                local ts = item.droppedAt or session.startTime or 0
                local key = format("%d-%s-%d", itemId, strlower(player), ts)
                local hit = existing[key]
                if hit then
                    hit.assignedTo = hit.assignedTo or item.assignedTo
                    hit.assignedBy = hit.assignedBy or item.assignedBy
                    hit.assignedAt = hit.assignedAt or item.assignedAt
                    hit.status = hit.status or item.status
                    hit.tradedAt = hit.tradedAt or item.tradedAt
                    hit.lootId = hit.lootId or item.lootId
                else
                    db.lootHistory[#db.lootHistory + 1] = {
                        lootId = item.lootId,
                        itemId = itemId,
                        itemName = item.itemName,
                        itemLink = item.itemLink,
                        itemQuality = item.itemQuality,
                        itemIcon = item.itemIcon,
                        player = player,
                        sourceType = item.sourceType,
                        boss = item.bossName,
                        raid = session.raidName,
                        timestamp = ts,
                        assignedTo = item.assignedTo,
                        assignedBy = item.assignedBy,
                        assignedAt = item.assignedAt,
                        status = item.status or "pending",
                        tradedAt = item.tradedAt,
                    }
                end
            end
        end
        for _, e in ipairs(db.lootHistory) do
            e.status = e.status or "pending"
        end
        db.lootSessions = nil
        db.currentSessionId = nil
        if db.settings and db.settings.permissionSettings then
            db.settings.permissionSettings.canVoteMaxRank = nil
            db.settings.permissionSettings.canSeeVotesMaxRank = nil
            db.settings.permissionSettings.canStartSessionMaxRank = nil
            db.settings.permissionSettings.canEndSessionMaxRank = nil
        end
        if db.settings and db.settings.lootSettings then
            db.settings.lootSettings.officerRankThreshold = nil
        end
        db.version = 2
    end

    if v < 4 then
        db.version = 4
    end

    -- WoW's CHAT_MSG_LOOT can fire duplicate messages whose player name is a
    -- lootHistory hyperlink ("|HlootHistory:8|h..."); those entries are garbage.
    if v < 5 then
        local cleaned = {}
        for _, e in ipairs(db.lootHistory or {}) do
            if not (e.player and e.player:find("|HlootHistory")) then
                cleaned[#cleaned + 1] = e
            end
        end
        db.lootHistory = cleaned
        db.version = 5
    end

    if v < 6 then
        for _, e in ipairs(db.lootHistory or {}) do
            if not e.lootId and e.itemId and e.player then
                e.lootId = format("%d-%s-%d", e.itemId, strlower(e.player or "unknown"), e.timestamp or 0)
            end
        end
        db.version = 6
    end

    -- v7 normalizes every entry to carry a sessionKey so all grouping keys off it
    -- with no fallback logic downstream.
    if v < 7 then
        local BUCKET = 1800
        for _, e in ipairs(db.lootHistory or {}) do
            if not e.sessionKey or e.sessionKey == "" then
                local instId = e.instanceId or 0
                local diffId = e.difficultyId or 0
                e.sessionKey = format("%d-%d-%d", instId, diffId, math.floor((e.timestamp or 0) / BUCKET))
            end
            if not e.instanceId then e.instanceId = 0 end
            if not e.difficultyId then e.difficultyId = 0 end
            if not e.originalInstanceId then e.originalInstanceId = e.instanceId end
            if not e.originalSessionKey then e.originalSessionKey = e.sessionKey end
        end
        db.version = 7
    end

    -- v8 adds the physical raid-loot ledger. This is intentionally separate
    -- from lootHistory: loot chat records first holder; the ledger records
    -- current/final owner and transfer events.
    if v < 8 then
        db.raidLootLedger = db.raidLootLedger or { drops = {}, eventLimit = 1200 }
        db.raidLootLedger.drops = db.raidLootLedger.drops or {}
        db.raidLootLedger.eventLimit = db.raidLootLedger.eventLimit or 1200
        db.raidLootLedger.sessionCounter = db.raidLootLedger.sessionCounter or 0
        db.settings = db.settings or {}
        db.settings.raidLootLedger = db.settings.raidLootLedger or {}
        if db.settings.raidLootLedger.trackDungeonLoot == nil then db.settings.raidLootLedger.trackDungeonLoot = true end
        db.settings.raidLootLedger.dungeonMinQuality = db.settings.raidLootLedger.dungeonMinQuality or 3
        db.settings.raidLootLedger.raidMinQuality = db.settings.raidLootLedger.raidMinQuality or 4
        if db.settings.raidLootLedger.allowGargulFallback == nil then db.settings.raidLootLedger.allowGargulFallback = false end
        db.version = 8
    end

    db.settings = db.settings or {}
    db.settings.raidLootLedger = db.settings.raidLootLedger or {}
    if db.settings.raidLootLedger.allowGargulFallback == nil then db.settings.raidLootLedger.allowGargulFallback = false end

    if v < 9 then
        db.gamba = db.gamba or {
            version = 1,
            current = nil,
            sessions = {},
            balances = {},
            debts = {},
            settings = {
                defaultAmount = 100,
                channel = "AUTO",
                announce = true,
                autoRoll = false,
            },
        }
        db.version = 9
    end

    if v < 10 then
        db.council = db.council or {
            active = nil,
            history = {},
            received = {},
            settings = {
                autoShareOnImport = true,
                announceImports = true,
            },
        }
        db.version = 10
    end
end

function DB:Load()
    local legacyDb = type(_G.iddqd_appDB) == "table" and _G.iddqd_appDB or nil
    local legacyDevDb = type(_G.iddqd_appDevDB) == "table" and _G.iddqd_appDevDB or nil

    if type(_G.iddqdDB) ~= "table" and legacyDb then
        _G.iddqdDB = legacyDb
    elseif type(_G.iddqdDB) ~= "table" and legacyDevDb then
        _G.iddqdDB = legacyDevDb
    end

    if type(_G.iddqdDB) ~= "table" then
        _G.iddqdDB = deepcopy(ns.DB_DEFAULTS)
    else
        if legacyDb then mergeLegacyDb(_G.iddqdDB, legacyDb) end
        if legacyDevDb then mergeLegacyDb(_G.iddqdDB, legacyDevDb) end
        migrate(_G.iddqdDB)
        ensure(_G.iddqdDB, ns.DB_DEFAULTS)
    end
    self.db = _G.iddqdDB
end

function DB:OnInit()
    self:Load()
    ns:Debug("DB loaded at version", self.db.version)
end

function DB:Get(key) return self.db and self.db.settings and self.db.settings[key] end
function DB:Set(key, value) if self.db and self.db.settings then self.db.settings[key] = value end end
