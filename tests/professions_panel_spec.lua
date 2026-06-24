local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"
local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end
function time() return 5000 end
function UnitName() return "Me" end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
UnitClass = function() return "Mage", "MAGE" end
function GetSpellInfo(id) return "Spell " .. tostring(id), nil, 123 end
-- Controllable GetItemInfo: itemId -> {name, quality, itemType, itemSubType, equipLoc, icon}
local ITEM_DB = {
    [501] = { "Deadly Blunderbuss", 2, "Weapon", "Guns", "INVTYPE_RANGED", 456 },
    [502] = { "Fel Iron Goggles", 3, "Armor", "Mail", "INVTYPE_HEAD", 456 },
    [503] = { "Hi-Impact Mithril Slugs", 1, "Projectile", "Bullet", "", 456 },
    [504] = { "Major Healing Potion", 1, "Consumable", "Potion", "", 456 },
    [505] = { "Mageweave Bag", 1, "Container", "Bag", "", 456 },
    [38682] = { "Major Healing Potion", 3, "Consumable", "Potion", "", 456 },
    [38679] = { "Runed Arcanite Rod", 3, "Trade Goods", "Devices", "", 456 },
}
function GetItemInfo(idOrName)
    local row = ITEM_DB[tonumber(idOrName)]
    if not row then return nil end  -- uncached
    -- WoW signature: name(1) link(2) quality(3) iLevel(4) reqLevel(5) type(6) subType(7) stack(8) equipLoc(9) icon(10)
    return row[1], nil, row[2], nil, nil, row[3], row[4], nil, row[5], row[6]
end
ns.professionRecipeDB = { skillLines={[333]="Enchanting"}, bySpellId={[100]={p=333,i=38682},[200]={p=333}}, byEffectId={} }
ns.modules.DB = { db = {} }
assert(loadfile(DIR .. "Modules/Professions/Store.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Professions/Panel.lua"))("iddqd", ns)
local Panel = ns:GetModule("ProfessionsPanel")
local Store = ns:GetModule("ProfessionsStore")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

