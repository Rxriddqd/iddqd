local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"
local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 1000 end
ns.modules.DB = { db = { settings = {}, raidMapPins = {} } }

local function load(path) return assert(loadfile(DIR .. path))("iddqd", ns) end
local A  = load("Modules/Attendance/Attendance.lua")
local RA = load("Modules/RaidAssignments/RaidAssignments.lua")
local RM = load("Modules/RaidMap/RaidMap.lua")
local VN = load("Modules/VisualNote/VisualNote.lua")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

-- Attendance ----------------------------------------------------------------
A.CurrentRoster   = function() return { "Alice", "Bob", "Cara" } end
A.CurrentInstance = function() return "Karazhan" end
local snap = A:TakeSnapshot()
check(snap ~= nil and #snap.members == 3, "TakeSnapshot records the roster")
check(snap.instance == "Karazhan", "snapshot captures instance")
check(snap.groups and snap.groups[1] and snap.groups[1][1] == "Alice", "snapshot stores raid groups")
check(#A:Snapshots() == 1, "snapshot stored")
A:TakeSnapshot()
check(#A:Snapshots() == 2 and A:Snapshots()[1].at ~= nil, "newest-first ordering")
A:SetSnapshotMode("every_kill")
check(A:SnapshotMode() == "every_kill" and A:ShouldAutoSnapshot("kill", 3) == true, "attendance auto mode supports every kill")
A:SetSnapshotMode("first_pull")
check(A:ShouldAutoSnapshot("pull", 3) == true, "attendance first-pull mode starts eligible")
A:_markAutoSeen("pull")
check(A:ShouldAutoSnapshot("pull", 3) == false, "attendance first-pull mode dedupes per raid")
A:DeleteSnapshot(1)
check(#A:Snapshots() == 1, "DeleteSnapshot removes one")
A:Clear()
check(#A:Snapshots() == 0, "Clear empties snapshots")

-- RaidAssignments -----------------------------------------------------------
local set = RA:CreateSet("Night 1")
check(set ~= nil and set.id ~= nil, "CreateSet returns a set with id")
check(RA:Selected() and RA:Selected().id == set.id, "new set becomes selected")
RA:SetNote(set.id, "Tanks: Bob")
check(RA:GetSet(set.id).note == "Tanks: Bob", "SetNote persists")
RA:RenameSet(set.id, "Night 2")
check(RA:GetSet(set.id).name == "Night 2", "RenameSet")
local set2 = RA:CreateSet("Night 3")
check(#RA:Sets() == 2, "two sets")
RA:Select(set.id)
check(RA:Selected().id == set.id, "Select switches active set")
RA:DeleteSet(set.id)
check(RA:GetSet(set.id) == nil and #RA:Sets() == 1, "DeleteSet removes the set")
check(RA:Selected().id == set2.id, "selection falls back after delete")

-- RaidMap -------------------------------------------------------------------
RM.ZoneKey = function() return "Karazhan" end
local pin = RM:AddPin(nil, 0.25, 0.75, 8, nil)
check(#RM:Pins() == 1 and pin.marker == 8, "AddPin stores a marker pin")
check(pin.x == 0.25 and pin.y == 0.75, "pin coords stored")
RM:AddPin(nil, 0.5, 0.5, 0, "Note here")
check(#RM:Pins() == 2, "second pin added")
RM:RemovePin(nil, pin)
check(#RM:Pins() == 1, "RemovePin removes one")
RM:ClearZone()
check(#RM:Pins() == 0, "ClearZone empties the zone")
-- Different zones are independent.
RM.ZoneKey = function() return "Gruul's Lair" end
RM:AddPin(nil, 0.1, 0.1, 1)
RM.ZoneKey = function() return "Karazhan" end
check(#RM:Pins() == 0, "zones are independent")

-- VisualNote ----------------------------------------------------------------
VN:Set("line one\nline two")
check(VN:Get() == "line one\nline two", "VisualNote set/get round-trip")
VN:Set("")
check(VN:Get() == "", "VisualNote clear")

-- RaidAssignments addon-sync round-trip --------------------------------------
-- Capture what Share() broadcasts, then feed it to a second RA instance (another client).
do
    local sent = {}
    _G.ChatThrottleLib = { SendAddonMessage = function(_, _, _, msg) sent[#sent + 1] = msg end }
    _G.IsInRaid = function() return true end
    _G.GetNumGroupMembers = function() return 5 end
    _G.UnitName = function() return "Officer" end

    local mkSet = RA:CreateSet("Sync Test")
    local big = {}
    for i = 1, 30 do big[i] = ("Line %d: interrupt rotation + tank swaps"):format(i) end
    local note = table.concat(big, "\n")
    RA:SetNote(mkSet.id, note)
    check(RA:Share(mkSet.id) == true, "Share broadcasts the active set")
    check(#sent >= 3, "Share emits STR/DAT/END stream")

    -- Second client (fresh ns2/DB), receives the messages from "Officer".
    local ns2 = { modules = {} }
    function ns2:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
    function ns2:GetModule(n) return self.modules[n] end
    function ns2:Print() end
    function ns2:Debug() end
    ns2.modules.DB = { db = { settings = {} } }
    _G.UnitName = function() return "Raider" end
    local RA2 = assert(loadfile(DIR .. "Modules/RaidAssignments/RaidAssignments.lua"))("iddqd", ns2)
    for _, msg in ipairs(sent) do RA2:OnAddonMessage("IDDQD_RA1", msg, "RAID", "Officer") end
    check(#RA2:Sets() == 1, "receiver stores the synced set")
    check(RA2:Sets()[1].note == note, "synced note is an exact round-trip")
    -- Re-share overwrites (per-sender), no duplicate.
    for _, msg in ipairs(sent) do RA2:OnAddonMessage("IDDQD_RA1", msg, "RAID", "Officer") end
    check(#RA2:Sets() == 1, "re-share overwrites the synced set (no duplicate)")
end

print(("new_modules_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
