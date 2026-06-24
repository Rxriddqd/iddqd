local ADDON, ns = ...

local Store = ns:NewModule("ProfessionsStore")

local PROTOCOL_VERSION = 7

local function now()
    return (time and time()) or os.time()
end

local function shortHash(value)
    value = tostring(value or "")
    local hash = 5381
    for i = 1, #value do
        hash = ((hash * 33) + value:byte(i)) % 2147483647
    end
    return tostring(hash)
end

function Store:DB()
    local db = ns:GetModule("DB")
    return db and db.db or nil
end

function Store:Get()
    local db = self:DB()
    if not db then return nil end
    db.professions = db.professions or { protocolVersion = PROTOCOL_VERSION, profiles = {}, settings = {} }
    self:MigrateOrReset()
    db.professions.profiles = db.professions.profiles or {}
    db.professions.settings = db.professions.settings or {}
    return db.professions
end

function Store:MigrateOrReset()
    local db = self:DB()
    if not db or not db.professions then return end
    local stored = tonumber(db.professions.protocolVersion or 0) or 0
    if stored < PROTOCOL_VERSION then
        ns:Debug("ProfessionsStore reset", tostring(stored), "->", tostring(PROTOCOL_VERSION))
        db.professions.profiles = {}
        db.professions.protocolVersion = PROTOCOL_VERSION
        db.professions.settings = db.professions.settings or {}
    end
end

