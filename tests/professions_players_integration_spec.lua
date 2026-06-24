local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function fireTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

local sent = {}
C_ChatInfo = {
    SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
    end,
    RegisterAddonMessagePrefix = function() return true end,
}

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function UnitName() return "Me" end
function UnitClass() return "Mage", "MAGE" end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end

ns.professionRecipeDB = { skillLines = {}, bySpellId = {}, byEffectId = {} }
ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Sync.lua"))("iddqd", ns)

local Sync = ns:GetModule("ProfessionsSync")
local Store = ns:GetModule("ProfessionsStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end
local function requestedProfession(name)
    for _, m in ipairs(sent) do
        if m.msg:find("^REQ7|7|" .. name .. "|") or m.msg:find("^RELAYREQ|7|[^|]+|" .. name .. "|") then return true end
    end
    return false
end

Sync:OnInit()
Sync:SetPanelOpen(true)

sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Victim-Realm|Victim|Realm|MAGE|9|Alchemy:hash1", "GUILD", "Victim-Realm")
for _ = 1, 5 do fireTimers() end
check(Store:NeedsUpdate("Victim-Realm", "Alchemy", "hash1") == true, "manifest advertises a profession we do not have")
check(requestedProfession("Alchemy") == true, "same-realm manifest is accepted")

sent = {}
Sync:OnAddonMessage("IDDQD_PROF", "MAN7|7|Victim-OtherRealm|Victim|OtherRealm|MAGE|9|Tailoring:hash2", "GUILD", "Victim-Realm")
for _ = 1, 5 do fireTimers() end
check(requestedProfession("Tailoring") == false, "explicit cross-realm MAN7 key is rejected")

print(("professions_players_integration_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
