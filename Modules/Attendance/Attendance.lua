local ADDON, ns = ...

-- Attendance: record point-in-time snapshots of the raid roster so officers can track who
-- showed up across raids. Data lives in db.settings.attendance.data (an array of snapshots).
-- A snapshot keeps the old flat members list and, for newer entries, raid-tab groups/classes:
-- { at = epoch, instance = "...", members = { "Name", ... }, groups = { [1] = {...}, ... },
--   classes = { Name = "MAGE", ... } }.

local Attendance = ns:NewModule("Attendance")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function now() return (time and time()) or 0 end

local function canon(name)
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(name) end
    name = tostring(name or "")
    name = (name:match("^%s*(.-)%s*$") or name)
    return (name:match("^([^-]+)") or name)
end

local VALID_MODES = {
    disabled = true,
    first_pull = true,
    first_kill = true,
    every_pull = true,
    every_kill = true,
}

local LEGACY_MODES = {
    [0] = "disabled",
    [1] = "first_pull",
    [2] = "first_kill",
    [3] = "every_pull",
    [4] = "every_kill",
}

local RAID_DIFFICULTIES = {
    [3] = true, [4] = true, [5] = true, [6] = true,       -- classic/TBC 10/25 normal/heroic
    [9] = true, [148] = true, [175] = true, [176] = true, -- classic 40/20/10/25 variants
    [185] = true, [193] = true, [194] = true,             -- classic 40/10hc/25hc variants
    [14] = true, [15] = true, [16] = true,                -- modern normal/heroic/mythic
}

local function normalizeMode(mode)
    if type(mode) == "number" then return LEGACY_MODES[mode] or "disabled" end
    if mode == true then return "first_pull" end
    if mode == false or mode == nil or mode == "" then return "disabled" end
    mode = tostring(mode)
    if VALID_MODES[mode] then return mode end
    return "disabled"
end

local function emptyGroups()
    local groups = {}
    for i = 1, 8 do groups[i] = {} end
    return groups
end

local function appendGroup(groups, groupIndex, name, classes, classFile)
    if not name or name == "" then return end
    local idx = tonumber(groupIndex) or 1
    if idx < 1 or idx > 8 then idx = 1 end
    groups[idx][#groups[idx] + 1] = name
    if classes and classFile and classFile ~= "" then classes[name] = tostring(classFile):upper() end
end

local function flattenGroups(groups)
    local members = {}
    for groupIndex = 1, 8 do
        local group = groups[groupIndex] or {}
        for slot = 1, #group do members[#members + 1] = group[slot] end
    end
    return members
end

local function groupsFromMembers(members)
    local groups = emptyGroups()
    for i, name in ipairs(members or {}) do
        appendGroup(groups, math.floor((i - 1) / 5) + 1, name)
    end
    return groups
end

local function groupsFromSnapshot(snap)
    if snap and snap.groups then
        local groups = emptyGroups()
        for groupIndex = 1, 8 do
            local src = snap.groups[groupIndex] or snap.groups[tostring(groupIndex)] or {}
            for slot = 1, #src do groups[groupIndex][slot] = src[slot] end
        end
        return groups
    end
    return groupsFromMembers((snap and snap.members) or {})
end

local function sortedCopy(list)
    local copy = {}
    for i, v in ipairs(list or {}) do copy[i] = v end
    table.sort(copy)
    return copy
end

function Attendance:Store()
    local d = db()
    if not d then return nil end
    d.settings = d.settings or {}
    d.settings.attendance = d.settings.attendance or {}
    local a = d.settings.attendance
    a.data = a.data or {}
    a.alts = a.alts or {}
    if a.autoMode == nil then a.autoMode = normalizeMode(a.mode or a.enabled) end
    return a
end

function Attendance:SnapshotMode()
    local a = self:Store()
    return normalizeMode(a and a.autoMode)
end

function Attendance:SetSnapshotMode(mode)
    local a = self:Store()
    if not a then return nil end
    a.autoMode = normalizeMode(mode)
    a.enabled = nil
    return a.autoMode
end

-- Current group/raid roster as raid-tab groups plus a flat list in group order.
function Attendance:CurrentRaidGroups()
    local groups = emptyGroups()
    local classes = {}
    if IsInRaid and IsInRaid() and GetRaidRosterInfo then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do
            local ok, name, rank, subgroup, level, localizedClass, classFile = pcall(GetRaidRosterInfo, i)
            if ok and name and name ~= "" then appendGroup(groups, subgroup, canon(name), classes, classFile or localizedClass) end
        end
    elseif IsInGroup and IsInGroup() then
        if UnitName then
            local classFile
            if UnitClass then local _, cf = UnitClass("player"); classFile = cf end
            appendGroup(groups, 1, canon(UnitName("player")), classes, classFile)
        end
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n - 1 do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) and UnitName then
                local classFile
                if UnitClass then local _, cf = UnitClass(unit); classFile = cf end
                appendGroup(groups, 1, canon(UnitName(unit)), classes, classFile)
            end
        end
    elseif UnitName then
        local classFile
        if UnitClass then local _, cf = UnitClass("player"); classFile = cf end
        appendGroup(groups, 1, canon(UnitName("player")), classes, classFile)
    end
    return groups, flattenGroups(groups), classes
