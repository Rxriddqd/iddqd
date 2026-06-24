local ADDON, ns = ...

local W = ns:NewModule("Widgets")
local Theme = ns:GetModule("Theme")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SOFT_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local ROUND_BUTTON = ("Interface\\AddOns\\%s\\Media\\button-round-mask.tga"):format(ADDON)
local ROUND_CHECKBOX = ("Interface\\AddOns\\%s\\Media\\checkbox-round-mask.tga"):format(ADDON)

-- Compat shim: applies a vertical gradient to a texture.
-- top/bottom are {r,g,b[,a]} in 0..1.
-- WoW VERTICAL gradient: first arg = bottom (min), second = top (max).
local function setVGradient(tex, top, bottom)
    local ta = top[4] or 1
    local ba = bottom[4] or 1
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], ba),
            CreateColor(top[1],    top[2],    top[3],    ta))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha("VERTICAL",
            bottom[1], bottom[2], bottom[3], ba,
            top[1],    top[2],    top[3],    ta)
    end
end

-- Neutral button gradient pairs, tuned slightly darker than the website because the WoW
-- client renders small UI textures brighter than browser CSS on the same monitor.
local NEUTRAL_TOP    = { 0.063, 0.067, 0.078 }   -- #101114-ish
local NEUTRAL_BOTTOM = { 0.043, 0.043, 0.050 }   -- #0b0b0d-ish
local HOVER_TOP      = { 0.082, 0.086, 0.102 }
local HOVER_BOTTOM   = { 0.055, 0.055, 0.064 }
local DISABLED_TOP   = { 0.042, 0.042, 0.047 }
local DISABLED_BOTTOM= { 0.030, 0.030, 0.034 }
local BLUE_TOP       = { 0.118, 0.220, 0.310 }
local BLUE_BOTTOM    = { 0.055, 0.122, 0.188 }
local BLUE_HOVER_TOP = { 0.150, 0.275, 0.380 }
local BLUE_HOVER_BOTTOM = { 0.070, 0.155, 0.235 }
local GREEN_TOP      = { 0.118, 0.260, 0.180 }
local GREEN_BOTTOM   = { 0.050, 0.145, 0.095 }
local GREEN_HOVER_TOP = { 0.150, 0.330, 0.225 }
local GREEN_HOVER_BOTTOM = { 0.065, 0.180, 0.115 }
local CHECKED_TOP    = { 0.125, 0.104, 0.056 }
local CHECKED_BOTTOM = { 0.074, 0.060, 0.030 }
local ROW_TOP        = { 0.058, 0.061, 0.072 }
local ROW_BOTTOM     = { 0.040, 0.041, 0.048 }
local ROW_ALT_TOP    = { 0.067, 0.071, 0.083 }
local ROW_ALT_BOTTOM = { 0.047, 0.049, 0.057 }
local ROW_GROUP_TOP  = { 0.086, 0.076, 0.052 }
local ROW_GROUP_BOTTOM = { 0.047, 0.043, 0.033 }
local ROW_SELECT_TOP = { 0.106, 0.093, 0.055 }
local ROW_SELECT_BOTTOM = { 0.061, 0.052, 0.029 }