function Store:ProfessionHash(spellIds, rank, maxRank)
    local ids = {}
    for _, id in ipairs(spellIds or {}) do ids[#ids + 1] = tonumber(id) end
    table.sort(ids)
    local rankStr = tostring(tonumber(rank) or "")
    local maxStr  = tostring(tonumber(maxRank) or "")
    return shortHash(table.concat(ids, ",") .. "|" .. rankStr .. "|" .. maxStr)
end

local function trim(v) return tostring(v or ""):gsub("^%s+",""):gsub("%s+$","") end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function currentRealm()
    local players = Players()
    if players and players.CurrentRealm then return players:CurrentRealm() end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    return (realm or ""):gsub("%s+", "")
end

local function localKey()
    local players = Players()
    if players and players.LocalName then return players:LocalName() end
    local name = trim(UnitName and UnitName("player"))
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = currentRealm()
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function shortPlayerName(value)
    local players = Players()
    if players and players.ShortName then return players:ShortName(value) end
    return tostring(value or ""):match("^([^-]+)") or tostring(value or "")
end

function Store:Profiles()
    local p = self:Get()
    return p and p.profiles or {}
end

function Store:Profile(key)
    return key and self:Profiles()[key] or nil
end

function Store:LocalProfile()
    local key = localKey()
    if not key then return nil end
    local profiles = self:Profiles()
    if not profiles[key] then
        local classFile
        if UnitClass then local _, cf = UnitClass("player"); classFile = cf end
        profiles[key] = {
            key = key,
            name = shortPlayerName(key),
            realm = currentRealm(),
            class = classFile,
            source = "owner",
            updatedAt = now(),
            professions = {},
        }
    end
    return profiles[key]
end

function Store:SetProfession(key, professionName, data, source)
    if not key or not professionName or type(data) ~= "table" then return nil end
    local profiles = self:Profiles()
    local profile = profiles[key]
    if not profile then
        profile = { key = key, name = shortPlayerName(key), source = source or "cache", professions = {} }
        profiles[key] = profile
    end
    profile.professions = profile.professions or {}
    local existing = profile.professions[professionName]
    -- Owner data is authoritative and is never replaced by cache (relayed) data,
    -- regardless of timestamps (cache copies can carry skewed/newer clocks).
    if existing and existing.source == "owner" and source == "cache" then
        return existing
    end
    local spellIds = {}
    for _, id in ipairs(data.spellIds or {}) do spellIds[#spellIds + 1] = tonumber(id) end
    table.sort(spellIds)
    local record = {
        skillLineId = data.skillLineId,
        rank = data.rank,
        maxRank = data.maxRank,
        spellIds = spellIds,
        hash = self:ProfessionHash(spellIds, data.rank, data.maxRank),
        source = source or "owner",
        updatedAt = data.updatedAt or now(),
        lastSyncAt = now(),
        syncState = "synced",
        unmappedCount = data.unmappedCount or 0,
    }
    profile.professions[professionName] = record
    profile.updatedAt = now()
    return record
end

function Store:Manifest()
    local profile = self:LocalProfile()
    if not profile then return nil end
    local manifest = { key = profile.key, name = profile.name, realm = profile.realm, class = profile.class, updatedAt = profile.updatedAt, professions = {} }
    for professionName, prof in pairs(profile.professions or {}) do
        manifest.professions[professionName] = prof.hash
    end
    return manifest
end

function Store:NeedsUpdate(key, professionName, remoteHash)
    local profile = self:Profile(key)
    local prof = profile and profile.professions and profile.professions[professionName]
    if not prof then return true end
    return prof.hash ~= remoteHash
end

-- True if we hold a copy (owner OR cache) of ownerKey's profession at exactly `hash`.
function Store:HasCachedProfession(ownerKey, professionName, hash)
    local profile = self:Profile(ownerKey)
    local prof = profile and profile.professions and profile.professions[professionName]
    if not prof then return false end
    return prof.hash == hash
end

function Store:ResolveSpellId(rawId)
    rawId = tonumber(rawId)
    if not rawId then return nil end
    local db = ns.professionRecipeDB
    if db and db.bySpellId and db.bySpellId[rawId] then return rawId end
    if db and db.byEffectId and db.byEffectId[rawId] then return tonumber(db.byEffectId[rawId]) end
    return nil
end

function Store:RecipeMeta(spellId)
    spellId = tonumber(spellId)
    local db = ns.professionRecipeDB
    local info = spellId and db and db.bySpellId and db.bySpellId[spellId]
    if not info then return nil end
    return { itemId = info.i, effectId = info.e, skillLine = info.p }
end

function Store:ProfessionName(skillLineId)
    skillLineId = tonumber(skillLineId)
    local db = ns.professionRecipeDB
    return skillLineId and db and db.skillLines and db.skillLines[skillLineId] or nil
end

-- Resolves the spell id that crafts `itemId` for the given `skillLineId`.
-- If skillLineId is nil, returns the first/any match from byItemId.
-- Returns nil if the item is not found in the static DB.
function Store:ResolveSpellIdByItem(itemId, skillLineId)
    itemId = tonumber(itemId)
    skillLineId = tonumber(skillLineId)
    local db = ns.professionRecipeDB
    local matches = itemId and db and db.byItemId and db.byItemId[itemId]
    if type(matches) ~= "table" then return nil end
    if skillLineId and matches[skillLineId] then return tonumber(matches[skillLineId]) end
    if not skillLineId then
        for _, spellId in pairs(matches) do return tonumber(spellId) end
    end
    return nil
end

-- Lazily build a {lowercased recipe name -> spellId} index for one profession,
-- scanning only that profession's spells once (not all of bySpellId per lookup).
function Store:ProfessionNameIndex(professionName)
    professionName = tostring(professionName or "")
    if professionName == "" or not GetSpellInfo then return nil end
    self._nameIndex = self._nameIndex or {}
    local idx = self._nameIndex[professionName]
    if idx then return idx end
    local db = ns.professionRecipeDB
    if not db or not db.bySpellId then return nil end
    idx = {}
    for spellId, info in pairs(db.bySpellId) do
        if self:ProfessionName(info.p) == professionName then
            local spellName = GetSpellInfo(spellId)
            if spellName then
                idx[spellName:lower():gsub("^%s+",""):gsub("%s+$","")] = spellId
            end
        end
    end
    self._nameIndex[professionName] = idx
    return idx
end

function Store:ResolveSpellIdByName(professionName, recipeName)
    professionName = tostring(professionName or "")
    recipeName = tostring(recipeName or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    if professionName == "" or recipeName == "" then return nil end
    local idx = self:ProfessionNameIndex(professionName)
    return idx and idx[recipeName] or nil
end

local SECONDARY_PROFESSIONS = {
    ["cooking"] = true, ["first aid"] = true, ["fishing"] = true,
}

-- Distinct profession names across all stored profiles, sorted primaries-first then
-- secondaries (Cooking/First Aid/Fishing), alphabetical within each group.
function Store:KnownProfessionNames()
    local seen, list = {}, {}
    for _, profile in pairs(self:Profiles()) do
        for name in pairs(profile.professions or {}) do
            if name and name ~= "" and not seen[name] then
                seen[name] = true
                list[#list + 1] = name
            end
        end
    end
    table.sort(list, function(a, b)
        local as = SECONDARY_PROFESSIONS[tostring(a):lower()] and true or false
        local bs = SECONDARY_PROFESSIONS[tostring(b):lower()] and true or false
        if as ~= bs then return not as end
        return tostring(a) < tostring(b)
    end)
    return list
end

ns.ProfessionsStoreShortHash = shortHash
