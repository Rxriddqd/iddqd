local ADDON, ns = ...

local ClassSpec = {}

-- Class colors (Classic/TBC), keyed UPPERCASE. Ported from the old core.lua.
local CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER  = { 0.67, 0.83, 0.45 },
    ROGUE   = { 1.00, 0.96, 0.41 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    SHAMAN  = { 0.00, 0.44, 0.87 },
    MAGE    = { 0.41, 0.80, 0.94 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID   = { 1.00, 0.49, 0.04 },
}

-- spec -> built-in WoW talent-tab icon (no shipped art). Ported verbatim from the
-- old raid_assignments_viewer.lua SPEC_ICONS (keys are specKey()-normalized).
local SPEC_ICONS = {
    ["warrior-arms"]        = "Interface\\Icons\\ability_warrior_savageblow",
    ["warrior-fury"]        = "Interface\\Icons\\ability_warrior_innerrage",
    ["warrior-protection"]  = "Interface\\Icons\\ability_warrior_defensivestance",
    ["paladin-holy"]        = "Interface\\Icons\\spell_holy_holybolt",
    ["paladin-protection"]  = "Interface\\Icons\\spell_holy_devotionaura",
    ["paladin-retribution"] = "Interface\\Icons\\spell_holy_auraoflight",
    ["hunter-beastmastery"] = "Interface\\Icons\\ability_hunter_beasttaming",
    ["hunter-marksmanship"] = "Interface\\Icons\\ability_marksmanship",
    ["hunter-survival"]     = "Interface\\Icons\\ability_hunter_swiftstrike",
    ["rogue-assassination"] = "Interface\\Icons\\ability_rogue_eviscerate",
    ["rogue-combat"]        = "Interface\\Icons\\ability_backstab",
    ["rogue-subtlety"]      = "Interface\\Icons\\ability_stealth",
    ["priest-discipline"]   = "Interface\\Icons\\spell_holy_wordfortitude",
    ["priest-holy"]         = "Interface\\Icons\\spell_holy_guardianspirit",
    ["priest-shadow"]       = "Interface\\Icons\\spell_shadow_shadowwordpain",
    ["shaman-elemental"]    = "Interface\\Icons\\spell_nature_lightning",
    ["shaman-enhancement"]  = "Interface\\Icons\\spell_nature_lightningshield",
    ["shaman-restoration"]  = "Interface\\Icons\\spell_nature_magicimmunity",
    ["mage-arcane"]         = "Interface\\Icons\\spell_holy_magicalsentry",
    ["mage-fire"]           = "Interface\\Icons\\spell_fire_firebolt02",
    ["mage-frost"]          = "Interface\\Icons\\spell_frost_frostbolt02",
    ["warlock-affliction"]  = "Interface\\Icons\\spell_shadow_deathcoil",
    ["warlock-demonology"]  = "Interface\\Icons\\spell_shadow_metamorphosis",
    ["warlock-destruction"] = "Interface\\Icons\\spell_shadow_rainoffire",
    ["druid-balance"]       = "Interface\\Icons\\spell_nature_starfall",
    ["druid-feral"]         = "Interface\\Icons\\ability_druid_catform",
    ["druid-feralcombat"]   = "Interface\\Icons\\ability_druid_catform",
    ["druid-restoration"]   = "Interface\\Icons\\spell_nature_healingtouch",
}

-- Built-in class atlas + per-class {l,r,t,b} cells (verified vs MRT on this client).
local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_ICON_COORDS = {
    WARRIOR = { 0,           0.25,       0,    0.25 },
    MAGE    = { 0.25,        0.49609375, 0,    0.25 },
    ROGUE   = { 0.49609375,  0.7421875,  0,    0.25 },
    DRUID   = { 0.7421875,   0.98828125, 0,    0.25 },
    HUNTER  = { 0,           0.25,       0.25, 0.5  },
    SHAMAN  = { 0.25,        0.49609375, 0.25, 0.5  },
    PRIEST  = { 0.49609375,  0.7421875,  0.25, 0.5  },
    WARLOCK = { 0.7421875,   0.98828125, 0.25, 0.5  },
    PALADIN = { 0,           0.25,       0.5,  0.75 },
}

-- Ordered spec display names per class (the picker + fallbacks use this order). Druid
-- lists "Feral" once (the feralcombat key is an alias of feral).
local CLASS_SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat", "Subtlety" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MAGE    = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID   = { "Balance", "Feral", "Restoration" },
}

