local ADDON, ns = ...

local Panel = ns:NewModule("LootActivePanel")
local Nav = ns:GetModule("Nav")
local Theme = ns:GetModule("Theme")
local W = ns:GetModule("Widgets")

-- Distribution subsystem modules (resolved lazily; may load after this file).
local function Store()  return ns:GetModule("LootDistStore")  end
local function Detect() return ns:GetModule("LootDistDetect") end
local function Sync()   return ns:GetModule("LootDistSync")   end
local function Popup()  return ns:GetModule("LootDistPopup")  end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Column geometry for the item table. X = left offset within the row; W = column width.
-- Item name occupies the left block (after caret + icon); the status columns are pulled LEFT
-- to make room for the inline response buttons (Upgrade/Minor/Off-Spec/PvP) that let any raider
-- respond directly on the row. Buttons sit to the right of Traded; Remind/Remove anchor right.
local COL_NAME_W   = 160
local COL_AWARDED_X, COL_AWARDED_W = 226, 118
local COL_TRADED_X, COL_TRADED_W   = 348, 40
-- Inline response buttons block: starts after Traded, 5 buttons (BiS/Upgrade/Minor/Off-Spec/PvP).
local RESP_BTN_X   = 430
local RESP_BTN_W   = 52
local PASS_BTN_W   = 48
local RESP_BTN_GAP = 3

-- The responses + their colours (match the mini-loot popup / responseColor). BiS first (pink).
local RESPONSE_BUTTONS = {
    { key = "bis",     label = "BiS",      color = { 0.96, 0.46, 0.86 } },  -- pink
    { key = "upgrade", label = "Upgrade",  color = { 0.36, 0.86, 0.54 } },
    { key = "minor",   label = "Minor",    color = { 0.94, 0.73, 0.28 } },
    { key = "offspec", label = "Off-Spec", color = { 0.36, 0.62, 0.95 } },
    { key = "pvp",     label = "PvP",       color = { 0.95, 0.55, 0.28 } },
}

local function qualityColor(q)
    q = tonumber(q)
    if q == 5 then return 1.00, 0.50, 0.00 end
    if q == 4 then return 0.64, 0.21, 0.93 end
    if q == 3 then return 0.00, 0.44, 0.87 end
    if q == 2 then return 0.12, 1.00, 0.00 end
    return Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3]
end

local function shortName(value)
    if not value or value == "" then return "-" end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(value) end
    return (strsplit("-", value))
end

local function showItemTooltip(owner, item)
    if not GameTooltip or not item then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if item.itemLink then
        GameTooltip:SetHyperlink(item.itemLink)
    elseif item.itemId then
        GameTooltip:SetHyperlink("item:" .. tostring(item.itemId))
    else
        GameTooltip:SetText(item.itemName or "Loot")
    end
    GameTooltip:Show()
end

local function showLootInfoTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Loot")
    GameTooltip:AddLine("Shift-click an item from your bags, loot window, or chat while this tab is open to add it manually.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("Ask Raid opens the mini-loot window for unawarded items. Raiders can also respond directly from this table.", 0.78, 0.82, 0.90, true)
    GameTooltip:AddLine("Loot Settings controls filtering, mini-loot behavior, and who may distribute loot.", 0.78, 0.82, 0.90, true)
    GameTooltip:Show()
end

local function entryIcon(entry)
    if entry.icon then return entry.icon end
    if entry.itemId and GetItemIcon then
        local ic = GetItemIcon(entry.itemId)
        if ic then return ic end
    end
    return QUESTION_ICON
end

local function entryName(entry)
    return entry.itemLink or entry.itemName or ("Item " .. tostring(entry.itemId or "?"))
end

local function responseCount(entry)
    local n = 0
    for _ in pairs(entry.responses or {}) do n = n + 1 end
    return n
end

-- Response -> display label + color.
local RESPONSE_LABEL = {
    bis = "BiS", upgrade = "Upgrade", minor = "Minor", offspec = "Off-Spec", pvp = "PvP",
}
local function responseLabel(r) return RESPONSE_LABEL[r] or (r or "?") end
local function responseColor(r)
    if r == "bis"     then return 0.96, 0.46, 0.86 end   -- pink
    if r == "upgrade" then return 0.36, 0.86, 0.54 end   -- green
    if r == "minor"   then return 0.94, 0.73, 0.28 end   -- yellow
    if r == "offspec" then return 0.36, 0.62, 0.95 end   -- blue
    if r == "pvp"     then return 0.95, 0.55, 0.28 end   -- orange
    return Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3]
end

local function classRGB(classFile)
    classFile = tostring(classFile or ""):upper()
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3]
end

