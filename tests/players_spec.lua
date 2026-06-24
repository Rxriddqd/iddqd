local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end

function GetNormalizedRealmName() return "Spine Shatter" end
function GetRealmName() return "Ignored Realm" end
function UnitName(unit) return unit == "player" and "Sylo" or nil end

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
local Players = ns:GetModule("Players")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Players:Trim("  abc  ") == "abc", "Trim removes surrounding whitespace")
check(Players:CurrentRealm() == "SpineShatter", "CurrentRealm normalizes spaces")
check(Players:FullName("Sylo") == "Sylo-SpineShatter", "FullName appends normalized realm")
check(Players:FullName("Sylo-Other") == "Sylo-Other", "FullName preserves existing realm")
check(Players:ShortName("Sylo-SpineShatter") == "Sylo", "ShortName removes realm")
check(Players:LocalName() == "Sylo-SpineShatter", "LocalName returns full player name")
check(Players:Same("Sylo-SpineShatter", "sylo") == true, "Same matches short and full names case-insensitively")
check(Players:Same("Sylo-SpineShatter", "sylo-OtherRealm") == false, "Same rejects explicit cross-realm names")
check(Players:Same("", "sylo") == false, "Same rejects empty names")

print(("players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
