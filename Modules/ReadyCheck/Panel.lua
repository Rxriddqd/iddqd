local ADDON, ns = ...

local Panel = ns:NewModule("ReadyCheckPanel")
local Theme = ns:GetModule("Theme")
local W = ns:GetModule("Widgets")

local ROW_H = 15
local ROW_STEP = 16
local HEADER_H = 18
local BUFF_ICON_SIZE = 14
local OVERLAY_BASE_H = 70
local OVERLAY_MIN_H = 90
local OVERLAY_MAX_ROWS = 25
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROUND_BUTTON = ("Interface\\AddOns\\%s\\Media\\button-round-mask.tga"):format(ADDON)

local BUFF_COLUMNS = {
    { key = "food", auraKey = "foodAura", lowKey = "foodLow", header = "FOOD", label = "Food", fallback = "Interface\\Icons\\INV_Misc_Fork&Knife", enabled = function(s) return s.checkFood ~= false end },
    { key = "flask", auraKey = "flaskAura", aurasKey = "flaskAuras", lowKey = "flaskLow", header = "FLASK", label = "Flask / Elixir", fallback = "Interface\\Icons\\INV_Potion_41", enabled = function(s) return s.checkFlask ~= false end, slots = 2 },
    { key = "stamina", auraKey = "staminaAura", header = "STA", label = "Stamina", fallback = "Interface\\Icons\\Spell_Holy_WordFortitude" },
    { key = "spirit", auraKey = "spiritAura", header = "SPI", label = "Spirit", fallback = "Interface\\Icons\\Spell_Holy_DivineSpirit" },
    { key = "shadow", auraKey = "shadowAura", header = "SH", label = "Shadow Protection", fallback = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { key = "motw", auraKey = "motwAura", header = "MOTW", label = "Mark of the Wild", fallback = "Interface\\Icons\\Spell_Nature_Regeneration" },
    { key = "blessing", auraKey = "blessingAura", aurasKey = "blessingAuras", header = "BLESS", label = "Paladin Blessing", fallback = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings", slots = 6, width = 96 },
    { key = "intellect", auraKey = "intellectAura", header = "INT", label = "Arcane Intellect", fallback = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
}

local function RC() return ns:GetModule("ReadyCheck") end

local function settings()
    local rc = RC()
    return rc and rc:Settings() or {}
end

local function overlayAlpha()
    local value = tonumber(settings().opacity) or 100
    value = math.max(30, math.min(100, value))
    return value / 100
end

local function restoreOverlayPosition(frame)
    if not frame then return end
    local pos = settings().overlayPosition
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point and pos.relativePoint then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, tonumber(pos.x) or 24, tonumber(pos.y) or -120)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -120)
    end
end

local function saveOverlayPosition(frame)
    if not frame or not frame.GetPoint then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    settings().overlayPosition = {
        point = point,
        relativePoint = relativePoint or point,
        x = math.floor((tonumber(x) or 0) + 0.5),
        y = math.floor((tonumber(y) or 0) + 0.5),
    }
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function makeOpacitySlider(parent, onCommit, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(24)

    local track = W:Card(frame, "raised", true)
    track:SetPoint("TOPLEFT", 0, -8)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(8)
    W:CardEdge(track, 0.08)
    frame.track = track

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(WHITE)
    fill:SetPoint("LEFT", 1, 0)
    fill:SetHeight(4)
    fill:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.86)
    frame.fill = fill

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(14, 14)
    thumb:SetPoint("CENTER", track, "LEFT", 1, 0)
    thumb.shadow = thumb:CreateTexture(nil, "BACKGROUND")
    thumb.shadow:SetTexture(ROUND_BUTTON)
    thumb.shadow:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, -1)
    thumb.shadow:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, -2)
    thumb.shadow:SetVertexColor(0, 0, 0, 0.45)
    thumb.edge = thumb:CreateTexture(nil, "BORDER")
    thumb.edge:SetTexture(ROUND_BUTTON)
    thumb.edge:SetAllPoints(thumb)
    thumb.edge:SetVertexColor(1, 1, 1, 0.12)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetTexture(ROUND_BUTTON)
    thumb.tex:SetPoint("TOPLEFT", thumb, "TOPLEFT", 1, -1)
    thumb.tex:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -1, 1)
    thumb.tex:SetVertexColor(0.38, 0.40, 0.44, 1)
    frame.thumb = thumb

    local minValue, maxValue = 30, 100
    local pendingValue = 100

    local function setVisual(value)
        value = clamp(value, minValue, maxValue)
        value = math.floor((value + 2.5) / 5) * 5
        value = clamp(value, minValue, maxValue)
        local changed = pendingValue ~= value
        pendingValue = value
        local pct = (value - minValue) / (maxValue - minValue)
        local width = math.max(1, track:GetWidth() or 1)
        local x = 1 + pct * math.max(1, width - 2)
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", x, 0)
        fill:SetWidth(math.max(1, x))
        if changed and onChange then onChange(value) end
    end

    local function setFromCursor()
        local scale = track:GetEffectiveScale() or 1
        local cursorX = ((GetCursorPosition and GetCursorPosition()) or 0) / scale
        local left = track:GetLeft() or cursorX
        local width = math.max(1, track:GetWidth() or 1)
        local pct = clamp((cursorX - left) / width, 0, 1)
        setVisual(minValue + pct * (maxValue - minValue))
    end

    local function commit()
        if onCommit then onCommit(pendingValue) end
    end

    local function startDrag()
        thumb.tex:SetVertexColor(0.56, 0.58, 0.63, 1)
        setFromCursor()
        frame:SetScript("OnUpdate", setFromCursor)
    end

    local function stopDrag()
        frame:SetScript("OnUpdate", nil)
        thumb.tex:SetVertexColor(0.38, 0.40, 0.44, 1)
        commit()
    end

    local function wheel(delta)
        setVisual(pendingValue + ((delta or 0) > 0 and 5 or -5))
        commit()
    end

    track:EnableMouse(true)
    track:EnableMouseWheel(true)
    track:SetScript("OnMouseDown", startDrag)
    track:SetScript("OnMouseUp", stopDrag)
    track:SetScript("OnMouseWheel", function(_, delta) wheel(delta) end)
    thumb:EnableMouse(true)
    thumb:EnableMouseWheel(true)
    thumb:SetScript("OnMouseDown", startDrag)
    thumb:SetScript("OnMouseUp", stopDrag)
    thumb:SetScript("OnMouseWheel", function(_, delta) wheel(delta) end)
    thumb:SetScript("OnEnter", function() thumb.tex:SetVertexColor(0.48, 0.50, 0.55, 1) end)
    thumb:SetScript("OnLeave", function() if not frame:GetScript("OnUpdate") then thumb.tex:SetVertexColor(0.38, 0.40, 0.44, 1) end end)
    thumb:SetScript("OnHide", stopDrag)
    frame:SetScript("OnHide", stopDrag)

    function frame:SetValue(value)
        setVisual(value)
    end

    return frame
