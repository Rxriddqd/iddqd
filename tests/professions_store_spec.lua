local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
ns.professionRecipeDB = {
    skillLines = { [333]="Enchanting", [202]="Engineering", [356]="Fishing" },
    bySpellId  = { [7421]={p=333,i=38682}, [7795]={p=333}, [7428]={p=333,i=38679} },
    byEffectId = { [25]=3449 },
    byItemId   = { [38679] = { [333] = 7428 } },
}
function GetSpellInfo(id)
    if id == 7428 then return "Enchant Bracer - Healing Power" end
    return "Spell " .. tostring(id)
end
function time() return 1000 end

ns.modules.DB = { db = {} }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Store.lua"))("iddqd", ns)
local Store = ns:GetModule("ProfessionsStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local p = Store:Get()
check(type(p) == "table", "Get returns a table")
check(p.protocolVersion == 7, "Get initialises protocolVersion to 7")
check(type(p.profiles) == "table", "Get creates profiles table")

ns.modules.DB.db.professions = { protocolVersion = 5, profiles = { ["Old-Realm"] = {} } }
Store:MigrateOrReset()
check(ns.modules.DB.db.professions.protocolVersion == 7, "MigrateOrReset bumps to 7")
check(next(ns.modules.DB.db.professions.profiles) == nil, "MigrateOrReset wipes old profiles")

ns.modules.DB.db.professions = { protocolVersion = 7, profiles = { ["Keep-Realm"] = { key="Keep-Realm" } } }
Store:MigrateOrReset()
check(ns.modules.DB.db.professions.profiles["Keep-Realm"] ~= nil, "MigrateOrReset preserves current-version profiles")

local h1 = Store:ProfessionHash({7795, 7421}, 300, 300)
local h2 = Store:ProfessionHash({7421, 7795}, 300, 300)
check(h1 == h2, "ProfessionHash is order-independent")
check(Store:ProfessionHash({7421}, 300, 300) ~= Store:ProfessionHash({7421}, 299, 300), "ProfessionHash is rank-sensitive")
check(type(h1) == "string" and #h1 > 0, "ProfessionHash returns a non-empty string")
check(Store:ProfessionHash({7421, 7795}, 300, 300) == "1865756657", "ProfessionHash golden value is stable (protocol contract)")

-- reset to a clean store for profile tests
ns.modules.DB.db.professions = nil
Store:Get()

-- LocalProfile creation
function UnitName() return "Nesi" end
function GetNormalizedRealmName() return "Spineshatter" end
function GetRealmName() return "Spineshatter" end
UnitClass = function() return "Mage", "MAGE" end
local lp = Store:LocalProfile()
check(lp ~= nil and lp.key == "Nesi-Spineshatter", "LocalProfile builds key Name-Realm")
check(lp.source == "owner", "LocalProfile is owner source")
check(lp.class == "MAGE", "LocalProfile captures class file from UnitClass")

-- SetProfession writes spellIds + hash
Store:SetProfession("Nesi-Spineshatter", "Enchanting", { skillLineId=333, spellIds={7421,7795}, rank=300, maxRank=300 }, "owner")
local prof = Store:Profile("Nesi-Spineshatter").professions["Enchanting"]
check(prof.hash == Store:ProfessionHash({7421,7795}, 300, 300), "SetProfession computes canonical hash")
check(#prof.spellIds == 2, "SetProfession stores spellIds")

-- owner is not overwritten by older cache
Store:SetProfession("Nesi-Spineshatter", "Enchanting", { skillLineId=333, spellIds={7421}, rank=300, maxRank=300, updatedAt=1 }, "cache")
check(#Store:Profile("Nesi-Spineshatter").professions["Enchanting"].spellIds == 2, "older cache does not overwrite owner data")
Store:SetProfession("Nesi-Spineshatter", "Enchanting", { skillLineId=333, spellIds={7421}, rank=300, maxRank=300, updatedAt=999999 }, "cache")
check(#Store:Profile("Nesi-Spineshatter").professions["Enchanting"].spellIds == 2, "newer-timestamp cache STILL does not overwrite owner data")
check(Store:Profile("Nesi-Spineshatter").professions["Enchanting"].source == "owner", "owner source preserved after cache attempts")

-- Manifest reflects stored hashes
local man = Store:Manifest()
check(man.key == "Nesi-Spineshatter", "Manifest carries key")
check(man.professions["Enchanting"] == prof.hash, "Manifest carries per-profession hash")

-- NeedsUpdate compares hashes
check(Store:NeedsUpdate("Nesi-Spineshatter", "Enchanting", prof.hash) == false, "NeedsUpdate false when hash matches")
check(Store:NeedsUpdate("Nesi-Spineshatter", "Enchanting", "different") == true, "NeedsUpdate true when hash differs")
check(Store:NeedsUpdate("Ghost-Realm", "Enchanting", "x") == true, "NeedsUpdate true when profile absent")

-- static lookups
check(Store:ResolveSpellId(7421) == 7421, "ResolveSpellId passes through known spellId")
check(Store:ResolveSpellId(25) == 3449, "ResolveSpellId maps effectId via byEffectId")
check(Store:ResolveSpellId(999999) == nil, "ResolveSpellId returns nil for unmapped id")
local meta = Store:RecipeMeta(7421)
check(meta and meta.itemId == 38682 and meta.skillLine == 333, "RecipeMeta returns item + skill line")

-- ResolveSpellIdByItem
check(Store:ResolveSpellIdByItem(38679, 333) == 7428, "ResolveSpellIdByItem resolves crafted item to spell for the skill line")
check(Store:ResolveSpellIdByItem(38679, nil) == 7428, "ResolveSpellIdByItem resolves with nil skill line (any)")
check(Store:ResolveSpellIdByItem(999999, 333) == nil, "ResolveSpellIdByItem nil for unknown item")

-- ResolveSpellIdByName
check(Store:ResolveSpellIdByName("Enchanting", "Enchant Bracer - Healing Power") == 7428, "ResolveSpellIdByName resolves by localized recipe name")
check(Store:ResolveSpellIdByName("Enchanting", "No Such Enchant") == nil, "ResolveSpellIdByName nil for unknown name")

-- KnownProfessionNames: distinct names across profiles, primaries before secondaries
ns.modules.DB.db.professions = nil
Store:Get()
Store:SetProfession("A-Realm", "Enchanting", { skillLineId=333, spellIds={7421}, rank=1, maxRank=1 }, "owner")
Store:SetProfession("A-Realm", "Cooking",    { skillLineId=185, spellIds={}, rank=1, maxRank=1 }, "owner")
Store:SetProfession("B-Realm", "Alchemy",    { skillLineId=171, spellIds={7421}, rank=1, maxRank=1 }, "owner")
Store:SetProfession("B-Realm", "Enchanting", { skillLineId=333, spellIds={7421}, rank=1, maxRank=1 }, "owner")
local names = Store:KnownProfessionNames()
local seen = {}; for _, n in ipairs(names) do check(not seen[n], "KnownProfessionNames distinct: " .. n); seen[n] = true end
check(seen["Enchanting"] and seen["Alchemy"] and seen["Cooking"], "KnownProfessionNames includes all professions")
local cookingIdx, lastPrimaryIdx = nil, 0
for i, n in ipairs(names) do
    if n == "Cooking" then cookingIdx = i elseif n == "Alchemy" or n == "Enchanting" then lastPrimaryIdx = i end
end
check(cookingIdx and cookingIdx > lastPrimaryIdx, "secondary professions sort after primaries")

-- HasCachedProfession: true only when we hold a copy at the matching hash
ns.modules.DB.db.professions = nil
Store:Get()
Store:SetProfession("Owner-Realm", "Alchemy", { skillLineId=171, spellIds={100,200}, rank=300, maxRank=300 }, "cache")
local hcp = Store:Profile("Owner-Realm").professions["Alchemy"].hash
check(Store:HasCachedProfession("Owner-Realm", "Alchemy", hcp) == true, "HasCachedProfession true at matching hash")
check(Store:HasCachedProfession("Owner-Realm", "Alchemy", "wronghash") == false, "false at non-matching hash")
check(Store:HasCachedProfession("Ghost-Realm", "Alchemy", hcp) == false, "false when we have no copy")
check(Store:HasCachedProfession("Owner-Realm", "Tailoring", hcp) == false, "false for a profession we don't have")

print(("professions_store_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
