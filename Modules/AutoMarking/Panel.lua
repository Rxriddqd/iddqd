local ADDON, ns = ...

local Panel = ns:NewModule("AutoMarkingPanel")

-- TBC raids, each with its background image (TGA in Media/raids). Order = display order of
-- the image-button strip.
local RAIDS = {
    { value = "kara",  label = "Karazhan",             icon = "tbc-raid-kara" },
    { value = "gruul", label = "Gruul's Lair",         icon = "tbc-raid-gruul" },
    { value = "mag",   label = "Magtheridon's Lair",   icon = "tbc-raid-magtheridon" },
    { value = "ssc",   label = "Serpentshrine Cavern", icon = "tbc-raid-ssc" },
    { value = "tk",    label = "Tempest Keep",         icon = "tbc-raid-tk" },
    { value = "hyjal", label = "Hyjal Summit",         icon = "tbc-raid-mh" },
    { value = "bt",    label = "Black Temple",         icon = "tbc-raid-bt" },
    { value = "za",    label = "Zul'Aman",             icon = "raid-za" },
    { value = "swp",   label = "Sunwell Plateau",      icon = "tbc-raid-swp" },
}
local RAID_ICON_PATH = ("Interface\\AddOns\\%s\\Media\\raids\\%%s"):format(ADDON)
local MODKEYS = { { value = "ALT", label = "Alt" }, { value = "SHIFT", label = "Shift" }, { value = "CTRL", label = "Ctrl" } }
local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local function db() return ns:GetModule("DB").db end
local function amSettings() return db().settings.autoMarking end
local function activeProfile()
    local AM = ns:GetModule("AutoMarking")
    return AM and AM:GetActiveProfile()
end

local function makeEditBox(parent, placeholderText)
    local host = ns:GetModule("Widgets"):TextInput(parent, { placeholder = placeholderText, inset = 6 })
    host.box = host.edit  -- back-compat alias for any `.box` callers
    return host, host.edit
end

-- Dimmed full-screen blocker behind a modal (mirrors the Council import modal).
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

-- Import modal: paste a profile string, live-validate it (via the profile codec), and import
-- only a valid string. onImport(text) is called with the validated string.
local function makeImportModal(onImport)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local Codec = ns:GetModule("AutoMarkingProfileCodec")

    local blocker = modalBackdrop()
    local modal = W:Card(blocker, "float", false)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(910)
    modal:SetSize(420, 202)
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 24)
    modal:EnableMouse(true)

    local title = W:Title(modal, "Import Auto-Marking Profile")
    title:SetPoint("TOPLEFT", 18, -16)
    local close = W:Button(modal, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -14, -14)

    local hint = modal:CreateFontString(nil, "OVERLAY")
    Theme:Text(hint, "caption", "dim")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", -18, 0); hint:SetJustifyH("LEFT")
    hint:SetText("Paste an !iddqd-am! profile string into the box below.")

    local target = W:Card(modal, "base", true)
    target:SetPoint("TOPLEFT", 18, -76); target:SetPoint("RIGHT", -18, 0); target:SetHeight(60)
    target:EnableMouse(true)

    local status = target:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "body", "dim")
    status:SetPoint("CENTER")
    status:SetText("Paste Import String")

    local edit = CreateFrame("EditBox", nil, target)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(0, 0, 0, 0.01)   -- invisible text (paste target only; status shows validity)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetPoint("TOPLEFT", 6, -6); edit:SetPoint("BOTTOMRIGHT", -6, 6)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    target:SetScript("OnMouseDown", function()
        edit:SetFocus()
        edit:SetCursorPosition(#(edit:GetText() or ""))
    end)

    local cancel = W:Button(modal, "Cancel", 78, 24)
    cancel:SetPoint("BOTTOMRIGHT", -18, 16)
    local import = W:Button(modal, "Import", 92, 24)
    import:SetTone("blue")
    import:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    import:Disable()

    local validText
    local function closeModal() blocker:Hide(); blocker:SetParent(nil) end
    close:SetScript("OnClick", closeModal)
    cancel:SetScript("OnClick", closeModal)
    blocker:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then closeModal() end end)

    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        validText = nil
        if text == "" then
            status:SetText("Paste Import String")
            status:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            import:Disable()
            return
        end
        local profile = Codec and Codec:DecodeString(text)
        if profile then
            validText = text
            status:SetText("Valid profile" .. (profile.name and (": " .. profile.name) or "") .. ".")
            status:SetTextColor(Theme.color.success[1], Theme.color.success[2], Theme.color.success[3], 1)
            import:Enable()
        else
            status:SetText("Invalid Import String")
            status:SetTextColor(Theme.color.danger[1], Theme.color.danger[2], Theme.color.danger[3], 1)
            import:Disable()
        end
    end)

    import:SetScript("OnClick", function()
        if not validText then return end
        onImport(validText)
        closeModal()
    end)

    blocker:Show(); modal:Show(); edit:SetFocus()
    return blocker
