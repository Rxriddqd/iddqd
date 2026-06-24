local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
local debugLines = {}
function ns:Debug(...) debugLines[#debugLines + 1] = table.concat({...}, " ") end
function ns:Print() end
function time() return 1000 end
function UnitName() return "Nesi" end
function GetNormalizedRealmName() return "Spineshatter" end
function GetRealmName() return "Spineshatter" end
UnitClass = function() return "Mage", "MAGE" end
ns.professionRecipeDB = {
    skillLines = { [333]="Enchanting", [202]="Engineering" },
    bySpellId  = { [7421]={p=333,i=38682}, [7795]={p=333}, [3978]={p=202}, [7428]={p=333,i=38679} },
    byEffectId = { [32]=3978 },
    byItemId   = { [38679] = { [333] = 7428 } },
}
function GetSpellInfo(id)
    if id == 7428 then return "Enchant Bracer - Healing Power" end
    return "Spell " .. tostring(id)
end

ns.modules.DB = { db = {} }
assert(loadfile(DIR .. "Modules/Professions/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Scanner.lua"))("iddqd", ns)
local Scanner = ns:GetModule("ProfessionsScanner")
local Store = ns:GetModule("ProfessionsStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

local rows = {
    { name = "Enchant Bracer", recipeLink = "spell:7421", itemLink = "item:38682" },
    { name = "Some Enchant",   recipeLink = "spell:32",   itemLink = nil },
    { name = "Header Skipped", recipeType = "header" },
    { name = "Unknown Craft",  recipeLink = "spell:999999", itemLink = "item:55555" },
}
local spellIds, unmapped = Scanner:ResolveRows(rows, "Enchanting", 333)
check(#spellIds == 2, "ResolveRows returns 2 mapped spell ids (header + unmapped skipped)")
check(spellIds[1] == 3978 and spellIds[2] == 7421, "resolved ids sorted: effectId-mapped 3978 and direct 7421")
local has999 = false; for _,v in ipairs(spellIds) do if v == 999999 then has999 = true end end
check(not has999, "unmapped recipe excluded from spellIds")
check(unmapped == 1, "one unmapped recipe counted")
local logged = false; for _,l in ipairs(debugLines) do if l:find("unmapped") then logged = true end end
check(logged, "unmapped recipe is debug-logged")

local changed = Scanner:CommitScan("Enchanting", 300, 300, 333, spellIds, unmapped)
check(changed == true, "first commit reports a change")
local prof = Store:LocalProfile().professions["Enchanting"]
check(prof and #prof.spellIds == 2, "committed two mapped spell ids")
check(prof.unmappedCount == 1, "unmappedCount stored")

local changed2 = Scanner:CommitScan("Enchanting", 300, 300, 333, spellIds, unmapped)
check(changed2 == false, "identical re-scan reports no change")

-- CanonicalProfession derives English name + skillLineId from resolved spell ids (locale-independent)
local cname, cline = Scanner:CanonicalProfession({7421, 7795}, "LocalizedName")
check(cname == "Enchanting" and cline == 333, "CanonicalProfession derives English name + skillLineId from spell ids")
check(Scanner:CanonicalProfession({}, "Fallback") == "Fallback", "CanonicalProfession falls back when no ids resolve")

-- ReadOpenProfession expands a collapsed header so its recipe becomes visible
local expandedHeaders = {}
local skills = {
    { name = "Cat A", recipeType = "header", expanded = false },  -- collapsed; expanding reveals index 2
    { name = "Bracer", recipeType = "trade" },
}
GetNumTradeSkills = function() return #skills end
GetTradeSkillInfo = function(i) local s = skills[i]; if not s then return nil end; return s.name, s.recipeType, nil, s.expanded end
GetTradeSkillRecipeLink = function(i) return skills[i] and skills[i].recipeType ~= "header" and "spell:7421" or nil end
GetTradeSkillItemLink = function(i) return nil end
GetTradeSkillLine = function() return "Verzauberkunst", 300, 300 end  -- localized name
ExpandTradeSkillSubClass = function(i) expandedHeaders[i] = true; if skills[i] then skills[i].expanded = true end end
local rrows, rname, rrank, rmax = Scanner:ReadOpenProfession()
check(expandedHeaders[1] == true, "ReadOpenProfession expands a collapsed header")
check(rname == "Verzauberkunst" and rrank == 300, "ReadOpenProfession returns localized name + rank (canonicalized later)")
check(#rrows == 2, "ReadOpenProfession reads all rows after expansion")

-- Regression: Craft-frame recipe with NO parseable link resolves by NAME (the Enchanting bug)
local craftRows = {
    { name = "Enchant Bracer - Healing Power", recipeLink = nil, itemLink = nil },   -- resolves by name -> 7428
    { name = "Some Rod", recipeLink = nil, itemLink = "item:38679" },                -- resolves by item -> 7428 (dup, deduped)
    { name = "Totally Unknown Enchant", recipeLink = nil, itemLink = nil },          -- genuinely unmapped
}
local cids, cunmapped = Scanner:ResolveRows(craftRows, "Enchanting", 333)
local has7428 = false; for _,v in ipairs(cids) do if v == 7428 then has7428 = true end end
check(has7428, "regression: name-resolvable craft recipe maps to spell 7428")
check(cunmapped == 1, "regression: only the truly-unknown craft recipe is unmapped")

-- Fishing resolve from skill-line rows (pure)
local function L(name, isHeader, isExpanded, rank, maxRank) return { name=name, isHeader=isHeader, isExpanded=isExpanded, rank=rank, maxRank=maxRank } end
local r1, m1 = Scanner:ResolveFishingFromSkillLines({ L("Cooking",false,false,1,1), L("Fishing",false,false,225,300) })
check(r1 == 225 and m1 == 300, "resolves fishing rank from a flat list")
local r2, m2 = Scanner:ResolveFishingFromSkillLines({ L("Secondary Skills",true,true), L("Fishing",false,false,75,150) })
check(r2 == 75 and m2 == 150, "skips headers and resolves fishing")
local r3 = Scanner:ResolveFishingFromSkillLines({ L("Cooking",false,false,300,300) })
check(r3 == nil, "no fishing -> nil")
local r4 = Scanner:ResolveFishingFromSkillLines({ L("Fishing",false,false,0,0) })
check(r4 == nil, "fishing rank 0 -> nil")
PROFESSIONS_FISHING = "Angeln"
local r5, m5 = Scanner:ResolveFishingFromSkillLines({ L("Angeln",false,false,150,225) })
check(r5 == 150 and m5 == 225, "localized fishing name resolves")
PROFESSIONS_FISHING = nil
check(Scanner:ResolveFishingFromSkillLines(nil) == nil, "nil rows -> nil")

print(("professions_scanner_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