end

local function statusColor(status)
    if status == "ready" then return 0.34, 0.92, 0.55 end
    if status == "notready" then return 0.95, 0.34, 0.30 end
    return 0.95, 0.74, 0.32
end

local function activeBuffColumns(s)
    local rc = RC()
    local cols = {}
    for _, col in ipairs(BUFF_COLUMNS) do
        local enabled = not col.enabled or col.enabled(s)
        if enabled and (not rc or not rc.ShouldTrackBuffGroup or rc:ShouldTrackBuffGroup(col.key)) then
            cols[#cols + 1] = col
        end
    end
    return cols
end

local function columnStep(col)
    return tonumber(col and col.width) or 36
end

local function columnsWidth(columns)
    local width = 0
    for _, col in ipairs(columns or {}) do width = width + columnStep(col) end
    return width
end

local function auraRemainingText(aura)
    local remaining = aura and tonumber(aura.remaining)
    if not remaining or remaining <= 0 then return nil end
    local mins = math.floor(remaining / 60)
    if mins <= 0 then return "<1 min remaining" end
    return ("%d min remaining"):format(mins)
end

local function showAuraTooltip(owner)
    if not (GameTooltip and owner) then return end
    local aura = owner._aura
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local shown
    if aura and aura.spellId and GameTooltip.SetSpellByID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, aura.spellId)
    end
    if not shown then
        if aura then
            GameTooltip:SetText(aura.name or owner._label or "Buff", 1, 1, 1)
        elseif owner._present then
            GameTooltip:SetText((owner._label or "Buff") .. " present", 0.34, 0.92, 0.55)
        end
    end
    local remain = auraRemainingText(aura)
    if remain then GameTooltip:AddLine(remain, 0.78, 0.82, 0.90) end
    GameTooltip:Show()
