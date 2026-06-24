local ADDON, ns = ...

-- Visual Note panel: a big auto-saving notepad with optional post-to-chat buttons.

local Panel = ns:NewModule("VisualNotePanel")

local function VN() return ns:GetModule("VisualNote") end

local function buildPanel(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)

    local title = W:Title(f, "Visual Note")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("A personal scratchpad — auto-saved. Optionally post it to chat.")

    -- Editor
    local box = W:Card(f, "raised", true)
    box:SetPoint("TOPLEFT", 18, -58)
    box:SetPoint("BOTTOMRIGHT", -18, 52)
    box:EnableMouse(true)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 13, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    edit:SetPoint("TOPLEFT", 8, -8)
    edit:SetPoint("BOTTOMRIGHT", -8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Auto-save on every change (cheap) and on focus loss.
    local function save(self) local vn = VN(); if vn then vn:Set(self:GetText()) end end
    edit:SetScript("OnTextChanged", save)
    edit:SetScript("OnEditFocusLost", save)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.edit = edit

    local ph = box:CreateFontString(nil, "OVERLAY")
    Theme:Text(ph, "body", "faint")
    ph:SetPoint("TOPLEFT", 10, -8)
    ph:SetText("Write anything — raid plan, reminders, cooldown rotations…")
    f.ph = ph

    -- Post buttons
    local postRaid = W:Button(f, "Post to Raid", 110, 24)
    postRaid:SetPoint("BOTTOMLEFT", 18, 16)
    postRaid:SetScript("OnClick", function()
        if VN() and VN():Post("RAID") then ns:Print("Posted note to raid/party.", "success")
        else ns:Print("Nothing to post (empty note or not grouped).", "warning") end
    end)
    local postGuild = W:Button(f, "Post to Guild", 110, 24)
    postGuild:SetPoint("LEFT", postRaid, "RIGHT", 8, 0)
    postGuild:SetScript("OnClick", function()
        if VN() and VN():Post("GUILD") then ns:Print("Posted note to guild.", "success")
        else ns:Print("Nothing to post (empty note or not in a guild).", "warning") end
    end)
    local clearBtn = W:Button(f, "Clear", 70, 24)
    clearBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    clearBtn:SetScript("OnClick", function()
        W:Confirm("IDDQD_VISNOTE_CLEAR", "Clear the note?", function()
            if VN() then VN():Set("") end
            f:Refresh()
        end)
    end)

    function f:Refresh()
        local text = (VN() and VN():Get()) or ""
        self.edit:SetText(text)
        self.ph:SetShown(text == "")
    end
    edit:SetScript("OnTextChanged", function(self) save(self); f.ph:SetShown((self:GetText() or "") == "") end)

    f:Refresh()
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("visnote", buildPanel)
end

return Panel
