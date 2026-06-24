local ADDON, ns = ...

local Panel = ns:NewModule("LootPanel")
local Nav = ns:GetModule("Nav")
local Theme = ns:GetModule("Theme")
local W = ns:GetModule("Widgets")

local function Store() return ns:GetModule("LootStore") end

local function iconPath(name)
    return ("Interface\\AddOns\\%s\\Media\\icons\\%s.tga"):format(ADDON, name)
end

local function raidIconPath(name)
    return ("Interface\\AddOns\\%s\\Media\\raids\\%s.tga"):format(ADDON, name)
end

local RAID_SESSION_ICONS = {
    -- Classic
    ["molten core"] = raidIconPath("classic-raid-mc"),
    ["blackwing lair"] = raidIconPath("classic-raid-bwl"),
    ["onyxia's lair"] = raidIconPath("classic-raid-onyxia"),
    ["temple of ahn'qiraj"] = raidIconPath("classic-raid-aq40"),
    ["ruins of ahn'qiraj"] = raidIconPath("classic-raid-aq20"),
    ["naxxramas"] = raidIconPath("classic-raid-naxx"),
    ["zul'gurub"] = raidIconPath("classic-raid-zg"),

    -- Burning Crusade
    ["karazhan"] = raidIconPath("tbc-raid-kara"),
    ["gruul's lair"] = raidIconPath("tbc-raid-gruul"),
    ["magtheridon's lair"] = raidIconPath("tbc-raid-magtheridon"),
    ["serpentshrine cavern"] = raidIconPath("tbc-raid-ssc"),
    ["tempest keep"] = raidIconPath("tbc-raid-tk"),
    ["hyjal summit"] = raidIconPath("tbc-raid-mh"),
    ["battle for mount hyjal"] = raidIconPath("tbc-raid-mh"),
    ["black temple"] = raidIconPath("tbc-raid-bt"),
    ["zul'aman"] = raidIconPath("raid-za"),
    ["sunwell plateau"] = raidIconPath("tbc-raid-swp"),

    -- Wrath
    ["the obsidian sanctum"] = raidIconPath("wotlk-raid-tos"),
    ["the eye of eternity"] = raidIconPath("wotlk-raid-teoe"),
    ["vault of archavon"] = raidIconPath("wotlk-raid-voa"),
    ["ulduar"] = raidIconPath("wotlk-raid-ulduar"),
    ["trial of the crusader"] = raidIconPath("wotlk-raid-togc"),
    ["trial of the grand crusader"] = raidIconPath("wotlk-raid-togc"),
    ["icecrown citadel"] = raidIconPath("wotlk-raid-icc"),
    ["the ruby sanctum"] = raidIconPath("wotlk-raid-trs"),
}

local RAID_SESSION_ICONS_BY_ID = {
    [409] = RAID_SESSION_ICONS["molten core"],
    [469] = RAID_SESSION_ICONS["blackwing lair"],
    [249] = RAID_SESSION_ICONS["onyxia's lair"],
    [531] = RAID_SESSION_ICONS["temple of ahn'qiraj"],
    [509] = RAID_SESSION_ICONS["ruins of ahn'qiraj"],
    [533] = RAID_SESSION_ICONS["naxxramas"],
    [309] = RAID_SESSION_ICONS["zul'gurub"],
    [532] = RAID_SESSION_ICONS["karazhan"],
    [565] = RAID_SESSION_ICONS["gruul's lair"],
    [544] = RAID_SESSION_ICONS["magtheridon's lair"],
    [548] = RAID_SESSION_ICONS["serpentshrine cavern"],
    [550] = RAID_SESSION_ICONS["tempest keep"],
    [534] = RAID_SESSION_ICONS["hyjal summit"],
    [564] = RAID_SESSION_ICONS["black temple"],
    [568] = RAID_SESSION_ICONS["zul'aman"],
    [580] = RAID_SESSION_ICONS["sunwell plateau"],
    [615] = RAID_SESSION_ICONS["the obsidian sanctum"],
    [616] = RAID_SESSION_ICONS["the eye of eternity"],
    [624] = RAID_SESSION_ICONS["vault of archavon"],
    [603] = RAID_SESSION_ICONS["ulduar"],
    [649] = RAID_SESSION_ICONS["trial of the crusader"],
    [631] = RAID_SESSION_ICONS["icecrown citadel"],
    [724] = RAID_SESSION_ICONS["the ruby sanctum"],
}

-- 5-man dungeon session icons (last-boss achievement art). Same scheme as raids:
-- Media\dungeons\<expansion>-dungeon-<shortcut>.tga, resolved by instanceID first then name.
local function dungeonIconPath(name)
    return ("Interface\\AddOns\\%s\\Media\\dungeons\\%s.tga"):format(ADDON, name)
end