end

-- Current group/raid roster as a sorted list of short names (includes the player).
function Attendance:CurrentRoster()
    local _, names = self:CurrentRaidGroups()
    table.sort(names)
    return names
end

function Attendance:CurrentInstance()
    if GetInstanceInfo then
        local name = GetInstanceInfo()
        if name and name ~= "" then return name end
    end
    if GetRealZoneText then
        local z = GetRealZoneText()
        if z and z ~= "" then return z end
    end
    return "Unknown"
end

function Attendance:RaidSessionKey()
    if GetInstanceInfo then
        local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID = pcall(GetInstanceInfo)
        if ok and name and name ~= "" then
            return table.concat({
                tostring(instanceID or name),
                tostring(instanceType or ""),
                tostring(difficultyID or ""),
                tostring(maxPlayers or ""),
                tostring(difficultyName or ""),
                tostring(dynamicDifficulty or ""),
                tostring(isDynamic or ""),
            }, ":")
        end
    end
    return self:CurrentInstance()
end

function Attendance:_autoSeen(trigger)
    local seen = self._autoSeenBySession
    local key = self:RaidSessionKey()
    return seen and seen[trigger] and seen[trigger][key]
end

function Attendance:_markAutoSeen(trigger)
    local key = self:RaidSessionKey()
    self._autoSeenBySession = self._autoSeenBySession or {}
    self._autoSeenBySession[trigger] = self._autoSeenBySession[trigger] or {}
    self._autoSeenBySession[trigger][key] = true
end

function Attendance:IsRaidEncounterDifficulty(difficultyID)
    return RAID_DIFFICULTIES[tonumber(difficultyID)] == true
end

function Attendance:AutoSnapshotAllowed(difficultyID)
    if IsInRaid and not IsInRaid() then return false end
    return self:IsRaidEncounterDifficulty(difficultyID)
end

function Attendance:ShouldAutoSnapshot(trigger, difficultyID)
    if not self:AutoSnapshotAllowed(difficultyID) then return false end
    local mode = self:SnapshotMode()
    if trigger == "pull" then
        if mode == "every_pull" then return true end
        if mode == "first_pull" then return not self:_autoSeen("pull") end
    elseif trigger == "kill" then
        if mode == "every_kill" then return true end
        if mode == "first_kill" then return not self:_autoSeen("kill") end
    end
    return false
end

