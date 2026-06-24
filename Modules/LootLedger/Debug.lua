local ADDON, ns = ...

-- Test/debug helpers for the loot overhaul. Self-contained: registers /iddqd loot*
-- commands and touches nothing in the production modules. Safe to delete this file
-- (and its Includes.xml line) once in-game verification is done.

local Debug = ns:NewModule("LootDebug")

local function Store() return ns:GetModule("LootStore") end
local function Sync() return ns:GetModule("LootSync") end
local function Tracker() return ns:GetModule("LootTracker") end

local function p(msg) ns:Print(msg) end

-- Count entries in a table.
local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Format remaining trade-window seconds as mm:ss (or "-").
local function fmtWindow(secs)
    secs = tonumber(secs)
    if not secs or secs <= 0 then return "-" end
    return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

local function shortDropID(dropID)
    -- dropID = bossGUID:itemID:slot ; show the tail (itemID:slot) for readability.
    dropID = tostring(dropID or "")
    local itemId, slot = dropID:match(":(%d+):(%d+)$")
    if itemId then return ("…:%s:%s"):format(itemId, slot) end
    return dropID
end

-- /iddqd lootdump  — print every drop with its computed state, grouped by session.
function Debug:Dump()
    local store = Store()
    if not store then p("LootStore not loaded."); return end
    local drops, sessions = store:Drops(), store:Sessions()
    p(("|cff66ccffLoot ledger:|r %d session(s), %d drop(s)"):format(count(sessions), count(drops)))

    -- Group dropIDs under their session.
    local bySession = {}
    for dropID, drop in pairs(drops) do
        local sid = drop.sessionID or "(none)"
        bySession[sid] = bySession[sid] or {}
        bySession[sid][dropID] = drop
    end

    -- Sessions first (so empty/guild-only sessions are visible too).
    for sid, sess in pairs(sessions) do
        local scope = sess.scope or "?"
        local tag = scope == "guild" and "|cff44ff44GUILD|r" or "|cffffaa00personal|r"
        p((" Session %s  [%s]  %s  hash=%s"):format(
            tostring(sid), tag, tostring(sess.instance or "?"), tostring(store:SessionHash(sid))))
        for dropID, drop in pairs(bySession[sid] or {}) do
            local st = store:ComputeState(drop)
            p(("   %s  %s  status=%s  holder=%s  final=%s  win=%s"):format(
                shortDropID(dropID),
                tostring(drop.itemName or drop.itemId or "?"),
                tostring(st.status),
                tostring(st.currentHolder or "-"),
                tostring(st.finalOwner or "-"),
                fmtWindow(st.tradeWindow)))
        end
        bySession[sid] = nil
    end
    -- Any drops whose session record is missing (shouldn't happen, but surface it).
    for sid, group in pairs(bySession) do
        p((" |cffff5555orphan session %s|r"):format(tostring(sid)))
        for dropID, drop in pairs(group) do
            local st = store:ComputeState(drop)
            p(("   %s  %s  status=%s"):format(shortDropID(dropID), tostring(drop.itemName or "?"), tostring(st.status)))
        end
    end
end

-- /iddqd lootkeys — print the RAW event keys per drop (to diff divergence between clients).
function Debug:Keys()
    local store = Store()
    if not store then p("LootStore not loaded."); return end
    for dropID, drop in pairs(store:Drops()) do
        p(("|cff66ccff%s|r  (%s)  hash-part:"):format(shortDropID(dropID), tostring(drop.itemName or drop.itemId or "?")))
        local keys = {}
        for k in pairs(drop.events or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        if #keys == 0 then p("   (no events)") end
        for _, k in ipairs(keys) do
            local ev = drop.events[k]
            p(("   key=%s  type=%s actor=%s target=%s at=%s"):format(
                tostring(k), tostring(ev.type), tostring(ev.actor or "-"),
                tostring(ev.target or "-"), tostring(ev.at or "-")))
        end
    end
end

-- /iddqd lootscope guild|personal   — force the ACTIVE session's scope (for isolation tests).
-- /iddqd lootscope threshold <0..1> — set the guild-ratio threshold for future sessions.
function Debug:Scope(args)
    local store, tracker = Store(), Tracker()
    if not store then p("LootStore not loaded."); return end
    args = tostring(args or ""):lower()
    local word, value = args:match("^(%S+)%s*(.-)$")

    if word == "threshold" then
        local n = tonumber(value)
        if not n or n < 0 or n > 1 then p("Usage: /iddqd lootscope threshold <0..1>"); return end
        local s = store:Get(); if not s then return end
        s.settings = s.settings or {}
        s.settings.guildRaidThreshold = n
        p(("Guild-raid threshold set to %.2f (applies to new sessions)."):format(n))
        return
    end

    local sid = tracker and tracker.activeSessionID
    if not sid then
        p("No active session. Enter an instance first (the session is created on zone-in).")
        return
    end
    local sess = store:Sessions()[sid]
    if not sess then p("Active session has no record yet — loot something first."); return end

    if word == "guild" then
        store:PromoteSession(sid)               -- promote-only path + broadcast
        local sy = Sync(); if sy and sy.OnSessionPromoted then sy:OnSessionPromoted(sid) end
        p(("Forced session %s -> |cff44ff44GUILD|r (will sync to guildmates)."):format(tostring(sid)))
    elseif word == "personal" then
        -- DecideScope never demotes, so set it directly to exercise personal isolation.
        sess.scope = "personal"
        sess.promotedAt = nil
        p(("Forced session %s -> |cffffaa00personal|r (must NOT appear on other clients)."):format(tostring(sid)))
    else
        p("Usage: /iddqd lootscope guild | personal | threshold <0..1>")
        local cur = sess.scope or "?"
        p(("Active session %s is currently '%s'."):format(tostring(sid), tostring(cur)))
    end
end

-- /iddqd lootwipe — clear ALL drops + sessions (keeps settings) for a clean test slate.
-- Useful to clear stale records left over from the old LootLedger before testing.
function Debug:Wipe()
    local store = Store()
    if not store then p("LootStore not loaded."); return end
    local r = store:Get()
    if not r then p("Loot ledger DB not ready."); return end
    local nd, ns_ = count(r.drops), count(r.sessions)
    for sid in pairs(r.sessions or {}) do
        if store.HideSession then store:HideSession(sid, true) end
    end
    r.drops = {}
    r.sessions = {}
    -- Also clear the loot-distribution list (separate DB table).
    local nDist = 0
    local dist = ns:GetModule("LootDistStore")
    if dist and dist.Get then
        local dr = dist:Get()
        if dr then nDist = count(dr.entries); dr.entries = {}; dr.tombstones = {} end
    end
    local detect = ns:GetModule("LootDistDetect")
    if detect then detect.outstanding = {} end   -- drop any pending awards
    p(("Wiped %d drop(s), %d session(s), %d distribution item(s). Settings kept."):format(nd, ns_, nDist))
    -- Drop the cached active session, then immediately recreate it if we're already inside
    -- an instance so testing can continue without zoning out and back in.
    local t = Tracker()
    if t then
        t.activeSessionID = nil
        t.instanceEnterAt = nil
        t.currentInstanceAnchorKey = nil
        if r.instanceAnchors then r.instanceAnchors = {} end
        if t.StartSessionNow then t:StartSessionNow(false) end
        if t.activeSessionID and store.UnhideSession then store:UnhideSession(t.activeSessionID) end
        if t.activeSessionID then
            p(("Active loot session recreated: %s"):format(tostring(t.activeSessionID)))
        end
    end
end

-- /iddqd lootsync — force an immediate manifest broadcast + pull (skip the timers).
function Debug:ForceSync()
    local sy = Sync()
    if not sy then p("LootSync not loaded."); return end
    if sy.BeginManualSync then
        sy:BeginManualSync()
        p("Loot sync: manifest broadcast + manual pull window opened (120s).")
    elseif sy.DoBroadcastManifest then
        sy:DoBroadcastManifest()
        p("Loot sync: manifest broadcast.")
    end
end

function Debug:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local slash = ns:GetModule("Slash")
    if not slash then return end
    slash:Register("lootdump", function() Debug:Dump() end)
    slash:Register("lootkeys", function() Debug:Keys() end)
    slash:Register("lootscope", function(rest) Debug:Scope(rest) end)
    slash:Register("lootsync", function() Debug:ForceSync() end)
    slash:Register("lootwipe", function() Debug:Wipe() end)
    -- Loot test mode: bypass the boss-loot popup gate + relax the leader/assist auto-add
    -- requirement, and let History track unknown green-or-better instance items. This makes
    -- dungeon trade tests possible without waiting for real raid loot.
    slash:Register("loottest", function()
        ns.LOOT_DIST_TEST = not ns.LOOT_DIST_TEST
        p("Loot test mode: " .. (ns.LOOT_DIST_TEST and "|cff44ff44ON|r (greens flow; auto-add and History whitelist relaxed)" or "|cffff5555OFF|r"))
    end)
end