local DUNGEON_SESSION_ICONS = {
    -- Classic
    ["the deadmines"] = dungeonIconPath("classic-dungeon-dm"),
    ["deadmines"] = dungeonIconPath("classic-dungeon-dm"),
    ["wailing caverns"] = dungeonIconPath("classic-dungeon-wc"),
    ["blackfathom deeps"] = dungeonIconPath("classic-dungeon-bfd"),
    ["the stockade"] = dungeonIconPath("classic-dungeon-stocks"),
    ["stormwind stockade"] = dungeonIconPath("classic-dungeon-stocks"),
    ["shadowfang keep"] = dungeonIconPath("classic-dungeon-sfk"),
    ["razorfen kraul"] = dungeonIconPath("classic-dungeon-rfk"),
    ["razorfen downs"] = dungeonIconPath("classic-dungeon-rfd"),
    ["zul'farrak"] = dungeonIconPath("classic-dungeon-zf"),
    ["maraudon"] = dungeonIconPath("classic-dungeon-mara"),
    ["gnomeregan"] = dungeonIconPath("classic-dungeon-gnomer"),
    ["uldaman"] = dungeonIconPath("classic-dungeon-uld"),
    ["the temple of atal'hakkar"] = dungeonIconPath("classic-dungeon-st"),
    ["sunken temple"] = dungeonIconPath("classic-dungeon-st"),
    ["blackrock depths"] = dungeonIconPath("classic-dungeon-brd"),
    ["lower blackrock spire"] = dungeonIconPath("classic-dungeon-lbrs"),
    ["upper blackrock spire"] = dungeonIconPath("classic-dungeon-ubrs"),
    ["dire maul"] = dungeonIconPath("classic-dungeon-dire-maul"),
    ["scarlet monastery"] = dungeonIconPath("classic-dungeon-sm"),
    ["scholomance"] = dungeonIconPath("classic-dungeon-scholo"),
    ["stratholme"] = dungeonIconPath("classic-dungeon-strat"),
    ["ragefire chasm"] = dungeonIconPath("classic-dungeon-rfc"),

    -- Burning Crusade
    ["hellfire ramparts"] = dungeonIconPath("tbc-dungeon-ramp"),     -- Omor the Unscarred
    ["the blood furnace"] = dungeonIconPath("tbc-dungeon-bf"),
    ["the shattered halls"] = dungeonIconPath("tbc-dungeon-sh"),
    ["the slave pens"] = dungeonIconPath("tbc-dungeon-sp"),
    ["the underbog"] = dungeonIconPath("tbc-dungeon-underbog"),      -- The Black Stalker
    ["the steamvault"] = dungeonIconPath("tbc-dungeon-sv"),
    ["mana-tombs"] = dungeonIconPath("tbc-dungeon-mt"),
    ["auchenai crypts"] = dungeonIconPath("tbc-dungeon-ac"),
    ["sethekk halls"] = dungeonIconPath("tbc-dungeon-seth"),
    ["shadow labyrinth"] = dungeonIconPath("tbc-dungeon-sl"),
    ["the mechanar"] = dungeonIconPath("tbc-dungeon-mech"),
    ["the botanica"] = dungeonIconPath("tbc-dungeon-bot"),
    ["the arcatraz"] = dungeonIconPath("tbc-dungeon-arc"),
    ["old hillsbrad foothills"] = dungeonIconPath("tbc-dungeon-ohb"),
    ["the black morass"] = dungeonIconPath("tbc-dungeon-bm"),
    ["magisters' terrace"] = dungeonIconPath("tbc-dungeon-mgt"),

    -- Wrath
    ["utgarde keep"] = dungeonIconPath("wotlk-dungeon-uk"),
    ["utgarde pinnacle"] = dungeonIconPath("wotlk-dungeon-up"),
    ["the nexus"] = dungeonIconPath("wotlk-dungeon-nexus"),
    ["the oculus"] = dungeonIconPath("wotlk-dungeon-oculus"),
    ["azjol-nerub"] = dungeonIconPath("wotlk-dungeon-an"),
    ["ahn'kahet: the old kingdom"] = dungeonIconPath("wotlk-dungeon-ak"),
    ["ahn'kahet"] = dungeonIconPath("wotlk-dungeon-ak"),
    ["drak'tharon keep"] = dungeonIconPath("wotlk-dungeon-dtk"),
    ["gundrak"] = dungeonIconPath("wotlk-dungeon-gd"),
    ["halls of stone"] = dungeonIconPath("wotlk-dungeon-hos"),
    ["halls of lightning"] = dungeonIconPath("wotlk-dungeon-hol"),
    ["the violet hold"] = dungeonIconPath("wotlk-dungeon-voh"),
    ["violet hold"] = dungeonIconPath("wotlk-dungeon-voh"),
    ["the culling of stratholme"] = dungeonIconPath("wotlk-dungeon-cos"),
    ["the forge of souls"] = dungeonIconPath("wotlk-dungeon-fos"),
    ["pit of saron"] = dungeonIconPath("wotlk-dungeon-pos"),
    ["halls of reflection"] = dungeonIconPath("wotlk-dungeon-hor"),
}

