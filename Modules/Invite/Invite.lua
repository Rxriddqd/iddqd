local ADDON, ns = ...

local Invite = ns:NewModule("Invite")

-- Group APIs, resolved once. Classic/TBC keep the bare globals; Retail moves
-- some under C_PartyInfo. Local to this module (its only consumer) for now.
local Group = {
    InviteUnit      = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit,
    ConvertToRaid   = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid,
    UninviteUnit    = UninviteUnit,
    DemoteAssistant = DemoteAssistant,
}
Invite._group = Group

-- State-query seam: real WoW globals by default, swappable in tests.
Invite._q = {
    isInRaid    = function() return IsInRaid() end,
    numGroup    = function() return GetNumGroupMembers() or 0 end,
    numGuild    = function() return GetNumGuildMembers() or 0 end,
    guildInfo   = function(i) return GetGuildRosterInfo(i) end,
    raidInfo    = function(i) return GetRaidRosterInfo(i) end,
    isInGuild   = function() return IsInGuild and IsInGuild() end,
    requestGuildRoster = function()
        local req = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
        if req then req() end
    end,
    now         = function() return type(time) == "function" and time() or 0 end,
    inUnitGroup = function(name)
        if UnitName(name) ~= nil then return true end
        local Players = ns.GetModule and ns:GetModule("Players") or nil
        local short = Players and Players.ShortName and Players:ShortName(name) or (name and name:match("^([^%-]+)"))
        return short and short ~= name and (UnitName(short) ~= nil) or false
    end,
    playerName  = function() return ns.playerName or UnitName("player") end,
    minLevel    = function() return 60 end,
    isLeader    = function() return UnitIsGroupLeader("player") end,
    after       = function(delay, fn) C_Timer.After(delay, fn) end,
}

-- Per-session state (never persisted).
Invite.pending = {}
Invite.mode = nil
Invite.convertToRaid = false
Invite.reinviteList = {}
Invite.invWords = {}
Invite.pendingKeywordGuild = {}

local function stripRealm(name)
    if not name then return nil end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(name) end
    return name:match("^([^%-]+)") or name
end
Invite._stripRealm = stripRealm

local function trimLower(text)
    text = tostring(text or ""):lower()
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end
Invite._trimLower = trimLower

local function settings()
    local DB = ns:GetModule("DB")
    return DB and DB.db and DB.db.settings and DB.db.settings.invite
end

local function ensureSettings()
    local s = settings()
    if not s then return nil end
    if s.words == nil then s.words = "inv 123" end
    if s.invByChat == nil then s.invByChat = false end
    if s.invByChatSay == nil then s.invByChatSay = false end
    if s.onlyGuild == nil then s.onlyGuild = true end
    return s
end

-- WoW chokes on very long cross-realm names; strip realm past 44 chars.
local function safeInvite(group, name)
    if not name then return end
    if #name >= 45 then group.InviteUnit(stripRealm(name)) else group.InviteUnit(name) end
end

function Invite:RebuildInvWords()
    local out = {}
    local words = (ensureSettings() and settings().words) or "inv 123"
    for word in tostring(words):gmatch("%S+") do
        out[trimLower(word)] = true
    end
    self.invWords = out
    return out
end

function Invite:GetOpt(key)
    local s = ensureSettings()
    return s and s[key]
end

function Invite:SetOpt(key, value)
    local s = ensureSettings()
    if not s then return end
    s[key] = value
    if key == "words" then self:RebuildInvWords() end
end

function Invite:IsGuildMember(name)
    if not name or not self._q.isInGuild() then return false end
    local short = stripRealm(name)
    if not short then return false end
    short = short:lower()
    for i = 1, self._q.numGuild() do
        local guildName = self._q.guildInfo(i)
        if guildName and (stripRealm(guildName) or ""):lower() == short then return true end
    end
    return false
end

function Invite:RequestGuildRoster()
    if self._q.isInGuild() then self._q.requestGuildRoster() end
end

local function keywordPendingKey(sender)
    local short = stripRealm(sender)
    return short and short:lower() or nil
