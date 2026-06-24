local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local sent = {}
C_ChatInfo = {
    SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
    end,
}
function GetNumGroupMembers() return 5 end
function IsInRaid() return true end
function GetRaidRosterInfo(i)
    if i == 1 then return "Lead-Realm", 2 end
    if i == 2 then return "Sylo-Realm", 0 end
    return "Raider" .. tostring(i) .. "-Realm", 0
end
function UnitName() return "Sylo" end
function time() return 1000 end
function GetTime() return 1000.25 end

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

ns.modules.DB = { db = {} }
ns.modules.LootActivePanel = { Refresh = function() ns.panelRefreshes = (ns.panelRefreshes or 0) + 1 end }

assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Detect.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Sync.lua"))("iddqd", ns)
local Sync = ns:GetModule("LootDistSync")
local Store = ns:GetModule("LootDistStore")
local Detect = ns:GetModule("LootDistDetect")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

Store:EnsureEntry("R1", { itemId = 1001 })
Store:SetResponse("R1", "Sylo", "WARRIOR", "upgrade", "", 900)

sent = {}
Sync:BroadcastClearResponse("R1")
check(#sent == 1, "BroadcastClearResponse sends one addon message")
check(sent[1] and sent[1].prefix == "IDDQD_LDIST1", "clear response uses loot distribution prefix")
check(sent[1] and sent[1].channel == "RAID", "clear response sends to raid")
check(sent[1] and sent[1].msg:find("^LDRESPDEL1|1|R1|Sylo|1000%.25$") ~= nil, "clear response payload preserves sub-second timestamp")

Sync:OnAddonMessage("IDDQD_LDIST1", "LDRESPDEL1|1|R1|Sylo|1000.25", "RAID", "Sylo-Realm")
check(Store:Entries()["R1"].responses["sylo"] == nil, "LDRESPDEL1 clears the stored response")
check((ns.panelRefreshes or 0) > 0, "LDRESPDEL1 refreshes the loot panel")

Store:SetResponse("R1", "Sylo", "WARRIOR", "bis", "", 950)
check(Store:Entries()["R1"].responses["sylo"] == nil, "older LDRESP1 cannot resurrect after clear")

sent = {}
Sync:BroadcastPolicy("assist_or_guild", 2)
check(#sent == 1 and sent[1].msg == "LDPERM1|1|assist_or_guild|2", "BroadcastPolicy includes guild-rank threshold")

Detect:SetDistributePolicy("assist", 2)
Sync:OnAddonMessage("IDDQD_LDIST1", "LDPERM1|1|guild|1", "RAID", "Lead-Realm")
check(Detect:DistributePolicy() == "guild" and Detect:DistributeGuildRank() == 1, "leader LDPERM1 applies guild policy + rank")
Sync:OnAddonMessage("IDDQD_LDIST1", "LDPERM1|1|leader|3", "RAID", "Sylo-Realm")
check(Detect:DistributePolicy() == "guild" and Detect:DistributeGuildRank() == 1, "non-leader LDPERM1 is ignored")

print(("loot_dist_sync_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