local DIM_COLOR  = { 0.604, 0.627, 0.678 }       -- --dim  (#9aa0ad)
local INK_COLOR  = { 0.914, 0.918, 0.933 }       -- --ink  (#e9eaee)

local function applySoftEdge(frame, alpha)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        edgeFile = SOFT_EDGE,
        edgeSize = 9,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropBorderColor(1, 1, 1, alpha or 0.08)
end

function W:Card(parent, tone, flat)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme:Surface(f, tone or "raised", flat)
    applySoftEdge(f, flat and 0.04 or 0.065)
    return f
end

-- A faint card edge: low alpha and used only to bound controls/cards, not separate rows.
function W:CardEdge(frame, alpha)
    local a = alpha or 0.075
    applySoftEdge(frame, a)
    return frame
end

function W:Eyebrow(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme:Text(fs, "eyebrow", "warm")
    fs:SetText((text or ""):upper())
    return fs
end

function W:Title(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Theme:Text(fs, "title", "ink")
    fs:SetText(text)
    return fs
end

function W:Button(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 96, h or 26)

    -- Rounded mask shadow. This is a real alpha-masked TGA, so the corners are genuinely
    -- transparent instead of a square texture with a border painted on top.
    local shadow = b:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(ROUND_BUTTON)
    shadow:SetPoint("TOPLEFT",  b, "TOPLEFT",  0, -1)
    shadow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, -2)
    shadow:SetVertexColor(0, 0, 0, 0.42)
    b._shadow = shadow

    local edge = b:CreateTexture(nil, "BORDER")
    edge:SetTexture(ROUND_BUTTON)
    edge:SetAllPoints(b)
    edge:SetVertexColor(1, 1, 1, 0.060)
    b._edge = edge

    -- Gradient fill (ARTWORK layer, covers the full button)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(ROUND_BUTTON)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    setVGradient(fill, NEUTRAL_TOP, NEUTRAL_BOTTOM)
    b._fill = fill

    -- 1px inner top highlight (BORDER layer)
    local hl = b:CreateTexture(nil, "BORDER")
    hl:SetTexture(WHITE)
    hl:SetHeight(1)
    hl:SetPoint("TOPLEFT",  b, "TOPLEFT",  8, -2)
    hl:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -2)
    hl:SetVertexColor(1, 1, 1, 0.040)
    b._hl = hl

    -- Label FontString — font BEFORE SetText (WoW crash guard)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Theme.font, 12, "")
    fs:SetTextColor(DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3], 1)
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(label or "")
    b.label = fs

    -- Press-offset tracking (OnMouseDown shifts content 1px down)
    local function applyOffset(offset)
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT",     b, "TOPLEFT",     1,  -1 - offset)
        fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1,  1 - offset)
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT",     b, "TOPLEFT",     0,  -offset)
        edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0,  -offset)
        fs:SetPoint("CENTER", b, "CENTER", 0, -offset)
        hl:SetPoint("TOPLEFT",  b, "TOPLEFT",  8, -2 - offset)
        hl:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -2 - offset)
    end

    b._pressed = false
    b._hovered = false

    local function applyTone(hovered)
        if b._tone == "blue" then
            setVGradient(b._fill, hovered and BLUE_HOVER_TOP or BLUE_TOP, hovered and BLUE_HOVER_BOTTOM or BLUE_BOTTOM)
            b._edge:SetVertexColor(hovered and 0.72 or 0.48, hovered and 0.88 or 0.75, 1, hovered and 0.135 or 0.120)
            b._hl:SetVertexColor(0.70, 0.90, 1, hovered and 0.095 or 0.080)
            b.label:SetTextColor(INK_COLOR[1], INK_COLOR[2], INK_COLOR[3], 1)
        elseif b._tone == "green" then
            setVGradient(b._fill, hovered and GREEN_HOVER_TOP or GREEN_TOP, hovered and GREEN_HOVER_BOTTOM or GREEN_BOTTOM)
            b._edge:SetVertexColor(hovered and 0.70 or 0.55, 1, hovered and 0.80 or 0.72, hovered and 0.135 or 0.120)
            b._hl:SetVertexColor(0.78, 1, 0.86, hovered and 0.095 or 0.080)
            b.label:SetTextColor(INK_COLOR[1], INK_COLOR[2], INK_COLOR[3], 1)
        else
            setVGradient(b._fill, hovered and HOVER_TOP or NEUTRAL_TOP, hovered and HOVER_BOTTOM or NEUTRAL_BOTTOM)
            b._edge:SetVertexColor(1, 1, 1, hovered and 0.075 or 0.060)
            b._hl:SetVertexColor(1, 1, 1, hovered and 0.055 or 0.040)
            local c = hovered and INK_COLOR or DIM_COLOR
            b.label:SetTextColor(c[1], c[2], c[3], 1)
        end
        -- A caller-set label colour (SetLabelColor) overrides the tone default. Brighten a touch
        -- on hover so the button still reads as interactive.
        if b._labelColor then
            local lc = b._labelColor
            local k = hovered and 1 or 0.82
            b.label:SetTextColor(lc[1] * k + (hovered and 0 or 0), lc[2] * k, lc[3] * k, 1)
        end
        if b._sharp then
            if b._shadow then b._shadow:Hide() end
        end
    end

    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self._hovered = true
        applyTone(true)
    end)

    b:SetScript("OnLeave", function(self)
        if not self:IsEnabled() then return end
        self._hovered = false
        applyTone(false)
        if self._pressed then
            self._pressed = false
            applyOffset(0)
        end
    end)

    b:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        self._pressed = true
        applyOffset(1)
        self._edge:SetVertexColor(1, 1, 1, 0.045)
        self._hl:SetVertexColor(1, 1, 1, 0.025)
    end)

    b:SetScript("OnMouseUp", function(self)
        if not self:IsEnabled() then return end
        if self._pressed then
            self._pressed = false
            applyOffset(0)
            applyTone(self._hovered)
        end
    end)

    b:SetScript("OnDisable", function(self)
        self._pressed = false
        self._hovered = false
        setVGradient(self._fill, DISABLED_TOP, DISABLED_BOTTOM)
        self._edge:SetVertexColor(1, 1, 1, 0.030)
        self._hl:SetVertexColor(1, 1, 1, 0.018)
        self.label:SetTextColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], 0.72)
    end)

    b:SetScript("OnEnable", function(self)
        applyTone(self._hovered)
    end)

    function b:SetText(t) self.label:SetText(t) end
    -- Override the label colour regardless of tone/hover (pass nil to clear). Used for the
    -- mini-loot response buttons so they match the Loot tab's response text colours.
    function b:SetLabelColor(r, g, b2)
        if r == nil then self._labelColor = nil else self._labelColor = { r, g, b2 } end
        applyTone(self._hovered)
    end
    function b:SetTone(tone)
        self._tone = tone
        if self:IsEnabled() then applyTone(self._hovered) end
    end
    function b:SetSharp(sharp)
        self._sharp = sharp and true or false
        if self._sharp then
            if self._shadow then self._shadow:Hide() end
            if self._edge then self._edge:SetTexture(WHITE); self._edge:SetVertexColor(1, 1, 1, 0.060) end
            if self._fill then self._fill:SetTexture(WHITE) end
            if self._hl then
                self._hl:ClearAllPoints()
                self._hl:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
                self._hl:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -1)
            end
        end
        if self:IsEnabled() then applyTone(self._hovered) end
    end

    return b