local HEALER_SPECS = {
    ["paladin-holy"] = true,
    ["priest-discipline"] = true,
    ["priest-holy"] = true,
    ["shaman-restoration"] = true,
    ["druid-restoration"] = true,
}

local TANK_SPECS = {
    ["warrior-protection"] = true,
    ["paladin-protection"] = true,
}

local DPS_SPECS = {
    ["warrior-arms"] = true,
    ["warrior-fury"] = true,
    ["paladin-retribution"] = true,
    ["hunter-beastmastery"] = true,
    ["hunter-marksmanship"] = true,
    ["hunter-survival"] = true,
    ["rogue-assassination"] = true,
    ["rogue-combat"] = true,
    ["rogue-subtlety"] = true,
    ["priest-shadow"] = true,
    ["shaman-elemental"] = true,
    ["shaman-enhancement"] = true,
    ["mage-arcane"] = true,
    ["mage-fire"] = true,
    ["mage-frost"] = true,
    ["warlock-affliction"] = true,
    ["warlock-demonology"] = true,
    ["warlock-destruction"] = true,
    ["druid-balance"] = true,
}

local ROLE_ALIASES = {
    tank = "tank",
    tanks = "tank",
    TANK = "tank",
    healer = "healer",
    heal = "healer",
    HEALER = "healer",
    dps = "dps",
    damager = "dps",
    damage = "dps",
    DAMAGER = "dps",
}

local ROLE_ATLASES = {
    tank = "groupfinder-icon-role-large-tank",
    healer = "groupfinder-icon-role-large-heal",
    dps = "groupfinder-icon-role-large-dps",
}

local ROLE_LABELS = {
    tank = "Tank",
    healer = "Healer",
    dps = "DPS",
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function ClassSpec.specKey(class, spec)
    if not class or not spec then return nil end
    return (class .. "-" .. spec):lower():gsub("%s", ""):gsub("'", "")
end

function ClassSpec.specIcon(class, spec)
    local key = ClassSpec.specKey(class, spec)
    return (key and SPEC_ICONS[key]) or FALLBACK_ICON
end

function ClassSpec.classColor(class)
    if not class then return { 1, 1, 1 } end
    -- Prefer the live client table; fall back to the ported colors.
    local up = class:upper()
    local g = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[up]
    if g and g.r then return { g.r, g.g, g.b } end
    return CLASS_COLORS[up] or { 1, 1, 1 }
end

-- The class icon as (texture, l, r, t, b). Unknown class -> the question-mark, full coords.
function ClassSpec.classIcon(class)
    local up = class and class:upper()
    local c = up and CLASS_ICON_COORDS[up]
    if c then return CLASS_ICON_TEX, c[1], c[2], c[3], c[4] end
    return FALLBACK_ICON, 0, 1, 0, 1
end

-- Ordered spec display names for a class (empty table if unknown).
function ClassSpec.specsForClass(class)
    local up = class and class:upper()
    return (up and CLASS_SPECS[up]) or {}
end

-- Is (class, spec) a known spec? (the picker validates against this.)
function ClassSpec.hasSpec(class, spec)
    local key = ClassSpec.specKey(class, spec)
    return key ~= nil and SPEC_ICONS[key] ~= nil
end

function ClassSpec.normalizeRole(role)
    if type(role) ~= "string" then return nil end
    return ROLE_ALIASES[role] or ROLE_ALIASES[role:lower()]
end

function ClassSpec.roleForSpec(class, spec, explicitRole)
    local normalized = ClassSpec.normalizeRole(explicitRole)
    if normalized then return normalized end
    local key = ClassSpec.specKey(class, spec)
    if not key then return nil end
    if TANK_SPECS[key] then return "tank" end
    if HEALER_SPECS[key] then return "healer" end
    if DPS_SPECS[key] then return "dps" end
    return nil
end

function ClassSpec.roleAtlas(role)
    local normalized = ClassSpec.normalizeRole(role)
    return normalized and ROLE_ATLASES[normalized] or nil
end

function ClassSpec.roleLabel(role)
    local normalized = ClassSpec.normalizeRole(role)
    return normalized and ROLE_LABELS[normalized] or nil
end

if type(ns) == "table" then ns.classSpec = ClassSpec end
return ClassSpec
