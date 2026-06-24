local ADDON, ns = ...

local AutoMarking = ns:NewModule("AutoMarking")
local Engine = ns.autoMarkEngine
local localProfileCounter = 0

-- File-local runtime state (not on the module surface).
local THROTTLE = 0.25
local lastMarkTime = 0
local activeMarks = {}  -- activeMarks[markerIndex] = guid that owns it (per pull)
local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function resetActiveMarks() for i = 1, 8 do activeMarks[i] = nil end end
local function clearActiveMarkForGuid(guid)
    if not guid then return end
    for i = 1, 8 do
        if activeMarks[i] == guid then activeMarks[i] = nil end
    end
end
local function markerName(marker) return MARKER_NAMES[marker] or tostring(marker) end

local function markerListText(markers)
    local out = {}
    for i = 1, #markers do out[#out + 1] = markerName(markers[i]) end
    return table.concat(out, ", ")
end

local function npcName(raidKey, npcID)
    local data = ns.autoMarkingNPCs and ns.autoMarkingNPCs[raidKey]
    for _, npc in ipairs((data and data.npcs) or {}) do
        if npc.id == npcID then return npc.name end
    end
    return tostring(npcID)
end

-- Injected seam (real WoW globals by default; fakes in tests).
AutoMarking._q = {
    mouseoverExists = function() return UnitExists("mouseover") end,
    mouseoverDead   = function() return UnitIsDead("mouseover") end,
    mouseoverGuid   = function() return UnitGUID("mouseover") end,
    raidTargetIndex = function() return GetRaidTargetIndex("mouseover") end,
    setRaidTarget   = function(m) SetRaidTarget("mouseover", m) end,
    unitExists      = function(unit) return UnitExists(unit) end,
    unitGuid        = function(unit) return UnitGUID(unit) end,
    unitRaidTarget  = function(unit) return GetRaidTargetIndex(unit) end,
    instanceId      = function() local _,_,_,_,_,_,_, id = GetInstanceInfo(); return id end,
    inGroup  = function() return IsInGroup() end,
    inRaid   = function() return IsInRaid() end,
    isLeader = function() return UnitIsGroupLeader("player") end,
    isAssist = function() return UnitIsGroupAssistant and UnitIsGroupAssistant("player") end,
    altDown   = function() return IsAltKeyDown() end,
    shiftDown = function() return IsShiftKeyDown() end,
    ctrlDown  = function() return IsControlKeyDown() end,
    now = function() return GetTime() end,
    after = function(delay, fn) if C_Timer and C_Timer.After then C_Timer.After(delay, fn) end end,
}

AutoMarking.currentRaidKey = nil
AutoMarking.instanceIdToRaidKey = nil

-- ---- Settings (UI is the only writer; runtime read-only; thin wrappers over the engine)
function AutoMarking:GetSettings()
    local db = ns:GetModule("DB").db
    return db and db.settings and db.settings.autoMarking
end
function AutoMarking:IsEnabled() local s = self:GetSettings(); return s and s.enabled or false end
function AutoMarking:NewProfileId()
    localProfileCounter = localProfileCounter + 1
    local t = (time and time()) or 0
    return ("am-%d-%d"):format(t, localProfileCounter)
end

function AutoMarking:EnsureProfiles()
    local s = self:GetSettings()
    if not s then return end
    Engine.migrate(s)
    if type(s.profiles) ~= "table" or #s.profiles == 0 then
        s.profiles = { Engine.normalizeProfile({ id = "default", name = "Default", raids = Engine.emptyRaids() }) }
        s.activeProfileId = "default"
    end
    local activeExists = false
    for _, profile in ipairs(s.profiles) do
        Engine.normalizeProfile(profile)
        if profile.id == s.activeProfileId then activeExists = true end
    end
    if not activeExists then s.activeProfileId = s.profiles[1].id end
end

function AutoMarking:GetProfiles()
    self:EnsureProfiles()
    local s = self:GetSettings()
    return (s and s.profiles) or {}
end

function AutoMarking:GetActiveProfile()
    self:EnsureProfiles()
    local s = self:GetSettings()
    if not s then return nil end
    for _, profile in ipairs(s.profiles or {}) do
        if profile.id == s.activeProfileId then return profile end
    end
    return s.profiles and s.profiles[1] or nil
end

function AutoMarking:SetActiveProfile(id)
    local s = self:GetSettings()
    if not (s and id) then return false end
    for _, profile in ipairs(self:GetProfiles()) do
        if profile.id == id then
            s.activeProfileId = id
            return true
        end
    end
    return false
end