local RESPONSE_RANK = { bis = 0, upgrade = 1, minor = 2, offspec = 3, pvp = 4 }
local function sortedResponses(entry)
    local list = {}
    for _, r in pairs(entry.responses or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        local ar, br = RESPONSE_RANK[a.response] or 99, RESPONSE_RANK[b.response] or 99
        if ar ~= br then return ar < br end
        return tostring(a.player) < tostring(b.player)
    end)
    return list
end

-- Can the local player distribute loot (Ask Raid / Award / Add / Remove)? Single source of
-- truth lives in Detect:CanDistributeLoot(); the panel just mirrors it for button-enable.
local function canDistribute()
    local d = Detect()
    return d and d:CanDistributeLoot() and true or false
end

local function now() return (GetTime and GetTime()) or (time and time()) or 0 end

-- The local player's recorded response for an entry (short-name lower key), or nil.
local function myChoice(entry)
    if not entry or not entry.responses then return nil end
    local me = (UnitName and UnitName("player")) or "me"
    local key = shortName(me):lower()
    local r = entry.responses[key]
    return r and r.response or nil
end

-- Record + broadcast THIS player's response to an entry (any raider may respond from the row).
local function respondToEntry(entryId, responseKey)
    local store = Store()
    if not store or not entryId or not responseKey then return end
    local me = (UnitName and UnitName("player")) or "me"
    local myClass
    if UnitClass then local _, cf = UnitClass("player"); myClass = cf end
    store:SetResponse(entryId, me, myClass, responseKey, "", now())
    local s = Sync()
    if s and s.BroadcastResponse then s:BroadcastResponse(entryId, responseKey, "") end
end

local function clearEntryResponse(entryId)
    local store = Store()
    if not store or not entryId then return end
    local me = (UnitName and UnitName("player")) or "me"
    if store.ClearResponse then store:ClearResponse(entryId, me, now()) end
    local s = Sync()
    if s and s.BroadcastClearResponse then s:BroadcastClearResponse(entryId) end
end

local function lootTabShouldShowEntry(entry)
    if not entry or not entry.itemId then return true end
    local db = ns:GetModule("DB"); db = db and db.db
    local settings = db and db.settings and db.settings.lootSettings
    if not settings or settings.smartMiniLootFilter ~= true then return true end
    local popup = Popup()
    if popup and popup.IsItemRelevant then return popup:IsItemRelevant(entry.itemId) end
    return true
end

