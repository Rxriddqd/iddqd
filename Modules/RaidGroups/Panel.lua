local ADDON, ns = ...

local Panel = ns:NewModule("RaidGroupsPanel")

local function db() return ns:GetModule("DB").db end

local function iconPath(name) return ("Interface\\AddOns\\%s\\Media\\icons\\%s.tga"):format(ADDON, name) end

local function countGroups(slots)
    slots = type(slots) == "table" and slots or {}
    local groups, members = {}, 0
    for idx = 1, 40 do
        if slots[idx] then members = members + 1; groups[math.ceil(idx / 5)] = true end
    end
    local g = 0; for _ in pairs(groups) do g = g + 1 end
    return members, g
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local RG = ns:GetModule("RaidGroups")
    local Grid = ns.raid_groups_grid
    local Edit = ns.raid_groups_edit
    local GuildRoster = ns.raid_groups_guildroster
    local Decoder = ns.raid_groups_decoder
    local f = W:Card(parent, "base", true)  -- flat: no top-light line across the panel top
    f._selected = nil

    -- Three columns: left rail (import + profile list) · center grid · right guild roster.
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(300)
    local roster = CreateFrame("Frame", nil, f)
    roster:SetPoint("TOPRIGHT", 0, 0); roster:SetPoint("BOTTOMRIGHT", 0, 0); roster:SetWidth(220)
    local center = CreateFrame("Frame", nil, f)
    center:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    center:SetPoint("BOTTOMRIGHT", roster, "BOTTOMLEFT", -12, 0)
    f._right = center
    f._roster = roster

    -- Drag state machine. _drag = { kind="grid", idx=n } or { kind="roster", member=t }.
    -- The cursor-following ghost must be a FRAME (only frames tick OnUpdate); its label is
    -- a child FontString. Parented to UIParent so it floats above the panel.
    f._drag = nil
    -- The drag ghost is a mini character card: a tinted bg + class/spec icon + class-colored
    -- name, following the cursor. A FRAME (only frames tick OnUpdate); children are its art.
    local ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(150, 22)
    Theme:Surface(ghost, "float")
    W:CardEdge(ghost, 0.08)
    local ghostIcon = ghost:CreateTexture(nil, "ARTWORK")
    ghostIcon:SetSize(15, 15)
    ghostIcon:SetPoint("LEFT", 4, 0)
    local ghostText = ghost:CreateFontString(nil, "OVERLAY")
    ghostText:SetFont(Theme.font, 13, "OUTLINE")
    ghostText:SetPoint("LEFT", ghostIcon, "RIGHT", 5, 0)
    ghost:Hide()
    -- Drives the cursor-follow AND the drag-cancel: while the ghost is shown (a drag is in
    -- progress) we poll the left button. A drop over a slot fires the slot's OnReceiveDrag/
    -- OnMouseUp first (clearing _drag, hiding the ghost). If the button comes up while the
    -- ghost is still shown, the release was outside any slot → cancel here. This replaces a
    -- UIParent OnMouseUp hook, which interfered with world (mob/NPC/ground) clicks.
    ghost:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then
            if f._cancelDrag then f._cancelDrag() end
            return
        end
        local mx, my = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        -- Center the card on the cursor so it reads as "picked up" from where you grabbed,
        -- not floating off to one side.
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / scale, my / scale)
    end)
    -- member = { name, class, spec }. Shows the spec icon if known, else the class icon.
    local function beginGhost(member)
        member = member or {}
        if ns.classSpec.hasSpec(member.class, member.spec) then
            ghostIcon:SetTexture(ns.classSpec.specIcon(member.class, member.spec))
            ghostIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            local path, l, r, t, b = ns.classSpec.classIcon(member.class)
            ghostIcon:SetTexture(path); ghostIcon:SetTexCoord(l, r, t, b)
        end
        local c = ns.classSpec.classColor(member.class)
        ghostText:SetTextColor(c[1], c[2], c[3], 1)
        ghostText:SetText(member.name or "")
        ghost:Show()
    end
    -- Show the drag-target highlight on grid slot `idx` (nil clears all). Only the Panel
    -- knows whether a drag is active, so the Grid just reports enter/leave.
    local function highlightSlot(idx)
        local g = f._grid
        if not g or not g._slots then return end
        for i, slot in pairs(g._slots) do
            if slot._hl then if i == idx then slot._hl:Show() else slot._hl:Hide() end end
        end
    end
    local function clearHighlight()
        local g = f._grid
        if g and g._slots then
            for _, slot in pairs(g._slots) do if slot._hl then slot._hl:Hide() end end
        end
    end
    local function endDrag()
        f._drag = nil
        ghost:Hide()
        clearHighlight()
    end
    -- The ghost's OnUpdate calls this when the mouse button comes up with no slot having
    -- consumed the drop (a release outside any slot) — cancel the in-flight drag cleanly.
    f._cancelDrag = function() if f._drag then endDrag() else ghost:Hide() end end

    -- LEFT: a compact single-line import box.
    local hdr = W:SectionHeader(left, "Import", "Paste a composition string.")
    hdr:SetPoint("TOPLEFT", 24, -20); hdr:SetPoint("RIGHT", -16, 0)

    local boxHost = W:TextInput(left, { placeholder = "Paste string…" })
    boxHost:SetPoint("TOPLEFT", 24, -62); boxHost:SetPoint("RIGHT", -100, 0); boxHost:SetHeight(28)
    local box = boxHost.edit
    f._box = box

    local importBtn = W:Button(left, "Import", 80, 26)
    importBtn:SetPoint("TOPRIGHT", -16, -61)
    importBtn:SetScript("OnClick", function()
        local text = box:GetText()
        if not text or text == "" then return end
        local profiles, err = Decoder.Decode((text:gsub("%s+$", "")))
        if not profiles then ns:Print(err or "Import failed.", "error"); return end
        local names = RG:SaveProfiles(profiles)
        ns:Print("Imported: " .. table.concat(names, ", "), "success")
        -- Clear + unfocus so we're not stuck writing in the box, then select the new profile.
        box:SetText(""); box:ClearFocus()
        f._selected = #RG:GetProfiles()
        f._gridSel = nil  -- profile set changed; force a grid rebuild
        f:Refresh()
    end)

    local opts = W:Checkbox(left, "Exact positions within groups",
        function() return db().settings.raidGroups.keepPosInGroup end,
        function(v) db().settings.raidGroups.keepPosInGroup = v end)
    opts:SetPoint("TOPLEFT", 24, -100)
    local optCaption = left:CreateFontString(nil, "OVERLAY")
    Theme:Text(optCaption, "caption", "faint")
    optCaption:SetText("Slower; more swaps. Off = only assign groups.")
    optCaption:SetPoint("TOPLEFT", 24, -124)

    local listHdr = W:SectionHeader(left, "Saved Profiles")
    listHdr:SetPoint("TOPLEFT", 24, -152); listHdr:SetPoint("RIGHT", -16, 0)

    -- Create row: a shared name box + "+ New" (blank profile) and "Load" (snapshot the raid).
    local nameHost = W:TextInput(left, { placeholder = "Profile name…", inset = 6 })
    nameHost:SetPoint("TOPLEFT", 24, -180); nameHost:SetWidth(146); nameHost:SetHeight(24)
    local nameBox = nameHost.edit
    local function updNamePH() nameHost.placeholder:SetShown(nameBox:GetText() == "" and not nameBox:HasFocus()) end

    local newBtn = W:Button(left, "+ New", 64, 22)
    newBtn:SetPoint("TOPLEFT", nameHost, "BOTTOMLEFT", 0, -8)
    local loadBtn = W:Button(left, "Load raid", 78, 22)
    loadBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)

    local function createAndSelect(profileOrNil)
        if not profileOrNil then return end
        nameBox:SetText(""); nameBox:ClearFocus(); updNamePH()
        f._selected = #RG:GetProfiles()
        f._gridSel = nil
        f:Refresh()
    end
    newBtn:SetScript("OnClick", function()
        createAndSelect((RG:CreateProfile(nameBox:GetText())))
    end)
    loadBtn:SetScript("OnClick", function()
        local p = RG:SnapshotCurrentRaid(nameBox:GetText())
        if not p then ns:Print("You must be in a raid to load it.", "warning"); return end
        createAndSelect(p)
    end)
    -- Enter in the name box creates a blank profile (the common case).
    nameBox:SetScript("OnEnterPressed", function(self)
        createAndSelect((RG:CreateProfile(self:GetText())))
    end)

    local listHost = CreateFrame("Frame", nil, left)
    listHost:SetPoint("TOPLEFT", 24, -246); listHost:SetPoint("BOTTOMRIGHT", -16, 16)
    f._listHost = listHost
    f._rows = {}

    -- Re-render the grid + roster after a profile mutation (force a grid rebuild so the
    -- mutated slots show, then refresh the roster dedup).
    local function afterEdit()
        f._gridSel = nil
        if f._closeSpecPicker then f._closeSpecPicker() end
        f:Refresh()
    end

    local renderRoster  -- forward declaration (defined below; referenced by Refresh + handlers)

    -- Grid drag/drop/remove handlers — translate frame events into EditProfile calls on
    -- the selected profile, then re-render. Built once; they read the live selection.
    f._gridHandlers = {
        beginDrag = function(idx)
            local sel = (RG:GetProfiles())[f._selected]
            if not (sel and sel.slots[idx]) then return end
            f._drag = { kind = "grid", idx = idx }
            beginGhost(sel.members[idx] or { name = sel.slots[idx] })
        end,
        onDrop = function(targetIdx)
            local d = f._drag
            if not d then return end
            local sel = (RG:GetProfiles())[f._selected]
            if not sel then endDrag(); return end
            if d.kind == "grid" then
                if d.idx ~= targetIdx then
                    if sel.slots[targetIdx] then Edit.swap(sel, d.idx, targetIdx)
                    else Edit.move(sel, d.idx, targetIdx) end
                end
            elseif d.kind == "roster" then
                if not sel.slots[targetIdx] then Edit.place(sel, targetIdx, d.member) end
            end
            endDrag()
            afterEdit()
        end,
        onRemove = function(idx)
            local sel = (RG:GetProfiles())[f._selected]
            if not sel then return end
            Edit.clear(sel, idx)
            afterEdit()
        end,
        onSlotEnter = function(idx)
            if f._drag then highlightSlot(idx) end
        end,
        onSlotLeave = function(idx)
            if f._drag then highlightSlot(nil) end
        end,
        onPickSpec = function(idx, anchor)
            local sel = (RG:GetProfiles())[f._selected]
            local m = sel and sel.members[idx]
            if m then f._openSpecPicker(idx, m, anchor) end
        end,
    }

    -- A reused floating spec-picker: a row of the class's spec icons anchored to the clicked
    -- icon. Clicking a spec assigns it; opening for another slot / clicking again closes it.
    local specPicker = CreateFrame("Frame", nil, f)
    specPicker:SetFrameStrata("DIALOG")
    specPicker:SetFrameLevel(f:GetFrameLevel() + 40)
    if specPicker.SetClampedToScreen then specPicker:SetClampedToScreen(true) end
    Theme:Surface(specPicker, "float")
    W:CardEdge(specPicker, 0.08)
    specPicker:Hide()
    specPicker._btns = {}
    local function closeSpecPicker()
        specPicker:Hide(); specPicker._idx = nil
    end
    f._openSpecPicker = function(idx, member, anchor)
        if specPicker:IsShown() and specPicker._idx == idx then closeSpecPicker(); return end
        specPicker._idx = idx
        for _, b in ipairs(specPicker._btns) do b:Hide() end
        local specs = ns.classSpec.specsForClass(member.class)
        local size, pad = 22, 4
        for i, spec in ipairs(specs) do
            local b = specPicker._btns[i]
            if not b then
                b = CreateFrame("Button", nil, specPicker)
                b:SetSize(size, size)
                b._icon = b:CreateTexture(nil, "ARTWORK"); b._icon:SetAllPoints(b)
                b._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                specPicker._btns[i] = b
            end
            b._icon:SetTexture(ns.classSpec.specIcon(member.class, spec))
            b:ClearAllPoints()
            b:SetPoint("LEFT", specPicker, "LEFT", pad + (i - 1) * (size + pad), 0)
            b:SetScript("OnClick", function()
                local sel = (RG:GetProfiles())[f._selected]
                if sel then Edit.setSpec(sel, idx, spec) end
                closeSpecPicker()
                afterEdit()
            end)
            b:Show()
        end
        specPicker:SetSize(pad + #specs * (size + pad), size + pad * 2)
        specPicker:ClearAllPoints()
        specPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        specPicker:Show()
    end
    f._closeSpecPicker = closeSpecPicker

    -- Roster column: header + a class-filter row + a scrollable, filterable member list.
    local rosterHdr = W:SectionHeader(roster, "Guild Roster")
    rosterHdr:SetPoint("TOPLEFT", 8, -20); rosterHdr:SetPoint("RIGHT", -8, 0)

    -- Min-level filter row: [All][60+][70] quick buttons (0 = no minimum). Default to 70 so the
    -- first visit shows only max-level (raid-eligible) members instead of the whole guild — that
    -- full-roster build is what caused the open lag. Users can switch to 60+/All at any time.
    f._minLevel = 70
    local LEVELS = { { "All", 0 }, { "60+", 60 }, { "70", 70 } }
    local levelBtns = {}
    local function applyLevelTint()
        for _, lb in ipairs(levelBtns) do
            local on = (lb._lvl == f._minLevel)
            lb.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5, 1)
            Theme:Surface(lb, on and "overlay" or "raised", true)
        end
    end
    for i, def in ipairs(LEVELS) do
        local lb = W:Button(roster, def[1], 42, 18)
        lb._lvl = def[2]
        lb:SetPoint("TOPLEFT", 8 + (i - 1) * 46, -44)
        lb:SetScript("OnClick", function()
            f._minLevel = lb._lvl
            applyLevelTint()
            renderRoster((RG:GetProfiles())[f._selected])
        end)
        levelBtns[i] = lb
    end
    applyLevelTint()

    -- Class-filter row: 9 class-icon toggles. Empty set = show all; selected = union.
    f._classFilter = {}  -- { [UPPERCLASS]=true }
    local FILTER_CLASSES = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","WARLOCK","DRUID" }
    local fsize, fgap = 20, 2
    for i, cls in ipairs(FILTER_CLASSES) do
        local b = CreateFrame("Button", nil, roster)
        b:SetSize(fsize, fsize)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * (fsize + fgap), -70)
        local tex = b:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(b)
        local path, l, r, t, bb = ns.classSpec.classIcon(cls)
        tex:SetTexture(path); tex:SetTexCoord(l, r, t, bb)
        -- Dim when not selected; full when selected. Start dim (empty filter).
        tex:SetVertexColor(0.45, 0.45, 0.45, 1)
        b._tex = tex
        b:SetScript("OnClick", function()
            if f._classFilter[cls] then f._classFilter[cls] = nil else f._classFilter[cls] = true end
            b._tex:SetVertexColor(f._classFilter[cls] and 1 or 0.45, f._classFilter[cls] and 1 or 0.45, f._classFilter[cls] and 1 or 0.45, 1)
            renderRoster((RG:GetProfiles())[f._selected])
        end)
    end

    local rosterScroll, rosterContent = W:ScrollHost(roster)
    rosterScroll:SetPoint("TOPLEFT", 8, -96); rosterScroll:SetPoint("BOTTOMRIGHT", -10, 8)
    rosterContent:SetWidth(196)
    f._rosterBar = W:ScrollBar(rosterScroll, rosterContent)
    f._rosterRows = {}

    renderRoster = function(sel)
        for _, r in ipairs(f._rosterRows) do r:Hide() end
        if not sel then if f._rosterBar then f._rosterBar:Update() end return end
        local placed = Edit.placedNames(sel)
        local filterActive = next(f._classFilter) ~= nil
        local minLevel = f._minLevel or 0
        local list = GuildRoster:List()
        local y, shown = 0, 0
        for _, mem in ipairs(list) do
            local classOk = (not filterActive) or (mem.class and f._classFilter[mem.class:upper()])
            local levelOk = (minLevel == 0) or ((mem.level or 0) >= minLevel)
            if classOk and levelOk and not placed[(mem.name or ""):lower()] then
                shown = shown + 1
                local row = f._rosterRows[shown]
                if not row then
                    row = W:ListRow(rosterContent); row:SetHeight(18)
                    row:SetPoint("TOPLEFT", 0, 0); row:SetPoint("TOPRIGHT", 0, 0)
                    row.name = W:ClassName(row, "", "Warrior"); row.name:SetPoint("LEFT", 6, 0)
                    row.lvl = row:CreateFontString(nil, "OVERLAY")
                    ns:GetModule("Theme"):Text(row.lvl, "caption", "faint"); row.lvl:SetPoint("RIGHT", -6, 0)
                    row:EnableMouse(true)
                    row:RegisterForDrag("LeftButton")
                    row:HookScript("OnEnter", function(self) self:SetRowHover(true) end)
                    row:HookScript("OnLeave", function(self) self:SetRowHover(false) end)
                    -- Double-click → place the member in the first empty slot of the selected
                    -- profile. Frames have no OnDoubleClick, so detect it by timing two clicks.
                    row:SetScript("OnMouseDown", function(self)
                        local t = GetTime()
                        if self._lastClick and (t - self._lastClick) < 0.3 then
                            self._lastClick = nil
                            local sel = (RG:GetProfiles())[f._selected]
                            local m = self._mem
                            if sel and m then
                                local idx = Edit.firstEmpty(sel)
                                if idx then
                                    Edit.place(sel, idx, m)
                                    afterEdit()
                                else
                                    ns:Print("All 40 slots are full.", "warning")
                                end
                            end
                        else
                            self._lastClick = t
                        end
                    end)
                    f._rosterRows[shown] = row
                end
                row._mem = mem
                row:SetRowVisual(shown, false)
                local c = ns.classSpec.classColor(mem.class)
                row.name:SetTextColor(c[1], c[2], c[3], 1)
                row.name:SetText(mem.name or "")
                row.lvl:SetText(mem.level and tostring(mem.level) or "")
                row:SetScript("OnDragStart", function()
                    f._drag = { kind = "roster", member = mem }
                    beginGhost(mem)
                end)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
                row:Show()
                y = y - 19
            end
        end
        rosterContent:SetHeight(math.max(1, -y))
        if f._rosterBar then f._rosterBar:Update() end
    end

    function f:Refresh()
        opts:SetChecked(db().settings.raidGroups.keepPosInGroup)
        for _, r in ipairs(f._rows) do r:Hide() end
        local profiles = RG:GetProfiles()
        if #profiles == 0 then
            if not f._empty then
                f._empty = listHost:CreateFontString(nil, "OVERLAY")
                Theme:Text(f._empty, "body", "dim")
                f._empty:SetText("Import a layout to get started.")
                f._empty:SetPoint("TOPLEFT", 0, 0)
            end
            f._empty:Show()
            if f._grid then f._grid:Hide() end
            return
        end
        if f._empty then f._empty:Hide() end
        if #profiles == 0 then f._selected = nil
        elseif not f._selected or f._selected > #profiles then f._selected = #profiles end
        local y = 0
        for i, p in ipairs(profiles) do
            local row = f._rows[i]
            if not row then
                row = W:ListRow(listHost); row:SetHeight(32)
                row.name = row:CreateFontString(nil, "OVERLAY")
                Theme:Text(row.name, "body", "ink"); row.name:SetPoint("LEFT", 10, 0)
                -- Icon-ONLY action buttons (no text label that could snap onto the glyph).
                -- Delete pinned right, Apply to its left; the name fills the rest.
                row.del = W:IconActionButton(row, iconPath("trash-2"), 28, 24, "Delete")
                row.del:SetPoint("RIGHT", -6, 0)
                row.apply = W:IconActionButton(row, iconPath("circle-play"), 28, 24, "Apply")
                row.apply:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
                -- Name truncates before the Apply button instead of running under it.
                row.name:SetPoint("RIGHT", row.apply, "LEFT", -8, 0)
                row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
                row:EnableMouse(true)
                row:HookScript("OnEnter", function(self) self:SetRowHover(true) end)
                row:HookScript("OnLeave", function(self) self:SetRowHover(false) end)
                f._rows[i] = row
            end
            local members, groups = countGroups(p.slots)
            row.name:SetText(("%s   |cff8a8f99%d · %dg|r"):format(p.name, members, groups))
            row.apply:SetScript("OnClick", function() RG:Apply(p) end)
            row.del:SetScript("OnClick", function()
                W:Confirm("IDDQD_RG_DELETE", ("Delete '%s'?"):format(p.name), function()
                    RG:DeleteProfile(i)
                    if f._selected and f._selected > 1 then f._selected = f._selected - 1 end
                    f._gridSel = nil  -- index→profile mapping shifted; force a grid rebuild
                    f:Refresh()
                end)
            end)
            row:SetScript("OnMouseDown", function() f._selected = i; f:Refresh() end)
            row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
            row:SetRowVisual(i, i == f._selected)
            row:Show()
            y = y - 38
        end

        -- Center grid for the selected profile, hosted in a scroll area so a short window can
        -- scroll to reach the lower groups (the grid is a fixed 4-row-tall content frame).
        -- Rebuild on selection change OR after an edit (f._gridSel = nil forces a fresh render).
        local sel = profiles[f._selected]
        if sel then
            if not f._gridScroll then
                f._gridScroll, f._gridContent = W:ScrollHost(f._right)
                f._gridScroll:SetPoint("TOPLEFT", 0, -12); f._gridScroll:SetPoint("BOTTOMRIGHT", -8, 8)
                f._gridBar = W:ScrollBar(f._gridScroll, f._gridContent)
                -- Keep the grid content matched to the viewport width (the grid reflows its
                -- columns from the content width), and re-sync the scrollbar, on any resize.
                f._gridScroll:SetScript("OnSizeChanged", function(self, w)
                    if w and w > 0 then f._gridContent:SetWidth(w) end
                    if f._gridBar then f._gridBar:Update() end
                end)
            end
            if f._gridSel ~= f._selected then
                if f._grid then f._grid:Hide() end
                f._grid = Grid:Build(f._gridContent, sel, f._gridHandlers)
                f._grid:SetPoint("TOPLEFT", 0, 0); f._grid:SetPoint("TOPRIGHT", 0, 0)
                f._gridContent:SetHeight(f._grid._contentHeight or 700)
                f._gridContent:SetWidth(f._gridScroll:GetWidth() or 1)
                f._gridSel = f._selected
            end
            f._grid:Show()
            f._gridScroll:Show()
            if f._gridBar then f._gridBar:Update() end
        else
            if f._grid then f._grid:Hide() end
            if f._gridScroll then f._gridScroll:Hide() end
            f._gridSel = nil
        end
        renderRoster(sel)
    end

    -- Ask the client for guild data; re-render the roster when it arrives. GUILD_ROSTER_UPDATE
    -- fires in a burst as the roster streams in (and each render re-walks + re-sorts the whole
    -- guild), so debounce into a single render once the burst settles to avoid the open lag.
    GuildRoster:Request()
    local function renderRosterSoon()
        if not f._selected then return end
        if not C_Timer or not C_Timer.After then
            renderRoster((RG:GetProfiles())[f._selected]); return
        end
        f._rosterToken = (f._rosterToken or 0) + 1
        local token = f._rosterToken
        C_Timer.After(0.3, function()
            if f._rosterToken == token and f._selected then
                renderRoster((RG:GetProfiles())[f._selected])
            end
        end)
    end
    ns:GetModule("Events"):On("GUILD_ROSTER_UPDATE", renderRosterSoon, "RaidGroupsPanel")

    return f
end