-- Take a snapshot of the current roster. Returns the snapshot table or nil.
function Attendance:TakeSnapshot(reason, encounterName)
    local a = self:Store()
    if not a then return nil end

    local groups, members, classes = self:CurrentRaidGroups()
    if #members == 0 then
        members = self:CurrentRoster()
        groups = groupsFromMembers(members)
        classes = {}
    end
    if #members == 0 then return nil end

    local snap = {
        at = now(),
        instance = self:CurrentInstance(),
        members = sortedCopy(members),
        groups = groups,
        classes = classes,
        reason = reason or "manual",
        encounter = encounterName,
    }
    table.insert(a.data, 1, snap)   -- newest first
    -- Keep the history bounded.
    while #a.data > 200 do table.remove(a.data) end
    return snap
end

function Attendance:TryAutoSnapshot(trigger, encounterName, difficultyID)
    if not self:ShouldAutoSnapshot(trigger, difficultyID) then return nil end
    local snap = self:TakeSnapshot(trigger, encounterName)
    if snap then self:_markAutoSeen(trigger) end
    return snap
end

function Attendance:OnPull(encounterName, difficultyID)
    local t = now()
    if self._lastPullAt and t > 0 and (t - self._lastPullAt) < 8 then return nil end
    local snap = self:TryAutoSnapshot("pull", encounterName, difficultyID)
    if snap then self._lastPullAt = t end
    return snap
end

function Attendance:OnKill(encounterName, difficultyID)
    local t = now()
    if self._lastKillAt and t > 0 and (t - self._lastKillAt) < 8 then return nil end
    local snap = self:TryAutoSnapshot("kill", encounterName, difficultyID)
    if snap then self._lastKillAt = t end
    return snap
end

function Attendance:OnEnable()
    if self._eventsRegistered then return end
    local Events = ns.GetModule and ns:GetModule("Events") or nil
    if not (Events and Events.On) then return end
    self._eventsRegistered = true
    local owner = "Attendance"
    Events:On("ENCOUNTER_START", function(_, name, difficultyID) self:OnPull(name, difficultyID) end, owner)
    Events:On("ENCOUNTER_END", function(_, name, difficultyID, _, success)
        if success == 1 or success == true then self:OnKill(name, difficultyID) end
    end, owner)
end

function Attendance:Snapshots()
    local a = self:Store()
    return (a and a.data) or {}
end

function Attendance:ExportSnapshot(indexOrSnapshot)
    local snap = type(indexOrSnapshot) == "number" and self:Snapshots()[indexOrSnapshot] or indexOrSnapshot
    if not snap then return nil end

    local lines = {}
    lines[#lines + 1] = "iddqd Attendance Snapshot"
    lines[#lines + 1] = "Time: " .. ((date and snap.at and date("%Y-%m-%d %H:%M", snap.at)) or tostring(snap.at or ""))
    lines[#lines + 1] = "Instance: " .. tostring(snap.instance or "")
    if snap.encounter and snap.encounter ~= "" then lines[#lines + 1] = "Encounter: " .. tostring(snap.encounter) end
    lines[#lines + 1] = "Reason: " .. tostring(snap.reason or "manual")
    lines[#lines + 1] = "Members: " .. tostring(snap.members and #snap.members or 0)
    lines[#lines + 1] = ""

    local groups = groupsFromSnapshot(snap)
    for groupIndex = 1, 8 do
        lines[#lines + 1] = ("Group %d"):format(groupIndex)
        local group = groups[groupIndex] or {}
        for slot = 1, 5 do
            local name = group[slot] or ""
            local classFile = name ~= "" and snap.classes and snap.classes[name] or ""
            lines[#lines + 1] = ("%d\t%s\t%s"):format(slot, name, classFile or "")
        end
        if groupIndex < 8 then lines[#lines + 1] = "" end
    end

    return table.concat(lines, "\n")
end

function Attendance:DeleteSnapshot(index)
    local a = self:Store()
    if a and a.data and a.data[index] then table.remove(a.data, index) end
end

function Attendance:Clear()
    local a = self:Store()
    if a then a.data = {} end
end

return Attendance
