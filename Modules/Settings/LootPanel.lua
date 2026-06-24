local ADDON, ns = ...

local Panel = ns:NewModule("LootSettingsPanel")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function getPath(path, default)
    local value = db()
    for _, key in ipairs(path) do
        value = value and value[key]
    end
    if value == nil then return default end
    return value
end

local function setPath(path, value)
    local root = db()
    if not root then return end
    local target = root
    for i = 1, #path - 1 do
        target[path[i]] = target[path[i]] or {}
        target = target[path[i]]
    end
    target[path[#path]] = value
end

local function getBool(path, default)
    local value = getPath(path, default)
    return value and true or false
end

local function listToText(list)
    if type(list) ~= "table" then return "" end
    return table.concat(list, ", ")
end

local function textToList(text)
    local out = {}
    for name in tostring(text or ""):gmatch("[^,%s]+") do
        out[#out + 1] = name
    end
    return out
end

local function makeEdit(parent, width, height)
    local host = ns:GetModule("Widgets"):TextInput(parent, { width = width or 220, height = height or 24 })
    return host, host.edit
end

-- Quality dropdown labels coloured to each rarity. Prefer Blizzard's own ITEM_QUALITY_COLORS
-- hex; fall back to the standard palette so it works even if that global is unavailable.
local QUALITY_HEX = {
    [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00",
    [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
}
local function qualityColored(q, text)
    local hex
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] and ITEM_QUALITY_COLORS[q].hex then
        -- ITEM_QUALITY_COLORS[q].hex is a full "|cffRRGGBB" prefix already.
        return ITEM_QUALITY_COLORS[q].hex .. text .. "|r"
    end
    hex = QUALITY_HEX[q] or "ffffff"
    return ("|cff%s%s|r"):format(hex, text)
end

local QUALITY_ITEMS = {
    { value = 0, label = qualityColored(0, "Poor") },
    { value = 1, label = qualityColored(1, "Common") },
    { value = 2, label = qualityColored(2, "Uncommon") },
    { value = 3, label = qualityColored(3, "Rare") },
    { value = 4, label = qualityColored(4, "Epic") },
    { value = 5, label = qualityColored(5, "Legendary") },
}

local ROLE_ITEMS = {
    { value = "assist", label = "Leader or Assist" },
    { value = "leader", label = "Leader Only" },
    { value = "any", label = "Any Player" },
}

local CHANNEL_ITEMS = {
    { value = "RAID", label = "Raid" },
    { value = "RAID_WARNING", label = "Raid Warning" },
    { value = "PARTY", label = "Party" },
    { value = "GUILD", label = "Guild" },
}

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)

    local title = W:Title(f, "Loot Settings")
    title:SetPoint("TOPLEFT", 12, -12)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    sub:SetText("Council-aware loot behavior, notifications, and officer automation.")

    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 12, -58)
    sf:SetPoint("BOTTOMRIGHT", -24, 12)
    f.scroll = sf
    f.content = content
    f.bar = W:ScrollBar(sf, content)
    content:SetWidth(760)

    local controls = {}
    local y = 0
    local function header(text, desc)
        local h = W:SectionHeader(content, text, desc)
        h:SetPoint("TOPLEFT", 0, y)
        h:SetPoint("RIGHT", 0, 0)
        y = y - (desc and 44 or 28)
    end
    local function checkbox(label, path, default)
        local cb = W:Checkbox(content, label, function() return getBool(path, default) end, function(v) setPath(path, v) end)
        cb:SetPoint("TOPLEFT", 0, y)
        y = y - 25
        controls[#controls + 1] = { type = "checkbox", widget = cb, path = path, default = default }
        return cb
    end
    local function dropdown(label, path, items, width, default)
        local text = content:CreateFontString(nil, "OVERLAY")
        Theme:Text(text, "caption", "dim")
        text:SetPoint("TOPLEFT", 0, y - 4)
        text:SetWidth(180)
        text:SetJustifyH("LEFT")
        text:SetText(label)
        local dd = W:Dropdown(content, {
            width = width or 150,
            height = 22,
            sharp = true,
            get = function() return getPath(path, default) end,
            set = function(v) setPath(path, v) end,
            items = function() return items end,
        })
        dd:SetPoint("LEFT", text, "RIGHT", 8, 0)
        y = y - 28
        controls[#controls + 1] = { type = "dropdown", widget = dd }
        return dd
    end

    header("Council Notifications", "Shown when the shared website plan assigns loot to your character.")
    checkbox("Show chat message for my assignments", { "settings", "notificationSettings", "showLootChatMessage" }, true)
    checkbox("Show centered popup for my assignments", { "settings", "notificationSettings", "showLootPopup" }, true)

    y = y - 8
    header("Loot Display", "Controls how the loot and council surfaces filter and present assignment data.")
    checkbox("Filter item choices by class", { "settings", "lootSettings", "filterByClass" }, true)
    checkbox("Show all items even when class filters exist", { "settings", "lootSettings", "showAllItems" }, false)
    -- Mini-loot window controls now live on the Loot tab itself (the window auto-opens for
    -- everyone by default; the opt-out + combat-close toggles are next to "Ask Raid").

    y = y - 8
    header("Auto Need", "Disabled by default. When enabled, only rolls Need on council-assigned loot for your own character.")
    checkbox("Enable auto-need on assigned loot", { "settings", "lootSettings", "autoNeed", "enabled" }, false)
    dropdown("Who may auto-need", { "settings", "lootSettings", "autoNeed", "roleRequirement" }, ROLE_ITEMS, 170, "assist")
    checkbox("Auto-need uncommon items", { "settings", "lootSettings", "autoNeed", "rarities", 2 }, false)
    checkbox("Auto-need rare items", { "settings", "lootSettings", "autoNeed", "rarities", 3 }, true)
    checkbox("Auto-need epic items", { "settings", "lootSettings", "autoNeed", "rarities", 4 }, true)
    checkbox("Auto-need legendary items", { "settings", "lootSettings", "autoNeed", "rarities", 5 }, false)

    y = y - 8
    header("Master Loot", "Disabled by default. Uses council assignments as the only source for automatic distribution.")
    checkbox("Enable council auto-master-loot", { "settings", "lootSettings", "autoMasterLoot" }, false)
    checkbox("Allow auto trade helper", { "settings", "lootSettings", "autoTradeEnabled" }, true)
    checkbox("Announce manual assignments", { "settings", "lootSettings", "announceAssignments" }, false)

    y = y - 8
    header("Loot Announcements", "Optional chat announcements for drops and council/master-loot actions.")
    checkbox("Enable loot announcements", { "settings", "lootSettings", "announceLoot", "enabled" }, false)
    dropdown("Announcement channel", { "settings", "lootSettings", "announceLoot", "channel" }, CHANNEL_ITEMS, 150, "RAID")
    dropdown("Minimum quality", { "settings", "lootSettings", "announceLoot", "minQuality" }, QUALITY_ITEMS, 150, 4)
    checkbox("Announce drops", { "settings", "lootSettings", "announceLoot", "announceDrops" }, false)
    checkbox("Announce assignments", { "settings", "lootSettings", "announceLoot", "announceAssignments" }, false)
    checkbox("Announce master-loot distribution", { "settings", "lootSettings", "announceLoot", "announceMasterLoot" }, false)

    y = y - 8
    header("Auto Assist", "Comma-separated characters to promote when you are leader.")
    checkbox("Enable auto-assist names", { "settings", "lootSettings", "autoAssistEnabled" }, true)
    local assistHost, assistEdit = makeEdit(content, 360, 24)
    assistHost:SetPoint("TOPLEFT", 0, y)
    assistEdit:SetText(listToText(getPath({ "settings", "lootSettings", "autoAssistNames" }, {})))
    assistEdit:SetScript("OnEditFocusLost", function(self)
        setPath({ "settings", "lootSettings", "autoAssistNames" }, textToList(self:GetText()))
    end)
    y = y - 34

    content:SetHeight(math.max(1, -y + 10))
    if f.bar then f.bar:Update() end

    function f:Refresh()
        for _, entry in ipairs(controls) do
            if entry.type == "checkbox" then
                entry.widget:SetChecked(getBool(entry.path, entry.default))
            elseif entry.type == "dropdown" and entry.widget.Refresh then
                entry.widget:Refresh()
            end
        end
        assistEdit:SetText(listToText(getPath({ "settings", "lootSettings", "autoAssistNames" }, {})))
        if self.bar then self.bar:Update() end
    end

    return f
end
