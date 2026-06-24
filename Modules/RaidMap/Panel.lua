local ADDON, ns = ...

-- Raid Map panel: a strategy board. Pick a marker from the palette, click the canvas to drop it,
-- drag to reposition, right-click a pin to remove. Pins are saved per current zone.

local Panel = ns:NewModule("RaidMapPanel")

local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function RM() return ns:GetModule("RaidMap") end

local function buildPanel(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)
    f.pinFrames = {}
    f.selectedMarker = 8   -- skull by default

    local title = W:Title(f, "Raid Map")
    title:SetPoint("TOPLEFT", 18, -16)
    local sub = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(sub, "caption", "dim")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Strategy board for the current zone. Pick a marker, click to place, drag to move, right-click to remove.")

    -- Zone label + Clear
    local zoneText = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(zoneText, "caption", "warm")
    zoneText:SetPoint("TOPLEFT", 18, -58)
    f.zoneText = zoneText

    local clearBtn = W:Button(f, "Clear", 70, 22)
    clearBtn:SetPoint("TOPRIGHT", -18, -54)
    clearBtn:SetScript("OnClick", function()
        W:Confirm("IDDQD_RAIDMAP_CLEAR", "Clear all pins for this zone?", function()
            local rm = RM(); if rm then rm:ClearZone() end
            f:Refresh()
        end)
    end)

    -- Marker palette
    local palette = CreateFrame("Frame", nil, f)
    palette:SetPoint("TOPLEFT", 18, -82)
    palette:SetSize(8 * 28, 26)
    f.paletteBtns = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, palette)
        b:SetSize(24, 24)
        b:SetPoint("LEFT", (i - 1) * 28, 0)
        local tex = b:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(b); tex:SetTexture(MARKER_TEX:format(i))
        local sel = b:CreateTexture(nil, "OVERLAY"); sel:SetTexture("Interface\\Buttons\\WHITE8X8")
        sel:SetPoint("TOPLEFT", -2, 2); sel:SetPoint("BOTTOMRIGHT", 2, -2)
        sel:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.30); sel:Hide()
        b._sel = sel; b._marker = i
        b:SetScript("OnClick", function() f.selectedMarker = i; f:RefreshPalette() end)
        b:SetScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(MARKER_NAMES[i]); GameTooltip:Show() end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.paletteBtns[i] = b
    end
    -- Text-only pin option
    local textBtn = W:Button(palette, "Text Pin", 70, 22)
    textBtn:SetPoint("LEFT", 8 * 28 + 6, 0)
    textBtn:SetScript("OnClick", function() f.selectedMarker = 0; f:RefreshPalette() end)
    f.textBtn = textBtn

    -- Canvas
    local canvas = W:Card(f, "raised", true)
    canvas:SetPoint("TOPLEFT", 18, -116)
    canvas:SetPoint("BOTTOMRIGHT", -18, 16)
    canvas:EnableMouse(true)
    f.canvas = canvas

    -- Place a pin where the user clicks (left-click on empty canvas).
    canvas:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if f._draggingPin then f._draggingPin = nil; return end
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local left, bottom, width, height = self:GetLeft(), self:GetBottom(), self:GetWidth(), self:GetHeight()
        if not left or width <= 0 or height <= 0 then return end
        local x = (cx - left) / width
        local y = (cy - bottom) / height
        if x < 0 or x > 1 or y < 0 or y > 1 then return end
        local rm = RM(); if not rm then return end
        local marker = f.selectedMarker
        local text = (marker == 0) and "Note" or nil
        rm:AddPin(nil, x, 1 - y, marker, text)   -- store y top-down for intuitive coords
        f:Refresh()
    end)

    function f:RefreshPalette()
        for i, b in ipairs(self.paletteBtns) do b._sel:SetShown(self.selectedMarker == i) end
    end

    function f:EnsurePinFrame(i)
        local pf = self.pinFrames[i]
        if pf then return pf end
        pf = CreateFrame("Button", nil, canvas)
        pf:SetSize(22, 22)
        pf:EnableMouse(true)
        pf:RegisterForDrag("LeftButton")
        pf.icon = pf:CreateTexture(nil, "ARTWORK"); pf.icon:SetAllPoints(pf)
        pf.label = pf:CreateFontString(nil, "OVERLAY")
        Theme:Text(pf.label, "caption", "ink")
        pf.label:SetPoint("TOP", pf, "BOTTOM", 0, -1)
        pf:SetScript("OnDragStart", function(self) f._draggingPin = self; self:StartMoving() end)
        pf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Convert new position back to normalized coords and persist.
            local left, bottom, width, height = canvas:GetLeft(), canvas:GetBottom(), canvas:GetWidth(), canvas:GetHeight()
            local px, py = self:GetCenter()
            if left and width > 0 and height > 0 and px then
                local nx = (px - left) / width
                local ny = (py - bottom) / height
                if self._pin then self._pin.x = math.max(0, math.min(1, nx)); self._pin.y = math.max(0, math.min(1, 1 - ny)) end
            end
            f._draggingPin = nil
            f:Refresh()
        end)
        pf:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                local rm = RM(); if rm and self._pin then rm:RemovePin(nil, self._pin); f:Refresh() end
            end
        end)
        pf:SetMovable(true)
        self.pinFrames[i] = pf
        return pf
    end

    function f:Refresh()
        self.zoneText:SetText("Zone: " .. (RM() and RM():ZoneKey() or "?"))
        self:RefreshPalette()
        for _, pf in ipairs(self.pinFrames) do pf:Hide() end
        local pins = (RM() and RM():Pins()) or {}
        local width, height = canvas:GetWidth() or 1, canvas:GetHeight() or 1
        for i, pin in ipairs(pins) do
            local pf = self:EnsurePinFrame(i)
            pf._pin = pin
            if pin.marker and pin.marker >= 1 and pin.marker <= 8 then
                pf.icon:SetTexture(MARKER_TEX:format(pin.marker))
                pf.label:SetText(pin.text or "")
            else
                pf.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
                pf.icon:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.9)
                pf.label:SetText(pin.text or "Note")
            end
            pf:ClearAllPoints()
            local px = (pin.x or 0.5) * width
            local py = (1 - (pin.y or 0.5)) * height
            pf:SetPoint("CENTER", canvas, "BOTTOMLEFT", px, py)
            pf:Show()
        end
    end

    -- Re-render on zone change so the board follows the player.
    if ns:GetModule("Events") then
        ns:GetModule("Events"):On("ZONE_CHANGED_NEW_AREA", function() if f:IsShown() then f:Refresh() end end, "RaidMapPanel")
    end

    f:Refresh()
    return f
end

function Panel:OnInit()
    ns:GetModule("Nav"):RegisterPanel("raid_map", buildPanel)
end

return Panel
