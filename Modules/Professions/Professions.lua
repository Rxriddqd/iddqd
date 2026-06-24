local ADDON, ns = ...

local Professions = ns:NewModule("Professions")

-- Legacy v5 professions controller/sync path. The canonical store/scanner/v7 sync path lives
-- in ProfessionsStore, ProfessionsScanner, and ProfessionsSync. Keep this compatibility-safe
-- until the old protocol can be removed deliberately.
local COMM_PREFIX = "IDDQD_PROF"
local PROTOCOL_VERSION = 5
local PROFILE_OP = "P5"
local MANIFEST_OP = "M6"
local MANIFEST_DELTA_OP = "M6"
local REQUEST_OP = "REQ5"
local WANT_OP = "WANT5"
local WANT_DELTA_OP = "WANTD5"
local DELTA_OP = "D5"
local REPAIR_OP = "FIX5"
local CHUNK_SIZE = 185
local CHUNK_DELAY = 0.35
local PROFESSION_CHUNK_DELAY = 0.45
local PROFILE_CHUNK_DUPLICATE_DELAY = 0.08
local STREAM_STALL_TIMEOUT = 12
local LATE_STREAM_STALL_TIMEOUT = 8
local INCOMING_CLEANUP_AGE = 180
local OUTGOING_STREAM_CACHE_AGE = 180
local AUTO_SHARE_COOLDOWN = 300
local AUTO_SCAN_DEBOUNCE = 0.85
local AUTO_SCAN_MIN_INTERVAL = 3
local REQUEST_RESPONSE_COOLDOWN = 60
local WANT_RESPONSE_COOLDOWN = 25
local REQUEST_SYNC_COOLDOWN = 30
local MANUAL_SYNC_WINDOW = 120
local DUPLICATE_SEND_COOLDOWN = 240
local MANIFEST_SEND_COOLDOWN = 90
local WANT_PROFILE_COOLDOWN = 8
local PROFILE_UNAVAILABLE_ATTEMPTS = 3
local PROFILE_UNAVAILABLE_WINDOW = 120
local PROFILE_UNAVAILABLE_COOLDOWN = 300
local MAX_PROFILE_REQUESTS_PER_FLUSH = 1
local MAX_PROFILE_REQUESTS_PER_PLAYER = 1
local MAX_ACTIVE_PROFILE_STREAMS = 1
local PROFILE_REQUEST_FLUSH_INTERVAL = 8
local MAX_SEND_QUEUE = 8
local MAX_INCOMING_CHUNKS = 6000
local MAX_DELTA_HISTORY_PER_PROFESSION = 8
local PROFESSION_DATA_GENERATION = 6
local CACHED_MANIFESTS_PER_REQUEST = 0
local CACHED_PROFILE_RELAY_COOLDOWN = 180

local json = ns.raid_assignments_json
local b64url = ns.raid_assignments_b64url

local function now()
    return (time and time()) or os.time()
end

local function trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function currentRealm()
    local players = Players()
    if players and players.CurrentRealm then return players:CurrentRealm() end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    return (realm or ""):gsub("%s+", "")
end

local function fullPlayerName(name, realm)
    local players = Players()
    if players and players.FullName then return players:FullName(name, realm) end
    name = trim(name)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = trim(realm or currentRealm())
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function localPlayer()
    local players = Players()
    if players and players.LocalName then return players:LocalName() end
    return fullPlayerName(UnitName("player"), currentRealm())
end

local function shortName(value)
    local players = Players()
    if players and players.ShortName then return players:ShortName(value) end
    value = trim(value)
    local name = strsplit("-", value)
    return name or value
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function recipeIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("enchant:(%d+)") or link:match("spell:(%d+)") or link:match("trade:(%d+)")
    return id and tonumber(id) or nil
end

local function staticRecipeInfo(recipeId)
    recipeId = tonumber(recipeId)
    local db = ns.professionRecipeDB
    return recipeId and db and db.bySpellId and db.bySpellId[recipeId] or nil
end

local staticProfessionName

local function staticSpellIdByEffectId(effectId)
    effectId = tonumber(effectId)
    local db = ns.professionRecipeDB
    return effectId and db and db.byEffectId and db.byEffectId[effectId] or nil
end

local function staticSpellIdByItemId(itemId, professionName)
    itemId = tonumber(itemId)
    professionName = trim(professionName)
    local db = ns.professionRecipeDB
    local byItemId = db and db.byItemId
    local matches = itemId and byItemId and byItemId[itemId]
    if type(matches) ~= "table" then return nil end
    local fallback
    for professionId, spellId in pairs(matches) do
        if not fallback then fallback = spellId end
        if professionName == "" or staticProfessionName(professionId) == professionName then
            return spellId
        end
    end
    return professionName == "" and fallback or nil
end

function staticProfessionName(skillLineId)
    skillLineId = tonumber(skillLineId)
    local db = ns.professionRecipeDB
    return skillLineId and db and db.skillLines and db.skillLines[skillLineId] or nil
end

local function staticRecipeIdByName(professionName, recipeName)
    professionName = trim(professionName)
    recipeName = lower(trim(recipeName))
    if professionName == "" or recipeName == "" or not GetSpellInfo then return nil end
    local db = ns.professionRecipeDB
    if not db or not db.bySpellId then return nil end
    local cacheKey = professionName .. ":" .. recipeName
    ns.professionRecipeNameCache = ns.professionRecipeNameCache or {}
    if ns.professionRecipeNameCache[cacheKey] ~= nil then return ns.professionRecipeNameCache[cacheKey] or nil end
    for spellId, info in pairs(db.bySpellId) do
        if staticProfessionName(info.p) == professionName then
            local spellName = GetSpellInfo(spellId)
            if spellName and lower(trim(spellName)) == recipeName then
                ns.professionRecipeNameCache[cacheKey] = spellId
                return spellId
            end
        end
    end
    ns.professionRecipeNameCache[cacheKey] = false
    return nil
end

local function cleanAddonField(value)
    value = tostring(value or "")
    value = value:gsub("[|\n\r]", " ")
    return trim(value)
end

local function cleanManifestField(value)
    value = cleanAddonField(value)
    value = value:gsub("[;~]", " ")
    return trim(value)
end

local function shortHash(value)
    value = tostring(value or "")
    local hash = 5381
    for i = 1, #value do
        hash = ((hash * 33) + value:byte(i)) % 2147483647
    end
    return tostring(hash)
end

local function routeKey(channel, target)
    return tostring(channel or "GUILD") .. ":" .. tostring(target or "*")
end