end

-- Export modal: a read-only box pre-filled + highlighted with the export string for copying.
local function makeExportModal(text)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")

    local blocker = modalBackdrop()
    local modal = W:Card(blocker, "float", false)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(910)
    modal:SetSize(420, 180)
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 24)
    modal:EnableMouse(true)

    local title = W:Title(modal, "Export Auto-Marking Profile")
    title:SetPoint("TOPLEFT", 18, -16)
    local close = W:Button(modal, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -14, -14)

    local hint = modal:CreateFontString(nil, "OVERLAY")
    Theme:Text(hint, "caption", "dim")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", -18, 0); hint:SetJustifyH("LEFT")
    hint:SetText("Copy this string (Ctrl+C) and share it.")

    local target = W:Card(modal, "base", true)
    target:SetPoint("TOPLEFT", 18, -78); target:SetPoint("RIGHT", -18, 0); target:SetHeight(34)
    target:EnableMouse(true)

    local edit = CreateFrame("EditBox", nil, target)
    edit:SetMultiLine(false)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetPoint("LEFT", 8, 0); edit:SetPoint("RIGHT", -8, 0); edit:SetHeight(22)
    edit:SetText(text or "")
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: re-highlight on any edit attempt instead of letting it change.
    edit:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(text or ""); self:HighlightText() end
    end)
    target:SetScript("OnMouseDown", function() edit:SetFocus(); edit:HighlightText() end)

    local function closeModal() blocker:Hide(); blocker:SetParent(nil) end
    close:SetScript("OnClick", closeModal)
    blocker:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then closeModal() end end)

    blocker:Show(); modal:Show()
    edit:SetFocus(); edit:HighlightText()
    return blocker
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local AM = ns:GetModule("AutoMarking")
    local DATA = ns.autoMarkingNPCs
    local f = W:Card(parent, "base", true)

    f._raidKey = AM.currentRaidKey or "kara"

    local profileLbl = f:CreateFontString(nil, "OVERLAY"); Theme:Text(profileLbl, "caption", "warm")
    profileLbl:SetText("PROFILE"); profileLbl:SetPoint("TOPLEFT", 24, -18)
    local profileDD = W:Dropdown(f, { width = 170, get = function() return amSettings().activeProfileId end,
        set = function(v) AM:SetActiveProfile(v); f:Rebuild() end, items = function() return AM:ProfileItems() end })
    profileDD:SetPoint("TOPLEFT", 24, -34)

    local nameHost, nameBox = makeEditBox(f, "Profile name...")
    nameHost:SetPoint("LEFT", profileDD, "RIGHT", 10, 0); nameHost:SetSize(150, 24)
    local saveName = W:Button(f, "Save", 54, 24)
    saveName:SetPoint("LEFT", nameHost, "RIGHT", 8, 0)
    saveName:SetScript("OnClick", function()
        if AM:RenameActiveProfile(nameBox:GetText()) then
            nameBox:ClearFocus()
            f:Rebuild()
        end
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        if AM:RenameActiveProfile(self:GetText()) then self:ClearFocus(); f:Rebuild() end
    end)

    local newProfile = W:Button(f, "New", 54, 24)
    newProfile:SetPoint("LEFT", saveName, "RIGHT", 8, 0)
    newProfile:SetScript("OnClick", function() AM:CreateProfile("New Profile"); f:Rebuild() end)
    local copyProfile = W:Button(f, "Copy", 58, 24)
    copyProfile:SetPoint("LEFT", newProfile, "RIGHT", 8, 0)
    copyProfile:SetScript("OnClick", function() AM:DuplicateActiveProfile(); f:Rebuild() end)
    local deleteProfile = W:Button(f, "Delete", 66, 24)
    deleteProfile:SetPoint("LEFT", copyProfile, "RIGHT", 8, 0)
    deleteProfile:SetScript("OnClick", function()
        local profile = AM:GetActiveProfile()
        if not profile then return end
        W:Confirm("IDDQD_AM_DELETE_PROFILE", ("Delete '%s'?"):format(profile.name), function()
            AM:DeleteActiveProfile()
            f:Rebuild()
        end)
    end)

    local enable = W:Checkbox(f, "Enable Auto Marking",
        function() return amSettings().enabled end,
        function(v) amSettings().enabled = v end)
    enable:SetPoint("TOPLEFT", 24, -70)

    local modEnable = W:Checkbox(f, "Only when modifier held",
        function() local p = activeProfile(); return p and p.modifierEnabled end,
        function(v) local p = activeProfile(); if p then p.modifierEnabled = v; p.updatedAt = time() end end)
    modEnable:SetPoint("LEFT", enable.label, "RIGHT", 22, 0)
    local modKey = W:Dropdown(f, { width = 70, get = function() local p = activeProfile(); return p and p.modifierKey end,
        set = function(v) local p = activeProfile(); if p then p.modifierKey = v; p.updatedAt = time() end end, items = function() return MODKEYS end })
    modKey:SetPoint("LEFT", modEnable.label, "RIGHT", 8, 0)

    local lock = W:Checkbox(f, "Lock marks after use",
        function() local p = activeProfile(); return p and p.lockAfterUse end,
        function(v) local p = activeProfile(); if p then p.lockAfterUse = v; p.updatedAt = time() end end)
    lock:SetPoint("LEFT", modKey, "RIGHT", 16, 0)

    -- Raid selector: a row of image buttons (one per TBC raid). The selected raid is shown in
    -- full colour with a brighter border; the rest are greyed out (desaturated + dimmed).
    local raidLbl = f:CreateFontString(nil, "OVERLAY"); Theme:Text(raidLbl, "caption", "warm")
    raidLbl:SetText("RAID"); raidLbl:SetPoint("TOPLEFT", 24, -104)

    local RB_SIZE, RB_GAP = 38, 6   -- square, compact
    f._raidButtons = {}
    for i, raid in ipairs(RAIDS) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(RB_SIZE, RB_SIZE)
        if i == 1 then
            btn:SetPoint("TOPLEFT", 24, -120)
        else
            btn:SetPoint("LEFT", f._raidButtons[i - 1], "RIGHT", RB_GAP, 0)
        end
        btn._raidValue = raid.value

        -- Thin border (a 1px inset frame of solid colour behind the image).
        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetTexture("Interface\\Buttons\\WHITE8X8")
        border:SetAllPoints(btn)
        btn._border = border

        local img = btn:CreateTexture(nil, "ARTWORK")
        img:SetTexture(RAID_ICON_PATH:format(raid.icon))
        img:SetPoint("TOPLEFT", 1, -1)
        img:SetPoint("BOTTOMRIGHT", -1, 1)
        btn._img = img

        -- Apply selected / greyed state.
        function btn:SetSelected(on)
            if on then
                self._border:SetVertexColor(0.85, 0.78, 0.45, 1)   -- warm highlight border
                self._img:SetDesaturated(false)
                self._img:SetVertexColor(1, 1, 1, 1)
            else
                self._border:SetVertexColor(0.25, 0.26, 0.30, 1)   -- thin neutral border
                self._img:SetDesaturated(true)
                self._img:SetVertexColor(0.55, 0.57, 0.62, 1)      -- dim/grey
            end
        end

        btn:SetScript("OnClick", function(self)
            if f._raidKey ~= self._raidValue then
                f._raidKey = self._raidValue
                f:Rebuild()
            end
        end)
        btn:SetScript("OnEnter", function(self)
            -- A subtle hover lift on un-selected buttons.
            if f._raidKey ~= self._raidValue then self._img:SetVertexColor(0.78, 0.80, 0.85, 1) end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(raid.label, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetSelected(f._raidKey == self._raidValue)
            if GameTooltip then GameTooltip:Hide() end
        end)

        f._raidButtons[i] = btn
    end

    -- Refresh the selected/greyed state of every raid button.
    function f:RefreshRaidButtons()
        for _, btn in ipairs(self._raidButtons) do
            btn:SetSelected(self._raidKey == btn._raidValue)
        end
    end

    -- Controls row, below the raid buttons.
    local clearBtn = W:Button(f, "Clear all markers", 130, 24)
    clearBtn:SetPoint("TOPLEFT", 24, -170)
    clearBtn:SetScript("OnClick", function()
        local rk = f._raidKey
        W:Confirm("IDDQD_AUTOMARK_CLEAR", ("Clear all marker assignments for this raid?"), function()
            AM:ClearRaid(rk); f:Rebuild()
        end)
    end)

    local importBtn = W:Button(f, "Import", 82, 24)
    importBtn:SetTone("blue")
    importBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    importBtn:SetScript("OnClick", function()
        makeImportModal(function(text)
            local profile, err = AM:ImportProfileString(text)
            if not profile then ns:Print(err or "Import failed.", "error"); return end
            ns:Print("Imported auto-marking profile: " .. profile.name, "success")
            f:Rebuild()
        end)
    end)

    local exportBtn = W:Button(f, "Export", 76, 24)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    exportBtn:SetScript("OnClick", function()
        local text, err = AM:ExportActiveProfileString()
        if not text then ns:Print(err or "Could not export profile.", "error"); return end
        makeExportModal(text)
    end)

    local shareBtn = W:Button(f, "Share", 70, 24)
    shareBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    shareBtn:SetScript("OnClick", function()
        local Share = ns:GetModule("AutoMarkingProfileShare")
        if not Share then return end
        Share:ShareActive()
    end)

    -- Scrollable list (moved up — the top controls now take two rows instead of four).
    -- BOTTOMRIGHT reserves room on the right for the 6px scrollbar so it doesn't overlap the
    -- rows; the content width tracks the viewport minus that bar gutter (set in OnSizeChanged).
    local BAR_GUTTER = 10
    local scroll, content = W:ScrollHost(f)
    scroll:SetPoint("TOPLEFT", 24, -204); scroll:SetPoint("BOTTOMRIGHT", -18 - BAR_GUTTER, 12)
    f._bar = W:ScrollBar(scroll, content)
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then content:SetWidth(w) end
        if f._bar then f._bar:Update() end
    end)
    content:SetWidth(tonumber(scroll:GetWidth()) or 540)
    f._content = content
    f._npcRows, f._hdrRows, f._infoRows = {}, {}, {}
    f._expanded = {}  -- [raidKey][groupId] = bool

    -- One reusable icon-strip refresher for an NPC row.
    local function refreshStrip(row)
        local list = AM:GetMarkerList(f._raidKey, row._npcID)
        local slotOf = {}
        for slot, m in ipairs(list) do slotOf[m] = slot end
        for m = 1, 8 do
            local cell = row._icons[m]
            local slot = slotOf[m]
            if slot then
                cell.tex:SetVertexColor(1, 1, 1, 1)
                cell.badge:SetText(tostring(slot)); cell.badgePlate:Show(); cell.badge:Show()
            else
                cell.tex:SetVertexColor(1, 1, 1, 0.3)
                cell.badgePlate:Hide(); cell.badge:Hide()
            end
        end
    end

    local function makeNpcRow(i)
        local row = W:ListRow(content); row:SetHeight(22)
        -- Boss skull icon (shown only for boss rows; positioned per-npc in placeNpc).
        row.bossIcon = row:CreateTexture(nil, "OVERLAY")
        row.bossIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
        row.bossIcon:SetSize(14, 14)
        row.bossIcon:Hide()
        row.name = row:CreateFontString(nil, "OVERLAY"); Theme:Text(row.name, "body", "ink")
        row.name:SetPoint("LEFT", 24, 0)
        row:HookScript("OnEnter", function(self) self:SetRowHover(true) end)
        row:HookScript("OnLeave", function(self) self:SetRowHover(false) end)
        row._icons = {}
        for m = 1, 8 do
            local cell = CreateFrame("Button", nil, row)
            cell:SetSize(18, 18)
            -- Reversed strip: Skull (marker 8) leftmost ... Star (marker 1) rightmost.
            cell:SetPoint("RIGHT", -6 - (m - 1) * 20, 0)
            cell.tex = cell:CreateTexture(nil, "ARTWORK"); cell.tex:SetAllPoints(cell)
            cell.tex:SetTexture(MARKER_TEX:format(m))
            cell.badgePlate = cell:CreateTexture(nil, "OVERLAY"); cell.badgePlate:SetTexture("Interface\\Buttons\\WHITE8X8")
            cell.badgePlate:SetSize(9, 9); cell.badgePlate:SetPoint("BOTTOMRIGHT", 1, -1); cell.badgePlate:SetVertexColor(0,0,0,0.85); cell.badgePlate:Hide()
            cell.badge = cell:CreateFontString(nil, "OVERLAY"); cell.badge:SetFont(Theme.font, 8, "OUTLINE")
            cell.badge:SetPoint("CENTER", cell.badgePlate, "CENTER", 0, 0); cell.badge:SetTextColor(1, 0.95, 0.4, 1); cell.badge:Hide()
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell._marker = m
            cell:SetScript("OnClick", function(_, mouseBtn)
                local list = AM:GetMarkerList(f._raidKey, row._npcID)
                local existing
                for slot, mk in ipairs(list) do if mk == m then existing = slot end end
                if mouseBtn == "RightButton" then
                    if existing then AM:SetMarker(f._raidKey, row._npcID, existing, nil) end
                else
                    if existing then return end
                    AM:SetMarker(f._raidKey, row._npcID, #list + 1, m)
                end
                refreshStrip(row)
                f:RefreshClear()
            end)
            row._icons[m] = cell
        end
        return row
    end

    local function makeHdrRow(i)
        local row = W:ListRow(content, true); row:SetHeight(20)
        row._chev = row:CreateFontString(nil, "OVERLAY"); Theme:Text(row._chev, "caption", "warm")
        row._chev:SetPoint("LEFT", 6, 0)
        row._t = row:CreateFontString(nil, "OVERLAY"); Theme:Text(row._t, "eyebrow", "warm")
        row._t:SetPoint("LEFT", 22, 0)
        row:HookScript("OnEnter", function(self) self:SetRowHover(true) end)
        row:HookScript("OnLeave", function(self) self:SetRowHover(false) end)
        return row
    end

    local function makeInfoRow(i)
        local row = W:ListRow(content)
        row._cols = {}
        for c = 1, 2 do
            local col = {}
            col.title = row:CreateFontString(nil, "OVERLAY")
            Theme:Text(col.title, "caption", "warm")
            col.title:SetJustifyH("LEFT")
            col.title:SetWordWrap(false)

            col.waves = {}
            col.bodies = {}
            for r = 1, 8 do
                local wave = row:CreateFontString(nil, "OVERLAY")
                Theme:Text(wave, "caption", "warm")
                wave:SetJustifyH("RIGHT")
                wave:SetJustifyV("TOP")
                wave:SetWordWrap(false)

                local body = row:CreateFontString(nil, "OVERLAY")
                Theme:Text(body, "caption", "dim")
                body:SetJustifyH("LEFT")
                body:SetJustifyV("TOP")
                body:SetWordWrap(true)

                col.waves[r] = wave
                col.bodies[r] = body
            end

            row._cols[c] = col
        end
        return row
    end

    function f:RefreshClear()
        local profile = AM:GetActiveProfile()
        local raid = profile and profile.raids and profile.raids[f._raidKey]
        if raid and next(raid) then clearBtn:Enable() else clearBtn:Disable() end
        deleteProfile:SetEnabled(#AM:GetProfiles() > 1)
    end

    -- Build the visible list for the current raid (groups -> sub-groups -> npcs).
    function f:Rebuild()
        for _, r in ipairs(f._npcRows) do r:Hide() end
        for _, r in ipairs(f._hdrRows) do r:Hide() end
        for _, r in ipairs(f._infoRows) do r:Hide() end
        local profile = AM:GetActiveProfile()
        if profile then
            if nameBox:GetText() ~= profile.name then nameBox:SetText(profile.name) end
        end
        profileDD:Refresh()
        enable:SetChecked(amSettings().enabled)
        modEnable:SetChecked(profile and profile.modifierEnabled)
        lock:SetChecked(profile and profile.lockAfterUse)
        modKey:Refresh(); f:RefreshRaidButtons()
        f:RefreshClear()

        local data = DATA and DATA[f._raidKey]
        local y, ni, hi, fi = 0, 0, 0, 0
        f._expanded[f._raidKey] = f._expanded[f._raidKey] or {}
        local exp = f._expanded[f._raidKey]

        local function placeNpc(npc, indent)
            ni = ni + 1
            local row = f._npcRows[ni] or makeNpcRow(ni); f._npcRows[ni] = row
            row._npcID = npc.id
            row:SetRowVisual(ni, false)
            row.name:SetText(npc.name)
            row.name:ClearAllPoints()
            if npc.boss then
                -- Boss: skull icon at the indent, name to its right.
                row.bossIcon:ClearAllPoints()
                row.bossIcon:SetPoint("LEFT", 12 + indent, 0)
                row.bossIcon:Show()
                row.name:SetPoint("LEFT", row.bossIcon, "RIGHT", 5, 0)
            else
                row.bossIcon:Hide()
                row.name:SetPoint("LEFT", 12 + indent, 0)
            end
            refreshStrip(row)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", -2, y)
            row:Show(); y = y - 24
        end
        -- Place a group's npcs: trash first (by order), then a small gap, then the boss +
        -- boss-fight npcs (fight=true, by order). The gap only appears when both exist.
        local function placeGroupNpcs(list, indent)
            local trash, fight = {}, {}
            for _, npc in ipairs(list or {}) do
                -- The actual boss is always on the fight side; `fight=true` adds boss-fight adds.
                if npc.boss or npc.fight then fight[#fight + 1] = npc else trash[#trash + 1] = npc end
            end
            local function byOrder(a, b) return (a.order or 0) < (b.order or 0) end
            table.sort(trash, byOrder); table.sort(fight, byOrder)
            for _, npc in ipairs(trash) do placeNpc(npc, indent) end
            if #trash > 0 and #fight > 0 then y = y - 8 end  -- detach bosses from trash
            for _, npc in ipairs(fight) do placeNpc(npc, indent) end
        end
        local function placeHdr(gid, name, indent, hasChildren)
            hi = hi + 1
            local row = f._hdrRows[hi] or makeHdrRow(hi); f._hdrRows[hi] = row
            local isOpen = exp[gid]
            if isOpen == nil then isOpen = true end  -- default-open (refine to marker-aware below)
            row._chev:SetText(hasChildren and (isOpen and "-" or "+") or " ")
            row._t:SetText((name or ""):upper())
            row._t:ClearAllPoints(); row._t:SetPoint("LEFT", 22 + indent, 0)
            row._chev:ClearAllPoints(); row._chev:SetPoint("LEFT", 6 + indent, 0)
            row:SetScript("OnClick", function()
                if hasChildren then exp[gid] = not isOpen; f:Rebuild() end
            end)
            row:SetRowVisual(hi, false, "group")
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", -2, y)
            row:Show(); y = y - 22
            return isOpen
        end

        local function placeInfo(section)
            if not section then return end
            local gid = section.id or section.title or "info"
            local open = placeHdr(gid, section.title or "Info", 0, true)
            if not open then return end

            local function setInfoCol(row, colIndex, tableData, x, colW)
                local col = row._cols[colIndex]
                if not col then return 0 end
                if not tableData then
                    col.title:Hide()
                    for i = 1, 8 do
                        col.waves[i]:Hide()
                        col.bodies[i]:Hide()
                    end
                    return 0
                end

                local rows = tableData.rows or {}
                local fallbackLines = tableData.lines or {}
                local hasWaves = #rows > 0
                local waveW = hasWaves and 30 or 0
                local bodyX = x + waveW + (hasWaves and 8 or 0)
                local bodyW = math.max(80, colW - waveW - (hasWaves and 8 or 0))

                col.title:ClearAllPoints()
                col.title:SetPoint("TOPLEFT", row, "TOPLEFT", x, -7)
                col.title:SetWidth(colW)
                col.title:SetText(tableData.title or "")
                col.title:Show()

                local titleH = col.title:GetStringHeight() or 14
                local top = math.ceil(11 + titleH + 7)
                local total = top + 8
                for i = 1, 8 do
                    local waveText, bodyText
                    if hasWaves then
                        local r = rows[i]
                        waveText = r and tostring(r[1] or "") or nil
                        bodyText = r and tostring(r[2] or "") or nil
                    else
                        bodyText = fallbackLines[i]
                    end

                    local wave = col.waves[i]
                    local body = col.bodies[i]
                    if bodyText and bodyText ~= "" then
                        wave:ClearAllPoints()
                        wave:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top)
                        wave:SetWidth(waveW)
                        wave:SetText(waveText or "")
                        if hasWaves then wave:Show() else wave:Hide() end

                        body:ClearAllPoints()
                        body:SetPoint("TOPLEFT", row, "TOPLEFT", bodyX, -top)
                        body:SetWidth(bodyW)
                        body:SetText(bodyText)
                        body:Show()

                        local lineH = math.max(13, body:GetStringHeight() or 13)
                        top = top + math.ceil(lineH) + 3
                        total = top + 6
                    else
                        wave:Hide()
                        body:Hide()
                    end
                end

                return total
            end

            local function placeInfoPair(leftTable, rightTable)
                if not leftTable and not rightTable then return end
                fi = fi + 1
                local row = f._infoRows[fi] or makeInfoRow(fi)
                f._infoRows[fi] = row
                local width = math.max(240, (tonumber(content:GetWidth()) or 540) - 28)
                local gap = 24
                local colW = rightTable and math.floor((width - gap) / 2) or width
                local leftH = setInfoCol(row, 1, leftTable, 14, colW)
                local rightH = setInfoCol(row, 2, rightTable, 14 + colW + gap, colW)
                local h = math.max(58, leftH, rightH)
                row:SetHeight(h)
                row:SetRowVisual(fi, false)
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", -2, y)
                row:Show(); y = y - h - 5
            end

            if section.tables and #section.tables > 0 then
                for i = 1, #section.tables, 2 do
                    placeInfoPair(section.tables[i], section.tables[i + 1])
                end
            else
                placeInfoPair({ title = section.title, lines = section.lines or {} }, nil)
            end
        end

        if not data then
            -- no dataset for this raid (shouldn't happen) — nothing to render.
            content:SetHeight(1); if f._bar then f._bar:Update() end; return
        end

        for _, section in ipairs(data.infoSections or {}) do
            placeInfo(section)
        end
        if data.infoSections and #data.infoSections > 0 then y = y - 4 end

        -- Group walk: top-level groups in order; their direct npcs (groupId==group.id) first,
        -- then sub-groups (children) each with their npcs. Raids with no groups: a flat list.
        local groups = data.groups or {}
        local npcsByGroup = {}
        for _, npc in ipairs(data.npcs or {}) do
            npcsByGroup[npc.groupId or "__none"] = npcsByGroup[npc.groupId or "__none"] or {}
            table.insert(npcsByGroup[npc.groupId or "__none"], npc)
        end

        if #groups == 0 then
            placeGroupNpcs(data.npcs or {}, 0)
        else
            for _, g in ipairs(groups) do
                local hasChildren = (g.children and #g.children > 0) or (npcsByGroup[g.id] and #npcsByGroup[g.id] > 0)
                local open = placeHdr(g.id, g.name, 0, hasChildren)
                if open then
                    placeGroupNpcs(npcsByGroup[g.id] or {}, 16)
                    for _, child in ipairs(g.children or {}) do
                        local copen = placeHdr(child.id, child.name, 16, (npcsByGroup[child.id] and #npcsByGroup[child.id] > 0))
                        if copen then placeGroupNpcs(npcsByGroup[child.id] or {}, 32) end
                    end
                end
            end
        end

        content:SetHeight(math.max(1, -y))
        if f._bar then f._bar:Update() end
    end

    function f:Refresh() f:Rebuild() end
    return f
end

return Panel
