local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

function time() return 1000 end
ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Store.lua"))("iddqd", ns)

local Store = ns:GetModule("LootDistStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(Store:ListId(nil, 30029, " Bob-SpineShatter ", 1000) == "30029:bob:33", "ListId uses shared short-name normalization")

Store:EnsureEntry("R", { itemId = 1 })
Store:SetResponse("R", " Bob-SpineShatter ", "WARRIOR", "upgrade", "", 10)
Store:SetResponse("R", "bob-OtherRealm", "WARRIOR", "minor", "", 20)
check(Store:Entries()["R"].responses["bob"].response == "minor", "responses share one short-name key")

Store:SetQuantity("R", 2)
check(Store:SetAward("R", " Bob-SpineShatter ", "Officer", 30) == true, "first normalized award succeeds")
check(Store:SetAward("R", "bob-OtherRealm", "Officer", 40) == false, "duplicate short-name award is rejected")

print(("loot_dist_players_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
