local ADDON, ns = ...

-- Pure auto-mark logic: NO WoW APIs. The WoW-facing module (AutoMarking.lua) feeds these
-- functions live state and applies the result. Headless-tested.
local M = ns:NewModule("AutoMarkEngine")

local MAX_SLOTS = 8
local RAID_KEYS = { "kara","gruul","mag","ssc","tk","hyjal","bt","za","swp" }
local GRUUL_NPC_ID_FIX_VERSION = 1
local GRUUL_NPC_ID_REMAP = {
    [21350] = 19389, -- old mislabeled Lair Brute row -> real Lair Brute
    [18847] = 21350, -- old mislabeled Gronn-Priest row -> real Gronn-Priest
    [19389] = 18847, -- old mislabeled Wild Fel Stalker row -> real Wild Fel Stalker
}

local function now()
    return (time and time()) or os.time()
end

local function emptyRaids()
    local raids = {}
    for _, key in ipairs(RAID_KEYS) do raids[key] = {} end
    return raids
end

local function cloneRaids(src)
    local raids = emptyRaids()
    for _, raidKey in ipairs(RAID_KEYS) do
        local raid = src and src[raidKey]
        if type(raid) == "table" then
            for npcID, list in pairs(raid) do
                if type(list) == "table" then
                    local copy = {}
                    for i = 1, MAX_SLOTS do
                        local marker = tonumber(list[i])
                        if marker and marker >= 1 and marker <= MAX_SLOTS then copy[#copy + 1] = marker end
                    end
                    if #copy > 0 then raids[raidKey][tonumber(npcID) or npcID] = copy end
                elseif type(list) == "number" and list >= 1 and list <= MAX_SLOTS then
                    raids[raidKey][tonumber(npcID) or npcID] = { list }
                end
            end
        end
    end
    return raids
end

local function mergeMarkerLists(dst, src)
    local seen = {}
    for i = 1, MAX_SLOTS do
        local marker = tonumber(dst[i])
        if marker and marker >= 1 and marker <= MAX_SLOTS then seen[marker] = true end
    end
    for i = 1, MAX_SLOTS do
        local marker = tonumber(src[i])
        if marker and marker >= 1 and marker <= MAX_SLOTS and not seen[marker] then
            dst[#dst + 1] = marker
            seen[marker] = true
        end
    end
end

local function remapGruulNpcIds(raids)
    local gruul = raids and raids.gruul
    if type(gruul) ~= "table" then return end

    local moved = {}
    for oldId, newId in pairs(GRUUL_NPC_ID_REMAP) do
        if type(gruul[oldId]) == "table" then
            moved[newId] = gruul[oldId]
            gruul[oldId] = nil
        end
    end

    for newId, list in pairs(moved) do
        if type(gruul[newId]) == "table" then
            mergeMarkerLists(gruul[newId], list)
        else
            gruul[newId] = list
        end
    end
end

function M.emptyRaids()
    return emptyRaids()
end

function M.cloneRaids(src)
    return cloneRaids(src)
end

function M.remapGruulNpcIds(raids)
    remapGruulNpcIds(raids)
end

-- Extract the creature/vehicle/pet npcID from a unit GUID. Player GUIDs and malformed
-- strings return nil. Allocation-free strict pattern.
function M.npcIdFromGuid(guid)
    if not guid then return nil end
    return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$"))
end

-- Pick the marker to apply for a mob, given its priority list, the per-pull registry
-- (activeMarks[markerIndex] = guid that owns it), this mob's guid, and lockAfterUse.
-- Returns (markerIndex, wrapped) or nil. Walks the list: a free slot or an already-ours
-- slot is taken; if all are taken and not locked, free this NPC's whole list and take
-- slot 1 (wrapped=true); if locked, return nil.
function M.pickMarker(markers, activeMarks, guid, lockAfterUse)
    for i = 1, #markers do
        local m = markers[i]
        if not m or m < 1 or m > MAX_SLOTS then
            -- skip malformed slot
        elseif activeMarks[m] == nil or activeMarks[m] == guid then
            return m, false
        end
    end
    if lockAfterUse then return nil end
    for i = 1, #markers do
        local m = markers[i]
        if m and m >= 1 and m <= MAX_SLOTS then activeMarks[m] = nil end
    end
    local first = markers[1]
    if not first or first < 1 or first > MAX_SLOTS then return nil end
    return first, true
end

-- ---- Settings ops (pure; operate on a passed-in settings table) -----------------------

function M.getMarkerList(settings, raidKey, npcID)
    if not (settings and raidKey and npcID) then return {} end
    local raid = settings.raids and settings.raids[raidKey]
    local list = raid and raid[npcID]
    if type(list) ~= "table" then return {} end
    return list
end

-- Set marker at a slot (marker=nil clears). Rejects a duplicate marker within the same NPC.
-- COMPACTS the list into a dense, hole-free sequence (preserving priority order) so that
-- `#list` is always valid — the runtime pickMarker walks `for i=1,#markers`, and a hole at
-- index 1 (from clearing a middle/first slot) would make `#` undefined. (The old addon only
-- trimmed trailing nils, which could leave a hole — this is the improvement.) Drops the
-- npcID key when the list empties.
function M.setMarker(settings, raidKey, npcID, slot, marker)
    if not (settings and raidKey and npcID) then return end
    slot = tonumber(slot) or 1
    if slot < 1 or slot > MAX_SLOTS then return end
    if marker == 0 then marker = nil end
    if marker and (marker < 1 or marker > MAX_SLOTS) then return end
    if not settings.raids then settings.raids = {} end
    if not settings.raids[raidKey] then settings.raids[raidKey] = {} end
    local list = settings.raids[raidKey][npcID]
    if type(list) ~= "table" then list = {}; settings.raids[raidKey][npcID] = list end
    if marker then
        for i = 1, MAX_SLOTS do
            if i ~= slot and list[i] == marker then return end  -- no duplicates within an NPC
        end
    end
    list[slot] = marker
    -- Compact into a dense sequence (preserve order, drop holes).
    local dense = {}
    for i = 1, MAX_SLOTS do if list[i] ~= nil then dense[#dense + 1] = list[i] end end
    for i = 1, MAX_SLOTS do list[i] = dense[i] end
    if #dense == 0 then settings.raids[raidKey][npcID] = nil end
end

function M.clearRaid(settings, raidKey)
    if not (settings and raidKey) then return end
    local t = settings.raids and settings.raids[raidKey]
    if not t then return end
    for k in pairs(t) do t[k] = nil end  -- preserve the table reference
end

function M.normalizeProfile(profile)
    profile.id = profile.id or ("profile-" .. tostring(now()))
    profile.name = (type(profile.name) == "string" and profile.name ~= "" and profile.name) or "Auto Marking Profile"
    profile.createdAt = tonumber(profile.createdAt) or now()
    profile.updatedAt = tonumber(profile.updatedAt) or profile.createdAt
    if profile.modifierEnabled == nil then profile.modifierEnabled = false end
    if profile.modifierKey ~= "ALT" and profile.modifierKey ~= "SHIFT" and profile.modifierKey ~= "CTRL" then
        profile.modifierKey = "ALT"
    end
    if profile.lockAfterUse == nil then profile.lockAfterUse = false end
    profile.raids = cloneRaids(profile.raids)
    return profile
end

-- Idempotent v1 -> v4 migration. v4 stores named profiles; enabled stays global.
function M.migrate(settings)
    if not settings then return end
    if not settings.version then settings.version = 1 end
    if settings.version < 2 then
        if settings.modifierEnabled == nil then settings.modifierEnabled = false end
        if settings.modifierKey == nil then settings.modifierKey = "ALT" end
        settings.version = 2
    end
    if settings.version < 3 then
        if settings.lockAfterUse == nil then settings.lockAfterUse = false end
        if settings.raids then
            for _, raid in pairs(settings.raids) do
                for npcID, value in pairs(raid) do
                    if type(value) == "number" then raid[npcID] = { value } end
                end
            end
        end
        settings.version = 3
    end
    local shouldFixGruulIds = (tonumber(settings.gruulNpcFixVersion) or 0) < GRUUL_NPC_ID_FIX_VERSION
    if shouldFixGruulIds and settings.raids then
        remapGruulNpcIds(settings.raids)
    end
    if settings.version < 4 or type(settings.profiles) ~= "table" or #settings.profiles == 0 then
        local profile = {
            id = "default",
            name = "Default",
            createdAt = 0,
            updatedAt = now(),
            modifierEnabled = settings.modifierEnabled and true or false,
            modifierKey = settings.modifierKey or "ALT",
            lockAfterUse = settings.lockAfterUse and true or false,
            raids = cloneRaids(settings.raids),
        }
        settings.profiles = { M.normalizeProfile(profile) }
        settings.activeProfileId = "default"
        settings.version = 4
    else
        for _, profile in ipairs(settings.profiles) do
            if shouldFixGruulIds then remapGruulNpcIds(profile.raids) end
            M.normalizeProfile(profile)
        end
        settings.activeProfileId = settings.activeProfileId or (settings.profiles[1] and settings.profiles[1].id) or "default"
        settings.version = 4
    end
    settings.gruulNpcFixVersion = GRUUL_NPC_ID_FIX_VERSION
end

if type(ns) == "table" then ns.autoMarkEngine = M end
return M
