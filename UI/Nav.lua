local ADDON, ns = ...

local Nav = ns:NewModule("Nav")

-- Ordered sections -> items. `panel` is the builder key a feature module will
-- register; until then the shell renders a placeholder.
Nav.sections = {
    { title = "iddqd", items = {
        { id = "overview",  label = "Overview", icon = "layout-dashboard" },
        { id = "loot",      label = "Loot",     icon = "gem" },
        { id = "council",   label = "Council",  icon = "gavel" },
        { id = "history",   label = "History",  icon = "history" },
        { id = "professions", label = "Professions", icon = "clipboard-check" },
        { id = "gamba",     label = "Gamba",    icon = "circle-play" },
    }},
    { title = "Raid Tools", items = {
        { id = "invite",        label = "Invite",          icon = "user-plus" },
        { id = "ready_check",   label = "Ready Check",     icon = "circle-check-big" },
        { id = "attendance",    label = "Attendance",      icon = "clipboard-check" },
        { id = "raid_groups",   label = "Raid Groups",     icon = "users" },
        { id = "auto_marking",  label = "Auto Marking",    icon = "target" },
        { id = "raid_map",      label = "Raid Map",        icon = "map",         badge = "NYI" },
        { id = "visnote",       label = "Visual Note",     icon = "pen-tool",    badge = "NYI" },
        { id = "assignments",   label = "Assignments",     icon = "list-checks", badge = "NYI" },
    }},
    { title = "Settings", items = {
        { id = "general",     label = "General",       icon = "settings" },
        { id = "permissions", label = "Permissions",   icon = "shield" },
        { id = "loot_set",    label = "Loot Settings", icon = "sliders-horizontal" },
    }},
    { title = "Data", items = {
        { id = "import", label = "Import", icon = "download" },
        { id = "export", label = "Export", icon = "upload" },
    }},
}

local panels = {}   -- [id] = function(parent) -> frame
function Nav:RegisterPanel(id, builder) panels[id] = builder end
function Nav:GetPanel(id) return panels[id] end