-- instanceID -> icon (authoritative; instance display names vary/localise). IDs from the
-- baked loot-source data + known map IDs.
local DUNGEON_SESSION_ICONS_BY_ID = {
    [36]  = DUNGEON_SESSION_ICONS["the deadmines"],
    [43]  = DUNGEON_SESSION_ICONS["wailing caverns"],
    [48]  = DUNGEON_SESSION_ICONS["blackfathom deeps"],
    [34]  = DUNGEON_SESSION_ICONS["the stockade"],
    [33]  = DUNGEON_SESSION_ICONS["shadowfang keep"],
    [47]  = DUNGEON_SESSION_ICONS["razorfen kraul"],
    [129] = DUNGEON_SESSION_ICONS["razorfen downs"],
    [209] = DUNGEON_SESSION_ICONS["zul'farrak"],
    [349] = DUNGEON_SESSION_ICONS["maraudon"],
    [90]  = DUNGEON_SESSION_ICONS["gnomeregan"],
    [70]  = DUNGEON_SESSION_ICONS["uldaman"],
    [109] = DUNGEON_SESSION_ICONS["the temple of atal'hakkar"],
    [230] = DUNGEON_SESSION_ICONS["blackrock depths"],
    [229] = DUNGEON_SESSION_ICONS["lower blackrock spire"],
    [389] = DUNGEON_SESSION_ICONS["ragefire chasm"],
    [429] = DUNGEON_SESSION_ICONS["dire maul"],
    [189] = DUNGEON_SESSION_ICONS["scarlet monastery"],
    [289] = DUNGEON_SESSION_ICONS["scholomance"],
    [329] = DUNGEON_SESSION_ICONS["stratholme"],
    -- TBC
    [543] = DUNGEON_SESSION_ICONS["hellfire ramparts"],
    [542] = DUNGEON_SESSION_ICONS["the blood furnace"],
    [540] = DUNGEON_SESSION_ICONS["the shattered halls"],
    [547] = DUNGEON_SESSION_ICONS["the slave pens"],
    [546] = DUNGEON_SESSION_ICONS["the underbog"],
    [545] = DUNGEON_SESSION_ICONS["the steamvault"],
    [557] = DUNGEON_SESSION_ICONS["mana-tombs"],
    [558] = DUNGEON_SESSION_ICONS["auchenai crypts"],
    [556] = DUNGEON_SESSION_ICONS["sethekk halls"],
    [555] = DUNGEON_SESSION_ICONS["shadow labyrinth"],
    [554] = DUNGEON_SESSION_ICONS["the mechanar"],
    [553] = DUNGEON_SESSION_ICONS["the botanica"],
    [552] = DUNGEON_SESSION_ICONS["the arcatraz"],
    [560] = DUNGEON_SESSION_ICONS["old hillsbrad foothills"],
    [269] = DUNGEON_SESSION_ICONS["the black morass"],
    [585] = DUNGEON_SESSION_ICONS["magisters' terrace"],
    -- Wrath
    [574] = DUNGEON_SESSION_ICONS["utgarde keep"],
    [575] = DUNGEON_SESSION_ICONS["utgarde pinnacle"],
    [576] = DUNGEON_SESSION_ICONS["the nexus"],
    [578] = DUNGEON_SESSION_ICONS["the oculus"],
    [601] = DUNGEON_SESSION_ICONS["azjol-nerub"],
    [619] = DUNGEON_SESSION_ICONS["ahn'kahet"],
    [600] = DUNGEON_SESSION_ICONS["drak'tharon keep"],
    [604] = DUNGEON_SESSION_ICONS["gundrak"],
    [599] = DUNGEON_SESSION_ICONS["halls of stone"],
    [602] = DUNGEON_SESSION_ICONS["halls of lightning"],
    [608] = DUNGEON_SESSION_ICONS["violet hold"],
    [595] = DUNGEON_SESSION_ICONS["the culling of stratholme"],
    [632] = DUNGEON_SESSION_ICONS["the forge of souls"],
    [658] = DUNGEON_SESSION_ICONS["pit of saron"],
    [668] = DUNGEON_SESSION_ICONS["halls of reflection"],
}

-- The authoritative map/instanceID. sessions store difficultyId (e.g. 174) in their own field,
-- but the REAL instanceID is the first segment of the sessionID ("545-174-82500" -> 545). Prefer
-- that; fall back to an explicit instanceId field if one is ever set.
local function sessionInstanceId(session)
    if not session then return 0 end
    local sid = tostring(session.sessionID or "")
    local fromSid = tonumber(sid:match("^(%d+)%-"))
    if fromSid then return fromSid end
    return tonumber(session.instanceId or 0) or 0
end

local function sessionKind(session)
    local instanceType = tostring((session and session.instanceType) or "")
    if instanceType == "party" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    local instanceId = sessionInstanceId(session)
    if RAID_SESSION_ICONS_BY_ID[instanceId] then return "raid" end
    if DUNGEON_SESSION_ICONS_BY_ID[instanceId] then return "dungeon" end
    return (session and session.scope == "guild") and "raid" or "dungeon"
end

-- Normalise an instance display name for matching: lowercase, drop a "Wing: " / "Coilfang: " /
-- "Auchindoun: " style prefix (Classic/TBC sub-instances), and a leading "the ".
local function normInstanceName(name)
    name = tostring(name or ""):lower()
    name = name:gsub("^[^:]+:%s*", "")   -- strip "coilfang: ", "auchindoun: ", "hellfire citadel: " etc.
    return name
end

local function raidSessionIcon(session)
    local instanceId = sessionInstanceId(session)
    if RAID_SESSION_ICONS_BY_ID[instanceId] then return RAID_SESSION_ICONS_BY_ID[instanceId] end
    if DUNGEON_SESSION_ICONS_BY_ID[instanceId] then return DUNGEON_SESSION_ICONS_BY_ID[instanceId] end
    local raw = tostring((session and session.instance) or ""):lower()
    if RAID_SESSION_ICONS[raw] then return RAID_SESSION_ICONS[raw] end
    if DUNGEON_SESSION_ICONS[raw] then return DUNGEON_SESSION_ICONS[raw] end
    local key = normInstanceName(session and session.instance)
    if RAID_SESSION_ICONS[key] then return RAID_SESSION_ICONS[key] end
    if DUNGEON_SESSION_ICONS[key] then return DUNGEON_SESSION_ICONS[key] end
    return iconPath("history")
end

local function statusColor(status)
    if status == "traded" or status == "finalized" or status == "obtained" then return Theme.color.success end
    if status == "guild_bank" then return { 0.42, 0.78, 1.00, 1 } end
    if status == "disenchanted" then return { 0.25, 0.55, 1.00, 1 } end   -- blue (enchanting)
    if status == "vendored" then return Theme.color.gold end
    if status == "deleted" then return Theme.color.danger end
    return Theme.color.dim
end

local function qualityColor(q)
    q = tonumber(q)
    if q == 5 then return 1.00, 0.50, 0.00 end
    if q == 4 then return 0.64, 0.21, 0.93 end
    if q == 3 then return 0.00, 0.44, 0.87 end
    if q == 2 then return 0.12, 1.00, 0.00 end
    return Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3]
end

local function shortName(value)
    if not value or value == "" then return "-" end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(value) end
    return (strsplit("-", value))
end

local function nameKey(value)
    return tostring(shortName(value or "")):lower()
end