end

-- Themed text input — the single source of truth for text entry styling across the addon
-- (the Professions search-box look: dark inset background, soft edge, themed font, a
-- placeholder hint that hides on focus or when text is present, escape/enter clear focus).
--
-- opts (all optional):
--   placeholder = hint text shown when empty + unfocused
--   multiLine   = true for a multi-line box
--   numeric     = true to strip non-digits as you type
--   maxLetters  = SetMaxLetters value
--   justify     = "LEFT" (default) | "RIGHT" | "CENTER"
--   inset       = horizontal text inset in px (default 8)
--   onChange    = function(text, userInput) called on edits
--   onEnter     = function(text) called on Enter (box also clears focus)
--
-- Returns the host Frame. The host exposes: host.edit (the EditBox), host:SetText(t),
-- host:GetText(), host:SetFocus(), host:SetOnChange(fn). Size/anchor the host as usual.
function W:TextInput(parent, opts)
    opts = opts or {}
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(opts.width or 280, opts.height or 24)
    host:EnableMouse(true)

    -- Dark inset background + soft edge (matches the Professions search box exactly).
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints(host)
    bg:SetVertexColor(0.03, 0.032, 0.038, 0.78)
    host.bg = bg
    applySoftEdge(host, 0.06)

    local inset = opts.inset or 8
    local edit = CreateFrame("EditBox", nil, host)
    edit:SetPoint("TOPLEFT", inset, 0)
    edit:SetPoint("BOTTOMRIGHT", -inset, 0)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(opts.multiLine and true or false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    if opts.justify then edit:SetJustifyH(opts.justify) end
    if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then opts.onEnter(self:GetText() or "") end
        self:ClearFocus()
    end)
    host.edit = edit

    -- Placeholder hint.
    local ph = edit:CreateFontString(nil, "ARTWORK")
    Theme:Text(ph, "caption", "faint")
    ph:SetPoint("LEFT", 0, 0)
    ph:SetText(opts.placeholder or "")
    host.placeholder = ph
    local function updatePlaceholder()
        ph:SetShown((edit:GetText() or "") == "" and not edit:HasFocus())
    end

    edit:SetScript("OnTextChanged", function(self, userInput)
        if opts.numeric and not self._cleaning then
            local text = self:GetText() or ""
            local digits = text:gsub("%D", "")
            if digits ~= text then
                self._cleaning = true
                self:SetText(digits)
                self:SetCursorPosition(#digits)
                self._cleaning = false
            end
        end
        updatePlaceholder()
        if host._onChange then host._onChange(self:GetText() or "", userInput) end
    end)
    edit:SetScript("OnEditFocusGained", function() ph:Hide() end)
    edit:SetScript("OnEditFocusLost", updatePlaceholder)
    host:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Shift-click an item link into this box. We hook the global HandleModifiedItemClick
    -- (the same hook Gargul uses) — it fires on EVERY shift-click of an item link (loot, bags,
    -- chat), unlike ChatEdit_InsertLink which only fires when a chat box is active. The link
    -- goes into whichever registered box is currently focused.
    if opts.insertLinks then
        if not W._itemClickHooked and type(HandleModifiedItemClick) == "function" and IsModifiedClick then
            W._itemClickHooked = true
            W._linkTargets = W._linkTargets or {}
            hooksecurefunc("HandleModifiedItemClick", function(link)
                if not link or not IsModifiedClick("CHATLINK") then return end
                for e in pairs(W._linkTargets) do
                    if e.IsVisible and e:IsVisible() and e:HasFocus() then
                        e:Insert(link)
                        return
                    end
                end
            end)
        end
        W._linkTargets = W._linkTargets or {}
        W._linkTargets[edit] = true
        -- Click anywhere on the box grabs focus, so a following shift-click lands here.
        host:SetScript("OnMouseUp", function() edit:SetFocus() end)
    end

    host._onChange = opts.onChange
    function host:SetOnChange(fn) self._onChange = fn end
    function host:SetText(t) self.edit:SetText(t or "") end
    function host:GetText() return self.edit:GetText() or "" end
    function host:SetFocus() self.edit:SetFocus() end

    updatePlaceholder()
    return host
end

-- ---------------------------------------------------------------------------
-- Item-quality icon borders
-- ---------------------------------------------------------------------------
-- Canonical item-quality -> RGB. Poor(0) grey, Common(1) white, Uncommon(2) green,
-- Rare(3) blue, Epic(4) purple, Legendary(5) orange. Matches Blizzard's palette.
local QUALITY_RGB = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}

