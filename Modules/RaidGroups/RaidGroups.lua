local ADDON, ns = ...

local RaidGroups = ns:NewModule("RaidGroups")

local function settings()
    local d = ns:GetModule("DB").db
    d.settings.raidGroups = d.settings.raidGroups or { profiles = {}, keepPosInGroup = false }
    d.settings.raidGroups.profiles = d.settings.raidGroups.profiles or {}
    return d.settings.raidGroups
end

local function normalizeProfile(profile)
    if type(profile) ~= "table" then return nil end
    profile.name = profile.name or "Unnamed Raid"
    profile.slots = type(profile.slots) == "table" and profile.slots or {}
    profile.members = type(profile.members) == "table" and profile.members or {}
    for idx = 1, 40 do
        if profile.slots[idx] and type(profile.members[idx]) ~= "table" then
            profile.members[idx] = { name = profile.slots[idx] }
        elseif profile.members[idx] and not profile.slots[idx] then
            profile.slots[idx] = profile.members[idx].name
        end
    end
    return profile
end

function RaidGroups:GetProfiles()
    local profiles = settings().profiles
    for i = #profiles, 1, -1 do
        if not normalizeProfile(profiles[i]) then
            table.remove(profiles, i)
        end
    end
    return profiles
end

function RaidGroups:FindProfile(uuid)
    if not uuid then return nil end
    for i, p in ipairs(self:GetProfiles()) do
        if p.uuid == uuid then return p, i end
    end
end