local function classColor(classFile)
    if classFile and ns.classSpec and ns.classSpec.classColor then
        local c = ns.classSpec.classColor(classFile)
        if c then return c[1], c[2], c[3] end
    end
    local token = classFile and tostring(classFile):upper():gsub("%s+", "")
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return nil
end

local function buildClassMap()
    local map = {}
    local function put(name, classFile)
        if not name or name == "" or not classFile or classFile == "" then return end
        map[nameKey(name)] = classFile
    end

    if UnitName and UnitClass then
        local player = UnitName("player")
        local _, classFile = UnitClass("player")
        put(player, classFile)
    end

    if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
        for i = 1, (GetNumGroupMembers() or 0) do
            local ok, name, _, _, _, _, classFile = pcall(GetRaidRosterInfo, i)
            if ok then put(name, classFile) end
        end
    elseif GetNumGroupMembers and UnitName and UnitClass then
        for i = 1, (GetNumGroupMembers() or 0) do
            local unit = "party" .. i
            if not UnitExists or UnitExists(unit) then
                local name = UnitName(unit)
                local _, classFile = UnitClass(unit)
                put(name, classFile)
            end
        end
    end

    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        if GuildRoster then pcall(GuildRoster) end
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, className, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            put(name, classFile or className)
        end
    end

    return map
end

local function setPlayerCell(fs, name, classMap)
    local display = shortName(name)
    fs:SetText(display)
    local classFile = name and classMap and classMap[nameKey(name)]
    local r, g, b = classColor(classFile)
    if r then
        fs:SetTextColor(r, g, b, 1)
    else
        fs:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
    end
end

local function displayStatus(status)
    if status == "finalized" then return "Finalized" end
    if status == "deleted" then return "Removed" end
    if status == "guild_bank" then return "Guild Bank" end
    status = tostring(status or "pending")
    return status:sub(1, 1):upper() .. status:sub(2):lower()
end

-- The looted actor (firstHolder): read from the drop's "looted" event.
local function lootedActor(drop)
    if not drop or not drop.events then return nil end
    for _, e in pairs(drop.events) do
        if e.type == "looted" then return e.actor end
    end
    return nil
end

local function showItemTooltip(owner, drop)
    if not GameTooltip or not drop then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if drop.itemLink then
        GameTooltip:SetHyperlink(drop.itemLink)
    elseif drop.itemId then
        GameTooltip:SetHyperlink("item:" .. tostring(drop.itemId))
    else
        GameTooltip:SetText(drop.itemName or "Tracked loot")
    end
    GameTooltip:Show()
end

-- Loot-table columns. Tightened (vs. the old 8/244/344/450/550 layout) so the loot table is
-- narrower and the session cards on the left can be wider. Names are the variable-length field,
-- so "Drop" keeps the most room; the three name columns + status are sized to short character
-- names. x is relative to the loot content/header frame (which starts after the session pane).
local COLUMNS = {
    { key = "drop", label = "Drop", x = 8, width = 196 },
    { key = "first", label = "First", x = 210, width = 76 },
    { key = "current", label = "Current", x = 292, width = 76 },
    { key = "final", label = "Final", x = 374, width = 76 },
    { key = "status", label = "Status", x = 456, width = 78 },
}

local function formatSessionTime(ts)
    if not ts or ts == 0 then return "Unknown time" end
    return date("%d %b %H:%M", ts)
end

-- Stable grouping key identifying the BOSS a drop came from. Must be the boss, not just the
-- dropID prefix: loot-table dropIDs are "LT:instanceID:boss:itemID", so taking the first
-- segment returned "LT" for EVERY such drop and collapsed an entire instance into one group
-- (all items showed under a single boss). Prefer the explicit bossName; for an "LT:" id use its
-- boss segment; otherwise fall back to the dropID's leading GUID segment.
local function bossKeyFor(drop)
    local boss = drop and drop.bossName
    if boss and boss ~= "" then return boss end
    local id = tostring(drop and drop.dropID or "")
    local ltBoss = id:match("^LT:[^:]*:([^:]+):")    -- LT:instanceID:BOSS:itemID
    if ltBoss and ltBoss ~= "" then return ltBoss end
    return id:match("^([^:]+)") or "unknown"
end

-- Human-readable boss label. Prefer the captured/synced bossName; fall back to a friendly
-- string instead of showing the raw Creature-… GUID.
local function bossLabelFor(drop)
    local name = drop and drop.bossName
    if name and name ~= "" then return name end
    return "Trash & unattributed"
end

