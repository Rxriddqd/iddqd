local ADDON, ns = ...

local Codec = ns:NewModule("AutoMarkingProfileCodec")

local b64url = ns.raid_assignments_b64url
local json = ns.raid_assignments_json
local Engine = ns.autoMarkEngine

local PREFIX = "!iddqd-am!"
local WIRE_VERSION = 2
local MIN_WIRE_VERSION = 1
local MAX_NPCS = 1000
local RAID_KEYS = { "kara","gruul","mag","ssc","tk","hyjal","bt","za","swp" }

local function now()
    return (time and time()) or os.time()
end

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function knownNpcSet()
    if Codec._knownNpcSet then return Codec._knownNpcSet end
    local out = {}
    local data = ns.autoMarkingNPCs or {}
    for _, raidKey in ipairs(RAID_KEYS) do
        out[raidKey] = {}
        local raid = data[raidKey]
        for _, npc in ipairs((raid and raid.npcs) or {}) do
            if npc.id then out[raidKey][tonumber(npc.id)] = true end
        end
    end
    Codec._knownNpcSet = out
    return out
end

local function raidKeySet()
    local out = {}
    for _, key in ipairs(RAID_KEYS) do out[key] = true end
    return out
end
local VALID_RAID = raidKeySet()

local function normalizeRaids(input, forWire)
    local known = knownNpcSet()
    local out, total = {}, 0
    for _, raidKey in ipairs(RAID_KEYS) do out[raidKey] = {} end
    if input == nil then return out end
    if type(input) ~= "table" then return nil, "Profile raids are invalid." end

    for raidKey, raid in pairs(input) do
        if not VALID_RAID[raidKey] then return nil, "Profile targets an unknown raid." end
        if type(raid) ~= "table" then return nil, "Profile raid data is invalid." end
        for rawNpcID, rawList in pairs(raid) do
            local npcID = tonumber(rawNpcID)
            if not npcID or not known[raidKey][npcID] then
                return nil, "Profile targets unknown NPCs. Update iddqd and try again."
            end
            if type(rawList) ~= "table" then return nil, "Profile marker data is invalid." end
            local list = {}
            for i = 1, 8 do
                local marker = tonumber(rawList[i])
                if marker ~= nil then
                    if marker < 1 or marker > 8 then return nil, "Profile contains an invalid raid marker." end
                    list[#list + 1] = marker
                end
            end
            if #list > 0 then
                total = total + 1
                if total > MAX_NPCS then return nil, "Profile is too large to import." end
                out[raidKey][forWire and tostring(npcID) or npcID] = list
            end
        end
    end
    return out
end

function Codec:EncodeProfile(profile, author)
    if not (profile and profile.raids) then return nil, "No auto-marking profile selected." end
    local raids, err = normalizeRaids(profile.raids, true)
    if not raids then return nil, err end
    local payload = {
        v = WIRE_VERSION,
        type = "autoMarkingProfile",
        name = profile.name or "Auto Marking Profile",
        author = author,
        createdAt = now(),
        profile = {
            modifierEnabled = profile.modifierEnabled and true or false,
            modifierKey = profile.modifierKey or "ALT",
            lockAfterUse = profile.lockAfterUse and true or false,
            raids = raids,
        },
    }
    local ok, encodedJson = pcall(json.encode, payload)
    if not ok or not encodedJson then return nil, "Could not encode profile." end
    local body = b64url.encode(encodedJson)
    if not body then return nil, "Could not encode profile." end
    return PREFIX .. body
end

function Codec:DecodeString(importString)
    importString = trim(importString)
    if importString:sub(1, #PREFIX) ~= PREFIX then return nil, "Not an iddqd auto-marking profile." end
    local raw = b64url.decode(importString:sub(#PREFIX + 1))
    if not raw then return nil, "Could not read the profile string." end
    local ok, payload = pcall(json.decode, raw)
    if not ok or type(payload) ~= "table" then return nil, "Could not read the profile string." end
    local payloadVersion = tonumber(payload.v)
    if payload.type ~= "autoMarkingProfile" or not payloadVersion or payloadVersion < MIN_WIRE_VERSION or payloadVersion > WIRE_VERSION then
        return nil, "This profile was exported by an incompatible iddqd version."
    end
    local wire = payload.profile
    if type(wire) ~= "table" then return nil, "Profile data is missing." end
    local raids, err = normalizeRaids(wire.raids, false)
    if not raids then return nil, err end
    if payloadVersion < 2 and Engine and Engine.remapGruulNpcIds then
        Engine.remapGruulNpcIds(raids)
    end
    local profile = {
        name = (type(payload.name) == "string" and payload.name ~= "" and payload.name) or "Imported Auto Marking",
        createdAt = now(),
        updatedAt = now(),
        modifierEnabled = wire.modifierEnabled and true or false,
        modifierKey = wire.modifierKey,
        lockAfterUse = wire.lockAfterUse and true or false,
        raids = raids,
    }
    return Engine.normalizeProfile(profile), nil, payload.author
end

function Codec:IsImportString(text)
    text = trim(text)
    return text:sub(1, #PREFIX) == PREFIX
end

function Codec:Prefix()
    return PREFIX
end

return Codec
