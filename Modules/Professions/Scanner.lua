local ADDON, ns = ...

local Scanner = ns:NewModule("ProfessionsScanner")

local function Store() return ns:GetModule("ProfessionsStore") end

local function lowerStr(v) return string.lower(tostring(v or "")) end

local function isFishingName(name)
    local l = lowerStr(name)
    if l == "fishing" then return true end
    local loc = (PROFESSIONS_FISHING or FISHING or "Fishing")
    return l == lowerStr(loc)
end

-- Pure: given skill-line rows {name, isHeader, isExpanded, rank, maxRank}, return the
-- Fishing (rank, maxRank) or nil. Header rows skipped; rank must be > 0.
function Scanner:ResolveFishingFromSkillLines(rows)
    for _, row in ipairs(rows or {}) do
        if row and not row.isHeader and isFishingName(row.name) then
            local rank = tonumber(row.rank or 0) or 0
            local maxRank = tonumber(row.maxRank or 0) or 0
            if rank > 0 and maxRank > 0 then return rank, maxRank end
        end
    end
    return nil
end

local function idFromRecipeLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("enchant:(%d+)") or link:match("spell:(%d+)") or link:match("trade:(%d+)")
    return id and tonumber(id) or nil
end

local function idFromItemLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- Pure core: rows is a list of { name, recipeType, recipeLink, itemLink }.
-- Returns (spellIds[], unmappedCount). Resolution chain (first hit wins):
--   1. recipe link -> Store:ResolveSpellId (spell/enchant/trade/effect id)
--   2. item link   -> Store:ResolveSpellIdByItem(itemId, skillLineId)
--   3. recipe name -> Store:ResolveSpellIdByName(professionName, name)
-- professionName must be the English canonical name for (3) to work.
-- skillLineId may be nil; ResolveSpellIdByItem then returns any matching profession.
function Scanner:ResolveRows(rows, professionName, skillLineId)
    local store = Store()
    local seen, spellIds, unmapped = {}, {}, 0
    for _, row in ipairs(rows or {}) do
        if row and row.recipeType ~= "header" and row.name then
            local rawId = idFromRecipeLink(row.recipeLink)
            local spellId = rawId and store:ResolveSpellId(rawId)
            -- Fallback 2: resolve via crafted-item id
            if not spellId then
                local itemId = idFromItemLink(row.itemLink)
                spellId = store:ResolveSpellIdByItem(itemId, skillLineId)
            end
            -- Fallback 3: resolve via localized recipe name (requires English professionName)
            if not spellId then
                spellId = store:ResolveSpellIdByName(professionName, row.name)
            end
            if spellId then
                if not seen[spellId] then seen[spellId] = true; spellIds[#spellIds + 1] = spellId end
            else
                local itemId = idFromItemLink(row.itemLink)
                unmapped = unmapped + 1
                ns:Debug("Professions unmapped", tostring(professionName), tostring(rawId or "?"), tostring(itemId or "?"), tostring(row.name or ""))
            end
        end
    end
    table.sort(spellIds)
    return spellIds, unmapped
end

-- Writes to Store; returns true if the profession hash OR unmapped count changed.
function Scanner:CommitScan(professionName, rank, maxRank, skillLineId, spellIds, unmappedCount)
    local store = Store()
    local profile = store:LocalProfile()
    local key = profile and profile.key
    if not key then return false end
    local newHash = store:ProfessionHash(spellIds, rank, maxRank)
    local existing = profile.professions[professionName]
    if existing and existing.hash == newHash and (existing.unmappedCount or 0) == (unmappedCount or 0) then
        return false
    end
    store:SetProfession(key, professionName, {
        skillLineId = skillLineId, rank = rank, maxRank = maxRank,
        spellIds = spellIds, unmappedCount = unmappedCount,
    }, "owner")
    return true
end

-- Derives the canonical English profession name + skillLineId from resolved spell ids,
-- so data is keyed locale-independently (the WoW API returns a localized name).
function Scanner:CanonicalProfession(spellIds, fallbackName)
    local db = ns.professionRecipeDB
    local counts = {}
    for _, spellId in ipairs(spellIds or {}) do
        local info = db and db.bySpellId and db.bySpellId[spellId]
        local p = info and info.p
        if p then counts[p] = (counts[p] or 0) + 1 end
    end
    local bestLine, bestCount
    for line, c in pairs(counts) do
        if not bestCount or c > bestCount then bestLine, bestCount = line, c end
    end
    if bestLine and db.skillLines and db.skillLines[bestLine] then
        return db.skillLines[bestLine], bestLine
    end
    return fallbackName, nil
end

-- Reads the open profession window via WoW APIs into rows, then resolves+commits.
-- Returns (professionName, changed) or nil if no profession is open.
--
-- Two-pass resolution breaks the chicken-and-egg dependency between CanonicalProfession
-- (which needs resolved spell ids to determine the English name + skillLineId) and
-- ResolveSpellIdByName (which needs the English professionName):
--   Pass 1: link + item resolution only (no professionName/skillLineId needed).
--           The resulting seed ids are fed to CanonicalProfession to derive the
--           canonical English name and skillLineId.
--   Pass 2: full resolution chain (link → item → name) using the now-known English
--           professionName and skillLineId. This final result is what gets committed.
--
-- Edge case: if pass 1 yields zero ids (e.g. pure Craft-frame profession where every
-- recipe has neither a parseable link nor a crafted item), CanonicalProfession falls
-- back to rawProfessionName with nil skillLineId. The name resolver then filters by
-- a potentially localized name that won't match English skillLines, so those recipes
-- remain unmapped and are logged. In practice most Craft recipes have a crafted item
-- (rods, oils, wands) that seeds the canonical profession on pass 1.
function Scanner:ScanOpen()
    local rows, rawProfessionName, rank, maxRank = self:ReadOpenProfession()
    if not rawProfessionName then return nil end
    -- First pass: link + item resolution (no profession-name dependency) to seed canonical detection.
    local seedIds = self:ResolveRows(rows, nil, nil)
    local professionName, skillLineId = self:CanonicalProfession(seedIds, rawProfessionName)
    if not skillLineId then
        ns:Debug("Professions: could not identify skill line for", tostring(rawProfessionName),
            "- name-based resolution unavailable (localized client?). Recipes may show unmapped.")
    end
    -- Final pass: now we have the English profession name + skill line, so name/item resolution works.
    local spellIds, unmapped = self:ResolveRows(rows, professionName, skillLineId)
    local changed = self:CommitScan(professionName, rank, maxRank, skillLineId, spellIds, unmapped)
    if changed then
        local sync = ns:GetModule("ProfessionsSync")
        if sync and sync.OnLocalChange then sync:OnLocalChange(professionName) end
    end
    -- Manual scans also refresh fishing (it has no trade/craft window). ScanFishingSkill
    -- is a no-op unless the fishing rank actually changed, so this won't double-broadcast.
    self:ScanFishingSkill()
    return professionName, changed
end

-- Reads the live WoW trade-skill / craft window. Returns rows + header info.
-- Split out so ScanOpen logic is testable without WoW globals.
function Scanner:ReadOpenProfession()
    local rows = {}
    if GetNumTradeSkills and GetTradeSkillInfo then
        -- Fix 1: Expand all collapsed category headers before reading the count,
        -- so recipes inside collapsed sections are not silently missed.
        if ExpandTradeSkillSubClass and GetTradeSkillInfo then
            local n = GetNumTradeSkills() or 0
            for i = n, 1, -1 do
                local _, recipeType, _, isExpanded = GetTradeSkillInfo(i)
                if recipeType == "header" and not isExpanded then pcall(ExpandTradeSkillSubClass, i) end
            end
        end
        local count = GetNumTradeSkills() or 0
        if count > 0 then
            for i = 1, count do
                local name, recipeType = GetTradeSkillInfo(i)
                rows[#rows + 1] = {
                    name = name, recipeType = recipeType,
                    recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i),
                    itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(i),
                }
            end
            -- Fix 2: Idiomatic multi-return for GetTradeSkillLine (avoids nil-guard on LHS of multi-assign).
            local professionName, rank, maxRank
            if GetTradeSkillLine then professionName, rank, maxRank = GetTradeSkillLine() end
            return rows, professionName, rank, maxRank
        end
    end
    if GetNumCrafts and GetCraftInfo then
        -- Fix 1 (Craft branch): Expand all collapsed craft category headers before reading count.
        if ExpandCraftSkillLine and GetCraftInfo then
            local n = GetNumCrafts() or 0
            for i = n, 1, -1 do
                local _, _, craftType, _, isExpanded = GetCraftInfo(i)
                if craftType == "header" and not isExpanded then pcall(ExpandCraftSkillLine, i) end
            end
        end
        local count = GetNumCrafts() or 0
        if count > 0 then
            for i = 1, count do
                local name, _, craftType = GetCraftInfo(i)
                rows[#rows + 1] = {
                    name = name, recipeType = craftType,
                    recipeLink = GetCraftSpellLink and GetCraftSpellLink(i),
                    itemLink = GetCraftItemLink and GetCraftItemLink(i),
                }
            end
            local professionName = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
            return rows, professionName, nil, nil
        end
    end
    return rows, nil
