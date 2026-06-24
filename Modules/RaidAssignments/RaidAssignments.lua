local ADDON, ns = ...

-- Raid Assignments: free-text assignment notes (tanks, heals, interrupts, etc.), organised into
-- named "sets" (e.g. one per raid). Each set holds a single multi-line note. Officers edit and
-- can post the note to raid / raid-warning chat. Data: db.settings.raidAssignments.sets.
-- A set = { id = "...", name = "...", note = "...", updatedAt = epoch }.

local RA = ns:NewModule("RaidAssignments")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function now() return (time and time()) or 0 end

-- Deterministic-ish id without Math.random reliance (epoch + counter).
function RA:NewId()
    self._idc = (self._idc or 0) + 1
    return ("set-%d-%d"):format(now(), self._idc)
end

function RA:Store()
    local d = db()
    if not d then return nil end
    d.settings = d.settings or {}
    d.settings.raidAssignments = d.settings.raidAssignments or {}
    local r = d.settings.raidAssignments
    r.sets = r.sets or {}
    return r
end

function RA:Sets()
    local r = self:Store()
    return (r and r.sets) or {}
end

function RA:CreateSet(name)
    local r = self:Store()
    if not r then return nil end
    local set = { id = self:NewId(), name = (name and name ~= "" and name) or "New Set", note = "", updatedAt = now() }
    table.insert(r.sets, set)
    r.lastSelectedSetId = set.id
    return set
end

function RA:GetSet(id)
    for _, s in ipairs(self:Sets()) do if s.id == id then return s end end
    return nil
end

function RA:DeleteSet(id)
    local r = self:Store()
    if not r then return end
    for i, s in ipairs(r.sets) do
        if s.id == id then table.remove(r.sets, i); break end
    end
    if r.lastSelectedSetId == id then r.lastSelectedSetId = r.sets[1] and r.sets[1].id or nil end
end

function RA:SetNote(id, note)
    local s = self:GetSet(id)
    if s then s.note = note or ""; s.updatedAt = now() end
end

function RA:RenameSet(id, name)
    local s = self:GetSet(id)
    if s and name and name ~= "" then s.name = name; s.updatedAt = now() end
end

function RA:Selected()
    local r = self:Store()
    if not r then return nil end
    local s = r.lastSelectedSetId and self:GetSet(r.lastSelectedSetId)
    if s then return s end
    return self:Sets()[1]
end

function RA:Select(id)
    local r = self:Store()
    if r then r.lastSelectedSetId = id end
end

-- Post the selected set's note to chat, one line per row. channel = "RAID" | "RAID_WARNING".
function RA:Post(id, channel)
    local s = self:GetSet(id)
    if not s or not s.note or s.note == "" then return false end
    if not SendChatMessage then return false end
    channel = channel or "RAID"
    -- Raid warning needs lead/assist; fall back to RAID otherwise.
    if channel == "RAID_WARNING" then
        local canRW = (UnitIsGroupLeader and UnitIsGroupLeader("player"))
            or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
        if not canRW then channel = "RAID" end
    end
    if not (IsInRaid and IsInRaid()) then
        channel = (IsInGroup and IsInGroup()) and "PARTY" or nil
    end
    if not channel then return false end
    for line in (s.note .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then pcall(SendChatMessage, "[iddqd] " .. line, channel) end
    end
    return true
end

--------------------------------------------------------------------------------
-- Addon-comms sync (MANUAL trigger only — never automatic, so it can't misfire).
-- An officer presses "Share to Raid"; the active set is chunked and broadcast over the
-- group channel. Receivers store it as the incoming set (overwriting the synced copy) so the
-- whole raid sees the same assignments. Prefix is independent of other subsystems.
--------------------------------------------------------------------------------
local COMM_PREFIX = "IDDQD_RA1"
local CHUNK = 220

local function sendAddon(msg, channel)
    if not channel then return end
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, msg, channel, nil, "NORMAL") end
    if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        ChatThrottleLib:SendAddonMessage("NORMAL", COMM_PREFIX, msg, channel)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, channel)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, COMM_PREFIX, msg, channel)
    end