end

local function showReadyCheckInfoTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Ready Check")
    GameTooltip:AddLine("Starts or monitors Blizzard ready checks and shows each player's Ready, Not Ready, or waiting status.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("The monitor tracks food, flask or elixir coverage, and raid buffs such as Stamina, Spirit, Shadow Protection, Mark of the Wild, Blessings, and Arcane Intellect.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("Buff columns are smart: raid buffs only appear when the group has a class that can provide them.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("Hover buff icons to inspect the exact aura.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("Ready Check Settings controls monitor visibility, opacity, announcement behavior, and end-of-check reports.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("/iddqd check or /id check announces the selected missing buff and consumable checks without starting a ready check.", 0.78, 0.82, 0.90, true)
    GameTooltip:Show()
end

local function applyBuffIcon(button, present, aura, enabled)
    if not button then return end
    if enabled == false or present ~= true then
        button.icon:SetTexture(nil)
        button._aura = nil
        button._present = nil
        button:EnableMouse(false)
        button:Hide()
        return
    end
    button._aura = aura
    button._present = true
    local texture = aura and aura.icon or button._fallback
    if texture then
        button.icon:SetTexture(texture)
        button.icon:SetVertexColor(1, 1, 1, 1)
    else
        button.icon:SetTexture(nil)
    end
    button:EnableMouse(true)
    button:Show()
end

local function clearBuffIcons(row)
    for _, col in ipairs(BUFF_COLUMNS) do
        applyBuffIcon(row.buffIcons and row.buffIcons[col.key], false, nil, false)
        if col.slots then
            for slot = 2, col.slots do
                applyBuffIcon(row.buffIcons and row.buffIcons[col.key .. slot], false, nil, false)
            end
        end
    end
end

local function remainingText(session)
    if not session then return "No ready check active." end
    local left = math.max(0, math.ceil((session.endsAt or 0) - ((GetTime and GetTime()) or 0)))
    if session.active then return ("|cffffd35a%ds|r remaining"):format(left) end
    return "Finished"
end

local function remainingParts(session)
    if not session then return "No check", false end
    if not session.active then return "Finished", false end
    local left = math.max(0, math.ceil((session.endsAt or 0) - ((GetTime and GetTime()) or 0)))
    return ("%ds remaining"):format(left), true
end

local function applyRow(row, data, index, width, columns)
    local rc = RC()
    row:SetWidth(width)
    row:SetRowVisual(index, false)
    row.icon:SetTexture(rc and rc:IconForStatus(data.status))
    row.group:SetText("G" .. tostring(data.group or 1))
    row.name:SetText(data.name or data.key or "?")
    local cr, cg, cb = rc:ClassColor(data.class)
    row.name:SetTextColor(cr, cg, cb, 1)
    row.status:SetText(rc:StatusText(data.status))
    row.status:SetTextColor(statusColor(data.status))
    clearBuffIcons(row)
    local x = 246
    for _, col in ipairs(columns or {}) do
        local icon = row.buffIcons[col.key]
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", x, 0)
            local auras = col.aurasKey and data[col.aurasKey]
            if auras and #auras > 0 then
                for slot = 1, math.min(col.slots or 1, #auras) do
                    local slotIcon = slot == 1 and icon or row.buffIcons[col.key .. slot]
                    if slotIcon then
                        slotIcon:ClearAllPoints()
                        slotIcon:SetPoint("LEFT", x + ((slot - 1) * 15), 0)
                        applyBuffIcon(slotIcon, true, auras[slot], true)
                    end
                end
            else
                applyBuffIcon(icon, data[col.key] == true, data[col.auraKey], true)
            end
        end
        x = x + columnStep(col)
    end
end

local function makeBuffIcon(row, col, x)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
    b:SetPoint("LEFT", x, 0)
    b._label = col.label
    b._fallback = col.fallback
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetScript("OnEnter", showAuraTooltip)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and row._owner and row._owner._rightClickDismiss then
            if row._owner.Dismiss then row._owner:Dismiss() else row._owner:Hide() end
        end
    end)
    return b
end

local function ensureRow(owner, parent, rows, index)
    local row = rows[index]
    if row then return row end
    row = W:ListRow(parent)
    row._owner = owner
    row:SetHeight(ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 7, 0)
    row.group = row:CreateFontString(nil, "OVERLAY")
    Theme:Text(row.group, "caption", "warm")
    row.group:SetPoint("LEFT", 28, 0)
    row.group:SetWidth(24)
    row.group:SetJustifyH("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY")
    Theme:Text(row.name, "caption", "ink")
    row.name:SetPoint("LEFT", 48, 0)
    row.name:SetWidth(118)
    row.name:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY")
    Theme:Text(row.status, "caption", "dim")
    row.status:SetPoint("LEFT", 174, 0)
    row.status:SetWidth(62)
    row.status:SetJustifyH("LEFT")
    row.buffIcons = {}
    local x = 246
    for _, col in ipairs(BUFF_COLUMNS) do
        row.buffIcons[col.key] = makeBuffIcon(row, col, x)
        if col.slots then
            for slot = 2, col.slots do row.buffIcons[col.key .. slot] = makeBuffIcon(row, col, x + ((slot - 1) * 15)) end
        end
        x = x + columnStep(col)
    end
    rows[index] = row
    return row
end

local function refreshHeader(frame)
    if not (frame and frame.buffHeaders) then return end
    for _, header in pairs(frame.buffHeaders) do header:Hide() end
    local x = 246
    for _, col in ipairs(activeBuffColumns(settings())) do
        local header = frame.buffHeaders[col.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("LEFT", x, 0)
            header:SetWidth(columnStep(col) - 3)
            header:Show()
        end
        x = x + columnStep(col)
    end
end

local function resizeOverlayForRows(frame, count)
    if not (frame and frame._autoSizeRows) then return end
    local visibleRows = math.max(1, math.min(tonumber(count) or 0, OVERLAY_MAX_ROWS))
    frame:SetHeight(math.max(OVERLAY_MIN_H, OVERLAY_BASE_H + (visibleRows * ROW_STEP)))
end

local function buildRows(frame, rows, content, scroll)
    local rc = RC()
    local list = rc and rc:SortedRows() or {}
    local columns = activeBuffColumns(settings())
    resizeOverlayForRows(frame, #list)
    for _, row in ipairs(rows) do row:Hide() end
    local contentW = math.max(254 + columnsWidth(columns), (scroll:GetWidth() or 540) - 2)
    content:SetWidth(contentW)
    if #list == 0 then
        local row = ensureRow(frame, content, rows, 1)
        row:SetPoint("TOPLEFT", 0, 0)
        row:SetPoint("TOPRIGHT", 0, 0)
        row:SetWidth(contentW)
        row:SetRowVisual(1, false)
        row.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        row.group:SetText("")
        row.name:SetText("No ready check data")
        row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
        row.status:SetText("")
        clearBuffIcons(row)
        row:Show()
        content:SetHeight(ROW_STEP)
        return
    end
    for i, data in ipairs(list) do
        local row = ensureRow(frame, content, rows, i)
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_STEP))
        row:SetPoint("TOPRIGHT", 0, -((i - 1) * ROW_STEP))
        applyRow(row, data, i, contentW, columns)
        row:Show()
    end
    content:SetHeight(math.max(scroll:GetHeight() or 1, #list * ROW_STEP))
end

local function refreshSummary(label, timerLabel)
    local rc = RC()
    local session = rc and rc.session
    local c = rc and rc:Counts() or {}
    if timerLabel then
        local text, active = remainingParts(session)
        timerLabel:SetText(text)
        if active then
            timerLabel:SetTextColor(1.0, 0.827, 0.353, 1)
        else
            timerLabel:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
        end
        label:SetText(("Ready %d/%d  Waiting %d  Not ready %d  Missing food %d  Missing flask %d"):format(
            c.ready or 0, c.total or 0, c.waiting or 0, c.notready or 0, c.missingFood or 0, c.missingFlask or 0))
    else
        label:SetText(("%s  Ready %d/%d  Waiting %d  Not ready %d  Missing food %d  Missing flask %d"):format(
            remainingText(session), c.ready or 0, c.total or 0, c.waiting or 0, c.notready or 0, c.missingFood or 0, c.missingFlask or 0))
    end
end

local function refreshCountdownBar(frame)
    if not (frame and frame.progressTrack and frame.progressFill) then return end
    local rc = RC()
    local session = rc and rc.session
    if not (session and session.active and session.startedAt and session.endsAt) then
        frame.progressTrack:Hide()
        frame.progressFill:Hide()
        return
    end
    local duration = math.max(1, (session.endsAt or 0) - (session.startedAt or 0))
    local remaining = math.max(0, (session.endsAt or 0) - ((GetTime and GetTime()) or 0))
    local pct = math.max(0, math.min(1, remaining / duration))
    local width = math.max(1, (frame.progressTrack:GetWidth() or 1) * pct)
    frame.progressFill:SetWidth(width)
    frame.progressTrack:Show()
    frame.progressFill:Show()
end

local function buildOverlay()
    local rc = RC()
    if not rc or Panel.overlay then return Panel.overlay end
    local f = W:Card(UIParent, "float", false)
    f:SetSize(630, 520)
    f._autoSizeRows = true
    f._rightClickDismiss = true
    f:SetAlpha(overlayAlpha())
    restoreOverlayPosition(f)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    function f:Dismiss()
        local session = rc.session
        self._dismissedSession = (session and session.startedAt) or "__no_session"
        self:Hide()
    end
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then self:Dismiss() end
    end)
    f.rows = {}

    local dragHandle = CreateFrame("Button", nil, f)
    dragHandle:SetPoint("TOPLEFT", 8, -6)
    dragHandle:SetPoint("TOPRIGHT", -38, -6)
    dragHandle:SetHeight(26)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    dragHandle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartMoving() end
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        f:StopMovingOrSizing()
        if button == "LeftButton" then saveOverlayPosition(f) end
        if button == "RightButton" then f:Dismiss() end
    end)

    local close = W:Button(f, "x", 22, 20)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Dismiss() end)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(f.timer, "caption", "warm")
    f.timer:SetPoint("TOPLEFT", 10, -14)
    f.timer:SetWidth(78)
    f.timer:SetHeight(14)
    f.timer:SetJustifyH("LEFT")
    f.summary = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(f.summary, "caption", "dim")
    f.summary:SetPoint("LEFT", f.timer, "RIGHT", 4, 0)
    f.summary:SetPoint("RIGHT", -12, 0)
    f.summary:SetHeight(14)
    f.summary:SetJustifyH("LEFT")
    if f.summary.SetWordWrap then f.summary:SetWordWrap(false) end

    f.progressTrack = f:CreateTexture(nil, "BACKGROUND")
    f.progressTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressTrack:SetPoint("TOPLEFT", 8, -32)
    f.progressTrack:SetPoint("TOPRIGHT", -8, -32)
    f.progressTrack:SetHeight(4)
    f.progressTrack:SetVertexColor(1, 1, 1, 0.08)
    f.progressFill = f:CreateTexture(nil, "ARTWORK")
    f.progressFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.progressFill:SetPoint("LEFT", f.progressTrack, "LEFT", 0, 0)
    f.progressFill:SetHeight(4)
    f.progressFill:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.92)
    f.progressTrack:Hide()
    f.progressFill:Hide()

    local header = W:ListRow(f)
    header:SetPoint("TOPLEFT", 8, -40)
    header:SetPoint("TOPRIGHT", -14, -40)
    header:SetHeight(HEADER_H)
    header:SetRowVisual(1, false, "group")
    local ht = header:CreateFontString(nil, "OVERLAY")
    Theme:Text(ht, "caption", "warm")
    ht:SetPoint("LEFT", 48, 0); ht:SetText("PLAYER")
    local hs = header:CreateFontString(nil, "OVERLAY")
    Theme:Text(hs, "caption", "warm")
    hs:SetPoint("LEFT", 174, 0); hs:SetText("STATUS")
    f.header = header
    f.buffHeaders = {}
    local x = 246
    for _, col in ipairs(BUFF_COLUMNS) do
        local h = header:CreateFontString(nil, "OVERLAY")
        Theme:Text(h, "caption", "warm")
        h:SetPoint("LEFT", x, 0)
        h:SetWidth(36)
        h:SetJustifyH("LEFT")
        h:SetText(col.header)
        f.buffHeaders[col.key] = h
        x = x + columnStep(col)
    end

    local scroll, content = W:ScrollHost(f)
    scroll:SetPoint("TOPLEFT", 8, -58)
    scroll:SetPoint("BOTTOMRIGHT", -14, 8)
    f.scroll, f.content = scroll, content
    f.bar = W:ScrollBar(scroll, content)

    function f:Refresh()
        local session = rc.session
        local sessionKey = (session and session.startedAt) or "__no_session"
        if self._sessionKey ~= sessionKey then
            self._sessionKey = sessionKey
            self._dismissedSession = nil
        end
        if session and session.active and session.test and session.endsAt and session.endsAt <= ((GetTime and GetTime()) or 0) then
            rc:Finish({ silent = true })
            session = rc.session
            sessionKey = (session and session.startedAt) or "__no_session"
        end
        self:SetAlpha(overlayAlpha())
        refreshSummary(self.summary, self.timer)
        refreshCountdownBar(self)
        refreshHeader(self)
        buildRows(self, self.rows, self.content, self.scroll)
        self.bar:Update()
        if session and session.active and not self:IsShown() and self._dismissedSession ~= sessionKey then self:Show() end
    end

    f:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        refreshCountdownBar(self)
        local session = rc.session
        local second = session and math.ceil(math.max(0, (session.endsAt or 0) - ((GetTime and GetTime()) or 0))) or -1
        if self._lastSummarySecond ~= second then
            self._lastSummarySecond = second
            refreshSummary(self.summary, self.timer)
        end
    end)

    function f:HideIfFinished()
        local session = rc.session
        if not (session and session.active) then self:Hide() end
    end

    f:Hide()
    Panel.overlay = f
    rc:RegisterOverlay(f)
    return f