function W:QualityRGB(quality)
    local c = QUALITY_RGB[tonumber(quality) or -1]
    if c then return c[1], c[2], c[3] end
    return nil   -- unknown/uncached: caller decides (we hide the border)
end

-- Icon borders are DISABLED. Every attempt to draw an even, quality-coloured border around the
-- icons (overlay edge bars, a stretched rounded-mask plate, a 1px backdrop edge) ended up uneven
-- — 1px on two sides and 2px on the others — because of how textures land on the device-pixel
-- grid at non-integer positions/scales. Rather than ship a border that looks wrong everywhere,
-- IconBorder is now a no-op that returns an inert stub. Call sites are unchanged: they still call
-- :SetQuality()/:Show()/:Hide(), which simply do nothing. (Kept so re-enabling later is one spot.)
local NOOP_BORDER = {
    SetColor = function() end,
    SetQuality = function() end,
    Show = function() end,
    Hide = function() end,
}
function W:IconBorder(icon)
    return NOOP_BORDER
end

-- Kept as a compatibility hook for older callers that still route controls through this helper.
-- Dropdowns now use W:Button directly, with opts.sharp deciding whether they should render as
-- crisp rectangular form controls.
function W:ControlShape(button)
    return button
end

-- A compact icon-ONLY action button (gradient button shape, a single centered Lucide
-- glyph, no text label). `iconPath` is a TGA path; `tip` (optional) tooltip via HookScript
-- so the button's own hover-gradient OnEnter/OnLeave still run.
function W:IconActionButton(parent, iconPath, w, h, tip)
    local b = W:Button(parent, "", w or 26, h or 24)  -- empty label = no text artifact
    local ic = b:CreateTexture(nil, "OVERLAY")
    ic:SetSize((h or 24) - 10, (h or 24) - 10)
    ic:SetPoint("CENTER", 0, 0)
    if iconPath then ic:SetTexture(iconPath) end
    ic:SetVertexColor(0.82, 0.86, 0.92, 1)
    b._icon = ic
    if tip then
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip); GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

-- Square icon button for the nav rail. `icon` is a texture path; selected state
-- lifts the surface tone.
function W:IconButton(parent, icon, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size or 32, size or 32)
    Theme:Surface(b, "base")
    W:CardEdge(b, 0.055)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER")
    tex:SetSize((size or 32) - 12, (size or 32) - 12)
    if icon then tex:SetTexture(icon) end
    tex:SetVertexColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
    b.icon = tex
    b._selected = false
    function b:SetSelected(on)
        self._selected = on
        Theme:Surface(self, on and "overlay" or "base")
        self.icon:SetVertexColor((on and Theme.color.ink or Theme.color.dim)[1], (on and Theme.color.ink or Theme.color.dim)[2], (on and Theme.color.ink or Theme.color.dim)[3], 1)
    end
    b:SetScript("OnEnter", function(self)
        if not self._selected then
            Theme:Surface(self, "raised")
            self.icon:SetVertexColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self._selected then
            Theme:Surface(self, "base")
            self.icon:SetVertexColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
        end
    end)
    return b
end

function W:SectionHeader(parent, title, desc)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(desc and 34 or 18)

    local t = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(t, "eyebrow", "warm")
    t:SetText((title or ""):upper())
    t:SetPoint("TOPLEFT", 0, 0)

    if desc then
        local d = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(d, "caption", "faint")
        d:SetText(desc)
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
    end
    return f
end

-- Compact rounded row used by table/list panels. The row owns only the visual shell; callers
-- still create their own columns, text, icons, tooltip handlers, and click behavior.
function W:ListRow(parent, clickable)
    local row = CreateFrame(clickable and "Button" or "Frame", nil, parent)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints(row)
    row._rowBg = bg

    local edge = row:CreateTexture(nil, "BORDER")
    edge:SetTexture(WHITE)
    edge:SetHeight(1)
    edge:SetPoint("BOTTOMLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", 0, 0)
    edge:SetVertexColor(1, 1, 1, 0.026)
    row._rowEdge = edge

    local hover = row:CreateTexture(nil, "ARTWORK")
    hover:SetTexture(WHITE)
    hover:SetAllPoints(row)
    hover:SetVertexColor(1, 1, 1, 0.040)
    hover:Hide()
    row._rowHover = hover

    function row:SetRowVisual(index, selected, kind)
        self._rowSelected = selected and true or false
        self._rowKind = kind
        local top, bottom = ROW_TOP, ROW_BOTTOM
        local alpha = 0.34
        if kind == "group" then
            top, bottom, alpha = ROW_GROUP_TOP, ROW_GROUP_BOTTOM, 0.46
        elseif selected then
            top, bottom, alpha = ROW_SELECT_TOP, ROW_SELECT_BOTTOM, 0.58
        elseif index and index % 2 == 0 then
            top, bottom, alpha = ROW_ALT_TOP, ROW_ALT_BOTTOM, 0.34
        end
        setVGradient(self._rowBg, top, bottom)
        self._rowBg:SetAlpha(alpha)
        self._rowEdge:SetVertexColor(
            selected and Theme.color.gold[1] or 1,
            selected and Theme.color.gold[2] or 1,
            selected and Theme.color.gold[3] or 1,
            selected and 0.26 or (kind == "group" and 0.075 or 0.026)
        )
        self._rowHover:SetShown(selected and kind ~= "group")
    end

    function row:SetRowHover(on)
        self._rowHover:SetShown((on or self._rowSelected) and self._rowKind ~= "group")
    end

    row:SetRowVisual(1, false)
    return row
