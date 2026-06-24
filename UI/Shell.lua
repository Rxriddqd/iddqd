local ADDON, ns = ...

local Shell = ns:NewModule("Shell")
local Theme = ns:GetModule("Theme")
local W = ns:GetModule("Widgets")
local Nav = ns:GetModule("Nav")

local RAIL_W = 170
local SHELL_NAME = ADDON .. "Shell"
local PANEL_PAD = 6
local PANEL_BOTTOM_PAD = 30

local function installImmediateDrag(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self, buttonName)
        if buttonName ~= "LeftButton" or self._sizing then return end
        self._moving = true
        self:StartMoving()
    end)
    local function stopMoving(self)
        if not self._moving then return end
        self._moving = false
        self:StopMovingOrSizing()
    end
    frame:SetScript("OnMouseUp", stopMoving)
    frame:HookScript("OnHide", stopMoving)
end

local function placeholder(parent, item)
    local f = CreateFrame("Frame", nil, parent)
    local eb = W:Eyebrow(f, "iddqd")
    eb:SetPoint("TOPLEFT", 24, -24)
    local title = W:Title(f, item.label)
    title:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -6)
    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    Theme:Text(sub, "body", "dim")
    sub:SetText("This panel lands in a later slice.")
    return f
end

local function flattenRootPanel(panel)
    if not panel then return end
    if panel.SetBackdrop then panel:SetBackdrop(nil) end
    if panel._bg then panel._bg:Hide() end
    if panel._shadow then panel._shadow:Hide() end
    if panel._tl then panel._tl:Hide() end
end

function Shell:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", SHELL_NAME, UIParent)
    f:SetSize(1080, 660)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    Theme:Surface(f, "page")
    if f._shadow then f._shadow:Hide() end
    W:CardEdge(f, 0.055)
    installImmediateDrag(f)
    f:SetResizable(true)
    f:Hide()

    -- Escape closes the window (the standard WoW frame-stack mechanism — needs a named frame).
    local already = false
    for _, n in ipairs(UISpecialFrames) do if n == SHELL_NAME then already = true; break end end
    if not already then tinsert(UISpecialFrames, SHELL_NAME) end

    -- No header bar — rail + content use the FULL window height. The logo + branding live at
    -- the TOP of the nav rail; a small ✕ closes from the top-right corner.
    local rail = W:Card(f, "void")
    rail:SetPoint("TOPLEFT")
    rail:SetPoint("BOTTOMLEFT")
    rail:SetWidth(RAIL_W)
    rail:SetClipsChildren(true)

    -- Large low-alpha mark in the rail. It gives the nav area the same branded feel as the
    -- website without competing with the actual controls.
    local logoMark = rail:CreateTexture(nil, "BACKGROUND", nil, 2)
    logoMark:SetTexture(("Interface\\AddOns\\%s\\Media\\logo"):format(ADDON))
    logoMark:SetSize(92, 84)
    logoMark:SetPoint("TOPLEFT", -46, 6)
    logoMark:SetAlpha(0.018)
    logoMark:SetVertexColor(0.46, 0.46, 0.50, 1)

    -- Branding at the top of the rail.
    local title = W:Title(rail, "iddqd")
    title:SetPoint("TOPLEFT", 58, -18)
    local version = rail:CreateFontString(nil, "OVERLAY")
    Theme:Text(version, "caption", "faint")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. tostring(ns.version or "1.0"))

    local content = CreateFrame("Frame", nil, f)
    Theme:Surface(content, "base", true)
    content:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT")

    -- A clean white X close, top-right corner. Raised WELL above the content card's frame
    -- level so it can't be drawn over (the content card now fills to the top of the window).
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetFrameStrata("DIALOG")
    close:SetFrameLevel(f:GetFrameLevel() + 50)
    local closeX = close:CreateFontString(nil, "OVERLAY")
    closeX:SetFont(Theme.font, 13, "OUTLINE")
    closeX:SetText("X")  -- plain uppercase X (always renders)
    closeX:SetPoint("CENTER", 0, 0)
    closeX:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
    close:SetScript("OnEnter", function() closeX:SetTextColor(Theme.color.danger[1], Theme.color.danger[2], Theme.color.danger[3], 1) end)
    close:SetScript("OnLeave", function() closeX:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1) end)
    close:SetScript("OnClick", function() self:Hide() end)

    local status = content:CreateFontString(nil, "OVERLAY")
    status:SetPoint("BOTTOMLEFT", 16, 10)
    Theme:Text(status, "caption", "faint")
    self.status = status

    self.buttons = {}
    self.panels = {}
    local y = -58  -- start below the rail branding block and watermark
    for _, section in ipairs(Nav.sections) do
        local eb = W:Eyebrow(rail, section.title)
        eb:SetPoint("TOPLEFT", 14, y)
        y = y - 18
        for _, item in ipairs(section.items) do
            local iconPath = ("Interface\\AddOns\\%s\\Media\\icons\\%s.tga"):format(ADDON, item.icon)
            local row = W:NavRow(rail, item, iconPath)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            row:SetScript("OnClick", function() self:Select(item.id) end)
            self.buttons[item.id] = row
            y = y - 24
        end
        y = y - 10
    end

    -- Resize grip. StartSizing on press; StopMovingOrSizing must be caught at the FRAME
    -- level (and on hide) — a fast resize moves the corner out from under the cursor, so the
    -- grip's own OnMouseUp can be missed, leaving the frame stuck sizing (it then "snaps huge"
    -- on the next mouse move). The frame-level OnMouseUp + OnHide guarantee the stop fires.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 45)
    grip:EnableMouse(true)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    local normal = grip:GetNormalTexture()
    if normal then
        normal:SetVertexColor(0.58, 0.62, 0.70, 0.62)
        normal:SetAllPoints(grip)
    end
    local highlight = grip:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(0.78, 0.82, 0.90, 0.78)
        highlight:SetAllPoints(grip)
    end
    local pushed = grip:GetPushedTexture()
    if pushed then
        pushed:SetVertexColor(0.40, 0.44, 0.52, 0.85)
        pushed:SetAllPoints(grip)
    end
    grip:SetScript("OnMouseDown", function() f._sizing = true; f:StartSizing("BOTTOMRIGHT") end)
    local function stopSizing() if f._sizing then f._sizing = false; f:StopMovingOrSizing() end end
    grip:SetScript("OnMouseUp", stopSizing)
    f:HookScript("OnMouseUp", stopSizing)
    f:HookScript("OnHide", stopSizing)
    -- SetResizeBounds is the current API; older clients only have SetMinResize.
    if f.SetResizeBounds then f:SetResizeBounds(820, 460) else f:SetMinResize(820, 460) end

    self.frame = f
    self.content = content
    return f
