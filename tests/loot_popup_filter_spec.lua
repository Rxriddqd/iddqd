local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Print() end
function ns:Debug() end

ns.modules.DB = { db = { settings = { lootSettings = { smartMiniLootFilter = true } } } }

local currentClass = "WARRIOR"
function UnitClass() return currentClass:sub(1, 1) .. currentClass:sub(2):lower(), currentClass end

local items = {
    [1001] = { "Healing Leather", "Armor", "Leather", "INVTYPE_CHEST", 4, { ITEM_MOD_HEALING_DONE_SHORT = 80, ITEM_MOD_INTELLECT_SHORT = 20 } },
    [1002] = { "Physical Leather", "Armor", "Leather", "INVTYPE_CHEST", 4, { ITEM_MOD_AGILITY_SHORT = 26, ITEM_MOD_ATTACK_POWER_SHORT = 52 } },
    [1003] = { "Plate Chest", "Armor", "Plate", "INVTYPE_CHEST", 4, { ITEM_MOD_STRENGTH_SHORT = 28 } },
    [1004] = { "Caster Wand", "Weapon", "Wands", "INVTYPE_RANGEDRIGHT", 2, { ITEM_MOD_SPELL_POWER_SHORT = 18 } },
    [1005] = { "Hunter Mail", "Armor", "Mail", "INVTYPE_CHEST", 4, { ITEM_MOD_AGILITY_SHORT = 24, ITEM_MOD_INTELLECT_SHORT = 18 } },
    [1006] = { "Healing Mail", "Armor", "Mail", "INVTYPE_CHEST", 4, { ITEM_MOD_HEALING_DONE_SHORT = 70, ITEM_MOD_MP5_SHORT = 8 } },
    [1007] = { "Tier Token", "Miscellaneous", "Junk", "", 15, nil },
    [30238] = { "Chestguard of the Vanquished Hero", "Miscellaneous", "Junk", "", 15, nil },
    [31091] = { "Chestguard of the Forgotten Protector", "Miscellaneous", "Junk", "", 15, nil },
}

function GetItemInfo(itemId)
    local it = items[itemId]
    if not it then return nil end
    return it[1], "|cffaa00ff[" .. it[1] .. "]|r", 4, 100, 70, it[2], it[3], 1, it[4], nil, nil, it[5]
end

function GetItemStats(itemId)
    local it = items[itemId]
    return it and it[6] or nil
end

assert(loadfile(DIR .. "Data/Static/TierTokens.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Store.lua"))("iddqd", ns)
local Popup = assert(loadfile(DIR .. "Modules/LootLedger/Distribution/Popup.lua"))("iddqd", ns)

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

currentClass = "WARRIOR"
check(Popup:ClassCanUse(1001) == false, "warrior does not see healing leather")
check(Popup:ClassCanUse(1002) == true, "warrior sees physical leather")
check(Popup:ClassCanUse(1004) == false, "warrior does not see wands")
check(Popup:ClassCanUse(9999) == true, "uncached items stay visible")

currentClass = "PALADIN"
check(Popup:ClassCanUse(1001) == true, "paladin sees healing leather")

currentClass = "PRIEST"
check(Popup:ClassCanUse(1003) == false, "priest does not see plate")
check(Popup:ClassCanUse(1004) == true, "priest sees wands")

currentClass = "HUNTER"
check(Popup:ClassCanUse(1005) == true, "hunter sees agility mail with intellect")
check(Popup:ClassCanUse(1006) == false, "hunter does not see healing mail")
check(Popup:ClassCanUse(1007) == true, "misc/token items stay visible")
check(Popup:ClassCanUse(30238) == true, "hunter sees Vanquished Hero token")
check(Popup:ClassCanUse(31091) == true, "hunter sees Forgotten Protector token")

currentClass = "WARRIOR"
check(Popup:ClassCanUse(30238) == false, "warrior does not see Vanquished Hero token")
check(Popup:ClassCanUse(31091) == true, "warrior sees Forgotten Protector token")

currentClass = "WARLOCK"
check(Popup:ClassCanUse(30238) == true, "warlock sees Vanquished Hero token")
check(Popup:ClassCanUse(31091) == false, "warlock does not see Forgotten Protector token")

ns.modules.DB.db.settings.lootSettings.smartMiniLootFilter = false
currentClass = "WARRIOR"
check(Popup:ShouldShow(1001) == true, "disabled smart filter preserves show-all behavior")
ns.modules.DB.db.settings.lootSettings.smartMiniLootFilter = true
check(Popup:ShouldShow(1001) == false, "enabled smart filter hides irrelevant mini-loot rows")

