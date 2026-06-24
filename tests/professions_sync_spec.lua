local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

-- Controllable C_Timer: store callbacks; tests fire them manually.
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
local function fireTimers() local t = timers; timers = {}; for _, e in ipairs(t) do e.fn() end end

-- Capture outgoing addon messages.
local sent = {}
C_ChatInfo = {
    SendAddonMessage = function(prefix, msg, channel, target) sent[#sent + 1] = { prefix=prefix, msg=msg, channel=channel, target=target } end,
    RegisterAddonMessagePrefix = function() return true end,
}

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 1000 end
function UnitName() return "Me" end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
UnitClass = function() return "Mage", "MAGE" end
ns.professionRecipeDB = { skillLines={[333]="Enchanting"}, bySpellId={[7421]={p=333}}, byEffectId={} }
ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Modules/Professions/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Sync.lua"))("iddqd", ns)
local Sync = ns:GetModule("ProfessionsSync")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

-- codec: chunk a payload then reassemble identically (0/1/many chunks)
for _, payload in ipairs({ "", "7421", string.rep("1234567890,", 60) }) do
    local chunks = Sync:ChunkPayload(payload)
    local rebuilt = table.concat(chunks)
    check(rebuilt == payload, "chunk/reassemble round-trips len " .. #payload)
    if #payload > 0 then check(#chunks >= 1, "non-empty payload yields >=1 chunk") end
    for _, c in ipairs(chunks) do check(#c <= 185, "no chunk exceeds CHUNK_SIZE") end
end

-- version gate: non-v7 messages are ignored by the router (clean break)
Sync:OnAddonMessage("IDDQD_PROF", "MAN5|whatever", "GUILD", "Someone-Realm")
check(Sync:ActiveIncomingCount() == 0, "malformed old message creates no incoming stream")
-- a well-formed-looking old message that embeds version 6 must STILL be dropped
Sync:OnAddonMessage("IDDQD_PROF", "STR6|6|s1|Enchanting|2|abc|225|300", "WHISPER", "Old-Realm")
check(Sync:ActiveIncomingCount() == 0, "v6 STR message is dropped (no stream opened)")
-- a wrong-prefix message is ignored entirely
Sync:OnAddonMessage("WRONG_PREFIX", "STR7|7|s1|Enchanting|2|abc|225|300", "WHISPER", "X-Realm")
check(Sync:ActiveIncomingCount() == 0, "wrong addon prefix is ignored")

-- helper to feed a v7 message
local function feed(op, body, sender) Sync:OnAddonMessage("IDDQD_PROF", op .. "|7|" .. body, "WHISPER", sender or "Owner-Realm") end

-- Known payload of two spell ids and the checksum the owner would compute.
local payload = "100,200"
local checksum = ns.ProfessionsStoreShortHash(payload .. "|225|300")
local function profOf(who) return ns:GetModule("ProfessionsStore"):Profile(who) end

-- Scenario A: in-order, no loss -> commits and stores
feed("STR7", "s1|Enchanting|2|" .. checksum .. "|225|300", "Alice-Realm")
feed("DAT7", "s1|1|100,", "Alice-Realm")
feed("DAT7", "s1|2|200", "Alice-Realm")
feed("END7", "s1", "Alice-Realm")
fireTimers()
check(profOf("Alice-Realm") and profOf("Alice-Realm").professions["Enchanting"] ~= nil, "A: profession stored after clean transfer")
check(profOf("Alice-Realm").professions["Enchanting"].hash == checksum, "A: stored hash equals advertised checksum")

-- Scenario B: reordered chunks -> still commits
feed("STR7", "s2|Enchanting|2|" .. checksum .. "|225|300", "Bob-Realm")
feed("DAT7", "s2|2|200", "Bob-Realm")
feed("DAT7", "s2|1|100,", "Bob-Realm")
feed("END7", "s2", "Bob-Realm")
fireTimers()
check(profOf("Bob-Realm").professions["Enchanting"] ~= nil, "B: reordered chunks commit")

-- Scenario C: dropped chunk -> receiver NAKs, then commits on resend
sent = {}
feed("STR7", "s3|Enchanting|2|" .. checksum .. "|225|300", "Cara-Realm")
feed("DAT7", "s3|1|100,", "Cara-Realm")
feed("END7", "s3", "Cara-Realm")
fireTimers()
local nakd = false; for _,m in ipairs(sent) do if m.msg:find("^NAK7|7|s3|") then nakd = true end end
check(nakd, "C: receiver NAKs the missing chunk")
feed("DAT7", "s3|2|200", "Cara-Realm")
fireTimers()
check(profOf("Cara-Realm").professions["Enchanting"] ~= nil, "C: commits after repair")

-- Scenario D: duplicate chunks -> ignored, single commit
feed("STR7", "s4|Enchanting|2|" .. checksum .. "|225|300", "Dan-Realm")
feed("DAT7", "s4|1|100,", "Dan-Realm")
feed("DAT7", "s4|1|100,", "Dan-Realm")
feed("DAT7", "s4|2|200", "Dan-Realm")
feed("END7", "s4", "Dan-Realm")
fireTimers()
check(profOf("Dan-Realm").professions["Enchanting"] ~= nil, "D: duplicates do not break commit")

-- Scenario E: checksum mismatch -> NOT stored
feed("STR7", "s5|Enchanting|2|BADHASH|225|300", "Eve-Realm")
feed("DAT7", "s5|1|100,", "Eve-Realm")
feed("DAT7", "s5|2|200", "Eve-Realm")
feed("END7", "s5", "Eve-Realm")
fireTimers()
local eve = profOf("Eve-Realm")
check(not (eve and eve.professions and eve.professions["Enchanting"]), "E: checksum mismatch is never stored")

-- Scenario F: permanent loss -> after MAX_NAK gives up, no leak, no infinite loop
feed("STR7", "s6|Enchanting|3|" .. checksum .. "|225|300", "Finn-Realm")
feed("DAT7", "s6|1|100,", "Finn-Realm")
feed("END7", "s6", "Finn-Realm")
for _ = 1, 12 do fireTimers() end
check(Sync:ActiveIncomingCount() == 0, "F: stalled stream abandoned (no leak, no infinite loop)")

-- Scenario G: chunk arrives BEFORE its STR7 -> buffered, reconciled, commits
feed("DAT7", "s7|1|100,", "Gwen-Realm")
feed("STR7", "s7|Enchanting|2|" .. checksum .. "|225|300", "Gwen-Realm")
feed("DAT7", "s7|2|200", "Gwen-Realm")
feed("END7", "s7", "Gwen-Realm")
fireTimers()
check(profOf("Gwen-Realm") and profOf("Gwen-Realm").professions["Enchanting"] ~= nil, "G: chunk-before-STR7 is buffered and commits")

-- Scenario H: two senders reuse the SAME streamId "o1" -> must be isolated (no cross-corruption)
local payloadH = "300,400"
local checksumH = ns.ProfessionsStoreShortHash(payloadH .. "|150|300")
feed("STR7", "o1|Enchanting|2|" .. checksum .. "|225|300", "Hank-Realm")     -- checksum is the "100,200|225|300" one
feed("DAT7", "o1|1|100,", "Hank-Realm")
feed("STR7", "o1|Tailoring|2|" .. checksumH .. "|150|300", "Ivy-Realm")       -- same streamId, different sender+profession
feed("DAT7", "o1|1|300,", "Ivy-Realm")
feed("DAT7", "o1|2|400", "Ivy-Realm")
feed("DAT7", "o1|2|200", "Hank-Realm")
feed("END7", "o1", "Hank-Realm")
feed("END7", "o1", "Ivy-Realm")
fireTimers()
check(profOf("Hank-Realm") and profOf("Hank-Realm").professions["Enchanting"] ~= nil, "H: Hank's Enchanting stored despite streamId collision")
check(profOf("Ivy-Realm") and profOf("Ivy-Realm").professions["Tailoring"] ~= nil, "H: Ivy's Tailoring stored despite streamId collision")

-- Scenario I: checksum mismatch is bounded (MAX_CHECKSUM_RETRIES) -> no infinite re-request
local reqCount = 0
local origRequest = Sync.RequestProfession
Sync.RequestProfession = function(self, owner, prof) if owner == "Jad-Realm" then reqCount = reqCount + 1 end end
for n = 1, 6 do
    feed("STR7", ("sJ%d|Enchanting|2|BADHASH|225|300"):format(n), "Jad-Realm")
    feed("DAT7", ("sJ%d|1|100,"):format(n), "Jad-Realm")
    feed("DAT7", ("sJ%d|2|200"):format(n), "Jad-Realm")
    feed("END7", ("sJ%d"):format(n), "Jad-Realm")
    fireTimers()
end
Sync.RequestProfession = origRequest
check(reqCount <= 2, "I: checksum-mismatch re-requests are bounded by MAX_CHECKSUM_RETRIES (got " .. reqCount .. ")")
check(not (profOf("Jad-Realm") and profOf("Jad-Realm").professions and profOf("Jad-Realm").professions["Enchanting"]), "I: bad-checksum data never stored")

-- Scenario J: empty (zero-chunk) profession (e.g. Fishing) commits via STR7+END7 with no DAT7, and does not leak
local fishChecksum = ns.ProfessionsStoreShortHash("" .. "|225|300")
feed("STR7", "sF|Fishing|0|" .. fishChecksum .. "|225|300", "Kim-Realm")
feed("END7", "sF", "Kim-Realm")
fireTimers()
check(profOf("Kim-Realm") and profOf("Kim-Realm").professions["Fishing"] ~= nil, "J: empty Fishing profession commits")
check(#profOf("Kim-Realm").professions["Fishing"].spellIds == 0, "J: Fishing stored with empty spellIds")

-- Scenario K: DAT7 arrives but STR7 never does -> stream is cleaned up after bounded waits (no leak)
feed("DAT7", "orphan1|1|999,", "Leo-Realm")
for _ = 1, 5 do fireTimers() end
check(Sync:ActiveIncomingCount() == 0, "K: orphaned pre-STR7 stream is cleaned up (no leak)")

-- ===== Task 6: sender state machine =====
-- Seed the local owner's Enchanting so we have something to send.
ns:GetModule("ProfessionsStore"):SetProfession("Me-Realm", "Enchanting", { skillLineId=333, spellIds={100,200}, rank=225, maxRank=300 }, "owner")
local ownerHash = ns:GetModule("ProfessionsStore"):Profile("Me-Realm").professions["Enchanting"].hash

-- REQ7 with a matching known hash -> nothing sent
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|" .. ownerHash, "WHISPER", "Asker-Realm")
for _ = 1, 20 do fireTimers() end
check(#sent == 0, "REQ7 with matching hash sends nothing")

-- REQ7 with a stale hash -> sends STR7 + DAT7 + END7, all whispered to requester
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|oldhash", "WHISPER", "Asker-Realm")
for _ = 1, 30 do fireTimers() end
local hasSTR, hasDAT, hasEND, allToAsker = false, false, false, true
for _, m in ipairs(sent) do
    if m.msg:find("^STR7|7|") then hasSTR = true end
    if m.msg:find("^DAT7|7|") then hasDAT = true end
    if m.msg:find("^END7|7|") then hasEND = true end
    if m.target ~= "Asker-Realm" then allToAsker = false end
end
check(hasSTR and hasDAT and hasEND, "REQ7 with stale hash streams STR7/DAT7/END7")
check(allToAsker, "all outgoing chunks are whispered to the requester")

-- The sent STR7 must advertise a checksum that the receiver would accept for this payload.
check(type(Sync:LastOutgoingStreamId()) == "string" and Sync:LastOutgoingStreamId() ~= "", "LastOutgoingStreamId returns the active outgoing id")

-- NAK7 -> resends only the named chunk index
-- Parse the streamId from the captured STR7 instead of relying on LastOutgoingStreamId.
local outId
for _, m in ipairs(sent) do local id = m.msg:match("^STR7|7|([^|]+)|"); if id then outId = id; break end end
check(type(outId) == "string" and outId ~= "", "outgoing streamId parsed from STR7")
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "NAK7|7|" .. outId .. "|1", "WHISPER", "Asker-Realm")
for _ = 1, 20 do fireTimers() end
local datIdxs = {}
for _, m in ipairs(sent) do local i = m.msg:match("^DAT7|7|[^|]+|(%d+)|") ; if i then datIdxs[#datIdxs+1] = i end end
check(#datIdxs >= 1, "NAK7 triggers at least one DAT7 resend")
local onlyChunk1 = true; for _, i in ipairs(datIdxs) do if i ~= "1" then onlyChunk1 = false end end
check(onlyChunk1, "NAK7 resends only the requested chunk index (chunk 1)")

-- End-to-end: a REQ7 followed by feeding the produced STR7/DAT7/END7 into a RECEIVER results in a stored profession.
-- (Reuse the same Sync as both sender and receiver; the payload {100,200} rank 225/300 round-trips.)
-- Since Task 5, the STR7 carries ownerKey=Me-Realm, so the receiver stores under the real owner key,
-- not under the relay sender "Echo-Realm".
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|oldhash2", "WHISPER", "Asker-Realm")
for _ = 1, 30 do fireTimers() end
-- Replay the captured STR7/DAT7/END7 as if they came from "Echo-Realm" into the receiver.
for _, m in ipairs(sent) do
    if m.msg:find("^STR7|7|") or m.msg:find("^DAT7|7|") or m.msg:find("^END7|7|") then
        Sync:OnAddonMessage("IDDQD_PROF", m.msg, "WHISPER", "Echo-Realm")
    end
end
fireTimers()
-- Task 5: data stored under the ownerKey embedded in STR7 (Me-Realm), not under the relay sender (Echo-Realm)
check(profOf("Me-Realm") and profOf("Me-Realm").professions["Enchanting"] ~= nil, "end-to-end: sender output is accepted by the receiver and stored")
check(#profOf("Me-Realm").professions["Enchanting"].spellIds == 2, "end-to-end: stored profession has the 2 spell ids")

-- Task 6 hardening: NAK7 from a NON-target sender is ignored (anti-spoof)
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|stale-x", "WHISPER", "Target-Realm")
for _ = 1, 30 do fireTimers() end
local sid
for _, m in ipairs(sent) do local id = m.msg:match("^STR7|7|([^|]+)|"); if id then sid = id; break end end
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "NAK7|7|" .. sid .. "|1", "WHISPER", "Imposter-Realm")  -- wrong sender
for _ = 1, 10 do fireTimers() end
local resentForImposter = false; for _, m in ipairs(sent) do if m.msg:find("^DAT7|7|") then resentForImposter = true end end
check(not resentForImposter, "NAK7 from non-target sender is ignored (no resend)")

-- legit target NAK still works
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "NAK7|7|" .. sid .. "|1", "WHISPER", "Target-Realm")
for _ = 1, 10 do fireTimers() end
local resentForTarget = false; for _, m in ipairs(sent) do if m.msg:find("^DAT7|7|") then resentForTarget = true end end
check(resentForTarget, "NAK7 from legit target triggers resend")

-- NAK7 flood is bounded by MAX_NAK (no infinite resend) — use a FRESH stream so nakCount starts at 0
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|stale-flood", "WHISPER", "Target-Realm")
for _ = 1, 30 do fireTimers() end
local sid2
for _, m in ipairs(sent) do local id = m.msg:match("^STR7|7|([^|]+)|"); if id then sid2 = id; break end end
sent = {}
for n = 1, 12 do Sync:OnAddonMessage("IDDQD_PROF", "NAK7|7|" .. sid2 .. "|1", "WHISPER", "Target-Realm") end
for _ = 1, 10 do fireTimers() end
local resendCount = 0; for _, m in ipairs(sent) do if m.msg:find("^DAT7|7|") then resendCount = resendCount + 1 end end
check(resendCount <= 5, "NAK7 resends are bounded by MAX_NAK (got " .. resendCount .. " resends across 12 NAKs)")

-- ===== Task 7: orchestration =====
-- BroadcastManifest sends one MAN7 to GUILD listing each profession:hash
sent = {}
Sync:BroadcastManifest()
local manMsg
for _, m in ipairs(sent) do if m.msg:find("^MAN7|7|") then manMsg = m end end
check(manMsg ~= nil and manMsg.channel == "GUILD", "BroadcastManifest sends MAN7 to GUILD")
-- our local profile has Enchanting from Task 6 seeding, so the manifest should mention it
check(manMsg.msg:find("Enchanting:", 1, true) ~= nil, "manifest includes profession:hash entries")

-- Incoming MAN7 for a profession we lack, panel OPEN -> acts immediately (REQ7 to owner if online, or RELAYREQ to guild if offline)
-- The test harness has no guild roster stub so IsGuildMemberOnline returns false -> RELAYREQ path exercised.
sent = {}
Sync:SetPanelOpen(true)
Sync.requestCooldown = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Zoe-Realm|Zoe|Realm|MAGE|123|Tailoring:remhash", "GUILD", "Zoe-Realm")
for _ = 1, 5 do fireTimers() end
local reqd = false
for _, m in ipairs(sent) do if (m.msg:find("^REQ7|7|Tailoring|") and m.target == "Zoe-Realm") or m.msg:find("^RELAYREQ|7|Zoe%-Realm|Tailoring|") then reqd = true end end
check(reqd, "MAN7 unknown profession + panel open -> acts immediately (REQ7 to owner or RELAYREQ to guild)")

-- Incoming MAN7, panel CLOSED -> does NOT request (lazy)
sent = {}
Sync:SetPanelOpen(false)
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Yan-Realm|Yan|Realm|MAGE|123|Mining:h2", "GUILD", "Yan-Realm")
for _ = 1, 5 do fireTimers() end
local reqd2 = false
for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Mining|") then reqd2 = true end end
check(not reqd2, "MAN7 panel closed -> no request (lazy)")

-- MAN7 advertising a profession+hash we ALREADY have -> no request even with panel open
sent = {}
Sync:SetPanelOpen(true)
-- seed a known cache entry for Quo-Realm Cooking with a specific hash
local qHash = ns:GetModule("ProfessionsStore"):SetProfession("Quo-Realm", "Cooking", { skillLineId=185, spellIds={500}, rank=1, maxRank=1 }, "cache").hash
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Quo-Realm|Quo|Realm|MAGE|123|Cooking:" .. qHash, "GUILD", "Quo-Realm")
for _ = 1, 5 do fireTimers() end
local reqd3 = false
for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Cooking|") then reqd3 = true end end
check(not reqd3, "MAN7 with already-known hash -> no request")
Sync:SetPanelOpen(false)

-- 1-IN rule: while an incoming stream is active, PumpRequests does not fire a new request
sent = {}
Sync:SetPanelOpen(true)
Sync.requestCooldown = {}   -- ensure New-Realm has no prior cooldown
-- open an incoming stream (no END7, so it stays active)
local cs = ns.ProfessionsStoreShortHash("100,200|1|1")
Sync:OnAddonMessage("IDDQD_PROF", "STR7|7|act1|Cooking|2|"..cs.."|1|1", "WHISPER", "Active-Realm")
-- now a MAN7 arrives wanting a different profession; it should QUEUE, not send REQ7/RELAYREQ yet
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|New-Realm|New|Realm|MAGE|9|Tailoring:zzz", "GUILD", "New-Realm")
for _ = 1, 3 do fireTimers() end
local reqWhileActive = false
for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Tailoring|") or m.msg:find("^RELAYREQ|7|New%-Realm|Tailoring|") then reqWhileActive = true end end
check(not reqWhileActive, "1-in: no new request while an incoming stream is active")
-- clean up the active stream so it doesn't pollute later assertions
for _ = 1, 12 do fireTimers() end  -- let it stall + abandon
Sync:SetPanelOpen(false)

-- ===== Task 7 hardening =====
-- Queue drains after the active stream is ABANDONED (MAX_NAK give-up), not just after success.
Sync.requestQueue = {}          -- clean slate
Sync.incoming = {}
Sync.requestCooldown = {}       -- clear so Queued-Realm has no prior cooldown
Sync:SetPanelOpen(true)
sent = {}
-- open an active incoming stream that will never complete (missing chunk 2)
local cs2 = ns.ProfessionsStoreShortHash("100,200|1|1")
Sync:OnAddonMessage("IDDQD_PROF", "STR7|7|stall1|Cooking|2|"..cs2.."|1|1", "WHISPER", "Staller-Realm")
Sync:OnAddonMessage("IDDQD_PROF", "DAT7|7|stall1|1|100,200", "WHISPER", "Staller-Realm")  -- only chunk 1; never completes
-- a MAN7 arrives wanting another profession -> queued (1-in blocks it now)
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Queued-Realm|Queued|Realm|MAGE|9|Tailoring:needit", "GUILD", "Queued-Realm")
-- confirm it did NOT fire yet (neither REQ7 nor RELAYREQ should be sent while 1-in is active)
local firedEarly = false; for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Tailoring|") or m.msg:find("^RELAYREQ|7|Queued%-Realm|Tailoring|") then firedEarly = true end end
check(not firedEarly, "hardening: queued request held while stream active")
-- now drive the stall to abandonment (NAK rounds then give-up) and confirm the queue drains
sent = {}
for _ = 1, 15 do fireTimers() end
-- Post-Task-7: no roster -> offline -> RELAYREQ; accept either form (owner-first-or-relay).
local drained = false; for _, m in ipairs(sent) do if (m.msg:find("^REQ7|7|Tailoring|") and m.target == "Queued-Realm") or m.msg:find("^RELAYREQ|7|Queued%-Realm|Tailoring|") then drained = true end end
check(drained, "hardening: queued request fires after the active stream is abandoned")
Sync:SetPanelOpen(false)

-- OnEnable is idempotent: calling twice doesn't double-register the CHAT_MSG_ADDON handler.
-- Provide a minimal Events stub that counts registrations.
local regCount = 0
ns.modules.Events = { On = function(self, ev, fn, owner) if ev == "CHAT_MSG_ADDON" then regCount = regCount + 1 end end }
Sync._enabled = nil  -- reset guard for the test
Sync:OnEnable()
Sync:OnEnable()
check(regCount == 1, "hardening: OnEnable registers CHAT_MSG_ADDON only once across two calls")

-- Spoofed MAN7 (advertised key != sender) is ignored.
sent = {}
Sync:SetPanelOpen(true)
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Victim-Realm|Victim|Realm|MAGE|9|Tailoring:xyz", "GUILD", "Attacker-Realm")
for _ = 1, 5 do fireTimers() end
local spoofReq = false; for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Tailoring|") then spoofReq = true end end
check(not spoofReq, "hardening: MAN7 whose key != sender is ignored (anti-spoof)")
Sync:SetPanelOpen(false)

-- ===== Integration: Sync notifies Panel on successful receive =====
local refreshCount = 0
ns.modules.ProfessionsPanel = { Refresh = function() refreshCount = refreshCount + 1 end }
local pl = "100,200"
local plChecksum = ns.ProfessionsStoreShortHash(pl .. "|225|300")
feed("STR7", "panelTest|Enchanting|2|" .. plChecksum .. "|225|300", "Nina-Realm")
feed("DAT7", "panelTest|1|100,", "Nina-Realm")
feed("DAT7", "panelTest|2|200", "Nina-Realm")
feed("END7", "panelTest", "Nina-Realm")
fireTimers()
check(profOf("Nina-Realm") and profOf("Nina-Realm").professions["Enchanting"] ~= nil, "integration: received profession stored")
check(refreshCount >= 1, "integration: Panel:Refresh called after successful receive")
-- empty (Fishing) receive also refreshes
local fc = ns.ProfessionsStoreShortHash("" .. "|225|300")
refreshCount = 0
feed("STR7", "panelFish|Fishing|0|" .. fc .. "|225|300", "Nina-Realm")
feed("END7", "panelFish", "Nina-Realm")
fireTimers()
check(refreshCount >= 1, "integration: Panel:Refresh called after empty-profession receive")

-- ===== Task 2: jitter + debounce + REQMAN =====
local d0 = Sync:LoginBroadcastDelay(function() return 0 end)
local d1 = Sync:LoginBroadcastDelay(function() return 1 end)
check(d0 >= 10 and d0 <= 11, "login delay at rng=0 is ~base (10)")
check(d1 >= 39 and d1 <= 41, "login delay at rng=1 is ~base+window (40)")
check(d1 > d0, "login delay scales with rng (spread, not constant)")

sent = {}
Sync.manualSyncUntil = nil
Sync:OnLocalChange("Enchanting")
Sync:OnLocalChange("Enchanting")
Sync:OnLocalChange("Alchemy")
local manBefore = 0; for _,m in ipairs(sent) do if m.msg:find("^MAN7|") then manBefore = manBefore + 1 end end
check(manBefore == 0, "OnLocalChange does not broadcast inline (debounced)")
fireTimers()
local manAfter = 0; for _,m in ipairs(sent) do if m.msg:find("^MAN7|") then manAfter = manAfter + 1 end end
check(manAfter == 1, "debounced change-burst yields exactly one MAN7")

sent = {}
Sync.lastManifestAt = 0   -- stale (age = time()=1000 > suppress window 30) -> respond
Sync:OnAddonMessage("IDDQD_PROF", "REQMAN|7", "GUILD", "Asker-Realm")
for _ = 1, 5 do fireTimers() end
local respondedMan = false; for _,m in ipairs(sent) do if m.msg:find("^MAN7|") then respondedMan = true end end
check(respondedMan, "REQMAN triggers a manifest re-broadcast when stale")

sent = {}
Sync.lastManifestAt = 1000   -- just broadcast (age 0 < 30) -> suppressed
Sync:OnAddonMessage("IDDQD_PROF", "REQMAN|7", "GUILD", "Asker-Realm")
for _ = 1, 5 do fireTimers() end
local respondedMan2 = false; for _,m in ipairs(sent) do if m.msg:find("^MAN7|") then respondedMan2 = true end end
check(not respondedMan2, "REQMAN suppressed when we broadcast recently")

-- REQMAN: two near-simultaneous REQMANs yield exactly ONE MAN7 response (re-check at fire time)
sent = {}
Sync.lastManifestAt = 0
Sync:OnAddonMessage("IDDQD_PROF", "REQMAN|7", "GUILD", "A-Realm")
Sync:OnAddonMessage("IDDQD_PROF", "REQMAN|7", "GUILD", "B-Realm")
for _ = 1, 12 do fireTimers() end
local manCount = 0; for _, m in ipairs(sent) do if m.msg:find("^MAN7|") then manCount = manCount + 1 end end
check(manCount == 1, "two near-simultaneous REQMANs yield exactly one MAN7 response")

-- ResolveRequestSource: owner online -> "owner"; offline -> "relay" (isOnline injected)
check(Sync:ResolveRequestSource("Nesi-Realm", function() return true end) == "owner", "owner online -> owner source")
check(Sync:ResolveRequestSource("Nesi-Realm", function() return false end) == "relay", "owner offline -> relay source")

-- ===== Task 4: cache relay =====
-- Seed a cached copy of an offline owner's Alchemy so WE are a relay candidate.
ns:GetModule("ProfessionsStore"):SetProfession("Off-Realm", "Alchemy", { skillLineId=171, spellIds={100,200}, rank=300, maxRank=300 }, "cache")
local offHash = ns:GetModule("ProfessionsStore"):Profile("Off-Realm").professions["Alchemy"].hash

-- RELAYREQ for data we hold -> we claim + serve (after jitter)
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off-Realm|Alchemy|%s"):format(offHash), "GUILD", "Needer-Realm")
for _ = 1, 10 do fireTimers() end
local claimed, servedSTR = false, false
for _, m in ipairs(sent) do
    if m.msg:find("^RELAYCLAIM|7|Off%-Realm|Alchemy|") then claimed = true end
    if m.msg:find("^STR7|7|") and m.target == "Needer-Realm" then servedSTR = true end
end
check(claimed, "relay candidate broadcasts a RELAYCLAIM")
check(servedSTR, "relay candidate serves the data via STR7 whisper to the requester")

-- another RELAYCLAIM arriving first -> we cancel (no claim, no serve)
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off-Realm|Alchemy|%s"):format(offHash), "GUILD", "Needer2-Realm")
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYCLAIM|7|Off-Realm|Alchemy|%s"):format(offHash), "GUILD", "OtherRelay-Realm")
for _ = 1, 10 do fireTimers() end
local weClaimed, weServed = false, false
for _, m in ipairs(sent) do
    if m.msg:find("^RELAYCLAIM|") then weClaimed = true end
    if m.msg:find("^STR7|7|") and m.target == "Needer2-Realm" then weServed = true end
end
check(not weClaimed and not weServed, "we cancel our serve when another relay claims first")

-- RELAYREQ for data we don't have / wrong hash -> no claim
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "RELAYREQ|7|Off-Realm|Alchemy|wronghash", "GUILD", "Needer3-Realm")
for _ = 1, 10 do fireTimers() end
local respondedWrong = false; for _, m in ipairs(sent) do if m.msg:find("^RELAYCLAIM|") then respondedWrong = true end end
check(not respondedWrong, "no claim when our cached hash doesn't match the request")

-- The served STR7 includes ownerKey + source fields (so receiver stores under owner as cache)
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off-Realm|Alchemy|%s"):format(offHash), "GUILD", "Needer4-Realm")
for _ = 1, 10 do fireTimers() end
local hdr
for _, m in ipairs(sent) do if m.msg:find("^STR7|7|") and m.target == "Needer4-Realm" then hdr = m.msg end end
check(hdr ~= nil, "served STR7 present")
check(hdr and hdr:find("|Off-Realm|cache", 1, true) ~= nil, "served STR7 header carries ownerKey + cache source")

-- Relay: TWO requesters for the same data both get served, with ONE claim
ns:GetModule("ProfessionsStore"):SetProfession("Off2-Realm", "Tailoring", { skillLineId=197, spellIds={11,22}, rank=300, maxRank=300 }, "cache")
local off2Hash = ns:GetModule("ProfessionsStore"):Profile("Off2-Realm").professions["Tailoring"].hash
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off2-Realm|Tailoring|%s"):format(off2Hash), "GUILD", "ReqA-Realm")
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off2-Realm|Tailoring|%s"):format(off2Hash), "GUILD", "ReqB-Realm")
for _ = 1, 12 do fireTimers() end
local claims, servedA, servedB = 0, false, false
for _, m in ipairs(sent) do
    if m.msg:find("^RELAYCLAIM|") then claims = claims + 1 end
    if m.msg:find("^STR7|7|") and m.target == "ReqA-Realm" then servedA = true end
    if m.msg:find("^STR7|7|") and m.target == "ReqB-Realm" then servedB = true end
end
check(claims == 1, "two requesters -> exactly one RELAYCLAIM")
check(servedA and servedB, "both requesters served")

-- Relay: if our cached copy is evicted before the timer fires, we do NOT claim (TOCTOU)
ns:GetModule("ProfessionsStore"):SetProfession("Off3-Realm", "Cooking", { skillLineId=185, spellIds={5}, rank=1, maxRank=1 }, "cache")
local off3Hash = ns:GetModule("ProfessionsStore"):Profile("Off3-Realm").professions["Cooking"].hash
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", ("RELAYREQ|7|Off3-Realm|Cooking|%s"):format(off3Hash), "GUILD", "ReqC-Realm")
-- evict before firing: wipe the cached profile via the live profiles table
ns:GetModule("ProfessionsStore"):Profiles()["Off3-Realm"] = nil
for _ = 1, 12 do fireTimers() end
local claimedAfterEvict = false; for _, m in ipairs(sent) do if m.msg:find("^RELAYCLAIM|") then claimedAfterEvict = true end end
check(not claimedAfterEvict, "TOCTOU: evicted copy -> no claim, no false suppression")

-- ===== Task 5: receiver honors STR7 ownerKey/source =====
local function profOf5(who) return ns:GetModule("ProfessionsStore"):Profile(who) end
-- Relayed STR7 (9-field, source=cache, ownerKey=Victim) stores under OWNER as cache
local relayPayload = "100,200"
local relayChecksum = ns.ProfessionsStoreShortHash(relayPayload .. "|300|300")
feed("STR7", ("rs1|Alchemy|2|%s|300|300|Victim-Realm|cache"):format(relayChecksum), "Relayer-Realm")
feed("DAT7", "rs1|1|100,", "Relayer-Realm")
feed("DAT7", "rs1|2|200", "Relayer-Realm")
feed("END7", "rs1", "Relayer-Realm")
fireTimers()
check(profOf5("Victim-Realm") and profOf5("Victim-Realm").professions["Alchemy"] ~= nil, "relayed data stored under OWNER key (Victim), not relay sender")
check(profOf5("Victim-Realm").professions["Alchemy"].source == "cache", "relayed data stored as cache source")
check(profOf5("Relayer-Realm") == nil or not (profOf5("Relayer-Realm").professions and profOf5("Relayer-Realm").professions["Alchemy"]), "relayed data NOT stored under the relay sender")

-- Owner-direct STR7 (legacy 7-field, no ownerKey/source) stores under sender as owner
local ownerPayload = "300,400"
local ownerChecksum = ns.ProfessionsStoreShortHash(ownerPayload .. "|225|300")
feed("STR7", ("os1|Tailoring|2|%s|225|300"):format(ownerChecksum), "Self5-Realm")
feed("DAT7", "os1|1|300,", "Self5-Realm")
feed("DAT7", "os1|2|400", "Self5-Realm")
feed("END7", "os1", "Self5-Realm")
fireTimers()
check(profOf5("Self5-Realm").professions["Tailoring"] ~= nil, "owner-direct (7-field) stores under sender")
check(profOf5("Self5-Realm").professions["Tailoring"].source == "owner", "owner-direct stored as owner source")

-- owner-direct write upgrades a prior relayed cache copy to owner source
feed("STR7", ("os2|Alchemy|2|%s|300|300|Victim-Realm|owner"):format(relayChecksum), "Victim-Realm")
feed("DAT7", "os2|1|100,", "Victim-Realm")
feed("DAT7", "os2|2|200", "Victim-Realm")
feed("END7", "os2", "Victim-Realm")
fireTimers()
check(profOf5("Victim-Realm").professions["Alchemy"].source == "owner", "owner-direct write upgrades cache copy to owner source")

-- ===== Task 6B: 1-out outgoing queue =====
ns:GetModule("ProfessionsStore"):SetProfession("Me-Realm", "Enchanting", { skillLineId=333, spellIds={100,200}, rank=225, maxRank=300 }, "owner")
ns:GetModule("ProfessionsStore"):SetProfession("Me-Realm", "Tailoring",  { skillLineId=197, spellIds={300,400}, rank=225, maxRank=300 }, "owner")
Sync.outgoing = {}
Sync.outQueue = {}
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Enchanting|stale", "WHISPER", "QA-Realm")
Sync:OnAddonMessage("IDDQD_PROF", "REQ7|7|Tailoring|stale",  "WHISPER", "QB-Realm")
-- before firing timers: only ONE STR7 started (one active outgoing)
local strNow = 0; for _, m in ipairs(sent) do if m.msg:find("^STR7|7|") then strNow = strNow + 1 end end
check(strNow == 1, "1-out: only one outgoing stream starts immediately")
-- drain: fire timers; the first stream's END7 fires PumpOutgoing -> second stream starts
for _ = 1, 40 do fireTimers() end
local strTotal = 0; for _, m in ipairs(sent) do if m.msg:find("^STR7|7|") then strTotal = strTotal + 1 end end
check(strTotal == 2, "1-out: queued second outgoing stream runs after the first completes")

-- ===== Task 7: background top-up + gating =====
ns.modules.DB.db.professions = ns.modules.DB.db.professions or {}
ns.modules.DB.db.professions.settings = { autoGuildSync = true }
check(Sync:AutoShareEnabled() == true, "AutoShareEnabled true when setting on")
ns.modules.DB.db.professions.settings.autoGuildSync = false
check(Sync:AutoShareEnabled() == false, "AutoShareEnabled false when setting off")
ns.modules.DB.db.professions.settings.autoGuildSync = true

-- ShouldPauseSync (pure, predicates injected)
check(Sync:ShouldPauseSync(function() return true end, function() return false end) == true, "pause when in combat")
check(Sync:ShouldPauseSync(function() return false end, function() return true end) == true, "pause when in instance")
check(Sync:ShouldPauseSync(function() return false end, function() return false end) == false, "no pause when idle")

-- DrainBackgroundOnce pulls at most one item from pendingStale
Sync.pendingStale = { { owner="X-Realm", profession="Alchemy" }, { owner="Y-Realm", profession="Tailoring" } }
Sync.pendingStaleSet = { ["X-Realm\31Alchemy"] = true, ["Y-Realm\31Tailoring"] = true }
Sync.requestQueue = {}; Sync.incoming = {}; Sync.requestCooldown = {}
local pulled = Sync:DrainBackgroundOnce()
check(pulled == 1, "DrainBackgroundOnce pulls at most one")
check(#Sync.pendingStale == 1, "one item removed per drain")

-- MAN7 with panel CLOSED records pending-stale (does NOT request immediately)
-- Stop background ticker so it doesn't drain pendingStale during fireTimers() calls.
Sync._bgTicking = false
Sync.panelOpen = false; Sync.manualSyncUntil = nil
Sync.pendingStale = {}; Sync.pendingStaleSet = {}; Sync.requestQueue = {}; Sync.requestCooldown = {}; Sync.wantedHash = {}
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Bg-Realm|Bg|Realm|MAGE|9|Tailoring:bghash", "GUILD", "Bg-Realm")
for _ = 1, 3 do fireTimers() end
local reqNow = false; for _, m in ipairs(sent) do if m.msg:find("^REQ7|7|Tailoring|") then reqNow = true end end
check(not reqNow, "panel closed: MAN7 does not request immediately")
local staleHas = false; for _, e in ipairs(Sync.pendingStale or {}) do if e.owner == "Bg-Realm" and e.profession == "Tailoring" then staleHas = true end end
check(staleHas, "panel closed: MAN7 records a pending-stale entry")

-- MAN7 panel OPEN still requests immediately (unchanged behavior)
Sync.panelOpen = true
Sync.requestQueue = {}; Sync.incoming = {}; Sync.requestCooldown = {}
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Op-Realm|Op|Realm|MAGE|9|Mining:ophash", "GUILD", "Op-Realm")
for _ = 1, 5 do fireTimers() end
-- Op-Realm is not in guild roster stub -> RequestProfession resolves to relay -> RELAYREQ (not REQ7).
local actedOp = false
for _, m in ipairs(sent) do if (m.msg:find("^REQ7|7|Mining|") or m.msg:find("^RELAYREQ|7|Op%-Realm|Mining|")) then actedOp = true end end
check(actedOp, "panel open: MAN7 acts immediately (REQ7 or RELAYREQ)")
Sync.panelOpen = false

-- RequestProfession: owner OFFLINE (not in roster) -> broadcasts RELAYREQ on GUILD
Sync.requestCooldown = {}; Sync.wantedHash = { ["Gone-Realm\31Alchemy"] = "wanthash" }
sent = {}
Sync:RequestProfession("Gone-Realm", "Alchemy")
local relayReq = false; for _, m in ipairs(sent) do if m.msg:find("^RELAYREQ|7|Gone%-Realm|Alchemy|wanthash") then relayReq = true end end
check(relayReq, "RequestProfession: offline owner -> RELAYREQ with wanted hash, on GUILD")

-- per-(owner,prof) cooldown: a second immediate request is suppressed
sent = {}
Sync:RequestProfession("Gone-Realm", "Alchemy")
local relayReq2 = false; for _, m in ipairs(sent) do if m.msg:find("^RELAYREQ|") then relayReq2 = true end end
check(not relayReq2, "RequestProfession cooldown suppresses immediate re-request")

-- AutoShare OFF + panel closed: MAN7 records NOTHING (no pending-stale, no request)
-- Flush any pending timers (e.g. RELAY_TIMEOUT callbacks from prior RequestProfession calls)
-- so they don't fire into the reset state and produce spurious pendingStale entries.
timers = {}
Sync._bgTicking = false
ns.modules.DB.db.professions.settings.autoGuildSync = false
Sync.panelOpen = false; Sync.manualSyncUntil = nil
Sync.pendingStale = {}; Sync.pendingStaleSet = {}; Sync.requestQueue = {}; Sync.requestCooldown = {}
sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|NoShare-Realm|NoShare|Realm|MAGE|9|Alchemy:nshash", "GUILD", "NoShare-Realm")
for _ = 1, 3 do fireTimers() end
check(#Sync.pendingStale == 0, "auto-share OFF + panel closed: MAN7 records no pending-stale")
local actedNo = false; for _, m in ipairs(sent) do if m.msg:find("^REQ7|") or m.msg:find("^RELAYREQ|") then actedNo = true end end
check(not actedNo, "auto-share OFF + panel closed: MAN7 sends no request")
ns.modules.DB.db.professions.settings.autoGuildSync = true   -- restore

-- pendingStale cap: never grows beyond MAX (500)
Sync._bgTicking = false
ns.modules.DB.db.professions.settings.autoGuildSync = true
Sync.panelOpen = false; Sync.manualSyncUntil = nil
Sync.pendingStale = {}; Sync.pendingStaleSet = {}
for i = 1, 600 do
    Sync:OnAddonMessage("IDDQD_PROF", ("MAN7|7|Cap%d-Realm|Cap|Realm|MAGE|9|Alchemy:h%d"):format(i, i), "GUILD", ("Cap%d-Realm"):format(i))
end
check(#Sync.pendingStale <= 500, "pendingStale is capped at MAX_PENDING_STALE (got " .. #Sync.pendingStale .. ")")

-- C1: panel close migrates queued requests to pendingStale (not dropped)
Sync._bgTicking = false
Sync.panelOpen = true
Sync.requestQueue = { { owner = "MigA-Realm", profession = "Alchemy" }, { owner = "MigB-Realm", profession = "Tailoring" } }
Sync.pendingStale = {}; Sync.pendingStaleSet = {}
Sync:SetPanelOpen(false)
local migA, migB = false, false
for _, e in ipairs(Sync.pendingStale) do
    if e.owner == "MigA-Realm" then migA = true end
    if e.owner == "MigB-Realm" then migB = true end
end
check(migA and migB, "C1: panel-close migrates queued requests to pendingStale")

-- I1: a RELAYREQ that yields no stream re-queues to pendingStale after RELAY_TIMEOUT
Sync._bgTicking = false
Sync.panelOpen = false
Sync.requestCooldown = {}; Sync.wantedHash = { ["Lost-Realm\31Mining"] = "losthash" }
Sync.pendingStale = {}; Sync.pendingStaleSet = {}
sent = {}
Sync:RequestProfession("Lost-Realm", "Mining")   -- offline (no roster) -> RELAYREQ
-- no stream arrives; fire the RELAY_TIMEOUT timer
for _ = 1, 30 do fireTimers() end
local reQueued = false; for _, e in ipairs(Sync.pendingStale) do if e.owner == "Lost-Realm" and e.profession == "Mining" then reQueued = true end end
check(reQueued, "I1: unfulfilled RELAYREQ re-queues to pendingStale for retry")

-- M1: AddPendingStale dedups O(1) (no duplicate entries)
Sync.pendingStale = {}; Sync.pendingStaleSet = {}
Sync:AddPendingStale("Dup-Realm", "Alchemy")
Sync:AddPendingStale("Dup-Realm", "Alchemy")
check(#Sync.pendingStale == 1, "M1: AddPendingStale dedups duplicate owner+profession")

print(("professions_sync_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