-- instanceID -> display name. Used to label a session whose stored `instance` field is missing
-- (e.g. one received via guild sync, which only carries drops + sessionID — not the name). The
-- instanceID is the first segment of the sessionID, so we can always recover a proper title
-- instead of falling back to the generic "Loot session". Covers the raids + 5-man dungeons the
-- addon knows about; unknown IDs still fall back gracefully.
local INSTANCE_NAME_BY_ID = {
    -- Classic raids
    [409] = "Molten Core", [469] = "Blackwing Lair", [249] = "Onyxia's Lair",
    [531] = "Temple of Ahn'Qiraj", [509] = "Ruins of Ahn'Qiraj", [533] = "Naxxramas", [309] = "Zul'Gurub",
    -- TBC raids
    [532] = "Karazhan", [565] = "Gruul's Lair", [544] = "Magtheridon's Lair",
    [548] = "Serpentshrine Cavern", [550] = "Tempest Keep", [534] = "Hyjal Summit",
    [564] = "Black Temple", [568] = "Zul'Aman", [580] = "Sunwell Plateau",
    -- Wrath raids
    [615] = "The Obsidian Sanctum", [616] = "The Eye of Eternity", [624] = "Vault of Archavon",
    [603] = "Ulduar", [649] = "Trial of the Crusader", [631] = "Icecrown Citadel", [724] = "The Ruby Sanctum",
    -- Classic dungeons
    [36] = "The Deadmines", [43] = "Wailing Caverns", [48] = "Blackfathom Deeps", [34] = "The Stockade",
    [33] = "Shadowfang Keep", [47] = "Razorfen Kraul", [129] = "Razorfen Downs", [209] = "Zul'Farrak",
    [349] = "Maraudon", [90] = "Gnomeregan", [70] = "Uldaman", [109] = "Sunken Temple",
    [230] = "Blackrock Depths", [229] = "Lower Blackrock Spire", [389] = "Ragefire Chasm",
    [429] = "Dire Maul", [189] = "Scarlet Monastery", [289] = "Scholomance", [329] = "Stratholme",
    -- TBC dungeons
    [543] = "Hellfire Ramparts", [542] = "The Blood Furnace", [540] = "The Shattered Halls",
    [547] = "The Slave Pens", [546] = "The Underbog", [545] = "The Steamvault",
    [557] = "Mana-Tombs", [558] = "Auchenai Crypts", [556] = "Sethekk Halls", [555] = "Shadow Labyrinth",
    [554] = "The Mechanar", [553] = "The Botanica", [552] = "The Arcatraz",
    [560] = "Old Hillsbrad Foothills", [269] = "The Black Morass", [585] = "Magisters' Terrace",
    -- Wrath dungeons
    [574] = "Utgarde Keep", [575] = "Utgarde Pinnacle", [576] = "The Nexus", [578] = "The Oculus",
    [601] = "Azjol-Nerub", [619] = "Ahn'kahet: The Old Kingdom", [600] = "Drak'Tharon Keep",
    [604] = "Gundrak", [599] = "Halls of Stone", [602] = "Halls of Lightning", [608] = "Violet Hold",
    [595] = "The Culling of Stratholme", [632] = "The Forge of Souls", [658] = "Pit of Saron",
    [668] = "Halls of Reflection",
}

-- Best display name for a session: its stored instance name, else recovered from the sessionID's
-- instanceID, else a generic fallback. Keeps synced sessions (no stored name) properly titled.
local function sessionDisplayName(sess, sid)
    if sess and sess.instance and sess.instance ~= "" then return sess.instance end
    local instId = tonumber(tostring(sid or ""):match("^(%d+)%-"))
    if instId and INSTANCE_NAME_BY_ID[instId] then return INSTANCE_NAME_BY_ID[instId] end
    return "Loot session"
end

-- Build the session list from Store:Sessions(). We show ALL sessions in the local
-- store (guild + own personal); there are no other players' personal sessions here.
local function buildSessions(mode)
    local store = Store()
    if not store then return {} end
    mode = mode == "dungeon" and "dungeon" or "raid"
    local sessions = {}
    local dropsBySession = {}
    for _, drop in pairs(store:Drops()) do
        local sid = drop.sessionID
        if sid then
            dropsBySession[sid] = dropsBySession[sid] or {}
            table.insert(dropsBySession[sid], drop)
        end
    end
    for sid, sess in pairs(store:Sessions()) do
        if store.IsSessionHidden and store:IsSessionHidden(sid) then
            -- local hide/delete: retained data may still be used for lifecycle/sync serving,
            -- but it should not reappear in this user's History panel.
        elseif sessionKind(sess) ~= mode then
            -- filtered by the Raid/Dungeon segmented control
        else
        local drops = dropsBySession[sid] or {}
        table.sort(drops, function(a, b) return (a.droppedAt or 0) < (b.droppedAt or 0) end)
        local displayName = sessionDisplayName(sess, sid)
        local firstAt = sess.startedAt or 0
        if firstAt == 0 and drops[1] and drops[1].droppedAt then firstAt = drops[1].droppedAt end
        table.insert(sessions, {
            key = sid,
            sessionID = sid,
            scope = sess.scope,
            instanceType = sess.instanceType,
            instance = sess.instance or displayName,   -- recovered name also helps icon name-match
            instanceId = sess.instanceId or sessionInstanceId(sess),
            difficultyId = sess.difficultyId,
            firstAt = firstAt,
            source = displayName,                        -- proper title even for synced sessions
            drops = drops,
        })
        end
    end
    table.sort(sessions, function(a, b) return (a.firstAt or 0) > (b.firstAt or 0) end)
    return sessions
end

