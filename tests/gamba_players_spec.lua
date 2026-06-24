local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function UnitName(unit) return unit == "player" and " Sylo-Spine Shatter " or nil end
function GetNormalizedRealmName() return "Spine Shatter" end
function GetRealmName() return "Ignored Realm" end

ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Gamba/Provider.lua"))("iddqd", ns)

local Gamba = ns:GetModule("GambaProvider")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Gamba:RegisterAccountCharacter(" Alt-Spine Shatter ") == true, "account character registration normalizes player name")
local settings = Gamba:Settings()
check(settings.accountRealms.spineshatter ~= nil, "account realm key uses normalized realm")
check(settings.accountCharacters.alt == "Alt", "account character stored by shared short name")

local roster = Gamba:AccountRosterCsv()
check(roster:find("Sylo", 1, true) ~= nil and roster:find("Alt", 1, true) ~= nil, "account roster exports normalized names")

check(Gamba:RegisterRemoteAccount(" Remote-Realm ", "acct:remote123", " Other-Realm ~Third-Realm ") == true, "remote account registration accepts normalized names")
check(Gamba:RemoteAccountId(" third-Elsewhere ") == "remote123", "remote roster lookup uses shared short names")

print(("gamba_players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
