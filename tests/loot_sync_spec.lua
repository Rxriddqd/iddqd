local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers+1] = { d=d, fn=fn } end }
local function fireTimers() local t = timers; timers = {}; for _,e in ipairs(t) do e.fn() end end
local sent = {}
C_ChatInfo = { SendAddonMessage = function(p,m,c,t) sent[#sent+1] = {prefix=p,msg=m,channel=c,target=t} end, RegisterAddonMessagePrefix = function() return true end }
local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 1000 end
ns.modules.DB = { db = {} }
assert(loadfile(DIR .. "Modules/LootLedger/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Sync.lua"))("iddqd", ns)
local Sync = ns:GetModule("LootSync")
local Store = ns:GetModule("LootStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

-- codec round-trip
for _, payload in ipairs({ "", "x", string.rep("ab,", 80) }) do
    local chunks = Sync:ChunkPayload(payload)
    check(table.concat(chunks) == payload, "chunk/reassemble len " .. #payload)
    for _, c in ipairs(chunks) do check(#c <= 185, "chunk <= 185") end
end

-- version gate: a non-v1 message is dropped (no crash, no handler)
Sync.handlers["TESTOP"] = function() error("should not be called for wrong version") end
Sync:OnAddonMessage("IDDQD_LOOT2", "TESTOP|5|whatever", "GUILD", "Someone-Realm")
check(true, "v5 message dropped (handler not called)")
-- a v1 message DOES reach its handler
local reached = false
Sync.handlers["TESTOP"] = function(self, rest, sender) reached = true end
Sync:OnAddonMessage("IDDQD_LOOT2", "TESTOP|1|payload", "GUILD", "Someone-Realm")
check(reached, "v1 message reaches its handler")
-- wrong prefix ignored
reached = false
Sync:OnAddonMessage("WRONG", "TESTOP|1|x", "GUILD", "Someone-Realm")
check(not reached, "wrong prefix ignored")

-- BroadcastManifest sends LMAN1 to GUILD listing only guild sessions
Store:Sessions()["GS1"] = nil; Store:Sessions()["PS1"] = nil; Store:Drops()["GD1"] = nil
Store:EnsureSession("GS1", { scope = "guild", instance = "Serpentshrine Cavern", instanceType = "raid", instanceId = 548, difficultyId = 14, startedAt = 777 })
Store:EnsureSession("PS1", { scope = "personal" })
Store:EnsureDrop("GD1", { sessionID = "GS1", itemId = 100 }); Store:AddEvent("GD1", { type="looted", actor="A-Realm", at=10 })
sent = {}
Sync:BroadcastManifest()
local man; for _, m in ipairs(sent) do if m.msg:find("^LMAN1|") then man = m end end
check(man ~= nil and man.channel == "GUILD", "BroadcastManifest sends LMAN1 to GUILD")
check(man.msg:find("GS1:", 1, true) ~= nil, "manifest includes guild session GS1")
check(man.msg:find("PS1:", 1, true) == nil, "manifest excludes personal session PS1")

-- Receiving a serialized drop+event for a GUILD session merges via event-union (idempotent)
local serialized = Sync:SerializeSessionDrops("GS1")
check(type(serialized) == "string" and #serialized > 0, "SerializeSessionDrops returns a payload")
Store:Drops()["GD1"] = nil
Sync:ApplySessionPayload("GS1", serialized)
check(Store:Drops()["GD1"] ~= nil, "ApplySessionPayload recreates the drop")
check(Store:Sessions()["GS1"].startedAt == 777 and Store:Sessions()["GS1"].instance == "Serpentshrine Cavern", "ApplySessionPayload preserves original session metadata")
local before = 0; for _ in pairs(Store:Drops()["GD1"].events) do before = before + 1 end
Sync:ApplySessionPayload("GS1", serialized)
local after = 0; for _ in pairs(Store:Drops()["GD1"].events) do after = after + 1 end
check(before == after, "re-applying the same payload is idempotent (no duplicate events)")

-- personal isolation: ApplySessionPayload for a session we consider personal is rejected
Store:Sessions()["PS2"] = { sessionID="PS2", scope="personal" }
Sync:ApplySessionPayload("PS2", serialized)
local hasPS2 = false; for _, d in pairs(Store:Drops()) do if d.sessionID == "PS2" then hasPS2 = true end end
check(not hasPS2, "personal session payload is rejected (no drops stored under personal session)")

-- end-to-end: peer advertises a guild session we lack -> we request it
Store:Sessions()["ES1"] = nil
for k, d in pairs(Store:Drops()) do if d.sessionID == "ES1" then Store:Drops()[k] = nil end end
Store:EnsureSession("ES1", { scope = "guild" })
Store:EnsureDrop("ED1", { sessionID = "ES1", itemId = 200, itemName = "Sword" })
Store:AddEvent("ED1", { type="looted", actor="A-Realm", at=10 })
Sync:OnInit()
Sync.panelOpen = true
sent = {}
Sync:OnAddonMessage("IDDQD_LOOT2", "LMAN1|ES1:bogushash", "GUILD", "Peer-Realm")
for _ = 1, 12 do fireTimers() end
local requested = false
for _, m in ipairs(sent) do if m.msg:find("^LREQ1|") or m.msg:find("^LRELAYREQ1|") then requested = true end end
check(requested, "manifest mismatch -> we request the session (owner or relay)")

-- A locally hidden/purged session must not be re-created just because another guildmate
-- advertises it in their manifest.
Store:HideSession("HIDE1", true)
sent = {}
Sync:OnAddonMessage("IDDQD_LOOT2", "LMAN1|HIDE1:remotehash", "GUILD", "Peer-Realm")
for _ = 1, 5 do fireTimers() end
check(Store:Sessions()["HIDE1"] == nil, "hidden session manifest does not recreate local session shell")
local requestedHidden = false
for _, m in ipairs(sent) do if m.msg:find("HIDE1", 1, true) then requestedHidden = true end end
check(requestedHidden == false, "hidden session manifest does not request the session")

-- empty manifest body does not crash
sent = {}
Sync:OnAddonMessage("IDDQD_LOOT2", "LMAN1|", "GUILD", "Peer-Realm")
check(true, "empty manifest handled")

-- replay transfer: serialize ES1, feed LSTR1/LDAT1/LEND1 back as if from a peer for a guild
-- session we hold -> drops applied; re-feed -> idempotent.
local payload = Sync:SerializeSessionDrops("ES1")
local chk = ns.LootStoreShortHash(payload)
local chunks = Sync:ChunkPayload(payload)
Store:Drops()["ED1"] = nil   -- wipe local copy; ES1 still a guild session locally
Sync.incoming = {}
Sync:OnAddonMessage("IDDQD_LOOT2", ("LSTR1|1|peerstream|ES1|%d|%s"):format(#chunks, chk), "WHISPER", "Peer-Realm")
for i, c in ipairs(chunks) do Sync:OnAddonMessage("IDDQD_LOOT2", ("LDAT1|1|peerstream|%d|%s"):format(i, c), "WHISPER", "Peer-Realm") end
Sync:OnAddonMessage("IDDQD_LOOT2", "LEND1|1|peerstream", "WHISPER", "Peer-Realm")
for _ = 1, 5 do fireTimers() end
check(Store:Drops()["ED1"] ~= nil, "transfer applied -> drop recreated")
local n1 = 0; for _ in pairs(Store:Drops()["ED1"].events) do n1 = n1 + 1 end
-- re-feed identical transfer
Sync.incoming = {}
Sync:OnAddonMessage("IDDQD_LOOT2", ("LSTR1|1|peerstream2|ES1|%d|%s"):format(#chunks, chk), "WHISPER", "Peer-Realm")
for i, c in ipairs(chunks) do Sync:OnAddonMessage("IDDQD_LOOT2", ("LDAT1|1|peerstream2|%d|%s"):format(i, c), "WHISPER", "Peer-Realm") end
Sync:OnAddonMessage("IDDQD_LOOT2", "LEND1|1|peerstream2", "WHISPER", "Peer-Realm")
for _ = 1, 5 do fireTimers() end
local n2 = 0; for _ in pairs(Store:Drops()["ED1"].events) do n2 = n2 + 1 end
check(n1 == n2, "re-applying transfer is idempotent (no duplicate events)")

-- personal isolation on transfer: a transfer for a session we DON'T hold as guild is rejected
Store:Sessions()["PX1"] = nil   -- unknown/not guild
Sync.incoming = {}
Sync:OnAddonMessage("IDDQD_LOOT2", ("LSTR1|1|pstream|PX1|%d|%s"):format(#chunks, chk), "WHISPER", "Peer-Realm")
for i, c in ipairs(chunks) do Sync:OnAddonMessage("IDDQD_LOOT2", ("LDAT1|1|pstream|%d|%s"):format(i, c), "WHISPER", "Peer-Realm") end
Sync:OnAddonMessage("IDDQD_LOOT2", "LEND1|1|pstream", "WHISPER", "Peer-Realm")
for _ = 1, 5 do fireTimers() end
local hasPX1 = false; for _, d in pairs(Store:Drops()) do if d.sessionID == "PX1" then hasPX1 = true end end
check(not hasPX1, "transfer for a non-guild session is rejected (personal isolation)")

-- MULTI-CHUNK / embedded-'|' transfer: a session with several drops serializes to a payload
-- that contains '|' (drop separators) and spans >1 chunk. The LDAT1 chunk data must survive
-- verbatim through the router (regression: split() truncated chunks at the first embedded '|',
-- corrupting every transfer of 2+ drops — single-drop transfers happened to have no '|').
Store:Sessions()["MC1"] = nil
for k, d in pairs(Store:Drops()) do if d.sessionID == "MC1" then Store:Drops()[k] = nil end end
Store:EnsureSession("MC1", { scope = "guild" })
local mcFirstDid
for i = 1, 6 do
    local did = "Creature-0-6424-36-51546-99" .. i .. "-000035A7A9:" .. (5000 + i)
    mcFirstDid = mcFirstDid or did
    Store:EnsureDrop(did, { sessionID = "MC1", itemId = 5000 + i, itemName = "Long Item Name Number " .. i, bossName = "Boss " .. i })
    Store:AddEvent(did, { type = "looted", actor = "Looter" .. i, at = 100 + i })
end
local mcPayload = Sync:SerializeSessionDrops("MC1")
local mcChunks = Sync:ChunkPayload(mcPayload)
local mcChk = ns.LootStoreShortHash(mcPayload)
check(#mcChunks >= 2, "multi-drop payload spans >1 chunk (got " .. #mcChunks .. ")")
check(mcPayload:find("|", 1, true) ~= nil, "multi-drop payload contains '|' separators")
-- wipe local copy, replay the transfer from a "peer"
for k, d in pairs(Store:Drops()) do if d.sessionID == "MC1" then Store:Drops()[k] = nil end end
Sync.incoming = {}
Sync:OnAddonMessage("IDDQD_LOOT2", ("LSTR1|1|mcstream|MC1|%d|%s"):format(#mcChunks, mcChk), "WHISPER", "Peer-Realm")
for i, c in ipairs(mcChunks) do Sync:OnAddonMessage("IDDQD_LOOT2", ("LDAT1|1|mcstream|%d|%s"):format(i, c), "WHISPER", "Peer-Realm") end
Sync:OnAddonMessage("IDDQD_LOOT2", "LEND1|1|mcstream", "WHISPER", "Peer-Realm")
for _ = 1, 5 do fireTimers() end
local mcCount = 0; for _, d in pairs(Store:Drops()) do if d.sessionID == "MC1" then mcCount = mcCount + 1 end end
check(mcCount == 6, "multi-chunk transfer applied all 6 drops (got " .. mcCount .. ")")
-- The re-serialized session must byte-match the original payload (full, uncorrupted round-trip).
check(Sync:SerializeSessionDrops("MC1") == mcPayload, "round-tripped session re-serializes identically (no corruption)")
-- bossName (display metadata) survives the transfer.
check(Store:Drops()[mcFirstDid] and Store:Drops()[mcFirstDid].bossName == "Boss 1", "bossName round-trips through transfer")

-- REQUEST COOLDOWN must not block a re-pull when the OWNER advertises a NEW hash.
-- (time() is constant here, so the time-based cooldown never elapses — a NEW wantedHash
-- must still get its own fresh request. Regression: cooldown keyed by sessionID alone left
-- a peer stuck on stale data for up to 60s after the owner changed it, e.g. a delete.)
Sync:OnInit()
Sync.panelOpen = true
Store:Sessions()["CD1"] = nil
Store:EnsureSession("CD1", { scope = "guild" })   -- we hold an (empty) shell; owner has more
Sync.sessionOwner = { CD1 = "Owner-Realm" }
-- First advertised version -> one request.
sent = {}
Sync.wantedHash = { CD1 = "hashV1" }
Sync:RequestSession("CD1")
local reqV1 = 0; for _, m in ipairs(sent) do if m.msg:find("^LREQ1|") or m.msg:find("^LRELAYREQ1|") then reqV1 = reqV1 + 1 end end
check(reqV1 == 1, "first version -> one request sent")
-- Same version again -> suppressed by cooldown.
sent = {}
Sync:RequestSession("CD1")
local reqSame = 0; for _, m in ipairs(sent) do if m.msg:find("^LREQ1|") or m.msg:find("^LRELAYREQ1|") then reqSame = reqSame + 1 end end
check(reqSame == 0, "same version re-request suppressed by cooldown (no loop)")
-- NEW version (owner changed data) -> must NOT be blocked by the prior cooldown.
sent = {}
Sync.wantedHash = { CD1 = "hashV2" }
Sync:RequestSession("CD1")
local reqV2 = 0; for _, m in ipairs(sent) do if m.msg:find("^LREQ1|") or m.msg:find("^LRELAYREQ1|") then reqV2 = reqV2 + 1 end end
check(reqV2 == 1, "NEW advertised hash bypasses the cooldown (re-pull happens immediately)")

print(("loot_sync_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