end

-- Reads the live Skills UI into rows (two-pass, expanding collapsed headers).
function Scanner:ReadSkillLines()
    if not GetNumSkillLines or not GetSkillLineInfo then return {} end
    if ExpandSkillHeader then
        local n = GetNumSkillLines() or 0
        for i = n, 1, -1 do
            local _, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded then pcall(ExpandSkillHeader, i) end
        end
    end
    local rows, count = {}, (GetNumSkillLines() or 0)
    for i = 1, count do
        local name, isHeader, isExpanded, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        rows[#rows + 1] = { name = name, isHeader = isHeader, isExpanded = isExpanded, rank = skillRank, maxRank = skillMaxRank }
    end
    return rows
end

-- Reads the Skills UI and commits Fishing rank. Returns true if it changed.
function Scanner:ScanFishingSkill()
    local store = Store()
    local profile = store and store:LocalProfile()
    local key = profile and profile.key
    if not key then return false end
    local rank, maxRank = self:ResolveFishingFromSkillLines(self:ReadSkillLines())
    if not rank then return false end
    local existing = profile.professions and profile.professions["Fishing"]
    local existingHash = existing and existing.hash
    store:SetProfession(key, "Fishing", { skillLineId = 356, rank = rank, maxRank = maxRank, spellIds = {} }, "owner")
    local newRecord = profile.professions["Fishing"]   -- set by SetProfession above
    local changed = (not existing) or (newRecord and newRecord.hash ~= existingHash) or false
    if changed then
        local sync = ns:GetModule("ProfessionsSync")
        if sync and sync.OnLocalChange then sync:OnLocalChange("Fishing") end
        local panel = ns:GetModule("ProfessionsPanel")
        if panel and panel.Refresh then panel:Refresh() end
    end
    return changed
end

function Scanner:ScheduleFishingScan()
    if not C_Timer then self:ScanFishingSkill(); return end
    self._fishToken = (self._fishToken or 0) + 1
    local token = self._fishToken
    C_Timer.After(1, function() if self._fishToken == token then self:ScanFishingSkill() end end)
end

local SCAN_DEBOUNCE = 0.85

function Scanner:ScheduleScanOpen()
    if not C_Timer then self:ScanOpen(); return end
    self._scanToken = (self._scanToken or 0) + 1
    local token = self._scanToken
    C_Timer.After(SCAN_DEBOUNCE, function() if self._scanToken == token then self:ScanOpen() end end)
end

function Scanner:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local events = ns:GetModule("Events")
    if events and events.On then
        events:On("SKILL_LINES_CHANGED", function() self:ScheduleFishingScan() end, self)
        events:On("PLAYER_ENTERING_WORLD", function() self:ScheduleFishingScan() end, self)
        events:On("TRADE_SKILL_SHOW",   function() self:ScheduleScanOpen() end, self)
        events:On("TRADE_SKILL_UPDATE", function() self:ScheduleScanOpen() end, self)
        events:On("CRAFT_SHOW",         function() self:ScheduleScanOpen() end, self)
        events:On("CRAFT_UPDATE",       function() self:ScheduleScanOpen() end, self)
    end
end
