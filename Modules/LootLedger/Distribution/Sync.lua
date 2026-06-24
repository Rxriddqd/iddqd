local ADDON, ns = ...
local Sync = ns:NewModule("LootDistSync")
local PROTOCOL_VERSION = 1
-- Distinct prefix from the ledger's IDDQD_LOOT2: the loot-distribution comms are a
-- separate protocol with their own ops; an independent prefix means old/other clients
-- never registered it and we ignore theirs.
local COMM_PREFIX = "IDDQD_LDIST1"
local CHUNK_SIZE = 185
local CHUNK_DELAY = 0.2
-- A WoW addon message body caps at 255 bytes. An LDONE1 message is "LDONE1|<v>|<payload>"; if
-- the payload fits under this it's sent as ONE instant message (no STR/DAT/END handshake, no
-- inter-chunk delay) — which is what makes manually-added items appear near-instantly.
local ONE_MSG_MAX = 240

local function Store() return ns:GetModule("LootDistStore") end

local function Players() return ns.GetModule and ns:GetModule("Players") or nil end
local function shortName(value)
    local players = Players()
    if players and players.ShortName then return players:ShortName(value) end
    value = tostring(value or "")
    return value:match("^([^-]+)") or value
end

-- prio: "ALERT" (fast, for interactive single-item updates) | "NORMAL" | "BULK" (catch-up). We
-- use a quicker queue than the old BULK default so live adds aren't stuck behind bulk traffic.
local function sendAddon(msg, channel, target, prio)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, msg, channel, target, prio or "NORMAL") end
    if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        ChatThrottleLib:SendAddonMessage(prio or "NORMAL", COMM_PREFIX, msg, channel, target)
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

local function dbg(...)
    if ns.LOOT_DIST_TEST then ns:Print("|cffaa88ffldist|r " .. table.concat({ ... }, " ")) end
end

-- Router: drop anything not on protocol version 1. Ops carry PROTOCOL_VERSION as the
-- first body field (after the op name).
function Sync:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local op, rest = message:match("^([A-Z0-9]+)|?(.*)$")
    if not op then return end
    dbg("RECV op=", tostring(op), "from=", tostring(sender), "chan=", tostring(channel))
    if tonumber(rest:match("^(%d+)")) ~= PROTOCOL_VERSION then dbg("  dropped: version gate"); return end
    if self.handlers and self.handlers[op] then self.handlers[op](self, rest, sender, channel) else dbg("  no handler for", tostring(op)) end
end

-- Full sanitiser: strips the field/record delimiters AND newlines. Use for every field
-- EXCEPT the itemLink (which legitimately contains '|').
local function clean(v)
    return (tostring(v or ""):gsub("[~;,|\n\r]", " "))
end

-- itemLink-only sanitiser: strip ONLY the '~' field delimiter and newlines, preserving the
-- '|' hyperlink escapes (|cff...|Hitem:...|h[Name]|h|r) so the receiver can render the link.
-- The whole payload rides the chunk transport, whose LDDAT1 handler takes the chunk verbatim,
-- so embedded '|' survives reassembly.
local function cleanLink(v)
    return (tostring(v or ""):gsub("[~\n\r]", " "))
end

-- Response-subfield sanitiser: ':' separates subfields and ',' separates responses, so a
-- response subfield must not contain ~ | ; , or :.
local function cleanResp(v)
    return (tostring(v or ""):gsub("[~;,|:\n\r]", " "))
end

local function refreshPanel()
    local p = ns:GetModule("LootActivePanel")
    if p and p.Refresh then p:Refresh() end
end

local function refreshPopup()
    local p = ns:GetModule("LootDistPopup")
    if p and p.Refresh and p.frame and p.frame:IsShown() then p:Refresh() end
end

-- The group channel to broadcast Ask/Response on: RAID in a raid, else PARTY in a party,
-- else nil (solo). A 2-person group is a PARTY, not a RAID — hardcoding "RAID" silently
-- failed to deliver when testing with two characters in a party.
local function groupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0 then return "PARTY" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

