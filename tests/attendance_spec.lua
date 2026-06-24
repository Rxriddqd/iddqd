local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local now = 1000
function time() return now end

ns.modules.DB = { db = { settings = { attendance = { enabled = 3 } } } }

function IsInRaid() return true end
function GetNumGroupMembers() return 6 end
function GetRaidRosterInfo(i)
    local rows = {
        { "Alice-Realm", 1 },
        { "Bob-Realm", 1 },
        { "Cara-Realm", 2 },
        { "Dori-Realm", 2 },
        { "Eve-Realm", 2 },
        { "Finn-Realm", 8 },
    }
    local row = rows[i]
    if row then return row[1], nil, row[2], nil, nil, "MAGE" end
end
function GetInstanceInfo() return "Karazhan", "raid", 3, "10 Player", 10, nil, nil, 532 end

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
local Attendance = assert(loadfile(DIR .. "Modules/Attendance/Attendance.lua"))("iddqd", ns)

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local groups, members, classes = Attendance:CurrentRaidGroups()
check(#members == 6, "CurrentRaidGroups returns all members")
check(groups[1][1] == "Alice" and groups[1][2] == "Bob", "group 1 preserves raid group slots")
check(groups[2][1] == "Cara" and groups[2][3] == "Eve", "group 2 preserves raid group slots")
check(groups[8][1] == "Finn", "group 8 is captured")
check(classes.Alice == "MAGE" and classes.Finn == "MAGE", "CurrentRaidGroups captures class files")

local snap = Attendance:TakeSnapshot("manual")
check(snap and #snap.members == 6, "TakeSnapshot stores flat members")
check(snap.groups and snap.groups[2][1] == "Cara", "TakeSnapshot stores grouped members")
check(snap.classes and snap.classes.Cara == "MAGE", "TakeSnapshot stores class metadata")
local exported = Attendance:ExportSnapshot(snap)
check(exported and exported:find("iddqd Attendance Snapshot", 1, true), "ExportSnapshot writes a header")
check(exported and exported:find("Group 2", 1, true) and exported:find("1\tCara\tMAGE", 1, true), "ExportSnapshot writes grouped class rows")

check(Attendance:SnapshotMode() == "every_pull", "legacy numeric mode migrates to string mode")
Attendance:SetSnapshotMode("first_pull")
check(Attendance:TryAutoSnapshot("pull", "Open World Mob") == nil, "auto snapshots ignore missing encounter difficulty")
check(Attendance:TryAutoSnapshot("kill", "Attumen", 3) == nil, "first-pull mode ignores kill triggers")
check(Attendance:TryAutoSnapshot("pull", "Attumen", 3) ~= nil, "first-pull mode snapshots first raid pull")
check(Attendance:TryAutoSnapshot("pull", "Moroes", 3) == nil, "first-pull mode ignores later pulls in the same raid")

Attendance:SetSnapshotMode("every_kill")
local before = #Attendance:Snapshots()
now = 2000
Attendance:OnKill("Attumen", 3)
Attendance:OnKill("Attumen", 3)
check(#Attendance:Snapshots() == before + 1, "OnKill debounces duplicate kill events")
now = 2010
Attendance:OnKill("Moroes", 3)
check(#Attendance:Snapshots() == before + 2, "OnKill allows a later kill snapshot")

print(("attendance_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
