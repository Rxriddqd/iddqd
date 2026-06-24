local ADDON, ns = ...

local Panel = ns:NewModule("ProfessionsPanel")

local function Store() return ns:GetModule("ProfessionsStore") end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function shortPlayerName(value)
    local players = Players()
    if players and players.ShortName then return players:ShortName(value) end
    return (strsplit("-", tostring(value or "")))
end

local function lower(v) return string.lower(tostring(v or "")) end

-- ---------------------------------------------------------------------------
-- Categorization (name-based, ported from old panel)
-- ---------------------------------------------------------------------------

local ENCHANT_SLOT_ORDER = {
    "Weapon","Two-Hand Weapon","Shield","Chest","Bracer","Gloves","Boots","Cloak","Ring","Other",
}
local CATEGORY_ORDER = {
    ["Enchanting"]     = ENCHANT_SLOT_ORDER,
    ["Blacksmithing"]  = { "Head","Shoulder","Chest","Wrist","Hands","Waist","Legs","Feet","Shield","One-Hand Weapon","Two-Hand Weapon","Weapon","Rod","Key","Consumable","Loading","Other" },
    ["Tailoring"]      = { "Head","Shoulder","Chest","Wrist","Hands","Waist","Legs","Feet","Cloak","Bag","Thread","Net","Reagent","Loading","Other" },
    ["Leatherworking"] = { "Head","Shoulder","Chest","Wrist","Hands","Waist","Legs","Feet","Cloak","Armor Kit","Drum","Bag","Quiver","Ammo Pouch","Reagent","Loading","Other" },
    ["Alchemy"]        = { "Flask","Battle Elixir","Guardian Elixir","Elixir","Potion","Transmute","Oil","Cauldron","Trinket","Reagent","Loading","Other" },
    ["Engineering"]    = { "Head","Trinket","Gun","Scope","Explosive","Device","Ammo","Pet","Mount","Reagent","Loading","Other" },
    ["Jewelcrafting"]  = { "Meta Gem","Red Gem","Blue Gem","Yellow Gem","Orange Gem","Purple Gem","Green Gem","Neck","Ring","Trinket","Figurine","Reagent","Loading","Other" },
    ["Cooking"]        = { "Feast","Food","Drink","Reagent","Loading","Other" },
    ["First Aid"]      = { "Bandage","Anti-Venom","Loading","Other" },
}
local CATEGORY_RANK = {}
for profession, order in pairs(CATEGORY_ORDER) do
    CATEGORY_RANK[profession] = {}
    for i, name in ipairs(order) do CATEGORY_RANK[profession][name] = i end
end
Panel.CATEGORY_ORDER = CATEGORY_ORDER
Panel.CATEGORY_RANK  = CATEGORY_RANK

local function isEnchanting(name) return lower(name) == "enchanting" end
Panel.isEnchanting = function(_, n) return isEnchanting(n) end

local function enchantSlotName(recipeName)
    local name = tostring(recipeName or "")
    local slot = name:match("^%s*Enchant%s+(.+)%s+%-%s+.+$")
    if not slot then return "Other" end
    slot = slot:gsub("^%s+", ""):gsub("%s+$", "")
    local l = lower(slot)
    if l == "2h weapon" or l == "two-hand weapon" or l == "two hand weapon" then return "Two-Hand Weapon" end
    if l:find("weapon", 1, true) then return "Weapon" end
    if l:find("shield", 1, true) then return "Shield" end
    if l:find("chest", 1, true) then return "Chest" end
    if l:find("bracer", 1, true) or l:find("wrist", 1, true) then return "Bracer" end
    if l:find("glove", 1, true) or l:find("hands", 1, true) then return "Gloves" end
    if l:find("boot", 1, true) or l:find("feet", 1, true) then return "Boots" end
    if l:find("cloak", 1, true) or l:find("back", 1, true) then return "Cloak" end
    if l:find("ring", 1, true) then return "Ring" end
    return slot ~= "" and slot or "Other"
end
Panel.enchantSlotName = function(_, n) return enchantSlotName(n) end
local function recipeDisplayName(recipe)
    recipe = recipe or {}
    return tostring(recipe.itemName or recipe.name or "")
end
local function nameHasAny(name, words)
    name = lower(name)
    for _, word in ipairs(words) do if name:find(lower(word), 1, true) then return true end end
    return false
end
local function armorSlotCategory(name)
    if nameHasAny(name, { "helm","hood","hat","crown","circlet","headguard","headpiece","goggles" }) then return "Head" end
    if nameHasAny(name, { "shoulder","spauld","mantle" }) then return "Shoulder" end
    if nameHasAny(name, { "chest","breastplate","robe","tunic","vest","hauberk" }) then return "Chest" end
    if nameHasAny(name, { "bracer","wrist","cuff" }) then return "Wrist" end
    if nameHasAny(name, { "glove","gauntlet","handguard" }) then return "Hands" end
    if nameHasAny(name, { "belt","girdle","waistguard","sash" }) then return "Waist" end
    if nameHasAny(name, { "leg","pant","trouser","kilt","leggings","legguard" }) then return "Legs" end
    if nameHasAny(name, { "boot","shoe","slipper","footpad","greave" }) then return "Feet" end
    if nameHasAny(name, { "cloak","cape" }) then return "Cloak" end
    return nil
end
local function weaponCategory(name)
    if nameHasAny(name, { "shield","buckler" }) then return "Shield" end
    if nameHasAny(name, { "two-handed","2h","greatsword","battleaxe","warhammer","polearm","staff" }) then return "Two-Hand Weapon" end
    if nameHasAny(name, { "sword","axe","mace","dagger","blade","hammer","fist" }) then return "One-Hand Weapon" end
    if nameHasAny(name, { "weapon","sharpening stone","weightstone" }) then return "Weapon" end
    return nil
end

-- equipLoc -> category. NOTE: wrist items map to "Wrist" here, but Enchanting uses
-- "Bracer" (see enchantSlotName); categoryFromItemType is never called for Enchanting
-- (professionCategory returns early for it), so the two schemes never collide.
local EQUIP_CATEGORY = {
    INVTYPE_HEAD="Head", INVTYPE_SHOULDER="Shoulder", INVTYPE_CHEST="Chest", INVTYPE_ROBE="Chest",
    INVTYPE_WRIST="Wrist", INVTYPE_HAND="Hands", INVTYPE_WAIST="Waist", INVTYPE_LEGS="Legs",
    INVTYPE_FEET="Feet", INVTYPE_CLOAK="Cloak", INVTYPE_FINGER="Ring", INVTYPE_NECK="Neck",
    INVTYPE_TRINKET="Trinket", INVTYPE_HOLDABLE="Shield", INVTYPE_SHIELD="Shield",
}
local TWO_HAND_SUBTYPES = {
    ["Two-Handed Swords"]=true, ["Two-Handed Axes"]=true, ["Two-Handed Maces"]=true,
    ["Staves"]=true, ["Polearms"]=true, ["Fishing Poles"]=true,
}
local RANGED_SUBTYPES = { ["Guns"]=true, ["Bows"]=true, ["Crossbows"]=true, ["Thrown"]=true }

