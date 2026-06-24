local ADDON, ns = ...
local Sync = ns:NewModule("LootSync")
local PROTOCOL_VERSION = 1
-- Bumped to ...2 for the 1.2.0 loot-format break (loot-table dropIDs, name normalization,
-- instance whitelist, chat capture). Older builds used "IDDQD_LOOT" and a different data
-- shape; changing the prefix cleanly isolates this version — old clients never registered
-- this prefix (they ignore us) and we ignore theirs. Bump this on every breaking format change.
local COMM_PREFIX = "IDDQD_LOOT2"
local CHUNK_SIZE = 185

local function Store() return ns:GetModule("LootStore") end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function sendAddon(msg, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, msg, channel, target, "BULK") end
    if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        ChatThrottleLib:SendAddonMessage("BULK", COMM_PREFIX, msg, channel, target)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, msg, channel, target)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, COMM_PREFIX, msg, channel, target)
    end
end

local function split(rest)
    local out = {}
    for part in (rest .. "|"):gmatch("([^|]*)|") do out[#out + 1] = part end
    return out
end

function Sync:ChunkPayload(payload)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.ChunkPayload then return Comm:ChunkPayload(payload, CHUNK_SIZE) end
    payload = tostring(payload or "")
    local chunks = {}
    if #payload == 0 then return chunks end
    local pos = 1
    while pos <= #payload do chunks[#chunks + 1] = payload:sub(pos, pos + CHUNK_SIZE - 1); pos = pos + CHUNK_SIZE end
    return chunks
end

-- Router: drop anything not on protocol version 1 (clean break from old DR2/TL3/LS1 ops).
function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local op, rest = message:match("^([A-Z0-9]+)|?(.*)$")
    if not op then return end
    -- Version gate: ops normally carry PROTOCOL_VERSION as the first body field.
    -- LMAN1 is the exception (its version is baked into the op name and BroadcastManifest
    -- emits no version field), so accept it when the op already encodes the version.
    if tonumber(rest:match("^(%d+)")) ~= PROTOCOL_VERSION then
        if op ~= ("LMAN" .. PROTOCOL_VERSION) then return end
    end
    if self.handlers and self.handlers[op] then self.handlers[op](self, rest, sender, channel) end
end

local function clean(v)
    return (tostring(v or ""):gsub("[~;,|\n\r]", " "))
end

-- Serialize all drops (and their events) of a session into a wire payload.
function Sync:SerializeSessionDrops(sessionID)
    local parts = {}
    local store = Store()
    local sess = store:Sessions()[sessionID] or {}
    parts[#parts + 1] = table.concat({
        "__META",
        tostring(tonumber(sess.startedAt) or ""),
        clean(sess.instance),
        clean(sess.instanceType),
        tostring(tonumber(sess.instanceId) or ""),
        tostring(tonumber(sess.difficultyId) or ""),
    }, "~")
    for dropID, drop in pairs(store:Drops()) do
        if drop.sessionID == sessionID then
            local evs = {}
            for _, e in pairs(drop.events or {}) do
                evs[#evs + 1] = table.concat({ clean(e.type), clean(e.actor), clean(e.target), tostring(tonumber(e.at) or 0), tostring(tonumber(e.remaining) or "") }, ":")
            end
            table.sort(evs)
            -- Field order: dropID ~ itemId ~ itemName ~ quality ~ events ~ bossName.
            -- (Display fields like itemName/quality/bossName are NOT part of SessionHash, so
            -- adding bossName here cannot affect convergence — it's display metadata only.)
            parts[#parts + 1] = table.concat({ clean(dropID), tostring(drop.itemId or ""), clean(drop.itemName), tostring(drop.quality or ""), table.concat(evs, ","), clean(drop.bossName) }, "~")
        end
    end
    table.sort(parts)  -- deterministic drop ordering so re-serves are byte-stable
    return table.concat(parts, "|")
end

-- Apply a received session payload: only if WE consider this session a guild session
-- (personal isolation). Merge is idempotent event-union via Store:AddEvent.
function Sync:ApplySessionPayload(sessionID, payload)
    local store = Store()
    if store:IsSessionHidden(sessionID) then return false end
    if not store:IsGuildSession(sessionID) then return false end
    local earliestDrop
    for dropPart in (payload or ""):gmatch("([^|]+)") do
        local f = {}
        for seg in (dropPart .. "~"):gmatch("([^~]*)~") do f[#f + 1] = seg end
        if f[1] == "__META" then
            store:EnsureSession(sessionID, {
                scope = "guild",
                startedAt = tonumber(f[2]),
                instance = f[3] ~= "" and f[3] or nil,
                instanceType = f[4] ~= "" and f[4] or nil,
                instanceId = tonumber(f[5]),
                difficultyId = tonumber(f[6]),
            })
        else
        local dropID, itemId, itemName, quality, evList, bossName = f[1], tonumber(f[2]), f[3], tonumber(f[4]), f[5], f[6]
        if dropID and dropID ~= "" then
            local drop = store:EnsureDrop(dropID, { sessionID = sessionID, itemId = itemId, itemName = itemName, quality = quality, bossName = (bossName ~= "" and bossName or nil) })
            if drop and drop.droppedAt and (not earliestDrop or drop.droppedAt < earliestDrop) then earliestDrop = drop.droppedAt end
            for evSeg in (evList or ""):gmatch("([^,]+)") do
                local p = {}
                for x in (evSeg .. ":"):gmatch("([^:]*):") do p[#p + 1] = x end
                local ev = { type = p[1], actor = (p[2] ~= "" and p[2] or nil), target = (p[3] ~= "" and p[3] or nil), at = tonumber(p[4]) or 0 }
                if p[5] and p[5] ~= "" then ev.remaining = tonumber(p[5]) end
                if ev.type and ev.type ~= "" then store:AddEvent(dropID, ev) end
            end
        end
        end
    end
    local sess = store:Sessions()[sessionID]
    if sess and (not sess.startedAt or sess.startedAt == 0) and earliestDrop then
        sess.startedAt = earliestDrop
    end
    return true
end

function Sync:BroadcastManifest()
    local man = Store():Manifest()
    local parts = {}
    for sessionID, hash in pairs(man) do parts[#parts + 1] = sessionID .. ":" .. hash end
    sendAddon(("LMAN%d|%s"):format(PROTOCOL_VERSION, table.concat(parts, ",")), "GUILD", nil)
end

-- ===========================================================================
-- Pull/relay/queue machinery ported from Modules/Professions/Sync.lua.
-- Sync unit = sessionID (a string). Outgoing payload = SerializeSessionDrops(sessionID),
-- checksum = ns.LootStoreShortHash(payload). All ops carry PROTOCOL_VERSION first.
-- ===========================================================================

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
local REQMAN_RESPONSE_JITTER = 30
local RELAY_JITTER = 10
local RELAY_TIMEOUT = 15
local BACKGROUND_INTERVAL = 12
local REQUEST_COOLDOWN = 60

local function samePlayer(a, b)
    local players = Players()
    if players and players.Same then return players:Same(a, b) end
    a = tostring(a or ""):lower(); b = tostring(b or ""):lower()
    local an = a:match("^([^-]+)") or a
    local bn = b:match("^([^-]+)") or b
    return a == b or an == bn
end

-- BUG 1 FIX: namespace incoming-stream keys by sender to prevent collision
-- when two senders independently choose the same streamId.
local function incomingKey(sender, streamId)
    return tostring(sender or "?") .. "\31" .. tostring(streamId or "")
end

-- Key for an in-flight relay-serve we're considering.
local function relayKey(sessionID, hash)
    return tostring(sessionID) .. "\31" .. tostring(hash)
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

-- ---------------------------------------------------------------------------
-- Outgoing (serve) 1-out queue
-- ---------------------------------------------------------------------------
function Sync:EnqueueOutgoing(target, sessionID, source)
    self.outQueue = self.outQueue or {}
    self.outQueue[#self.outQueue + 1] = { target = target, sessionID = sessionID, source = source }
    self:PumpOutgoing()
end

function Sync:PumpOutgoing()
    if self:ActiveOutgoingCount() > 0 then return end   -- 1-out: one active stream at a time
    self.outQueue = self.outQueue or {}
    local job = table.remove(self.outQueue, 1)
    if job then self:StartOutgoing(job.target, job.sessionID, job.source) end
end

function Sync:NextOutgoingId()
    self.outSeq = (self.outSeq or 0) + 1
    self.lastOutId = "o" .. tostring(self.outSeq)
    return self.lastOutId
end

function Sync:LastOutgoingStreamId()
    return self.lastOutId
end

function Sync:StartOutgoing(target, sessionID, source)
    source = source or "owner"
    -- Evict stale cached outgoing streams so the table doesn't grow unbounded.
    local nowTs = (time and time()) or 0
    self.outgoing = self.outgoing or {}
    for id, entry in pairs(self.outgoing) do
        if (nowTs - (entry.at or 0)) > OUTGOING_CACHE_AGE then self.outgoing[id] = nil end
    end
    local payload = self:SerializeSessionDrops(sessionID)
    local checksum = ns.LootStoreShortHash(payload)
    local chunks = self:ChunkPayload(payload)
    local total = #chunks
    local streamId = self:NextOutgoingId()
    self.outgoing[streamId] = {
        target = target, sessionID = sessionID, source = source,
        chunks = chunks, total = total, checksum = checksum,
        at = (time and time()) or 0,
    }
    -- LSTR1|v|streamId|sessionID|total|checksum
    sendAddon(("LSTR1|%d|%s|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, sessionID, total, checksum), "WHISPER", target)
    for i = 1, total do
        local idx = i
        local function fire() sendAddon(("LDAT1|%d|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, idx, chunks[idx]), "WHISPER", target) end
        if C_Timer then C_Timer.After(CHUNK_DELAY * i, fire) else fire() end
    end
    local function finish()
        sendAddon(("LEND1|%d|%s"):format(PROTOCOL_VERSION, streamId), "WHISPER", target)
        local e = self.outgoing[streamId]; if e then e.finished = true end
        self:PumpOutgoing()
    end
    if C_Timer then C_Timer.After(CHUNK_DELAY * (total + 1), finish) else finish() end
end

-- ---------------------------------------------------------------------------
-- Incoming (receive) stream machinery
-- ---------------------------------------------------------------------------
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

local function panelRefresh()
    local p = ns:GetModule("LootPanel")
    if p and p.Refresh then p:Refresh() end
    -- The active (tradeable) panel must refresh too: a synced drop carrying a live
    -- trade window otherwise stays invisible there until the next OnUpdate tick (or
    -- forever while the panel is hidden).
    local ap = ns:GetModule("LootActivePanel")
    if ap and ap.Refresh then ap:Refresh() end
end

function Sync:EvaluateIncoming(key)
    local stream = self.incoming[key]
    if not stream then return end

    -- BUG 4 FIX: bound the wait for the LSTR1 header; clean up if it never arrives.
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

    -- BUG 3 FIX: handle total==0 as a legitimate empty-payload guild session
    -- (a guild session with zero drops): verify checksum over empty string.
    if stream.total == 0 then
        local verify = ns.LootStoreShortHash("")
        if verify == stream.checksum then
            if not Store():IsSessionHidden(stream.sessionID) then
                Store():EnsureSession(stream.sessionID, { scope = "guild" })
            end
            self.checksumFailures = self.checksumFailures or {}
            self.checksumFailures[tostring(stream.sessionID) .. "\31" .. tostring(stream.sender)] = nil
            self.wantedHash = self.wantedHash or {}
            self.wantedHash[tostring(stream.sessionID)] = nil
            panelRefresh()
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
        local verify = ns.LootStoreShortHash(payload)
        if verify == stream.checksum then
            self:ApplySessionPayload(stream.sessionID, payload)
            -- BUG 2 FIX: clear the failure counter on successful commit so a later
            -- legitimate retransmission is not permanently blocked.
            self.checksumFailures = self.checksumFailures or {}
            self.checksumFailures[tostring(stream.sessionID) .. "\31" .. tostring(stream.sender)] = nil
            self.wantedHash = self.wantedHash or {}
            self.wantedHash[tostring(stream.sessionID)] = nil
            panelRefresh()
            self.incoming[key] = nil
            self:PumpRequests()
            return
        else
            -- BUG 2 FIX: track checksum-failure counts in a table on self, keyed by
            -- sessionID, independent of stream lifetime so the count survives stream
            -- teardown and actually bounds re-request calls.
            local sender = stream.sender
            local sessionID = stream.sessionID
            self.incoming[key] = nil
            self.checksumFailures = self.checksumFailures or {}
            -- Key by (sessionID, sender) so a corrupt/lossy stream from one relayer does not
            -- spend another sender's retry budget (the owner can still deliver after a relay fails).
            local fkey = tostring(sessionID) .. "\31" .. tostring(sender)
            local count = (self.checksumFailures[fkey] or 0) + 1
            self.checksumFailures[fkey] = count
            if count <= MAX_CHECKSUM_RETRIES then
                self.sessionOwner = self.sessionOwner or {}
                self.sessionOwner[sessionID] = self.sessionOwner[sessionID] or sender
                self:RequestSession(sessionID)
            end
            self:PumpRequests()
            return
        end
    end
    if (stream.nakCount or 0) < MAX_NAK then
        stream.nakCount = (stream.nakCount or 0) + 1
        -- LNAK1 must echo the raw streamId the SENDER knows (stream.streamId),
        -- NOT the namespaced key used internally.
        sendAddon(("LNAK1|%d|%s|%s"):format(PROTOCOL_VERSION, stream.streamId, table.concat(missing, ",")), "WHISPER", stream.sender)
        self:ScheduleQuiet(key)
    else
        self.incoming[key] = nil  -- give up: nothing stored, no infinite loop
        self:PumpRequests()
    end
end

-- ---------------------------------------------------------------------------
-- Manifest broadcast
-- ---------------------------------------------------------------------------
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

-- Debounced: collapse a burst of local changes into one LMAN1.
function Sync:ScheduleManifestBroadcast()
    if not C_Timer then self:DoBroadcastManifest(); return end
    self._manToken = (self._manToken or 0) + 1
    local token = self._manToken
    C_Timer.After(MANIFEST_DEBOUNCE, function()
        if self._manToken == token then self:DoBroadcastManifest() end
    end)
end

function Sync:OnLocalChange(sessionID)
    self:ScheduleManifestBroadcast()
end

-- Tracker calls this when a session promotes to guild scope.
function Sync:OnSessionPromoted(sessionID)
    self:DoBroadcastManifest()
end

-- ---------------------------------------------------------------------------
-- Request (pull) 1-in queue
-- ---------------------------------------------------------------------------
function Sync:EnqueueRequest(sessionID)
    self.requestQueue = self.requestQueue or {}
    -- de-dupe: don't queue the same session twice
    for _, job in ipairs(self.requestQueue) do
        if job.sessionID == sessionID then return end
    end
    if #self.requestQueue >= 100 then
        ns:Debug("Loot request queue full; dropping", tostring(sessionID))
        return
    end
    self.requestQueue[#self.requestQueue + 1] = { sessionID = sessionID }
    self:PumpRequests()
end

function Sync:PumpRequests()
    if self:ActiveIncomingCount() > 0 then return end  -- 1-in rule: wait for the active stream
    self.requestQueue = self.requestQueue or {}
    local job = table.remove(self.requestQueue, 1)
    if job then self:RequestSession(job.sessionID) end
end

function Sync:SetPanelOpen(open)
    self.panelOpen = open and true or false
    if self.panelOpen then
        self:PumpRequests()
    else
        -- Panel closed: don't drop queued requests — hand them to the background ticker
        -- (pendingStale) so they still converge, instead of stranding them behind cooldowns.
        for _, job in ipairs(self.requestQueue or {}) do
            self:AddPendingStale(job.sessionID)
        end
        self.requestQueue = {}
    end
end

function Sync:BeginManualSync()
    self.manualSyncUntil = ((time and time()) or 0) + 120
    self:DoBroadcastManifest()
    self:PumpRequests()
end

-- ---------------------------------------------------------------------------
-- Background ticker / pendingStale
-- ---------------------------------------------------------------------------
function Sync:AutoShareEnabled()
    local db = ns:GetModule("DB"); db = db and db.db
    local s = db and db.raidLootLedger and db.raidLootLedger.settings
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
function Sync:AddPendingStale(sessionID)
    self.pendingStale = self.pendingStale or {}
    self.pendingStaleSet = self.pendingStaleSet or {}
    local k = tostring(sessionID)
    if self.pendingStaleSet[k] then return false end
    if #self.pendingStale >= MAX_PENDING_STALE then
        ns:Debug("Loot pendingStale full; dropping", tostring(sessionID))
        return false
    end
    self.pendingStaleSet[k] = true
    self.pendingStale[#self.pendingStale + 1] = { sessionID = sessionID }
    return true
end

-- Pull at most one pending-stale item (via existing 1-in queue). Returns 0/1.
function Sync:DrainBackgroundOnce()
    self.pendingStale = self.pendingStale or {}
    if #self.pendingStale == 0 then return 0 end
    -- Don't drain into a full request queue (the item would be dropped); wait for a later tick.
    if #(self.requestQueue or {}) >= 100 then return 0 end
    local job = table.remove(self.pendingStale, 1)
    self.pendingStaleSet = self.pendingStaleSet or {}
    self.pendingStaleSet[tostring(job.sessionID)] = nil
    self:EnqueueRequest(job.sessionID)
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

-- Pure: decide how to obtain sessionID's data. isOnline(owner) injected (IO at call site).
function Sync:ResolveRequestSource(owner, isOnline)
    if isOnline and isOnline(owner) then return "owner" end
    return "relay"
end

function Sync:RequestSession(sessionID)
    self.sessionOwner = self.sessionOwner or {}
    local owner = self.sessionOwner[sessionID]
    if not owner then return end
    local store = Store()
    local known = store:SessionHash(sessionID)
    -- Cooldown is keyed by (sessionID, wantedHash) — NOT sessionID alone. It exists to stop
    -- re-requesting the SAME version in a loop, but must NOT block a request for a NEW version:
    -- when the owner's data changes (e.g. a delete) it advertises a new hash, and that new hash
    -- gets its own fresh request immediately instead of waiting out the previous pull's cooldown.
    self.wantedHash = self.wantedHash or {}
    local wantHash = self.wantedHash[tostring(sessionID)] or ""
    self.requestCooldown = self.requestCooldown or {}
    local ckey = tostring(sessionID) .. "\31" .. tostring(wantHash)
    local nowTs = (time and time()) or 0
    if (nowTs - (self.requestCooldown[ckey] or 0)) < REQUEST_COOLDOWN then return end
    self.requestCooldown[ckey] = nowTs
    local src = self:ResolveRequestSource(owner, function(o) return self:IsGuildMemberOnline(o) end)
    if src == "owner" then
        sendAddon(("LREQ1|%d|%s|%s"):format(PROTOCOL_VERSION, sessionID, known), "WHISPER", owner)
    else
        -- offline owner: ask the guild for a cached copy at the OWNER's advertised hash.
        self.wantedHash = self.wantedHash or {}
        local wantHash = self.wantedHash[ckey] or known
        sendAddon(("LRELAYREQ1|%d|%s|%s"):format(PROTOCOL_VERSION, sessionID, wantHash), "GUILD", nil)
        -- Requester-side retry: if no stream materializes (all candidates evicted, or the
        -- claim/relay was lost), re-queue for the background ticker so it converges later.
        if C_Timer then
            C_Timer.After(RELAY_TIMEOUT, function()
                local store2 = Store()
                if store2:SessionHash(sessionID) ~= wantHash then
                    self:AddPendingStale(sessionID)
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
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
    self.sessionOwner = self.sessionOwner or {}
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
                sendAddon(("LREQMAN1|%d"):format(PROTOCOL_VERSION), "GUILD", nil)
            end
        end)
        self:StartBackgroundTicker()
    end
end

-- ===========================================================================
-- Handlers
-- ===========================================================================
Sync.incoming = {}
Sync.handlers = {}

-- BUG 1 FIX: LSTR1 handler keys self.incoming by incomingKey(sender, streamId).
-- The raw streamId is stored on the stream so LNAK1 replies echo the sender's own id.
Sync.handlers["LSTR1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId f[3]=sessionID f[4]=total f[5]=checksum
    local streamId = f[2]
    if not streamId or streamId == "" then return end
    local key = incomingKey(sender, streamId)
    self.incoming[key] = self.incoming[key] or { chunks = {}, received = 0 }
    local stream = self.incoming[key]
    stream.sender    = sender
    stream.streamId  = streamId  -- raw id for LNAK1 replies
    stream.sessionID = f[3]
    stream.total     = tonumber(f[4]) or 0
    stream.checksum  = f[5]
    self:ScheduleQuiet(key)
end

-- BUG 1 FIX: LDAT1 handler keys self.incoming by incomingKey(sender, streamId).
Sync.handlers["LDAT1"] = function(self, rest, sender)
    -- CRITICAL: the chunk PAYLOAD (last field) is raw serialized session data that itself
    -- contains '|' (the drop separator). It must NOT be split on '|' — parse the three
    -- leading fields and take the remainder verbatim. (Splitting truncated multi-drop
    -- payloads at the first embedded '|', corrupting every transfer of 2+ drops.)
    local version, streamId, idxStr, payload = rest:match("^(%d+)|([^|]*)|([^|]*)|(.*)$")
    local index = tonumber(idxStr)
    if not streamId or streamId == "" or not index then return end
    local key = incomingKey(sender, streamId)
    local stream = self.incoming[key]
    if not stream then  -- chunk arrived before LSTR1: buffer it
        stream = { chunks = {}, received = 0, sender = sender, streamId = streamId }
        self.incoming[key] = stream
    end
    if not stream.chunks[index] then
        stream.chunks[index] = payload or ""
        stream.received = stream.received + 1
    end
    self:ScheduleQuiet(key)
end

-- BUG 1 FIX: LEND1 handler receives sender and keys self.incoming by incomingKey(sender, streamId).
Sync.handlers["LEND1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId
    local streamId = f[2]
    if not streamId then return end
    local key = incomingKey(sender, streamId)
    if self.incoming[key] then self:EvaluateIncoming(key) end
end

Sync.handlers["LNAK1"] = function(self, rest, sender)
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
            sendAddon(("LDAT1|%d|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, idx, out.chunks[idx]), "WHISPER", out.target)
        end
    end
    sendAddon(("LEND1|%d|%s"):format(PROTOCOL_VERSION, streamId), "WHISPER", out.target)
end

-- Owner serves a requested session.
Sync.handlers["LREQ1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=sessionID f[3]=knownHash
    local sessionID, knownHash = f[2], f[3]
    if not sessionID or sessionID == "" then return end
    local store = Store()
    if not store:IsGuildSession(sessionID) then return end  -- we don't hold it as guild
    if knownHash == store:SessionHash(sessionID) then return end  -- requester already current
    self:EnqueueOutgoing(sender, sessionID, "owner")
end

-- Manifest: body is v|sid:hash,sid:hash,... (no key/name/realm/class/updatedAt).
Sync.handlers["LMAN1"] = function(self, rest, sender)
    -- Body is "sid:hash,sid:hash,..." (the LMAN1 op encodes the version; BroadcastManifest
    -- emits no separate version field, so parse the pairs directly from rest).
    local store = Store()
    local nowTs = (time and time()) or 0
    for entry in (rest or ""):gmatch("([^,]+)") do
        local sessionID, hash = entry:match("^([^:]+):(.+)$")
        if sessionID and hash then
            if store:IsSessionHidden(sessionID) then
                self.wantedHash = self.wantedHash or {}
                self.wantedHash[tostring(sessionID)] = nil
            else
            local mine = store:SessionHash(sessionID)
            if mine ~= hash then
                -- Create the local guild-session shell so ApplySessionPayload will later
                -- accept real guild data through the personal-isolation gate.
                store:EnsureSession(sessionID, { scope = "guild" })
                self.wantedHash = self.wantedHash or {}
                self.wantedHash[tostring(sessionID)] = hash
                -- The manifest sender is a holder/owner; track it so RequestSession knows whom to whisper.
                -- Prefer an already-known holder unless this sender is currently online, so a brief
                -- LMAN1 from an offline relayer can't redirect our request and strand it behind the
                -- per-session cooldown for a full cycle (matches the reference's prefer-existing pattern).
                self.sessionOwner = self.sessionOwner or {}
                if not self.sessionOwner[sessionID] or self:IsGuildMemberOnline(sender) then
                    self.sessionOwner[sessionID] = sender
                end
                -- Pull immediately whenever we will sync at all: panel open, in a manual-sync
                -- window, OR auto-share is on. A guild loot tracker must converge promptly
                -- without the user having to open a panel — gating the immediate request on
                -- panelOpen left peers in a permanent "you're stale / no you're stale" standoff.
                -- EnqueueRequest respects the 1-in rule (PumpRequests), so this is safe.
                if self.panelOpen or (self.manualSyncUntil and nowTs <= self.manualSyncUntil) or self:AutoShareEnabled() then
                    self:EnqueueRequest(sessionID)
                else
                    self:AddPendingStale(sessionID)
                end
            end
            end
        end
    end
end

Sync.handlers["LREQMAN1"] = function(self, rest, sender)
    -- A guildmate asks everyone to re-advertise. Respond only if our manifest is stale,
    -- and spread responses across a wide window so a login storm does not collapse into a
    -- simultaneous burst. Re-check staleness at fire time to avoid double-sending.
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

Sync.handlers["LRELAYREQ1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=sessionID f[3]=hash
    local sessionID, hash = f[2], f[3]
    if not sessionID or not hash then return end
    if not Store():HasCachedSession(sessionID, hash) then return end  -- not a candidate
    self.pendingRelay = self.pendingRelay or {}
    local rk = relayKey(sessionID, hash)
    local entry = self.pendingRelay[rk]
    if entry then
        -- another requester wants the same data; serve them too when we fire
        entry.requesters[sender] = true
        return
    end
    entry = { sessionID = sessionID, hash = hash,
              requesters = { [sender] = true }, cancelled = false }
    self.pendingRelay[rk] = entry
    local function fire()
        self.pendingRelay[rk] = nil
        if entry.cancelled then return end
        -- TOCTOU re-check: re-verify we still hold the copy (eviction can race the jitter
        -- timer); if it's gone, stand down WITHOUT claiming so another valid candidate can serve.
        if not Store():HasCachedSession(sessionID, hash) then return end
        sendAddon(("LRELAYCLAIM1|%d|%s|%s"):format(PROTOCOL_VERSION, sessionID, hash), "GUILD", nil)
        for requester in pairs(entry.requesters) do
            self:EnqueueOutgoing(requester, sessionID, "cache")
        end
    end
    if C_Timer then
        local delay = math.random() * RELAY_JITTER
        C_Timer.After(delay, fire)
    else
        fire()
    end
end

-- LRELAYCLAIM1 is trusted: any guild member can cancel pending relays for a (sessionID,hash)
-- tuple. A requester-side RELAY_TIMEOUT retry covers a claim that never results in a served stream.
Sync.handlers["LRELAYCLAIM1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=sessionID f[3]=hash
    local rk = relayKey(f[2], f[3])
    local entry = self.pendingRelay and self.pendingRelay[rk]
    if entry then entry.cancelled = true end  -- another relay is serving; cancel ours
end

Sync._sendAddon = sendAddon
Sync._split = split
Sync.PROTOCOL_VERSION = PROTOCOL_VERSION
Sync.COMM_PREFIX = COMM_PREFIX
