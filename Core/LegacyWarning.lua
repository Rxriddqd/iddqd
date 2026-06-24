local ADDON, ns = ...

local LegacyWarning = ns:NewModule("LegacyWarning")

local LEGACY_ADDONS = {
    { name = "iddqdapp", folder = "iddqdapp" },
    { name = "iddqd_app", folder = "iddqd_app" },
    { name = "iddqd_app_dev", folder = "iddqd_app_dev" },
}

local function addonLoaded(addonName)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, addonName)
    return ok and loaded and true or false
end

local function detectLegacyAddons()
    local found = {}
    for _, legacy in ipairs(LEGACY_ADDONS) do
        if legacy.name ~= ADDON then
            if addonLoaded(legacy.name) then
                found[#found + 1] = {
                    name = legacy.name,
                    folder = legacy.folder,
                    loaded = true,
                }
            end
        end
    end
    return found
end

local function folderList(found)
    local out = {}
    for _, addon in ipairs(found or {}) do
        out[#out + 1] = addon.folder or addon.name
    end
    return table.concat(out, ", ")
end

local function showPopup(message)
    if not StaticPopupDialogs or not StaticPopup_Show then return false end
    StaticPopupDialogs.IDDQD_LEGACY_ADDON_WARNING = StaticPopupDialogs.IDDQD_LEGACY_ADDON_WARNING or {
        text = "%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("IDDQD_LEGACY_ADDON_WARNING", message)
    return true
end

function LegacyWarning:OnEnable()
    if self.warned then return end
    self.warned = true
    local function warn()
        local found = detectLegacyAddons()
        if #found == 0 then return end

        local folders = folderList(found)
        local message = ("Old iddqd addon folder detected: %s.\n\nPlease exit the game and delete the old folder from Interface\\AddOns. Keeping both addons installed can cause duplicate windows, slash commands, and stale data."):format(folders)
        ns:Print(("Old iddqd addon detected (%s). Delete the old folder from Interface\\AddOns to avoid duplicate addons."):format(folders), "warning")
        showPopup(message)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(4, warn)
    else
        warn()
    end
end