end

-- Checkbox is DB-agnostic: getFn() supplies initial state, setFn(bool) persists a change.
function W:Checkbox(parent, label, getFn, setFn)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetHeight(22)

    local shadow = cb:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(ROUND_CHECKBOX)
    shadow:SetSize(18, 18)
    shadow:SetPoint("LEFT", 0, -1)
    shadow:SetVertexColor(0, 0, 0, 0.46)

    local edge = cb:CreateTexture(nil, "BORDER")
    edge:SetTexture(ROUND_CHECKBOX)
    edge:SetSize(18, 18)
    edge:SetPoint("LEFT", 0, 0)
    edge:SetVertexColor(1, 1, 1, 0.055)
    cb._edge = edge

    local box = cb:CreateTexture(nil, "ARTWORK")
    box:SetTexture(ROUND_CHECKBOX)
    box:SetSize(16, 16)
    box:SetPoint("CENTER", edge, "CENTER", 0, 0)
    setVGradient(box, NEUTRAL_TOP, NEUTRAL_BOTTOM)
    cb._box = box

    local tick = cb:CreateTexture(nil, "OVERLAY")
    tick:SetTexture(ROUND_CHECKBOX)
    tick:SetSize(9, 9)
    tick:SetPoint("CENTER", edge, "CENTER", 0, 0)
    tick:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.95)

    local fs = cb:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Theme.font, 12, "")
    fs:SetTextColor(DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3], 1)
    fs:SetPoint("LEFT", edge, "RIGHT", 8, 0)
    fs:SetText(label or "")
    cb.label = fs
    -- Size the clickable hitbox to the actual content (box + gap + label), not a fixed 220px,
    -- so the checkbox doesn't overlap a control placed to its right. tonumber() guards the
    -- headless stub (which returns a non-number from GetStringWidth).
    cb:SetWidth(18 + 8 + (tonumber(fs:GetStringWidth()) or 120) + 4)

    cb._checked = getFn and getFn() and true or false
    local function render()
        local enabled = cb._available ~= false
        local labelColor = enabled and (cb._hovered and INK_COLOR or DIM_COLOR) or Theme.color.faint
        cb.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3], enabled and 1 or 0.72)
        if cb._checked then
            setVGradient(box, CHECKED_TOP, CHECKED_BOTTOM)
            edge:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], enabled and 0.58 or 0.20)
            tick:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], enabled and 0.95 or 0.32)
            tick:Show()
        else
            setVGradient(box, cb._hovered and HOVER_TOP or NEUTRAL_TOP, cb._hovered and HOVER_BOTTOM or NEUTRAL_BOTTOM)
            edge:SetVertexColor(1, 1, 1, enabled and (cb._hovered and 0.085 or 0.055) or 0.025)
            tick:Hide()
        end
        box:SetAlpha(enabled and 1 or 0.48)
    end
    render()

    function cb:SetChecked(v)
        self._checked = v and true or false
        render()
    end

    function cb:SetAvailable(v)
        self._available = v ~= false
        self:EnableMouse(self._available)
        render()
    end

    cb:SetScript("OnClick", function(self)
        if self._available == false then return end
        self._checked = not self._checked
        render()
        if setFn then setFn(self._checked) end
    end)
    cb:SetScript("OnEnter", function(self)
        if self._available == false then return end
        self._hovered = true
        self.label:SetTextColor(INK_COLOR[1], INK_COLOR[2], INK_COLOR[3], 1)
        render()
    end)
    cb:SetScript("OnLeave", function(self)
        self._hovered = false
        render()
    end)
    return cb
end

