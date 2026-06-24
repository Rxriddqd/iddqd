local ADDON, ns = ...

-- SetRole: adds a "Set Role (by iddqd)" submenu to the unit right-click menu (your own
-- portrait, target/party/raid unit menus) so a raid leader / assist can set a player's
-- Blizzard raid role (Tank / Healer / DPS / No Role). Mirrors the flow MoveAny uses.
--
-- Uses the modern Menu.ModifyMenu API (present on the Anniversary TBC client). Every WoW
-- global is guarded so the file loads and cleanly no-ops on a client without it (e.g. an
-- older Era build that lacks the role system) — nothing else in the addon depends on it.

local SetRole = ns:NewModule("SetRole")

-- The three settable roles + No Role, in display order. The icon coords index into the
-- shared LFG portrait-roles atlas texture (same swatches Blizzard's own role checker uses).
local ROLES = {
    { role = "TANK",    label = "Tank",   coords = "0:19:22:41" },
    { role = "HEALER",  label = "Healer", coords = "20:39:1:20" },
    { role = "DAMAGER", label = "DPS",    coords = "20:39:22:41" },
}
local ROLE_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:%s|t "

-- Which roles a class may take (so we don't offer Tank to a Mage, etc.). Conservative TBC
-- set; an unknown class falls through to "all allowed" rather than hiding everything.
local CLASS_ROLES = {
    WARRIOR     = { TANK = true, DAMAGER = true },
    PALADIN     = { TANK = true, HEALER = true, DAMAGER = true },
    DEATHKNIGHT = { TANK = true, DAMAGER = true },
    HUNTER      = { DAMAGER = true },
    SHAMAN      = { HEALER = true, DAMAGER = true },
    ROGUE       = { DAMAGER = true },
    DRUID       = { TANK = true, HEALER = true, DAMAGER = true },
    MAGE        = { DAMAGER = true },
    WARLOCK     = { DAMAGER = true },
    PRIEST      = { HEALER = true, DAMAGER = true },
    MONK        = { TANK = true, HEALER = true, DAMAGER = true },
}

local function currentRole(unit)
    if not UnitGroupRolesAssigned then return "NONE" end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return (ok and role) or "NONE"
end

local function classCanBe(unit, role)
    if not UnitClass then return true end
    local _, class = UnitClass(unit)
    local set = class and CLASS_ROLES[class]
    if not set then return true end          -- unknown class -> don't restrict
    return set[role] == true
end

-- May the local player set THIS unit's role? Own role always; others only as leader/assist.
local function canSet(unit)
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
    return (leader or assist) and true or false
end

-- Build the submenu onto an existing root menu description (Menu.ModifyMenu callback).
function SetRole:Populate(rootDescription, contextData)
    if not rootDescription or not contextData then return end
    local unit = contextData.unit
    if not unit then return end
    if not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
    if not ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())) then return end
    if not UnitSetRole then return end       -- client without the role setter: no menu

    -- Avoid inserting twice if the callback fires more than once for one menu.
    if rootDescription.EnumerateElementDescriptions then
        for _, el in rootDescription:EnumerateElementDescriptions() do
            if el.iddqdSetRole then return end
        end
    end

    local submenu = MenuUtil.CreateButton("Set Role (by iddqd)")
    submenu.iddqdSetRole = true
    rootDescription:Insert(submenu, 2)
    submenu:SetEnabled(canSet(unit))

    for _, def in ipairs(ROLES) do
        local label = ROLE_ICON:format(def.coords) .. def.label
        local btn = submenu:CreateRadio(
            label,
            function() return currentRole(unit) == def.role end,
            function() pcall(UnitSetRole, unit, def.role) end
        )
        if btn and btn.SetEnabled then btn:SetEnabled(classCanBe(unit, def.role)) end
    end

    submenu:CreateRadio(
        "No Role",
        function() return currentRole(unit) == "NONE" end,
        function() pcall(UnitSetRole, unit, "NONE") end
    )
end

function SetRole:OnEnable()
    if self._enabled then return end
    -- Require the modern menu API + role setter; otherwise stay dormant (older/Era clients).
    if not (Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.CreateButton and UnitSetRole) then
        return
    end
    self._enabled = true

    local menuTypes = {
        "MENU_UNIT_SELF", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
        "MENU_UNIT_PARTY", "MENU_UNIT_RAID", "MENU_UNIT_PLAYER", "MENU_UNIT_RAID_PLAYER",
    }
    for _, menuType in ipairs(menuTypes) do
        pcall(Menu.ModifyMenu, menuType, function(_, rootDescription, contextData)
            self:Populate(rootDescription, contextData)
        end)
    end
end

return SetRole
