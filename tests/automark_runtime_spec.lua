-- Headless test for AutoMarking runtime ownership pruning.
local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {}, autoMarkingNPCs = { gruul = { npcs = { { id = 19389, name = "Lair Brute" } } } } }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Print() end

local Engine = assert(loadfile(DIR .. "Modules/AutoMarking/markEngine.lua"))("iddqd", ns)
ns.autoMarkEngine = Engine

ns.modules.DB = {
    db = {
        debug = false,
        settings = {
            autoMarking = {
                version = 4,
                gruulNpcFixVersion = 1,
                enabled = true,
                activeProfileId = "default",
                profiles = {
                    {
                        id = "default",
                        name = "Default",
                        modifierEnabled = false,
                        modifierKey = "ALT",
                        lockAfterUse = false,
                        raids = { gruul = { [19389] = { 8, 7 } } },
                    },
                },
            },
        },
    },
}

local AM = assert(loadfile(DIR .. "Modules/AutoMarking/AutoMarking.lua"))("iddqd", ns)
AM.currentRaidKey = "gruul"

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local now, mouseGuid, visible, applied = 10, nil, {}, {}
local retry
local function guid(n) return "Creature-0-3133-565-7-19389-00000000" .. n end

AM._q = {
    mouseoverExists = function() return true end,
    mouseoverDead = function() return false end,
    mouseoverGuid = function() return mouseGuid end,
    raidTargetIndex = function() return visible.mouseover and visible.mouseover.marker end,
    setRaidTarget = function(m) applied[#applied + 1] = m; visible.mouseover = { guid = mouseGuid, marker = m } end,
    unitExists = function(unit) return visible[unit] ~= nil end,
    unitGuid = function(unit) return visible[unit] and visible[unit].guid end,
    unitRaidTarget = function(unit) return visible[unit] and visible[unit].marker end,
    inGroup = function() return true end,
    inRaid = function() return true end,
    isLeader = function() return true end,
    isAssist = function() return false end,
    altDown = function() return false end,
    shiftDown = function() return false end,
    ctrlDown = function() return false end,
    now = function() now = now + 1; return now end,
    after = function(_, fn) retry = fn end,
}

mouseGuid = guid("A")
visible = { mouseover = { guid = mouseGuid, marker = nil } }
AM:OnMouseoverChanged()
check(applied[1] == 8, "first visible Lair Brute gets skull")

mouseGuid = guid("B")
visible = { mouseover = { guid = mouseGuid, marker = nil } }
AM:OnMouseoverChanged()
check(applied[2] == 7, "previous owner stays reserved even when no longer visible")

mouseGuid = guid("C")
visible = {
    mouseover = { guid = mouseGuid, marker = nil },
    nameplate1 = { guid = guid("A"), marker = 8 },
    nameplate2 = { guid = guid("B"), marker = 7 },
}
AM:OnMouseoverChanged()
check(applied[3] == 8, "third Lair Brute wraps only after both configured marks are reserved")

AM:OnCombatLogEvent(nil, "UNIT_DIED", nil, nil, nil, nil, nil, guid("C"))
mouseGuid = guid("F")
visible = {
    mouseover = { guid = mouseGuid, marker = nil },
    nameplate1 = { guid = guid("B"), marker = 7 },
}
AM:OnMouseoverChanged()
check(applied[4] == 8, "dead owner frees its marker from combat log cleanup")

now = 100
AM._q.now = function() return now end
mouseGuid = guid("D")
visible = { mouseover = { guid = mouseGuid, marker = nil } }
AM:OnMouseoverChanged()
check(applied[5] == 8, "first fast-hover Lair Brute gets skull")

now = 100.05
mouseGuid = guid("E")
visible = {
    mouseover = { guid = mouseGuid, marker = nil },
    nameplate1 = { guid = guid("D"), marker = 8 },
}
AM:OnMouseoverChanged()
check(applied[6] == nil and type(retry) == "function", "throttled second fast-hover Lair Brute schedules a retry")

now = 100.35
retry()
check(applied[6] == 7, "retry marks second fast-hover Lair Brute with the next marker")

print(("automark_runtime_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
