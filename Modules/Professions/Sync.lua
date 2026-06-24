local ADDON, ns = ...

local Sync = ns:NewModule("ProfessionsSync")

local PROTOCOL_VERSION = 7
local COMM_PREFIX = "IDDQD_PROF"
local CHUNK_SIZE = 185

local function Store() return ns:GetModule("ProfessionsStore") end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function samePlayer(a, b)
    local players = Players()
    if players and players.Same then return players:Same(a, b) end
    a = tostring(a or ""):lower(); b = tostring(b or ""):lower()
    local an = a:match("^([^-]+)") or a
    local bn = b:match("^([^-]+)") or b
    return a == b or an == bn
end

function Sync:ChunkPayload(payload)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.ChunkPayload then return Comm:ChunkPayload(payload, CHUNK_SIZE) end
    payload = tostring(payload or "")
    local chunks = {}
    if #payload == 0 then return chunks end
    local pos = 1
    while pos <= #payload do
        chunks[#chunks + 1] = payload:sub(pos, pos + CHUNK_SIZE - 1)
        pos = pos + CHUNK_SIZE
    end
    return chunks
end

function Sync:ActiveIncomingCount()
    local n = 0
    for _ in pairs(self.incoming or {}) do n = n + 1 end
    return n
end

function Sync:ActiveOutgoingCount()
    local n = 0
    for _, e in pairs(self.outgoing or {}) do if not e.finished then n = n + 1 end end
    return n
end

function Sync:EnqueueOutgoing(target, professionName, ownerKey, source)
    self.outQueue = self.outQueue or {}
    self.outQueue[#self.outQueue + 1] = { target = target, profession = professionName, ownerKey = ownerKey, source = source }
    self:PumpOutgoing()
end

function Sync:PumpOutgoing()
    if self:ActiveOutgoingCount() > 0 then return end   -- 1-out: one active stream at a time
    self.outQueue = self.outQueue or {}
    local job = table.remove(self.outQueue, 1)
    if job then self:StartOutgoing(job.target, job.profession, job.ownerKey, job.source) end
end

-- Message router. Drops anything not on protocol version 7 (clean break).
function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local op, rest = message:match("^([A-Z0-9]+)|?(.*)$")
    if not op then return end
    local version = rest:match("^(%d+)")
    if tonumber(version) ~= PROTOCOL_VERSION then return end
    if self.handlers and self.handlers[op] then
        self.handlers[op](self, rest, sender, channel)
    end
end

local QUIET_TIMEOUT = 2
local MAX_NAK = 5
local MAX_CHECKSUM_RETRIES = 2
local MAX_PENDING_STALE = 500
local CHUNK_DELAY = 0.3
local OUTGOING_CACHE_AGE = 60
local LOGIN_BROADCAST_BASE = 10
local LOGIN_BROADCAST_WINDOW = 30
local MANIFEST_DEBOUNCE = 5
local MANIFEST_REBROADCAST_SUPPRESS = 30
local REQMAN_RESPONSE_JITTER = 30   -- spread REQMAN responses across the same window as login broadcasts
local RELAY_JITTER = 10   -- wide enough that the first RELAYCLAIM propagates before the next candidate fires (relay is for an offline owner; a few extra seconds is invisible)
local RELAY_TIMEOUT = 15  -- if no stream materialises within this many seconds, re-queue for retry
local BACKGROUND_INTERVAL = 12
local REQUEST_COOLDOWN = 60

local function sendAddon(msg, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, msg, channel, target, "BULK") end
    -- Route through ChatThrottleLib at BULK priority (the de-facto addon throttling
    -- standard) so guild-scale sends respect the CPS budget, burst cap, and post-login
    -- clamp. Falls back to a direct send when CTL is absent (e.g. test harness).
    if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        ChatThrottleLib:SendAddonMessage("BULK", COMM_PREFIX, msg, channel, target)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, channel, target)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, COMM_PREFIX, msg, channel, target)
    end
end

