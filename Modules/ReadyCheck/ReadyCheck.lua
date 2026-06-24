local ADDON, ns = ...

local ReadyCheck = ns:NewModule("ReadyCheck")

local READY_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING_ICON = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local COMM_PREFIX = "IDDQDRC1"
local ANNOUNCE_ELECTION_DELAY = 0.75

local FOOD_AURAS = {
    [18125] = true, [18141] = true, [18192] = true, [18194] = true, [18222] = true,
    [19705] = true, [19706] = true, [19708] = true, [19709] = true, [19710] = true,
    [19711] = true, [22730] = true, [22789] = true, [22790] = true, [24870] = true,
    [25661] = true, [25694] = true, [25804] = true, [25941] = true, [33254] = true,
    [33256] = true, [33257] = true, [33259] = true, [33261] = true, [33263] = true,
    [33265] = true, [33268] = true, [33272] = true, [35272] = true, [40323] = true,
    [42293] = true, [43722] = true, [43764] = true, [43771] = true, [44097] = true,
    [44098] = true, [44099] = true, [44100] = true, [44101] = true, [44102] = true,
    [44104] = true, [44105] = true, [44106] = true, [45245] = true, [45619] = true,
    [46682] = true, [46899] = true,
}

local FOOD_IN_PROGRESS_AURAS = {
    [104934] = true,
}

local FOOD_IN_PROGRESS_ICONS = {
    [134062] = true,
    [132805] = true,
    [133950] = true,
}

local BATTLE_ELIXIR_AURAS = {
    [3593] = true, [10667] = true, [10668] = true, [10669] = true, [10692] = true,
    [10693] = true, [11328] = true, [11334] = true, [11405] = true, [11406] = true,
    [11474] = true, [15233] = true, [16323] = true, [16329] = true, [17038] = true,
    [17535] = true, [17537] = true, [17538] = true, [17539] = true, [17543] = true,
    [17544] = true, [17545] = true, [17546] = true, [17548] = true, [17549] = true,
    [21920] = true, [24363] = true, [28490] = true, [28491] = true, [28493] = true,
    [28496] = true, [28497] = true, [28501] = true, [28503] = true, [28514] = true,
    [33720] = true, [33721] = true, [33726] = true, [38954] = true,
}

local GUARDIAN_ELIXIR_AURAS = {
    [11348] = true, [11349] = true, [11364] = true, [11371] = true, [15279] = true,
    [16325] = true, [16326] = true, [17624] = true, [24361] = true, [24382] = true,
    [24383] = true, [24417] = true, [28502] = true, [28509] = true, [28511] = true,
    [28512] = true, [28513] = true, [28515] = true, [39625] = true, [39626] = true,
    [39627] = true, [39628] = true,
}

local TRUE_FLASK_AURAS = {
    [17626] = true, [17627] = true, [17628] = true, [17629] = true,
    [28518] = true, [28519] = true, [28520] = true, [28521] = true,
    [28540] = true, [42735] = true,
    [40567] = true, [40568] = true, [40572] = true, [40573] = true,
    [40575] = true, [40576] = true, [41608] = true, [41609] = true,
    [41610] = true, [41611] = true, [46837] = true, [46839] = true,
}

local RAID_BUFF_GROUPS = {
    {
        key = "stamina",
        label = "Stamina",
        providerClasses = { PRIEST = true },
        spells = {
            1243, 1244, 1245, 2791, 10937, 10938, 25389,
            21562, 21564, 25392,
        },
    },
    {
        key = "spirit",
        label = "Spirit",
        providerClasses = { PRIEST = true },
        recipientClasses = {
            DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
            PRIEST = true, SHAMAN = true, WARLOCK = true,
        },
        spells = {
            14752, 14818, 14819, 27841, 25312,
            27681, 32999,
        },
    },
    {
        key = "shadow",
        label = "Shadow Protection",
        providerClasses = { PRIEST = true },
        spells = {
            976, 10957, 10958, 25433,
            27683, 39374,
        },
    },
    {
        key = "motw",
        label = "Mark of the Wild",
        providerClasses = { DRUID = true },
        spells = {
            1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990,
            21849, 21850, 26991,
        },
    },
    {
        key = "blessing",
        label = "Paladin Blessing",
        providerClasses = { PALADIN = true },
        spells = {
            19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140,
            25782, 25916, 27141,
            19742, 19850, 19852, 19853, 19854, 25290, 27142,
            25894, 25918, 27143,
            20217, 25898,
            1038, 25895,
            19977, 19978, 19979, 27144,
            25890, 27145,
            20911, 20912, 20913, 20914, 27168,
            25899, 27169,
        },
    },
    {
        key = "intellect",
        label = "Arcane Intellect",
        providerClasses = { MAGE = true },
        recipientClasses = {
            DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
            PRIEST = true, SHAMAN = true, WARLOCK = true,
        },
        spells = {
            1459, 1460, 1461, 10156, 10157, 27126,
            23028, 27127,
        },
    },
}