end

function Invite:_inviteKeywordSender(sender)
    if not sender or self._q.inUnitGroup(sender) then return false end
    if not self._q.isInRaid() and self._q.numGroup() >= 5 then
        self._group.ConvertToRaid()
    end
    safeInvite(self._group, sender)
    return true
end

function Invite:QueueGuildKeywordInvite(sender, source)
    local key = keywordPendingKey(sender)
    if not key then return end
    self.pendingKeywordGuild[key] = {
        sender = sender,
        source = source or "WHISPER",
        expiresAt = self._q.now() + 10,
    }
    self:RequestGuildRoster()
    self._q.after(2, function() self:ProcessPendingKeywordInvites() end)
end

function Invite:ProcessPendingKeywordInvites()
    local now = self._q.now()
    for key, pending in pairs(self.pendingKeywordGuild) do
        local s = ensureSettings()
        local sourceEnabled = false
        if s and pending then
            sourceEnabled = pending.source == "WHISPER" and s.invByChat or pending.source ~= "WHISPER" and s.invByChatSay
        end
        if not pending or not pending.sender or not sourceEnabled or now > (pending.expiresAt or 0) then
            self.pendingKeywordGuild[key] = nil
        elseif not self:GetOpt("onlyGuild") or self:IsGuildMember(pending.sender) then
            self:_inviteKeywordSender(pending.sender)
            self.pendingKeywordGuild[key] = nil
        else
            self:RequestGuildRoster()
        end
    end
end

