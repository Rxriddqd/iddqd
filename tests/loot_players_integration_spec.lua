local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
function date() return "now" end
function UnitName(unit) return unit == "player" and "Tester" or nil end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
function strsplit(sep, value)
    value = tostring(value or "")
    local out = {}
    for part in (value .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return table.unpack(out)
end

ns.modules.DB = { db = { raidLootLedger = { drops = {}, sessionCounter = 0 }, settings = { raidLootLedger = {} } } }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/LootLedger.lua"))("iddqd", ns)

local Ledger = ns:GetModule("LootLedger")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Ledger:IsLocalPlayerInDrop({ currentHolder = "Tester-Realm" }) == true, "local full name matches same realm")
check(Ledger:IsLocalPlayerInDrop({ currentHolder = "tester" }) == true, "short name remains compatible")
check(Ledger:IsLocalPlayerInDrop({ currentHolder = "Tester-OtherRealm" }) == false, "explicit cross-realm holder is not local player")

print(("loot_players_integration_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
