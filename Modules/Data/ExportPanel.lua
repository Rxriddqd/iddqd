local ADDON, ns = ...

-- Export hub: produce a shareable string for the chosen subsystem into a read-only box the user
-- can select-all and copy (WoW can't write the clipboard, so we focus + highlight on click).
-- Only data types with an available encoder are offered.

local Panel = ns:NewModule("ExportPanel")

local TYPES = {
    { value = "council",  label = "Council Loot Assignments" },
    { value = "automark", label = "Auto-Marking Profile" },
}

-- Each exporter returns string|nil, message. nil string = nothing to export.
local function exportCouncil()
    local c = ns:GetModule("Council")
    if not c or not c.Active then return nil, "Council module unavailable." end
    local active = c:Active()
    if not active then return nil, "No active council import to export." end
    local text = active.encoded or (c.EncodePayload and c:EncodePayload(active))
    if not text or text == "" then return nil, "Could not encode council data." end
    return text, "Council assignments ready — select all and copy."
end

local function exportAutoMark()
    local AM = ns:GetModule("AutoMarking")
    if not AM or not AM.ExportActiveProfileString then return nil, "Auto-Marking module unavailable." end
    local text = AM:ExportActiveProfileString()
    if not text or text == "" then return nil, "No active auto-marking profile to export." end
    return text, "Auto-marking profile ready — select all and copy."
end

local EXPORTERS = { council = exportCouncil, automark = exportAutoMark }

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)
    f._type = "council"

    local title = W:Title(f, "Export")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Generate a shareable string, then select all (Ctrl+A) and copy (Ctrl+C).")

    local typeLabel = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(typeLabel, "caption", "dim")
    typeLabel:SetPoint("TOPLEFT", 18, -64)
    typeLabel:SetText("Data type")
    local typeDD = W:Dropdown(f, {
        width = 240, height = 22, sharp = true,
        get = function() return f._type end,
        set = function(v) f._type = v end,
        items = function() return TYPES end,
    })
    typeDD:SetPoint("LEFT", typeLabel, "RIGHT", 10, 0)

    -- Output box (read-only-ish: editable so the user can select, but we re-fill on generate).
    local box = W:Card(f, "raised", true)
    box:SetPoint("TOPLEFT", 18, -96)
    box:SetPoint("BOTTOMRIGHT", -18, 56)
    box:EnableMouse(true)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    edit:SetPoint("TOPLEFT", 8, -8)
    edit:SetPoint("BOTTOMRIGHT", -8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Selecting the box highlights everything for an easy copy.
    box:SetScript("OnMouseDown", function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    f._edit = edit

    local status = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "caption", "dim")
    status:SetPoint("BOTTOMLEFT", 18, 20)
    status:SetPoint("RIGHT", -160, 0)
    status:SetJustifyH("LEFT")

    local genBtn = W:Button(f, "Generate", 120, 26)
    genBtn:SetTone("blue")
    genBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    genBtn:SetScript("OnClick", function()
        local fn = EXPORTERS[f._type]
        local text, msg = fn()
        if text then
            edit:SetText(text)
            edit:SetFocus()
            edit:HighlightText()
            status:SetTextColor(Theme.color.success[1], Theme.color.success[2], Theme.color.success[3], 1)
        else
            edit:SetText("")
            status:SetTextColor(Theme.color.danger[1], Theme.color.danger[2], Theme.color.danger[3], 1)
        end
        status:SetText(msg or "")
    end)

    function f:Refresh() if typeDD.Refresh then typeDD:Refresh() end end
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("export", function(parent)
        return Panel:Build(parent)
    end)
end

return Panel