local function encodeChunkList(chunks)
    if type(chunks) ~= "table" or #chunks == 0 then return nil end
    local list = {}
    for _, index in ipairs(chunks) do
        index = tonumber(index)
        if index and index > 0 then list[#list + 1] = tostring(index) end
    end
    return #list > 0 and table.concat(list, ",") or nil
end

local function decodeChunkList(value)
    if type(value) ~= "string" or value == "" then return nil end
    local chunks = {}
    for part in value:gmatch("(%d+)") do
        chunks[#chunks + 1] = tonumber(part)
        if #chunks >= 64 then break end
    end
    return #chunks > 0 and chunks or nil
end

local function sendAddon(prefix, message, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then
        local ok, err = Comm:SendAddon(prefix, message, channel, target)
        if not ok then ns:Debug("Professions send failed", tostring(channel), tostring(target or ""), tostring(err)) end
        return ok
    end
    local ok, err
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok, err = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
    elseif SendAddonMessage then
        ok, err = pcall(SendAddonMessage, prefix, message, channel, target)
    else
        ok, err = false, "SendAddonMessage unavailable"
    end
    if not ok then ns:Debug("Professions send failed", tostring(channel), tostring(target or ""), tostring(err)) end
    return ok
end

local function registerPrefix(prefix)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        local ok, err = Comm:RegisterPrefix(prefix)
        if not ok then ns:Debug("Professions prefix register failed", tostring(err)) end
        return ok
    end
    local ok, err
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        ok, err = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    elseif RegisterAddonMessagePrefix then
        ok, err = pcall(RegisterAddonMessagePrefix, prefix)
    else
        ok, err = false, "RegisterAddonMessagePrefix unavailable"
    end
    if not ok then ns:Debug("Professions prefix register failed", tostring(err)) end
    return ok
end

local function playerClass()
    if not UnitClass then return nil end
    local _, classFile = UnitClass("player")
    return classFile
end

local function isFrameShown(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local IGNORED_PROFESSIONS = {
    poisons = true,
}

local function validProfessionName(name)
    name = trim(name)
    if name == "" then return nil end
    local unknown = UNKNOWN and tostring(UNKNOWN) or "UNKNOWN"
    if lower(name) == "unknown" or lower(name) == lower(unknown) then return nil end
    if IGNORED_PROFESSIONS[lower(name)] then return nil end
    return name
end

local function isValidProfessionName(name)
    return validProfessionName(name) ~= nil
end

local function visibleTradeSkillTitle()
    local title = TradeSkillFrameTitleText and TradeSkillFrameTitleText.GetText and TradeSkillFrameTitleText:GetText()
    return validProfessionName(title)
end

local function visibleCraftTitle()
    local title = CraftFrameTitleText and CraftFrameTitleText.GetText and CraftFrameTitleText:GetText()
    return validProfessionName(title)
end

local function localizedFishingName()
    return PROFESSIONS_FISHING or FISHING or "Fishing"
end

local function isFishingName(name)
    name = lower(name)
    return name == "fishing" or name == lower(localizedFishingName())
end

local SECONDARY_PROFESSIONS = {
    ["cooking"] = true,
    ["first aid"] = true,
    ["fishing"] = true,
}

local function isSecondaryProfession(name)
    return SECONDARY_PROFESSIONS[lower(name)] and true or false
end

local function professionLine()
    if GetTradeSkillLine then
        local name, rank, maxRank = GetTradeSkillLine()
        name = validProfessionName(name)
        if name then
            return tostring(name), tonumber(rank), tonumber(maxRank)
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" then
            local name = validProfessionName(info.professionName)
            if name then return tostring(name), tonumber(info.skillLevel), tonumber(info.maxSkillLevel) end
        end
    end
    local title = visibleTradeSkillTitle()
    if title then return title, nil, nil end
    return nil
end

local function itemNameFromLink(link, fallback)
    if type(link) == "string" then
        local linked = link:match("%[([^%]]+)%]")
        if linked and linked ~= "" then return linked end
    end
    return fallback
end

local function itemIconById(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemId)
        if ok and icon then return icon end
    end
    if GetItemIcon then
        local ok, icon = pcall(GetItemIcon, itemId)
        if ok and icon then return icon end
    end
    if GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, itemId)
        if ok and icon then return icon end
    end
    return nil
end

local function itemVisual(linkOrId)
    if not linkOrId or not GetItemInfo then return nil, nil, nil end
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(linkOrId)
    icon = icon or itemIconById(type(linkOrId) == "number" and linkOrId or itemIdFromLink(linkOrId))
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        local itemId = type(linkOrId) == "number" and linkOrId or itemIdFromLink(linkOrId)
        if itemId then pcall(C_Item.RequestLoadItemDataByID, itemId) end
    end
    return name, quality, icon
end

local function tradeSkillIcon(index)
    if GetTradeSkillIcon then
        local ok, icon = pcall(GetTradeSkillIcon, index)
        if ok and icon then return icon end
    end
    return nil
end

local function craftIcon(index)
    if GetCraftIcon then
        local ok, icon = pcall(GetCraftIcon, index)
        if ok and icon then return icon end
    end
    return nil
end

local function reagentRow(name, count, link, icon)
    name = trim(name)
    if name == "" then return nil end
    return {
        name = name,
        count = tonumber(count) or 1,
        itemLink = link,
        itemId = itemIdFromLink(link),
        icon = icon,
    }
end

local function tradeSkillReagents(index)
    if not GetTradeSkillNumReagents or not GetTradeSkillReagentInfo then return nil end
    local total = tonumber(GetTradeSkillNumReagents(index) or 0) or 0
    if total <= 0 then return nil end
    local reagents = {}
    for reagentIndex = 1, total do
        local name, icon, count = GetTradeSkillReagentInfo(index, reagentIndex)
        local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(index, reagentIndex)
        local row = reagentRow(name, count, link, icon)
        if row then reagents[#reagents + 1] = row end
    end
    return #reagents > 0 and reagents or nil
end

local function craftReagents(index)
    if not GetCraftNumReagents or not GetCraftReagentInfo then return nil end
    local total = tonumber(GetCraftNumReagents(index) or 0) or 0
    if total <= 0 then return nil end
    local reagents = {}
    for reagentIndex = 1, total do
        local name, icon, count = GetCraftReagentInfo(index, reagentIndex)
        local link = GetCraftReagentItemLink and GetCraftReagentItemLink(index, reagentIndex)
        local row = reagentRow(name, count, link, icon)
        if row then reagents[#reagents + 1] = row end
    end
    return #reagents > 0 and reagents or nil
end

local function modernReagents(recipeId)
    if not C_TradeSkillUI then return nil end
    local reagents = {}
    if C_TradeSkillUI.GetRecipeSchematic then
        local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeId, false)
        if ok and type(schematic) == "table" then
            for _, reagent in ipairs(schematic.reagentSlotSchematics or {}) do
                local quantity = reagent.quantityRequired or reagent.quantity or reagent.requiredQuantity or 1
                for _, reagentInfo in ipairs(reagent.reagents or {}) do
                    local itemId = reagentInfo.itemID or reagentInfo.itemId
                    local link = itemId and (select(2, GetItemInfo(itemId)))
                    local name, _, _, _, _, _, _, _, _, icon = itemId and GetItemInfo(itemId)
                    local row = reagentRow(name or reagentInfo.name or (itemId and ("Item #" .. itemId)), quantity, link, icon)
                    if row then
                        row.itemId = row.itemId or itemId
                        reagents[#reagents + 1] = row
                    end
                end
            end
        end
    end
    if #reagents == 0 and C_TradeSkillUI.GetRecipeNumReagents and C_TradeSkillUI.GetRecipeReagentInfo then
        local total = tonumber(C_TradeSkillUI.GetRecipeNumReagents(recipeId) or 0) or 0
        for reagentIndex = 1, total do
            local name, icon, count = C_TradeSkillUI.GetRecipeReagentInfo(recipeId, reagentIndex)
            local link = C_TradeSkillUI.GetRecipeReagentItemLink and C_TradeSkillUI.GetRecipeReagentItemLink(recipeId, reagentIndex)
            local row = reagentRow(name, count, link, icon)
            if row then reagents[#reagents + 1] = row end
        end
    end
    return #reagents > 0 and reagents or nil
end

local function normalizeRecipe(recipe)
    if not recipe then return nil end
    local staticInfo = staticRecipeInfo(recipe.recipeId)
    if not staticInfo and recipe.recipeId then
        local spellId = staticSpellIdByEffectId(recipe.recipeId)
        if spellId then
            recipe.spellEffectId = tonumber(recipe.recipeId)
            recipe.recipeId = spellId
            recipe.recipeLink = "spell:" .. tostring(spellId)
            staticInfo = staticRecipeInfo(spellId)
        end
    end
    if staticInfo then
        recipe.itemId = recipe.itemId or staticInfo.i
        recipe.spellEffectId = recipe.spellEffectId or staticInfo.e
        recipe.professionSkillLine = recipe.professionSkillLine or staticInfo.p
        recipe.staticProfessionName = recipe.staticProfessionName or staticProfessionName(staticInfo.p)
        recipe.itemIcon = (staticInfo.i and itemIconById(staticInfo.i)) or recipe.itemIcon
    end
    local spellIcon
    if recipe.recipeId and GetSpellInfo and ((not recipe.name or recipe.name == "") or not recipe.itemIcon) then
        local spellName
        spellName, _, spellIcon = GetSpellInfo(recipe.recipeId)
        recipe.name = recipe.name or spellName
    end
    if (not recipe.name or recipe.name == "") and recipe.recipeId then
        recipe.name = "Spell " .. tostring(recipe.recipeId)
    end
    if (not recipe.itemName or recipe.itemName == "") and recipe.itemId and GetItemInfo then
        local itemName = GetItemInfo(recipe.itemId)
        recipe.itemName = itemName
    end
    if not recipe.name or recipe.name == "" then return nil end
    if recipe.itemLink or recipe.itemId then
        local name, quality, icon = itemVisual(recipe.itemLink or recipe.itemId)
        recipe.itemName = recipe.itemName or name
        recipe.itemQuality = recipe.itemQuality or quality
        recipe.itemIcon = recipe.itemIcon or icon
    end
    recipe.itemIcon = recipe.itemIcon or spellIcon
    recipe.key = tostring(recipe.recipeId or recipe.name)
    return recipe
end

local function compactValue(value)
    return value == nil and "" or value
end

local function expandValue(value)
    return value ~= "" and value or nil
end

local function compactReagents(reagents)
    if type(reagents) ~= "table" or #reagents == 0 then return nil end
    local compact = {}
    for _, reagent in ipairs(reagents) do
        compact[#compact + 1] = {
            compactValue(reagent.itemId),
            compactValue(reagent.name),
            compactValue(reagent.count),
            compactValue(reagent.itemLink),
            compactValue(reagent.icon),
        }
    end
    return compact
end

local function recipeCanUseStaticOnly(recipe)
    if type(recipe) ~= "table" or not recipe.recipeId then return false end
    local staticInfo = staticRecipeInfo(recipe.recipeId)
    if not staticInfo then return false end
    if staticInfo.p == 333 or staticInfo.e then return true end
    local itemId = tonumber(recipe.itemId)
    local staticItemId = tonumber(staticInfo.i)
    return not itemId or not staticItemId or itemId == staticItemId
end

local function encodeRecipeIds(ids)
    if type(ids) ~= "table" or #ids == 0 then return nil end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    return table.concat(ids, ",")
end

local function decodeRecipeIds(value)
    if type(value) ~= "string" or value == "" then return nil end
    local ids = {}
    for id in value:gmatch("(%d+)") do
        ids[#ids + 1] = tonumber(id)
    end
    return #ids > 0 and ids or nil
end

local function compactRecipe(recipe)
    if type(recipe) ~= "table" then return nil end
    local hasRecipeId = recipe.recipeId and true or false
    if hasRecipeId then
        local staticInfo = staticRecipeInfo(recipe.recipeId)
        if not recipe.itemId and not staticInfo then
            return {
                compactValue(recipe.recipeId),
                compactValue(recipe.name),
                "",
                "",
                compactValue(recipe.difficultyRank),
                compactValue(recipe.sourceIndex),
                compactValue(recipe.key),
                compactValue(recipe.itemName or recipe.name),
                compactValue(recipe.itemQuality),
                compactValue(recipe.itemIcon),
                compactValue(recipe.recipeLink),
                compactValue(recipe.itemLink),
                compactReagents(recipe.reagents) or "",
            }
        end
        if staticInfo then
            local row = { compactValue(recipe.recipeId) }
            local function setRowValue(index, value)
                for i = 2, index - 1 do
                    if row[i] == nil then row[i] = "" end
                end
                row[index] = value
            end
            local itemId = tonumber(recipe.itemId)
            local staticItemId = tonumber(staticInfo.i)
            if itemId and itemId ~= staticItemId then setRowValue(3, itemId) end
            return row
        end
        return {
            compactValue(recipe.recipeId),
            "",
            compactValue(recipe.itemId),
            "",
            compactValue(recipe.difficultyRank),
            compactValue(recipe.sourceIndex),
        }
    end
    return {
        "",
        compactValue(recipe.name),
        compactValue(recipe.itemId),
        "",
        compactValue(recipe.difficultyRank),
        compactValue(recipe.sourceIndex),
        compactValue(recipe.key),
        compactValue(recipe.itemName ~= recipe.name and recipe.itemName or nil),
        compactValue(recipe.itemQuality),
        compactValue(recipe.itemIcon),
        compactValue(recipe.recipeLink),
        compactValue(recipe.itemLink),
        compactReagents(recipe.reagents) or "",
    }
end

local function compactProfile(profile, professionFilter)
    if type(profile) ~= "table" then return nil end
    professionFilter = validProfessionName(professionFilter)
    local compact = {
        g = PROFESSION_DATA_GENERATION,
        k = profile.key,
        n = profile.name,
        r = profile.realm,
        c = profile.class,
        u = profile.updatedAt,
        pp = professionFilter,
        p = {},
    }
    for professionName, profession in pairs(profile.professions or {}) do
        if isValidProfessionName(professionName) and (not professionFilter or professionName == professionFilter) then
            local prof = {
                n = professionName,
                r = profession.rank,
                m = profession.maxRank,
                u = profession.updatedAt,
                h = profession.scanHash,
                ids = nil,
                rs = {},
            }
            local staticIds = {}
            for _, recipe in pairs(profession.recipes or {}) do
                if recipe and (not staticRecipeInfo(recipe.recipeId)) and not staticSpellIdByEffectId(recipe.recipeId) then
                    local resolvedId = staticSpellIdByItemId(recipe.itemId, professionName) or staticRecipeIdByName(professionName, recipe.name or recipe.itemName)
                    if resolvedId then
                        recipe.recipeId = resolvedId
                        recipe.recipeLink = "spell:" .. tostring(resolvedId)
                        normalizeRecipe(recipe)
                    end
                end
                if recipeCanUseStaticOnly(recipe) then
                    staticIds[#staticIds + 1] = tonumber(recipe.recipeId)
                else
                    local row = compactRecipe(recipe)
                    if row then prof.rs[#prof.rs + 1] = row end
                end
            end
            prof.ids = encodeRecipeIds(staticIds)
            if professionName == "Enchanting" or #prof.rs > 0 then
                ns:Debug("Professions compact " .. tostring(professionName), "static", tostring(#staticIds), "fallback", tostring(#prof.rs))
            end
            table.sort(prof.rs, function(a, b)
                local an = expandValue(a[2]) or a.n or expandValue(a[7]) or a.k or tostring(a[1] or "")
                local bn = expandValue(b[2]) or b.n or expandValue(b[7]) or b.k or tostring(b[1] or "")
                return tostring(an) < tostring(bn)
            end)
            compact.p[#compact.p + 1] = prof
        end
    end
    table.sort(compact.p, function(a, b) return tostring(a.n or "") < tostring(b.n or "") end)
    return compact
end

local function profileManifest(profile)
    if type(profile) ~= "table" then return nil end
    local manifest = {
        g = PROFESSION_DATA_GENERATION,
        k = profile.key,
        n = profile.name,
        r = profile.realm,
        c = profile.class,
        u = profile.updatedAt,
        p = {},
    }
    for professionName, profession in pairs(profile.professions or {}) do
        if isValidProfessionName(professionName) then
            local count = 0
            for _ in pairs(profession.recipes or {}) do count = count + 1 end
            manifest.p[#manifest.p + 1] = {
                n = professionName,
                r = profession.rank,
                m = profession.maxRank,
                u = profession.updatedAt,
                h = shortHash(profession.scanHash or ""),
                c = count,
            }
        end
    end
    table.sort(manifest.p, function(a, b) return tostring(a.n or "") < tostring(b.n or "") end)
    return manifest
end

local expandReagents

local function expandCompactRecipe(row)
    if type(row) ~= "table" then return nil end
    local recipeId = expandValue(row[1]) or row.id
    local recipeName = expandValue(row[2]) or row.n
    local itemId = expandValue(row[3]) or row.it
    local requiredSkill = expandValue(row[4]) or row.req
    local difficultyRank = expandValue(row[5]) or row.d
    local sourceIndex = expandValue(row[6]) or row.x
    local key = expandValue(row[7]) or row.k
    local itemName = expandValue(row[8]) or row.iname
    local itemQuality = expandValue(row[9]) or row.q
    local itemIcon = expandValue(row[10]) or row.ico
    local recipeLink = expandValue(row[11]) or row.rl
    local itemLink = expandValue(row[12]) or row.il
    local reagents = expandValue(row[13]) or row.rg
    return normalizeRecipe({
        key = key,
        recipeId = recipeId,
        name = recipeName,
        itemId = itemId,
        itemName = itemName,
        itemQuality = itemQuality,
        itemIcon = itemIcon,
        recipeLink = recipeLink or (recipeId and ("spell:" .. tostring(recipeId)) or nil),
        itemLink = itemLink,
        reagents = expandReagents(reagents),
        requiredSkill = requiredSkill,
        difficultyRank = difficultyRank,
        sourceIndex = sourceIndex,
    })
end

local function expandCompactProfile(compact)
    if type(compact) ~= "table" then return nil end
    local profile = {
        dataGeneration = tonumber(compact.g or 0) or 0,
        key = compact.k,
        name = compact.n,
        realm = compact.r,
        class = compact.c,
        updatedAt = compact.u,
        partialProfession = validProfessionName(compact.pp),
        professions = {},
    }
    for _, prof in ipairs(compact.p or {}) do
        local professionName = validProfessionName(prof.n)
        if professionName then
            local profession = {
                dataGeneration = tonumber(compact.g or 0) or 0,
                name = professionName,
                rank = prof.r,
                maxRank = prof.m,
                updatedAt = prof.u,
                scanHash = prof.h,
                recipes = {},
            }
            for _, recipeId in ipairs(decodeRecipeIds(prof.ids) or {}) do
                local recipe = normalizeRecipe({
                    recipeId = recipeId,
                    recipeLink = "spell:" .. tostring(recipeId),
                })
                if recipe then profession.recipes[recipe.key] = recipe end
            end
            for _, row in ipairs(prof.rs or {}) do
                local recipe = expandCompactRecipe(row)
                if recipe then profession.recipes[recipe.key] = recipe end
            end
            profile.professions[professionName] = profession
        end
    end
    return profile
end

local function expandManifest(manifest)
    if type(manifest) ~= "table" then return nil end
    local profile = {
        dataGeneration = tonumber(manifest.g or 0) or 0,
        key = manifest.k,
        name = manifest.n,
        realm = manifest.r,
        class = manifest.c,
        updatedAt = manifest.u,
        professions = {},
        manifestOnly = true,
    }
    for _, prof in ipairs(manifest.p or {}) do
        local professionName = validProfessionName(prof.n)
        if professionName then
            profile.professions[professionName] = {
                dataGeneration = tonumber(manifest.g or 0) or 0,
                name = professionName,
                rank = prof.r,
                maxRank = prof.m,
                updatedAt = prof.u,
                scanHash = prof.h,
                recipeCount = prof.c,
                recipes = {},
            }
        end
    end
    return profile
end

function expandReagents(rows)
    if type(rows) ~= "table" then return nil end
    local reagents = {}
    for _, reagent in ipairs(rows) do
        local itemId = expandValue(reagent[1]) or reagent.id or reagent.itemId
        local row = reagentRow(expandValue(reagent[2]) or reagent.n or reagent.name, expandValue(reagent[3]) or reagent.c or reagent.count, expandValue(reagent[4]) or reagent.il or reagent.itemLink, expandValue(reagent[5]) or reagent.ico or reagent.icon)
        if row then
            row.itemId = row.itemId or itemId
            reagents[#reagents + 1] = row
        end
    end
    return #reagents > 0 and reagents or nil
end

local function professionSignature(profession, rank, maxRank, recipes)
    local parts = {
        tostring(profession or ""),
        tostring(rank or ""),
        tostring(maxRank or ""),
    }
    local recipeParts = {}
    for key, recipe in pairs(recipes or {}) do
        if recipeCanUseStaticOnly(recipe) then
            recipeParts[#recipeParts + 1] = "S:" .. tostring(recipe.recipeId)
        else
            recipeParts[#recipeParts + 1] = table.concat({
                tostring(key or ""),
                tostring(recipe.recipeId or ""),
                tostring(recipe.name or ""),
                tostring(recipe.itemId or ""),
                tostring(recipe.itemIcon or ""),
                tostring(recipe.recipeLink or ""),
                tostring(recipe.itemLink or ""),
                tostring(#(recipe.reagents or {})),
                tostring(recipe.difficultyRank or ""),
            }, ":")
        end
    end
    table.sort(recipeParts)
    for _, part in ipairs(recipeParts) do parts[#parts + 1] = part end
    return table.concat(parts, "|")
end

local function recipeFingerprint(recipe)
    if type(recipe) ~= "table" then return "" end
    if recipeCanUseStaticOnly(recipe) then return shortHash("S:" .. tostring(recipe.recipeId)) end
    local parts = {
        tostring(recipe.key or ""),
        tostring(recipe.recipeId or ""),
        tostring(recipe.name or ""),
        tostring(recipe.itemId or ""),
        tostring(recipe.itemName or ""),
        tostring(recipe.itemQuality or ""),
        tostring(recipe.itemIcon or ""),
        tostring(recipe.recipeLink or ""),
        tostring(recipe.itemLink or ""),
        tostring(recipe.difficultyRank or ""),
        tostring(recipe.sourceIndex or ""),
    }
    local reagents = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        reagents[#reagents + 1] = table.concat({
            tostring(reagent.itemId or ""),
            tostring(reagent.name or ""),
            tostring(reagent.count or ""),
            tostring(reagent.itemLink or ""),
            tostring(reagent.icon or ""),
        }, ":")
    end
    table.sort(reagents)
    for _, reagent in ipairs(reagents) do parts[#parts + 1] = reagent end
    return shortHash(table.concat(parts, "|"))
end

local function compactProfessionDelta(profile, professionName, previousProfession, nextProfession)
    if type(profile) ~= "table" or not isValidProfessionName(professionName) or type(previousProfession) ~= "table" or type(nextProfession) ~= "table" then return nil end
    local fromHash = previousProfession.scanHash
    local toHash = nextProfession.scanHash
    if not fromHash or not toHash or fromHash == toHash then return nil end
    local delta = {
        g = PROFESSION_DATA_GENERATION,
        k = profile.key,
        n = profile.name,
        r = profile.realm,
        c = profile.class,
        u = profile.updatedAt,
        p = professionName,
        pr = nextProfession.rank,
        pm = nextProfession.maxRank,
        pu = nextProfession.updatedAt,
        f = fromHash,
        t = toHash,
        ids = nil,
        rs = {},
        rm = {},
    }
    local previousRecipes = previousProfession.recipes or {}
    local nextRecipes = nextProfession.recipes or {}
    for key, recipe in pairs(nextRecipes) do
        local previous = previousRecipes[key]
        if not previous or recipeFingerprint(previous) ~= recipeFingerprint(recipe) then
            if recipeCanUseStaticOnly(recipe) then
                delta.ids = delta.ids or {}
                delta.ids[#delta.ids + 1] = tonumber(recipe.recipeId)
            else
                local row = compactRecipe(recipe)
                if row then delta.rs[#delta.rs + 1] = row end
            end
        end
    end
    for key in pairs(previousRecipes) do
        if not nextRecipes[key] then delta.rm[#delta.rm + 1] = tostring(key) end
    end
    table.sort(delta.rs, function(a, b)
        local an = expandValue(a[2]) or expandValue(a[7]) or tostring(a[1] or "")
        local bn = expandValue(b[2]) or expandValue(b[7]) or tostring(b[1] or "")
        return tostring(an) < tostring(bn)
    end)
    table.sort(delta.rm)
    delta.ids = encodeRecipeIds(delta.ids)
    if not delta.ids and #delta.rs == 0 and #delta.rm == 0 then return nil end
    return delta
end

local function difficultyRank(value)
    value = lower(value)
    if value == "optimal" then return 4 end
    if value == "medium" then return 3 end
    if value == "easy" then return 2 end
    if value == "trivial" then return 1 end
    return 0
end

function Professions:Store()
    local db = ns:GetModule("DB")
    db = db and db.db
    if not db then return nil end
    db.professions = db.professions or { profiles = {}, settings = {} }
    db.professions.profiles = db.professions.profiles or {}
    db.professions.settings = db.professions.settings or {}
    db.professions.deltaHistory = db.professions.deltaHistory or {}
    if tonumber(db.professions.dataGeneration or 0) < PROFESSION_DATA_GENERATION then
        ns:Debug("Professions cache generation reset", tostring(db.professions.dataGeneration or 0), "->", tostring(PROFESSION_DATA_GENERATION))
        db.professions.profiles = {}
        db.professions.deltaHistory = {}
        db.professions.lastScanAt = 0
        db.professions.dataGeneration = PROFESSION_DATA_GENERATION
        self.incoming = {}
        self.completedIncoming = {}
        self.rejectedIncoming = {}
        self.pendingProfileRequests = {}
        self.scheduledWantByProfile = {}
        self.lastWantByProfile = {}
        self.lastWantResponseBySender = {}
        self.lastRequestResponseBySender = {}
        self.lastSentByRoute = {}
        self.lastManifestByRoute = {}
        self.sendQueue = {}
        self.sendingProfile = false
        self.activeSendRoute = nil
        self.activeSendSignature = nil
        self.profileRequestFailures = {}
        self.profileRequestUnavailableUntil = {}
        self.sendEpoch = (self.sendEpoch or 0) + 1
    end
    return db.professions
end

function Professions:Profiles()
    local store = self:Store()
    return store and store.profiles or {}
end

local function profileGeneration(profile)
    return tonumber(profile and profile.dataGeneration or 0) or 0
end

local function profileIsCurrentGeneration(profile)
    return profileGeneration(profile) >= PROFESSION_DATA_GENERATION
end

function Professions:LocalProfile()
    local key = localPlayer()
    if not key then return nil end
    local profiles = self:Profiles()
    profiles[key] = profiles[key] or {
        key = key,
        name = shortName(key),
        realm = currentRealm(),
        class = playerClass(),
        professions = {},
        updatedAt = 0,
    }
    profiles[key].dataGeneration = PROFESSION_DATA_GENERATION
    return profiles[key]
end

function Professions:DeltaHistory()
    local store = self:Store()
    if not store then return nil end
    store.deltaHistory = store.deltaHistory or {}
    local key = localPlayer()
    if not key then return nil end
    store.deltaHistory[key] = store.deltaHistory[key] or {}
    return store.deltaHistory[key]
end

function Professions:RememberProfessionDelta(professionName, delta)
    professionName = validProfessionName(professionName)
    if not professionName or type(delta) ~= "table" or not delta.f or not delta.t then return false end
    local history = self:DeltaHistory()
    if not history then return false end
    history[professionName] = history[professionName] or {}
    history[professionName][delta.f] = {
        at = now(),
        toHash = delta.t,
        delta = delta,
    }
    history[professionName][shortHash(delta.f)] = {
        at = now(),
        toHash = delta.t,
        delta = delta,
    }
    local entries, seen = {}, {}
    for fromHash, row in pairs(history[professionName]) do
        local deltaKey = row.delta or fromHash
        if not seen[deltaKey] then
            seen[deltaKey] = true
            entries[#entries + 1] = {
                fromHash = fromHash,
                at = tonumber(row.at or 0) or 0,
                delta = row.delta,
            }
        end
    end
    table.sort(entries, function(a, b) return a.at > b.at end)
    local keep = {}
    for i = 1, math.min(MAX_DELTA_HISTORY_PER_PROFESSION, #entries) do
        local keptDelta = entries[i].delta
        if keptDelta and keptDelta.f then
            keep[keptDelta.f] = true
            keep[shortHash(keptDelta.f)] = true
        else
            keep[entries[i].fromHash] = true
        end
    end
    for fromHash in pairs(history[professionName]) do
        if not keep[fromHash] then history[professionName][fromHash] = nil end
    end
    return true
end

function Professions:ProfessionDelta(professionName, fromHash)
    professionName = validProfessionName(professionName)
    if not professionName or not fromHash then return nil end
    local history = self:DeltaHistory()
    local row = history and history[professionName] and (history[professionName][fromHash] or history[professionName][shortHash(fromHash)])
    return row and row.delta or nil
end

function Professions:PanelRefresh()
    if not (self.panel and self.panel.Refresh) then return end
    if not C_Timer then
        self.panel:Refresh()
        return
    end
    if self.panelRefreshQueued then return end
    self.panelRefreshQueued = true
    C_Timer.After(0.08, function()
        self.panelRefreshQueued = false
        if self.panel and self.panel.Refresh then self.panel:Refresh() end
    end)
end

function Professions:RegisterPanel(panel)
    self.panel = panel
    self:FlushPendingProfileRequests()
end

function Professions:SetSyncStatus(label, current, total, active)
    current = tonumber(current or 0) or 0
    total = tonumber(total or 0) or 0
    self.syncStatusSerial = (self.syncStatusSerial or 0) + 1
    self.syncStatus = {
        label = tostring(label or ""),
        current = current,
        total = total,
        active = active and true or false,
        updatedAt = now(),
        token = self.syncStatusSerial,
    }
    if self.panel and self.panel.RefreshSyncStatus then
        self.panel:RefreshSyncStatus()
    end
    if C_Timer then
        local token = self.syncStatus.token
        local delay = active and 30 or 5
        C_Timer.After(delay, function()
            if self.syncStatus and self.syncStatus.token == token and not self.syncStatus.active then
                self.syncStatus = nil
                if self.panel and self.panel.RefreshSyncStatus then self.panel:RefreshSyncStatus() end
            elseif self.syncStatus and self.syncStatus.token == token and self.syncStatus.active then
                self.syncStatus.active = false
                self.syncStatus.label = "Profession sync waiting for data"
                self.syncStatus.updatedAt = now()
                self.syncStatusSerial = (self.syncStatusSerial or 0) + 1
                self.syncStatus.token = self.syncStatusSerial
                if self.panel and self.panel.RefreshSyncStatus then self.panel:RefreshSyncStatus() end
                local clearToken = self.syncStatus.token
                C_Timer.After(5, function()
                    if self.syncStatus and self.syncStatus.token == clearToken and not self.syncStatus.active then
                        self.syncStatus = nil
                        if self.panel and self.panel.RefreshSyncStatus then self.panel:RefreshSyncStatus() end
                    end
                end)
            end
        end)
    end
end

function Professions:SyncStatus()
    return self.syncStatus
end

function Professions:ShouldRequestProfileData()
    if self.manualSyncUntil and now() <= tonumber(self.manualSyncUntil or 0) then return true end
    return self.panel and self.panel.IsShown and self.panel:IsShown()
end

function Professions:QueueProfileRequest(sender, manifestProfile)
    if not sender or sender == "" or type(manifestProfile) ~= "table" or not manifestProfile.key then return false end
    self.pendingProfileRequests = self.pendingProfileRequests or {}
    local key = fullPlayerName(manifestProfile.key) or manifestProfile.key or sender
    local existingProfile = self:Profiles()[key]
    local existingRequest = self.pendingProfileRequests[key]
    local signatureParts = {}
    for professionName, prof in pairs(manifestProfile.professions or {}) do
        signatureParts[#signatureParts + 1] = tostring(professionName) .. ":" .. tostring(prof.scanHash or "") .. ":" .. tostring(prof.updatedAt or "")
    end
    table.sort(signatureParts)
    local signature = table.concat(signatureParts, ";")
    if existingRequest and existingRequest.signature == signature
        and (existingRequest.manifest and existingRequest.manifest.deltaCapable or not manifestProfile.deltaCapable) then
        return true
    end
    if not manifestProfile.deltaCapable and ((existingProfile and existingProfile.deltaCapable) or (existingRequest and existingRequest.manifest and existingRequest.manifest.deltaCapable)) then
        manifestProfile.deltaCapable = true
        for _, remoteProf in pairs(manifestProfile.professions or {}) do
            remoteProf.deltaCapable = true
        end
    end
    self.pendingProfileRequests[key] = {
        sender = sender,
        manifest = manifestProfile,
        at = now(),
        signature = signature,
    }
    ns:Debug("Professions queued profile request", tostring(key), "from", tostring(sender))
    self:ScheduleProfileRequestFlush(PROFILE_REQUEST_FLUSH_INTERVAL)
    return true
end

function Professions:ClearStalledIncomingStreams()
    local at = now()
    local cleared = false
    for key, stream in pairs(self.incoming or {}) do
        local timeout = stream.lateStart and LATE_STREAM_STALL_TIMEOUT or STREAM_STALL_TIMEOUT
        if at - tonumber(stream.at or 0) >= timeout then
            local missing = {}
            for i = 1, tonumber(stream.total or 0) do
                if not stream.chunks[i] then
                    missing[#missing + 1] = i
                    if #missing >= 8 then break end
                end
            end
            ns:Debug("Professions stream stalled", tostring(stream.sender or "?"), tostring(key), tostring(stream.received or 0) .. "/" .. tostring(stream.total or 0), "missing", table.concat(missing, ","))
            local missingText = encodeChunkList(missing)
            local requestedRepair = false
            if missingText and not stream.repairRequestedAt then
                stream.repairRequestedAt = at
                stream.at = at
                stream.timeoutToken = (stream.timeoutToken or 0) + 1
                sendAddon(COMM_PREFIX, ("%s|%s|%s"):format(REPAIR_OP, cleanAddonField(stream.streamId or ""), cleanAddonField(missingText)), "WHISPER", stream.sender)
                self:SetSyncStatus("Profession stream missed data; requesting repair", stream.received or 0, stream.total or 1, true)
                ns:Debug("Professions requested stream repair", tostring(stream.sender or "?"), tostring(stream.streamId or key), missingText)
                requestedRepair = true
            end
            if not requestedRepair then
                self:SetSyncStatus("Profession stream missed data; retrying", stream.received or 0, stream.total or 1, true)
                self.incoming[key] = nil
                cleared = true
            end
        end
    end
    if cleared then
        self.lastPendingProfileFlushAt = nil
        self.lastWantByProfile = {}
        self.scheduledWantByProfile = {}
        self:ScheduleProfileRequestFlush(1)
    end
    return cleared
end

function Professions:ActiveIncomingProfileStreams()
    self:ClearStalledIncomingStreams()
    local count = 0
    for _, stream in pairs(self.incoming or {}) do
        if stream and tonumber(stream.total or 0) > tonumber(stream.received or 0) then
            count = count + 1
        end
    end
    return count
end

function Professions:PrimaryIncomingStream()
    local best
    for key, stream in pairs(self.incoming or {}) do
        if stream and tonumber(stream.total or 0) > tonumber(stream.received or 0) then
            if not best or tonumber(stream.startedAt or stream.at or 0) < tonumber(best.stream.startedAt or best.stream.at or 0) then
                best = { key = key, stream = stream }
            end
        end
    end
    return best
end

function Professions:ProfileRequestKey(key, professionName)
    key = fullPlayerName(key) or key
    professionName = validProfessionName(professionName)
    if not key or not professionName then return nil end
    return key .. ":" .. professionName
end

function Professions:ProfileRequestUnavailable(key, professionName)
    local requestKey = self:ProfileRequestKey(key, professionName)
    if not requestKey then return false end
    self.profileRequestUnavailableUntil = self.profileRequestUnavailableUntil or {}
    local untilAt = tonumber(self.profileRequestUnavailableUntil[requestKey] or 0) or 0
    if untilAt > now() then return true, untilAt end
    self.profileRequestUnavailableUntil[requestKey] = nil
    return false
end

function Professions:RecordProfileRequestAttempt(key, professionName)
    local requestKey = self:ProfileRequestKey(key, professionName)
    if not requestKey then return end
    self.profileRequestFailures = self.profileRequestFailures or {}
    self.profileRequestUnavailableUntil = self.profileRequestUnavailableUntil or {}
    local at = now()
    local state = self.profileRequestFailures[requestKey]
    if not state or at - tonumber(state.firstAt or 0) > PROFILE_UNAVAILABLE_WINDOW then
        state = { firstAt = at, count = 0 }
        self.profileRequestFailures[requestKey] = state
    end
    state.count = tonumber(state.count or 0) + 1
    state.lastAt = at
    if state.count >= PROFILE_UNAVAILABLE_ATTEMPTS then
        self.profileRequestUnavailableUntil[requestKey] = at + PROFILE_UNAVAILABLE_COOLDOWN
        self.profileRequestFailures[requestKey] = nil
        self.scheduledWantByProfile = self.scheduledWantByProfile or {}
        self.lastWantByProfile = self.lastWantByProfile or {}
        self.scheduledWantByProfile[requestKey] = nil
        self.lastWantByProfile[requestKey] = nil
        ns:Debug("Professions profile temporarily unavailable", tostring(key), tostring(professionName), tostring(PROFILE_UNAVAILABLE_COOLDOWN) .. "s")
    end
end

function Professions:HasRequestableProfessions(manifestProfile)
    for _, professionName in ipairs(self:NeededProfessions(manifestProfile)) do
        if not self:ProfileRequestUnavailable(manifestProfile.key, professionName) then
            return true
        end
    end
    return false
end

function Professions:HasPendingProfileRequests()
    for _, request in pairs(self.pendingProfileRequests or {}) do
        if request and request.sender and request.manifest and self:HasRequestableProfessions(request.manifest) then
            return true
        end
    end
    return false
end

function Professions:ClearProfileRequestState(key, professionName)
    key = fullPlayerName(key) or key
    professionName = validProfessionName(professionName)
    if not key then return end
    self.pendingProfileRequests = self.pendingProfileRequests or {}
    self.scheduledWantByProfile = self.scheduledWantByProfile or {}
    self.lastWantByProfile = self.lastWantByProfile or {}
    self.profileRequestFailures = self.profileRequestFailures or {}
    self.profileRequestUnavailableUntil = self.profileRequestUnavailableUntil or {}
    if professionName then
        local requestKey = key .. ":" .. professionName
        self.scheduledWantByProfile[requestKey] = nil
        self.lastWantByProfile[requestKey] = nil
        self.profileRequestFailures[requestKey] = nil
        self.profileRequestUnavailableUntil[requestKey] = nil
    else
        for requestKey in pairs(self.profileRequestFailures) do
            if requestKey:find(key .. ":", 1, true) == 1 then self.profileRequestFailures[requestKey] = nil end
        end
        for requestKey in pairs(self.profileRequestUnavailableUntil) do
            if requestKey:find(key .. ":", 1, true) == 1 then self.profileRequestUnavailableUntil[requestKey] = nil end
        end
    end
    local request = self.pendingProfileRequests[key]
    if request and (not request.manifest or not self:HasRequestableProfessions(request.manifest)) then
        self.pendingProfileRequests[key] = nil
    end
end

function Professions:NextPendingProfileRequest()
    local bestKey, bestRequest
    for key, request in pairs(self.pendingProfileRequests or {}) do
        if request and request.sender and request.manifest and self:HasRequestableProfessions(request.manifest) then
            if not bestRequest
                or tonumber(request.at or 0) < tonumber(bestRequest.at or 0)
                or (tonumber(request.at or 0) == tonumber(bestRequest.at or 0) and tostring(key) < tostring(bestKey)) then
                bestKey = key
                bestRequest = request
            end
        end
    end
    return bestKey, bestRequest
end

function Professions:ScheduleProfileRequestFlush(delay)
    if not C_Timer or self.profileRequestFlushQueued then return end
    self.profileRequestFlushQueued = true
    C_Timer.After(delay or PROFILE_REQUEST_FLUSH_INTERVAL, function()
        self.profileRequestFlushQueued = false
        if self:FlushPendingProfileRequests() or self:HasPendingProfileRequests() then
            self:ScheduleProfileRequestFlush(PROFILE_REQUEST_FLUSH_INTERVAL)
        end
    end)
end

function Professions:FlushPendingProfileRequests()
    if not self:ShouldRequestProfileData() then return false end
    if self.lastPendingProfileFlushAt and now() - self.lastPendingProfileFlushAt < 8 then return false end
    self.lastPendingProfileFlushAt = now()
    local pending = self.pendingProfileRequests
    local sent = false
    local activeStreams = self:ActiveIncomingProfileStreams()
    if activeStreams >= MAX_ACTIVE_PROFILE_STREAMS then
        ns:Debug("Professions profile request flush waiting for active streams", tostring(activeStreams))
        self:SetSyncStatus("Waiting for profession streams", activeStreams, MAX_ACTIVE_PROFILE_STREAMS, true)
        self:ScheduleProfileRequestFlush(PROFILE_REQUEST_FLUSH_INTERVAL)
        return false
    end
    local budget = math.min(MAX_PROFILE_REQUESTS_PER_FLUSH, MAX_ACTIVE_PROFILE_STREAMS - activeStreams)
    if pending then
        local key, request = self:NextPendingProfileRequest()
        if key and request and budget > 0 then
            local ok, used = self:RequestProfileFrom(request.sender, request.manifest, math.min(budget, MAX_PROFILE_REQUESTS_PER_PLAYER))
            if ok then
                sent = true
                budget = math.max(0, budget - (tonumber(used or 0) or 0))
                if not self:HasRequestableProfessions(request.manifest) then pending[key] = nil end
            end
        end
    end
    if budget > 0 and not self:HasPendingProfileRequests() then
        local ok = self:RequestMissingStoredProfiles(budget)
        if ok then sent = true end
    end
    if self:HasPendingProfileRequests() then
        self:ScheduleProfileRequestFlush(PROFILE_REQUEST_FLUSH_INTERVAL)
    end
    return sent
end

function Professions:RequestMissingStoredProfiles(budget)
    if not self:ShouldRequestProfileData() then return false end
    budget = tonumber(budget or MAX_PROFILE_REQUESTS_PER_FLUSH) or MAX_PROFILE_REQUESTS_PER_FLUSH
    local sent = false
    for key, profile in pairs(self:Profiles()) do
        if budget <= 0 then break end
        if key ~= localPlayer() and type(profile) == "table" and self:HasRequestableProfessions(profile) then
            local sender = profile.lastManifestSender or profile.key or key
            if sender then
                local ok, used = self:RequestProfileFrom(sender, profile, math.min(budget, MAX_PROFILE_REQUESTS_PER_PLAYER))
                if ok then
                    sent = true
                    budget = math.max(0, budget - (tonumber(used or 0) or 0))
                end
            end
        end
    end
    return sent
end

function Professions:PruneInvalidProfessions(profile)
    if type(profile) ~= "table" then return end
    for professionName in pairs(profile.professions or {}) do
        if not isValidProfessionName(professionName) then
            profile.professions[professionName] = nil
        end
    end
end

function Professions:ScanClassicTradeSkill()
    if not GetNumTradeSkills or not GetTradeSkillInfo then return nil end
    local profession, rank, maxRank = professionLine()
    if not profession then return nil end
    local recipes = {}
    local count = GetNumTradeSkills() or 0
    if ExpandTradeSkillSubClass then
        for i = count, 1, -1 do
            local _, recipeType, _, isExpanded = GetTradeSkillInfo(i)
            if recipeType == "header" and not isExpanded then
                pcall(ExpandTradeSkillSubClass, i)
            end
        end
        count = GetNumTradeSkills() or count
    end
    for i = 1, count do
        local name, recipeType = GetTradeSkillInfo(i)
        if name and recipeType ~= "header" then
            local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
            local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
            local itemId = itemIdFromLink(itemLink)
            local recipeId = recipeIdFromLink(recipeLink)
            if not staticRecipeInfo(recipeId) and not staticSpellIdByEffectId(recipeId) then
                recipeId = staticSpellIdByItemId(itemId, profession) or staticRecipeIdByName(profession, name) or recipeId
            end
            local recipe = normalizeRecipe({
                recipeId = recipeId,
                name = tostring(name),
                difficulty = recipeType,
                difficultyRank = difficultyRank(recipeType),
                sourceIndex = i,
                recipeLink = recipeLink,
                itemId = itemId,
                itemName = itemNameFromLink(itemLink),
                itemIcon = tradeSkillIcon(i),
                itemLink = itemLink,
                reagents = tradeSkillReagents(i),
            })
            if recipe then recipes[recipe.key] = recipe end
        end
    end
    return profession, rank, maxRank, recipes
end

function Professions:ScanModernTradeSkill()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then return nil end
    local profession, rank, maxRank = professionLine()
    if not profession then return nil end
    local recipes = {}
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if type(ids) ~= "table" then return nil end
    for _, recipeId in ipairs(ids) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeId)
        if ok and type(info) == "table" and info.name and info.learned ~= false then
            local itemLink
            if C_TradeSkillUI.GetRecipeItemLink then
                local itemOk, link = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeId)
                if itemOk then itemLink = link end
            end
            local itemId = itemIdFromLink(itemLink)
            local recipeLink
            if C_TradeSkillUI.GetRecipeLink then
                local recipeOk, link = pcall(C_TradeSkillUI.GetRecipeLink, recipeId)
                if recipeOk then recipeLink = link end
            end
            recipeId = tonumber(recipeId)
            if not staticRecipeInfo(recipeId) and not staticSpellIdByEffectId(recipeId) then
                recipeId = staticSpellIdByItemId(itemId, profession) or staticRecipeIdByName(profession, info.name) or recipeId
            end
            local recipe = normalizeRecipe({
                recipeId = tonumber(recipeId),
                name = tostring(info.name),
                difficulty = info.difficulty or info.difficultyName,
                difficultyRank = difficultyRank(info.difficulty or info.difficultyName),
                recipeLink = recipeLink,
                itemId = itemId,
                itemName = itemNameFromLink(itemLink),
                itemIcon = info.icon,
                itemLink = itemLink,
                reagents = modernReagents(recipeId),
            })
            if recipe then recipes[recipe.key] = recipe end
        end
    end
    return profession, rank, maxRank, recipes
end

function Professions:ScanCraftFrame()
    if not GetNumCrafts or not GetCraftInfo then return nil end
    local profession = GetCraftDisplaySkillLine and validProfessionName(GetCraftDisplaySkillLine()) or visibleCraftTitle()
    if not profession then return nil end
    local recipes = {}
    local count = GetNumCrafts() or 0
    if ExpandCraftSkillLine then
        for i = count, 1, -1 do
            local _, _, craftType, _, isExpanded = GetCraftInfo(i)
            if craftType == "header" and not isExpanded then
                pcall(ExpandCraftSkillLine, i)
            end
        end
        count = GetNumCrafts() or count
    end
    for i = 1, count do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            local itemLink = GetCraftItemLink and GetCraftItemLink(i)
            local recipeLink = GetCraftSpellLink and GetCraftSpellLink(i)
            local itemId = itemIdFromLink(itemLink)
            local recipeId = recipeIdFromLink(recipeLink)
            if not staticRecipeInfo(recipeId) and not staticSpellIdByEffectId(recipeId) then
                recipeId = staticSpellIdByItemId(itemId, profession) or staticRecipeIdByName(profession, name) or recipeId
            end
            local recipe = normalizeRecipe({
                recipeId = recipeId,
                name = tostring(name),
                difficulty = craftType,
                difficultyRank = difficultyRank(craftType),
                sourceIndex = i,
                recipeLink = recipeLink,
                itemId = itemId,
                itemName = itemNameFromLink(itemLink),
                itemIcon = craftIcon(i),
                itemLink = itemLink,
                reagents = craftReagents(i),
            })
            if recipe then recipes[recipe.key] = recipe end
        end
    end
    return profession, nil, nil, recipes
end

function Professions:ScanOpenProfession(silent)
    local profession, rank, maxRank, recipes
    local craftShown = isFrameShown(CraftFrame)
    local tradeReady = false
    if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady then
        local ok, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
        tradeReady = ok and ready and true or false
    end
    local tradeShown = isFrameShown(TradeSkillFrame) or tradeReady
    if not craftShown and not tradeShown then
        if not silent then ns:Print("Open a profession window first, then scan again.", "warning") end
        return false
    end
    if craftShown and not tradeShown then
        profession, rank, maxRank, recipes = self:ScanCraftFrame()
        if not profession then profession, rank, maxRank, recipes = self:ScanClassicTradeSkill() end
    else
        profession, rank, maxRank, recipes = self:ScanModernTradeSkill()
        if not profession then profession, rank, maxRank, recipes = self:ScanClassicTradeSkill() end
        if not profession then profession, rank, maxRank, recipes = self:ScanCraftFrame() end
    end
    if not profession or not recipes then
        if not silent then ns:Print("Open a profession window first, then scan again.", "warning") end
        return false
    end

    local profile = self:LocalProfile()
    if not profile then return false end
    profile.name = shortName(localPlayer())
    profile.realm = currentRealm()
    profile.class = playerClass()
    profile.professions = profile.professions or {}
    self:PruneInvalidProfessions(profile)
    local scanHash = professionSignature(profession, rank, maxRank, recipes)
    local existing = profile.professions[profession]
    local changed = not existing or existing.scanHash ~= scanHash
    if not changed then
        local store = self:Store()
        if store then store.lastScanAt = now() end
        if not silent then ns:Print(("%s already up to date."):format(profession), "success") end
        self:PanelRefresh()
        return true
    end

    profile.updatedAt = now()
    local nextProfession = {
        name = profession,
        rank = rank,
        maxRank = maxRank,
        recipes = recipes,
        updatedAt = profile.updatedAt,
        scanHash = scanHash,
    }
    local delta = existing and compactProfessionDelta(profile, profession, existing, nextProfession)
    if delta then self:RememberProfessionDelta(profession, delta) end
    profile.professions[profession] = nextProfession

    local store = self:Store()
    if store then store.lastScanAt = profile.updatedAt end
    self:PanelRefresh()
    self:AutoShare()
    if not silent then
        local count = 0
        for _ in pairs(recipes) do count = count + 1 end
        ns:Print(("Scanned %s: %d recipes."):format(profession, count), "success")
    end
    return true
end

function Professions:ScanFishingSkill(silent)
    if not GetNumSkillLines or not GetSkillLineInfo then return false end
    local rank, maxRank
    local count = tonumber(GetNumSkillLines() or 0) or 0
    for i = 1, count do
        local name, isHeader, isExpanded, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then
            pcall(ExpandSkillHeader, i)
        elseif name and isFishingName(name) then
            rank = tonumber(skillRank) or 0
            maxRank = tonumber(skillMaxRank) or 0
            break
        end
    end
    if not rank then
        count = tonumber(GetNumSkillLines() or 0) or count
        for i = 1, count do
            local name, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
            if not isHeader and name and isFishingName(name) then
                rank = tonumber(skillRank) or 0
                maxRank = tonumber(skillMaxRank) or 0
                break
            end
        end
    end
    if not rank or rank <= 0 or not maxRank or maxRank <= 0 then return false end

    local profile = self:LocalProfile()
    if not profile then return false end
    profile.name = shortName(localPlayer())
    profile.realm = currentRealm()
    profile.class = playerClass()
    profile.professions = profile.professions or {}
    self:PruneInvalidProfessions(profile)

    local profession = "Fishing"
    local scanHash = ("skill:%s:%s"):format(tostring(rank or 0), tostring(maxRank or 0))
    local existing = profile.professions[profession]
    if existing and existing.scanHash == scanHash then return true end

    profile.updatedAt = now()
    profile.professions[profession] = {
        name = profession,
        rank = rank,
        maxRank = maxRank,
        recipes = {},
        isSkill = true,
        updatedAt = profile.updatedAt,
        scanHash = scanHash,
    }
    local store = self:Store()
    if store then store.lastScanAt = profile.updatedAt end
    self:PanelRefresh()
    self:AutoShare()
    if not silent then
        ns:Print(("Scanned Fishing: %d/%d."):format(rank or 0, maxRank or 0), "success")
    end
    return true
end

function Professions:ScheduleScan()
    if not C_Timer then return self:ScanOpenProfession(true) end
    self.scanToken = (self.scanToken or 0) + 1
    local token = self.scanToken
    C_Timer.After(AUTO_SCAN_DEBOUNCE, function()
        if token ~= self.scanToken then return end
        local at = now()
        if self.lastAutoScanAt and at - self.lastAutoScanAt < AUTO_SCAN_MIN_INTERVAL then return end
        self.lastAutoScanAt = at
        self:ScanOpenProfession(true)
    end)
end

function Professions:ScheduleSkillScan()
    if not C_Timer then return self:ScanFishingSkill(true) end
    self.skillScanToken = (self.skillScanToken or 0) + 1
    local token = self.skillScanToken
    C_Timer.After(1.0, function()
        if token ~= self.skillScanToken then return end
        self:ScanFishingSkill(true)
    end)
end

function Professions:HookSkillFrame()
    if self.skillFrameHooked then return end
    if SkillFrame and SkillFrame.HookScript then
        SkillFrame:HookScript("OnShow", function() self:ScheduleSkillScan() end)
        self.skillFrameHooked = true
        return
    end
    if hooksecurefunc then
        local ok = pcall(hooksecurefunc, "ToggleCharacter", function(tab)
            if tab == "SkillFrame" or tab == "SkillsFrame" then
                self:ScheduleSkillScan()
            end
        end)
        if ok then self.skillFrameHooked = true end
    end
end

function Professions:EncodeProfile(profile, professionName)
    if not json or not json.encode or not b64url or not b64url.encode or not profile then return nil end
    self:PruneInvalidProfessions(profile)
    local ok, raw = pcall(json.encode, {
        v = PROTOCOL_VERSION,
        compact = true,
        profile = compactProfile(profile, professionName),
    })
    if not ok or type(raw) ~= "string" then return nil end
    return b64url.encode(raw)
end

function Professions:EncodeDelta(delta)
    if not json or not json.encode or not b64url or not b64url.encode or type(delta) ~= "table" then return nil end
    local ok, raw = pcall(json.encode, {
        v = PROTOCOL_VERSION,
        delta = true,
        profession = delta,
    })
    if not ok or type(raw) ~= "string" then return nil end
    return b64url.encode(raw)
end

function Professions:EncodeManifest(profile)
    if not profile then return nil end
    self:PruneInvalidProfessions(profile)
    local manifest = profileManifest(profile)
    if not manifest or not manifest.k then return nil end
    local professions = {}
    for _, profession in ipairs(manifest.p or {}) do
        professions[#professions + 1] = table.concat({
            cleanManifestField(profession.n),
            cleanManifestField(profession.r),
            cleanManifestField(profession.m),
            cleanManifestField(profession.u),
            cleanManifestField(profession.h),
            cleanManifestField(profession.c),
        }, "~")
    end
    return table.concat({
        cleanManifestField(manifest.k),
        cleanManifestField(manifest.n),
        cleanManifestField(manifest.r),
        cleanManifestField(manifest.c),
        cleanManifestField(manifest.u),
        cleanManifestField(manifest.g),
        table.concat(professions, ";"),
    }, "|")
end

function Professions:DecodeManifest(encoded)
    if type(encoded) ~= "string" or encoded == "" then return nil end
    local key, name, realm, class, updatedAt, generation, profText = strsplit("|", encoded, 7)
    local manifest = {
        g = tonumber(generation) or 0,
        k = key,
        n = name,
        r = realm,
        c = class,
        u = tonumber(updatedAt),
        p = {},
    }
    for part in string.gmatch(profText or "", "([^;]+)") do
        local professionName, rank, maxRank, profUpdatedAt, hash, count = strsplit("~", part, 6)
        if professionName and professionName ~= "" then
            manifest.p[#manifest.p + 1] = {
                n = professionName,
                r = tonumber(rank),
                m = tonumber(maxRank),
                u = tonumber(profUpdatedAt),
                h = hash,
                c = tonumber(count),
            }
        end
    end
    return expandManifest(manifest)
end

function Professions:NeedsProfile(manifestProfile)
    return #self:NeededProfessions(manifestProfile) > 0
end

function Professions:NeededProfessions(manifestProfile)
    local needed = {}
    if type(manifestProfile) ~= "table" or not manifestProfile.key then return needed end
    local key = fullPlayerName(manifestProfile.key) or manifestProfile.key
    if key == localPlayer() then return needed end
    local current = self:Profiles()[key]
    if not current then
        for professionName in pairs(manifestProfile.professions or {}) do
            if isValidProfessionName(professionName) then needed[#needed + 1] = professionName end
        end
        table.sort(needed)
        return needed
    end
    for professionName, remoteProf in pairs(manifestProfile.professions or {}) do
        local localProf = current.professions and current.professions[professionName]
        local hasRecipes = localProf and (next(localProf.recipes or {}) ~= nil or tonumber(remoteProf.recipeCount or 0) == 0)
        if not localProf or current.manifestOnly or not hasRecipes then
            needed[#needed + 1] = professionName
        elseif remoteProf.scanHash and shortHash(localProf.scanHash or "") ~= tostring(remoteProf.scanHash) then
            needed[#needed + 1] = professionName
        elseif tonumber(localProf.updatedAt or 0) < tonumber(remoteProf.updatedAt or 0) then
            needed[#needed + 1] = professionName
        end
    end
    table.sort(needed)
    return needed
end

function Professions:StoreManifest(manifestProfile, sender)
    if type(manifestProfile) ~= "table" or not manifestProfile.key then return false end
    if not profileIsCurrentGeneration(manifestProfile) then
        ns:Debug("Professions ignored outdated manifest generation from", tostring(sender or "?"), tostring(manifestProfile.dataGeneration or 0))
        return false
    end
    local key = fullPlayerName(manifestProfile.key) or manifestProfile.key
    if key == localPlayer() then return false end
    local profiles = self:Profiles()
    local current = profiles[key]
    if not current then
        manifestProfile.key = key
        manifestProfile.name = manifestProfile.name or shortName(key)
        manifestProfile.dataGeneration = PROFESSION_DATA_GENERATION
        manifestProfile.lastManifestSender = sender
        manifestProfile.deltaCapable = manifestProfile.deltaCapable and true or nil
        for _, remoteProf in pairs(manifestProfile.professions or {}) do
            remoteProf.dataGeneration = PROFESSION_DATA_GENERATION
            remoteProf.lastManifestSender = sender
            remoteProf.deltaCapable = manifestProfile.deltaCapable and true or nil
        end
        profiles[key] = manifestProfile
        self:PanelRefresh()
        return true
    end
    current.name = current.name or manifestProfile.name or shortName(key)
    current.realm = current.realm or manifestProfile.realm
    current.class = current.class or manifestProfile.class
    current.dataGeneration = PROFESSION_DATA_GENERATION
    current.lastManifestSender = sender or current.lastManifestSender
    current.deltaCapable = manifestProfile.deltaCapable or current.deltaCapable
    current.manifestUpdatedAt = math.max(tonumber(current.manifestUpdatedAt or 0) or 0, tonumber(manifestProfile.updatedAt or 0) or 0)
    current.professions = current.professions or {}
    for professionName, remoteProf in pairs(manifestProfile.professions or {}) do
        remoteProf.dataGeneration = PROFESSION_DATA_GENERATION
        remoteProf.lastManifestSender = sender
        remoteProf.deltaCapable = manifestProfile.deltaCapable and true or nil
        local localProf = current.professions[professionName]
        if not localProf then
            current.professions[professionName] = remoteProf
        else
            localProf.lastManifestSender = sender or localProf.lastManifestSender
            localProf.deltaCapable = remoteProf.deltaCapable or localProf.deltaCapable
            localProf.rank = localProf.rank or remoteProf.rank
            localProf.maxRank = localProf.maxRank or remoteProf.maxRank
            localProf.manifestUpdatedAt = math.max(tonumber(localProf.manifestUpdatedAt or 0) or 0, tonumber(remoteProf.updatedAt or 0) or 0)
            localProf.manifestScanHash = remoteProf.scanHash or localProf.manifestScanHash
            localProf.recipeCount = localProf.recipeCount or remoteProf.recipeCount
        end
    end
    ns:Debug("Professions stored manifest from", tostring(sender or "?"), tostring(key))
    self:PanelRefresh()
    return true
end

function Professions:ProcessSendQueue()
    if self.sendingProfile then return end
    self.sendQueue = self.sendQueue or {}
    if self:ActiveIncomingProfileStreams() > 0 then
        if #self.sendQueue == 0 then return end
        ns:Debug("Professions send queue waiting for incoming stream", tostring(#(self.sendQueue or {})))
        self:ScheduleSendQueue(3)
        return
    end
    local job = table.remove(self.sendQueue, 1)
    if not job then return end

    self.sendingProfile = true
    self.activeSendRoute = job.route
    self.activeSendSignature = job.signature
    local sendEpoch = self.sendEpoch or 0
    local index = 1
    local label = job.label or (job.professionName and ("Sending " .. tostring(job.professionName) .. " to guild") or "Sending profession profile to guild")
    self.outgoingStreams = self.outgoingStreams or {}
    local outgoing = {
        at = now(),
        channel = job.channel,
        target = job.target,
        streamId = job.streamId,
        total = job.total,
        messages = {},
    }
    for chunkIndex = 1, job.total do
        local chunk = job.encoded:sub((chunkIndex - 1) * CHUNK_SIZE + 1, chunkIndex * CHUNK_SIZE)
        outgoing.messages[chunkIndex] = ("%s|%s|%d|%d|%s"):format(job.op or PROFILE_OP, cleanAddonField(job.streamId), job.total, chunkIndex, chunk)
    end
    self.outgoingStreams[job.streamId] = outgoing
    ns:Debug("Professions sending profile", tostring(job.channel), tostring(job.target or ""), tostring(job.professionName or "full"), "stream", tostring(job.streamId), "chunks", job.total, "bytes", #job.encoded)

    local function sendNext()
        if (self.sendEpoch or 0) ~= sendEpoch then
            ns:Debug("Professions send aborted by generation reset", tostring(job.streamId))
            return
        end
        if index > job.total then
            ns:Debug("Professions send complete", tostring(job.streamId), tostring(job.total) .. "/" .. tostring(job.total))
            self:SetSyncStatus(job.professionName and ("Shared " .. tostring(job.professionName)) or "Profession profile shared", job.total, job.total, false)
            self.lastSentByRoute = self.lastSentByRoute or {}
            self.lastSentByRoute[job.route] = {
                signature = job.signature,
                at = now(),
            }
            self.sendingProfile = false
            self.activeSendRoute = nil
            self.activeSendSignature = nil
            self:ProcessSendQueue()
            return
        end

        local message = outgoing.messages[index]
        sendAddon(COMM_PREFIX, message, job.channel, job.target)
        if job.duplicateChunks and C_Timer and C_Timer.After then
            local duplicateEpoch = sendEpoch
            C_Timer.After(PROFILE_CHUNK_DUPLICATE_DELAY, function()
                if (self.sendEpoch or 0) == duplicateEpoch then
                    sendAddon(COMM_PREFIX, message, job.channel, job.target)
                end
            end)
        end
        if index == 1 or index == job.total or index % 10 == 0 then
            self:SetSyncStatus(label, index, job.total, true)
        end
        if index == 1 or index == job.total or index % 25 == 0 then
            ns:Debug("Professions sent chunk", tostring(job.streamId), tostring(index) .. "/" .. tostring(job.total))
        end
        index = index + 1
        if C_Timer then
            C_Timer.After(job.delay or CHUNK_DELAY, sendNext)
        else
            sendNext()
        end
    end

    sendNext()
end

function Professions:ScheduleSendQueue(delay)
    if not C_Timer or self.sendQueueScheduled then return end
    self.sendQueueScheduled = true
    C_Timer.After(delay or 3, function()
        self.sendQueueScheduled = false
        self:ProcessSendQueue()
    end)
end

function Professions:CleanupOutgoingStreams()
    local at = now()
    for streamId, stream in pairs(self.outgoingStreams or {}) do
        if at - tonumber(stream.at or 0) > OUTGOING_STREAM_CACHE_AGE then
            self.outgoingStreams[streamId] = nil
        end
    end
end

function Professions:SendStreamRepair(target, streamId, missingText)
    if not target or target == "" or not streamId or streamId == "" then return false end
    local missing = decodeChunkList(missingText)
    if not missing then return false end
    self:CleanupOutgoingStreams()
    local stream = self.outgoingStreams and self.outgoingStreams[streamId]
    if not stream then
        ns:Debug("Professions repair skipped: stream cache expired", tostring(streamId), tostring(target))
        return false
    end
    local sent = 0
    for offset, chunkIndex in ipairs(missing) do
        local message = stream.messages and stream.messages[chunkIndex]
        if message then
            sent = sent + 1
            if C_Timer and C_Timer.After then
                C_Timer.After((sent - 1) * 0.18, function()
                    sendAddon(COMM_PREFIX, message, "WHISPER", target)
                end)
            else
                sendAddon(COMM_PREFIX, message, "WHISPER", target)
            end
        end
    end
    if sent > 0 then
        ns:Debug("Professions repaired stream", tostring(streamId), "to", tostring(target), tostring(sent), "chunks")
        return true
    end
    return false
end

function Professions:SendProfile(channel, target, professionName)
    channel = channel or "GUILD"
    professionName = validProfessionName(professionName)
    if channel == "GUILD" and (not IsInGuild or not IsInGuild()) then return false end
    local profile = self:LocalProfile()
    return self:SendProfileData(profile, channel, target, professionName, false)
end

function Professions:SendProfileData(profile, channel, target, professionName, relayed)
    channel = channel or "GUILD"
    professionName = validProfessionName(professionName)
    if channel == "GUILD" and (not IsInGuild or not IsInGuild()) then return false end
    if profile and profile.key ~= localPlayer() and not profileIsCurrentGeneration(profile) then
        ns:Debug("Professions send skipped: cached profile generation is stale", tostring(profile.key or "?"), tostring(profile.dataGeneration or 0))
        return false
    end
    if not profile or not profile.updatedAt or profile.updatedAt <= 0 then
        ns:Debug("Professions send skipped: no profile")
        return false
    end
    if professionName and not (profile.professions and profile.professions[professionName]) then
        ns:Debug("Professions send skipped: missing profession", tostring(professionName))
        return false
    end
    local encoded = self:EncodeProfile(profile, professionName)
    if not encoded then
        ns:Debug("Professions send skipped: encode failed")
        return false
    end
    self.sendSerial = (self.sendSerial or 0) + 1
    local streamSuffix = professionName and ("-" .. tostring(professionName):gsub("[^%w]", "")) or ""
    local streamId = ("%s-%d-%d%s"):format(shortName(profile.key or localPlayer()) or "player", now(), self.sendSerial, streamSuffix)
    local total = math.max(1, math.ceil(#encoded / CHUNK_SIZE))
    local route = routeKey(channel, target) .. ":" .. tostring(profile.key or "LOCAL") .. ":" .. tostring(professionName or "FULL")
    local signature = tostring(profile.key or "") .. ":" .. tostring(professionName or "FULL") .. ":" .. tostring(profile.updatedAt or "") .. ":" .. tostring(#encoded)
    self.lastSentByRoute = self.lastSentByRoute or {}
    local sent = self.lastSentByRoute[route]
    if sent and sent.signature == signature and now() - tonumber(sent.at or 0) < DUPLICATE_SEND_COOLDOWN then
        ns:Debug("Professions send skipped: identical stream recently sent", route)
        return true
    end
    if self.activeSendRoute == route and self.activeSendSignature == signature then
        ns:Debug("Professions send skipped: identical stream active", route)
        return true
    end
    self.sendQueue = self.sendQueue or {}
    for i = #self.sendQueue, 1, -1 do
        local queued = self.sendQueue[i]
        if queued.route == route then
            if queued.signature == signature then
                ns:Debug("Professions send skipped: identical stream queued", route)
                return true
            end
            table.remove(self.sendQueue, i)
        end
    end
    while #self.sendQueue >= MAX_SEND_QUEUE do
        table.remove(self.sendQueue, 1)
    end
    self.sendQueue[#self.sendQueue + 1] = {
        channel = channel,
        target = target,
        encoded = encoded,
        streamId = streamId,
        total = total,
        route = route,
        signature = signature,
        professionName = professionName,
        delay = professionName and PROFESSION_CHUNK_DELAY or CHUNK_DELAY,
        op = PROFILE_OP,
        label = relayed and ("Relaying " .. tostring(professionName or "professions")) or nil,
        duplicateChunks = true,
    }
    self:ProcessSendQueue()
    return true
end

function Professions:SendDelta(channel, target, professionName, fromHash)
    channel = channel or "WHISPER"
    professionName = validProfessionName(professionName)
    if not professionName or not fromHash then return false end
    local delta = self:ProfessionDelta(professionName, fromHash)
    if not delta then
        ns:Debug("Professions delta unavailable", tostring(target or ""), tostring(professionName), tostring(fromHash))
        return false
    end
    local encoded = self:EncodeDelta(delta)
    if not encoded then
        ns:Debug("Professions delta skipped: encode failed", tostring(professionName))
        return false
    end
    self.sendSerial = (self.sendSerial or 0) + 1
    local streamId = ("%s-%d-%d-D%s"):format(shortName(localPlayer()) or "player", now(), self.sendSerial, tostring(professionName):gsub("[^%w]", ""))
    local total = math.max(1, math.ceil(#encoded / CHUNK_SIZE))
    local route = routeKey(channel, target) .. ":DELTA:" .. tostring(professionName)
    local signature = tostring(professionName) .. ":" .. tostring(delta.f or "") .. ":" .. tostring(delta.t or "") .. ":" .. tostring(#encoded)
    self.lastSentByRoute = self.lastSentByRoute or {}
    local sent = self.lastSentByRoute[route]
    if sent and sent.signature == signature and now() - tonumber(sent.at or 0) < DUPLICATE_SEND_COOLDOWN then
        ns:Debug("Professions delta skipped: identical stream recently sent", route)
        return true
    end
    if self.activeSendRoute == route and self.activeSendSignature == signature then
        ns:Debug("Professions delta skipped: identical stream active", route)
        return true
    end
    self.sendQueue = self.sendQueue or {}
    for i = #self.sendQueue, 1, -1 do
        local queued = self.sendQueue[i]
        if queued.route == route then
            if queued.signature == signature then
                ns:Debug("Professions delta skipped: identical stream queued", route)
                return true
            end
            table.remove(self.sendQueue, i)
        end
    end
    while #self.sendQueue >= MAX_SEND_QUEUE do
        table.remove(self.sendQueue, 1)
    end
    self.sendQueue[#self.sendQueue + 1] = {
        channel = channel,
        target = target,
        encoded = encoded,
        streamId = streamId,
        total = total,
        route = route,
        signature = signature,
        professionName = professionName,
        delay = PROFESSION_CHUNK_DELAY,
        op = DELTA_OP,
        label = "Sending " .. tostring(professionName) .. " delta",
        duplicateChunks = true,
    }
    self:ProcessSendQueue()
    return true
end

function Professions:SendManifest(channel, target)
    channel = channel or "GUILD"
    if channel == "GUILD" and (not IsInGuild or not IsInGuild()) then return false end
    local profile = self:LocalProfile()
    return self:SendManifestForProfile(profile, channel, target, false)
end

function Professions:SendManifestForProfile(profile, channel, target, relayed)
    channel = channel or "GUILD"
    if channel == "GUILD" and (not IsInGuild or not IsInGuild()) then return false end
    if profile and profile.key ~= localPlayer() and not profileIsCurrentGeneration(profile) then
        ns:Debug("Professions manifest skipped: cached profile generation is stale", tostring(profile.key or "?"), tostring(profile.dataGeneration or 0))
        return false
    end
    if not profile or not profile.updatedAt or profile.updatedAt <= 0 then
        ns:Debug("Professions manifest skipped: no profile")
        return false
    end
    local encoded = self:EncodeManifest(profile)
    if not encoded then
        ns:Debug("Professions manifest skipped: encode failed")
        return false
    end
    local route = routeKey(channel, target) .. ":" .. tostring(profile.key or "LOCAL")
    local signature = tostring(profile.updatedAt or "") .. ":" .. tostring(#encoded)
    self.lastManifestByRoute = self.lastManifestByRoute or {}
    local sent = self.lastManifestByRoute[route]
    if sent and sent.signature == signature and now() - tonumber(sent.at or 0) < MANIFEST_SEND_COOLDOWN then
        ns:Debug("Professions manifest skipped: recently sent", route)
        return true
    end
    self.lastManifestByRoute[route] = { signature = signature, at = now() }
    ns:Debug(relayed and "Professions relaying manifest" or "Professions sending manifest", tostring(channel), tostring(target or ""), tostring(profile.key or ""), "bytes", #encoded)
    if self:ActiveIncomingProfileStreams() == 0 and not self.sendingProfile then
        self:SetSyncStatus(relayed and "Relaying profession summary" or (channel == "WHISPER" and "Sending profession summary" or "Sharing profession summary"), 1, 1, false)
    end
    local ok = sendAddon(COMM_PREFIX, MANIFEST_DELTA_OP .. "|" .. encoded, channel, target)
    local legacyOk = MANIFEST_OP ~= MANIFEST_DELTA_OP and sendAddon(COMM_PREFIX, MANIFEST_OP .. "|" .. encoded, channel, target)
    return ok or legacyOk
end

function Professions:ProfileHasProfessionData(profile, professionName)
    if type(profile) ~= "table" or profile.manifestOnly then return false end
    if not profileIsCurrentGeneration(profile) then return false end
    professionName = validProfessionName(professionName)
    if professionName then
        local profession = profile.professions and profile.professions[professionName]
        return profession and (profession.isSkill or next(profession.recipes or {}) ~= nil or tonumber(profession.recipeCount or 0) == 0) and true or false
    end
    for name, profession in pairs(profile.professions or {}) do
        if isValidProfessionName(name) and (profession.isSkill or next(profession.recipes or {}) ~= nil or tonumber(profession.recipeCount or 0) == 0) then
            return true
        end
    end
    return false
end

function Professions:SendCachedManifests(channel, target, limit)
    channel = channel or "WHISPER"
    limit = tonumber(limit or CACHED_MANIFESTS_PER_REQUEST) or CACHED_MANIFESTS_PER_REQUEST
    if limit <= 0 then return 0 end
    local localKey = localPlayer()
    local rows = {}
    for key, profile in pairs(self:Profiles()) do
        if key ~= localKey and profileIsCurrentGeneration(profile) and self:ProfileHasProfessionData(profile) then
            rows[#rows + 1] = {
                key = key,
                profile = profile,
                updatedAt = tonumber(profile.updatedAt or profile.manifestUpdatedAt or 0) or 0,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        return tostring(a.key) < tostring(b.key)
    end)
    local sent = 0
    for _, row in ipairs(rows) do
        if sent >= limit then break end
        if self:SendManifestForProfile(row.profile, channel, target, true) then
            sent = sent + 1
        end
    end
    return sent
end

function Professions:RequestProfileFrom(sender, manifestProfile, maxProfessions)
    if not sender or sender == "" then return false, 0 end
    local key = fullPlayerName(manifestProfile and manifestProfile.key or sender) or sender
    local target = sender
    local needed = self:NeededProfessions(manifestProfile)
    if #needed == 0 then return false, 0 end
    maxProfessions = tonumber(maxProfessions or #needed) or #needed
    self.lastWantByProfile = self.lastWantByProfile or {}
    self.scheduledWantByProfile = self.scheduledWantByProfile or {}
    local sent = 0

    for _, professionName in ipairs(needed) do
        if sent >= maxProfessions then break end
        local requestKey = key .. ":" .. professionName
        local unavailable = self:ProfileRequestUnavailable(key, professionName)
        if unavailable then
            ns:Debug("Professions profile request suppressed: temporarily unavailable", tostring(key), tostring(sender), tostring(professionName))
        elseif self.scheduledWantByProfile[requestKey] then
            ns:Debug("Professions profile request already scheduled", tostring(key), tostring(sender), tostring(professionName))
        else
            local last = self.lastWantByProfile[requestKey]
            if last and now() - last < WANT_PROFILE_COOLDOWN then
                ns:Debug("Professions profile request throttled", tostring(key), tostring(sender), tostring(professionName))
            else
                self.scheduledWantByProfile[requestKey] = true
                sent = sent + 1
                local progressIndex = sent
                local delay = (math.random and math.random(1, 3) or 2) + ((sent - 1) * 1.2)
                local function sendWant()
                    self.scheduledWantByProfile[requestKey] = nil
                    if self:ProfileRequestUnavailable(key, professionName) then
                        ns:Debug("Professions request skipped: temporarily unavailable", tostring(key), tostring(professionName))
                        return
                    end
                    local stillNeeded = false
                    for _, neededProfession in ipairs(self:NeededProfessions(manifestProfile)) do
                        if neededProfession == professionName then
                            stillNeeded = true
                            break
                        end
                    end
                    if not stillNeeded then
                        self:ClearProfileRequestState(key, professionName)
                        ns:Debug("Professions request skipped: already synced", tostring(key), tostring(professionName))
                        return
                    end
                    local activeStreams = self:ActiveIncomingProfileStreams()
                    if activeStreams >= MAX_ACTIVE_PROFILE_STREAMS then
                        ns:Debug("Professions request delayed for active streams", tostring(activeStreams), tostring(key), tostring(professionName))
                        self:SetSyncStatus("Waiting for profession streams", activeStreams, MAX_ACTIVE_PROFILE_STREAMS, true)
                        self:QueueProfileRequest(sender, manifestProfile)
                        self:ScheduleProfileRequestFlush(PROFILE_REQUEST_FLUSH_INTERVAL)
                        return
                    end
                    ns:Debug("Professions requesting", tostring(professionName), "from", tostring(target))
                    self:SetSyncStatus("Requesting " .. tostring(professionName) .. " from " .. shortName(target), progressIndex, math.min(#needed, maxProfessions), true)
                    self.lastWantByProfile[requestKey] = now()
                    self:RecordProfileRequestAttempt(key, professionName)
                    sendAddon(COMM_PREFIX, ("%s|%s|%d|%s|%s"):format(WANT_OP, cleanAddonField(localPlayer() or ""), now(), cleanAddonField(professionName), cleanAddonField(key)), "WHISPER", target)
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(delay, sendWant)
                else
                    sendWant()
                end
            end
        end
    end
    return sent > 0, sent
end

function Professions:AutoShare()
    local store = self:Store()
    local settings = store and store.settings or {}
    if settings.autoGuildSync == false then return false end
    if not IsInGuild or not IsInGuild() then return false end
    local at = now()
    local wait = self.lastAutoShareAt and (AUTO_SHARE_COOLDOWN - (at - self.lastAutoShareAt)) or 0
    if wait and wait > 0 then
        if not self.shareQueued and C_Timer then
            self.shareQueued = true
            C_Timer.After(wait + 0.1, function()
                self.shareQueued = false
                self.lastAutoShareAt = now()
                self:SendManifest("GUILD")
            end)
        end
        return false
    end
    self.lastAutoShareAt = at
    return self:SendManifest("GUILD")
end

function Professions:RequestSync()
    if not IsInGuild or not IsInGuild() then
        ns:Print("Join a guild before requesting profession sync.", "warning")
        return false
    end
    local at = now()
    if self.lastRequestSyncAt and at - self.lastRequestSyncAt < REQUEST_SYNC_COOLDOWN then
        ns:Print("Profession sync was already requested. Please wait a moment.", "warning")
        return false
    end
    self.lastRequestSyncAt = at
    ns:Debug("Professions requesting sync over GUILD")
    self:SetSyncStatus("Requesting guild profession summaries", 1, 1, true)
    self.manualSyncUntil = at + MANUAL_SYNC_WINDOW
    self.lastPendingProfileFlushAt = nil
    self:FlushPendingProfileRequests()
    sendAddon(COMM_PREFIX, ("%s|%s|%d"):format(REQUEST_OP, cleanAddonField(localPlayer() or ""), at), "GUILD")
    ns:Print("Profession sync requested.", "success")
    return true
end

function Professions:ReceiveProfile(profile, sender)
    if type(profile) ~= "table" or not profile.key then
        ns:Debug("Professions received invalid profile from", tostring(sender or "?"))
        return false
    end
    if not profileIsCurrentGeneration(profile) then
        ns:Debug("Professions ignored outdated profile generation from", tostring(sender or "?"), tostring(profile.dataGeneration or 0))
        return false
    end
    self:PruneInvalidProfessions(profile)
    local profiles = self:Profiles()
    local key = fullPlayerName(profile.key) or profile.key
    local current = profiles[key]
    local partialProfession = validProfessionName(profile.partialProfession)
    if partialProfession then
        local incomingProf = profile.professions and profile.professions[partialProfession]
        if not incomingProf then
            ns:Debug("Professions ignored empty partial profile from", tostring(sender or "?"), tostring(key), tostring(partialProfession))
            return false
        end
        current = current or {
            key = key,
            name = profile.name or shortName(key),
            realm = profile.realm,
            class = profile.class,
            professions = {},
            updatedAt = 0,
            dataGeneration = PROFESSION_DATA_GENERATION,
        }
        current.key = key
        current.name = profile.name or current.name or shortName(key)
        current.realm = profile.realm or current.realm
        current.class = profile.class or current.class
        current.dataGeneration = PROFESSION_DATA_GENERATION
        current.professions = current.professions or {}
        local existing = current.professions[partialProfession]
        if existing
            and not current.manifestOnly
            and next(existing.recipes or {}) ~= nil
            and incomingProf.scanHash
            and existing.scanHash == incomingProf.scanHash
            and tonumber(existing.updatedAt or 0) >= tonumber(incomingProf.updatedAt or 0)
        then
            ns:Debug("Professions ignored stale partial profile from", tostring(sender or "?"), tostring(key), tostring(partialProfession))
            return false
        end
        incomingProf.dataGeneration = PROFESSION_DATA_GENERATION
        current.professions[partialProfession] = incomingProf
        current.updatedAt = math.max(tonumber(current.updatedAt or 0) or 0, tonumber(profile.updatedAt or 0) or 0, tonumber(incomingProf.updatedAt or 0) or 0)
        current.manifestOnly = nil
        current.manifestUpdatedAt = nil
        profiles[key] = current
        ns:Debug("Professions stored", tostring(partialProfession), "from", tostring(sender or "?"), tostring(key))
        self:ClearProfileRequestState(key, partialProfession)
        if self:ActiveIncomingProfileStreams() == 0 and not self.sendingProfile then
            self:SetSyncStatus("Synced " .. tostring(partialProfession) .. " from " .. shortName(sender or key), 1, 1, false)
        end
        self:PanelRefresh()
        self:ScheduleProfileRequestFlush(1)
        return true
    end
    if current and not current.manifestOnly and tonumber(current.updatedAt or 0) >= tonumber(profile.updatedAt or 0) then
        ns:Debug("Professions ignored stale profile from", tostring(sender or "?"), tostring(key))
        return false
    end
    profile.key = key
    profile.name = profile.name or shortName(key)
    profile.dataGeneration = PROFESSION_DATA_GENERATION
    profile.manifestOnly = nil
    profile.manifestUpdatedAt = nil
    profiles[key] = profile
    ns:Debug("Professions stored profile from", tostring(sender or "?"), tostring(key))
    self:ClearProfileRequestState(key)
    self:PanelRefresh()
    self:ScheduleProfileRequestFlush(1)
    return true
end

function Professions:RequestFullProfileFrom(sender, professionName)
    professionName = validProfessionName(professionName)
    if not sender or sender == "" or not professionName then return false end
    ns:Debug("Professions requesting full fallback", tostring(professionName), "from", tostring(sender))
    sendAddon(COMM_PREFIX, ("%s|%s|%d|%s"):format(WANT_OP, cleanAddonField(localPlayer() or ""), now(), cleanAddonField(professionName)), "WHISPER", sender)
    return true
end

function Professions:ApplyDelta(delta, sender)
    if type(delta) ~= "table" or not delta.k or not delta.p or not delta.f or not delta.t then
        ns:Debug("Professions ignored invalid delta from", tostring(sender or "?"))
        return false
    end
    if tonumber(delta.g or 0) < PROFESSION_DATA_GENERATION then
        ns:Debug("Professions ignored outdated delta generation from", tostring(sender or "?"), tostring(delta.g or 0))
        return false
    end
    local key = fullPlayerName(delta.k) or delta.k
    local professionName = validProfessionName(delta.p)
    if not key or not professionName then return false end
    local profiles = self:Profiles()
    local current = profiles[key]
    local profession = current and current.professions and current.professions[professionName]
    if not profession or profession.scanHash ~= delta.f then
        ns:Debug("Professions delta base mismatch from", tostring(sender or "?"), tostring(professionName), tostring(profession and profession.scanHash or "missing"), tostring(delta.f))
        self:RequestFullProfileFrom(sender, professionName)
        return false
    end

    local recipes = {}
    for recipeKey, recipe in pairs(profession.recipes or {}) do
        recipes[recipeKey] = recipe
    end
    for _, recipeKey in ipairs(delta.rm or {}) do
        recipes[tostring(recipeKey)] = nil
    end
    for _, recipeId in ipairs(decodeRecipeIds(delta.ids) or {}) do
        local recipe = normalizeRecipe({
            recipeId = recipeId,
            recipeLink = "spell:" .. tostring(recipeId),
        })
        if recipe then recipes[recipe.key] = recipe end
    end
    for _, row in ipairs(delta.rs or {}) do
        local recipe = expandCompactRecipe(row)
        if recipe then recipes[recipe.key] = recipe end
    end

    current.key = key
    current.name = delta.n or current.name or shortName(key)
    current.realm = delta.r or current.realm
    current.class = delta.c or current.class
    current.professions = current.professions or {}
    current.updatedAt = math.max(tonumber(current.updatedAt or 0) or 0, tonumber(delta.u or 0) or 0, tonumber(delta.pu or 0) or 0)
    current.manifestOnly = nil
    current.manifestUpdatedAt = nil
    current.professions[professionName] = {
        dataGeneration = PROFESSION_DATA_GENERATION,
        name = professionName,
        rank = delta.pr or profession.rank,
        maxRank = delta.pm or profession.maxRank,
        updatedAt = delta.pu or current.updatedAt,
        scanHash = delta.t,
        recipes = recipes,
    }
    profiles[key] = current
    ns:Debug("Professions applied delta", tostring(professionName), "from", tostring(sender or "?"), tostring(#(delta.rs or {})) .. " changed", tostring(#(delta.rm or {})) .. " removed")
    if self:ActiveIncomingProfileStreams() == 0 and not self.sendingProfile then
        self:SetSyncStatus("Synced " .. tostring(professionName) .. " changes from " .. shortName(sender or key), 1, 1, false)
    end
    self:PanelRefresh()
    self:ScheduleProfileRequestFlush(1)
    return true
end

function Professions:ScheduleIncomingTimeout(key, streamId)
    if not C_Timer then return end
    self.incoming = self.incoming or {}
    local stream = self.incoming[key]
    if not stream then return end
    stream.timeoutToken = (stream.timeoutToken or 0) + 1
    local token = stream.timeoutToken
    local timeout = stream.lateStart and LATE_STREAM_STALL_TIMEOUT or STREAM_STALL_TIMEOUT
    C_Timer.After(timeout, function()
        local current = self.incoming and self.incoming[key]
        if not current or current.timeoutToken ~= token then return end
        local currentTimeout = current.lateStart and LATE_STREAM_STALL_TIMEOUT or STREAM_STALL_TIMEOUT
        if now() - tonumber(current.at or 0) < currentTimeout then return end
        local missing = {}
        for i = 1, tonumber(current.total or 0) do
            if not current.chunks[i] then
                missing[#missing + 1] = i
                if #missing >= 8 then break end
            end
        end
        ns:Debug("Professions stream stalled", tostring(current.sender or "?"), tostring(streamId), tostring(current.received or 0) .. "/" .. tostring(current.total or 0), "missing", table.concat(missing, ","))
        local missingText = encodeChunkList(missing)
        if missingText and not current.repairRequestedAt then
            current.repairRequestedAt = now()
            current.at = now()
            current.timeoutToken = (current.timeoutToken or 0) + 1
            sendAddon(COMM_PREFIX, ("%s|%s|%s"):format(REPAIR_OP, cleanAddonField(streamId), cleanAddonField(missingText)), "WHISPER", current.sender)
            self:SetSyncStatus("Profession stream missed data; requesting repair", current.received or 0, current.total or 1, true)
            ns:Debug("Professions requested stream repair", tostring(current.sender or "?"), tostring(streamId), missingText)
            self:ScheduleIncomingTimeout(key, streamId)
            return
        end
        self:SetSyncStatus("Profession stream missed data; retrying", current.received or 0, current.total or 1, true)
        self.incoming[key] = nil
        self.lastPendingProfileFlushAt = nil
        self.lastWantByProfile = {}
        self.scheduledWantByProfile = {}
        self:ScheduleSendQueue(1)
        self:ScheduleProfileRequestFlush(1)
    end)
end

function Professions:CleanupIncoming()
    local at = now()
    if self.incoming then
        for key, stream in pairs(self.incoming) do
            if at - tonumber(stream.at or 0) > INCOMING_CLEANUP_AGE then
                ns:Debug("Professions incoming cleanup", tostring(stream.sender or "?"), tostring(key), tostring(stream.received or 0) .. "/" .. tostring(stream.total or 0))
                self.incoming[key] = nil
            end
        end
    end
    if self.completedIncoming then
        for key, completedAt in pairs(self.completedIncoming) do
            if at - tonumber(completedAt or 0) > INCOMING_CLEANUP_AGE then
                self.completedIncoming[key] = nil
            end
        end
    end
    if self.rejectedIncoming then
        for key, rejectedAt in pairs(self.rejectedIncoming) do
            if at - tonumber(rejectedAt or 0) > INCOMING_CLEANUP_AGE then
                self.rejectedIncoming[key] = nil
            end
        end
    end
end

function Professions:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    self:CleanupIncoming()
    local op, rest = strsplit("|", message or "", 2)
    if sender == UnitName("player") or sender == localPlayer() then
        if op ~= PROFILE_OP then
            ns:Debug("Professions ignored own addon message", tostring(channel), tostring(op or "?"))
        end
        return
    end
    if op ~= PROFILE_OP and op ~= DELTA_OP then
        ns:Debug("Professions addon message", tostring(op or "?"), "from", tostring(sender or "?"), "via", tostring(channel or "?"))
    end
    if op ~= REQUEST_OP
        and op ~= WANT_OP
        and op ~= WANT_DELTA_OP
        and op ~= REPAIR_OP
        and op ~= MANIFEST_OP
        and op ~= PROFILE_OP
        and op ~= DELTA_OP
    then
        ns:Debug("Professions ignored outdated sync op", tostring(op), "from", tostring(sender or "?"))
        return
    end
    if op == REQUEST_OP then
        self.lastRequestResponseBySender = self.lastRequestResponseBySender or {}
        local key = lower(sender or "?")
        local last = self.lastRequestResponseBySender[key]
        if last and now() - last < REQUEST_RESPONSE_COOLDOWN then
            ns:Debug("Professions request response throttled for", tostring(sender or "?"))
            return
        end
        self.lastRequestResponseBySender[key] = now()
        if sender and sender ~= "" then
            local delay = math.random and math.random(1, 8) or 4
            if C_Timer and C_Timer.After then
                C_Timer.After(delay, function()
                    if not self:SendManifest("WHISPER", sender) then
                        ns:Debug("Professions request response had no manifest for", tostring(sender))
                    end
                end)
            elseif not self:SendManifest("WHISPER", sender) then
                ns:Debug("Professions request response had no manifest for", tostring(sender))
            end
        else
            self:AutoShare()
        end
        return
    end
    if op == REPAIR_OP then
        local streamId, missingText = strsplit("|", rest or "", 2)
        if not self:SendStreamRepair(sender, streamId, missingText) then
            ns:Debug("Professions repair request could not be served", tostring(sender or "?"), tostring(streamId or "?"))
        end
        return
    end
    if op == WANT_OP or op == WANT_DELTA_OP then
        self.lastWantResponseBySender = self.lastWantResponseBySender or {}
        local requester, requestAt, professionName, knownHash, ownerKey
        if op == WANT_DELTA_OP then
            requester, requestAt, professionName, knownHash = strsplit("|", rest or "", 4)
        else
            requester, requestAt, professionName, ownerKey = strsplit("|", rest or "", 4)
        end
        professionName = validProfessionName(professionName)
        local replyTarget = fullPlayerName(requester) or sender
        local wantsDelta = op == WANT_DELTA_OP and knownHash and knownHash ~= ""
        local profileKey = fullPlayerName(ownerKey) or localPlayer()
        local relayProfile = profileKey and self:Profiles()[profileKey] or nil
        if profileKey ~= localPlayer() then
            ns:Debug("Professions owner-only request skipped", tostring(profileKey or "?"), tostring(professionName or "full"))
            return
        end
        local key = lower(tostring(sender or "?") .. ":" .. tostring(profileKey or "LOCAL") .. ":" .. tostring(professionName or "FULL") .. ":" .. tostring(wantsDelta and "D" or "F"))
        local last = self.lastWantResponseBySender[key]
        if last and now() - last < WANT_RESPONSE_COOLDOWN then
            ns:Debug("Professions WANT response throttled for", tostring(sender or "?"), tostring(professionName or "full"))
            return
        end
        self.lastWantResponseBySender[key] = now()
        if sender and sender ~= "" then
            local delay = ownerKey and (math.random and math.random(4, 12) or 8) or (math.random and math.random(1, 4) or 2)
            if C_Timer and C_Timer.After then
                C_Timer.After(delay, function()
                    local sent = self:SendProfile("WHISPER", replyTarget, professionName)
                    if not sent then
                        ns:Debug("Professions WANT response had no profile for", tostring(replyTarget), tostring(professionName or "full"))
                    end
                end)
            else
                local sent = self:SendProfile("WHISPER", replyTarget, professionName)
                if not sent then
                    ns:Debug("Professions WANT response had no profile for", tostring(replyTarget), tostring(professionName or "full"))
                end
            end
        end
        return
    end
    if op == MANIFEST_OP or op == MANIFEST_DELTA_OP then
        local manifestProfile = self:DecodeManifest(rest or "")
        if not manifestProfile then
            ns:Debug("Professions invalid manifest from", tostring(sender or "?"))
            return
        end
        manifestProfile.deltaCapable = op == MANIFEST_DELTA_OP and true or manifestProfile.deltaCapable
        if not self:StoreManifest(manifestProfile, sender) then
            return
        end
        if self:NeedsProfile(manifestProfile) then
            self:QueueProfileRequest(sender, manifestProfile)
            self:FlushPendingProfileRequests()
        end
        return
    end
    local deltaStream = op == DELTA_OP
    if op ~= PROFILE_OP and not deltaStream then
        ns:Debug("Professions ignored unknown op", tostring(op or "?"))
        return
    end

    local streamId, total, index, chunk = strsplit("|", rest or "", 4)
    total = tonumber(total)
    index = tonumber(index)
    if not streamId or not total or not index or not chunk then
        ns:Debug("Professions ignored malformed chunk from", tostring(sender or "?"))
        return
    end
    local key = tostring(sender or "?") .. ":" .. streamId
    self.rejectedIncoming = self.rejectedIncoming or {}
    self.completedIncoming = self.completedIncoming or {}
    if self.completedIncoming[key] then return end
    if self.rejectedIncoming[key] then return end
    if total < 1 or total > MAX_INCOMING_CHUNKS or index < 1 or index > total then
        ns:Debug("Professions ignored invalid stream bounds from", tostring(sender or "?"), tostring(index) .. "/" .. tostring(total))
        self:SetSyncStatus("Ignored invalid profession sync from " .. shortName(sender), 1, 1, false)
        self.rejectedIncoming[key] = now()
        return
    end
    self.incoming = self.incoming or {}
    local stream = self.incoming[key]
    if not stream then
        stream = { total = total, chunks = {}, received = 0, at = now(), startedAt = now(), sender = sender, streamId = streamId, lateStart = index ~= 1 }
        self.incoming[key] = stream
        ns:Debug("Professions receiving profile", tostring(sender or "?"), "stream", tostring(streamId), "chunks", total, "first", tostring(index))
        local primary = self:PrimaryIncomingStream()
        if primary and primary.key == key and not self.sendingProfile then
            self:SetSyncStatus("Receiving professions from " .. shortName(sender), 0, total, true)
        else
            ns:Debug("Professions receiving queued background stream", tostring(sender or "?"), tostring(streamId))
        end
        self:ScheduleIncomingTimeout(key, streamId)
    elseif tonumber(stream.total or 0) ~= total then
        ns:Debug("Professions ignored stream total mismatch from", tostring(sender or "?"), tostring(streamId), tostring(stream.total), tostring(total))
        self.incoming[key] = nil
        self.rejectedIncoming[key] = now()
        return
    end
    if not stream.chunks[index] then
        stream.chunks[index] = chunk
        stream.received = stream.received + 1
        if index == 1 then stream.lateStart = nil end
    end
    stream.at = now()
    self:ScheduleIncomingTimeout(key, streamId)
    local primary = self:PrimaryIncomingStream()
    if primary and primary.key == key and not self.sendingProfile and (index == 1 or index == total or index % 10 == 0) then
        self:SetSyncStatus("Receiving professions from " .. shortName(sender), stream.received, stream.total, true)
    end
    if index == 1 or index == total or index % 25 == 0 then
        ns:Debug("Professions chunk", tostring(sender or "?"), tostring(streamId), index .. "/" .. total)
    end
    if stream.received < stream.total then return end

    self.incoming[key] = nil
    self.completedIncoming[key] = now()
    self:ScheduleSendQueue(1)
    local encoded = table.concat(stream.chunks)
    if not b64url or not b64url.decode or not json or not json.decode then
        ns:Debug("Professions decode unavailable")
        self:SetSyncStatus("Profession sync decode unavailable", 1, 1, false)
        return
    end
    local raw = b64url.decode(encoded)
    if not raw then
        ns:Debug("Professions b64 decode failed from", tostring(sender or "?"))
        self:SetSyncStatus("Profession sync decode failed", 1, 1, false)
        return
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        ns:Debug("Professions json decode failed from", tostring(sender or "?"))
        self:SetSyncStatus("Profession sync data was invalid", 1, 1, false)
        return
    end
    local decodedVersion = tonumber(decoded.v or 0)
    if decodedVersion ~= PROTOCOL_VERSION then
        ns:Debug("Professions protocol mismatch from", tostring(sender or "?"), tostring(decoded.v))
        self:SetSyncStatus("Ignored outdated profession data from " .. shortName(sender), 1, 1, false)
        return
    end
    if deltaStream then
        self:ApplyDelta(decoded.profession, sender)
        return
    end
    self:ReceiveProfile(decoded.compact and expandCompactProfile(decoded.profile) or decoded.profile, sender)
end

function Professions:KnownProfessionNames()
    local seen, list = {}, {}
    for _, profile in pairs(self:Profiles()) do
        for name in pairs(profile.professions or {}) do
            if isValidProfessionName(name) and not seen[name] then
                seen[name] = true
                list[#list + 1] = name
            end
        end
    end
    table.sort(list, function(a, b)
        local as, bs = isSecondaryProfession(a), isSecondaryProfession(b)
        if as ~= bs then return not as end
        return tostring(a or "") < tostring(b or "")
    end)
    return list
end

function Professions:RecipeRows(filterText, professionFilter)
    filterText = lower(filterText or "")
    professionFilter = professionFilter or "ALL"
    local rows = {}
    for _, profile in pairs(self:Profiles()) do
        for professionName, profession in pairs(profile.professions or {}) do
            if isValidProfessionName(professionName) and (professionFilter == "ALL" or professionFilter == professionName) then
                for _, recipe in pairs(profession.recipes or {}) do
                    local hay = lower(table.concat({
                        profile.name or "",
                        profile.key or "",
                        professionName or "",
                        recipe.name or "",
                        recipe.itemName or "",
                    }, " "))
                    if filterText == "" or hay:find(filterText, 1, true) then
                        rows[#rows + 1] = {
                            profile = profile,
                            profession = profession,
                            professionName = professionName,
                            recipe = recipe,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local ap, bp = a.professionName or "", b.professionName or ""
        if ap ~= bp then return ap < bp end
        local ar, br = a.recipe.name or "", b.recipe.name or ""
        if ar ~= br then return ar < br end
        return (a.profile.name or "") < (b.profile.name or "")
    end)
    return rows
end

function Professions:PendingCraftProfileCount()
    local count = 0
    for key, profile in pairs(self:Profiles()) do
        if key ~= localPlayer() and type(profile) == "table" and self:HasRequestableProfessions(profile) then
            count = count + 1
        end
    end
    return count
end

function Professions:FishingRows(filterText, professionFilter)
    if professionFilter ~= "Fishing" then return {} end
    filterText = lower(filterText or "")
    local rows = {}
    for _, profile in pairs(self:Profiles()) do
        local profession = profile.professions and profile.professions.Fishing
        if profession then
            local hay = lower(table.concat({
                profile.name or "",
                profile.key or "",
                "Fishing",
                tostring(profession.rank or ""),
                tostring(profession.maxRank or ""),
            }, " "))
            if filterText == "" or hay:find(filterText, 1, true) then
                rows[#rows + 1] = {
                    profile = profile,
                    profession = profession,
                    professionName = "Fishing",
                    rank = tonumber(profession.rank or 0) or 0,
                    maxRank = tonumber(profession.maxRank or 0) or 0,
                    updatedAt = profession.updatedAt or profile.updatedAt,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
        if (a.maxRank or 0) ~= (b.maxRank or 0) then return (a.maxRank or 0) > (b.maxRank or 0) end
        return tostring(a.profile and (a.profile.name or a.profile.key) or "") < tostring(b.profile and (b.profile.name or b.profile.key) or "")
    end)
    return rows
end

function Professions:OnInit()
    registerPrefix(COMM_PREFIX)
end

function Professions:OnEnable()
    if self._enabled then return end
    self._enabled = true
    registerPrefix(COMM_PREFIX)
    self:HookSkillFrame()
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function() self:HookSkillFrame() end)
    end
    local Events = ns:GetModule("Events")
    if Events then
        Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
            self:OnAddonMessage(prefix, message, channel, sender)
        end, "Professions")
        Events:On("TRADE_SKILL_SHOW", function() self:ScheduleScan() end, "Professions")
        Events:On("TRADE_SKILL_UPDATE", function() self:ScheduleScan() end, "Professions")
        Events:On("CRAFT_SHOW", function() self:ScheduleScan() end, "Professions")
        Events:On("CRAFT_UPDATE", function() self:ScheduleScan() end, "Professions")
        Events:On("PLAYER_ENTERING_WORLD", function() self:ScheduleSkillScan() end, "Professions")
        Events:On("SKILL_LINES_CHANGED", function() self:ScheduleSkillScan() end, "Professions")
    end
    if IsInGuild and IsInGuild() and C_Timer then
        local jitter = math.random and math.random(30, 120) or 60
        C_Timer.After(jitter, function() self:AutoShare() end)
    end
end





