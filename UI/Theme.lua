local ADDON, ns = ...

local Theme = ns:NewModule("Theme")

local function rgb(hex, a)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return { r, g, b, a or 1 }
end

Theme.color = {
    void    = rgb("070708"),
    page    = rgb("0a0a0b"),
    base    = rgb("101115"),
    raised  = rgb("15161a"),
    overlay = rgb("1d1e23"),
    float   = rgb("26272c"),
    hair    = { 1, 1, 1, 0.05 },

    ink   = rgb("e9eaee"),
    dim   = rgb("9aa0ad"),
    faint = rgb("646a76"),
    warm  = rgb("bdb4a2"),

    gold    = rgb("caa65a"),
    success = rgb("5fbf8a"),
    danger  = rgb("d4756b"),
}

Theme.font = "Fonts\\FRIZQT__.TTF"
Theme.size = { display = 30, title = 22, section = 16, body = 13, caption = 11, eyebrow = 10, mono = 12 }
Theme.radius = { sm = 5, md = 9, lg = 13 }
Theme.space  = { [1] = 4, [2] = 8, [3] = 12, [4] = 16, [6] = 24, [8] = 32 }

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function setVGradient(tex, top, bottom)
    local ta = top[4] or 1
    local ba = bottom[4] or 1
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], ba),
            CreateColor(top[1], top[2], top[3], ta))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha("VERTICAL",
            bottom[1], bottom[2], bottom[3], ba,
            top[1], top[2], top[3], ta)
    end
end

local surfaceGradient = {
    void    = { top = { 0.038, 0.038, 0.043, 1 }, bottom = { 0.022, 0.022, 0.024, 1 } },
    page    = { top = { 0.060, 0.060, 0.068, 1 }, bottom = { 0.039, 0.039, 0.043, 1 } },
    base    = { top = { 0.090, 0.094, 0.110, 1 }, bottom = { 0.063, 0.067, 0.082, 1 } },
    raised  = { top = { 0.118, 0.122, 0.145, 1 }, bottom = { 0.082, 0.086, 0.102, 1 } },
    overlay = { top = { 0.114, 0.118, 0.137, 1 }, bottom = { 0.086, 0.086, 0.098, 1 } },
    float   = { top = { 0.168, 0.172, 0.194, 1 }, bottom = { 0.125, 0.129, 0.149, 1 } },
}

function Theme:Surface(frame, tone, flat)
    local c = self.color[tone] or self.color.base
    if not frame._bg then
        frame._shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._shadow:SetTexture(WHITE)
        frame._shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -2)
        frame._shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -3)
        frame._shadow:SetVertexColor(0, 0, 0, 0.36)

        frame._bg = frame:CreateTexture(nil, "BACKGROUND")
        frame._bg:SetAllPoints(frame)
        frame._bg:SetTexture(WHITE)
    end
    -- 1px inner top-light: depth via light, not borders. Created lazily so a frame
    -- first rendered flat can later be promoted to a raised/overlay state.
    if not frame._tl then
        frame._tl = frame:CreateTexture(nil, "BORDER")
        frame._tl:SetTexture(WHITE)
        frame._tl:SetHeight(1)
        frame._tl:SetPoint("TOPLEFT", 0, 0)
        frame._tl:SetPoint("TOPRIGHT", 0, 0)
        frame._tl:SetVertexColor(1, 1, 1, 0.04)
    end
    local g = surfaceGradient[tone]
    if g then
        setVGradient(frame._bg, g.top, g.bottom)
    else
        frame._bg:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    if frame._tl then
        frame._tl:SetShown(not flat)
        frame._tl:SetVertexColor(1, 1, 1, tone == "overlay" and 0.06 or 0.04)
    end
    if frame._shadow then
        frame._shadow:SetShown(not flat and tone ~= "void")
        frame._shadow:SetVertexColor(0, 0, 0, tone == "float" and 0.55 or tone == "overlay" and 0.46 or 0.34)
    end
    return frame
end

function Theme:Text(fs, variant, tone)
    local size = self.size[variant] or self.size.body
    local c = self.color[tone] or self.color.ink
    fs:SetFont(self.font, size, "")
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    if variant == "eyebrow" then
        fs:SetSpacing(0)
    end
    return fs
end
