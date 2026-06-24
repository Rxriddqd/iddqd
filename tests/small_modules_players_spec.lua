local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 1000 end

function IsInRaid() return true end
function GetNumGroupMembers() return 2 end
function GetRaidRosterInfo(i)
    if i == 1 then return " Alice-Realm ", nil, 1, nil, nil, "MAGE" end
    if i == 2 then return "Bob-Realm", nil, 1, nil, nil, "WARRIOR" end
end
function UnitName(unit) return unit == "player" and "Alice-Realm" or nil end

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Invite/Invite.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Attendance/Attendance.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/RaidGroups/EditProfile.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/RaidGroups/GuildRoster.lua"))("iddqd", ns)

local Invite = ns:GetModule("Invite")
local Attendance = ns:GetModule("Attendance")
local Edit = ns:GetModule("RaidGroupsEdit")
local GuildRoster = ns:GetModule("RaidGroupsGuildRoster")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Invite._stripRealm(" Bob-Realm ") == "Bob", "Invite strips realm through Players")

local roster = Attendance:CurrentRoster()
check(roster[1] == "Alice" and roster[2] == "Bob", "Attendance normalizes roster names")

local profile = { slots = {}, members = {} }
check(Edit.place(profile, 1, { name = " Cara-Realm ", class = "PRIEST" }) == true, "RaidGroupsEdit places member")
check(Edit.place(profile, 2, { name = "Cara-Other", class = "PRIEST" }) == true, "RaidGroupsEdit replaces duplicate short name")
check(profile.slots[1] == nil and profile.slots[2] == "Cara-Other", "RaidGroupsEdit duplicate removal uses Players")
check(Edit.placedNames(profile).cara == true, "RaidGroupsEdit placedNames uses Players")

GuildRoster._q.numMembers = function() return 1 end
GuildRoster._q.info = function() return " Dori-Realm ", nil, nil, 70, nil, nil, nil, nil, true, nil, "DRUID" end
local guild = GuildRoster:List()
check(guild[1] and guild[1].name == "Dori", "RaidGroupsGuildRoster list uses Players")

print(("small_modules_players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