end

local function buildPanel(parent)
    local f = W:Card(parent, "base", true)
    f.rows = {}

    local title = W:Title(f, "Ready Check")
    title:SetPoint("TOPLEFT", 18, -16)
    local infoBtn = W:Button(f, "?", 22, 22)
    infoBtn:SetPoint("LEFT", title, "RIGHT", 8, 0)
    infoBtn:SetScript("OnEnter", showReadyCheckInfoTooltip)
    infoBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.infoBtn = infoBtn

    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Monitor Blizzard ready checks with status, food, and flask readiness.")

    local startBtn = W:Button(f, "Start Ready Check", 136, 24)
    startBtn:SetTone("blue")
    startBtn:SetPoint("TOPRIGHT", -18, -16)
    startBtn:SetScript("OnClick", function() local rc = RC(); if rc then rc:StartBlizzard() end end)

    local testBtn = W:Button(f, "Test", 62, 24)
    testBtn:SetPoint("RIGHT", startBtn, "LEFT", -8, 0)
    testBtn:SetScript("OnClick", function()
        local rc = RC()
        if rc then rc:Test(); local o = buildOverlay(); if o and o.Refresh then o:Refresh() end end
    end)

    local opts = {
        { label = "Show ready-check monitor", key = "enabled", default = true },
        { label = "Only show for raid leader / assist", key = "showOnlyLeader", default = false },
        { label = "Check food buffs", key = "checkFood", default = true },
        { label = "Check flask/elixir buffs", key = "checkFlask", default = true },
        { label = "Announce on ready check", key = "announceOnReadyCheck", default = false },
        { label = "Announce missing food", key = "announceMissingFood", default = false },
        { label = "Announce missing flask/elixirs", key = "announceMissingFlask", default = false },
        { label = "Announce missing raid buffs", key = "announceMissingRaidBuffs", default = false },
    }
    local rcForBuffs = RC()
    for _, group in ipairs((rcForBuffs and rcForBuffs.BuffGroups and rcForBuffs:BuffGroups()) or {}) do
        opts[#opts + 1] = {
            label = group.label,
            key = group.key,
            default = true,
            nested = true,
            parentKey = "announceMissingRaidBuffs",
            settingGroup = "announceRaidBuffs",
        }
    end
    opts[#opts + 1] = { label = "Announce end status", key = "announceEndStatus", default = false }
    opts[#opts + 1] = { label = "Announce when everyone is ready", key = "announceEndAllReady", default = false }

    local settingsBtn = W:Button(f, "Ready Check Settings", 154, 24)
    settingsBtn:SetPoint("RIGHT", testBtn, "LEFT", -8, 0)
    f.settingsBtn = settingsBtn

    local settingsBackdrop = CreateFrame("Button", nil, f)
    settingsBackdrop:SetAllPoints(f)
    settingsBackdrop:EnableMouse(true)
    settingsBackdrop:Hide()
    if settingsBackdrop.SetFrameLevel and f.GetFrameLevel then settingsBackdrop:SetFrameLevel((f:GetFrameLevel() or 1) + 35) end
    f.settingsBackdrop = settingsBackdrop

    local settingsPanel = W:Card(f, "float", false)
    settingsPanel:SetSize(354, 466)
    settingsPanel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -48)
    if settingsPanel.SetFrameLevel and f.GetFrameLevel then settingsPanel:SetFrameLevel((f:GetFrameLevel() or 1) + 40) end
    settingsPanel:EnableMouse(true)
    settingsPanel:Hide()
    settingsPanel:HookScript("OnHide", function() settingsBackdrop:Hide() end)
    f.settingsPanel = settingsPanel

    local settingsTitle = W:Eyebrow(settingsPanel, "Ready Check Settings")
    settingsTitle:SetPoint("TOPLEFT", 16, -14)
    local closeSettings = W:Button(settingsPanel, "x", 20, 18)
    closeSettings:SetPoint("TOPRIGHT", -10, -10)
    closeSettings:SetScript("OnClick", function() settingsPanel:Hide(); settingsBackdrop:Hide() end)
    settingsBackdrop:SetScript("OnClick", function() settingsPanel:Hide(); settingsBackdrop:Hide() end)

    local checks = {}
    local opacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY")
    Theme:Text(opacityLabel, "caption", "dim")
    opacityLabel:SetPoint("TOPLEFT", 16, -42)
    opacityLabel:SetText("Ready Check window opacity (Test)")
    local opacityValue = settingsPanel:CreateFontString(nil, "OVERLAY")
    Theme:Text(opacityValue, "caption", "warm")
    opacityValue:SetPoint("TOPRIGHT", -16, -42)
    opacityValue:SetWidth(42)
    opacityValue:SetJustifyH("RIGHT")
    local function applyOpacity(value)
        local rounded = clamp(value, 30, 100)
        settings().opacity = rounded
        opacityValue:SetText(rounded .. "%")
        local o = Panel.overlay
        if o and o.SetAlpha then o:SetAlpha(rounded / 100) end
    end
    local opacitySlider = makeOpacitySlider(settingsPanel, applyOpacity, applyOpacity)
    opacitySlider:SetPoint("TOPLEFT", 16, -64)
    opacitySlider:SetPoint("TOPRIGHT", -16, -64)
    for i, opt in ipairs(opts) do
        local cb = W:Checkbox(settingsPanel, opt.label, function()
            local s = settings()
            if opt.settingGroup then
                local group = s[opt.settingGroup]
                return type(group) ~= "table" and opt.default or (group[opt.key] == nil and opt.default or group[opt.key])
            end
            return s[opt.key] == nil and opt.default or s[opt.key]
        end, function(v)
            local s = settings()
            if opt.settingGroup then
                s[opt.settingGroup] = type(s[opt.settingGroup]) == "table" and s[opt.settingGroup] or {}
                s[opt.settingGroup][opt.key] = v and true or false
            else
                s[opt.key] = v and true or false
            end
            f:Refresh()
            if settingsPanel.Refresh then settingsPanel:Refresh() end
        end)
        cb:SetPoint("TOPLEFT", opt.nested and 36 or 16, -96 - (i - 1) * 22)
        checks[#checks + 1] = { cb = cb, opt = opt }
    end
    f.checks = checks

    function settingsPanel:Refresh()
        local s = settings()
        local opacity = math.max(30, math.min(100, tonumber(s.opacity) or 100))
        opacityValue:SetText(opacity .. "%")
        if opacitySlider.SetValue then opacitySlider:SetValue(opacity) end
        for _, item in ipairs(checks) do
            if item.cb.SetChecked then
                if item.opt.settingGroup then
                    local group = s[item.opt.settingGroup]
                    item.cb:SetChecked(type(group) ~= "table" and item.opt.default or (group[item.opt.key] == nil and item.opt.default or group[item.opt.key]))
                else
                    item.cb:SetChecked(s[item.opt.key] == nil and item.opt.default or s[item.opt.key])
                end
            end
            if item.cb.SetAvailable then
                item.cb:SetAvailable(not item.opt.parentKey or s[item.opt.parentKey] == true)
            end
        end
    end

    settingsBtn:SetScript("OnClick", function()
        if settingsPanel:IsShown() then
            settingsPanel:Hide()
            settingsBackdrop:Hide()
        else
            settingsPanel:Refresh()
            settingsBackdrop:Show()
            settingsPanel:Show()
        end
    end)
    f:HookScript("OnHide", function()
        if settingsPanel then settingsPanel:Hide() end
        if settingsBackdrop then settingsBackdrop:Hide() end
    end)

    f.summary = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(f.summary, "caption", "dim")
    f.summary:SetPoint("TOPLEFT", 18, -68)
    f.summary:SetPoint("RIGHT", -18, 0)
    f.summary:SetJustifyH("LEFT")

    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 18, -94)
    sf:SetPoint("BOTTOMRIGHT", -28, 18)
    f.scroll, f.content = sf, content
    f.bar = W:ScrollBar(sf, content)

    function f:Refresh()
        for _, item in ipairs(self.checks or {}) do
            if item.cb.SetChecked then
                local s = settings()
                item.cb:SetChecked(s[item.opt.key] == nil and item.opt.default or s[item.opt.key])
            end
        end
        refreshSummary(self.summary)
        if self.settingsPanel and self.settingsPanel.Refresh then self.settingsPanel:Refresh() end
        buildRows(self, self.rows, self.content, self.scroll)
        self.bar:Update()
    end

    local rc = RC()
    if rc then rc:RegisterPanel(f) end
    buildOverlay()
    f:Refresh()
    return f
end

function Panel:OnInit()
    local Nav = ns:GetModule("Nav")
    if Nav then Nav:RegisterPanel("ready_check", buildPanel) end
end

function Panel:OnEnable()
    buildOverlay()
end

return Panel