local Store = ns:GetModule("LootDistStore")
Store:EnsureEntry("filter:bad", { itemId = 1001, quality = 4 })
Store:EnsureEntry("filter:good", { itemId = 1002, quality = 4 })
Popup.active = { ["filter:bad"] = true, ["filter:good"] = true }
local visible, activeCount = Popup:VisibleActiveIds()
check(activeCount == 2, "mini-loot active filter sees all active entries")
check(#visible == 1 and visible[1] == "filter:good", "mini-loot active filter hides irrelevant existing rows")

ns.modules.DB.db.settings.lootSettings.smartMiniLootFilter = false
visible, activeCount = Popup:VisibleActiveIds()
check(activeCount == 2, "mini-loot active filter keeps active count when disabled")
check(#visible == 2, "mini-loot active filter restores rows when disabled")
ns.modules.DB.db.settings.lootSettings.smartMiniLootFilter = true

local realRefresh, realShow, refreshes, shows = Popup.Refresh, Popup.Show, 0, 0
Popup.Refresh = function() refreshes = refreshes + 1 end
Popup.Show = function(self)
    shows = shows + 1
    self.frame = { IsShown = function() return true end }
end

Store:EnsureEntry("auto:hidden", { itemId = 1002, quality = 4 })
Popup.active = {}
Popup.frame = { IsShown = function() return false end }
Popup:OnEntryAdded("auto:hidden")
check(Popup.active["auto:hidden"] == nil, "hidden popup does not auto-add new loot")
check(refreshes == 0, "hidden popup does not refresh for new loot")
check(shows == 0, "hidden popup does not open without opt-in")

ns.modules.DB.db.settings.lootSettings.autoOpenMiniLootOnAdd = true
Store:EnsureEntry("auto:open", { itemId = 1002, quality = 4 })
Popup.active = {}
Popup.frame = nil
Popup:OnEntryAdded("auto:open")
check(Popup.active["auto:open"] == true, "opt-in hidden popup tracks relevant new loot")
check(shows == 1, "opt-in hidden popup opens for relevant new loot")

ns.modules.DB.db.settings.lootSettings.disableMiniLoot = true
Store:EnsureEntry("auto:disabled", { itemId = 1002, quality = 4 })
Popup.active = {}
Popup.frame = nil
Popup:OnEntryAdded("auto:disabled")
check(Popup.active["auto:disabled"] == nil, "global mini-loot opt-out suppresses add auto-open")
check(shows == 1, "global mini-loot opt-out does not open add popup")
ns.modules.DB.db.settings.lootSettings.disableMiniLoot = false
ns.modules.DB.db.settings.lootSettings.autoOpenMiniLootOnAdd = false

Store:EnsureEntry("auto:visible", { itemId = 1002, quality = 4 })
Popup.active = {}
Popup.frame = { IsShown = function() return true end }
Popup:OnEntryAdded("auto:visible")
check(Popup.active["auto:visible"] == true, "open popup auto-adds relevant new loot")
check(refreshes == 1, "open popup refreshes after relevant new loot")

Store:EnsureEntry("auto:filtered", { itemId = 1001, quality = 4 })
Popup.active = {}
Popup:OnEntryAdded("auto:filtered")
check(Popup.active["auto:filtered"] == nil, "open popup keeps filtered new loot hidden")
check(refreshes == 1, "filtered new loot does not refresh popup")

Store:EnsureEntry("auto:existing", { itemId = 1002, quality = 4 })
Popup.active = { ["auto:existing"] = true }
Popup:OnEntryAdded("auto:existing")
check(Popup.active["auto:existing"] == true, "open popup keeps existing active loot")
check(refreshes == 2, "open popup refreshes existing active loot updates")

ns.modules.DB.db.settings.lootSettings.disableMiniLoot = true
Store:EnsureEntry("auto:visible-disabled", { itemId = 1002, quality = 4 })
Popup.active = {}
Popup.frame = { IsShown = function() return true end }
Popup:OnEntryAdded("auto:visible-disabled")
check(Popup.active["auto:visible-disabled"] == true, "open popup still live-adds relevant loot when auto-open is disabled")
check(refreshes == 3, "open popup refreshes live-add even when auto-open is disabled")
ns.modules.DB.db.settings.lootSettings.disableMiniLoot = false

Popup.Refresh = realRefresh
Popup.Show = realShow

print(("loot_popup_filter_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
