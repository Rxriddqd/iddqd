local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local t = 1000
function GetTime() return t end
function time() return t end
function GetNormalizedRealmName() return "Realm" end

local leader, assist = false, false
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return assist end

local roster = {
    { "Alice-Realm", 1, "MAGE" },
    { "Bob-Realm", 1, "WARRIOR" },
    { "Cara-Realm", 2, "PRIEST" },
}
local inRaid = true
function IsInRaid() return inRaid end
function IsInGroup() return true end
function GetNumGroupMembers() return #roster end
function GetRaidRosterInfo(i)
    local r = roster[i]
    if r then return r[1], nil, r[2], nil, nil, r[3], nil, r[4] ~= false end
end
function UnitName(unit)
    if unit == "player" then return "Alice" end
    local idx = tonumber(tostring(unit):match("^raid(%d+)$"))
    if idx and roster[idx] then return roster[idx][1] end
    idx = tonumber(tostring(unit):match("^party(%d+)$"))
    return idx and roster[idx + 1] and roster[idx + 1][1] or unit
end
function UnitClass(unit)
    if unit == "player" then return nil, roster[1] and roster[1][3] or "MAGE" end
    local idx = tonumber(tostring(unit):match("^raid(%d+)$"))
    if idx and roster[idx] then return nil, roster[idx][3] end
    idx = tonumber(tostring(unit):match("^party(%d+)$"))
    return nil, idx and roster[idx + 1] and roster[idx + 1][3] or "MAGE"
end
function UnitExists() return true end

local auras = {
    raid1 = {
        { "Well Fed", "icon", 33257, 2000 },
        { "Flask", "icon", 28518, 2000 },
        { "Power Word: Fortitude", "fort", 10938, 2000 },
        { "Prayer of Spirit", "spirit", 32999, 2000 },
        { "Prayer of Shadow Protection", "shadow", 27683, 2000 },
        { "Gift of the Wild", "motw", 21850, 2000 },
        { "Greater Blessing of Kings", "kings", 25898, 2000 },
        { "Greater Blessing of Might", "might", 25916, 2000 },
        { "Arcane Brilliance", "int", 23028, 2000 },
    },
    raid2 = {
        { "Well Fed", "icon", 33257, 1100 },
        { "Food", "eating", 104934, 1006 },
    },
    raid3 = {
        { "Adept's Elixir", "battle", 33721, 2000 },
        { "Elixir of Major Fortitude", "guardian", 28513, 2000 },
    },
}
function UnitAura(unit, index)
    local aura = auras[unit] and auras[unit][index]
    if not aura then return nil end
    return aura[1], aura[2], nil, nil, nil, aura[4], aura[5], nil, nil, aura[3]
