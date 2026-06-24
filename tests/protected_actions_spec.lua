local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function UnitName(unit) if unit == "player" then return "Sylo" end end
function GetNormalizedRealmName() return "SpineShatter" end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end

local initiated, used = 0, 0
function InitiateTrade() initiated = initiated + 1 end
C_Container = {
    UseContainerItem = function() used = used + 1 end,
}

ns.modules.DB = { db = { lootDistribution = {}, settings = { lootSettings = { distributePermission = "leader" } } } }
assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Detect.lua"))("iddqd", ns)

local Store = ns:GetModule("LootDistStore")
local Detect = ns:GetModule("LootDistDetect")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

Store:EnsureEntry("A1", {
    itemId = 9001,
    itemName = "Test Item",
    itemLink = "|cff1eff00|Hitem:9001::::::::|h[Test Item]|h|r",
})

Detect:Award("A1", "Target")
check(initiated == 0, "Award reminder does not call protected InitiateTrade")

Detect.outstanding = {
    target = { id = "A1", itemId = 9001, itemLink = "|cff1eff00|Hitem:9001::::::::|h[Test Item]|h|r" },
}
Detect:PlacePending("target")
check(used == 0, "Trade reminder does not call protected UseContainerItem")

print(("protected_actions_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
