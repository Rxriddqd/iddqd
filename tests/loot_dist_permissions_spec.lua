local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

local leader, assist, guildRank = false, false, nil
function UnitIsGroupLeader() return leader end
function UnitIsGroupAssistant() return assist end
function UnitName() return "Sylo" end
function GetGuildInfo() return "iddqd", "Rank", guildRank end

ns.modules.DB = { db = { settings = { lootSettings = {} } } }
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Detect.lua"))("iddqd", ns)
local Detect = ns:GetModule("LootDistDetect")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end
local function role(l, a, r) leader, assist, guildRank = l, a, r end

Detect:SetDistributePolicy("assist")
role(false, false, nil)
check(Detect:CanDistributeLoot() == false, "assist policy rejects plain raider")
role(false, true, nil)
check(Detect:CanDistributeLoot() == true, "assist policy allows raid assist")
role(true, false, nil)
check(Detect:CanDistributeLoot() == true, "assist policy allows raid leader")

Detect:SetDistributePolicy("leader")
role(false, true, 0)
check(Detect:CanDistributeLoot() == false, "leader policy rejects assist even with guild rank")
role(true, false, 9)
check(Detect:CanDistributeLoot() == true, "leader policy allows raid leader")

Detect:SetDistributePolicy("guild", 2)
role(false, false, 1)
check(Detect:CanDistributeLoot() == true, "guild policy allows sufficient guild rank")
role(false, false, 3)
check(Detect:CanDistributeLoot() == false, "guild policy rejects lower guild rank")
role(true, false, 9)
check(Detect:CanDistributeLoot() == true, "guild policy always allows raid leader")

Detect:SetDistributePolicy("assist_and_guild", 2)
role(false, true, 1)
check(Detect:CanDistributeLoot() == true, "assist_and_guild allows assist with sufficient rank")
role(false, true, 3)
check(Detect:CanDistributeLoot() == false, "assist_and_guild rejects assist with low rank")
role(false, false, 1)
check(Detect:CanDistributeLoot() == false, "assist_and_guild rejects ranked non-assist")
role(true, false, 9)
check(Detect:CanDistributeLoot() == true, "assist_and_guild always allows raid leader")

Detect:SetDistributePolicy("assist_or_guild", 2)
role(false, true, 9)
check(Detect:CanDistributeLoot() == true, "assist_or_guild allows assist without rank")
role(false, false, 1)
check(Detect:CanDistributeLoot() == true, "assist_or_guild allows sufficient rank without assist")
role(false, false, 3)
check(Detect:CanDistributeLoot() == false, "assist_or_guild rejects raider without assist or rank")

Detect:SetDistributePolicy("nonsense")
check(Detect:DistributePolicy() == "assist", "invalid policy normalizes to assist")

print(("loot_dist_permissions_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
