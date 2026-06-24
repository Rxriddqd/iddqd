local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = {
    modules = {},
    raid_assignments_json = {},
    raid_assignments_b64url = {},
}
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function GetTime() return 1000 end
function UnitName(unit)
    if unit == "player" then return "Sylo" end
    if unit == "party1" then return " Target-SpineShatter " end
    return nil
end
function GetNormalizedRealmName() return "Spine Shatter" end
function GetRealmName() return "Ignored Realm" end

local raidNames = {
    "Other-SpineShatter",
    " Target-SpineShatter ",
}
function IsInRaid() return true end
function GetNumGroupMembers() return #raidNames end
function GetRaidRosterInfo(i) return raidNames[i], 0 end
function GetMasterLootCandidate(_, i) return raidNames[i] end

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Council/Council.lua"))("iddqd", ns)

local Council = ns:GetModule("Council")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Council:CandidateIndexFor(1, " Target-OtherRealm ") == 2, "CandidateIndexFor normalizes short display names")
check(Council:GroupMemberPresent("target") == true, "GroupMemberPresent normalizes roster names")

print(("council_players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