-- Deterministic category from the crafted item's TYPE (GetItemInfo). Returns a category
-- string, "__LOADING__" if the item isn't cached yet, or nil if unmappable.
local function categoryFromItemType(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId == 0 then return nil end
    if not GetItemInfo then return nil end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemId)
    if not itemType then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemId) end
        return "__LOADING__"
    end
    if equipLoc and EQUIP_CATEGORY[equipLoc] then return EQUIP_CATEGORY[equipLoc] end
    if itemType == "Weapon" then
        if RANGED_SUBTYPES[itemSubType] then return "Gun" end
        if TWO_HAND_SUBTYPES[itemSubType] then return "Two-Hand Weapon" end
        return "One-Hand Weapon"
    end
    if itemType == "Projectile" then return "Ammo" end
    if itemType == "Quiver" then return (itemSubType == "Ammo Pouch") and "Ammo Pouch" or "Quiver" end
    if itemType == "Consumable" then
        if itemSubType == "Potion" then return "Potion" end
        if itemSubType == "Elixir" then return "Elixir" end
        if itemSubType == "Flask" then return "Flask" end
        if itemSubType == "Food & Drink" or itemSubType == "Food" then return "Food" end
        if itemSubType == "Bandage" then return "Bandage" end
        if itemSubType == "Scroll" then return "Scroll" end
        return "Consumable"
    end
    if itemType == "Gem" then
        local s = lower(itemSubType or "")
        if s:find("meta", 1, true) then return "Meta Gem" end
        if s:find("red", 1, true) then return "Red Gem" end
        if s:find("blue", 1, true) then return "Blue Gem" end
        if s:find("yellow", 1, true) then return "Yellow Gem" end
        if s:find("orange", 1, true) then return "Orange Gem" end
        if s:find("purple", 1, true) then return "Purple Gem" end
        if s:find("green", 1, true) then return "Green Gem" end
        return "Reagent"
    end
    if itemType == "Container" then return "Bag" end
    if itemType == "Trade Goods" then return "Reagent" end
    return nil
end

local function professionCategory(professionName, recipe)
    local profession = tostring(professionName or "")
    if isEnchanting(profession) then return enchantSlotName(recipe and recipe.name) end
    local itemId = recipe and recipe.itemId
    if itemId then
        local c = categoryFromItemType(itemId)
        if c == "__LOADING__" then return "Loading" end
        if c then return c end
    end
    -- Name-based fallback for recipes without a cached itemId (legacy data, pre-scan).
    local name = recipeDisplayName(recipe)
    local l = lower(name)
    if profession == "Blacksmithing" then
        return armorSlotCategory(name) or weaponCategory(name)
            or (l:find("rod", 1, true) and "Rod") or (l:find("key", 1, true) and "Key")
            or (nameHasAny(name, { "stone","chain","spike" }) and "Consumable") or "Other"
    end
    if profession == "Tailoring" then
        return armorSlotCategory(name)
            or (l:find("bag", 1, true) and "Bag") or (l:find("thread", 1, true) and "Thread")
            or (l:find("net", 1, true) and "Net")
            or (nameHasAny(name, { "cloth","bolt","imbued","spellcloth","shadowcloth","primal mooncloth" }) and "Reagent") or "Other"
    end
    if profession == "Leatherworking" then
        return armorSlotCategory(name)
            or (l:find("armor kit", 1, true) and "Armor Kit") or (l:find("drum", 1, true) and "Drum")
            or (l:find("bag", 1, true) and "Bag") or (l:find("quiver", 1, true) and "Quiver")
            or (l:find("ammo pouch", 1, true) and "Ammo Pouch")
            or (nameHasAny(name, { "leather","hide","scale" }) and "Reagent") or "Other"
    end
    if profession == "Alchemy" then
        if l:find("flask", 1, true) then return "Flask" end
        if l:find("battle elixir", 1, true) then return "Battle Elixir" end
        if l:find("guardian elixir", 1, true) then return "Guardian Elixir" end
        if l:find("elixir", 1, true) then return "Elixir" end
        if l:find("potion", 1, true) then return "Potion" end
        if l:find("transmute", 1, true) then return "Transmute" end
        if l:find("oil", 1, true) then return "Oil" end
        if l:find("cauldron", 1, true) then return "Cauldron" end
        if l:find("stone", 1, true) or l:find("trinket", 1, true) then return "Trinket" end
        if nameHasAny(name, { "primal","might","earthstorm","skyfire" }) then return "Reagent" end
        return "Other"
    end
    if profession == "Engineering" then
        return armorSlotCategory(name)
            or (l:find("trinket", 1, true) and "Trinket")
            or (nameHasAny(name, { "gun","rifle","blaster" }) and "Gun")
            or (l:find("scope", 1, true) and "Scope")
            or (nameHasAny(name, { "bomb","grenade","dynamite","explosive","sapper" }) and "Explosive")
            or (nameHasAny(name, { "gadget","device","injector","transporter","teleporter","repair bot","mote extractor" }) and "Device")
            or (nameHasAny(name, { "bullet","shell","arrow" }) and "Ammo")
            or (nameHasAny(name, { "pet","squirrel","dragonling","toad" }) and "Pet")
            or (nameHasAny(name, { "mount","machine" }) and "Mount")
            or (nameHasAny(name, { "powder","fuse","part","tube","widget","casing" }) and "Reagent") or "Other"
    end
    if profession == "Jewelcrafting" then
        if l:find("meta", 1, true) then return "Meta Gem" end
        if nameHasAny(name, { "ruby","garnet","living ruby" }) then return "Red Gem" end
        if nameHasAny(name, { "sapphire","moonstone","star","nightseye" }) then return "Blue Gem" end
        if nameHasAny(name, { "dawnstone","topaz","citrine" }) then return "Yellow Gem" end
        if nameHasAny(name, { "orange" }) then return "Orange Gem" end
        if nameHasAny(name, { "purple","amethyst" }) then return "Purple Gem" end
        if nameHasAny(name, { "green","emerald","peridot" }) then return "Green Gem" end
        if nameHasAny(name, { "neck","necklace","pendant","choker" }) then return "Neck" end
        if nameHasAny(name, { "ring","band" }) then return "Ring" end
        if l:find("trinket", 1, true) then return "Trinket" end
        if l:find("figurine", 1, true) then return "Figurine" end
        return "Other"
    end
    if profession == "Cooking" then
        if l:find("feast", 1, true) then return "Feast" end
        if nameHasAny(name, { "tea","drink","juice" }) then return "Drink" end
        return "Food"
    end
    if profession == "First Aid" then
        if l:find("anti-venom", 1, true) then return "Anti-Venom" end
        if l:find("bandage", 1, true) then return "Bandage" end
        return "Other"
    end
    return "Other"
end
Panel.professionCategory = professionCategory  -- file-local reference for Task 4 grouping
function Panel:Category(professionName, recipe) return professionCategory(professionName, recipe) end

-- ---------------------------------------------------------------------------
-- Pure layer (tested without WoW UI)
-- ---------------------------------------------------------------------------

-- Resolve one spellId into the rich recipe shape the grouping code expects.
local function resolveRecipe(store, spellId)
    local meta = store:RecipeMeta(spellId) or {}
    local name, _, spellIcon
    if GetSpellInfo then name, _, spellIcon = GetSpellInfo(spellId) end
    local itemId = meta.itemId
    local itemName, itemQuality, itemIcon
    if itemId and GetItemInfo then
        local n, _, q, _, _, _, _, _, _, ic = GetItemInfo(itemId)
        itemName, itemQuality, itemIcon = n, q, ic
    end
    return {
        recipeId    = spellId,
        name        = name,
        itemName    = itemName,
        itemId      = itemId,
        itemIcon    = itemIcon or spellIcon,
        itemQuality = itemQuality,
        recipeLink  = "spell:" .. tostring(spellId),
        effectId    = meta.effectId,
    }