Store:SetProfession("Al-Realm", "Enchanting", { skillLineId=333, spellIds={100,200}, rank=300, maxRank=300 }, "owner")
local rows = Panel:RecipeRows()
check(#rows >= 2, "RecipeRows lists stored recipes resolved from spellIds")
local hasName = false; for _,r in ipairs(rows) do if r.name and r.name ~= "" then hasName = true end end
check(hasName, "rows resolve a display name via GetSpellInfo")
-- each row carries the player + profession + sync state for honest display
local r1 = rows[1]
check(r1.player and r1.professionName == "Enchanting", "row carries player + professionName")

-- filtering by profession
local none = Panel:RecipeRows(nil, "Tailoring")
check(#none == 0, "profession filter excludes other professions")
-- search filter
local searched = Panel:RecipeRows("Spell 100", nil)
check(#searched >= 1, "search filter matches by name")

-- sync-state label mapping is pure and testable
check(Panel:SyncStateLabel("synced", 5000):find("Synced") ~= nil, "synced label")
check(Panel:SyncStateLabel("pending"):find("Syncing") ~= nil, "pending label says Syncing")
check(Panel:SyncStateLabel("waiting"):find("Waiting") ~= nil, "waiting label")
check(Panel:SyncStateLabel("unavailable"):find("Unavailable") ~= nil, "unavailable label")
check(Panel:SyncStateLabel("synced", 4900):find("ago") ~= nil or Panel:SyncStateLabel("synced", 4900):find("just now") ~= nil, "synced label shows relative freshness when timestamp given")
check(Panel:SyncStateLabel("synced"):find("Synced") ~= nil, "synced label without timestamp is plain 'Synced'")

-- button actions are safe no-ops when their target modules are absent (they just shouldn't error)
local ok = pcall(function() Panel:OnScanClicked(); Panel:OnShareClicked(); Panel:OnRequestSyncClicked() end)
check(ok, "button actions do not error when sync/scanner modules absent")

-- Refresh is a safe no-op when no frame is bound (UI not built in tests)
local ok2 = pcall(function() Panel:Refresh() end)
check(ok2, "Refresh is a safe no-op without a bound frame")

-- RecipeRows now also carries profile + nested recipe for grouping
local rows2 = Panel:RecipeRows()
local r = rows2[1]
check(r.profile and r.professionName == "Enchanting", "row carries profile + professionName")
check(r.recipe and (r.recipe.recipeId == 100 or r.recipe.recipeId == 200), "row carries a recipe with recipeId")
check(r.recipe.recipeLink == ("spell:" .. tostring(r.recipe.recipeId)), "recipe has spell link")

-- FishingRows: rank-based, not recipe-based
Store:SetProfession("Fisher-Realm", "Fishing", { skillLineId=356, spellIds={}, rank=225, maxRank=300 }, "owner")
local frows = Panel:FishingRows()
check(#frows >= 1, "FishingRows lists fishing characters")
check(frows[1].rank ~= nil and frows[1].maxRank ~= nil, "fishing row carries rank/maxRank")
check(frows[1].professionName == "Fishing", "fishing row professionName is Fishing")
-- Fishing is excluded from RecipeRows
local allRows = Panel:RecipeRows()
for _, rr in ipairs(allRows) do check(rr.professionName ~= "Fishing", "RecipeRows excludes Fishing") end

-- Categorization (name-based, ported from old panel)
local function cat(prof, name, itemName) return Panel:Category(prof, { name = name, itemName = itemName }) end
check(cat("Enchanting", "Enchant Gloves - Major Strength") == "Gloves", "enchant gloves -> Gloves")
check(cat("Enchanting", "Enchant 2H Weapon - Major Agility") == "Two-Hand Weapon", "enchant 2H -> Two-Hand Weapon")
check(cat("Enchanting", "Enchant Cloak - Greater Defense") == "Cloak", "enchant cloak -> Cloak")
check(cat("Alchemy", nil, "Major Healing Potion") == "Potion", "alchemy potion -> Potion")
check(cat("Alchemy", nil, "Flask of Supreme Power") == "Flask", "alchemy flask -> Flask")
check(cat("Alchemy", nil, "Transmute: Arcanite") == "Transmute", "alchemy transmute -> Transmute")
check(cat("Blacksmithing", nil, "Ornate Bronze Bracers") == "Wrist", "blacksmith bracers -> Wrist")
check(cat("Tailoring", nil, "Mageweave Bag") == "Bag", "tailoring bag -> Bag")
check(cat("Cooking", nil, "Grilled Squid") == "Food", "cooking -> Food")
check(cat("Engineering", nil, "Goblin Sapper Charge") == "Explosive", "engineering bomb -> Explosive")
check(cat("UnknownProf", "whatever", "whatever") == "Other", "unknown profession -> Other")

-- Grouping
ns.modules.DB.db.professions = nil
Store:Get()
Store:SetProfession("P1-Realm", "Alchemy", { skillLineId=171, spellIds={100}, rank=300, maxRank=300 }, "owner")
Store:SetProfession("P2-Realm", "Alchemy", { skillLineId=171, spellIds={100}, rank=300, maxRank=300 }, "owner")
Store:SetProfession("P3-Realm", "Alchemy", { skillLineId=171, spellIds={200}, rank=300, maxRank=300 }, "owner")
-- distinct item names so 100 and 200 are different crafts and categorize differently
GetItemInfo = function(id)
    if tonumber(id) == 38682 then return "Major Healing Potion", nil, 3, nil, nil, "Consumable", "Potion", nil, "", 456 end
    return "Flask of Supreme Power", nil, 3, nil, nil, "Consumable", "Flask", nil, "", 456
end
local arows = Panel:RecipeRows(nil, "Alchemy")
local groups = Panel:BuildCraftGroups(arows)
check(#groups == 2, "two distinct crafts -> two groups")
local potionGroup
for _, g in ipairs(groups) do if (g.recipe.itemName or ""):find("Potion") then potionGroup = g end end
check(potionGroup and #potionGroup.makers == 2, "shared craft collapses to one group with 2 makers")
check(potionGroup and potionGroup.category == "Potion", "grouped potion craft has category Potion")

local display = Panel:BuildDisplayGroups(groups, {})
local headerCount, craftCount = 0, 0
for _, d in ipairs(display) do
    if d.kind == "category" then headerCount = headerCount + 1 elseif d.kind == "craft" then craftCount = craftCount + 1 end
end
check(headerCount >= 1, "collapsed display has category headers")
check(craftCount == 0, "collapsed display hides craft rows")
local firstKey = display[1].key
local display2 = Panel:BuildDisplayGroups(groups, { [firstKey] = true })
local expandedCrafts = 0
for _, d in ipairs(display2) do if d.kind == "craft" then expandedCrafts = expandedCrafts + 1 end end
check(expandedCrafts == 1, "expanding one category reveals exactly its 1 craft row")

-- Restore table-driven stub before type-based tests (grouping section overrides GetItemInfo above)
GetItemInfo = function(idOrName)
    local row = ITEM_DB[tonumber(idOrName)]
    if not row then return nil end
    return row[1], nil, row[2], nil, nil, row[3], row[4], nil, row[5], row[6]
end

-- Type-based categorization (item-bearing professions)
check(Panel:Category("Engineering", { itemId = 501 }) == "Gun", "weapon/Guns -> Gun")
check(Panel:Category("Engineering", { itemId = 502 }) == "Head", "equipLoc HEAD -> Head")
check(Panel:Category("Engineering", { itemId = 503 }) == "Ammo", "Projectile/Bullet -> Ammo")
check(Panel:Category("Alchemy", { itemId = 504 }) == "Potion", "Consumable/Potion -> Potion")
check(Panel:Category("Tailoring", { itemId = 505 }) == "Bag", "Container -> Bag")
check(Panel:Category("Engineering", { itemId = 999 }) == "Loading", "uncached item -> Loading")
check(Panel:Category("Engineering", { }) == "Other", "no itemId -> Other")
check(Panel:Category("Enchanting", { name = "Enchant Gloves - Major Strength" }) == "Gloves", "enchanting still uses slot parse")
check(Panel:Category("Enchanting", { name = "Enchant Bracer - Stats", itemId = 99999 }) == "Bracer", "Enchanting bypasses the itemId path (never Loading/Other)")

print(("professions_panel_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
