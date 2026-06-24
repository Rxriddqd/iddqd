local ADDON, ns = ...

-- Raid Assignments panel: manage named assignment sets and post the active one to chat.

local Panel = ns:NewModule("RaidAssignmentsPanel")

local function RA() return ns:GetModule("RaidAssignments") end

local function buildPanel(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)
    f.rows = {}
    Panel.frame = f   -- exposed so RaidAssignments sync can refresh on incoming data

    local title = W:Title(f, "Raid Assignments")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Write tank/heal/interrupt notes per set, then post them to the raid.")

    -- Left rail: set list + New
    local rail = W:Card(f, "overlay", true)
    rail:SetPoint("TOPLEFT", 14, -58)
    rail:SetPoint("BOTTOMLEFT", 14, 14)
    rail:SetWidth(210)

    local newBtn = W:Button(rail, "New Set", 90, 22)
    newBtn:SetTone("blue")
    newBtn:SetPoint("TOPLEFT", 10, -10)
    newBtn:SetScript("OnClick", function()
        local r = RA(); if r then local s = r:CreateSet("New Set"); if s then r:Select(s.id) end end
        f:Refresh()
    end)

    local railScroll, railContent = W:ScrollHost(rail)
    railScroll:SetPoint("TOPLEFT", 8, -42)
    railScroll:SetPoint("BOTTOMRIGHT", -8, 10)
    f.railScroll, f.railContent = railScroll, railContent
    f.railBar = W:ScrollBar(railScroll, railContent)

    -- Right pane: name + note editor + post buttons
    local pane = W:Card(f, "overlay", true)
    pane:SetPoint("TOPLEFT", rail, "TOPRIGHT", 12, 0)
    pane:SetPoint("BOTTOMRIGHT", -14, 14)

    local nameHost = W:TextInput(pane, { placeholder = "Set name…", width = 240, height = 24, inset = 6 })
    nameHost:SetPoint("TOPLEFT", 12, -12)
    f.nameHost = nameHost
    nameHost.edit:SetScript("OnEditFocusLost", function(self)
        local s = RA() and RA():Selected()
        if s then RA():RenameSet(s.id, self:GetText()); f:RefreshRail() end
    end)

    local delBtn = W:Button(pane, "Delete", 72, 24)
    delBtn:SetPoint("TOPRIGHT", -12, -12)
    delBtn:SetScript("OnClick", function()
        local s = RA() and RA():Selected()
        if not s then return end
        W:Confirm("IDDQD_RA_DELETE", "Delete this assignment set?", function()
            RA():DeleteSet(s.id); f:Refresh()
        end)
    end)

    -- Note editor
    local noteBox = W:Card(pane, "raised", true)
    noteBox:SetPoint("TOPLEFT", 12, -48)
    noteBox:SetPoint("BOTTOMRIGHT", -12, 52)
    noteBox:EnableMouse(true)
    local noteEdit = CreateFrame("EditBox", nil, noteBox)
    noteEdit:SetMultiLine(true)
    noteEdit:SetAutoFocus(false)
    noteEdit:SetFont(Theme.font, 13, "")
    noteEdit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    noteEdit:SetPoint("TOPLEFT", 8, -8)
    noteEdit:SetPoint("BOTTOMRIGHT", -8, 8)
    noteEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    noteEdit:SetScript("OnEditFocusLost", function(self)
        local s = RA() and RA():Selected()
        if s then RA():SetNote(s.id, self:GetText()) end
    end)
    noteBox:SetScript("OnMouseDown", function() noteEdit:SetFocus() end)
    f.noteEdit = noteEdit

    local notePH = noteBox:CreateFontString(nil, "OVERLAY")
    Theme:Text(notePH, "body", "faint")
    notePH:SetPoint("TOPLEFT", 10, -8)
    notePH:SetText("e.g.\nTanks: Bob (boss), Sue (adds)\nInterrupts: Joe > Amy > Max\nHeals: assigned by lead")
    notePH:SetJustifyH("LEFT")
    noteEdit:SetScript("OnTextChanged", function(self) notePH:SetShown((self:GetText() or "") == "") end)
    f.notePH = notePH

    local postRaid = W:Button(pane, "Post to Raid", 110, 24)
    postRaid:SetPoint("BOTTOMLEFT", 12, 14)
    postRaid:SetScript("OnClick", function()
        local s = RA() and RA():Selected()
        if s and RA():Post(s.id, "RAID") then ns:Print("Posted assignments to raid.", "success")
        else ns:Print("Nothing to post (empty note or not in a raid).", "warning") end
    end)
    local postRW = W:Button(pane, "Raid Warning", 110, 24)
    postRW:SetPoint("LEFT", postRaid, "RIGHT", 8, 0)
    postRW:SetScript("OnClick", function()
        local s = RA() and RA():Selected()
        if s and RA():Post(s.id, "RAID_WARNING") then ns:Print("Posted assignments (raid warning).", "success")
        else ns:Print("Nothing to post (empty note or not in a raid).", "warning") end
    end)

    -- Share via addon comms (other iddqd users receive it as a synced set). Manual only.
    local shareBtn = W:Button(pane, "Share (addon)", 110, 24)
    shareBtn:SetPoint("LEFT", postRW, "RIGHT", 8, 0)
    shareBtn:SetScript("OnClick", function()
        local s = RA() and RA():Selected()
        if s and RA():Share(s.id) then ns:Print("Shared assignments to the raid (addon).", "success")
        else ns:Print("Couldn't share (no set or not in a group).", "warning") end
    end)

    -- Rail row pool
    function f:EnsureRow(i)
        local row = self.rows[i]
        if row then return row end
        row = W:ListRow(railContent, true)
        row:SetHeight(24)
        row.label = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.label, "caption", "ink")
        row.label:SetPoint("LEFT", 8, 0); row.label:SetPoint("RIGHT", -8, 0); row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnMouseUp", function(self) if self._select then self._select() end end)
        self.rows[i] = row
        return row
    end

    function f:RefreshRail()
        for _, r in ipairs(self.rows) do r:Hide() end
        local sets = (RA() and RA():Sets()) or {}
        local selId = (RA() and RA():Selected() and RA():Selected().id) or nil
        local w = math.max(180, (railScroll:GetWidth() or 0) - 4)
        railContent:SetWidth(w)
        local y = 0
        for i, s in ipairs(sets) do
            local row = self:EnsureRow(i)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetSize(w, 24)
            row:SetRowVisual(i, s.id == selId)
            row.label:SetText(s.name or "Set")
            row._select = function() RA():Select(s.id); f:Refresh() end
            row:Show()
            y = y - 25
        end
        railContent:SetHeight(math.max(railScroll:GetHeight() or 1, -y))
        if self.railBar then self.railBar:Update() end
    end

    function f:Refresh()
        self:RefreshRail()
        local s = RA() and RA():Selected()
        if s then
            nameHost.edit:SetText(s.name or "")
            noteEdit:SetText(s.note or "")
            notePH:SetShown((s.note or "") == "")
            pane:Show()
        else
            nameHost.edit:SetText("")
            noteEdit:SetText("")
            notePH:SetShown(true)
        end
    end

    f:Refresh()
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("assignments", buildPanel)
end

return Panel