-- Group a session's drops by boss (stable GUID-prefix key), labelled by boss name, and
-- honour the collapse/expand state in `expanded` ([bossKey]=true means collapsed).
local function buildDisplayRows(session, expanded)
    expanded = expanded or {}
    local rows, groupOrder, groups, labels = {}, {}, {}, {}
    for _, drop in ipairs((session and session.drops) or {}) do
        local boss = bossKeyFor(drop)
        if not groups[boss] then
            groups[boss] = {}
            labels[boss] = bossLabelFor(drop)
            table.insert(groupOrder, boss)
        end
        table.insert(groups[boss], drop)
    end
    for _, boss in ipairs(groupOrder) do
        local collapsed = expanded[boss] and true or false
        local kids = groups[boss]
        table.insert(rows, { kind = "boss", key = boss, name = labels[boss], count = #kids, collapsed = collapsed })
        if not collapsed then
            table.sort(kids, function(a, b) return (a.droppedAt or 0) < (b.droppedAt or 0) end)
            for _, drop in ipairs(kids) do
                table.insert(rows, { kind = "drop", drop = drop })
            end
        end
    end
    return rows
end

-- Hide a session from this user's panel. The underlying drops are retained so lifecycle changes
-- can still be tracked and guildmates can still be served data if they request it.
local function deleteSession(sessionID)
    local store = Store()
    if not store or not sessionID then return 0 end
    if store.HideSession then store:HideSession(sessionID, false) end
    local count = 0
    for _, drop in pairs(store:Drops()) do
        if drop.sessionID == sessionID then count = count + 1 end
    end
    return count
end

-- Resolve a display name for a drop. If the item name isn't cached yet, request it
-- and refresh the panel once it loads, instead of permanently showing "Item #ID".
local function resolveDropName(drop, frame)
    if drop.itemName and drop.itemName ~= "" and not tostring(drop.itemName):find("^Item #") then
        return drop.itemName
    end
    local id = drop.itemId
    if id and GetItemInfo then
        local name = GetItemInfo(drop.itemLink or id)
        if name and name ~= "" then
            drop.itemName = name   -- cache the resolved name back onto the drop
            return name
        end
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
            frame._pendingItemLoad = frame._pendingItemLoad or {}
            if not frame._pendingItemLoad[id] then
                frame._pendingItemLoad[id] = true
            end
        end
    end
    return "Item #" .. tostring(id or "?")
end

local function buildPanel(parent)
    local f = W:Card(parent, "base", true)
    Panel:SetFrame(f)

    -- SetPanelOpen wiring: tell LootSync when this panel becomes visible/hidden.
    f:HookScript("OnShow", function()
        local s = ns:GetModule("LootSync")
        if s and s.SetPanelOpen then s:SetPanelOpen(true) end
    end)
    f:HookScript("OnHide", function()
        local s = ns:GetModule("LootSync")
        if s and s.SetPanelOpen then s:SetPanelOpen(false) end
    end)

    -- Register a listener (once) that refreshes the panel when a pending item (name or icon)
    -- loads. Items stream into the client cache over a few seconds after opening a session, so
    -- DEBOUNCE: coalesce the burst into a single refresh instead of one per item.
    if not f._itemInfoListener and CreateFrame then
        f._itemInfoListener = CreateFrame("Frame")
        f._itemInfoListener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        f._itemInfoListener:SetScript("OnEvent", function(_, _, itemID)
            if not (f._pendingItemLoad and itemID and f._pendingItemLoad[itemID]) then return end
            f._pendingItemLoad[itemID] = nil
            if not f:IsShown() or not f.Refresh then return end
            if not C_Timer then f:Refresh(); return end
            f._refreshToken = (f._refreshToken or 0) + 1
            local token = f._refreshToken
            C_Timer.After(0.2, function()
                if f._refreshToken == token and f:IsShown() then f:Refresh() end
            end)
        end)
    end

    local title = W:Title(f, "Raid Loot History")
    title:SetPoint("TOPLEFT", 18, -16)

    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Tracks first holder, trades, and final owner for each looted item.")

    local share = W:Button(f, "Share", 86, 24)
    share:SetPoint("TOPRIGHT", -18, -18)
    share:SetScript("OnClick", function()
        local s = ns:GetModule("LootSync")
        if not s then return end
        if s.BeginManualSync then s:BeginManualSync()
        elseif s.DoBroadcastManifest then s:DoBroadcastManifest() end
    end)

    local sessionTitle = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sessionTitle, "eyebrow", "warm")
    sessionTitle:SetPoint("TOPLEFT", 18, -72)
    sessionTitle:SetText("Sessions")

    f.sessionMode = "raid"
    local raidBtn = W:Button(f, "Raid", 58, 22)
    raidBtn:SetPoint("LEFT", sessionTitle, "RIGHT", 12, 0)
    local dungeonBtn = W:Button(f, "Dungeon", 78, 22)
    dungeonBtn:SetPoint("LEFT", raidBtn, "RIGHT", 6, 0)
    f.raidSessionBtn = raidBtn
    f.dungeonSessionBtn = dungeonBtn
    local function setSessionMode(mode)
        f.sessionMode = mode == "dungeon" and "dungeon" or "raid"
        if f.raidSessionBtn then f.raidSessionBtn:SetTone(f.sessionMode == "raid" and "blue" or nil) end
        if f.dungeonSessionBtn then f.dungeonSessionBtn:SetTone(f.sessionMode == "dungeon" and "blue" or nil) end
        f.selectedSessionKey = nil
        f:Refresh()
    end
    raidBtn:SetScript("OnClick", function() setSessionMode("raid") end)
    dungeonBtn:SetScript("OnClick", function() setSessionMode("dungeon") end)
    raidBtn:SetTone("blue")

    local sessionSf, sessionContent = W:ScrollHost(f)
    sessionSf:SetPoint("TOPLEFT", 18, -90)
    sessionSf:SetPoint("BOTTOMLEFT", 18, 18)
    sessionSf:SetWidth(240)   -- wider session cards (was 178); loot table shifts right to suit
    f.sessionScroll = sessionSf
    f.sessionContent = sessionContent
    f.sessionRows = {}
    f.sessionBar = W:ScrollBar(sessionSf, sessionContent)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 276, -72)
    header:SetPoint("TOPRIGHT", -28, -72)
    header:SetHeight(16)
    f.header = header
    f.headerLabels = {}

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.bg:SetAllPoints(header)
    header.bg:SetVertexColor(1, 1, 1, 0.025)

    header.line = header:CreateTexture(nil, "BORDER")
    header.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT", 0, 0)
    header.line:SetPoint("BOTTOMRIGHT", 0, 0)
    header.line:SetVertexColor(1, 1, 1, 0.06)

    for _, col in ipairs(COLUMNS) do
        local label = header:CreateFontString(nil, "OVERLAY")
        Theme:Text(label, "eyebrow", "warm")
        label:SetPoint("LEFT", col.x, 1)
        label:SetWidth(col.width)
        label:SetJustifyH("LEFT")
        label:SetText(col.label)
        f.headerLabels[col.key] = label
    end

    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 276, -90)
    sf:SetPoint("BOTTOMRIGHT", -28, 18)
    f.scroll = sf
    f.content = content
    f.rows = {}
    f.bar = W:ScrollBar(sf, content)

    function f:EnsureSessionRow(i)
        local row = self.sessionRows[i]
        if row then return row end
        row = W:ListRow(sessionContent, true)
        row:SetHeight(34)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 7, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.del = W:IconActionButton(row, iconPath("trash-2"), 20, 20, "Delete session")
        row.del:SetPoint("RIGHT", -5, 0)
        if row.del._icon then row.del._icon:SetSize(13, 13) end
        -- Instance name (primary line).
        row.label = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.label, "caption", "ink")
        row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.label:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        -- Date / scope (secondary line).
        row.sub = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.sub, "caption", "faint")
        row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -1)
        row.sub:SetPoint("RIGHT", -8, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self:SetRowHover(true) end)
        row:SetScript("OnLeave", function(self) self:SetRowHover(false) end)
        self.sessionRows[i] = row
        return row
    end

    function f:EnsureLootRow(i)
        local row = self.rows[i]
        if row then return row end
        row = W:ListRow(content)

        -- 18px (even) so it centers on a whole pixel in the 22px row; anchored TOPLEFT with
        -- integer offsets so the quality border lands evenly on all sides (a fractional icon
        -- position rounds the border to 1px on some edges and 2px on others). Top inset 2.
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -2)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconBorder = W:IconBorder(row.icon)

        row.name = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.name, "caption", "ink")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetWidth(COLUMNS[1].width - 32)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.first = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.first, "caption", "dim")
        row.first:SetPoint("LEFT", COLUMNS[2].x, 0)
        row.first:SetWidth(COLUMNS[2].width)
        row.first:SetJustifyH("LEFT")
        row.first:SetWordWrap(false)

        row.current = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.current, "caption", "dim")
        row.current:SetPoint("LEFT", COLUMNS[3].x, 0)
        row.current:SetWidth(COLUMNS[3].width)
        row.current:SetJustifyH("LEFT")
        row.current:SetWordWrap(false)

        row.final = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.final, "caption", "dim")
        row.final:SetPoint("LEFT", COLUMNS[4].x, 0)
        row.final:SetWidth(COLUMNS[4].width)
        row.final:SetJustifyH("LEFT")
        row.final:SetWordWrap(false)

        row.status = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.status, "caption", "dim")
        row.status:SetPoint("LEFT", COLUMNS[5].x, 0)
        row.status:SetWidth(COLUMNS[5].width)
        row.status:SetJustifyH("LEFT")
        row.status:SetWordWrap(false)

        row.group = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.group, "eyebrow", "warm")
        row.group:SetPoint("LEFT", 8, 0)
        row.group:SetPoint("RIGHT", -8, 0)
        row.group:SetJustifyH("LEFT")
        row.group:SetWordWrap(false)

        self.rows[i] = row
        return row
    end

    function f:SelectSession(key)
        self.selectedSessionKey = key
        self:Refresh()
    end

    function f:SelectedSession()
        local sessions = self.sessions or {}
        if #sessions == 0 then return nil end
        for _, session in ipairs(sessions) do
            if session.key == self.selectedSessionKey then return session end
        end
        self.selectedSessionKey = sessions[1].key
        return sessions[1]
    end

    function f:RefreshSessions()
        for _, row in ipairs(self.sessionRows) do row:Hide() end
        local sessions = self.sessions or {}
        local rowH, y = 34, 0
        local contentW = math.max(220, (sessionSf:GetWidth() or 0) - 8)
        sessionContent:SetWidth(contentW)

        if #sessions == 0 then
            local row = self:EnsureSessionRow(1)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(contentW, rowH)
            row.icon:SetTexture(iconPath("history"))
            row.icon:Show()
            row.label:SetText("No sessions")
            row.sub:SetText("Loot will appear here")
            row.selected = false
            row:SetRowVisual(1, false)
            row:SetScript("OnClick", nil)
            row.del:Hide()
            row:Show()
            sessionContent:SetHeight(rowH)
            self.sessionBar:Update()
            return
        end

        for i, session in ipairs(sessions) do
            local row = self:EnsureSessionRow(i)
            local selected = session.key == self.selectedSessionKey
            local sessionKey = session.key
            local dropCount = #(session.drops or {})
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(contentW, rowH)
            row.icon:SetTexture(raidSessionIcon(session))
            row.icon:Show()
            -- Primary line = the instance (the meaningful label); secondary = date; badge = count.
            row.label:SetText(session.source or "Loot session")
            row.sub:SetText(("%s  |  %d drop%s"):format(formatSessionTime(session.firstAt), dropCount, dropCount == 1 and "" or "s"))
            row.selected = selected
            row:SetRowVisual(i, selected)
            row:SetScript("OnClick", function() self:SelectSession(sessionKey) end)
            row.del:Show()
            row.del:Enable()
            row.del:SetScript("OnClick", function()
                W:Confirm("IDDQD_LOOT_DELETE_SESSION", ("Delete this loot session with %d drops?"):format(dropCount), function()
                    local removed = deleteSession(sessionKey)
                    self.selectedSessionKey = nil
                    ns:Print(("Hidden loot session locally (%d drops retained)."):format(removed), "warning")
                    self:Refresh()
                end)
            end)
            row:Show()
            y = y - rowH
        end

        sessionContent:SetHeight(math.max(sessionSf:GetHeight(), #sessions * rowH))
        self.sessionBar:Update()
    end

    function f:RefreshLoot()
        for _, row in ipairs(self.rows) do row:Hide() end
        local session = self:SelectedSession()
        self.collapsed = self.collapsed or {}   -- [bossKey] = true when collapsed
        local displayRows = buildDisplayRows(session, self.collapsed)
        local y = 0
        local rowH, groupH = 22, 20
        -- Min width covers the last column (status ends ~534); the table is narrower now so the
        -- session cards on the left can be wider.
        local contentW = math.max(540, (sf:GetWidth() or 0) - 8)
        content:SetWidth(contentW)

        if not session then
            local row = self:EnsureLootRow(1)
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetSize(contentW, rowH)
            row.icon:Hide()
            row.name:Hide()
            row.first:Hide()
            row.current:Hide()
            row.final:Hide()
            row.status:Hide()
            row.group:Show()
            row.group:SetText("No loot has been tracked yet.")
            row:SetRowVisual(1, false)
            row:Show()
            content:SetHeight(rowH)
            self.bar:Update()
            return
        end

        local store = Store()
        local classMap = buildClassMap()
        for i, entry in ipairs(displayRows) do
            local row = self:EnsureLootRow(i)
            local isBoss = entry.kind == "boss"
            local height = isBoss and groupH or rowH
            row:SetSize(contentW, height)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            row.icon:SetShown(not isBoss)
            if isBoss and row.iconBorder then row.iconBorder:Hide() end
            row.name:SetShown(not isBoss)
            row.first:SetShown(not isBoss)
            row.current:SetShown(not isBoss)
            row.final:SetShown(not isBoss)
            row.status:SetShown(not isBoss)
            row.group:SetShown(isBoss)
            row.drop = nil

            if isBoss then
                row:SetRowVisual(i, false, "group")
                -- Collapse toggle (+ when collapsed, - when expanded) + boss name + drop count;
                -- the whole row toggles the group.
                local toggle = entry.collapsed and "|cffaaaaaa+|r" or "|cffaaaaaa-|r"
                row.group:SetText(("%s  %s  |cff888888(%d)|r"):format(toggle, tostring(entry.name), entry.count or 0))
                local bossKey = entry.key
                row:SetScript("OnEnter", function(self) self:SetRowHover(true) end)
                row:SetScript("OnLeave", function(self) self:SetRowHover(false) end)
                row:SetScript("OnMouseDown", function()
                    f.collapsed[bossKey] = not f.collapsed[bossKey]
                    f:RefreshLoot()
                end)
            else
                local drop = entry.drop
                local state = (store and store:ComputeState(drop)) or {}
                local icon = drop.icon
                if not icon and drop.itemId then
                    -- Prefer GetItemIcon (resolves from the item cache faster than full GetItemInfo
                    -- and is enough for the icon texture); fall back to GetItemInfo's icon.
                    if GetItemIcon then icon = GetItemIcon(drop.itemId) end
                    if not icon then icon = select(10, GetItemInfo(drop.itemId)) end
                    if icon then
                        drop.icon = icon   -- cache it back so future renders are instant
                    elseif C_Item and C_Item.RequestLoadItemDataByID then
                        -- Not cached yet: request a load and mark pending so the
                        -- GET_ITEM_INFO_RECEIVED listener re-renders once it arrives (otherwise
                        -- the icon only appears after the user tabs away and back).
                        pcall(C_Item.RequestLoadItemDataByID, drop.itemId)
                        f._pendingItemLoad = f._pendingItemLoad or {}
                        f._pendingItemLoad[drop.itemId] = true
                    end
                end
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if row.iconBorder then row.iconBorder:SetQuality(drop.quality) end
                row.name:SetText(resolveDropName(drop, f))
                row.name:SetTextColor(qualityColor(drop.quality))
                setPlayerCell(row.first, lootedActor(drop) or state.currentHolder, classMap)
                setPlayerCell(row.current, state.currentHolder, classMap)
                -- Final is a real terminal ownership state, not just "latest known holder".
                -- Trades keep moving Current; only concrete finalizing events populate Final.
                setPlayerCell(row.final, state.status == "finalized" and state.finalOwner or nil, classMap)
                row.status:SetText(displayStatus(state.status))
                local c = statusColor(state.status)
                row.status:SetTextColor(c[1], c[2], c[3], 1)
                row.drop = drop
                row:SetRowVisual(i, false)
                row:SetScript("OnEnter", function(self)
                    self:SetRowHover(true)
                    showItemTooltip(self, self.drop)
                end)
                row:SetScript("OnLeave", function(self)
                    self:SetRowHover(false)
                    if GameTooltip then GameTooltip:Hide() end
                end)
                row:SetScript("OnMouseDown", nil)
                row:SetRowHover(false)
            end
            row:Show()
            y = y - height
        end

        content:SetHeight(math.max(sf:GetHeight(), -y))
        self.bar:Update()
    end

    function f:Refresh()
        self.sessions = buildSessions(self.sessionMode)
        if self.raidSessionBtn then self.raidSessionBtn:SetTone(self.sessionMode == "raid" and "blue" or nil) end
        if self.dungeonSessionBtn then self.dungeonSessionBtn:SetTone(self.sessionMode == "dungeon" and "blue" or nil) end
        self:SelectedSession()
        self:RefreshSessions()
        self:RefreshLoot()
    end

    sf:SetScript("OnSizeChanged", function()
        f:Refresh()
    end)
    sessionSf:SetScript("OnSizeChanged", function()
        f:Refresh()
    end)

    f:Refresh()
    return f
end

-- Frame handshake: Sync/Tracker call ns:GetModule("LootPanel"):Refresh() when data changes.
function Panel:SetFrame(frame) self.frame = frame end

-- Debounced: a burst of changes (a loot window of several items, a bag audit) collapses into
-- one rebuild on the next frame. Skips work entirely when the panel isn't shown.
function Panel:Refresh()
    if not (self.frame and self.frame.Refresh and self.frame:IsShown()) then return end
    if self._refreshPending then return end
    self._refreshPending = true
    local function fire()
        self._refreshPending = nil
        if self.frame and self.frame.Refresh and self.frame:IsShown() then self.frame:Refresh() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, fire) else fire() end
end

Nav:RegisterPanel("history", buildPanel)