end

-- Flat rows {profile, profession, professionName, recipe} (+ convenience player/name/...).
-- Skips Fishing (handled by FishingRows).
function Panel:RecipeRows(searchText, professionFilter)
    local store = Store()
    local rows = {}
    if not store then return rows end
    searchText = searchText and lower(searchText) or ""
    for key, profile in pairs(store:Profiles()) do
        for professionName, prof in pairs(profile.professions or {}) do
            if lower(professionName) ~= "fishing"
                and (not professionFilter or professionFilter == "" or professionFilter == "ALL" or professionFilter == professionName) then
                for _, spellId in ipairs(prof.spellIds or {}) do
                    local recipe = resolveRecipe(store, spellId)
                    local hay = lower(table.concat({
                        profile.name or "", key, professionName,
                        recipe.name or "", recipe.itemName or "",
                    }, " "))
                    if searchText == "" or hay:find(searchText, 1, true) then
                        rows[#rows + 1] = {
                            profile        = profile,
                            profession     = prof,          -- the profession record table (NOT the name)
                            professionName = professionName,
                            recipe         = recipe,
                            player         = profile.name or key,
                            spellId        = spellId,
                            name           = recipe.name or ("Spell " .. tostring(spellId)),
                            syncState      = prof.syncState,
                            lastSyncAt     = prof.lastSyncAt,
                        }
                    end
                end
            end
        end
    end
    return rows
end

