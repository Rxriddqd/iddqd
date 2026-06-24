local ADDON, ns = ...

-- Import hub: paste a shareable string and route it to the right subsystem's existing decoder.
-- Reuses the proven codecs (Council:ImportText, RaidGroups Decoder, AutoMarking:ImportProfileString)
-- rather than reinventing any parsing.

local Panel = ns:NewModule("ImportPanel")

local TYPES = {
    { value = "council",    label = "Council Loot Assignments" },
    { value = "raidgroups", label = "Raid Group Layout" },
    { value = "automark",   label = "Auto-Marking Profile" },
}

-- Each importer takes the pasted text, returns ok(boolean), message(string).
local function importCouncil(text)
    local c = ns:GetModule("Council")
    if not c or not c.ImportText then return false, "Council module unavailable." end
    local imported, err = c:ImportText(text, { share = false })
    if not imported then return false, tostring(err or "Invalid council import string.") end
    local n = imported.assignments and #imported.assignments or 0
    return true, ("Imported %d council assignment%s."):format(n, n == 1 and "" or "s")
end

local function importRaidGroups(text)
    local RG = ns:GetModule("RaidGroups")
    local Decoder = ns.raid_groups_decoder
    if not RG or not Decoder then return false, "Raid Groups module unavailable." end
    local ok, decoded = pcall(Decoder.Decode, text)
    if not ok or type(decoded) ~= "table" then return false, "Invalid raid group string." end
    if RG.SaveProfiles then RG:SaveProfiles(decoded) end
    return true, "Raid group layout imported."
end

local function importAutoMark(text)
    local AM = ns:GetModule("AutoMarking")
    if not AM or not AM.ImportProfileString then return false, "Auto-Marking module unavailable." end
    local profile, err = AM:ImportProfileString(text)
    if not profile then return false, tostring(err or "Invalid auto-marking string.") end
    return true, "Auto-marking profile imported."
end

local IMPORTERS = { council = importCouncil, raidgroups = importRaidGroups, automark = importAutoMark }

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)
    f._type = "council"

    local title = W:Title(f, "Import")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Paste a shared string to import it into the chosen system.")

    -- Type selector
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

    -- Paste box (multi-line)
    local box = W:Card(f, "raised", true)
    box:SetPoint("TOPLEFT", 18, -96)
    box:SetPoint("BOTTOMRIGHT", -18, 56)
    box:EnableMouse(true)
    local hint = box:CreateFontString(nil, "OVERLAY")
    Theme:Text(hint, "body", "faint")
    hint:SetPoint("TOPLEFT", 10, -8)
    hint:SetText("Paste import string here…")
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    edit:SetPoint("TOPLEFT", 8, -8)
    edit:SetPoint("BOTTOMRIGHT", -8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self) hint:SetShown((self:GetText() or "") == "") end)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Status + import button
    local status = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "caption", "dim")
    status:SetPoint("BOTTOMLEFT", 18, 20)
    status:SetPoint("RIGHT", -160, 0)
    status:SetJustifyH("LEFT")

    local importBtn = W:Button(f, "Import", 120, 26)
    importBtn:SetTone("blue")
    importBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    importBtn:SetScript("OnClick", function()
        local text = edit:GetText() or ""
        if text == "" then
            status:SetText("Nothing to import.")
            status:SetTextColor(Theme.color.danger[1], Theme.color.danger[2], Theme.color.danger[3], 1)
            return
        end
        local fn = IMPORTERS[f._type]
        local ok, msg = fn(text)
        status:SetText(msg)
        local c = ok and Theme.color.success or Theme.color.danger
        status:SetTextColor(c[1], c[2], c[3], 1)
        if ok then edit:SetText("") end
    end)

    function f:Refresh() if typeDD.Refresh then typeDD:Refresh() end end
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("import", function(parent)
        return Panel:Build(parent)
    end)
end

return Panel