function RaidGroups:SaveProfiles(decoded)
    local profiles = self:GetProfiles()
    local names = {}
    for _, np in ipairs(decoded) do
        normalizeProfile(np)
        local existing = np.uuid and self:FindProfile(np.uuid)
        if existing then
            existing.name = np.name; existing.time = np.time
            existing.slots = np.slots; existing.members = np.members
        else
            profiles[#profiles + 1] = np
        end
        names[#names + 1] = np.name
    end
    return names
end

function RaidGroups:DeleteProfile(index)
    table.remove(self:GetProfiles(), index)
end

-- Injectable seams (real WoW globals by default; fakes in tests).
RaidGroups._group = {
    SetRaidSubgroup  = function(i, g) SetRaidSubgroup(i, g) end,
    SwapRaidSubgroup = function(i, j) SwapRaidSubgroup(i, j) end,
}
RaidGroups._q = {
    isInRaid  = function() return IsInRaid() end,
    isLeader  = function() return UnitIsGroupLeader("player") end,
    isAssist  = function() return UnitIsGroupAssistant and UnitIsGroupAssistant("player") end,
    inCombat  = function() return InCombatLockdown() end,
    numRaid   = function() return GetNumGroupMembers() or 0 end,
    raidInfo  = function(i) local n, _, sg = GetRaidRosterInfo(i); return n, sg end,
    rosterFull = function(i) return GetRaidRosterInfo(i) end,
}

local function stripRealm(name)
    if not name then return nil end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(name) end
    return name:match("^([^%-]+)") or name
end

-- A locally-unique profile id (never collides with the website's real UUIDs).
local localCounter = 0
local function localId()
    localCounter = localCounter + 1
    local t = (ns and ns.now and ns.now()) or (time and time()) or 0
    return "local-" .. t .. "-" .. localCounter
end

-- Create a blank 8-group profile (filled by dragging guild members in). Returns it + index.
function RaidGroups:CreateProfile(name)
    local profiles = self:GetProfiles()
    local p = { uuid = localId(), name = (name and name ~= "" and name) or "New Raid",
                time = (ns and ns.now and ns.now()) or 0, slots = {}, members = {} }
    profiles[#profiles + 1] = p
    return p, #profiles
end

-- Snapshot the current in-game raid into a new profile (who is in which group right now).
-- Returns the profile + index, or nil if not in a raid.
function RaidGroups:SnapshotCurrentRaid(name)
    local q = self._q
    if not (q.isInRaid and q.isInRaid()) or q.numRaid() == 0 then return nil end
    local p = { uuid = localId(), name = (name and name ~= "" and name) or "Current Raid",
                time = (ns and ns.now and ns.now()) or 0, slots = {}, members = {} }
    local groupCount = {}  -- subgroup -> how many placed so far
    for i = 1, q.numRaid() do
        local nm, _, subgroup, _, _, classFile, _, _, _, _, _, combatRole = q.rosterFull(i)
        if nm and subgroup and subgroup >= 1 and subgroup <= 8 then
            local short = stripRealm(nm)
            local pos = (groupCount[subgroup] or 0) + 1
            if pos <= 5 then
                groupCount[subgroup] = pos
                local idx = (subgroup - 1) * 5 + pos
                p.slots[idx] = short
                p.members[idx] = { name = short, class = classFile, spec = nil, role = combatRole }
            end
        end
    end
    local profiles = self:GetProfiles()
    profiles[#profiles + 1] = p
    return p, #profiles
end

function RaidGroups:Apply(profile)
    profile = normalizeProfile(profile)
    if not profile then return end
    local q = self._q
    if not q.isInRaid() then
        ns:Print("You must be in a raid.", "warning"); return
    end
    if not (q.isLeader() or (q.isAssist and q.isAssist())) then
        ns:Print("Must be raid leader or have raid assist.", "warning"); return
    end
    if q.inCombat() then
        ns:Print("Can't rearrange groups in combat.", "warning"); return
    end

    local needGroup, needPos = {}, {}
    for idx = 1, 40 do
        local name = profile.slots[idx]
        if name then
            needGroup[name] = math.ceil(idx / 5)
            needPos[name] = ((idx - 1) % 5) + 1
        end
    end
    if not (ns:GetModule("DB").db.settings.raidGroups.keepPosInGroup) then
        needPos = {}
    end

    -- The raid leader is raid index 1; record which target group they belong to,
    -- so phase 2 can offset other members in that group (the RL holds slot 1).
    local rlName = select(1, self._q.raidInfo(1))
    if rlName and not needGroup[rlName] then
        local short = stripRealm(rlName)
        if needGroup[short] then rlName = short end
    end
    self.groupWithRL = (rlName and needGroup[rlName]) or 0

    self.needGroup = needGroup
    self.needPos = needPos
    self.locked = {}
    self.groupsReady = false
    self:ProcessRoster()
end

function RaidGroups:ProcessRoster()
    if not self.needGroup then return end
    local q, group = self._q, self._group

    if q.inCombat() then
        ns:Print("Combat started — aborting group changes.", "warning")
        self.needGroup = nil; self.needPos = {}; self.locked = {}; self.groupsReady = false
        return
    end

    local needGroup, needPos, locked = self.needGroup, self.needPos, self.locked

    local currentGroup, currentPos, nameToID, groupSize = {}, {}, {}, {}
    for i = 1, 8 do groupSize[i] = 0 end
    for i = 1, q.numRaid() do
        local name, sg = q.raidInfo(i)
        if name then
            if not needGroup[name] then
                local short = stripRealm(name)
                if needGroup[short] then name = short end
            end
            currentGroup[name] = sg
            nameToID[name] = i
            groupSize[sg] = (groupSize[sg] or 0) + 1
            currentPos[name] = groupSize[sg]
        end
    end

    if not self.groupsReady then
        local waited = false
        for unit, g in pairs(needGroup) do
            if currentGroup[unit] and currentGroup[unit] ~= g and groupSize[g] < 5 then
                group.SetRaidSubgroup(nameToID[unit], g)
                groupSize[currentGroup[unit]] = groupSize[currentGroup[unit]] - 1
                groupSize[g] = groupSize[g] + 1
                waited = true
            end
        end
        if waited then return end

        local setToSwap, swapped = {}, false
        for unit, g in pairs(needGroup) do
            if not setToSwap[unit] and currentGroup[unit] and currentGroup[unit] ~= g then
                local other
                for u2, g2 in pairs(currentGroup) do
                    if not setToSwap[u2] and g2 == g and needGroup[u2] ~= g2 then other = u2; break end
                end
                if other and nameToID[unit] and nameToID[other] then
                    group.SwapRaidSubgroup(nameToID[unit], nameToID[other])
                    setToSwap[unit] = true; setToSwap[other] = true; swapped = true
                end
            end
        end
        if swapped then return end
        self.groupsReady = true
    end

    if next(needPos) then
        local setToSwap, swapped = {}, false
        for unit, basePos in pairs(needPos) do
            local pos = basePos
            if currentGroup[unit] == self.groupWithRL then pos = pos + 1 end
            if not locked[unit] and currentPos[unit] and currentPos[unit] ~= pos
               and nameToID[unit] ~= 1 and not setToSwap[unit] then
                local bridge
                for u2, g2 in pairs(currentGroup) do
                    if g2 ~= currentGroup[unit] and nameToID[u2] ~= 1 and not setToSwap[u2] then bridge = u2; break end
                end
                local occupant
                for u2, p2 in pairs(currentPos) do
                    if currentGroup[u2] == currentGroup[unit] and p2 == pos and nameToID[u2] ~= 1 and not setToSwap[u2] then occupant = u2; break end
                end
                if bridge and occupant and nameToID[unit] and nameToID[bridge] and nameToID[occupant] then
                    locked[unit] = true
                    group.SwapRaidSubgroup(nameToID[unit], nameToID[bridge])
                    group.SwapRaidSubgroup(nameToID[bridge], nameToID[occupant])
                    group.SwapRaidSubgroup(nameToID[unit], nameToID[bridge])
                    setToSwap[unit] = true; setToSwap[occupant] = true; setToSwap[bridge] = true
                    swapped = true
                end
            end
        end
        if swapped then return end
    end

    self.needGroup = nil
    ns:Print("Raid groups applied.", "success")
    if self.onApplyComplete then self.onApplyComplete() end
end

function RaidGroups:OnInit()
    ns:GetModule("Nav"):RegisterPanel("raid_groups", function(parent)
        return ns:GetModule("RaidGroupsPanel"):Build(parent)
    end)
end

function RaidGroups:OnEnable()
    if self._enabled then return end
    self._enabled = true
    ns:GetModule("Events"):On("GROUP_ROSTER_UPDATE", function()
        if self.needGroup then
            if self._debounce then self._debounce:Cancel() end
            if C_Timer and C_Timer.NewTimer then
                self._debounce = C_Timer.NewTimer(0.3, function() self._debounce = nil; self:ProcessRoster() end)
            else
                self._debounce = nil
                self:ProcessRoster()
            end
        end
    end, "RaidGroups")
end

return RaidGroups