-- ===========================================================================
-- Serialize / apply one entry (the round-trip — keep field order identical)
-- Field order (joined by '~'):
--   id ~ itemId ~ itemLink ~ itemName ~ quality ~ holder ~ source ~
--   awardWinner ~ awardedBy ~ awardedAt ~ traded ~ tradeWindowEndsAt ~ responsesBlock ~
--   awardWinnerClass
-- responsesBlock = each response joined by ',' as player:classFile:response:note:at
-- awardWinnerClass is field 14 (appended): the winner's class file for class-colouring;
-- older/empty payloads simply omit it (the panel falls back to the response class lookup).
-- ===========================================================================
function Sync:SerializeEntry(e)
    if not e then return "" end
    local resps = {}
    for _, r in pairs(e.responses or {}) do
        resps[#resps + 1] = table.concat({
            cleanResp(r.player), cleanResp(r.classFile), cleanResp(r.response),
            cleanResp(r.note), tostring(tonumber(r.at) or 0),
        }, ":")
    end
    table.sort(resps)  -- deterministic ordering so re-serializes are byte-stable
    local award = e.award
    -- Multi-award block (field 16): every award as winner:by:at:class, joined by ','. Field 15 is
    -- the quantity. Both are appended so older parsers (that read 14 fields) still work.
    local awardsList = {}
    for _, a in ipairs(e.awards or {}) do
        awardsList[#awardsList + 1] = table.concat({
            cleanResp(a.winner), cleanResp(a.awardedBy), tostring(tonumber(a.awardedAt) or 0),
            cleanResp(a.winnerClass),
        }, ":")
    end
    local fields = {
        clean(e.id),
        tostring(tonumber(e.itemId) or ""),
        cleanLink(e.itemLink),
        clean(e.itemName),
        tostring(tonumber(e.quality) or ""),
        clean(e.holder),
        clean(e.source),
        award and clean(award.winner) or "",
        award and clean(award.awardedBy) or "",
        award and tostring(tonumber(award.awardedAt) or "") or "",
        e.traded and "1" or "0",
        e.tradeWindowEndsAt ~= nil and tostring(tonumber(e.tradeWindowEndsAt) or "") or "",
        table.concat(resps, ","),
        award and clean(award.winnerClass) or "",
        tostring(tonumber(e.quantity) or 1),          -- field 15: quantity
        table.concat(awardsList, ","),                -- field 16: all awards
    }
    return table.concat(fields, "~")
end