local RAID_BUFF_BY_SPELL = {}
local RAID_BUFF_BY_KEY = {}
for _, group in ipairs(RAID_BUFF_GROUPS) do
    RAID_BUFF_BY_KEY[group.key] = group
    for _, spellId in ipairs(group.spells or {}) do RAID_BUFF_BY_SPELL[spellId] = group end
end

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function now()
    return (GetTime and GetTime()) or (time and time()) or 0
end

local function trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function cleanCommField(value)
    return trim(value):gsub("[|\n\r]", " ")
end

local function shortName(value)
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(value) end
    value = trim(value)
    return (value:match("^([^-]+)") or value)
end

local function fullName(name)
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.FullName then return Players:FullName(name) end
    name = trim(name)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName()
    realm = trim(realm):gsub("%s+", "")
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function classColor(classFile)
    local token = classFile and tostring(classFile):upper():gsub("%s+", "")
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.86, 0.88, 0.92
end

local function unitClassFile(unit)
    if not UnitClass then return nil end
    local localizedClass, classFile = UnitClass(unit)
    return classFile or localizedClass
end

local function unitAura(unit, index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
        if not aura then return nil end
        return aura.name, aura.icon, aura.spellId, aura.expirationTime, aura.sourceUnit
    end
    if UnitAura then
        local name, icon, _, _, _, expirationTime, sourceUnit, _, _, spellId = UnitAura(unit, index, "HELPFUL")
        return name, icon, spellId, expirationTime, sourceUnit
    end
    return nil
end

local function unitDisplayName(unitOrName)
    if not unitOrName or unitOrName == "" then return nil end
    local name = UnitName and UnitName(unitOrName)
    return shortName(fullName(name or unitOrName) or name or unitOrName)
end

local function auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
    return {
        name = name,
        icon = icon,
        spellId = tonumber(spellId),
        expirationTime = expirationTime,
        remaining = remaining,
        sourceUnit = sourceUnit,
        casterName = unitDisplayName(sourceUnit),
    }
end

local function unitExists(unit)
    return not UnitExists or UnitExists(unit)
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function isFoodInProgress(name, icon, spellId)
    if spellId and FOOD_IN_PROGRESS_AURAS[spellId] then return true end
    if icon and FOOD_IN_PROGRESS_ICONS[icon] then return true end
    local n = lower(name)
    return n == "food" or n == "drink" or n == "food & drink" or n == "eating" or n == "drinking"
end

function ReadyCheck:Settings()
    local d = db()
    if not d then return {} end
    d.settings = d.settings or {}
    d.settings.readyCheck = d.settings.readyCheck or {}
    local s = d.settings.readyCheck
    if s.enabled == nil then s.enabled = true end
    if s.showOnlyLeader == nil then s.showOnlyLeader = false end
    if s.checkFood == nil then s.checkFood = true end
    if s.checkFlask == nil then s.checkFlask = true end
    if s.opacity == nil then s.opacity = 100 end
    if s.announceOnReadyCheck == nil then s.announceOnReadyCheck = false end
    if s.announceMissingFood == nil then s.announceMissingFood = false end
    if s.announceMissingFlask == nil then s.announceMissingFlask = false end
    if s.announceMissingRaidBuffs == nil then s.announceMissingRaidBuffs = false end
    if type(s.announceRaidBuffs) ~= "table" then s.announceRaidBuffs = {} end
    if s.announceEndStatus == nil then s.announceEndStatus = false end
    if s.announceEndAllReady == nil then s.announceEndAllReady = false end
    if s.lowBuffMinutes == nil then s.lowBuffMinutes = 10 end
    if s.autoHideSeconds == nil then s.autoHideSeconds = 8 end
    if s.sort == nil or s.sort == "status" then s.sort = "roster" end
    return s
end

function ReadyCheck:ShouldAnnounceRaidBuff(key)
    local s = self:Settings()
    if s.announceMissingRaidBuffs ~= true then return false end
    local selected = s.announceRaidBuffs
    if type(selected) ~= "table" then return true end
    return selected[key] ~= false
end

function ReadyCheck:IsLeaderOrAssist()
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    return false
end

function ReadyCheck:ShouldShow()
    local s = self:Settings()
    if s.enabled == false then return false end
    if s.showOnlyLeader and not self:IsLeaderOrAssist() then return false end
    return true
end

function ReadyCheck:CurrentRoster()
    local rows = {}
    if IsInRaid and IsInRaid() and GetRaidRosterInfo then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do
            local name, rank, subgroup, level, localizedClass, classFile, zone, online = GetRaidRosterInfo(i)
            if name and name ~= "" then
                local key = fullName(name) or name
                rows[#rows + 1] = {
                    key = key,
                    name = shortName(key),
                    unit = "raid" .. i,
                    group = tonumber(subgroup) or 1,
                    class = classFile or localizedClass,
                    online = online ~= false,
                    status = "waiting",
                }
            end
        end
    elseif IsInGroup and IsInGroup() then
        local function add(unit, group)
            if unitExists(unit) and UnitName then
                local name = UnitName(unit)
                if name and name ~= "" then
                    local classFile = unitClassFile(unit)
                    local key = fullName(name) or name
                    local connected = not UnitIsConnected or UnitIsConnected(unit) ~= false
                    rows[#rows + 1] = { key = key, name = shortName(key), unit = unit, group = group or 1, class = classFile, online = connected, status = "waiting" }
                end
            end
        end
        add("player", 1)
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, math.max(0, n - 1) do add("party" .. i, 1) end
    elseif UnitName then
        local name = UnitName("player")
        local classFile = unitClassFile("player")
        local key = fullName(name) or name or "Player"
        rows[#rows + 1] = { key = key, name = shortName(key), unit = "player", group = 1, class = classFile, online = true, status = "waiting" }
    end
    table.sort(rows, function(a, b)
        if (a.group or 1) ~= (b.group or 1) then return (a.group or 1) < (b.group or 1) end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    for i, row in ipairs(rows) do row.order = i end
    return rows
end

function ReadyCheck:ScanUnit(unit)
    local result = { food = false, flask = false, foodLow = false, flaskLow = false, flaskAuras = {}, blessingAuras = {} }
    for _, group in ipairs(RAID_BUFF_GROUPS) do result[group.key] = false end
    if not unit or not unitExists(unit) then return result end
    local lowSeconds = math.max(0, tonumber(self:Settings().lowBuffMinutes) or 10) * 60
    local t = now()
    for i = 1, 80 do
        local name, icon, spellId, expirationTime, sourceUnit = unitAura(unit, i)
        if not name then break end
        spellId = tonumber(spellId)
        local remaining = expirationTime and expirationTime > 0 and (expirationTime - t) or nil
        if spellId and FOOD_AURAS[spellId] then
            result.food = true
            result.foodLow = remaining and remaining <= lowSeconds or false
            result.foodAura = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
        elseif isFoodInProgress(name, icon, spellId) then
            result.food = true
            result.foodInProgress = true
            result.foodAura = auraRecord(name, icon or "Interface\\Icons\\INV_Misc_Fork&Knife", spellId, expirationTime, remaining, sourceUnit)
        end
        if spellId and TRUE_FLASK_AURAS[spellId] then
            result.flask = true
            result.flaskLow = remaining and remaining <= lowSeconds or false
            result.flaskAura = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
            result.flaskAuras = { result.flaskAura }
        elseif spellId and BATTLE_ELIXIR_AURAS[spellId] then
            result.battleElixir = true
            result.battleElixirAura = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
            result.battleElixirLow = remaining and remaining <= lowSeconds or false
            result.flaskLow = result.flaskLow or result.battleElixirLow
        elseif spellId and GUARDIAN_ELIXIR_AURAS[spellId] then
            result.guardianElixir = true
            result.guardianElixirAura = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
            result.guardianElixirLow = remaining and remaining <= lowSeconds or false
            result.flaskLow = result.flaskLow or result.guardianElixirLow
        elseif icon == 136000 then
            result.food = true
            result.foodAura = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
        end
        local buffGroup = spellId and RAID_BUFF_BY_SPELL[spellId]
        if buffGroup then
            local record = auraRecord(name, icon, spellId, expirationTime, remaining, sourceUnit)
            result[buffGroup.key] = true
            result[buffGroup.key .. "Aura"] = result[buffGroup.key .. "Aura"] or record
            if buffGroup.key == "blessing" then result.blessingAuras[#result.blessingAuras + 1] = record end
        end
    end
    if not result.flask and result.battleElixir and result.guardianElixir then
        result.flask = true
        result.flaskAura = result.battleElixirAura
        result.flaskAuras = { result.battleElixirAura, result.guardianElixirAura }
    elseif result.flask then
        result.flaskAuras = result.flaskAuras and #result.flaskAuras > 0 and result.flaskAuras or { result.flaskAura }
    else
        if result.battleElixirAura then result.flaskAuras[#result.flaskAuras + 1] = result.battleElixirAura end
        if result.guardianElixirAura then result.flaskAuras[#result.flaskAuras + 1] = result.guardianElixirAura end
    end
    return result
end

function ReadyCheck:AnalyzeConsumables(row)
    if not row then return nil end
    local c = self:ScanUnit(row.unit)
    row.food = c.food
    row.flask = c.flask
    row.foodLow = c.foodLow
    row.flaskLow = c.flaskLow
    row.foodAura = c.foodAura
    row.flaskAura = c.flaskAura
    row.foodInProgress = c.foodInProgress
    row.battleElixir = c.battleElixir
    row.guardianElixir = c.guardianElixir
    row.battleElixirAura = c.battleElixirAura
    row.guardianElixirAura = c.guardianElixirAura
    row.flaskAuras = c.flaskAuras
    row.blessingAuras = c.blessingAuras
    for _, group in ipairs(RAID_BUFF_GROUPS) do
        row[group.key] = c[group.key]
        row[group.key .. "Aura"] = c[group.key .. "Aura"]
    end
    return c
end

local function statusText(status)
    if status == "ready" then return "Ready" end
    if status == "notready" then return "Not ready" end
    return "Waiting"
end

function ReadyCheck:SortedRows()
    local session = self.session
    local rows = {}
    for _, row in pairs((session and session.rowsByKey) or {}) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        local ao, bo = tonumber(a.order), tonumber(b.order)
        if ao and bo and ao ~= bo then return ao < bo end
        if ao and not bo then return true end
        if bo and not ao then return false end
        if (a.group or 1) ~= (b.group or 1) then return (a.group or 1) < (b.group or 1) end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return rows
end

function ReadyCheck:Counts()
    local counts = { total = 0, ready = 0, waiting = 0, notready = 0, missingFood = 0, missingFlask = 0 }
    for _, row in ipairs(self:SortedRows()) do
        counts.total = counts.total + 1
        counts[row.status or "waiting"] = (counts[row.status or "waiting"] or 0) + 1
        if self:Settings().checkFood and row.food == false then counts.missingFood = counts.missingFood + 1 end
        if self:Settings().checkFlask and row.flask == false then counts.missingFlask = counts.missingFlask + 1 end
    end
    return counts
end

local function displayName(row)
    return row and (row.name or shortName(row.key) or row.key) or "?"
end

local function rowIsOnline(row)
    return not row or row.online ~= false
end

local function classToken(row)
    return row and row.class and tostring(row.class):upper():gsub("%s+", "") or nil
end

local function rowShouldHaveRaidBuff(row, group)
    if not rowIsOnline(row) then return false end
    local recipients = group and group.recipientClasses
    if type(recipients) ~= "table" then return true end
    local token = classToken(row)
    return token and recipients[token] == true
end

local function chatChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function schedule(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end

local function sendAddon(prefix, message, channel)
    if not (prefix and message and channel) then return false end
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(prefix, message, channel, nil, "NORMAL") end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then return pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel) end
    if SendAddonMessage then return pcall(SendAddonMessage, prefix, message, channel) end
    return false
end

local function registerPrefix(prefix)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then return Comm:RegisterPrefix(prefix) end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then return pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix) end
    if RegisterAddonMessagePrefix then return pcall(RegisterAddonMessagePrefix, prefix) end
    return false
end

local function localPlayerName()
    local name = UnitName and UnitName("player") or nil
    return shortName(fullName(name) or name or "player")
end

local function localAnnouncePriority()
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return 1 end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return 2 end
    return 3
end

local function addNameLines(lines, label, names)
    if #names == 0 then return end
    local prefix = label .. ": "
    local line = prefix
    for _, name in ipairs(names) do
        local addition = (line == prefix) and name or (", " .. name)
        if #line + #addition > 210 and line ~= prefix then
            lines[#lines + 1] = line
            line = prefix .. name
        else
            line = line .. addition
        end
    end
    if line ~= prefix then lines[#lines + 1] = line end
end

local function addMissingBlessingLines(lines, rows)
    local paladins = {}
    for _, row in ipairs(rows or {}) do
        if rowIsOnline(row) and classToken(row) == "PALADIN" then
            paladins[#paladins + 1] = {
                name = displayName(row),
                key = tostring(displayName(row) or ""):lower(),
            }
        end
    end
    if #paladins == 0 then return end

    local byPaladin = {}
    local generic = {}
    for _, paladin in ipairs(paladins) do byPaladin[paladin.key] = { label = paladin.name, names = {} } end

    for _, row in ipairs(rows or {}) do
        if rowIsOnline(row) then
            local auras = row.blessingAuras or {}
            if #auras < #paladins then
                local knownCasters, knownCount, allSourcesKnown = {}, 0, true
                for _, aura in ipairs(auras) do
                    local caster = aura and aura.casterName
                    if caster and caster ~= "" then
                        local key = tostring(caster):lower()
                        if not knownCasters[key] then
                            knownCasters[key] = true
                            knownCount = knownCount + 1
                        end
                    else
                        allSourcesKnown = false
                    end
                end

                if allSourcesKnown and knownCount == #auras then
                    for _, paladin in ipairs(paladins) do
                        if not knownCasters[paladin.key] then
                            local bucket = byPaladin[paladin.key]
                            bucket.names[#bucket.names + 1] = displayName(row)
                        end
                    end
                else
                    generic[#generic + 1] = displayName(row)
                end
            end
        end
    end

    for _, paladin in ipairs(paladins) do
        local bucket = byPaladin[paladin.key]
        addNameLines(lines, "Missing Paladin Blessing from " .. bucket.label, bucket.names)
    end
    addNameLines(lines, "Missing Paladin Blessing", generic)
end

function ReadyCheck:ReportRows()
    local rows = self:SortedRows()
    if #rows > 0 then
        for _, row in ipairs(rows) do self:AnalyzeConsumables(row) end
        return rows
    end
    rows = self:CurrentRoster()
    for _, row in ipairs(rows) do self:AnalyzeConsumables(row) end
    return rows
end

function ReadyCheck:BuildAnnouncementLines()
    local s = self:Settings()
    local rows = self:ReportRows()
    local lines = {}

    if s.announceMissingFood == true then
        local names = {}
        for _, row in ipairs(rows) do
            if rowIsOnline(row) and row.food == false then names[#names + 1] = displayName(row) end
        end
        addNameLines(lines, "Missing food", names)
    end

    if s.announceMissingFlask == true then
        local names = {}
        for _, row in ipairs(rows) do
            if rowIsOnline(row) and row.flask == false then names[#names + 1] = displayName(row) end
        end
        addNameLines(lines, "Missing flask/elixirs", names)
    end

    if s.announceMissingRaidBuffs == true then
        for _, group in ipairs(RAID_BUFF_GROUPS) do
            if self:ShouldAnnounceRaidBuff(group.key) and self:ShouldTrackBuffGroup(group.key) then
                if group.key == "blessing" then
                    addMissingBlessingLines(lines, rows)
                else
                    local names = {}
                    for _, row in ipairs(rows) do
                        if rowShouldHaveRaidBuff(row, group) and row[group.key] == false then names[#names + 1] = displayName(row) end
                    end
                    addNameLines(lines, "Missing " .. group.label, names)
                end
            end
        end
    end

    if #lines == 0 and (s.announceMissingFood or s.announceMissingFlask or s.announceMissingRaidBuffs) then
        lines[#lines + 1] = "Ready check: selected buff/consumable checks passed."
    end
    return lines
end

function ReadyCheck:BuildEndStatusLines()
    local s = self:Settings()
    local rows = self:SortedRows()
    local lines = {}
    local ready, notReady, waiting = 0, {}, {}

    for _, row in ipairs(rows) do
        if row.status == "ready" then
            ready = ready + 1
        elseif row.status == "notready" then
            notReady[#notReady + 1] = displayName(row)
        else
            waiting[#waiting + 1] = displayName(row)
        end
    end

    local total = ready + #notReady + #waiting
    if total == 0 then return lines end

    if #notReady == 0 and #waiting == 0 then
        if s.announceEndAllReady == true then
            lines[#lines + 1] = "Ready check ended: everyone is ready."
        end
        return lines
    end

    if s.announceEndStatus == true then
        lines[#lines + 1] = ("Ready check ended: Ready %d/%d, Not ready %d, AFK/no response %d."):format(
            ready, total, #notReady, #waiting)
        addNameLines(lines, "Not ready", notReady)
        addNameLines(lines, "AFK/no response", waiting)
    end

    return lines
end

local function sendAnnouncementLines(lines)
    if #lines == 0 then return false end
    local channel = chatChannel()
    for _, line in ipairs(lines) do
        if channel and SendChatMessage then
            pcall(SendChatMessage, "[iddqd] " .. line, channel)
        elseif ns.Print then
            ns:Print(line)
        end
    end
    return true
end

local function candidateWins(a, b)
    if not b then return true end
    local ap, bp = tonumber(a.priority) or 9, tonumber(b.priority) or 9
    if ap ~= bp then return ap < bp end
    return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
end

function ReadyCheck:BestAnnouncementCandidate(bucket)
    local best
    for _, candidate in pairs((bucket and bucket.candidates) or {}) do
        if candidateWins(candidate, best) then best = candidate end
    end
    return best
end

function ReadyCheck:AddAnnouncementCandidate(key, name, priority)
    if not key or key == "" then return nil end
    self.announceBuckets = self.announceBuckets or {}
    local bucket = self.announceBuckets[key]
    if not bucket then
        bucket = { candidates = {}, createdAt = now() }
        self.announceBuckets[key] = bucket
    end
    name = shortName(name or "?")
    local candidateKey = name:lower()
    bucket.candidates[candidateKey] = {
        name = name,
        priority = tonumber(priority) or 9,
        localPlayer = candidateKey == localPlayerName():lower(),
    }
    return bucket
end

function ReadyCheck:SendAnnouncementClaim(key, name)
    local channel = chatChannel()
    if channel then sendAddon(COMM_PREFIX, "S|" .. cleanCommField(key) .. "|" .. cleanCommField(name or localPlayerName()), channel) end
end

function ReadyCheck:CoordinatedAnnouncement(kind, key, lines)
    if #lines == 0 then return false end
    local channel = chatChannel()
    if not channel then return sendAnnouncementLines(lines) end

    key = cleanCommField(tostring(kind or "announce") .. ":" .. tostring(key or "default"))
    local localName = localPlayerName()
    local bucket = self:AddAnnouncementCandidate(key, localName, localAnnouncePriority())
    bucket.lines = lines

    sendAddon(COMM_PREFIX, ("C|%s|%d|%s"):format(key, localAnnouncePriority(), cleanCommField(localName)), channel)

    if bucket.scheduled then return true end
    bucket.scheduled = true
    schedule(ANNOUNCE_ELECTION_DELAY, function()
        if bucket.sent then return end
        local winner = self:BestAnnouncementCandidate(bucket)
        if winner and winner.localPlayer then
            bucket.sent = true
            self:SendAnnouncementClaim(key, localName)
            return sendAnnouncementLines(bucket.lines or lines)
        end
    end)
    return true
end

function ReadyCheck:AnnounceCheck(manual)
    local s = self:Settings()
    if not manual and s.announceOnReadyCheck ~= true then return false end
    local lines = self:BuildAnnouncementLines()
    if #lines == 0 then
        if manual and ns.Print then ns:Print("No ready-check announcement categories are enabled.", "warning") end
        return false
    end
    if manual then return sendAnnouncementLines(lines) end
    local session = self.session
    return self:CoordinatedAnnouncement("start", session and session.announceKey or "manual", lines)
end

function ReadyCheck:AnnounceEndStatus()
    local session = self.session
    if not session or session._endStatusAnnounced then return false end
    session._endStatusAnnounced = true
    return self:CoordinatedAnnouncement("end", session.announceKey or "manual", self:BuildEndStatusLines())
end

function ReadyCheck:Notify()
    if self.panel and self.panel.Refresh then self.panel:Refresh() end
    if self.overlay and self.overlay.Refresh then self.overlay:Refresh() end
end

function ReadyCheck:RegisterPanel(panel)
    self.panel = panel
end

function ReadyCheck:RegisterOverlay(overlay)
    self.overlay = overlay
end

function ReadyCheck:Start(starter, timer, opts)
    opts = opts or {}
    if not opts.force and not self:ShouldShow() then return nil end
    self.announceBuckets = {}
    local rows = self:CurrentRoster()
    local rowsByKey = {}
    local duration = tonumber(timer) or 35
    local announceKey = ("%s:%d"):format(cleanCommField(shortName(starter or "?")), math.floor(duration + 0.5))
    for i, row in ipairs(rows) do
        row.order = row.order or i
        self:AnalyzeConsumables(row)
        rowsByKey[row.key] = row
    end
    self.session = {
        active = true,
        test = opts.test and true or false,
        manual = opts.manual and true or false,
        starter = starter and shortName(starter) or nil,
        startedAt = now(),
        endsAt = now() + duration,
        announceKey = announceKey,
        rowsByKey = rowsByKey,
    }
    if starter then self:Confirm(starter, true, true) end
    if not opts.silent then self:AnnounceCheck(false) end
    self:Notify()
    return self.session
end

function ReadyCheck:Finish(opts)
    opts = type(opts) == "table" and opts or {}
    if self.session then
        if not opts.silent then self:AnnounceEndStatus() end
        self.session.active = false
        self.session.finishedAt = now()
    end
    self:Notify()
    local Timers = ns:GetModule("Timers")
    local delay = tonumber(self:Settings().autoHideSeconds) or 8
    if Timers then
        Timers:Debounce(self, "hide-overlay", delay, function()
            if self.overlay and self.overlay.HideIfFinished then self.overlay:HideIfFinished() end
        end)
    end
end

function ReadyCheck:ScheduleTestFinish(session)
    if not (session and session.test and session.endsAt) then return end
    if not (C_Timer and C_Timer.After) then return end
    local delay = math.max(0.1, (session.endsAt or now()) - now())
    C_Timer.After(delay, function()
        if self.session == session and session.active and session.test then
            self:Finish({ silent = true })
        end
    end)
end

function ReadyCheck:Confirm(unitOrName, response, alreadyName)
    local session = self.session
    if not session then return false end
    local name = alreadyName and unitOrName or (UnitName and UnitName(unitOrName)) or unitOrName
    local key = fullName(name)
    local short = shortName(name)
    local row = key and session.rowsByKey[key]
    if not row and short then
        for _, candidate in pairs(session.rowsByKey) do
            if candidate.name == short then row = candidate; break end
        end
    end
    if not row then return false end
    row.status = response == true and "ready" or "notready"
    row.respondedAt = now()
    self:AnalyzeConsumables(row)
    self:Notify()
    return true
end

function ReadyCheck:RefreshConsumables()
    if not self.session then return end
    for _, row in pairs(self.session.rowsByKey or {}) do self:AnalyzeConsumables(row) end
    self:Notify()
end

function ReadyCheck:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local op, key, a, b = tostring(message or ""):match("^([^|]*)|?([^|]*)|?([^|]*)|?(.*)$")
    if op == "C" then
        local bucket = self:AddAnnouncementCandidate(key, b ~= "" and b or sender, tonumber(a) or 9)
        if bucket and bucket.sentBy then bucket.sent = true end
    elseif op == "S" then
        self.announceBuckets = self.announceBuckets or {}
        local bucket = self.announceBuckets[key]
        if not bucket then
            bucket = { candidates = {}, createdAt = now() }
            self.announceBuckets[key] = bucket
        end
        bucket.sent = true
        bucket.sentBy = a ~= "" and a or sender
    end
end

function ReadyCheck:StartBlizzard()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("Ready check cannot be started in combat.", "warning")
        return false
    end
    if not self:IsLeaderOrAssist() then
        ns:Print("You need raid leader or assist to start a ready check.", "warning")
        return false
    end
    if DoReadyCheck then
        DoReadyCheck()
        return true
    end
    self:Start(UnitName and UnitName("player"), 35, { force = true, manual = true })
    return true
end

function ReadyCheck:Test()
    local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "WARLOCK", "SHAMAN" }
    local rowsByKey = {}
    for i = 1, 25 do
        local key = ("Tester%d-Realm"):format(i)
        rowsByKey[key] = {
            key = key,
            name = ("Tester%d"):format(i),
            unit = nil,
            group = math.floor((i - 1) / 5) + 1,
            class = classes[((i - 1) % #classes) + 1],
            status = i % 7 == 0 and "notready" or i % 3 == 0 and "ready" or "waiting",
            food = i % 4 ~= 0,
            flask = i % 5 ~= 0,
            order = i,
        }
    end
    self.session = { active = true, test = true, startedAt = now(), endsAt = now() + 35, rowsByKey = rowsByKey, starter = "Test" }
    self:ScheduleTestFinish(self.session)
    self:Notify()
    return self.session
end

function ReadyCheck:IconForStatus(status)
    if status == "ready" then return READY_ICON end
    if status == "notready" then return NOT_READY_ICON end
    return WAITING_ICON
end

function ReadyCheck:StatusText(status)
    return statusText(status)
end

function ReadyCheck:ClassColor(classFile)
    return classColor(classFile)
end

function ReadyCheck:BuffGroups()
    return RAID_BUFF_GROUPS
end

function ReadyCheck:ShouldTrackBuffGroup(key)
    local group = RAID_BUFF_BY_KEY[key]
    if not (group and group.providerClasses) then return true end
    local rows = self:SortedRows()
    if #rows == 0 then rows = self:CurrentRoster() end
    for _, row in ipairs(rows) do
        local classFile = row.class and tostring(row.class):upper():gsub("%s+", "")
        if rowIsOnline(row) and classFile and group.providerClasses[classFile] then return true end
    end
    return false
end

function ReadyCheck:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Events = ns:GetModule("Events")
    if Events then
        registerPrefix(COMM_PREFIX)
        Events:On("READY_CHECK", function(starter, timer) self:Start(starter, timer) end, "ReadyCheck")
        Events:On("READY_CHECK_CONFIRM", function(unit, response) self:Confirm(unit, response) end, "ReadyCheck")
        Events:On("READY_CHECK_FINISHED", function() self:Finish() end, "ReadyCheck")
        Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender) self:OnAddonMessage(prefix, message, channel, sender) end, "ReadyCheck")
        Events:On("GROUP_ROSTER_UPDATE", function()
            if self.session and self.session.active and not self.session.test then
                self:Start(self.session.starter, math.max(1, (self.session.endsAt or now()) - now()), { force = true, silent = true })
            end
        end, "ReadyCheck")
        Events:On("UNIT_AURA", function(unit)
            if not (self.session and self.session.active and unit) then return end
            for _, row in pairs(self.session.rowsByKey or {}) do
                if row.unit == unit then self:AnalyzeConsumables(row); self:Notify(); return end
            end
        end, "ReadyCheck")
    end
    local Slash = ns:GetModule("Slash")
    if Slash then
        Slash:Register("ready", function() self:StartBlizzard() end)
        Slash:Register("readytest", function() self:Test() end)
        Slash:Register("check", function() self:AnnounceCheck(true) end)
    end
end

return ReadyCheck