end

function Shell:Select(id)
    self:Build()
    local item
    for _, section in ipairs(Nav.sections) do
        for _, it in ipairs(section.items) do if it.id == id then item = it end end
    end
    if not item then return end

    for bid, b in pairs(self.buttons) do b:SetSelected(bid == id) end

    if self.current then self.current:Hide() end
    local panel = self.panels[id]
    if not panel then
        local builder = Nav:GetPanel(id)
        panel = builder and builder(self.content) or placeholder(self.content, item)
        flattenRootPanel(panel)
        self.panels[id] = panel
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
    panel:SetPoint("BOTTOMRIGHT", -PANEL_PAD, PANEL_BOTTOM_PAD)
    panel:Show()
    if panel.Refresh then panel:Refresh() end
    self.current = panel
    self.status:SetText("Selected: " .. item.label)

    local db = ns:GetModule("DB").db
    if db then db.lastTab = id end
end

function Shell:Show()
    self:Build()
    self.frame:Show()
    self.frame:SetAlpha(0)
    self.frame._fadeElapsed = 0
    self.frame:SetScript("OnUpdate", function(frame, elapsed)
        frame._fadeElapsed = (frame._fadeElapsed or 0) + elapsed
        local p = math.min(1, frame._fadeElapsed / 0.16)
        frame:SetAlpha(p)
        if p >= 1 then frame:SetScript("OnUpdate", nil) end
    end)
    local db = ns:GetModule("DB").db
    self:Select((db and db.lastTab) or "overview")
end

function Shell:Hide() if self.frame then self.frame:Hide() end end
function Shell:Toggle() if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end end

function Shell:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local slash = ns:GetModule("Slash")
    slash:Register("", function() self:Toggle() end)
    slash:Register("show", function() self:Show() end)
end