end
local sent = {}
function SendChatMessage(message, channel)
    sent[#sent + 1] = { message = message, channel = channel }
end

ns.modules.DB = { db = { settings = { readyCheck = {} } } }
assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
local ReadyCheck = assert(loadfile(DIR .. "Modules/ReadyCheck/ReadyCheck.lua"))("iddqd", ns)

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local settings = ReadyCheck:Settings()
check(settings.enabled == true and settings.checkFood == true and settings.checkFlask == true, "Settings applies defaults")
check(settings.opacity == 100 and settings.announceOnReadyCheck == false and settings.announceMissingFood == false and settings.announceEndStatus == false and settings.announceEndAllReady == false, "Settings applies announcement defaults")

local current = ReadyCheck:CurrentRoster()
check(#current == 3, "CurrentRoster reads raid roster")
check(current[1].name == "Alice" and current[3].group == 2, "CurrentRoster normalizes names and groups")

inRaid = false
roster = {
    { "Alice-Realm", 1, "MAGE" },
    { "Dara-Realm", 1, "DRUID" },
}
current = ReadyCheck:CurrentRoster()
check(#current == 2 and current[2].class == "DRUID", "CurrentRoster captures party class tokens")
check(ReadyCheck:ShouldTrackBuffGroup("motw") == true, "ShouldTrackBuffGroup enables MOTW in party with druid")
inRaid = true
roster = {
    { "Alice-Realm", 1, "MAGE" },
    { "Bob-Realm", 1, "WARRIOR" },
    { "Cara-Realm", 2, "PRIEST" },
}

local scan = ReadyCheck:ScanUnit("raid1")
check(scan.food == true and scan.flask == true, "ScanUnit detects food and flask")
check(scan.foodAura and scan.foodAura.spellId == 33257 and scan.flaskAura and scan.flaskAura.icon == "icon", "ScanUnit captures aura metadata")
check(scan.stamina == true and scan.spirit == true and scan.shadow == true and scan.motw == true and scan.blessing == true and scan.intellect == true, "ScanUnit detects raid buff groups")
check(scan.blessingAuras and #scan.blessingAuras == 2 and scan.blessingAuras[2].icon == "might", "ScanUnit captures all blessing auras")
check(scan.staminaAura and scan.staminaAura.icon == "fort" and scan.spiritAura and scan.spiritAura.icon == "spirit" and scan.intellectAura and scan.intellectAura.spellId == 23028, "ScanUnit captures raid buff metadata")
scan = ReadyCheck:ScanUnit("raid2")
check(scan.food == true and scan.foodLow == true and scan.foodInProgress == true and scan.flask == false and scan.stamina == false, "ScanUnit detects low food, eating food, and missing buffs")
scan = ReadyCheck:ScanUnit("raid3")
check(scan.flask == true and scan.battleElixir == true and scan.guardianElixir == true, "ScanUnit treats battle and guardian elixir pair as flask coverage")
check(scan.flaskAuras and #scan.flaskAuras == 2 and scan.flaskAuras[1].icon == "battle" and scan.flaskAuras[2].icon == "guardian", "ScanUnit captures both elixir icons")

ReadyCheck:Start("Alice-Realm", 35, { force = true })
local counts = ReadyCheck:Counts()
check(counts.total == 3 and counts.ready == 1 and counts.waiting == 2, "Start creates a ready-check session and marks starter ready")
check(counts.missingFood == 1 and counts.missingFlask == 1, "Counts tracks missing consumables")
check(ReadyCheck:ShouldTrackBuffGroup("stamina") == true and ReadyCheck:ShouldTrackBuffGroup("spirit") == true and ReadyCheck:ShouldTrackBuffGroup("shadow") == true and ReadyCheck:ShouldTrackBuffGroup("intellect") == true, "ShouldTrackBuffGroup enables buffs with providers")
check(ReadyCheck:ShouldTrackBuffGroup("motw") == false and ReadyCheck:ShouldTrackBuffGroup("blessing") == false, "ShouldTrackBuffGroup hides buffs without providers")
local election = { candidates = {
    assist = { name = "Assist", priority = 2 },
    member = { name = "Member", priority = 3 },
    leader = { name = "Leader", priority = 1 },
} }
check(ReadyCheck:BestAnnouncementCandidate(election).name == "Leader", "Announcement election prefers raid leader")
election.candidates.leader = nil
check(ReadyCheck:BestAnnouncementCandidate(election).name == "Assist", "Announcement election falls back to assist")
check(ReadyCheck:AnnounceCheck(true) == false and #sent == 0, "AnnounceCheck does nothing when categories are disabled")
settings.announceMissingFood = true
settings.announceMissingFlask = true
settings.announceMissingRaidBuffs = true
local lines = ReadyCheck:BuildAnnouncementLines()
check(#lines >= 4 and table.concat(lines, "\n"):find("Missing food: Cara", 1, true), "BuildAnnouncementLines reports missing food")
check(table.concat(lines, "\n"):find("Missing flask/elixirs: Bob", 1, true), "BuildAnnouncementLines reports missing flask")
check(table.concat(lines, "\n"):find("Missing Stamina:", 1, true), "BuildAnnouncementLines reports missing raid buffs")
check(table.concat(lines, "\n"):find("Missing Spirit: Cara", 1, true) and not table.concat(lines, "\n"):find("Missing Spirit: Bob", 1, true), "BuildAnnouncementLines skips non-mana classes for Spirit")
check(table.concat(lines, "\n"):find("Missing Arcane Intellect: Cara", 1, true) and not table.concat(lines, "\n"):find("Missing Arcane Intellect: Bob", 1, true), "BuildAnnouncementLines skips non-mana classes for Arcane Intellect")
ReadyCheck.session.rowsByKey["Cara-Realm"].online = false
lines = ReadyCheck:BuildAnnouncementLines()
check(not table.concat(lines, "\n"):find("Cara", 1, true), "BuildAnnouncementLines skips offline players")
ReadyCheck.session.rowsByKey["Cara-Realm"].online = true
settings.announceRaidBuffs.stamina = false
lines = ReadyCheck:BuildAnnouncementLines()
check(not table.concat(lines, "\n"):find("Missing Stamina:", 1, true) and table.concat(lines, "\n"):find("Missing Shadow Protection:", 1, true), "BuildAnnouncementLines respects per-buff raid announcement toggles")
settings.announceRaidBuffs.stamina = true
lines = ReadyCheck:BuildAnnouncementLines()
ReadyCheck:AnnounceCheck(true)
check(#sent == #lines and sent[1].channel == "RAID" and sent[1].message:find("^%[iddqd%]"), "AnnounceCheck sends configured report to raid")
sent = {}

roster = {
    { "Alice-Realm", 1, "MAGE" },
    { "Bob-Realm", 1, "WARRIOR" },
    { "Palaone-Realm", 1, "PALADIN" },
    { "Palatwo-Realm", 1, "PALADIN" },
}
auras = {
    raid1 = {
        { "Greater Blessing of Kings", "kings", 25898, 2000, "raid3" },
    },
    raid2 = {},
    raid3 = {
        { "Greater Blessing of Kings", "kings", 25898, 2000, "raid3" },
        { "Greater Blessing of Might", "might", 25916, 2000, "raid4" },
    },
    raid4 = {
        { "Greater Blessing of Kings", "kings", 25898, 2000, "raid3" },
        { "Greater Blessing of Might", "might", 25916, 2000, "raid4" },
    },
}
ReadyCheck:Start("Alice-Realm", 35, { force = true, silent = true })
lines = ReadyCheck:BuildAnnouncementLines()
local blessingText = table.concat(lines, "\n")
check(blessingText:find("Missing Paladin Blessing from Palatwo: Alice, Bob", 1, true), "BuildAnnouncementLines reports missing blessings by paladin caster")
check(blessingText:find("Missing Paladin Blessing from Palaone: Bob", 1, true), "BuildAnnouncementLines reports players with no blessing under each paladin")

roster = {
    { "Alice-Realm", 1, "MAGE" },
    { "Bob-Realm", 1, "WARRIOR" },
    { "Cara-Realm", 2, "PRIEST" },
}
auras = {
    raid1 = {
        { "Well Fed", "icon", 33257, 2000 },
        { "Flask", "icon", 28518, 2000 },
        { "Power Word: Fortitude", "fort", 10938, 2000 },
        { "Prayer of Spirit", "spirit", 32999, 2000 },
        { "Prayer of Shadow Protection", "shadow", 27683, 2000 },
        { "Gift of the Wild", "motw", 21850, 2000 },
        { "Greater Blessing of Kings", "kings", 25898, 2000 },
        { "Greater Blessing of Might", "might", 25916, 2000 },
        { "Arcane Brilliance", "int", 23028, 2000 },
    },
    raid2 = {
        { "Well Fed", "icon", 33257, 1100 },
        { "Food", "eating", 104934, 1006 },
    },
    raid3 = {
        { "Adept's Elixir", "battle", 33721, 2000 },
        { "Elixir of Major Fortitude", "guardian", 28513, 2000 },
    },
}

settings.announceOnReadyCheck = true
ReadyCheck:Start("Alice-Realm", 35, { force = true, silent = true })
check(#sent == 0, "Start silent suppresses automatic announcement")
ReadyCheck:Start("Alice-Realm", 35, { force = true })
check(#sent > 0, "Start announces when enabled")
sent = {}

ReadyCheck:Confirm("raid2", false)
counts = ReadyCheck:Counts()
check(counts.notready == 1 and counts.waiting == 1, "Confirm marks not-ready responses")

local rows = ReadyCheck:SortedRows()
check(rows[1].name == "Alice" and rows[2].name == "Bob" and rows[2].status == "notready", "SortedRows keeps roster positions static when players respond")

settings.announceEndStatus = true
settings.announceEndAllReady = false
sent = {}
ReadyCheck:Finish()
check(ReadyCheck.session and ReadyCheck.session.active == false, "Finish marks session inactive")
check(#sent == 3 and sent[1].message:find("Ready check ended: Ready 1/3", 1, true), "Finish announces end status summary")
check(sent[2].message:find("Not ready: Bob", 1, true) and sent[3].message:find("AFK/no response: Cara", 1, true), "Finish announces not-ready and AFK players")
ReadyCheck:Finish()
check(#sent == 3, "Finish only announces end status once")

settings.announceEndStatus = false
settings.announceEndAllReady = true
sent = {}
ReadyCheck:Start("Alice-Realm", 35, { force = true, silent = true })
ReadyCheck:Confirm("raid2", true)
ReadyCheck:Confirm("raid3", true)
ReadyCheck:Finish()
check(#sent == 1 and sent[1].message:find("everyone is ready", 1, true), "Finish announces everyone ready when enabled")

settings.showOnlyLeader = true
leader, assist = false, false
check(ReadyCheck:ShouldShow() == false, "ShouldShow respects leader-only setting")
assist = true
check(ReadyCheck:ShouldShow() == true, "ShouldShow allows assists when leader-only is enabled")

local testTimers = {}
C_Timer = { After = function(delay, fn) testTimers[#testTimers + 1] = { delay = delay, fn = fn } end }
settings.announceEndStatus = true
settings.announceEndAllReady = true
sent = {}
local testSession = ReadyCheck:Test()
check(testSession and testSession.active == true and testSession.test == true and #testTimers == 1, "Test starts a local timed session")
t = t + 35
testTimers[1].fn()
check(testSession.active == false and testSession.finishedAt == t, "Test session expires locally")
check(#sent == 0, "Test session expiry does not announce ready-check results")
C_Timer = nil

print(("ready_check_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