end

local function groupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0 then return "PARTY" end
    return nil
end

-- Broadcast the selected set to the group. name + note packed; note is chunked. We strip the
-- field delimiter (\1) and newlines are encoded as \2 so the note survives one-line transport.
function RA:Share(id)
    local s = self:GetSet(id)
    if not s then return false end
    local channel = groupChannel()
    if not channel then return false end
    local encNote = (s.note or ""):gsub("\\", "\\\\"):gsub("\n", "\\n")
    local name = (s.name or "Set"):gsub("[\n|]", " ")
    local payload = name .. "\1" .. encNote
    self._outSeq = (self._outSeq or 0) + 1
    local streamId = tostring(self._outSeq)
    local chunks = {}
    local pos = 1
    while pos <= #payload do chunks[#chunks + 1] = payload:sub(pos, pos + CHUNK - 1); pos = pos + CHUNK end
    if #chunks == 0 then chunks[1] = "" end
    sendAddon(("STR|%s|%d"):format(streamId, #chunks), channel)
    for i, c in ipairs(chunks) do sendAddon(("DAT|%s|%d|%s"):format(streamId, i, c), channel) end
    sendAddon(("END|%s"):format(streamId), channel)
    return true
end

RA._incoming = {}

function RA:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX or not message then return end
    -- Ignore our own echo (RAID addon messages are not echoed, but guard anyway).
    local me = UnitName and UnitName("player")
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if sender and me and ((Players and Players.Same and Players:Same(sender, me)) or sender == me or sender:match("^([^-]+)") == me) then return end
    local op, rest = message:match("^(%u%u%u)|(.*)$")
    if not op then return end
    if op == "STR" then
        local sid, total = rest:match("^([^|]+)|(%d+)$")
        if sid then self._incoming[sender .. ":" .. sid] = { total = tonumber(total), chunks = {} } end
    elseif op == "DAT" then
        local sid, idx, data = rest:match("^([^|]+)|(%d+)|(.*)$")
        local stream = sid and self._incoming[sender .. ":" .. sid]
        if stream then stream.chunks[tonumber(idx)] = data or "" end
    elseif op == "END" then
        local sid = rest:match("^([^|]+)$")
        local key = sid and (sender .. ":" .. sid)
        local stream = key and self._incoming[key]
        if not stream then return end
        self._incoming[key] = nil
        local parts = {}
        for i = 1, (stream.total or 0) do
            if stream.chunks[i] == nil then return end   -- missing chunk: drop
            parts[i] = stream.chunks[i]
        end
        local payload = table.concat(parts)
        local name, encNote = payload:match("^([^\1]*)\1(.*)$")
        if not name then return end
        local note = encNote:gsub("\\n", "\n"):gsub("\\\\", "\\")
        self:ApplyShared(sender, name, note)
    end
end

-- Store/replace a received set (one per sender) and refresh the panel if open.
function RA:ApplyShared(sender, name, note)
    local r = self:Store()
    if not r then return end
    local label = ("%s (from %s)"):format(name, sender or "?")
    -- Find an existing synced set from this sender to overwrite, else create one.
    local target
    for _, s in ipairs(r.sets) do
        if s.syncedFrom == sender then target = s; break end
    end
    if not target then
        target = { id = self:NewId(), syncedFrom = sender }
        table.insert(r.sets, target)
    end
    target.name = label
    target.note = note or ""
    target.updatedAt = now()
    local panel = ns:GetModule("RaidAssignmentsPanel")
    if panel and panel.frame and panel.frame.Refresh and panel.frame:IsShown() then panel.frame:Refresh() end
    ns:Print(("Received raid assignments from %s."):format(sender or "?"), "success")
end

function RA:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix(COMM_PREFIX)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    end
    local e = ns:GetModule("Events")
    if e and e.On then
        e:On("CHAT_MSG_ADDON", function(prefix, message, chan, sender)
            self:OnAddonMessage(prefix, message, chan, sender)
        end, "RaidAssignments")
    end
end

return RA