-- Nav rail row: icon + label, with hover + selected states and a gold active edge.
function W:NavRow(parent, item, iconPath)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(24)

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetTexture(WHITE)
    sel:SetAllPoints(row)
    sel:SetVertexColor(Theme.color.overlay[1], Theme.color.overlay[2], Theme.color.overlay[3], 1)
    sel:Hide()
    row._sel = sel

    local edge = row:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(WHITE)
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOMLEFT", 0, 0)
    edge:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 1)
    edge:Hide()
    row._edge = edge

    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(15, 15)
    icon:SetPoint("LEFT", 12, 0)
    if iconPath then icon:SetTexture(iconPath) end
    icon:SetVertexColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
    row._icon = icon

    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Theme.font, 12, "")
    fs:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
    fs:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", item.badge and -38 or -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(item.label or "")
    row._label = fs

    if item.badge then
        local badge = row:CreateFontString(nil, "OVERLAY")
        badge:SetFont(Theme.font, 9, "")
        badge:SetTextColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], 0.72)
        badge:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        badge:SetText(item.badge)
        row._badge = badge
    end

    local function tint(c)
        row._icon:SetVertexColor(c[1], c[2], c[3], 1)
        row._label:SetTextColor(c[1], c[2], c[3], 1)
        if row._badge then row._badge:SetTextColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], row._selected and 0.92 or 0.72) end
    end

    row._selected = false
    function row:SetSelected(on)
        self._selected = on
        if on then self._sel:Show(); self._edge:Show() else self._sel:Hide(); self._edge:Hide() end
        tint(on and Theme.color.ink or Theme.color.dim)
    end

    row:SetScript("OnEnter", function(self)
        if self._selected then return end
        self._sel:Show()
        self._sel:SetVertexColor(Theme.color.raised[1], Theme.color.raised[2], Theme.color.raised[3], 1)
        tint(Theme.color.ink)
    end)
    row:SetScript("OnLeave", function(self)
        if self._selected then
            self._sel:SetVertexColor(Theme.color.overlay[1], Theme.color.overlay[2], Theme.color.overlay[3], 1)
            return
        end
        self._sel:Hide()
        tint(Theme.color.dim)
    end)

    return row
end

-- Confirmation popup (StaticPopup wrapper). `name` is a unique dialog key.
function W:Confirm(name, text, onAccept)
    W._confirmCb = W._confirmCb or {}
    if not StaticPopupDialogs[name] then
        StaticPopupDialogs[name] = {
            text = text,
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnAccept = function() if W._confirmCb[name] then W._confirmCb[name]() end end,
        }
    end
    StaticPopupDialogs[name].text = text
    W._confirmCb[name] = onAccept
    StaticPopup_Show(name)
end

-- Class-colored name fontstring. `class` is a class name (any case).
function W:ClassName(parent, name, class)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontNormal)
    local c = ns.classSpec.classColor(class)
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetText(name or "")
    return fs
end

-- Small spec icon texture (built-in WoW ability art; full color, not tinted).
function W:SpecIcon(parent, class, spec, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size or 14, size or 14)
    tex:SetTexture(ns.classSpec.specIcon(class, spec))
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return tex
end

-- A filled-slot card: a raised (grey) surface sized by the caller. The grid puts the
-- icon + class name + ✕ onto the returned frame.
function W:SlotCard(parent, flat)
    local card = W:Card(parent, "raised", flat)
    return card
end