local function guildRankItems()
    local byValue = {}
    if GuildControlGetNumRanks and GuildControlGetRankName then
        local count = tonumber(GuildControlGetNumRanks()) or 0
        for i = 1, count do
            local idx = i - 1
            local name = GuildControlGetRankName(i)
            byValue[idx] = name and name ~= "" and name or ("Rank " .. idx)
        end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers() or 0) do
            local _, rankName, rankIndex = GetGuildRosterInfo(i)
            rankIndex = tonumber(rankIndex)
            if rankIndex ~= nil and byValue[rankIndex] == nil then
                byValue[rankIndex] = rankName and rankName ~= "" and rankName or ("Rank " .. rankIndex)
            end
        end
    end
    if next(byValue) == nil then
        for i = 0, 9 do byValue[i] = "Rank " .. i end
    end
    local items = {}
    for rankIndex, rankName in pairs(byValue) do
        items[#items + 1] = { value = rankIndex, label = ("%d - %s"):format(rankIndex, rankName) }
    end
    table.sort(items, function(a, b) return a.value < b.value end)
    return items
end

local function policyUsesGuildRank(policy)
    return tostring(policy or ""):find("guild", 1, true) ~= nil
end

local function buildPanel(parent)
    local f = W:Card(parent, "base", true)
    Panel:SetFrame(f)

    f.expanded = {}      -- [entryId] = true
    f.rows = {}          -- entry ListRow pool
    f.subRows = {}       -- responder sub-row pool

    local title = W:Title(f, "Loot")
    title:SetPoint("TOPLEFT", 18, -16)

    local infoBtn = W:Button(f, "?", 22, 22)
    infoBtn:SetPoint("LEFT", title, "RIGHT", 8, 0)
    infoBtn:SetScript("OnEnter", showLootInfoTooltip)
    infoBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.infoBtn = infoBtn

    -- ---- Officer header controls -------------------------------------------
    local askBtn = W:Button(f, "Ask Raid", 86, 24)
    askBtn:SetTone("blue")
    askBtn:SetPoint("TOPRIGHT", -18, -16)
    askBtn:SetScript("OnClick", function()
        local store, sync, popup = Store(), Sync(), Popup()
        if not store then return end
        local ids, items = {}, {}
        for _, e in ipairs(store:SortedEntries()) do
            if not e.award and e.itemId then   -- skip malformed entries with no itemId
                ids[#ids + 1] = e.id
                items[#items + 1] = { id = e.id, itemId = e.itemId, quality = e.quality }
            end
        end
        if sync then sync:BroadcastAsk(ids) end
        if popup then
            if ns.LOOT_DIST_TEST then ns:Print(("|cffaa88ffldist|r Ask button -> OnAsk with %d item(s)"):format(#items)) end
            local ok, err = pcall(function() popup:OnAsk(items) end)
            if not ok and ns.LOOT_DIST_TEST then ns:Print("|cffff5555ldist OnAsk ERROR:|r " .. tostring(err)) end
        end
        ns:Print(("Asked the raid about %d item%s."):format(#ids, #ids == 1 and "" or "s"), "success")
    end)
    f.askBtn = askBtn

    local clearBtn = W:Button(f, "Clear Awarded", 110, 24)
    clearBtn:SetPoint("RIGHT", askBtn, "LEFT", -8, 0)
    clearBtn:SetScript("OnClick", function()
        local store, d = Store(), Detect()
        if not store then return end
        local doomed = {}
        for _, e in ipairs(store:SortedEntries()) do
            if e.award and e.traded then doomed[#doomed + 1] = e.id end
        end
        for _, id in ipairs(doomed) do
            if d and d.Remove then d:Remove(id) else store:RemoveEntry(id) end
        end
        f:Refresh()
    end)
    f.clearBtn = clearBtn

    local function ls()
        local db = ns:GetModule("DB"); db = db and db.db
        if not db then return {} end
        db.settings = db.settings or {}
        db.settings.lootSettings = db.settings.lootSettings or {}
        return db.settings.lootSettings
    end

    -- Distribution-permission control (raid-leader-only). Decides who may add/remove/award loot.
    -- The leader's choice is broadcast to the group so everyone enforces the same policy.
    local PERM_ITEMS = {
        { value = "assist", label = "Raid Leader + Assists" },
        { value = "leader", label = "Raid Leader only" },
        { value = "guild", label = "Raid Leader + Guild Rank" },
        { value = "assist_and_guild", label = "Raid Leader + Assist with Guild Rank" },
        { value = "assist_or_guild", label = "Raid Leader + Assist or Guild Rank" },
    }

    local settingsBtn = W:Button(f, "Loot Settings", 104, 24)
    settingsBtn:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
    f.settingsBtn = settingsBtn

    local settingsBackdrop = CreateFrame("Button", nil, f)
    settingsBackdrop:SetAllPoints(f)
    settingsBackdrop:EnableMouse(true)
    settingsBackdrop:Hide()
    if settingsBackdrop.SetFrameLevel and f.GetFrameLevel then settingsBackdrop:SetFrameLevel((f:GetFrameLevel() or 1) + 35) end
    f.settingsBackdrop = settingsBackdrop

    local settings = W:Card(f, "float", false)
    settings:SetSize(420, 282)
    settings:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -48)
    if settings.SetFrameLevel and f.GetFrameLevel then settings:SetFrameLevel((f:GetFrameLevel() or 1) + 40) end
    settings:EnableMouse(true)
    settings:Hide()
    settings:HookScript("OnHide", function() settingsBackdrop:Hide() end)
    f.settingsPanel = settings

    local settingsTitle = W:Eyebrow(settings, "Loot Settings")
    settingsTitle:SetPoint("TOPLEFT", 16, -14)
    local closeSettings = W:Button(settings, "x", 20, 18)
    closeSettings:SetPoint("TOPRIGHT", -10, -10)
    closeSettings:SetScript("OnClick", function() settings:Hide(); settingsBackdrop:Hide() end)
    settingsBackdrop:SetScript("OnClick", function() settings:Hide(); settingsBackdrop:Hide() end)

    local cbSmartFilter = W:Checkbox(settings, "Only show usable/relevant loot",
        function() return ls().smartMiniLootFilter == true end,
        function(v)
            ls().smartMiniLootFilter = v and true or false
            f:Refresh()
            local popup = Popup()
            if popup and popup.OnFilterChanged then popup:OnFilterChanged() end
        end)
    cbSmartFilter:SetPoint("TOPLEFT", 16, -44)
    f.cbSmartFilter = cbSmartFilter

    local cbOpenOnAdd = W:Checkbox(settings, "Open mini loot when loot is added",
        function() return ls().autoOpenMiniLootOnAdd == true end,
        function(v) ls().autoOpenMiniLootOnAdd = v and true or false end)
    cbOpenOnAdd:SetPoint("TOPLEFT", 16, -70)
    f.cbOpenOnAdd = cbOpenOnAdd

    local cbDisable = W:Checkbox(settings, "Don't auto-open mini loot window",
        function() return ls().disableMiniLoot == true end,
        function(v) ls().disableMiniLoot = v and true or false end)
    cbDisable:SetPoint("TOPLEFT", 16, -96)
    f.cbDisableMiniLoot = cbDisable

    local cbCombat = W:Checkbox(settings, "Close mini loot in combat",
        function() local lw = ls().lootWindow or {}; return lw.closeOnCombat ~= false end,
        function(v) ls().lootWindow = ls().lootWindow or {}; ls().lootWindow.closeOnCombat = v and true or false end)
    cbCombat:SetPoint("TOPLEFT", 16, -122)
    f.cbCombat = cbCombat

    local permLabel = settings:CreateFontString(nil, "OVERLAY")
    Theme:Text(permLabel, "caption", "dim")
    permLabel:SetPoint("TOPLEFT", 16, -154)
    permLabel:SetText("Who can add / remove / award loot:")
    local permDD = W:Dropdown(settings, {
        width = 292, height = 22, sharp = true,
        keepOpenOnRefresh = true,
        get = function() local d = Detect(); return d and d:DistributePolicy() or "assist" end,
        set = function(v)
            local d = Detect()
            if not d then return end
            local rank = ls().distributeGuildRank
            d:SetDistributePolicy(v, rank)
            local s = Sync(); if s and s.BroadcastPolicy then s:BroadcastPolicy(v, rank) end
            f:Refresh()
            if settings.Refresh then settings:Refresh() end
        end,
        items = function() return PERM_ITEMS end,
    })
    permDD:SetPoint("TOPLEFT", 16, -180)
    f.permLabel, f.permDD = permLabel, permDD

    local rankLabel = settings:CreateFontString(nil, "OVERLAY")
    Theme:Text(rankLabel, "caption", "dim")
    rankLabel:SetPoint("TOPLEFT", 16, -214)
    rankLabel:SetText("Guild rank threshold (0 highest):")
    local rankDD = W:Dropdown(settings, {
        width = 220, height = 22, sharp = true, maxVisible = 8,
        keepOpenOnRefresh = true,
        get = function() return tonumber(ls().distributeGuildRank) or 2 end,
        set = function(v)
            v = tonumber(v) or 2
            ls().distributeGuildRank = v
            local d = Detect()
            local policy = d and d.DistributePolicy and d:DistributePolicy() or ls().distributePermission or "assist"
            if d and d.SetDistributePolicy then d:SetDistributePolicy(policy, v) end
            local s = Sync(); if s and s.BroadcastPolicy then s:BroadcastPolicy(policy, v) end
            f:Refresh()
            if settings.Refresh then settings:Refresh() end
        end,
        items = guildRankItems,
    })
    rankDD:SetPoint("TOPLEFT", 16, -236)
    f.guildRankLabel, f.guildRankDD = rankLabel, rankDD

    function settings:Refresh()
        if cbSmartFilter.SetChecked then cbSmartFilter:SetChecked(ls().smartMiniLootFilter == true) end
        if cbOpenOnAdd.SetChecked then cbOpenOnAdd:SetChecked(ls().autoOpenMiniLootOnAdd == true) end
        if cbDisable.SetChecked then cbDisable:SetChecked(ls().disableMiniLoot == true) end
        if cbCombat.SetChecked then local lw = ls().lootWindow or {}; cbCombat:SetChecked(lw.closeOnCombat ~= false) end
        if permDD.Refresh then permDD:Refresh() end
        if rankDD.Refresh then rankDD:Refresh() end
        local d = Detect()
        local isLeader = d and d.IsRaidLeader and d:IsRaidLeader()
        if isLeader then permDD:Enable() else permDD:Disable() end
        local rankEnabled = isLeader and policyUsesGuildRank(d and d.DistributePolicy and d:DistributePolicy() or ls().distributePermission)
        if rankEnabled then
            rankDD:Enable()
            rankLabel:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
        else
            rankDD:Disable()
            rankLabel:SetTextColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], 0.72)
        end
    end

    settingsBtn:SetScript("OnClick", function()
        if settings:IsShown() then
            settings:Hide()
            settingsBackdrop:Hide()
        else
            settings:Refresh()
            settingsBackdrop:Show()
            settings:Show()
        end
    end)
    f:HookScript("OnHide", function()
        if settings then settings:Hide() end
        if settingsBackdrop then settingsBackdrop:Hide() end
    end)

    -- Shift-click an item ANYWHERE (bags, loot, chat) to add it straight to the loot list while
    -- the Loot page is open — no text box required.
    if not Panel._shiftAddHooked and type(HandleModifiedItemClick) == "function" and IsModifiedClick then
        Panel._shiftAddHooked = true
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not link or not IsModifiedClick("CHATLINK") then return end
            local pf = Panel.frame
            if not (pf and pf.IsVisible and pf:IsVisible()) then return end
            if not canDistribute() then return end
            local d = Detect()
            if d and d.ManualAdd then d:ManualAdd(link) end
            if pf.Refresh then pf:Refresh() end
        end)
    end

    -- ---- Column header -----------------------------------------------------
    -- A static header so the "Awarded To" / "Traded" columns read as a table. The X offsets
    -- match the per-row column constants; +6 accounts for the row's left inset under the icon.
    local function headerLabel(text, x, w)
        local fs = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(fs, "caption", "dim")
        fs:SetPoint("TOPLEFT", 18 + 6 + x, -64)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        return fs
    end
    f.hdrItem    = headerLabel("Item", 40, COL_NAME_W)             -- after caret(12)+icon(24)+gaps
    f.hdrAwarded = headerLabel("Awarded To", COL_AWARDED_X, COL_AWARDED_W)
    f.hdrTraded  = headerLabel("Traded", COL_TRADED_X, COL_TRADED_W)
    f.hdrResp    = headerLabel("Your Response", RESP_BTN_X, RESP_BTN_W * 5 + RESP_BTN_GAP * 5 + PASS_BTN_W)

    -- Thin rule under the header.
    f.hdrRule = f:CreateTexture(nil, "ARTWORK")
    f.hdrRule:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.hdrRule:SetVertexColor(1, 1, 1, 0.10)
    f.hdrRule:SetPoint("TOPLEFT", 18, -80)
    f.hdrRule:SetPoint("TOPRIGHT", -28, -80)
    f.hdrRule:SetHeight(1)

    -- ---- Scroll list -------------------------------------------------------
    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 18, -84)
    sf:SetPoint("BOTTOMRIGHT", -28, 18)
    f.scroll = sf
    f.content = content
    f.bar = W:ScrollBar(sf, content)

    -- Entry rows ------------------------------------------------------------
    function f:EnsureRow(i)
        local row = self.rows[i]
        if row then return row end
        row = W:ListRow(content)
        row:SetHeight(34)

        -- Expand/collapse indicator: a plain + / - to the LEFT of the icon.
        row.caret = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.caret, "body", "dim")
        row.caret:SetPoint("LEFT", 8, 0)
        row.caret:SetWidth(12)
        row.caret:SetJustifyH("CENTER")

        -- Anchor the icon to the row's TOPLEFT with INTEGER offsets, not centered on the caret
        -- fontstring. Centering on a fontstring can put the icon's edges on half-pixels, which
        -- makes the quality border round to 1px on some sides and 2px on others. Fixed integer
        -- offsets keep all four edges on whole pixels so the border is even. (Row is 34px tall,
        -- icon 24px -> top inset 5 centers it.)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -5)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconBorder = W:IconBorder(row.icon)

        -- Item-name column (left block).
        row.name = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.name, "caption", "ink")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(COL_NAME_W)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        -- Tooltip/click target for only the item identity area (icon + name). The full row can
        -- still hover/toggle, but mousing response buttons or status columns no longer shows the
        -- item tooltip.
        row.itemHotspot = CreateFrame("Button", nil, row)
        row.itemHotspot:SetPoint("LEFT", row.icon, "LEFT", 0, 0)
        row.itemHotspot:SetSize(24 + 8 + COL_NAME_W, 30)
        row.itemHotspot:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            if parent and parent.SetRowHover then parent:SetRowHover(true) end
            showItemTooltip(self, parent and parent.item)
        end)
        row.itemHotspot:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            local parent = self:GetParent()
            if parent and parent.SetRowHover and not parent:IsMouseOver() then parent:SetRowHover(false) end
        end)
        row.itemHotspot:SetScript("OnMouseUp", function(self)
            local parent = self:GetParent()
            if parent and parent._onToggle then parent:_onToggle() end
        end)

        -- "Awarded To" column: class-coloured winner name (or — / response count).
        row.awarded = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.awarded, "caption", "ink")
        row.awarded:SetPoint("LEFT", COL_AWARDED_X, 0)
        row.awarded:SetWidth(COL_AWARDED_W)
        row.awarded:SetJustifyH("LEFT")
        row.awarded:SetWordWrap(false)

        -- "Traded" column: Yes / No / — .
        row.traded = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.traded, "caption", "dim")
        row.traded:SetPoint("LEFT", COL_TRADED_X, 0)
        row.traded:SetWidth(COL_TRADED_W)
        row.traded:SetJustifyH("LEFT")
        row.traded:SetWordWrap(false)

        -- Inline response buttons (Upgrade/Minor/Off-Spec/PvP) — ANY raider may click to respond
        -- directly on the row, no "Ask Raid" needed. Coloured to match the mini-loot popup.
        row.respBtns = {}
        do
            local prev
            for _, def in ipairs(RESPONSE_BUTTONS) do
                local b = W:Button(row, def.label, RESP_BTN_W, 18)
                if prev then b:SetPoint("LEFT", prev, "RIGHT", RESP_BTN_GAP, 0)
                else b:SetPoint("LEFT", RESP_BTN_X, 0) end
                b._respColor = def.color
                if def.color and b.SetLabelColor then b:SetLabelColor(def.color[1], def.color[2], def.color[3]) end
                row.respBtns[def.key] = b
                prev = b
            end
            row.passBtn = W:Button(row, "Pass", PASS_BTN_W, 18)
            row.passBtn:SetPoint("LEFT", prev, "RIGHT", RESP_BTN_GAP, 0)
            if row.passBtn.SetLabelColor then row.passBtn:SetLabelColor(1, 1, 1) end
        end

        -- Per-row officer buttons (anchored from the right). No per-row Ask — the top-right
        -- "Ask Raid" button covers it.
        row.removeBtn = W:Button(row, "Remove", 66, 22)
        row.removeBtn:SetPoint("RIGHT", -16, 0)   -- inset so it stays inside the item label
        row.remindBtn = W:Button(row, "Remind", 66, 22)
        row.remindBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 0)

        row:SetScript("OnEnter", function(self)
            self:SetRowHover(true)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetRowHover(false)
            if GameTooltip then GameTooltip:Hide() end
        end)
        -- Click the row itself to toggle the responder list.
        row:SetScript("OnMouseUp", function(self)
            if self._onToggle then self._onToggle() end
        end)
        self.rows[i] = row
        return row
    end

    -- Responder sub-rows (plain frames) -------------------------------------
    function f:EnsureSubRow(i)
        local row = self.subRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(24)

        -- Subtle table background so the responder list reads as rows (alternating tint).
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.bg:SetPoint("TOPLEFT", 40, 0)      -- indent under the item, leaving the expand gutter
        row.bg:SetPoint("BOTTOMRIGHT", -4, 1)

        row.player = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.player, "caption", "ink")
        row.player:SetPoint("LEFT", 56, 0)
        row.player:SetWidth(130)
        row.player:SetJustifyH("LEFT")
        row.player:SetWordWrap(false)

        row.resp = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.resp, "caption", "dim")
        row.resp:SetPoint("LEFT", 192, 0)
        row.resp:SetWidth(80)
        row.resp:SetJustifyH("LEFT")

        row.note = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.note, "caption", "dim")
        row.note:SetPoint("LEFT", 280, 0)
        row.note:SetWidth(260)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(false)

        row.awardBtn = W:Button(row, "Award", 52, 18)
        row.awardBtn:SetTone("green")
        row.awardBtn:SetPoint("RIGHT", -16, 0)   -- inset so it stays inside the window

        self.subRows[i] = row
        return row
    end

    function f:Refresh()
        for _, row in ipairs(self.rows) do row:Hide() end
        for _, row in ipairs(self.subRows) do row:Hide() end

        -- `officer` here means "may distribute loot" (leader/assist). Drives every officer-only
        -- control: Ask Raid, Clear Awarded, per-row Remind/Remove, and the Award button.
        local officer = canDistribute()
        if officer then self.askBtn:Enable(); self.clearBtn:Enable()
        else self.askBtn:Disable(); self.clearBtn:Disable() end
        -- (self.askBtn is the TOP-RIGHT "Ask Raid" button, not a per-row one.)

        -- The permission dropdown is the RAID LEADER's to set; reflect the current policy and
        -- only let the leader change it (assists/raiders see it but can't troll the setting).
        if self.settingsPanel and self.settingsPanel.Refresh then
            self.settingsPanel:Refresh()
        end

        local store = Store()
        local allEntries = store and store:SortedEntries() or {}
        local entries, filteredCount = {}, 0
        for _, entry in ipairs(allEntries) do
            if lootTabShouldShowEntry(entry) then
                entries[#entries + 1] = entry
            else
                filteredCount = filteredCount + 1
            end
        end
        -- Min width fits: 5 response buttons (end ~702) + a gap + the right-anchored Remind/Remove
        -- (~140px). 860 keeps them from overlapping.
        local contentW = math.max(860, (sf:GetWidth() or 0) - 8)
        content:SetWidth(contentW)

        if #entries == 0 then
            local row = self:EnsureRow(1)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetSize(contentW, 34)
            row:SetRowVisual(1, false)
            row.icon:SetTexture(QUESTION_ICON)
            row.icon:Show()
            if row.iconBorder then row.iconBorder:Hide() end   -- placeholder row: no quality border
            row.caret:SetText("")
            row.name:SetText(filteredCount > 0 and "No loot matching your filter." or "No loot to distribute yet.")
            row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            row.awarded:SetText(""); row.traded:SetText("")
            if row.respBtns then for _, b in pairs(row.respBtns) do b:Hide() end end
            if row.passBtn then row.passBtn:Hide() end
            if row.itemHotspot then row.itemHotspot:Hide() end
            row.remindBtn:Hide(); row.removeBtn:Hide()
            row._onToggle = nil
            row.item = nil
            row:Show()
            content:SetHeight(math.max(sf:GetHeight() or 1, 34))
            self.bar:Update()
            return
        end

        local y, rowIndex, subIndex = 0, 0, 0
        for _, entry in ipairs(entries) do
            rowIndex = rowIndex + 1
            local row = self:EnsureRow(rowIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(contentW, 34)
            row:SetRowVisual(rowIndex, self.expanded[entry.id])
            row.icon:SetTexture(entryIcon(entry))
            row.icon:Show()
            if row.itemHotspot then row.itemHotspot:Show() end
            if row.iconBorder then row.iconBorder:SetQuality(entry.quality) end
            -- Item name, with "  x2"/"x3" appended when quantity > 1.
            local qty = tonumber(entry.quantity) or 1
            local nameText = entryName(entry)
            if qty > 1 then nameText = nameText .. ("  |cffaaaaaax%d|r"):format(qty) end
            row.name:SetText(nameText)
            row.name:SetTextColor(qualityColor(entry.quality))

            -- "Awarded To" column — class-coloured winner(s). For multi-copy items shows all
            -- winners + the (awarded/total) count; before any award, a dim response count.
            local awards = entry.awards or (entry.award and { entry.award }) or {}
            if #awards > 0 then
                if #awards == 1 then
                    row.awarded:SetText(shortName(awards[1].winner) .. (qty > 1 and (" (1/%d)"):format(qty) or ""))
                    row.awarded:SetTextColor(classRGB(awards[1].winner and awards[1].winnerClass))
                else
                    local names = {}
                    for _, a in ipairs(awards) do names[#names + 1] = shortName(a.winner) end
                    row.awarded:SetText(("%s (%d/%d)"):format(table.concat(names, ", "), #awards, qty))
                    row.awarded:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
                end
            else
                local n = responseCount(entry)
                row.awarded:SetText(("— (%d response%s)"):format(n, n == 1 and "" or "s"))
                row.awarded:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            end

            -- "Traded" column — Yes (green) / No (dim) once awarded; a plain — before award.
            if not entry.award then
                row.traded:SetText("—")
                row.traded:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            elseif entry.traded then
                row.traded:SetText("Yes")
                row.traded:SetTextColor(Theme.color.success[1], Theme.color.success[2], Theme.color.success[3], 1)
            else
                row.traded:SetText("No")
                row.traded:SetTextColor(Theme.color.warm[1], Theme.color.warm[2], Theme.color.warm[3], 1)
            end

            -- Inline response buttons: every raider can respond directly here. Hidden once ALL
            -- copies are awarded. Once a selection is made, the chosen button keeps its colour and
            -- the others grey out (text) + dim — matching the mini-loot window.
            local store0 = Store()
            local fullyAwarded = store0 and store0.IsFullyAwarded and store0:IsFullyAwarded(entry.id)
            local mine = myChoice(entry)
            for key, b in pairs(row.respBtns) do
                if fullyAwarded then
                    b:Hide()
                else
                    b:Show()
                    local selected = (mine == key)
                    b:SetAlpha(mine == nil and 1 or (selected and 1 or 0.55))
                    if b.SetLabelColor then
                        if mine ~= nil and not selected then
                            b:SetLabelColor(0.45, 0.45, 0.45)           -- greyed: answered, not this one
                        elseif b._respColor then
                            b:SetLabelColor(b._respColor[1], b._respColor[2], b._respColor[3])
                        end
                    end
                    b:SetScript("OnClick", function()
                        respondToEntry(entry.id, key)
                        self:Refresh()
                    end)
                end
            end
            if fullyAwarded then
                row.passBtn:Hide()
            else
                row.passBtn:Show()
                if row.passBtn.SetLabelColor then row.passBtn:SetLabelColor(1, 1, 1) end
                row.passBtn:SetAlpha(mine and 1 or 0.35)
                if mine then row.passBtn:Enable() else row.passBtn:Disable() end
                row.passBtn:SetScript("OnClick", function()
                    if not myChoice(entry) then return end
                    clearEntryResponse(entry.id)
                    self:Refresh()
                end)
            end

            -- Expand indicator: + (collapsed) / - (expanded) to the left of the icon, shown
            -- only when the item has responses to reveal.
            local hasResponses = responseCount(entry) > 0
            row.caret:SetText(hasResponses and (self.expanded[entry.id] and "-" or "+") or "")
            row._onToggle = function()
                self.expanded[entry.id] = not self.expanded[entry.id]
                self:Refresh()
            end

            -- Per-row officer buttons
            if officer then
                if entry.award and entry.tradeWindowEndsAt then
                    row.remindBtn:Show()
                    row.remindBtn:SetScript("OnClick", function()
                        local d = Detect()
                        if d then d:Remind(entry.id) end
                    end)
                else
                    row.remindBtn:Hide()
                end

                row.removeBtn:Show()
                row.removeBtn:SetScript("OnClick", function()
                    local d = Detect()
                    -- Remove DECREMENTS quantity (x2 -> x1); at the last copy it deletes the row.
                    if d and d.RemoveOne then d:RemoveOne(entry.id)
                    elseif d and d.Remove then d:Remove(entry.id) end
                    self:Refresh()
                end)
            else
                row.remindBtn:Hide(); row.removeBtn:Hide()
            end

            row.item = entry
            row:Show()
            y = y - 34

            -- Expanded responder sub-rows
            if self.expanded[entry.id] then
                local respList = sortedResponses(entry)
                for ri, r in ipairs(respList) do
                    subIndex = subIndex + 1
                    local srow = self:EnsureSubRow(subIndex)
                    srow:ClearAllPoints()
                    srow:SetPoint("TOPLEFT", 0, y)
                    srow:SetSize(contentW, 24)
                    -- Dark-grey responder rows (the panel the class-coloured names sit on), with
                    -- a subtle alternation so the table is still readable.
                    if ri % 2 == 0 then srow.bg:SetVertexColor(0.05, 0.05, 0.06, 1)
                    else srow.bg:SetVertexColor(0.07, 0.07, 0.08, 1) end
                    srow.bg:Show()
                    srow.player:SetText(shortName(r.player))
                    srow.player:SetTextColor(classRGB(r.classFile))
                    srow.resp:SetText(responseLabel(r.response))
                    srow.resp:SetTextColor(responseColor(r.response))
                    srow.note:SetText(r.note and r.note ~= "" and r.note or "")
                    srow.note:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
                    -- Has this responder already been awarded a copy?
                    local alreadyWon = false
                    for _, a in ipairs(entry.awards or (entry.award and { entry.award }) or {}) do
                        if shortName(a.winner):lower() == shortName(r.player):lower() then alreadyWon = true; break end
                    end
                    if officer and not alreadyWon and not fullyAwarded then
                        srow.awardBtn:Show()
                        srow.awardBtn:Enable()
                        srow.awardBtn:SetScript("OnClick", function()
                            local d = Detect()
                            if d then d:Award(entry.id, r.player) end
                            self:Refresh()
                        end)
                    else
                        srow.awardBtn:Hide()
                    end
                    srow:Show()
                    y = y - 24
                end
            end
        end

        content:SetHeight(math.max(sf:GetHeight() or 1, -y))
        self.bar:Update()
    end

    -- 10s tick keeps trade-window countdowns / states fresh.
    f:SetScript("OnUpdate", function(self, elapsed)
        self._tick = (self._tick or 0) + elapsed
        if self._tick < 10 then return end
        self._tick = 0
        if self:IsShown() then self:Refresh() end
    end)

    f:Refresh()
    return f
end

-- Frame handshake: Sync may call ns:GetModule("LootActivePanel"):Refresh().
function Panel:SetFrame(frame) self.frame = frame end

-- Debounced live refresh; no-op when hidden.
function Panel:Refresh()
    if not (self.frame and self.frame.Refresh and self.frame:IsShown()) then return end
    if self._refreshPending then return end
    self._refreshPending = true
    local function fire()
        self._refreshPending = nil
        if self.frame and self.frame.Refresh and self.frame:IsShown() then self.frame:Refresh() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, fire) else fire() end
end

Nav:RegisterPanel("loot", buildPanel)