-- Fishing characters with skill ranks (no recipes), sorted by rank descending.
function Panel:FishingRows(searchText)
    local store = Store()
    local rows = {}
    if not store then return rows end
    searchText = searchText and lower(searchText) or ""
    for key, profile in pairs(store:Profiles()) do
        local prof = profile.professions and profile.professions["Fishing"]
        if prof then
            local hay = lower(table.concat({
                profile.name or "", key, "Fishing",
                tostring(prof.rank or ""), tostring(prof.maxRank or ""),
            }, " "))
            if searchText == "" or hay:find(searchText, 1, true) then
                rows[#rows + 1] = {
                    profile = profile, profession = prof, professionName = "Fishing",
                    rank = tonumber(prof.rank or 0) or 0, maxRank = tonumber(prof.maxRank or 0) or 0,
                    updatedAt = prof.updatedAt or profile.updatedAt,
                    player = profile.name or key,
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.maxRank ~= b.maxRank then return a.maxRank > b.maxRank end
        return tostring(a.player) < tostring(b.player)
    end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Grouping (Task 4) — pure, references file-locals from categorization block
-- ---------------------------------------------------------------------------

local function craftKey(entry)
    local recipe = entry.recipe or {}
    return table.concat({
        tostring(recipe.itemId or 0),
        tostring(recipe.recipeId or recipe.key or recipe.name or "MISSING"),
        tostring(entry.professionName or ""),
        tostring(recipe.itemName or recipe.name or ""),
    }, ":")
end

function Panel:BuildCraftGroups(rows)
    local groups, order = {}, {}
    for _, entry in ipairs(rows or {}) do
        local key = craftKey(entry)
        local group = groups[key]
        if not group then
            group = {
                key = key, recipe = entry.recipe, professionName = entry.professionName,
                enchantSlot = isEnchanting(entry.professionName) and enchantSlotName(entry.recipe and entry.recipe.name) or nil,
                category = professionCategory(entry.professionName, entry.recipe),
                makers = {}, latestAt = 0,
            }
            groups[key] = group
            order[#order + 1] = group
        end
        local at = tonumber((entry.profession and entry.profession.updatedAt) or (entry.profile and entry.profile.updatedAt) or 0) or 0
        if at > group.latestAt then group.latestAt = at end
        group.makers[#group.makers + 1] = entry
    end
    table.sort(order, function(a, b)
        local an = (a.recipe and (a.recipe.itemName or a.recipe.name)) or ""
        local bn = (b.recipe and (b.recipe.itemName or b.recipe.name)) or ""
        if an ~= bn then return an < bn end
        return (a.professionName or "") < (b.professionName or "")
    end)
    for _, group in ipairs(order) do
        table.sort(group.makers, function(a, b)
            return ((a.profile and a.profile.name) or "") < ((b.profile and b.profile.name) or "")
        end)
    end
    return order
end

-- Best-effort item quality for a craft group (0=Poor .. 5=Legendary). Prefers the quality
-- captured on the recipe; falls back to a live GetItemInfo lookup by itemId/name. Unknown ->
-- -1 so not-yet-cached items sort below known ones (they settle up once item info loads and
-- the panel refreshes on GET_ITEM_INFO_RECEIVED).
local function groupQuality(group)
    local recipe = group and group.recipe
    if not recipe then return -1 end
    local q = tonumber(recipe.itemQuality)
    if q then return q end
    if GetItemInfo then
        local query = recipe.itemId or recipe.itemLink or recipe.itemName
        if query then
            local _, _, cq = GetItemInfo(query)
            if cq then
                recipe.itemQuality = cq   -- memoise so later sorts/renders are stable
                return cq
            end
        end
    end
    return -1
end

-- Stamp each group's quality once (groupQuality may call GetItemInfo). Doing this here, before
-- BuildDisplayGroups, keeps GetItemInfo OUT of the per-comparison sort path (which would call
-- it O(n log n) times); the sort below then just reads the cached number.
function Panel:StampGroupQualities(groups)
    for _, group in ipairs(groups or {}) do
        group._quality = groupQuality(group)
    end
end

function Panel:BuildDisplayGroups(groups, expanded)
    expanded = expanded or {}
    local display, buckets, bucketOrder = {}, {}, {}
    for _, group in ipairs(groups or {}) do
        local profession = group.professionName or "Other"
        local category = group.category or "Other"
        local useCategory = CATEGORY_ORDER[profession] ~= nil
        local bucketKey = "category:" .. profession .. ":" .. (useCategory and category or "Other")
        local bucket = buckets[bucketKey]
        if not bucket then
            bucket = {
                kind = "category", key = bucketKey,
                name = useCategory and category or profession,
                professionName = profession, groups = {}, latestAt = 0,
            }
            buckets[bucketKey] = bucket
            bucketOrder[#bucketOrder + 1] = bucket
        end
        bucket.groups[#bucket.groups + 1] = group
        if (group.latestAt or 0) > bucket.latestAt then bucket.latestAt = group.latestAt end
    end
    table.sort(bucketOrder, function(a, b)
        if a.professionName ~= b.professionName then return (a.professionName or "") < (b.professionName or "") end
        local ranks = CATEGORY_RANK[a.professionName or ""] or {}
        local ar, br = ranks[a.name] or 999, ranks[b.name] or 999
        if ar ~= br then return ar < br end
        return (a.name or "") < (b.name or "")
    end)
    for _, bucket in ipairs(bucketOrder) do
        -- Within a category: highest quality first (epic > rare > uncommon > common), then
        -- alphabetical by item name as the tiebreaker.
        table.sort(bucket.groups, function(a, b)
            -- Read the quality stamped by StampGroupQualities (no GetItemInfo in the comparator).
            local aq = a._quality or groupQuality(a)
            local bq = b._quality or groupQuality(b)
            if aq ~= bq then return aq > bq end
            local an = (a.recipe and (a.recipe.itemName or a.recipe.name)) or ""
            local bn = (b.recipe and (b.recipe.itemName or b.recipe.name)) or ""
            if an ~= bn then return an < bn end
            return tostring(a.key) < tostring(b.key)
        end)
        display[#display + 1] = bucket
        if expanded[bucket.key] then
            for _, group in ipairs(bucket.groups) do
                display[#display + 1] = { kind = "craft", group = group, nested = true }
            end
        end
    end
    return display
end

local function agoText(lastSyncAt)
    local nowTs = (time and time()) or 0
    local secs = nowTs - (tonumber(lastSyncAt) or nowTs)
    if secs < 0 then secs = 0 end
    if secs < 60 then return "just now" end
    if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
    if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
    return math.floor(secs / 86400) .. "d ago"
end

function Panel:SyncStateLabel(state, lastSyncAt)
    if state == "synced" then
        if lastSyncAt then return "Synced " .. agoText(lastSyncAt) end
        return "Synced"
    end
    if state == "pending" then return "Syncing\226\128\166" end  -- "Syncing…"
    if state == "waiting" then return "Waiting for player" end
    if state == "unavailable" then return "Unavailable" end
    return ""
end

-- Button actions (wired to frame in-game; safe no-ops when modules absent).
function Panel:OnScanClicked()
    local scanner = ns:GetModule("ProfessionsScanner")
    if scanner and scanner.ScanOpen then scanner:ScanOpen() end
end

function Panel:OnShareClicked()
    local sync = ns:GetModule("ProfessionsSync")
    if sync and sync.BroadcastManifest then sync:BroadcastManifest() end
end

function Panel:OnRequestSyncClicked()
    local sync = ns:GetModule("ProfessionsSync")
    if sync and sync.BeginManualSync then sync:BeginManualSync() end
end

-- Frame handshake: Sync calls Panel:Refresh() when data arrives.
function Panel:SetFrame(frame) self.frame = frame end

function Panel:Refresh()
    -- External callers (sync apply, scan) reach Refresh only when profile data changed, so the
    -- cached craft tree is stale -> invalidate before rebuilding.
    if self.frame and self.frame.InvalidateTree then self.frame:InvalidateTree() end
    if self.frame and self.frame.Refresh then self.frame:Refresh() end
end

-- ---------------------------------------------------------------------------
-- In-game UI (guarded: skipped in tests where CreateFrame is nil)
-- ---------------------------------------------------------------------------

if CreateFrame and ns:GetModule("Nav") then
    local Nav   = ns:GetModule("Nav")
    local W     = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")

    -- -----------------------------------------------------------------------
    -- In-game-only helpers (ported from old panel)
    -- -----------------------------------------------------------------------

    local function normalizeClass(classValue)
        if not classValue then return nil end
        classValue = tostring(classValue)
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classValue] then return classValue end
        local upper = string.upper(classValue:gsub("%s+", ""))
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[upper] then return upper end
        for token in pairs(RAID_CLASS_COLORS or {}) do
            if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] == classValue then return token end
            if LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[token] == classValue then return token end
        end
        return nil
    end

    local function classColor(classFile)
        local token = normalizeClass(classFile)
        local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        if c then return c.r, c.g, c.b end
        return 0.86, 0.88, 0.92
    end

    local function playerName(profile)
        local value = (profile and (profile.name or profile.key)) or "?"
        return shortPlayerName(value)
    end

    local function currentPlayerNames()
        local name = UnitName and UnitName("player")
        local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName()
        realm = realm and tostring(realm):gsub("%s+", "") or nil
        return name, name and realm and (name .. "-" .. realm) or name
    end

    local function currentPlayerClass()
        if not UnitClass then return nil end
        local _, classFile = UnitClass("player")
        return normalizeClass(classFile)
    end

    local function normalizeName(value)
        value = tostring(value or "")
        if value == "" then return "" end
        return string.lower((value:gsub("%s+", "")))
    end

    local function isCurrentProfile(profile)
        if not profile then return false end
        local short, full = currentPlayerNames()
        local key  = normalizeName(profile.key  or "")
        local name = normalizeName(profile.name or "")
        return key ~= "" and (key == normalizeName(full) or key == normalizeName(short))
            or name ~= "" and (name == normalizeName(full) or name == normalizeName(short))
    end

    local function colorHex(r, g, b)
        return ("ff%02x%02x%02x"):format(
            math.floor((r or 1) * 255 + 0.5),
            math.floor((g or 1) * 255 + 0.5),
            math.floor((b or 1) * 255 + 0.5))
    end

    local function coloredText(text, r, g, b)
        return ("|c%s%s|r"):format(colorHex(r, g, b), tostring(text or ""))
    end

    local function buildGuildStatusMap()
        local map = {}
        if not IsInGuild or not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return map end
        if GuildRoster then pcall(GuildRoster) end
        local count = tonumber(GetNumGuildMembers() or 0) or 0
        for i = 1, count do
            local name, _, _, _, className, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if name then
                local shortName = shortPlayerName(name)
                local info = {
                    online = online and true or false,
                    class  = normalizeClass(classFile) or normalizeClass(className),
                }
                map[normalizeName(name)]      = info
                map[normalizeName(shortName)] = info
            end
        end
        local player = UnitName and UnitName("player")
        local realm  = GetRealmName and GetRealmName()
        if player then
            local _, classFile = UnitClass and UnitClass("player")
            local info = { online = true, class = normalizeClass(classFile) }
            map[normalizeName(player)] = info
            if realm then map[normalizeName(player .. "-" .. realm)] = info end
        end
        return map
    end

    local function profileStatus(profile, statusMap)
        if not profile then return nil end
        local key  = profile.key  or profile.name
        local name = profile.name or profile.key
        return statusMap and (
            statusMap[normalizeName(key)]
            or statusMap[normalizeName(name)]
            or statusMap[normalizeName(playerName(profile))]
        ) or nil
    end

    local function qualityColor(q)
        q = tonumber(q)
        if q == 5 then return 1.00, 0.50, 0.00 end
        if q == 4 then return 0.64, 0.21, 0.93 end
        if q == 3 then return 0.00, 0.44, 0.87 end
        if q == 2 then return 0.12, 1.00, 0.00 end
        if q == 1 then return 1.00, 1.00, 1.00 end
        return 0.86, 0.88, 0.92
    end

    local function shortTime(ts)
        ts = tonumber(ts or 0)
        if ts <= 0 then return "-" end
        return date("%d %b %H:%M", ts)
    end

    local function itemIdFromLink(link)
        if type(link) ~= "string" then return nil end
        local id = link:match("item:(%d+)")
        return id and tonumber(id) or nil
    end

    local function itemIconById(itemId)
        itemId = tonumber(itemId)
        if not itemId then return nil end
        if C_Item and C_Item.GetItemIconByID then
            local ok, icon = pcall(C_Item.GetItemIconByID, itemId)
            if ok and icon then return icon end
        end
        if GetItemIcon then
            local ok, icon = pcall(GetItemIcon, itemId)
            if ok and icon then return icon end
        end
        if GetItemInfoInstant then
            local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, itemId)
            if ok and icon then return icon end
        end
        return nil
    end

    local function itemVisual(recipe)
        if not recipe then return nil, nil, nil end
        local name    = recipe.itemName
        local quality = recipe.itemQuality
        local icon    = recipe.itemIcon
        local recipeId = tonumber(recipe.recipeId)
        local db = ns.professionRecipeDB
        local staticInfo = recipeId and db and db.bySpellId and db.bySpellId[recipeId]
        if not staticInfo and recipeId and db and db.byEffectId and db.byEffectId[recipeId] then
            recipeId   = db.byEffectId[recipeId]
            staticInfo = db.bySpellId and db.bySpellId[recipeId]
        end
        local staticItemId   = staticInfo and staticInfo.i
        local staticItemIcon = itemIconById(staticItemId)
        if staticItemIcon then icon = staticItemIcon end
        local query = recipe.itemLink or recipe.itemId or staticItemId
        if query and GetItemInfo then
            local cachedName, _, cachedQuality, _, _, _, _, _, _, cachedIcon = GetItemInfo(query)
            name    = name    or cachedName
            quality = quality or cachedQuality
            icon    = staticItemIcon or cachedIcon or icon or itemIconById(recipe.itemId or staticItemId or itemIdFromLink(query))
            if not cachedName and C_Item and C_Item.RequestLoadItemDataByID then
                local itemId = recipe.itemId or staticItemId or itemIdFromLink(query)
                if itemId then pcall(C_Item.RequestLoadItemDataByID, itemId) end
            end
        end
        if (not name or not icon) and (recipe.itemName or recipe.name) and GetItemInfo then
            local cachedName, _, cachedQuality, _, _, _, _, _, _, cachedIcon = GetItemInfo(recipe.itemName or recipe.name)
            name    = name    or cachedName
            quality = quality or cachedQuality
            icon    = icon    or cachedIcon
        end
        if (not name or not icon) and recipe.recipeId then
            if GetSpellInfo then
                local spellName, _, spellIcon = GetSpellInfo(recipe.recipeId)
                name = name or spellName
                icon = icon or spellIcon
            end
            if not icon and GetSpellTexture then icon = GetSpellTexture(recipe.recipeId) end
        end
        return name or recipe.name or "Recipe", quality, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local PROFESSION_ICONS = {
        alchemy        = "Interface\\Icons\\Trade_Alchemy",
        blacksmithing  = "Interface\\Icons\\Trade_BlackSmithing",
        cooking        = "Interface\\Icons\\INV_Misc_Food_15",
        enchanting     = "Interface\\Icons\\Trade_Engraving",
        engineering    = "Interface\\Icons\\Trade_Engineering",
        ["first aid"]  = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
        fishing        = "Interface\\Icons\\Trade_Fishing",
        herbalism      = "Interface\\Icons\\Trade_Herbalism",
        inscription    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
        jewelcrafting  = "Interface\\Icons\\INV_Misc_Gem_01",
        leatherworking = "Interface\\Icons\\INV_Misc_ArmorKit_17",
        mining         = "Interface\\Icons\\Trade_Mining",
        skinning       = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
        tailoring      = "Interface\\Icons\\Trade_Tailoring",
    }

    local ENCHANT_ICON   = "Interface\\Icons\\Spell_Holy_GreaterHeal"
    local QUESTION_ICON  = "Interface\\Icons\\INV_Misc_QuestionMark"

    local function professionIcon(name)
        if name == "ALL" then return "Interface\\Icons\\INV_Misc_Book_09" end
        return PROFESSION_ICONS[lower(name)] or "Interface\\Icons\\INV_Misc_Note_01"
    end

    local SECONDARY_PROFESSIONS = {
        ["cooking"]   = true,
        ["first aid"] = true,
        ["fishing"]   = true,
    }

    local function isSecondaryProfession(name)
        return SECONDARY_PROFESSIONS[lower(name)] and true or false
    end

    local function setTooltipHyperlink(link)
        if not link or not GameTooltip or not GameTooltip.SetHyperlink then return false end
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        return ok and true or false
    end

    local function setTooltipSpell(recipeId)
        recipeId = tonumber(recipeId)
        if not recipeId or not GameTooltip or not GameTooltip.SetSpellByID then return false end
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, recipeId)
        return ok and true or false
    end

    local function showRecipeTooltip(owner, row)
        if not GameTooltip or not row or not row.data then return end
        local recipe = row.data.recipe
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local shown = recipe and setTooltipHyperlink(recipe.recipeLink)
        if not shown and recipe then shown = setTooltipHyperlink(recipe.itemLink) end
        if not shown and recipe then shown = setTooltipSpell(recipe.recipeId) end
        if not shown then GameTooltip:SetText((recipe and recipe.name) or "Recipe") end
        if recipe and recipe.itemLink and recipe.recipeLink then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Crafted item:", 0.72, 0.76, 0.84)
            GameTooltip:AddLine(recipe.itemLink, 1, 1, 1, true)
        end
        local lines = GameTooltip.NumLines and GameTooltip:NumLines() or 0
        if recipe and type(recipe.reagents) == "table" and #recipe.reagents > 0 and lines <= 4 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Materials:", 0.72, 0.76, 0.84)
            for _, reagent in ipairs(recipe.reagents) do
                local count = tonumber(reagent.count or 0) or 0
                local label = reagent.itemLink or reagent.name or "Reagent"
                if count > 1 then
                    GameTooltip:AddLine(("  %s x%d"):format(label, count), 1, 1, 1, true)
                else
                    GameTooltip:AddLine(("  %s"):format(label), 1, 1, 1, true)
                end
            end
        end
        GameTooltip:Show()
    end

    -- -----------------------------------------------------------------------
    -- buildPanel
    -- -----------------------------------------------------------------------

    local function buildPanel(parent)
        local f = W:Card(parent, "base", true)
        f.rows           = {}
        f.searchText     = ""
        f.professionFilter = "ALL"
        f.expanded       = {}
        f.profButtons    = {}

        -- Title block
        local eyebrow = W:Eyebrow(f, "Guild Professions")
        eyebrow:SetPoint("TOPLEFT", 12, -12)
        local title = W:Title(f, "Crafts")
        title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -3)
        local subtitle = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(subtitle, "caption", "dim")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetText("Search guild crafts, enchants, patterns, consumables, and raid utility.")

        -- Actions area (top-right)
        local actions = CreateFrame("Frame", nil, f)
        actions:SetPoint("TOPRIGHT", -12, -14)
        actions:SetSize(398, 62)

        local scanBtn = W:Button(actions, "Scan Open Profession", 150, 24)
        scanBtn:SetTone("blue")
        scanBtn:SetPoint("TOPLEFT", 0, -8)
        local shareBtn = W:Button(actions, "Share", 72, 24)
        shareBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
        local requestBtn = W:Button(actions, "Request Sync", 106, 24)
        requestBtn:SetPoint("LEFT", shareBtn, "RIGHT", 8, 0)

        -- Status text line (replaces old syncProgress bar)
        local syncText = actions:CreateFontString(nil, "OVERLAY")
        Theme:Text(syncText, "caption", "dim")
        syncText:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -5)
        syncText:SetPoint("RIGHT", 0, 0)
        syncText:SetJustifyH("LEFT")
        syncText:SetWordWrap(false)
        f.syncText = syncText

        -- Shared themed search box (the original source of this style; host.edit is the
        -- EditBox, host:SetText("") clears it, host.placeholder is the hint).
        local searchBox = W:TextInput(f, {
            width = 280, height = 24,
            placeholder = "Search craft, recipe, profession, or player…",
            onChange = function(text, userInput)
                f.searchText = text
                if userInput then f:Refresh() end
            end,
        })
        searchBox:SetPoint("TOPLEFT", 12, -84)
        f.searchBox = searchBox

        -- Profession filter icon buttons (to the right of the search box)
        local profButtons = CreateFrame("Frame", nil, f)
        profButtons:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
        profButtons:SetPoint("RIGHT", -12, 0)
        profButtons:SetHeight(34)
        f.profButtonHost = profButtons

        -- Summary line
        local summary = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(summary, "caption", "dim")
        summary:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -8)
        summary:SetPoint("RIGHT", -12, 0)
        summary:SetJustifyH("LEFT")
        summary:SetWordWrap(false)
        f.summary = summary

        -- Inner card hosting the header + scroll list
        local listHost = W:Card(f, "overlay", true)
        listHost:SetPoint("TOPLEFT", 12, -142)
        listHost:SetPoint("BOTTOMRIGHT", -12, 12)

        local header = W:ListRow(listHost)
        header:SetPoint("TOPLEFT", 10, -10)
        header:SetPoint("TOPRIGHT", -14, -10)
        header:SetHeight(24)
        header:SetRowVisual(1, false, "group")
        f.header = header

        local scroll, content = W:ScrollHost(listHost)
        scroll:SetPoint("TOPLEFT", 10, -36)
        scroll:SetPoint("BOTTOMRIGHT", -14, 10)
        f.scroll    = scroll
        f.content   = content
        f.scrollBar = W:ScrollBar(scroll, content)

        local function addText(frame, variant, tone)
            local fs = frame:CreateFontString(nil, "OVERLAY")
            Theme:Text(fs, variant or "caption", tone or "dim")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            return fs
        end

        local function applyDefaultRowLayout(row)
            if not row or not row.name then return end
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", 46, 0)
            row.name:SetWidth(310)
            row.name:SetJustifyH("LEFT")
            row.prof:ClearAllPoints()
            row.prof:SetPoint("LEFT", 372, 0)
            row.prof:SetWidth(128)
            row.prof:SetJustifyH("LEFT")
            row.makers:ClearAllPoints()
            row.makers:SetPoint("LEFT", 510, 0)
            row.makers:SetWidth(220)
            row.makers:SetJustifyH("LEFT")
            row.updated:ClearAllPoints()
            row.updated:SetPoint("RIGHT", -8, 0)
            row.updated:SetWidth(92)
            row.updated:SetJustifyH("RIGHT")
        end

        -- Header labels
        header.craft = addText(header, "caption", "faint")
        header.craft:SetPoint("LEFT", 34, 0)
        header.craft:SetText("CRAFT")
        header.prof = addText(header, "caption", "faint")
        header.prof:SetPoint("LEFT", 372, 0)
        header.prof:SetText("PROFESSION")
        header.makers = addText(header, "caption", "faint")
        header.makers:SetPoint("LEFT", 510, 0)
        header.makers:SetText("CRAFTERS")
        header.updated = addText(header, "caption", "faint")
        header.updated:SetPoint("RIGHT", -8, 0)
        header.updated:SetWidth(92)
        header.updated:SetJustifyH("RIGHT")
        header.updated:SetText("UPDATED")

        local function ensureRow(i)
            local row = f.rows[i]
            if row then
                row:SetRowVisual(i, false)
                applyDefaultRowLayout(row)
                return row
            end
            row = W:ListRow(content, true)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", 8, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.iconBorder = W:IconBorder(row.icon)
            row.chev = addText(row, "caption", "warm")
            row.chev:SetPoint("LEFT", 36, 0)
            row.chev:SetWidth(8)
            row.name = addText(row, "caption", "ink")
            row.name:SetPoint("LEFT", 46, 0)
            row.name:SetWidth(310)
            row.prof = addText(row, "caption", "dim")
            row.prof:SetPoint("LEFT", 372, 0)
            row.prof:SetWidth(128)
            row.makers = addText(row, "caption", "dim")
            row.makers:SetPoint("LEFT", 510, 0)
            row.makers:SetWidth(220)
            row.updated = addText(row, "caption", "faint")
            row.updated:SetPoint("RIGHT", -8, 0)
            row.updated:SetWidth(92)
            row.updated:SetJustifyH("RIGHT")
            applyDefaultRowLayout(row)
            row:SetScript("OnEnter", function(self)
                self:SetRowHover(true)
                if self.kind == "craft" then showRecipeTooltip(self, self) end
            end)
            row:SetScript("OnLeave", function(self)
                self:SetRowHover(false)
                if GameTooltip then GameTooltip:Hide() end
            end)
            row:SetScript("OnClick", function(self)
                if (self.kind ~= "craft" and self.kind ~= "category") or not self.groupKey then return end
                f.expanded[self.groupKey] = not f.expanded[self.groupKey]
                f:Refresh()
            end)
            f.rows[i] = row
            return row
        end

        function f:RefreshProfessionButtons()
            local store = Store()
            local known = store and store:KnownProfessionNames() or {}
            local values = { "ALL" }
            for _, name in ipairs(known) do values[#values + 1] = name end
            for _, button in ipairs(self.profButtons) do button:Hide() end

            local x, size, gap = 0, 34, 6
            local seenSecondary = false
            for i, value in ipairs(values) do
                if value ~= "ALL" and isSecondaryProfession(value) and not seenSecondary then
                    x = x + 16
                    seenSecondary = true
                end
                local button = self.profButtons[i]
                if not button then
                    button = CreateFrame("Button", nil, self.profButtonHost, "BackdropTemplate")
                    button:SetSize(size, size)
                    button.fill = button:CreateTexture(nil, "BACKGROUND")
                    button.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
                    button.fill:SetAllPoints(button)
                    button.icon = button:CreateTexture(nil, "ARTWORK")
                    button.icon:SetPoint("TOPLEFT", 1, -1)
                    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                    button.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
                    button.border = {}
                    for edgeIndex = 1, 4 do
                        button.border[edgeIndex] = button:CreateTexture(nil, "OVERLAY")
                        button.border[edgeIndex]:SetTexture("Interface\\Buttons\\WHITE8X8")
                    end
                    button.border[1]:SetPoint("TOPLEFT", 0, 0)
                    button.border[1]:SetPoint("TOPRIGHT", 0, 0)
                    button.border[1]:SetHeight(1)
                    button.border[2]:SetPoint("BOTTOMLEFT", 0, 0)
                    button.border[2]:SetPoint("BOTTOMRIGHT", 0, 0)
                    button.border[2]:SetHeight(1)
                    button.border[3]:SetPoint("TOPLEFT", 0, 0)
                    button.border[3]:SetPoint("BOTTOMLEFT", 0, 0)
                    button.border[3]:SetWidth(1)
                    button.border[4]:SetPoint("TOPRIGHT", 0, 0)
                    button.border[4]:SetPoint("BOTTOMRIGHT", 0, 0)
                    button.border[4]:SetWidth(1)
                    function button:SetButtonVisual(iconR, iconG, iconB, iconA, borderR, borderG, borderB, borderA, fillR, fillG, fillB, fillA)
                        self.icon:SetVertexColor(iconR, iconG, iconB, iconA)
                        for _, edge in ipairs(self.border or {}) do
                            edge:SetVertexColor(borderR, borderG, borderB, borderA)
                        end
                        if self.fill then
                            self.fill:Show()
                            self.fill:SetVertexColor(fillR, fillG, fillB, fillA)
                        end
                    end
                    function button:SetSelected(on)
                        self._selected = on and true or false
                        if on then
                            self:SetButtonVisual(1, 1, 1, 1, 0.92, 0.76, 0.38, 0.62, 0.075, 0.064, 0.035, 0.86)
                        else
                            self:SetButtonVisual(0.38, 0.40, 0.46, 0.78, 0.58, 0.60, 0.66, 0.22, 0.028, 0.030, 0.036, 0.72)
                        end
                    end
                    self.profButtons[i] = button
                end
                button:ClearAllPoints()
                button:SetPoint("LEFT", self.profButtonHost, "LEFT", x, 0)
                button.icon:SetTexture(professionIcon(value))
                button.value = value
                button:SetSelected(self.professionFilter == value)
                button:SetScript("OnClick", function(self)
                    f.professionFilter = self.value or "ALL"
                    f:Refresh()
                end)
                button:SetScript("OnEnter", function(self)
                    if not self._selected then
                        self:SetButtonVisual(0.74, 0.78, 0.86, 0.95, 0.74, 0.76, 0.82, 0.42, 0.045, 0.048, 0.058, 0.82)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(value == "ALL" and "All Professions" or value)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function(self)
                    if not self._selected then
                        self:SetButtonVisual(0.38, 0.40, 0.46, 0.78, 0.58, 0.60, 0.66, 0.22, 0.028, 0.030, 0.036, 0.72)
                    end
                    GameTooltip:Hide()
                end)
                button:Show()
                x = x + size + gap
            end
        end

        function f:RefreshStatus()
            local store = Store()
            local lp      = store and store:LocalProfile()
            local updated = lp and tonumber(lp.updatedAt or 0) or 0
            self.syncText:SetText(updated > 0
                and ("Last local scan: " .. date("%d %b %H:%M", updated))
                or "Open a profession window and click Scan; learned recipes sync to guild members.")
        end

        function f:Refresh()
            for _, row in ipairs(self.rows) do row:Hide() end
            self:RefreshProfessionButtons()
            self:RefreshStatus()

            local statusMap   = buildGuildStatusMap()
            local store       = Store()
            local profiles    = store and store:Profiles() or {}
            local profileCount = 0
            for _ in pairs(profiles) do profileCount = profileCount + 1 end

            -- Fishing view
            if self.professionFilter == "Fishing" then
                self.header.craft:SetText("PLAYER")
                self.header.prof:SetText("SKILL")
                self.header.makers:SetText("STATUS")
                self.header.updated:SetText("UPDATED")
                local rows = Panel:FishingRows(self.searchText)
                self.summary:SetText(("%d fishing character%s  -  sorted by skill"):format(#rows, #rows == 1 and "" or "s"))
                local contentW = math.max(850, (self.scroll:GetWidth() or 850) - 4)
                self.content:SetWidth(contentW)
                local y, rowIndex = 0, 0
                if #rows == 0 then
                    rowIndex = rowIndex + 1
                    local row = ensureRow(rowIndex)
                    row:SetPoint("TOPLEFT", 0, 0)
                    row:SetPoint("TOPRIGHT", 0, 0)
                    row:SetSize(contentW, 28)
                    row.icon:Hide()
                    row.chev:SetText("")
                    row.name:SetText("No fishing skill data found")
                    row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
                    row.prof:SetText("Open the character skills panel to scan Fishing.")
                    row.makers:SetText("")
                    row.updated:SetText("")
                    row.data     = nil
                    row.kind     = "empty"
                    row.groupKey = nil
                    row:SetRowVisual(1, false)
                    row:Show()
                    self.content:SetHeight(28)
                    self.scrollBar:Update()
                    return
                end
                for _, skill in ipairs(rows) do
                    rowIndex = rowIndex + 1
                    local row = ensureRow(rowIndex)
                    row:SetPoint("TOPLEFT", 0, y)
                    row:SetPoint("TOPRIGHT", 0, y)
                    row:SetSize(contentW, 26)
                    row.icon:Show()
                    row.icon:SetTexture(professionIcon("Fishing"))
                    row.chev:SetText("")
                    local statusInfo = profileStatus(skill.profile, statusMap)
                    local classToken = isCurrentProfile(skill.profile) and currentPlayerClass()
                        or normalizeClass(skill.profile and skill.profile.class)
                        or (statusInfo and statusInfo.class)
                    local r, g, b = classColor(classToken)
                    row.name:SetText(coloredText(playerName(skill.profile), r, g, b))
                    row.name:SetTextColor(1, 1, 1, 1)
                    row.prof:SetText(("%d/%d"):format(skill.rank or 0, skill.maxRank or 0))
                    local online = statusInfo and statusInfo.online
                    row.makers:SetText(online and coloredText("Online", 0.28, 0.95, 0.42) or coloredText("Offline", 0.95, 0.24, 0.24))
                    row.makers:SetTextColor(1, 1, 1, 1)
                    row.updated:SetText(shortTime(skill.updatedAt))
                    row.data     = nil
                    row.kind     = "skill"
                    row.groupKey = nil
                    row:SetRowVisual(rowIndex, false)
                    row:Show()
                    y = y - 26
                end
                self.content:SetHeight(math.max(self.scroll:GetHeight() or 1, -y))
                self.scrollBar:Update()
                return
            end

            -- Three-level tree view (category > craft > maker)
            self.header.craft:SetText("CRAFT")
            self.header.prof:SetText("PROFESSION")
            self.header.makers:SetText("CRAFTERS")
            self.header.updated:SetText("UPDATED")

            -- Heavy build (RecipeRows over ~all profiles x professions x spells, then group +
            -- sort) is CACHED. It only depends on the filter + search text, NOT on expand state,
            -- scroll, or resize — so those interactions (and the GET_ITEM_INFO refresh burst)
            -- reuse the cache instead of rebuilding the whole tree each time. InvalidateTree()
            -- (called on data changes) drops the cache so the next Refresh rebuilds.
            local cacheKey = (self.professionFilter or "ALL") .. "\31" .. (self.searchText or "")
            if not self._treeCache or self._treeCacheKey ~= cacheKey then
                local flatRows = Panel:RecipeRows(self.searchText, self.professionFilter == "ALL" and "" or self.professionFilter)
                local groups   = Panel:BuildCraftGroups(flatRows)
                Panel:StampGroupQualities(groups)
                self._treeCache = { flatRows = flatRows, groups = groups }
                self._treeCacheKey = cacheKey
            end
            local flatRows = self._treeCache.flatRows
            local groups   = self._treeCache.groups
            -- BuildDisplayGroups depends on expand state, so it runs each Refresh — but it's the
            -- cheap part (bucket + flatten of already-built/sorted groups), no GetItemInfo now.
            local displayGroups = Panel:BuildDisplayGroups(groups, self.expanded)
            self.summary:SetText(("%d crafts  -  %d makers  -  %d characters"):format(#groups, #flatRows, profileCount))
            local contentW = math.max(850, (self.scroll:GetWidth() or 850) - 4)
            self.content:SetWidth(contentW)

            local y, rowIndex = 0, 0
            if #groups == 0 then
                rowIndex = rowIndex + 1
                local row = ensureRow(rowIndex)
                row:SetPoint("TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", 0, 0)
                row:SetSize(contentW, 28)
                row.icon:Hide()
                if row.iconBorder then row.iconBorder:Hide() end
                row.chev:SetText("")
                row.name:SetText("No profession crafts found")
                row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
                row.prof:SetText("Open a profession window, then click Scan.")
                row.makers:SetText("")
                row.updated:SetText("")
                row.data     = nil
                row.kind     = "empty"
                row.groupKey = nil
                row:SetRowVisual(1, false)
                row:Show()
                self.content:SetHeight(28)
                self.scrollBar:Update()
                return
            end

            for _, display in ipairs(displayGroups) do
                if display.kind == "category" then
                    rowIndex = rowIndex + 1
                    local row = ensureRow(rowIndex)
                    row:SetPoint("TOPLEFT", 0, y)
                    row:SetPoint("TOPRIGHT", 0, y)
                    row:SetSize(contentW, 26)
                    row.icon:Hide()
                    if row.iconBorder then row.iconBorder:Hide() end
                    row.chev:SetText(self.expanded[display.key] and "-" or "+")
                    row.name:SetText(display.name)
                    row.name:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 1)
                    row.prof:SetText(display.professionName or "-")
                    row.makers:SetText(("%d crafts"):format(#(display.groups or {})))
                    row.updated:SetText(shortTime(display.latestAt))
                    row.data     = nil
                    row.kind     = "category"
                    row.groupKey = display.key
                    row:SetRowVisual(rowIndex, self.expanded[display.key], "group")
                    row:Show()
                    y = y - 26
                else
                    local group = display.group
                    rowIndex = rowIndex + 1
                    local row = ensureRow(rowIndex)
                    row:SetPoint("TOPLEFT", 0, y)
                    row:SetPoint("TOPRIGHT", 0, y)
                    row:SetSize(contentW, 30)
                    row.icon:Show()
                    local itemName, itemQuality, icon = itemVisual(group.recipe)
                    if isEnchanting(group.professionName) and group.enchantSlot ~= "Other" then
                        icon = ENCHANT_ICON
                    elseif isEnchanting(group.professionName) and icon == QUESTION_ICON then
                        icon = professionIcon("Enchanting")
                    end
                    row.icon:SetTexture(icon)
                    if row.iconBorder then row.iconBorder:SetQuality(itemQuality) end
                    row.chev:SetText(self.expanded[group.key] and "-" or "+")
                    row.name:SetText((display.nested and "  " or "") .. itemName)
                    row.name:SetTextColor(qualityColor(itemQuality))
                    row.prof:SetText(group.professionName or "-")
                    row.makers:SetText(tostring(#group.makers))
                    row.updated:SetText(shortTime(group.latestAt))
                    row.data     = { recipe = group.recipe }
                    row.kind     = "craft"
                    row.groupKey = group.key
                    row:SetRowVisual(rowIndex, self.expanded[group.key])
                    row:Show()
                    y = y - 30

                    if self.expanded[group.key] then
                        for _, maker in ipairs(group.makers) do
                            rowIndex = rowIndex + 1
                            local makerRow = ensureRow(rowIndex)
                            makerRow:SetPoint("TOPLEFT", 0, y)
                            makerRow:SetPoint("TOPRIGHT", 0, y)
                            makerRow:SetSize(contentW, 22)
                            makerRow.icon:Hide()
                            if makerRow.iconBorder then makerRow.iconBorder:Hide() end   -- no item icon on maker rows -> no border
                            makerRow.chev:SetText("")
                            local statusInfo = profileStatus(maker.profile, statusMap)
                            local classToken = isCurrentProfile(maker.profile) and currentPlayerClass()
                                or normalizeClass(maker.profile and maker.profile.class)
                                or (statusInfo and statusInfo.class)
                            local r, g, b = classColor(classToken)
                            local online = statusInfo and statusInfo.online
                            local status = online and coloredText("Online", 0.28, 0.95, 0.42) or coloredText("Offline", 0.95, 0.24, 0.24)
                            makerRow.name:SetWidth(190)
                            makerRow.name:SetText("  " .. coloredText(playerName(maker.profile), r, g, b))
                            makerRow.name:SetTextColor(1, 1, 1, 1)
                            makerRow.prof:ClearAllPoints()
                            makerRow.prof:SetPoint("LEFT", 250, 0)
                            makerRow.prof:SetWidth(92)
                            makerRow.prof:SetJustifyH("CENTER")
                            makerRow.prof:SetText(status)
                            makerRow.prof:SetTextColor(1, 1, 1, 1)
                            local rank    = maker.profession and maker.profession.rank
                            local maxRank = maker.profession and maker.profession.maxRank
                            makerRow.makers:SetText(rank and maxRank
                                and ("%s %d/%d"):format(group.professionName or "-", rank, maxRank)
                                or group.professionName or "-")
                            makerRow.makers:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
                            makerRow.updated:SetText(shortTime(
                                (maker.profession and maker.profession.updatedAt)
                                or (maker.profile  and maker.profile.updatedAt)))
                            makerRow.data     = { recipe = group.recipe }
                            makerRow.kind     = "maker"
                            makerRow.groupKey = nil
                            makerRow:SetRowVisual(rowIndex, false)
                            makerRow:Show()
                            y = y - 22
                        end
                    end
                end
            end

            self.content:SetHeight(math.max(self.scroll:GetHeight() or 1, -y))
            self.scrollBar:Update()
        end

        -- Button click handlers
        scanBtn:SetScript("OnClick", function()
            local sc = ns:GetModule("ProfessionsScanner"); if sc and sc.ScanOpen then sc:ScanOpen() end
            f:InvalidateTree()   -- a scan can add recipes -> rebuild the tree
            f:Refresh()
        end)
        shareBtn:SetScript("OnClick", function()
            local sy = ns:GetModule("ProfessionsSync")
            if sy and sy.BroadcastManifest then sy:BroadcastManifest(); ns:Print("Profession summary shared.", "success") end
        end)
        requestBtn:SetScript("OnClick", function()
            local sy = ns:GetModule("ProfessionsSync"); if sy and sy.BeginManualSync then sy:BeginManualSync() end
        end)

        -- Resize re-render
        scroll:SetScript("OnSizeChanged", function() f:Refresh() end)

        -- Coalesce GET_ITEM_INFO_RECEIVED into a single debounced refresh. Items stream
        -- into the client cache for ~30s after login; refreshing per-item caused the
        -- category list to churn (and bucket keys to flap as names resolved), which made
        -- category-expand clicks need several tries. One refresh after the burst settles fixes it.
        -- Drop the cached craft tree so the next Refresh rebuilds it. Call ONLY when the
        -- underlying profile data changed (scan/sync) — never on expand/scroll/resize.
        function f:InvalidateTree()
            self._treeCache = nil
            self._treeCacheKey = nil
        end

        function f:RefreshSoon()
            if not C_Timer then self:Refresh(); return end
            self._refreshToken = (self._refreshToken or 0) + 1
            local token = self._refreshToken
            C_Timer.After(0.4, function()
                if self._refreshToken == token and self:IsShown() then
                    -- Item info finished streaming in: re-stamp qualities on the CACHED groups
                    -- (cheap) so newly-resolved rarities re-sort correctly, without paying for a
                    -- full RecipeRows rebuild during the ~30s post-login item-cache burst.
                    if self._treeCache and self._treeCache.groups then
                        Panel:StampGroupQualities(self._treeCache.groups)
                    end
                    self:Refresh()
                end
            end)
        end

        f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        f:SetScript("OnEvent", function(self, event)
            if event == "GET_ITEM_INFO_RECEIVED" then self:RefreshSoon() end
        end)

        f:SetScript("OnShow", function()
            local s = ns:GetModule("ProfessionsSync"); if s and s.SetPanelOpen then s:SetPanelOpen(true) end
            f.searchText = ""
            if f.searchBox then f.searchBox:SetText("") end
            f:Refresh()
        end)

        f:SetScript("OnHide", function()
            local sync = ns:GetModule("ProfessionsSync")
            if sync and sync.SetPanelOpen then sync:SetPanelOpen(false) end
        end)

        Panel:SetFrame(f)
        return f
    end

    Nav:RegisterPanel("professions", buildPanel)
end
