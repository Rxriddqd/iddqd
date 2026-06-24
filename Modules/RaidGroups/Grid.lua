local ADDON, ns = ...

local Grid = ns:NewModule("RaidGroupsGrid")

-- Lay out 8 group blocks in the WoW raid arrangement: 4 rows of 2 groups, read
-- left-to-right then top-to-bottom (G1+G2 row, G3+G4 row, G5+G6, G7+G8). Each group
-- is a labeled vertical block of 5 slots.
function Grid:Build(parent, profile, handlers)
    handlers = handlers or {}
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)  -- flat: no top-light line above the group boxes
    f._slots = {}  -- idx -> slot frame (Panel uses these for drag highlight)

    -- Compact cells (SLOT_H) with a small gap (SLOT_STRIDE = height + gap) so each reads as a
    -- discrete card while keeping the whole grid short enough to avoid scrolling. GROUP_H fits
    -- the label + 5 strided rows.
    local SLOT_H, SLOT_GAP, PAD = 18, 2, 6
    local SLOT_STRIDE = SLOT_H + SLOT_GAP            -- 20
    local SLOT_TOP = 20                               -- first cell's y-offset below the label
    local GROUP_H = SLOT_TOP + 5 * SLOT_STRIDE + 4    -- 124

    -- Build the 8 group blocks once; positioning is deferred to relayout() so the grid
    -- reflows when the host frame finally gets a real width (WoW resolves anchored widths
    -- AFTER Build runs, so parent:GetWidth() is often 0 on first open).
    local blocks = {}
    for g = 1, 8 do
        local block = W:Card(f, "raised", true)  -- flat: avoid stacked top-lights in the grid
        block:SetHeight(GROUP_H)
        blocks[g] = block

        local label = block:CreateFontString(nil, "OVERLAY")
        Theme:Text(label, "caption", "warm")
        label:SetText("Group " .. g)
        label:SetPoint("TOPLEFT", 8, -6)

        for s = 1, 5 do
            local idx = (g - 1) * 5 + s
            local m = profile.members and profile.members[idx]
            local y = -(SLOT_TOP + (s - 1) * SLOT_STRIDE)

            -- Every slot is a mouse/drop target spanning the row (the gap lives between rows).
            local slot = CreateFrame("Frame", nil, block)
            slot:SetPoint("TOPLEFT", 6, y)
            slot:SetPoint("TOPRIGHT", -6, y)
            slot:SetHeight(SLOT_H)
            slot:EnableMouse(true)
            slot:SetScript("OnReceiveDrag", function() if handlers.onDrop then handlers.onDrop(idx) end end)
            slot:SetScript("OnMouseUp", function() if handlers.onDrop then handlers.onDrop(idx) end end)
            slot:SetScript("OnEnter", function() if handlers.onSlotEnter then handlers.onSlotEnter(idx) end end)
            slot:SetScript("OnLeave", function() if handlers.onSlotLeave then handlers.onSlotLeave(idx) end end)
            f._slots[idx] = slot

            -- A hidden highlight overlay the Panel shows on the slot under the cursor mid-drag.
            local hl = slot:CreateTexture(nil, "OVERLAY")
            hl:SetTexture("Interface\\Buttons\\WHITE8X8")
            hl:SetAllPoints(slot)
            hl:SetVertexColor(1, 1, 1, 0.14)
            hl:Hide()
            slot._hl = hl

            -- A subtle hover glow on filled slots (separate from the drag highlight so the two
            -- don't fight): brightens slightly on mouse-over.
            local hover = slot:CreateTexture(nil, "ARTWORK")
            hover:SetTexture("Interface\\Buttons\\WHITE8X8")
            hover:SetAllPoints(slot)
            hover:SetVertexColor(1, 1, 1, 0.06)
            hover:Hide()
            slot._hover = hover
            slot:HookScript("OnEnter", function() if profile.members and profile.members[idx] then hover:Show() end end)
            slot:HookScript("OnLeave", function() hover:Hide() end)

            if m then
                -- Filled slots sit on a grey card with a faint edge; the gap between rows
                -- (SLOT_GAP) keeps adjacent cards visually separate.
                local card = W:SlotCard(slot, true)
                card:SetAllPoints(slot)
                card:SetFrameLevel(slot:GetFrameLevel())  -- behind the slot's mouse layer
                W:CardEdge(card, 0.12)

                -- Class/spec icon as a Button — click to pick a spec.
                local iconBtn = CreateFrame("Button", nil, slot)
                iconBtn:SetSize(14, 14)
                iconBtn:SetPoint("LEFT", 4, 0)
                local icon = W:ClassOrSpecIcon(iconBtn, m.class, m.spec, 14)
                icon:SetAllPoints(iconBtn)
                iconBtn:SetScript("OnClick", function() if handlers.onPickSpec then handlers.onPickSpec(idx, iconBtn) end end)

                -- A bare red ✕ to remove (no button background), pinned right of the cell.
                local x = W:RemoveX(slot, 14, function() if handlers.onRemove then handlers.onRemove(idx) end end)
                x:SetPoint("RIGHT", -5, 0)

                local role = ns.classSpec.roleForSpec(m.class, m.spec, m.role)
                local roleAtlas = ns.classSpec.roleAtlas(role)
                local roleBtn = CreateFrame("Button", nil, slot)
                roleBtn:SetSize(14, 14)
                roleBtn:SetPoint("RIGHT", x, "LEFT", -3, 0)
                local roleIcon = roleBtn:CreateTexture(nil, "ARTWORK")
                roleIcon:SetAllPoints(roleBtn)
                if roleAtlas and roleIcon.SetAtlas then
                    roleIcon:SetAtlas(roleAtlas)
                    roleBtn._roleLabel = ns.classSpec.roleLabel(role)
                    roleBtn:SetScript("OnEnter", function(self)
                        if not (self._roleLabel and GameTooltip) then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(self._roleLabel, 1, 1, 1)
                    end)
                    roleBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                else
                    roleBtn:Hide()
                end

                -- Name between the icon and the role/✕ controls; bounded right so long
                -- names truncate instead of running under the controls.
                local nm = W:ClassName(slot, m.name, m.class)
                nm:SetPoint("LEFT", iconBtn, "RIGHT", 7, 0)
                nm:SetPoint("RIGHT", roleBtn, "LEFT", -4, 0)
                nm:SetJustifyH("LEFT")
                nm:SetWordWrap(false)

                -- Filled slots are a drag source.
                slot:RegisterForDrag("LeftButton")
                slot:SetScript("OnDragStart", function() if handlers.beginDrag then handlers.beginDrag(idx) end end)
            else
                -- Empty slots are a recessed (darker) cell with the same faint edge, so the
                -- grid reads as a full 8x5 of discrete cells.
                local cell = W:SlotCard(slot, true)
                cell:SetAllPoints(slot)
                Theme:Surface(cell, "base", true)  -- darker than the raised filled card
                W:CardEdge(cell, 0.08)
            end
        end
    end

    -- Position the 8 blocks for a given grid width: 4 rows of 2, read left-to-right then
    -- top-to-bottom, each block half-width.
    local function relayout(width)
        local W0 = tonumber(width) or 400
        if W0 < 1 then return end  -- ignore a zero/garbage pass; a later OnSizeChanged carries the real width
        for g = 1, 8 do
            local col = (g - 1) % 2
            local rowIdx = math.floor((g - 1) / 2)
            local block = blocks[g]
            block:ClearAllPoints()
            block:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * 0.5 * W0, -(PAD + rowIdx * (GROUP_H + PAD)))
            block:SetWidth((W0 * 0.5) - PAD * 2)
        end
    end

    -- The grid is a fixed-height content frame (4 group-rows tall) so the Panel can host it
    -- in a scroll area — the window can be shorter than the grid and you scroll to reach the
    -- lower groups. Height is constant; only the WIDTH reflows (2 columns).
    f._contentHeight = PAD + 4 * (GROUP_H + PAD)
    f:SetHeight(f._contentHeight)

    relayout(tonumber(parent:GetWidth()) or 400)
    f:SetScript("OnSizeChanged", function(self, w) relayout(w) end)

    return f
end

if type(ns) == "table" then ns.raid_groups_grid = Grid end
return Grid
