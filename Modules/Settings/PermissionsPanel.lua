local ADDON, ns = ...

-- Permissions panel: who in the guild may use the addon's officer-level features. Edits
-- db.settings.permissionSettings. Kept deliberately simple — a guild-rank cutoff per capability,
-- chosen from the guild's real rank names so officers never deal with raw rank numbers.

local Panel = ns:NewModule("PermissionsPanel")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function getPath(path, default)
    local value = db()
    for _, key in ipairs(path) do value = value and value[key] end
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

-- Build the dropdown items from the guild's actual ranks (0 = Guild Master, then officers...).
-- Falls back to numeric placeholders out of guild or before the roster loads.
local function rankItems()
    local items = {}
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    if n and n > 0 then
        for i = 0, n - 1 do
            local name = (GuildControlGetRankName and GuildControlGetRankName(i + 1)) or ("Rank " .. i)
            items[#items + 1] = { value = i, label = ("%d — %s"):format(i, name) }
        end
    else
        for i = 0, 9 do items[#items + 1] = { value = i, label = "Rank " .. i } end
    end
    return items
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)

    local title = W:Title(f, "Permissions")
    title:SetPoint("TOPLEFT", 12, -12)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    sub:SetText("Control which guild ranks may use the addon's shared/officer features.")

    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 12, -58)
    sf:SetPoint("BOTTOMRIGHT", -24, 12)
    f.scroll, f.content = sf, content
    f.bar = W:ScrollBar(sf, content)
    content:SetWidth(760)

    local controls = {}
    local y = 0
    local function header(text, desc)
        local h = W:SectionHeader(content, text, desc)
        h:SetPoint("TOPLEFT", 0, y); h:SetPoint("RIGHT", 0, 0)
        y = y - (desc and 44 or 28)
    end
    local function rankDropdown(label, path, default)
        local text = content:CreateFontString(nil, "OVERLAY")
        Theme:Text(text, "caption", "dim")
        text:SetPoint("TOPLEFT", 0, y - 4)
        text:SetWidth(280); text:SetJustifyH("LEFT")
        text:SetText(label)
        local dd = W:Dropdown(content, {
            width = 200, height = 22, sharp = true,
            get = function() return getPath(path, default) end,
            set = function(v) setPath(path, v) end,
            items = rankItems,
        })
        dd:SetPoint("LEFT", text, "RIGHT", 8, 0)
        y = y - 28
        controls[#controls + 1] = { type = "dropdown", widget = dd }
        return dd
    end

    header("Sync & Broadcast", "Highest guild rank (lower number = higher rank) allowed to broadcast addon data to the guild.")
    rankDropdown("Max rank that can broadcast data", { "settings", "permissionSettings", "canBroadcastMaxRank" }, 2)

    y = y - 8
    header("Note", "Loot distribution permission (Ask Raid / Award) is governed by raid role — raid leader or assist — not guild rank, and is configured automatically. Guild-rank gating applies to data sharing.")

    content:SetHeight(math.max(1, -y + 10))
    if f.bar then f.bar:Update() end

    function f:Refresh()
        for _, e in ipairs(controls) do
            if e.type == "dropdown" and e.widget.Refresh then e.widget:Refresh() end
        end
        if self.bar then self.bar:Update() end
    end

    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("permissions", function(parent)
        return Panel:Build(parent)
    end)
end

return Panel