-- Split a "|"-delimited body into fields (keeps empty fields).
local function split(rest)
    local out = {}
    for part in (rest .. "|"):gmatch("([^|]*)|") do out[#out + 1] = part end
    return out
end

-- BUG 1 FIX: namespace incoming-stream keys by sender to prevent collision
-- when two senders independently choose the same streamId (e.g. both pick "o1").
local function incomingKey(sender, streamId)
    return tostring(sender or "?") .. "\31" .. tostring(streamId or "")
end

function Sync:ScheduleQuiet(key)
    if not C_Timer then return end
    local stream = self.incoming[key]
    if not stream then return end
    stream.token = (stream.token or 0) + 1
    local token = stream.token
    C_Timer.After(QUIET_TIMEOUT, function()
        local s = self.incoming[key]
        if s and s.token == token then self:EvaluateIncoming(key) end
    end)
end

function Sync:EvaluateIncoming(key)
    local stream = self.incoming[key]
    if not stream then return end

    -- BUG 4 FIX: bound the wait for the STR7 header; clean up if it never arrives.
    if not stream.total then
        stream.headerWaits = (stream.headerWaits or 0) + 1
        if stream.headerWaits >= 2 then
            self.incoming[key] = nil  -- header never arrived; clean up, no leak
            self:PumpRequests()
        else
            self:ScheduleQuiet(key)
        end
        return
    end

    -- BUG 3 FIX: handle total==0 as a legitimate empty-payload profession
    -- (e.g. Fishing/Cooking with no recipes): verify checksum over empty string.
    if stream.total == 0 then
        local verify = ns.ProfessionsStoreShortHash("" .. "|" .. tostring(tonumber(stream.rank) or "") .. "|" .. tostring(tonumber(stream.maxRank) or ""))
        if verify == stream.checksum then
            Store():SetProfession(stream.ownerKey, stream.profession, {
                rank = stream.rank, maxRank = stream.maxRank, spellIds = {},
            }, stream.source)
            self.checksumFailures = self.checksumFailures or {}
            self.checksumFailures[tostring(stream.ownerKey) .. "\31" .. tostring(stream.profession)] = nil
            self.wantedHash = self.wantedHash or {}
            self.wantedHash[tostring(stream.ownerKey) .. "\31" .. tostring(stream.profession)] = nil
            local panel = ns:GetModule("ProfessionsPanel")
            if panel and panel.Refresh then panel:Refresh() end
        end
        self.incoming[key] = nil
        self:PumpRequests()
        return
    end

    local missing = {}
    for i = 1, stream.total do if not stream.chunks[i] then missing[#missing + 1] = i end end
    if #missing == 0 then
        local parts = {}
        for i = 1, stream.total do parts[i] = stream.chunks[i] end
        local payload = table.concat(parts)
        local verify = ns.ProfessionsStoreShortHash(payload .. "|" .. tostring(tonumber(stream.rank) or "") .. "|" .. tostring(tonumber(stream.maxRank) or ""))
        if verify == stream.checksum then
            local spellIds = {}
            for id in payload:gmatch("(%d+)") do spellIds[#spellIds + 1] = tonumber(id) end
            Store():SetProfession(stream.ownerKey, stream.profession, {
                rank = stream.rank, maxRank = stream.maxRank, spellIds = spellIds,
            }, stream.source)
            -- BUG 2 FIX: clear the failure counter on successful commit so a later
            -- legitimate retransmission is not permanently blocked.
            self.checksumFailures = self.checksumFailures or {}
            self.checksumFailures[tostring(stream.ownerKey) .. "\31" .. tostring(stream.profession)] = nil
            self.wantedHash = self.wantedHash or {}
            self.wantedHash[tostring(stream.ownerKey) .. "\31" .. tostring(stream.profession)] = nil
            local panel = ns:GetModule("ProfessionsPanel")
            if panel and panel.Refresh then panel:Refresh() end
            self.incoming[key] = nil
            self:PumpRequests()
            return
        else
            -- BUG 2 FIX: track checksum-failure counts in a table on self, keyed by
            -- (sender, profession), independent of stream lifetime so the count
            -- survives stream teardown and actually bounds re-request calls.
            local sender, profession = stream.sender, stream.profession
            self.incoming[key] = nil
            self.checksumFailures = self.checksumFailures or {}
            local fkey = tostring(stream.ownerKey) .. "\31" .. tostring(profession)
            local count = (self.checksumFailures[fkey] or 0) + 1
            self.checksumFailures[fkey] = count
            if count <= MAX_CHECKSUM_RETRIES then
                self:RequestProfession(sender, profession)
            end
            self:PumpRequests()
            return
        end
    end
    if (stream.nakCount or 0) < MAX_NAK then
        stream.nakCount = (stream.nakCount or 0) + 1
        -- NAK7 must echo the raw streamId the SENDER knows (stream.streamId),
        -- NOT the namespaced key used internally.
        sendAddon(("NAK7|%d|%s|%s"):format(PROTOCOL_VERSION, stream.streamId, table.concat(missing, ",")), "WHISPER", stream.sender)
        self:ScheduleQuiet(key)
    else
        self.incoming[key] = nil  -- give up: nothing stored, no infinite loop
        self:PumpRequests()
    end
end

function Sync:BroadcastManifest()
    local store = Store()
    local manifest = store:Manifest()
    if not manifest then return end
    local parts = {}
    for professionName, hash in pairs(manifest.professions or {}) do
        parts[#parts + 1] = professionName .. ":" .. tostring(hash)
    end
    local body = ("%d|%s|%s|%s|%s|%s|%s"):format(
        PROTOCOL_VERSION, manifest.key or "", manifest.name or "", manifest.realm or "",
        manifest.class or "", tostring(manifest.updatedAt or ""), table.concat(parts, ","))
    sendAddon("MAN7|" .. body, "GUILD", nil)
end

-- Pure: compute the jittered login-broadcast delay. rng() returns 0..1.
function Sync:LoginBroadcastDelay(rng)
    local r = (rng or math.random)()
    return LOGIN_BROADCAST_BASE + (tonumber(r) or 0) * LOGIN_BROADCAST_WINDOW
end

-- Broadcast now + stamp lastManifestAt (so REQMAN suppression works).
function Sync:DoBroadcastManifest()
    self.lastManifestAt = (time and time()) or 0
    self:BroadcastManifest()
end

-- Debounced: collapse a burst of local changes into one MAN7.
function Sync:ScheduleManifestBroadcast()
    if not C_Timer then self:DoBroadcastManifest(); return end
    self._manToken = (self._manToken or 0) + 1
    local token = self._manToken
    C_Timer.After(MANIFEST_DEBOUNCE, function()
        if self._manToken == token then self:DoBroadcastManifest() end
    end)
end

function Sync:OnLocalChange(professionName)
    self:ScheduleManifestBroadcast()
end

function Sync:EnqueueRequest(owner, professionName)
    self.requestQueue = self.requestQueue or {}
    -- de-dupe: don't queue the same owner+profession twice
    for _, job in ipairs(self.requestQueue) do
        if job.owner == owner and job.profession == professionName then return end
    end
    if #self.requestQueue >= 100 then
        ns:Debug("Professions request queue full; dropping", tostring(owner), tostring(professionName))
        return
    end
    self.requestQueue[#self.requestQueue + 1] = { owner = owner, profession = professionName }
    self:PumpRequests()
end

function Sync:PumpRequests()
    if self:ActiveIncomingCount() > 0 then return end  -- 1-in rule: wait for the active stream
    self.requestQueue = self.requestQueue or {}
    local job = table.remove(self.requestQueue, 1)
    if job then self:RequestProfession(job.owner, job.profession) end
end

function Sync:SetPanelOpen(open)
    self.panelOpen = open and true or false
    if self.panelOpen then
        self:PumpRequests()
    else
        -- Panel closed: don't drop queued requests — hand them to the background ticker
        -- (pendingStale) so they still converge, instead of stranding them behind cooldowns.
        for _, job in ipairs(self.requestQueue or {}) do
            self:AddPendingStale(job.owner, job.profession)
        end
        self.requestQueue = {}
    end
end

function Sync:BeginManualSync()
    self.manualSyncUntil = ((time and time()) or 0) + 120
    self:DoBroadcastManifest()
    self:PumpRequests()
end

function Sync:OnInit()
    self.incoming = self.incoming or {}
    self.outgoing = self.outgoing or {}
    self.handlers = self.handlers or {}
    self.requestQueue = self.requestQueue or {}
    self.checksumFailures = self.checksumFailures or {}
    self.pendingRelay = self.pendingRelay or {}
    self.outQueue = self.outQueue or {}
    self.pendingStale = self.pendingStale or {}
    self.pendingStaleSet = self.pendingStaleSet or {}
    self.requestCooldown = self.requestCooldown or {}
    self.wantedHash = self.wantedHash or {}
    if Store().MigrateOrReset then Store():MigrateOrReset() end
end

function Sync:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix(COMM_PREFIX)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    end
    local events = ns:GetModule("Events")
    if events and events.On then
        events:On("CHAT_MSG_ADDON", function(prefix, message, channel, msgSender)
            self:OnAddonMessage(prefix, message, channel, msgSender)
        end, self)
    end
    if C_Timer then
        local delay = self:LoginBroadcastDelay(math.random)
        C_Timer.After(delay, function() self:DoBroadcastManifest() end)
        C_Timer.After(delay + 1, function()
            -- Only ask the guild to re-advertise if we don't already have fresh local data
            -- to share. Avoids every client pinging during a simultaneous login storm.
            if (self.lastManifestAt or 0) == 0 then
                sendAddon(("REQMAN|%d"):format(PROTOCOL_VERSION), "GUILD", nil)
            end
        end)
        self:StartBackgroundTicker()
    end
end

function Sync:NextOutgoingId()
    self.outSeq = (self.outSeq or 0) + 1
    self.lastOutId = "o" .. tostring(self.outSeq)
    return self.lastOutId
end

function Sync:LastOutgoingStreamId()
    return self.lastOutId
end

function Sync:StartOutgoing(target, professionName, ownerKey, source)
    local store = Store()
    source = source or "owner"
    ownerKey = ownerKey or (store:LocalProfile() and store:LocalProfile().key)
    -- Evict stale cached outgoing streams so the table doesn't grow unbounded.
    local nowTs = (time and time()) or 0
    self.outgoing = self.outgoing or {}
    for id, entry in pairs(self.outgoing) do
        if (nowTs - (entry.at or 0)) > OUTGOING_CACHE_AGE then self.outgoing[id] = nil end
    end
    local profile = store:Profile(ownerKey)
    local prof = profile and profile.professions and profile.professions[professionName]
    if not prof then return end
    local ids = {}
    for _, id in ipairs(prof.spellIds or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local payload = table.concat(ids, ",")
    local checksum = store:ProfessionHash(prof.spellIds, prof.rank, prof.maxRank)
    local chunks = self:ChunkPayload(payload)
    local total = #chunks
    local streamId = self:NextOutgoingId()
    self.outgoing[streamId] = {
        target = target, profession = professionName, ownerKey = ownerKey, source = source,
        chunks = chunks, total = total, checksum = checksum, rank = prof.rank, maxRank = prof.maxRank,
        at = (time and time()) or 0,
    }
    -- STR7|v|streamId|profession|total|checksum|rank|maxRank|ownerKey|source
    sendAddon(("STR7|%d|%s|%s|%d|%s|%s|%s|%s|%s"):format(
        PROTOCOL_VERSION, streamId, professionName, total, checksum,
        tostring(prof.rank or ""), tostring(prof.maxRank or ""),
        tostring(ownerKey or ""), source), "WHISPER", target)
    for i = 1, total do
        local idx = i
        local function fire() sendAddon(("DAT7|%d|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, idx, chunks[idx]), "WHISPER", target) end
        if C_Timer then C_Timer.After(CHUNK_DELAY * i, fire) else fire() end
    end
    local function finish()
        sendAddon(("END7|%d|%s"):format(PROTOCOL_VERSION, streamId), "WHISPER", target)
        local e = self.outgoing[streamId]; if e then e.finished = true end
        self:PumpOutgoing()
    end
    if C_Timer then C_Timer.After(CHUNK_DELAY * (total + 1), finish) else finish() end
end

-- Pure: decide how to obtain ownerKey's data. isOnline(ownerKey) injected (IO at call site).
function Sync:ResolveRequestSource(ownerKey, isOnline)
    if isOnline and isOnline(ownerKey) then return "owner" end
    return "relay"
end

function Sync:AutoShareEnabled()
    local db = ns:GetModule("DB"); db = db and db.db
    local s = db and db.professions and db.professions.settings
    if not s then return true end
    return s.autoGuildSync ~= false
end

-- Pure: pause sync during combat / instances. Predicates injected for tests.
function Sync:ShouldPauseSync(inCombat, inInstance)
    if inCombat and inCombat() then return true end
    if inInstance and inInstance() then return true end
    return false
end

-- O(1) dedup helper for pendingStale: uses a companion set to avoid linear scans.
-- Returns true if the item was added, false if it was already present or the list is full.
function Sync:AddPendingStale(owner, profession)
    self.pendingStale = self.pendingStale or {}
    self.pendingStaleSet = self.pendingStaleSet or {}
    local k = tostring(owner) .. "\31" .. tostring(profession)
    if self.pendingStaleSet[k] then return false end
    if #self.pendingStale >= MAX_PENDING_STALE then
        ns:Debug("Professions pendingStale full; dropping", tostring(owner), tostring(profession))
        return false
    end
    self.pendingStaleSet[k] = true
    self.pendingStale[#self.pendingStale + 1] = { owner = owner, profession = profession }
    return true
end

-- Pull at most one pending-stale item (owner-first via existing 1-in queue). Returns 0/1.
function Sync:DrainBackgroundOnce()
    self.pendingStale = self.pendingStale or {}
    if #self.pendingStale == 0 then return 0 end
    -- Don't drain into a full request queue (the item would be dropped); wait for a later tick.
    if #(self.requestQueue or {}) >= 100 then return 0 end
    local job = table.remove(self.pendingStale, 1)
    self.pendingStaleSet = self.pendingStaleSet or {}
    self.pendingStaleSet[tostring(job.owner) .. "\31" .. tostring(job.profession)] = nil
    self:EnqueueRequest(job.owner, job.profession)
    return 1
end

-- IO ticker: periodically drain one item if auto-share on and not paused.
function Sync:StartBackgroundTicker()
    if not C_Timer or self._bgTicking then return end
    self._bgTicking = true
    local function tick()
        if not self._bgTicking then return end
        local paused = self:ShouldPauseSync(
            function() return InCombatLockdown and InCombatLockdown() end,
            function() local i = IsInInstance and IsInInstance(); return i and true or false end)
        if self:AutoShareEnabled() and not self.panelOpen and not paused then
            self:DrainBackgroundOnce()
        end
        local jitter = (math.random()) * 4
        C_Timer.After(BACKGROUND_INTERVAL + jitter, tick)
    end
    C_Timer.After(BACKGROUND_INTERVAL, tick)
end

-- Best-effort online check via guild roster; "unknown" -> treat as offline (use relay).
function Sync:IsGuildMemberOnline(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    local players = Players()
    local short = players and players.ShortName and players:ShortName(name) or (tostring(name):match("^([^-]+)") or name)
    for i = 1, (GetNumGuildMembers() or 0) do
        local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if gname then
            local gshort = players and players.ShortName and players:ShortName(gname) or (tostring(gname):match("^([^-]+)") or gname)
            if gname == name or gshort == short then return online and true or false end
        end
    end
    return false
end

function Sync:RequestProfession(owner, professionName)
    local store = Store()
    local profile = store:Profile(owner)
    local prof = profile and profile.professions and profile.professions[professionName]
    local known = prof and prof.hash or ""
    -- per-(owner,profession) cooldown to avoid request loops
    -- Retry relies on manifest re-advertisement + cooldown expiry (no separate retry timer needed).
    self.requestCooldown = self.requestCooldown or {}
    local ckey = tostring(owner) .. "\31" .. tostring(professionName)
    local nowTs = (time and time()) or 0
    if (nowTs - (self.requestCooldown[ckey] or 0)) < REQUEST_COOLDOWN then return end
    self.requestCooldown[ckey] = nowTs
    local src = self:ResolveRequestSource(owner, function(o) return self:IsGuildMemberOnline(o) end)
    if src == "owner" then
        sendAddon(("REQ7|%d|%s|%s"):format(PROTOCOL_VERSION, professionName, known), "WHISPER", owner)
    else
        -- offline owner: ask the guild for a cached copy at the OWNER's advertised hash.
        self.wantedHash = self.wantedHash or {}
        local wantHash = self.wantedHash[ckey] or (prof and prof.hash) or known
        sendAddon(("RELAYREQ|%d|%s|%s|%s"):format(PROTOCOL_VERSION, owner, professionName, wantHash), "GUILD", nil)
        -- Requester-side retry: if no stream materializes (all candidates evicted, or the
        -- claim/relay was lost), re-queue for the background ticker so it converges later.
        if C_Timer then
            C_Timer.After(RELAY_TIMEOUT, function()
                local store2 = Store()
                if store2:NeedsUpdate(owner, professionName, wantHash) then
                    self:AddPendingStale(owner, professionName)
                end
            end)
        end
    end
end

Sync.incoming = {}
Sync.handlers = {}

-- BUG 1 FIX: STR7 handler keys self.incoming by incomingKey(sender, streamId).
-- The raw streamId is stored on the stream so NAK7 replies echo the sender's own id.
Sync.handlers["STR7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId f[3]=profession f[4]=total f[5]=checksum f[6]=rank f[7]=maxRank [f[8]=ownerKey f[9]=source]
    local streamId = f[2]
    if not streamId or streamId == "" then return end
    local key = incomingKey(sender, streamId)
    self.incoming[key] = self.incoming[key] or { chunks = {}, received = 0 }
    local stream = self.incoming[key]
    stream.sender   = sender
    stream.streamId = streamId  -- raw id for NAK7 replies
    stream.profession = f[3]
    stream.total    = tonumber(f[4]) or 0
    stream.checksum = f[5]
    stream.rank     = tonumber(f[6])
    stream.maxRank  = tonumber(f[7])
    stream.ownerKey = (f[8] ~= nil and f[8] ~= "") and f[8] or sender   -- relay: real owner; else the sender is the owner
    stream.source   = (f[9] == "cache") and "cache" or "owner"   -- whitelist: only cache|owner
    self:ScheduleQuiet(key)
end

-- BUG 1 FIX: DAT7 handler keys self.incoming by incomingKey(sender, streamId).
Sync.handlers["DAT7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId f[3]=index f[4]=payload
    local streamId, index = f[2], tonumber(f[3])
    if not streamId or streamId == "" or not index then return end
    local key = incomingKey(sender, streamId)
    local stream = self.incoming[key]
    if not stream then  -- chunk arrived before STR7: buffer it
        stream = { chunks = {}, received = 0, sender = sender, streamId = streamId }
        self.incoming[key] = stream
    end
    if not stream.chunks[index] then
        stream.chunks[index] = f[4] or ""
        stream.received = stream.received + 1
    end
    self:ScheduleQuiet(key)
end

-- BUG 1 FIX: END7 handler receives sender and keys self.incoming by incomingKey(sender, streamId).
-- Previously the signature was function(self, rest) with sender dropped, causing all END7
-- lookups to use the wrong (un-namespaced) key and never find the stream.
Sync.handlers["END7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId
    local streamId = f[2]
    if not streamId then return end
    local key = incomingKey(sender, streamId)
    if self.incoming[key] then self:EvaluateIncoming(key) end
end

Sync.handlers["REQ7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=profession f[3]=knownHash
    local professionName, knownHash = f[2], f[3]
    local store = Store()
    local profile = store:LocalProfile()
    local prof = profile and profile.professions and profile.professions[professionName]
    if not prof then return end
    if knownHash == prof.hash then return end  -- requester already current
    self:EnqueueOutgoing(sender, professionName)
end

Sync.handlers["NAK7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId f[3]=missingList
    local streamId = f[2]
    local out = self.outgoing and self.outgoing[streamId]
    if not out then return end
    if out.target ~= sender then return end          -- only the legitimate target may NAK
    out.nakCount = (out.nakCount or 0) + 1
    if out.nakCount > MAX_NAK then return end          -- bound resends; ignore floods
    for idx in (f[3] or ""):gmatch("(%d+)") do
        idx = tonumber(idx)
        if out.chunks[idx] then
            sendAddon(("DAT7|%d|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, idx, out.chunks[idx]), "WHISPER", out.target)
        end
    end
    sendAddon(("END7|%d|%s"):format(PROTOCOL_VERSION, streamId), "WHISPER", out.target)
end

Sync.handlers["MAN7"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=key f[3]=name f[4]=realm f[5]=class f[6]=updatedAt f[7]=profession:hash,...
    local key = f[2]
    if not key or key == "" then return end
    if not samePlayer(key, sender) then return end
    local store = Store()
    local nowTs = (time and time()) or 0
    for entry in (f[7] or ""):gmatch("([^,]+)") do
        local professionName, hash = entry:match("^([^:]+):(.+)$")
        if professionName and hash then
            if store:NeedsUpdate(key, professionName, hash) then
                self.wantedHash = self.wantedHash or {}
                self.wantedHash[tostring(key) .. "\31" .. tostring(professionName)] = hash
                if self.panelOpen or (self.manualSyncUntil and nowTs <= self.manualSyncUntil) then
                    self:EnqueueRequest(key, professionName)
                elseif self:AutoShareEnabled() then
                    self:AddPendingStale(key, professionName)
                end
            end
        end
    end
end

Sync.handlers["REQMAN"] = function(self, rest, sender)
    -- A guildmate asks everyone to re-advertise. Respond only if our manifest is stale,
    -- and spread responses across a wide window so a login storm (where everyone is stale
    -- at once) does not collapse into a simultaneous burst. Re-check staleness at fire time
    -- so a member who broadcasts during the spread (or a second REQMAN) does not double-send.
    local nowTs = (time and time()) or 0
    if (nowTs - (self.lastManifestAt or 0)) < MANIFEST_REBROADCAST_SUPPRESS then return end
    if C_Timer then
        local delay = (math.random()) * REQMAN_RESPONSE_JITTER
        C_Timer.After(delay, function()
            local now2 = (time and time()) or 0
            if (now2 - (self.lastManifestAt or 0)) >= MANIFEST_REBROADCAST_SUPPRESS then
                self:DoBroadcastManifest()
            end
        end)
    else
        self:DoBroadcastManifest()
    end
end

-- Key for an in-flight relay-serve we're considering.
local function relayKey(ownerKey, professionName, hash)
    return tostring(ownerKey) .. "\31" .. tostring(professionName) .. "\31" .. tostring(hash)
end

Sync.handlers["RELAYREQ"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=ownerKey f[3]=profession f[4]=hash
    local ownerKey, professionName, hash = f[2], f[3], f[4]
    if not ownerKey or not professionName or not hash then return end
    if not Store():HasCachedProfession(ownerKey, professionName, hash) then return end  -- not a candidate
    self.pendingRelay = self.pendingRelay or {}
    local rk = relayKey(ownerKey, professionName, hash)
    local entry = self.pendingRelay[rk]
    if entry then
        -- another requester wants the same data; serve them too when we fire
        entry.requesters[sender] = true
        return
    end
    entry = { owner = ownerKey, profession = professionName, hash = hash,
              requesters = { [sender] = true }, cancelled = false }
    self.pendingRelay[rk] = entry
    local function fire()
        self.pendingRelay[rk] = nil
        if entry.cancelled then return end
        -- Re-verify we still hold the copy (eviction can race the jitter timer); if it's
        -- gone, stand down WITHOUT claiming so another valid candidate can serve.
        if not Store():HasCachedProfession(ownerKey, professionName, hash) then return end
        sendAddon(("RELAYCLAIM|%d|%s|%s|%s"):format(PROTOCOL_VERSION, ownerKey, professionName, hash), "GUILD", nil)
        for requester in pairs(entry.requesters) do
            self:EnqueueOutgoing(requester, professionName, ownerKey, "cache")
        end
    end
    if C_Timer then
        local delay = math.random() * RELAY_JITTER
        C_Timer.After(delay, fire)
    else
        fire()
    end
end

-- RELAYCLAIM is trusted: any guild member can cancel pending relays for a (owner,prof,hash)
-- tuple. Acceptable in a trusted guild; a requester-side retry (Task 7 background top-up
-- re-requests if no data arrives) covers a claim that never results in a served stream.
Sync.handlers["RELAYCLAIM"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=ownerKey f[3]=profession f[4]=hash
    local rk = relayKey(f[2], f[3], f[4])
    local entry = self.pendingRelay and self.pendingRelay[rk]
    if entry then entry.cancelled = true end  -- another relay is serving; cancel ours
end
