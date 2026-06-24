local ADDON, ns = ...

local Panel = ns:NewModule("SettingsPanel")

local function db() return ns:GetModule("DB").db end

-- Lenient read: nil counts as the supplied default (matches the old `~= false`).
local function getBool(path, default)
    local d = db()
    local v = d
    for _, k in ipairs(path) do v = v and v[k] end
    if v == nil then return default end
    return v and true or false
end

local function setPath(path, value)
    local d = db()
    if not d then return end
    for i = 1, #path - 1 do
        d[path[i]] = d[path[i]] or {}
        d = d[path[i]]
    end
    d[path[#path]] = value
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local f = W:Card(parent, "base", true)  -- flat: no top-light line across the panel top

    local controls = {}
    local y = -20

    local function header(title, desc)
        local h = W:SectionHeader(f, title, desc)
        h:SetPoint("TOPLEFT", 24, y)
        h:SetPoint("RIGHT", -24, 0)
        y = y - (desc and 44 or 28)
    end

    local function checkbox(label, getFn, setFn)
        local cb = W:Checkbox(f, label, getFn, setFn)
        cb:SetPoint("TOPLEFT", 24, y)
        y = y - 26
        controls[#controls + 1] = { cb = cb, get = getFn }
        return cb
    end

    header("General", "Addon display and debug options.")

    checkbox("Hide minimap button",
        function() return getBool({"minimap", "hide"}, false) end,
        function(v)
            setPath({"minimap", "hide"}, v)
            local mm = ns:GetModule("Minimap"); if mm then mm:SetHidden(v) end
        end)

    checkbox("Enable verbose debug logging",
        function() return getBool({"debug"}, false) end,
        function(v)
            setPath({"debug"}, v)
            ns:Print(v and "Debug logging enabled" or "Debug logging disabled", v and "success" or nil)
        end)

    y = y - 14
    header("Loot Notifications", "Notify you when loot is assigned to your character.")

    checkbox("Show chat message",
        function() return getBool({"settings", "notificationSettings", "showLootChatMessage"}, true) end,
        function(v) setPath({"settings", "notificationSettings", "showLootChatMessage"}, v) end)

    checkbox("Show screen popup",
        function() return getBool({"settings", "notificationSettings", "showLootPopup"}, true) end,
        function(v) setPath({"settings", "notificationSettings", "showLootPopup"}, v) end)

    function f:Refresh()
        for _, c in ipairs(controls) do c.cb:SetChecked(c.get()) end
    end

    return f
end