function AutoMarking:ProfileItems()
    local out = {}
    for _, profile in ipairs(self:GetProfiles()) do out[#out + 1] = { value = profile.id, label = profile.name } end
    return out
end

function AutoMarking:CreateProfile(name, source)
    self:EnsureProfiles()
    local s = self:GetSettings()
    if not s then return nil end
    local profile = Engine.normalizeProfile({
        id = self:NewProfileId(),
        name = (name and name ~= "" and name) or "New Profile",
        createdAt = time and time() or 0,
        updatedAt = time and time() or 0,
        modifierEnabled = source and source.modifierEnabled or false,
        modifierKey = source and source.modifierKey or "ALT",
        lockAfterUse = source and source.lockAfterUse or false,
        raids = source and Engine.cloneRaids(source.raids) or Engine.emptyRaids(),
    })
    s.profiles[#s.profiles + 1] = profile
    s.activeProfileId = profile.id
    return profile
end

function AutoMarking:DuplicateActiveProfile()
    local active = self:GetActiveProfile()
    if not active then return nil end
    return self:CreateProfile((active.name or "Profile") .. " Copy", active)
end

function AutoMarking:RenameActiveProfile(name)
    local active = self:GetActiveProfile()
    if not active or not name or name == "" then return false end
    active.name = name:sub(1, 48)
    active.updatedAt = time and time() or active.updatedAt
    return true
end

function AutoMarking:DeleteActiveProfile()
    local s = self:GetSettings()
    if not (s and s.profiles and #s.profiles > 1) then return false end
    for i, profile in ipairs(s.profiles) do
        if profile.id == s.activeProfileId then
            table.remove(s.profiles, i)
            s.activeProfileId = s.profiles[math.min(i, #s.profiles)].id
            return true
        end
    end
    return false
end

function AutoMarking:ExportActiveProfileString()
    local Codec = ns:GetModule("AutoMarkingProfileCodec")
    if not Codec then return nil, "Profile codec is not loaded." end
    return Codec:EncodeProfile(self:GetActiveProfile(), UnitName and UnitName("player") or nil)
end

function AutoMarking:ImportProfileString(importString)
    local Codec = ns:GetModule("AutoMarkingProfileCodec")
    if not Codec then return nil, "Profile codec is not loaded." end
    local profile, err = Codec:DecodeString(importString)
    if not profile then return nil, err end
    local s = self:GetSettings()
    if not s then return nil, "Auto Marking settings are not loaded." end
    self:EnsureProfiles()
    profile.id = self:NewProfileId()
    s.profiles[#s.profiles + 1] = Engine.normalizeProfile(profile)
    s.activeProfileId = profile.id
    return profile
end

function AutoMarking:GetMarkerList(raidKey, npcID)
    return Engine.getMarkerList(self:GetActiveProfile(), raidKey, npcID)
end
function AutoMarking:GetMarker(raidKey, npcID, slot) return self:GetMarkerList(raidKey, npcID)[slot or 1] end
function AutoMarking:SetMarker(raidKey, npcID, slot, marker)
    local profile = self:GetActiveProfile()
    Engine.setMarker(profile, raidKey, npcID, slot, marker)
    if profile then profile.updatedAt = time and time() or profile.updatedAt end
end
function AutoMarking:ClearRaid(raidKey)
    local profile = self:GetActiveProfile()
    Engine.clearRaid(profile, raidKey)
    if profile then profile.updatedAt = time and time() or profile.updatedAt end
end

local function canMark(q)
    if not q.inGroup() then return true end
    if q.inRaid() then return q.isLeader() or (q.isAssist and q.isAssist()) end
    return q.isLeader()
end

local function scanVisibleMarkedUnits(q)
    local visible = {}
    local function scan(unit)
        if q.unitExists and q.unitExists(unit) then
            local guid = q.unitGuid and q.unitGuid(unit)
            local marker = q.unitRaidTarget and q.unitRaidTarget(unit)
            if guid and marker and marker >= 1 and marker <= 8 then
                visible[marker] = guid
            end
        end
    end

    scan("target")
    scan("focus")
    scan("mouseover")
    for i = 1, 5 do scan("boss" .. i) end
    for i = 1, 40 do scan("nameplate" .. i) end
    return visible
end

local function syncVisibleActiveMarks(q, markers)
    local visible = scanVisibleMarkedUnits(q)
    for i = 1, #markers do
        local marker = markers[i]
        if marker and visible[marker] then
            activeMarks[marker] = visible[marker]
        end
    end
end

function AutoMarking:DebugMark(npcID, markers, picked)
    local db = ns:GetModule("DB").db
    if not (db and db.debug) then return end
    ns:Print(("%s (%d): %s -> %s"):format(
        npcName(self.currentRaidKey, npcID),
        npcID,
        markerListText(markers),
        markerName(picked)
    ), "info")
end

function AutoMarking:ScheduleMouseoverRetry(guid, delay)
    if not (guid and self._q.after) then return end
    if self.pendingRetryGuid == guid then return end
    self.pendingRetryGuid = guid
    self._q.after(math.max(0.02, delay or THROTTLE), function()
        if self.pendingRetryGuid ~= guid then return end
        self.pendingRetryGuid = nil
        if self._q.mouseoverGuid and self._q.mouseoverGuid() == guid then
            self:OnMouseoverChanged()
        end
    end)
end

function AutoMarking:RefreshCurrentRaid()
    local id = self._q.instanceId()
    self.currentRaidKey = self.instanceIdToRaidKey and self.instanceIdToRaidKey[id] or nil
end

function AutoMarking:OnCombatLogEvent(...)
    local _, subevent, _, _, _, _, _, destGUID
    if CombatLogGetCurrentEventInfo then
        _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    else
        _, subevent, _, _, _, _, _, destGUID = ...
    end
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" or subevent == "UNIT_DISSIPATES" then
        clearActiveMarkForGuid(destGUID)
    end
end

-- The mark gate. Canonical order (cheapest exits first; throttle LAST so only real mark
-- attempts consume the window). See the spec — order is load-bearing.
function AutoMarking:OnMouseoverChanged()
    local q = self._q
    local s = self:GetSettings()
    if not s or not s.enabled then return end

    local profile = self:GetActiveProfile()
    if not profile then return end

    if profile.modifierEnabled then
        local k = profile.modifierKey
        local held = (k == "ALT" and q.altDown()) or (k == "SHIFT" and q.shiftDown()) or (k == "CTRL" and q.ctrlDown())
        if not held then return end
    end

    if not q.mouseoverExists() then return end
    if q.mouseoverDead() then return end
    if not self.currentRaidKey then return end
    if not canMark(q) then return end

    local guid = q.mouseoverGuid()
    if not guid then return end
    local npcID = Engine.npcIdFromGuid(guid)
    if not npcID then return end

    local raid = profile.raids[self.currentRaidKey]
    if not raid then return end
    local markers = raid[npcID]
    if type(markers) ~= "table" or #markers == 0 then return end

    syncVisibleActiveMarks(q, markers)
    local picked = Engine.pickMarker(markers, activeMarks, guid, profile.lockAfterUse)
    if not picked then return end

    if q.raidTargetIndex() == picked then
        activeMarks[picked] = guid  -- record ownership even on dedupe
        return
    end

    local now = q.now()
    local remaining = THROTTLE - (now - lastMarkTime)
    if remaining > 0 then
        self:ScheduleMouseoverRetry(guid, remaining + 0.02)
        return
    end
    lastMarkTime = now

    q.setRaidTarget(picked)
    activeMarks[picked] = guid
    self:DebugMark(npcID, markers, picked)
end

function AutoMarking:OnInit()
    local s = self:GetSettings()
    if not s then error("AutoMarking: settings not initialized") end
    Engine.migrate(s)
    self:EnsureProfiles()

    self.instanceIdToRaidKey = {
        [532]="kara", [565]="gruul", [544]="mag", [548]="ssc",
        [550]="tk", [534]="hyjal", [564]="bt", [568]="za", [580]="swp",
    }

    ns:GetModule("Nav"):RegisterPanel("auto_marking", function(parent)
        local P = ns:GetModule("AutoMarkingPanel")
        if P then return P:Build(parent) end
    end)
end

function AutoMarking:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Events = ns:GetModule("Events")
    Events:On("UPDATE_MOUSEOVER_UNIT", function() self:OnMouseoverChanged() end, "AutoMarking")
    Events:On("ZONE_CHANGED_NEW_AREA", function() self:RefreshCurrentRaid(); resetActiveMarks() end, "AutoMarking")
    Events:On("PLAYER_ENTERING_WORLD", function() self:RefreshCurrentRaid(); resetActiveMarks() end, "AutoMarking")
    Events:On("GROUP_ROSTER_UPDATE",   function() self:RefreshCurrentRaid() end, "AutoMarking")
    Events:On("PLAYER_REGEN_ENABLED",  function() resetActiveMarks() end, "AutoMarking")
    Events:On("COMBAT_LOG_EVENT_UNFILTERED", function(...) self:OnCombatLogEvent(...) end, "AutoMarking")
    self:RefreshCurrentRaid()
    resetActiveMarks()
end

return AutoMarking