function Invite:_buildMassPending(ranks)
    local q = self._q
    local out = {}
    local me = q.playerName()
    local minLvl = q.minLevel()
    for i = 1, q.numGuild() do
        local name, _, rankIndex, level, _, _, _, _, online, _, _, _, _, isMobile = q.guildInfo(i)
        if name and online and not isMobile
            and ranks[(rankIndex or 0) + 1]
            and level and level >= minLvl
            and not q.inUnitGroup(name)
            and stripRealm(name) ~= me
        then
            out[#out + 1] = name
        end
    end
    return out
end

-- Invite from self.pending, honoring the 5-person party cap before raid.
function Invite:_pump()
    local q, group = self._q, self._group
    local inRaid = q.isInRaid()
    if not inRaid then self.convertToRaid = true end
    local slots = inRaid and math.huge or (5 - math.max(q.numGroup(), 1))
    while #self.pending > 0 and slots > 0 do
        safeInvite(group, table.remove(self.pending, 1))
        slots = slots - 1
    end
end

-- Roster-event continuation (the cap->convert->resume dance, ported faithfully).
function Invite:OnGroupRosterUpdate()
    local inRaid = self._q.isInRaid()
    if inRaid then
        self.convertToRaid = false
    elseif self.convertToRaid then
        self._group.ConvertToRaid()
        return
    end
    if self.mode and inRaid and #self.pending > 0 then
        self:_pump()
    end
    if self.mode and #self.pending == 0 then
        self.mode = nil
    end
end

local function leaderGuard(self)
    if not self._q.isLeader() then
        ns:Print("You must be the raid leader.", "warning")
        return false
    end
    return true
end

function Invite:StartMassInvite(seconds)
    seconds = seconds or 10
    local ranks = (ns:GetModule("DB").db.settings.invite.ranks) or {}
    local function go()
        self.mode = "mass"
        self.pending = self:_buildMassPending(ranks)
        if #self.pending == 0 then
            ns:Print("No eligible guild members to invite.", "warning")
            self.mode = nil
            return
        end
        self:_pump()
    end
    if seconds <= 0 then go(); return end
    if IsInGuild() then
        SendChatMessage(("[iddqd] Mass-inviting selected ranks in %d seconds. Please leave your groups."):format(seconds), "GUILD")
    end
    ns:Print(("Mass invite in %d seconds..."):format(seconds), "warning")
    if self.countdownTimer then self.countdownTimer:Cancel() end
    local remaining = seconds
    if self.onCountdown then self.onCountdown(remaining) end
    self.countdownTimer = C_Timer.NewTicker(1, function(ticker)
        remaining = remaining - 1
        if remaining <= 0 then
            ticker:Cancel()
            self.countdownTimer = nil
            if self.onCountdown then self.onCountdown(nil) end
            ns:Print("Sending invites now.", "success")
            go()
        else
            if self.onCountdown then self.onCountdown(remaining) end
        end
    end)
end

function Invite:CancelMassInvite()
    if self.countdownTimer then
        self.countdownTimer:Cancel()
        self.countdownTimer = nil
        ns:Print("Mass invite cancelled.", "warning")
        if IsInGuild() then SendChatMessage("[iddqd] Mass invite cancelled.", "GUILD") end
    end
    if self.onCountdown then self.onCountdown(nil) end
end

function Invite:IsCountingDown() return self.countdownTimer ~= nil end

function Invite:DisbandRaid()
    if not leaderGuard(self) then return end
    local q = self._q
    local me = q.playerName()
    for j = q.numGroup(), 1, -1 do
        local name = q.raidInfo(j)
        if name and stripRealm(name) ~= me and name ~= me then
            self._group.UninviteUnit(name)
        end
    end
end

function Invite:DemoteAll()
    if not leaderGuard(self) then return end
    local q = self._q
    for i = 1, q.numGroup() do
        local name, rank = q.raidInfo(i)
        if name and rank == 1 then self._group.DemoteAssistant(name) end
    end
end

function Invite:Reinvite()
    if not leaderGuard(self) then return end
    if not self._q.isInRaid() then ns:Print("You are not in a raid.", "warning"); return end
    local q = self._q
    wipe(self.reinviteList)
    for j = 1, q.numGroup() do
        local name = q.raidInfo(j)
        if name then self.reinviteList[#self.reinviteList + 1] = name end
    end
    self:DisbandRaid()
    C_Timer.After(5, function()
        self.pending = {}
        for i = 1, #self.reinviteList do self.pending[i] = self.reinviteList[i] end
        self.mode = "reinvite"
        self.convertToRaid = false
        self:_pump()
    end)
end

function Invite:OnWhisper(msg, sender, source)
    local s = ensureSettings()
    if not (s and msg and sender) then return end

    source = source or "WHISPER"
    if source == "WHISPER" then
        if not s.invByChat then return end
    elseif not s.invByChatSay then
        return
    end

    if stripRealm(sender) == self._q.playerName() then return end

    local words = self.invWords
    if not words or next(words) == nil then words = self:RebuildInvWords() end
    local keyword = trimLower(msg)
    local matchesKeyword = words[keyword] or words["anykeyword"]
    if not matchesKeyword then return end

    if not s.onlyGuild then
        self:_inviteKeywordSender(sender)
        return
    end

    if self:IsGuildMember(sender) then
        self:_inviteKeywordSender(sender)
        return
    end

    self:QueueGuildKeywordInvite(sender, source)
end

function Invite:OnInit()
    ns:GetModule("Nav"):RegisterPanel("invite", function(parent)
        return ns:GetModule("InvitePanel"):Build(parent)
    end)
end

function Invite:OnEnable()
    if self._enabled then return end
    self._enabled = true
    self:RequestGuildRoster()
    self:RebuildInvWords()
    local Events = ns:GetModule("Events")
    Events:On("GROUP_ROSTER_UPDATE", function() self:OnGroupRosterUpdate() end, "Invite")
    Events:On("GUILD_ROSTER_UPDATE", function() self:ProcessPendingKeywordInvites() end, "Invite")
    Events:On("CHAT_MSG_WHISPER", function(msg, sender) self:OnWhisper(msg, sender, "WHISPER") end, "Invite")
    Events:On("CHAT_MSG_SAY", function(msg, sender) self:OnWhisper(msg, sender, "SAY") end, "Invite")
    Events:On("CHAT_MSG_YELL", function(msg, sender) self:OnWhisper(msg, sender, "YELL") end, "Invite")
end