function Sync:ApplyEntryPayload(payload)
    -- '~'-aware split that keeps empty fields and does NOT touch the responsesBlock's
    -- internal commas/colons (those are parsed afterwards).
    local f = {}
    for seg in (tostring(payload or "") .. "~"):gmatch("([^~]*)~") do f[#f + 1] = seg end
    local id = f[1]
    if not id or id == "" then return end
    local itemId            = tonumber(f[2])
    local itemLink          = (f[3] ~= "" and f[3]) or nil
    local itemName          = (f[4] ~= "" and f[4]) or nil
    local quality           = tonumber(f[5])
    local holder            = (f[6] ~= "" and f[6]) or nil
    local source            = (f[7] ~= "" and f[7]) or nil
    local awardWinner       = f[8] or ""
    local awardedBy         = (f[9] ~= "" and f[9]) or nil
    local awardedAt         = tonumber(f[10])
    local traded            = f[11]
    local tradeWindowEndsAt = tonumber(f[12])
    local responsesBlock    = f[13] or ""
    local awardWinnerClass  = (f[14] ~= "" and f[14]) or nil
    local quantity          = tonumber(f[15]) or 1
    local awardsBlock       = f[16] or ""

    local store = Store()
    if not store then return end
    -- A broadcast entry is the sender authoritatively (re-)adding an item. Clear any local
    -- tombstone for this id first, otherwise EnsureEntry's tombstone gate silently drops it —
    -- which is why a manually (re-)added item showed for some raiders but not others (the others
    -- still held a tombstone from a previous remove/clear). Deletes propagate via LDDEL1, so a
    -- real removal still converges; a fresh add legitimately overrides an old tombstone.
    if store.ClearTombstone then store:ClearTombstone(id) end
    store:EnsureEntry(id, {
        itemId = itemId, itemLink = itemLink, itemName = itemName, quality = quality,
        holder = holder, source = source, tradeWindowEndsAt = tradeWindowEndsAt,
    })
    -- Quantity is authoritative from the sender (set, not increment, so re-applies converge).
    if store.SetQuantity then store:SetQuantity(id, quantity) end
    -- Apply all awards. Prefer the multi-award block (field 16); fall back to the single award
    -- (fields 8-10,14) for older senders. SetAward is idempotent (rejects dupes / over-quantity).
    if awardsBlock ~= "" then
        for seg in awardsBlock:gmatch("([^,]+)") do
            local p = {}
            for x in (seg .. ":"):gmatch("([^:]*):") do p[#p + 1] = x end
            local winner, by, at, cls = p[1], p[2], p[3], p[4]
            if winner and winner ~= "" then
                store:SetAward(id, winner, (by ~= "" and by) or nil, tonumber(at), (cls ~= "" and cls) or nil)
            end
        end
    elseif awardWinner ~= "" then
        store:SetAward(id, awardWinner, awardedBy, awardedAt, awardWinnerClass)
    end
    store:SetTraded(id, traded == "1")
    for respSeg in responsesBlock:gmatch("([^,]+)") do
        local p = {}
        for x in (respSeg .. ":"):gmatch("([^:]*):") do p[#p + 1] = x end
        local player, classFile, response, note, at = p[1], p[2], p[3], p[4], p[5]
        if player and player ~= "" and response and response ~= "" then
            store:SetResponse(id, player, classFile, response, note, tonumber(at))
        end
    end
    refreshPanel()
    local popup = ns:GetModule("LootDistPopup")
    if popup and popup.OnEntryAdded then popup:OnEntryAdded(id) end
    return id
end

-- ===========================================================================
-- Chunked broadcast of an entry (STR/DAT/END, modelled on LootSync)
-- ===========================================================================
-- Send a serialized payload as a STR/DAT/END chunk stream on one channel.
function Sync:sendEntryStream(payload, channel)
    if not channel then return end
    local chunks = self:ChunkPayload(payload)
    local total = #chunks
    self.outSeq = (self.outSeq or 0) + 1
    local streamId = "d" .. tostring(self.outSeq)
    sendAddon(("LDSTR1|%d|%s|%d"):format(PROTOCOL_VERSION, streamId, total), channel, nil)
    for i = 1, total do
        local idx = i
        local function fire()
            sendAddon(("LDDAT1|%d|%s|%d|%s"):format(PROTOCOL_VERSION, streamId, idx, chunks[idx]), channel, nil)
        end
        if C_Timer then C_Timer.After(CHUNK_DELAY * i, fire) else fire() end
    end
    local function finish()
        sendAddon(("LDEND1|%d|%s"):format(PROTOCOL_VERSION, streamId), channel, nil)
    end
    if C_Timer then C_Timer.After(CHUNK_DELAY * (total + 1), finish) else finish() end
end

-- Broadcast one entry to the live group (RAID/PARTY) so every raid member's Store + Loot tab
-- converges — not just guildmates. Also mirror to GUILD so a guildie not yet grouped catches
-- up. The receiver merges idempotently, so the double-delivery is harmless.
--
-- FAST PATH: a single item's serialized payload almost always fits in one 255-byte message, so
-- send it as ONE instant LDONE1 (no STR/DAT/END, no 0.2s-per-chunk delay) on the quick queue.
-- Only oversized payloads (lots of responses) fall back to the chunk stream.
function Sync:BroadcastEntry(id)
    local store = Store(); if not store then return end
    local e = store:Entries()[id]; if not e then return end
    local payload = self:SerializeEntry(e)
    local group = groupChannel()
    if #payload <= ONE_MSG_MAX then
        local msg = ("LDONE1|%d|%s"):format(PROTOCOL_VERSION, payload)
        if group then sendAddon(msg, group, nil, "ALERT") end
        if IsInGuild and IsInGuild() then sendAddon(msg, "GUILD", nil, "ALERT") end
    else
        if group then self:sendEntryStream(payload, group) end
        if IsInGuild and IsInGuild() then self:sendEntryStream(payload, "GUILD") end
    end
end

-- LDDEL1: convergent delete. Carries id + deletedAt so the tombstone wins by timestamp and
-- can't be resurrected by an older create/update still in flight. Sent to group + guild.
function Sync:BroadcastRemove(id, at)
    if not id then return end
    at = tonumber(at) or ((time and time()) or 0)
    local msg = ("LDDEL1|%d|%s|%d"):format(PROTOCOL_VERSION, clean(id), at)
    local group = groupChannel()
    if group then sendAddon(msg, group, nil) end
    if IsInGuild and IsInGuild() then sendAddon(msg, "GUILD", nil) end
    dbg("BroadcastRemove", tostring(id), "at", tostring(at))
end

-- LDPERM1: broadcast the raid-leader's loot-distribution policy so the whole group enforces
-- the same rule. Only the raid leader should send this (callers gate on that).
function Sync:BroadcastPolicy(policy, guildRank)
    local channel = groupChannel()
    if not channel then return end
    sendAddon(("LDPERM1|%d|%s|%s"):format(PROTOCOL_VERSION, clean(policy), tostring(tonumber(guildRank) or "")), channel, nil)
    dbg("BroadcastPolicy", tostring(policy), tostring(guildRank))
end

-- Re-broadcast every live (un-deleted) entry — used when a new member joins so their Loot tab
-- populates with the current list. Debounced by the caller. Does NOT pop the raider window;
-- it only syncs entry DATA into the Store (the popup only opens on an explicit Ask).
function Sync:RebroadcastAll()
    local store = Store(); if not store then return end
    local n = 0
    for _, e in pairs(store:Entries()) do
        self:BroadcastEntry(e.id)
        n = n + 1
    end
    -- If we're the raid leader, also re-assert the distribution policy so late joiners adopt it.
    local detect = ns:GetModule("LootDistDetect")
    if detect and detect.IsRaidLeader and detect:IsRaidLeader() and detect.DistributePolicy then
        self:BroadcastPolicy(detect:DistributePolicy(), detect.DistributeGuildRank and detect:DistributeGuildRank())
    end
    dbg("RebroadcastAll:", tostring(n), "entr(ies)")
end

-- ===========================================================================
-- Other messages (single, unchunked)
-- ===========================================================================
-- LDASK1: officer asks the raid to respond. Body carries id:itemId:quality per item, joined
-- by ','. The itemLink is DELIBERATELY NOT sent — it contains ':' (|Hitem:12345:0:...) which
-- would collide with the ':' subfield separator. The receiver resolves the link/name/icon
-- from itemId via GetItemInfo, so nothing is lost.
function Sync:BroadcastAsk(ids)
    local store = Store(); if not store then return end
    local entries = store:Entries()
    local parts = {}
    for _, id in ipairs(ids or {}) do
        local e = entries[id]
        if e then
            -- Fields joined by '~' (NOT ':'): the lootListId itself contains ':' and '-'
            -- (e.g. "6560:cylo:557"), which a ':'-split would shred. clean() strips '~' and
            -- ',' from each field, so neither delimiter can appear inside a value.
            parts[#parts + 1] = table.concat({
                clean(e.id), tostring(tonumber(e.itemId) or ""),
                tostring(tonumber(e.quality) or ""),
            }, "~")
        end
    end
    if #parts == 0 then dbg("BroadcastAsk: 0 valid entries, nothing sent"); return end
    local channel = groupChannel()
    dbg("BroadcastAsk SEND", tostring(#parts), "item(s) to", tostring(channel))
    if not channel then return end

    -- Addon messages cap at 255 bytes. With many items (or long item-GUID ids) the joined
    -- body can exceed that and the whole send silently fails — which is why "Ask Raid" stopped
    -- reaching other clients once several items were in the list. Split the parts across as
    -- many LDASK1 messages as needed, keeping each under a safe budget. The receiver's handler
    -- accumulates items per message, so multiple messages just add incrementally.
    local PREFIX = ("LDASK1|%d|"):format(PROTOCOL_VERSION)
    local MAX_BODY = 240 - #PREFIX            -- leave headroom under the 255-byte limit
    local batch, batchLen, sent = {}, 0, 0
    local function flush()
        if #batch == 0 then return end
        sendAddon(PREFIX .. table.concat(batch, ","), channel, nil)
        sent = sent + 1
        batch, batchLen = {}, 0
    end
    for _, part in ipairs(parts) do
        local add = #part + (#batch > 0 and 1 or 0)   -- +1 for the joining comma
        if batchLen + add > MAX_BODY and #batch > 0 then flush() end
        batch[#batch + 1] = part
        batchLen = batchLen + #part + (#batch > 1 and 1 or 0)
    end
    flush()
    dbg("BroadcastAsk: sent in", tostring(sent), "message(s)")
end

-- LDRESP1: a raider's response to one item.
function Sync:BroadcastResponse(id, response, note)
    local me = UnitName and UnitName("player")
    -- Select the 2nd return explicitly: `local _, c = X and X()` truncates via `and` and
    -- leaves c nil, which stripped the class from every broadcast response.
    local classFile
    if UnitClass then local _, cf = UnitClass("player"); classFile = cf end
    if not id or not me or not response then return end
    local channel = groupChannel()
    if not channel then return end
    local at = (GetTime and GetTime()) or (time and time()) or 0
    sendAddon(("LDRESP1|%d|%s|%s|%s|%s|%s|%s"):format(
        PROTOCOL_VERSION, clean(id), clean(me), clean(classFile),
        clean(response), clean(note), tostring(at)), channel, nil)
end

function Sync:BroadcastClearResponse(id)
    local me = UnitName and UnitName("player")
    if not id or not me then return end
    local channel = groupChannel()
    if not channel then return end
    local at = (GetTime and GetTime()) or (time and time()) or 0
    sendAddon(("LDRESPDEL1|%d|%s|%s|%s"):format(
        PROTOCOL_VERSION, clean(id), clean(me), tostring(at)), channel, nil)
end

-- Reminder: a NORMAL whisper (not an addon message) nudging the winner to trade.
function Sync:Reminder(winner, itemLink, minutesLeft)
    if SendChatMessage and winner then
        pcall(SendChatMessage,
            ("[iddqd] Trade reminder: ~%dm left to trade %s."):format(tonumber(minutesLeft) or 0, itemLink or "your item"),
            "WHISPER", nil, winner)
    end
end

-- ===========================================================================
-- Incoming stream keys + lifecycle
-- ===========================================================================
-- Namespace incoming-stream keys by sender to prevent collision when two senders
-- independently choose the same streamId.
local function incomingKey(sender, streamId)
    return tostring(sender or "?") .. "\31" .. tostring(streamId or "")
end

Sync.incoming = {}
Sync.handlers = {}

function Sync:OnEnable()
    if self._enabled then return end
    self._enabled = true
    self.incoming = self.incoming or {}
    self.handlers = self.handlers or {}
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix(COMM_PREFIX)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    end
    -- Once per session, drop tombstones old enough that a stale re-create is no longer a risk.
    local store = Store()
    if store and store.PruneTombstones then store:PruneTombstones() end
    local events = ns:GetModule("Events")
    if events and events.On then
        events:On("CHAT_MSG_ADDON", function(prefix, message, channel, msgSender)
            self:OnAddonMessage(prefix, message, channel, msgSender)
        end, self)

        -- Roster changes: when the group GROWS (someone joined), an officer re-broadcasts the
        -- current list so the joiner's Loot tab populates. Debounced to coalesce the roster
        -- event storm (and so multiple joins in quick succession fire one rebroadcast).
        self._lastGroupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        events:On("GROUP_ROSTER_UPDATE", function() self:OnRosterUpdate() end, self)
    end
end

-- Fired on every roster change. Detects a net JOIN and (if we may distribute loot) schedules
-- a single debounced rebroadcast of the live list. A net LEAVE just updates the cached size;
-- the leaving client cleans its own window via the popup/panel's own roster handler.
function Sync:OnRosterUpdate()
    local size = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local grew = size > (self._lastGroupSize or 0)
    self._lastGroupSize = size
    if not grew then return end

    -- Only a distributor should answer joins (avoids every raider rebroadcasting). Resolve via
    -- Detect so the rule stays in one place.
    local detect = ns:GetModule("LootDistDetect")
    if not (detect and detect.CanDistributeLoot and detect:CanDistributeLoot()) then return end

    if self._rebroadcastPending then return end
    self._rebroadcastPending = true
    local function fire()
        self._rebroadcastPending = nil
        self:RebroadcastAll()
    end
    if C_Timer and C_Timer.After then C_Timer.After(2.0, fire) else fire() end
end

-- ===========================================================================
-- Handlers
-- ===========================================================================
-- LDSTR1|v|streamId|total : open an incoming chunked entry stream.
Sync.handlers["LDSTR1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId f[3]=total
    local streamId = f[2]
    if not streamId or streamId == "" then return end
    local key = incomingKey(sender, streamId)
    self.incoming[key] = { chunks = {}, total = tonumber(f[3]) or 0, sender = sender }
end

-- LDDAT1: one chunk. CRITICAL — the chunk PAYLOAD (last field) is raw serialized entry data
-- that itself contains '|' (the itemLink hyperlink escapes). It MUST NOT be split on '|':
-- parse the three leading fields and take the remainder VERBATIM via regex.
Sync.handlers["LDDAT1"] = function(self, rest, sender)
    local version, streamId, idxStr, payload = rest:match("^(%d+)|([^|]*)|([^|]*)|(.*)$")
    local index = tonumber(idxStr)
    if not streamId or streamId == "" or not index then return end
    local key = incomingKey(sender, streamId)
    local stream = self.incoming[key]
    if not stream then  -- chunk arrived before LDSTR1: buffer it
        stream = { chunks = {}, total = nil, sender = sender }
        self.incoming[key] = stream
    end
    if stream.chunks[index] == nil then
        stream.chunks[index] = payload or ""
    end
end

-- LDEND1: reassemble + apply, then clear. Only apply if all 1..total chunks present.
Sync.handlers["LDEND1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=streamId
    local streamId = f[2]
    if not streamId then return end
    local key = incomingKey(sender, streamId)
    local stream = self.incoming[key]
    if not stream then return end
    self.incoming[key] = nil
    -- Distinguish "LDSTR1 never arrived" (total == nil — can't reassemble) from a real
    -- "zero-chunk stream" (total == 0). Conflating them via `or 0` would silently discard a
    -- completed entry whose header packet was lost.
    local total = stream.total
    if total == nil then return end   -- header missing; nothing to reassemble
    if total == 0 then return end     -- intentional empty-payload stream
    local parts = {}
    for i = 1, total do
        if stream.chunks[i] == nil then return end  -- missing chunk: drop (v1 has no NAK)
        parts[i] = stream.chunks[i]
    end
    local payload = table.concat(parts)
    self:ApplyEntryPayload(payload)
end

-- LDDEL1|v|id|deletedAt : convergent delete. Tombstone the id (LWW by deletedAt) so it's
-- removed everywhere and stays removed even if an older create is still in flight.
Sync.handlers["LDDEL1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=id f[3]=deletedAt
    local id = f[2]
    if not id or id == "" then return end
    local store = Store(); if not store then return end
    store:RemoveEntry(id, tonumber(f[3]))
    refreshPanel()
    -- Also drop it from the raider popup's active set if it's showing there.
    local popup = ns:GetModule("LootDistPopup")
    if popup and popup.OnRemoved then popup:OnRemoved(id) end
end

-- LDONE1: a whole entry in one message (the fast path for single-item adds/updates). The
-- payload after "LDONE1|<v>|" is the same serialized entry the chunk stream reassembles, taken
-- VERBATIM (it contains '|' from the itemLink, so don't split on '|').
Sync.handlers["LDONE1"] = function(self, rest, sender)
    local payload = rest:match("^%d+|(.*)$")
    if not payload or payload == "" then return end
    self:ApplyEntryPayload(payload)
end

-- LDPERM1: adopt the raid-leader's distribution policy. Only act on it from
-- someone who is actually the raid leader, so a non-leader can't spoof the policy.
Sync.handlers["LDPERM1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=policy f[3]=guildRank
    local policy = f[2]
    if policy ~= "leader" and policy ~= "assist" and policy ~= "guild"
        and policy ~= "assist_and_guild" and policy ~= "assist_or_guild" then return end
    -- Trust the message only if the sender is the raid leader.
    local isLeader = false
    if GetNumGroupMembers and GetRaidRosterInfo and IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank == 2 then
                if shortName(name) == shortName(sender) then isLeader = true end
                break
            end
        end
    else
        isLeader = true   -- party/no-roster: accept (party leader can't be verified the same way)
    end
    if not isLeader then return end
    local detect = ns:GetModule("LootDistDetect")
    if detect and detect.SetDistributePolicy then detect:SetDistributePolicy(policy, tonumber(f[3])) end
    refreshPanel()
end

-- LDASK1: render the asked items into the raider popup.
Sync.handlers["LDASK1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=version f[2]=body(id:itemId:quality:link,...)
    local body = f[2] or ""
    local items = {}
    for seg in body:gmatch("([^,]+)") do
        -- Fields are '~'-delimited (the id itself contains ':' and '-', so we can't split on ':').
        local p = {}
        for x in (seg .. "~"):gmatch("([^~]*)~") do p[#p + 1] = x end
        local id = p[1]
        if id and id ~= "" then
            items[#items + 1] = { id = id, itemId = tonumber(p[2]), quality = tonumber(p[3]) }
        end
    end
    dbg("LDASK1 handler: parsed", tostring(#items), "item(s)")
    local popup = ns:GetModule("LootDistPopup")
    if popup and popup.OnAsk then popup:OnAsk(items) else dbg("  LootDistPopup missing!") end
end

-- LDRESP1|v|id|player|classFile|response|note|at : record a raider response.
-- note may contain spaces but NOT '|' (clean() stripped it at send), so split() is safe.
Sync.handlers["LDRESP1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=id f[3]=player f[4]=classFile f[5]=response f[6]=note f[7]=at
    local id = f[2]
    if not id or id == "" then return end
    local store = Store(); if not store then return end
    store:SetResponse(id, f[3], f[4], f[5], f[6], tonumber(f[7]))
    refreshPanel()
    refreshPopup()
end

-- LDRESPDEL1|v|id|player|at : remove a raider's response, LWW by timestamp.
Sync.handlers["LDRESPDEL1"] = function(self, rest, sender)
    local f = split(rest)  -- f[1]=v f[2]=id f[3]=player f[4]=at
    local id = f[2]
    if not id or id == "" then return end
    local store = Store(); if not store then return end
    if store.ClearResponse then store:ClearResponse(id, f[3], tonumber(f[4])) end
    refreshPanel()
    refreshPopup()
end

Sync._sendAddon = sendAddon
Sync._split = split
Sync.PROTOCOL_VERSION = PROTOCOL_VERSION
Sync.COMM_PREFIX = COMM_PREFIX
