local ADDON, ns = ...

-- Attendance panel: take/list roster snapshots. Officer-facing view over the Attendance module.

local Panel = ns:NewModule("AttendancePanel")

local function A() return ns:GetModule("Attendance") end

local function fmtTime(epoch)
    epoch = tonumber(epoch)
    if not epoch or epoch == 0 then return "-" end
    if date then return date("%Y-%m-%d %H:%M", epoch) end
    return tostring(epoch)
end

local AUTO_MODES = {
    { value = "disabled", label = "Manual only" },
    { value = "first_pull", label = "First pull in each raid" },
    { value = "first_kill", label = "First boss kill in each raid" },
    { value = "every_pull", label = "Every pull" },
    { value = "every_kill", label = "Every boss kill" },
}

local REASON_LABELS = {
    manual = "Manual",
    pull = "Pull",
    kill = "Kill",
}

local function emptyGroups()
    local groups = {}
    for i = 1, 8 do groups[i] = {} end
    return groups
end

local function groupsFromSnapshot(snap)
    if snap and snap.groups then
        local groups = emptyGroups()
        for groupIndex = 1, 8 do
            local src = snap.groups[groupIndex] or snap.groups[tostring(groupIndex)] or {}
            for slot = 1, #src do groups[groupIndex][slot] = src[slot] end
        end
        return groups
    end

    local groups = emptyGroups()
    for i, name in ipairs((snap and snap.members) or {}) do
        local groupIndex = math.floor((i - 1) / 5) + 1
        if groupIndex <= 8 then groups[groupIndex][#groups[groupIndex] + 1] = name end
    end
    return groups
end

local function memberCount(snap)
    if snap and snap.members then return #snap.members end
    local total, groups = 0, groupsFromSnapshot(snap)
    for groupIndex = 1, 8 do total = total + #(groups[groupIndex] or {}) end
    return total
end

local function snapshotLabel(snap)
    local label = snap and snap.instance or "-"
    if snap and snap.encounter and snap.encounter ~= "" then label = label .. " - " .. snap.encounter end
    local reason = snap and REASON_LABELS[snap.reason or "manual"] or nil
    if reason and reason ~= "Manual" then label = reason .. ": " .. label end
    return label
end

local function classForSnapshotName(snap, name)
    if not (snap and snap.classes and name) then return nil end
    return snap.classes[name] or snap.classes[tostring(name)]
end

local function classColor(classFile, Theme)
    if classFile and ns.classSpec and ns.classSpec.classColor then
        local c = ns.classSpec.classColor(classFile)
        if c then return c[1], c[2], c[3], 1 end
    end
    local c = Theme.color.ink
    return c[1], c[2], c[3], 1
end

local function setClassIcon(tex, classFile)
    if classFile and ns.classSpec and ns.classSpec.classIcon then
        local path, l, r, t, b = ns.classSpec.classIcon(classFile)
        tex:SetTexture(path)
        tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
        tex:Show()
        return
    end
    tex:Hide()
end

local function modalBackdrop()
    local blocker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    blocker:SetFrameStrata("DIALOG")
    blocker:SetFrameLevel(900)
    blocker:SetAllPoints(UIParent)
    blocker:EnableMouse(true)
    if blocker.EnableKeyboard then blocker:EnableKeyboard(true) end
    blocker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    blocker:SetBackdropColor(0, 0, 0, 0.50)
    return blocker
end

local function showExportModal(text)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")

    local blocker = modalBackdrop()
    local modal = W:Card(blocker, "float", false)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(910)
    modal:SetSize(620, 460)
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 24)
    modal:EnableMouse(true)

    local title = W:Title(modal, "Export Attendance Snapshot")
    title:SetPoint("TOPLEFT", 18, -16)
    local close = W:Button(modal, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -14, -14)

    local hint = modal:CreateFontString(nil, "OVERLAY")
    Theme:Text(hint, "caption", "dim")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", -18, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Copy this snapshot data with Ctrl+C.")

    local target = W:Card(modal, "base", true)
    target:SetPoint("TOPLEFT", 18, -76)
    target:SetPoint("BOTTOMRIGHT", -22, 48)
    target:EnableMouse(true)

    local scroll = CreateFrame("ScrollFrame", nil, target)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -18, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetWidth(560)
    do
        local lineCount = 1
        tostring(text or ""):gsub("\n", function() lineCount = lineCount + 1 end)
        edit:SetHeight(math.max(320, lineCount * 15 + 16))
    end
    edit:SetText(text or "")
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(text or ""); self:HighlightText() end
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (edit:GetHeight() or 0) - (self:GetHeight() or 0))
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 24)))
    end)
    target:SetScript("OnMouseDown", function() edit:SetFocus(); edit:HighlightText() end)
    local bar = W:ScrollBar(scroll, edit)

    local function closeModal() blocker:Hide(); blocker:SetParent(nil) end
    close:SetScript("OnClick", closeModal)
    blocker:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then closeModal() end end)

    blocker:Show()
    modal:Show()
    bar:Update()
    edit:SetFocus()
    edit:HighlightText()
    return blocker
