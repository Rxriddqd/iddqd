local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = {
    modules = {},
    raid_assignments_json = {},
    raid_assignments_b64url = {},
    professionRecipeDB = { skillLines = {}, bySpellId = {}, byEffectId = {} },
}
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function UnitName(unit) return unit == "player" and "Me" or nil end
function UnitClass() return "Mage", "MAGE" end
function GetNormalizedRealmName() return "Spine Shatter" end
function GetRealmName() return "Ignored Realm" end
function strsplit(sep, value, limit)
    value = tostring(value or "")
    local first, rest = value:match("^(.-)" .. sep .. "(.*)$")
    if limit == 2 then return first or value, rest end
    return first or value, rest
end

ns.modules.DB = { db = { professions = {} } }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Professions.lua"))("iddqd", ns)

local Professions = ns:GetModule("Professions")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local profile = Professions:LocalProfile()
check(profile ~= nil, "legacy LocalProfile is available")
check(profile.key == "Me-SpineShatter", "legacy LocalProfile uses normalized full local player name")
check(profile.name == "Me", "legacy LocalProfile stores short display name")
check(profile.realm == "SpineShatter", "legacy LocalProfile stores normalized realm")

print(("professions_legacy_players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