-- A bare red ✕ remove control: a transparent click Button with a red "x" glyph that
-- brightens on hover (no button background — just the X). `onClick` fires on click.
function W:RemoveX(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 14, size or 14)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Theme.font, (size or 14) - 2, "")
    fs:SetText("x")
    fs:SetPoint("CENTER")
    local DIM, HOT = { 0.78, 0.26, 0.26 }, { 1.0, 0.42, 0.42 }  -- red, brighter on hover
    fs:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    b:SetScript("OnEnter", function() fs:SetTextColor(HOT[1], HOT[2], HOT[3], 1) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(DIM[1], DIM[2], DIM[3], 1) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Returns a texture showing the SPEC icon if the spec is known, else the CLASS icon, else
-- the question-mark. (Centralizes the class-icon fallback for slots without a spec.)
function W:ClassOrSpecIcon(parent, class, spec, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size or 14, size or 14)
    if ns.classSpec.hasSpec(class, spec) then
        tex:SetTexture(ns.classSpec.specIcon(class, spec))
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the icon border
    else
        local path, l, r, t, b = ns.classSpec.classIcon(class)
        tex:SetTexture(path)
        tex:SetTexCoord(l, r, t, b)
    end
    return tex
end

-- A minimal vertical scrollbar bound to a ScrollFrame + its content. Call bar:Update()
-- after the content height changes (re-sizes the thumb, hides the bar when content fits).
-- The thumb drags the scroll; the ScrollFrame's own mousewheel handler still works.
function W:ScrollBar(scrollFrame, content)
    local W_BAR = 6
    local bar = CreateFrame("Frame", nil, scrollFrame:GetParent())
    bar:SetWidth(W_BAR)
    -- Sit in the gutter just OUTSIDE the scroll frame's right edge, so the bar never overlaps
    -- the content rows (callers reserve ~8-10px of gutter to the right of the scroll frame).
    bar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetAllPoints(bar)
    track:SetVertexColor(1, 1, 1, 0.025)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(W_BAR)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbTex:SetAllPoints(thumb)
    thumbTex:SetVertexColor(1, 1, 1, 0.20)
    thumb:SetScript("OnEnter", function() thumbTex:SetVertexColor(1, 1, 1, 0.34) end)
    thumb:SetScript("OnLeave", function() if not thumb._dragging then thumbTex:SetVertexColor(1, 1, 1, 0.20) end end)

    local function maxScroll()
        return math.max(0, (content:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    end
    -- Position the thumb for the current scroll offset.
    local function placeThumb()
        local barH = bar:GetHeight() or 1
        local ch = content:GetHeight() or 1
        local sh = scrollFrame:GetHeight() or 1
        local frac = (sh > 0 and ch > 0) and math.min(1, sh / ch) or 1
        local thumbH = math.max(16, barH * frac)
        thumb:SetHeight(thumbH)
        local ms = maxScroll()
        local cur = scrollFrame:GetVerticalScroll() or 0
        local p = (ms > 0) and (cur / ms) or 0
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(p * (barH - thumbH)))
    end

    local function stopDrag()
        thumb._dragging = false
        thumb._grabOffset = nil
        if not thumb:IsMouseOver() then thumbTex:SetVertexColor(1, 1, 1, 0.20) end
    end

    local function updateFromCursor()
        if not thumb._dragging then return end
        local _, my = GetCursorPosition()
        local scale = bar:GetEffectiveScale()
        local barTop = bar:GetTop() or 0
        local barH = bar:GetHeight() or 1
        local thumbH = thumb:GetHeight() or 1
        local rel = (barTop - (my / scale)) - (thumb._grabOffset or thumbH / 2)
        local p = math.max(0, math.min(1, rel / math.max(1, barH - thumbH)))
        scrollFrame:SetVerticalScroll(p * maxScroll())
        placeThumb()
    end

    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnMouseDown", function()
        local _, my = GetCursorPosition()
        local scale = bar:GetEffectiveScale()
        local thumbTop = thumb:GetTop() or 0
        local thumbH = thumb:GetHeight() or 1
        thumb._grabOffset = math.max(0, math.min(thumbH, thumbTop - (my / scale)))
        thumb._dragging = true
        thumbTex:SetVertexColor(1, 1, 1, 0.38)
        updateFromCursor()
    end)
    thumb:SetScript("OnMouseUp", stopDrag)
    thumb:SetScript("OnDragStart", function() thumb._dragging = true; updateFromCursor() end)
    thumb:SetScript("OnDragStop", stopDrag)
    thumb:SetScript("OnUpdate", function()
        if thumb._dragging and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            stopDrag()
            return
        end
        updateFromCursor()
    end)

    -- Keep the thumb in sync when the wheel scrolls (hook the existing handler).
    scrollFrame:HookScript("OnVerticalScroll", function() placeThumb() end)

    function bar:Update()
        -- Clamp the scroll offset to the (possibly shrunk) content so a collapse doesn't leave
        -- the content scrolled past its end.
        local ms = maxScroll()
        if (scrollFrame:GetVerticalScroll() or 0) > ms then scrollFrame:SetVerticalScroll(ms) end
        if ms <= 0 then bar:Hide() else bar:Show(); placeThumb() end
    end
    bar:Update()
    return bar
end

-- A reusable dropdown. opts = { width, height?, get=function()->value, set=function(value),
-- items=function()->{ {value=v, label=s}, ... } }. Click opens a floating list (DIALOG
-- strata); choosing calls set(value) + closes; clicking the button again toggles it shut.
function W:Dropdown(parent, opts)
    local h = opts.height or 22
    local maxVisible = opts.maxVisible or 0
    local btn = W:Button(parent, "", opts.width or 140, h)
    W:ControlShape(btn)
    if opts.sharp and btn.SetSharp then btn:SetSharp(true) end
    local function setAtlasOrTexture(tex, atlas, texture)
        if atlas and tex.SetAtlas then
            local ok = pcall(tex.SetAtlas, tex, atlas)
            if ok then return true end
        end
        if texture then
            tex:SetTexture(texture)
            return true
        end
        return false
    end
    if opts.icon or opts.iconAtlas then
        local icon = btn:CreateTexture(nil, "OVERLAY")
        setAtlasOrTexture(icon, opts.iconAtlas, opts.icon)
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetVertexColor(0.7, 0.74, 0.8, 1)
        btn._dropdownIcon = icon
    end
    local caret = btn:CreateTexture(nil, "OVERLAY")
    setAtlasOrTexture(caret, opts.chevronAtlas, opts.chevron or ("Interface\\AddOns\\%s\\Media\\icons\\chevron-down.tga"):format(ADDON))
    caret:SetSize(14, 14); caret:SetPoint("RIGHT", -7, 0); caret:SetVertexColor(0.78, 0.82, 0.88, 1)
    btn.label:ClearAllPoints(); btn.label:SetPoint("LEFT", (opts.icon or opts.iconAtlas) and 25 or 8, 0)
    btn.label:SetPoint("RIGHT", -25, 0)
    if opts.labelFontSize then
        btn.label:SetFont(Theme.font, tonumber(opts.labelFontSize) or 12, "")
    end

    local function currentLabel()
        local v = opts.get and opts.get()
        for _, it in ipairs(opts.items()) do if it.value == v then return it.label end end
        return ""
    end
    btn:SetText(currentLabel())

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("DIALOG")
    list:SetFrameLevel(200)
    if list.SetClampedToScreen then list:SetClampedToScreen(true) end
    Theme:Surface(list, "float")
    W:CardEdge(list, 0.09)
    list:Hide()
    list._rows = {}

    local scroll = CreateFrame("ScrollFrame", nil, list)
    scroll:SetPoint("TOPLEFT", 0, 0)
    list._scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    list._content = content

    local slider = CreateFrame("Slider", nil, list, "BackdropTemplate")
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(9)
    slider:SetPoint("TOPRIGHT", -2, -2)
    slider:SetPoint("BOTTOMRIGHT", -2, 2)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(h)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider._bg = slider:CreateTexture(nil, "BACKGROUND")
    slider._bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    slider._bg:SetAllPoints(slider)
    slider._bg:SetVertexColor(1, 1, 1, 0.035)
    slider:SetThumbTexture(ROUND_BUTTON)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 26)
        thumb:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.85)
    end
    slider:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value or 0)
    end)
    slider:Hide()

    local function closeList() list:Hide() end
    local function openList()
        local items = opts.items()
        for _, r in ipairs(list._rows) do r:Hide() end
        local w = opts.width or 140
        local visible = #items
        if maxVisible > 0 then visible = math.min(visible, maxVisible) end
        visible = math.max(1, visible)
        local needsScroll = maxVisible > 0 and #items > maxVisible
        local listHeight = math.max(h, visible * h)
        local rowWidth = w - (needsScroll and 12 or 0)
        for i, it in ipairs(items) do
            local r = list._rows[i]
            if not r then
                r = CreateFrame("Button", nil, content); r:SetHeight(h)
                r._t = r:CreateFontString(nil, "OVERLAY"); Theme:Text(r._t, "body", "ink")
                if opts.rowFontSize then r._t:SetFont(Theme.font, tonumber(opts.rowFontSize) or 12, "") end
                r._t:SetPoint("LEFT", 8, 0)
                r._hl = r:CreateTexture(nil, "BACKGROUND"); r._hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                r._hl:SetAllPoints(r); r._hl:SetVertexColor(1,1,1,0.055); r._hl:Hide()
                if opts.preview then
                    r._preview = CreateFrame("Button", nil, r)
                    r._preview:SetSize(26, 24)
                    r._preview:SetPoint("RIGHT", -3, 0)
                    r._previewIcon = r._preview:CreateTexture(nil, "OVERLAY")
                    r._previewIcon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
                    r._previewIcon:SetSize(18, 18)
                    r._previewIcon:SetPoint("CENTER")
                    r._previewIcon:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.95)
                    r._preview:SetScript("OnClick", function(self)
                        if opts.preview then opts.preview(self.value) end
                    end)
                    r._t:SetPoint("RIGHT", r._preview, "LEFT", -4, 0)
                else
                    r._t:SetPoint("RIGHT", -8, 0)
                end
                r:SetScript("OnEnter", function() r._hl:Show() end)
                r:SetScript("OnLeave", function() r._hl:Hide() end)
                list._rows[i] = r
            end
            r:SetWidth(rowWidth)
            r._t:SetText(it.label)
            if r._preview then
                r._preview.value = it.value
                r._preview:Show()
            end
            r:SetScript("OnClick", function()
                if opts.set then opts.set(it.value) end
                btn:SetText(currentLabel())
                closeList()
            end)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * h); r:SetPoint("TOPRIGHT", 0, -(i - 1) * h)
            r:Show()
        end
        content:SetSize(rowWidth, math.max(listHeight, #items * h))
        scroll:SetPoint("BOTTOMRIGHT", needsScroll and -13 or 0, 0)
        scroll:SetVerticalScroll(0)
        list:SetWidth(w)
        list:SetHeight(listHeight)
        if needsScroll then
            slider:SetMinMaxValues(0, math.max(0, (#items * h) - listHeight))
            slider:SetValue(0)
            slider:Show()
        else
            slider:Hide()
        end
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local _, maxScroll = slider:GetMinMaxValues()
            local nextValue = math.max(0, math.min(maxScroll or 0, (self:GetVerticalScroll() or 0) - delta * h * 2))
            slider:SetValue(nextValue)
        end)
        if list.SetScale and UIParent and UIParent.GetEffectiveScale and btn.GetEffectiveScale then
            list:SetScale((btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
        end
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        list:Show()
    end

    btn:SetScript("OnClick", function()
        if list:IsShown() then closeList() else openList() end
    end)

    function btn:Refresh()
        btn:SetText(currentLabel())
        if opts.keepOpenOnRefresh ~= true and list:IsShown() then closeList() end
    end
    btn:HookScript("OnHide", closeList)
    return btn
end

function W:ScrollHost(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        -- Clamp BOTH ends: 0 (top) and maxScroll = content - viewport (bottom). Without the
        -- upper clamp the wheel scrolls the content right off the top of the window.
        local maxScroll = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 24)))
    end)
    return sf, content
end