end

local function buildPanel(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)
    f.expanded = {}
    f.rows = {}
    f.subRows = {}
    f.groupBlocks = {}
    f.optionChecks = {}

    local title = W:Title(f, "Attendance")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Snapshot who's in the raid. Click a snapshot to inspect the saved raid groups.")

    local snapBtn = W:Button(f, "Take Snapshot", 120, 24)
    snapBtn:SetTone("blue")
    snapBtn:SetPoint("TOPRIGHT", -18, -16)
    snapBtn:SetScript("OnClick", function()
        local a = A()
        local snap = a and a:TakeSnapshot()
        if snap then
            ns:Print(("Attendance snapshot taken: %d member%s in %s."):format(
                #snap.members, #snap.members == 1 and "" or "s", snap.instance), "success")
        else
            ns:Print("Couldn't take a snapshot — are you in a group?", "warning")
        end
        f:Refresh()
    end)

    local clearBtn = W:Button(f, "Clear", 70, 24)
    clearBtn:SetPoint("RIGHT", snapBtn, "LEFT", -8, 0)
    clearBtn:SetScript("OnClick", function()
        W:Confirm("IDDQD_ATTENDANCE_CLEAR", "Clear all attendance snapshots?", function()
            local a = A(); if a then a:Clear() end
            f:Refresh()
        end)
    end)

    local settings = W:SectionHeader(f, "Automatic snapshots", "Choose when iddqd saves the current raid roster.")
    settings:SetPoint("TOPLEFT", 18, -60)
    settings:SetPoint("RIGHT", -18, 0)

    for i, opt in ipairs(AUTO_MODES) do
        local cb = W:Checkbox(f, opt.label, function()
            local a = A()
            return a and a:SnapshotMode() == opt.value
        end, function()
            local a = A()
            if a then a:SetSnapshotMode(opt.value) end
            f:RefreshOptions()
        end)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        cb:SetPoint("TOPLEFT", 18 + col * 250, -100 - row * 24)
        f.optionChecks[i] = cb
    end

    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 18, -172)
    sf:SetPoint("BOTTOMRIGHT", -28, 18)
    f.scroll, f.content = sf, content
    f.bar = W:ScrollBar(sf, content)

    function f:EnsureRow(i)
        local row = self.rows[i]
        if row then return row end
        row = W:ListRow(content, true)
        row:SetHeight(28)
        row.caret = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.caret, "body", "dim")
        row.caret:SetPoint("LEFT", 8, 0); row.caret:SetWidth(12); row.caret:SetJustifyH("CENTER")
        row.when = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.when, "caption", "ink")
        row.when:SetPoint("LEFT", 26, 0); row.when:SetWidth(150); row.when:SetJustifyH("LEFT")
        row.inst = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.inst, "caption", "dim")
        row.inst:SetPoint("LEFT", 186, 0); row.inst:SetWidth(220); row.inst:SetJustifyH("LEFT")
        row.count = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.count, "caption", "warm")
        row.count:SetPoint("LEFT", 416, 0); row.count:SetWidth(96); row.count:SetJustifyH("LEFT")
        row.removeBtn = W:Button(row, "Remove", 66, 20)
        row.removeBtn:SetPoint("RIGHT", -6, 0)
        row.exportBtn = W:Button(row, "Export", 58, 20)
        row.exportBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 0)
        row:SetScript("OnMouseUp", function(self) if self._toggle then self._toggle() end end)
        self.rows[i] = row
        return row
    end

    function f:EnsureGroupBlock(i)
        local block = self.groupBlocks[i]
        if block then return block end
        block = CreateFrame("Frame", nil, content)
        block.bg = block:CreateTexture(nil, "BACKGROUND")
        block.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        block.bg:SetAllPoints(block)
        block.bg:SetVertexColor(0.045, 0.047, 0.055, 0.82)
        block.edge = block:CreateTexture(nil, "BORDER")
        block.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        block.edge:SetHeight(1)
        block.edge:SetPoint("TOPLEFT", 0, 0)
        block.edge:SetPoint("TOPRIGHT", 0, 0)
        block.edge:SetVertexColor(1, 1, 1, 0.06)
        block.title = block:CreateFontString(nil, "OVERLAY")
        Theme:Text(block.title, "caption", "warm")
        block.title:SetPoint("TOPLEFT", 8, -6)
        block.slots = {}
        for slot = 1, 5 do
            local num = block:CreateFontString(nil, "OVERLAY")
            Theme:Text(num, "caption", "faint")
            num:SetPoint("TOPLEFT", 8, -25 - (slot - 1) * 15)
            num:SetWidth(16)
            num:SetJustifyH("RIGHT")
            num:SetText("")
            local icon = block:CreateTexture(nil, "ARTWORK")
            icon:SetSize(12, 12)
            icon:SetPoint("LEFT", num, "LEFT", 0, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:Hide()
            local name = block:CreateFontString(nil, "OVERLAY")
            Theme:Text(name, "caption", "ink")
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetPoint("RIGHT", -8, 0)
            name:SetJustifyH("LEFT")
            block.slots[slot] = { icon = icon, name = name }
        end
        self.groupBlocks[i] = block
        return block
    end

    function f:RefreshOptions()
        local a = A()
        local mode = a and a:SnapshotMode() or "disabled"
        for i, opt in ipairs(AUTO_MODES) do
            local cb = self.optionChecks[i]
            if cb and cb.SetChecked then cb:SetChecked(mode == opt.value) end
        end
    end

    function f:Refresh()
        for _, r in ipairs(self.rows) do r:Hide() end
        for _, r in ipairs(self.subRows) do r:Hide() end
        for _, r in ipairs(self.groupBlocks) do r:Hide() end
        self:RefreshOptions()
        local snaps = (A() and A():Snapshots()) or {}
        local contentW = math.max(660, (sf:GetWidth() or 0) - 8)
        content:SetWidth(contentW)

        if #snaps == 0 then
            local row = self:EnsureRow(1)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, 0); row:SetSize(contentW, 28)
            row:SetRowVisual(1, false)
            row.caret:SetText(""); row.inst:SetText(""); row.count:SetText("")
            row.when:SetText("No snapshots yet — press Take Snapshot in a raid.")
            row.when:SetWidth(contentW - 30)
            row.removeBtn:Hide(); row.exportBtn:Hide(); row._toggle = nil
            row:Show()
            content:SetHeight(math.max(sf:GetHeight() or 1, 28))
            self.bar:Update()
            return
        end

        local y, ri, si = 0, 0, 0
        for idx, snap in ipairs(snaps) do
            ri = ri + 1
            local row = self:EnsureRow(ri)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetSize(contentW, 28)
            row:SetRowVisual(ri, self.expanded[idx])
            row.when:SetWidth(150)
            row.when:SetText(fmtTime(snap.at))
            row.when:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
            row.inst:SetText(snapshotLabel(snap))
            local m = memberCount(snap)
            row.count:SetText(("%d member%s"):format(m, m == 1 and "" or "s"))
            row.caret:SetText(m > 0 and (self.expanded[idx] and "-" or "+") or "")
            row._toggle = function() self.expanded[idx] = not self.expanded[idx]; self:Refresh() end
            row.removeBtn:Show()
            row.exportBtn:Show()
            row.exportBtn:SetScript("OnClick", function()
                local a = A()
                local text = a and a:ExportSnapshot(snap)
                if text and text ~= "" then showExportModal(text) end
            end)
            row.removeBtn:SetScript("OnClick", function()
                local a = A(); if a then a:DeleteSnapshot(idx) end
                self.expanded[idx] = nil
                self:Refresh()
            end)
            row:Show()
            y = y - 28

            if self.expanded[idx] and m > 0 then
                local groups = groupsFromSnapshot(snap)
                local blockH, gapX, gapY = 96, 8, 4
                local leftPad = 24
                local blockW = math.min(210, math.floor((contentW - leftPad - gapX - 4) / 2))
                local startY = y - 6
                for groupIndex = 1, 8 do
                    si = si + 1
                    local block = self:EnsureGroupBlock(si)
                    local col = (groupIndex - 1) % 2
                    local rowIndex = math.floor((groupIndex - 1) / 2)
                    local group = groups[groupIndex] or {}
                    block:ClearAllPoints()
                    block:SetPoint("TOPLEFT", leftPad + col * (blockW + gapX), startY - rowIndex * (blockH + gapY))
                    block:SetSize(blockW, blockH)
                    block.title:SetText(("Group %d"):format(groupIndex))
                    for slot = 1, 5 do
                        local name = group[slot]
                        local classFile = classForSnapshotName(snap, name)
                        local slotFrame = block.slots[slot]
                        slotFrame.name:SetText(name and name ~= "" and name or "-")
                        if name and name ~= "" then
                            slotFrame.name:SetTextColor(classColor(classFile, Theme))
                            setClassIcon(slotFrame.icon, classFile)
                        else
                            local c = Theme.color.faint
                            slotFrame.name:SetTextColor(c[1], c[2], c[3], 0.72)
                            slotFrame.icon:Hide()
                        end
                    end
                    block:Show()
                end
                y = startY - 4 * (blockH + gapY)
            end
        end
        content:SetHeight(math.max(sf:GetHeight() or 1, -y))
        self.bar:Update()
    end

    f:Refresh()
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("attendance", buildPanel)
end

return Panel
