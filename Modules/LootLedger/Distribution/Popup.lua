local ADDON, ns = ...

-- LootDistPopup: the raider-side mini-loot popup. When an officer "Asks" the raid about
-- one or more items (LDASK1), this surfaces a small, movable themed window with one row per
-- item: icon + quality-colored link + four response buttons (Upgrade/Minor/Off-Spec/PvP) +
-- a small note field. Clicking a button records the choice locally (Store) and broadcasts it
-- (Sync). Settings (db.settings.lootSettings) gate whether the popup auto-opens.
local Popup = ns:NewModule("LootDistPopup")

local function Store() return ns:GetModule("LootDistStore") end
local function Sync() return ns:GetModule("LootDistSync") end
local function DB() local d = ns:GetModule("DB"); return d and d.db or nil end
local function lootSettings()
    local db = DB()
    local s = db and db.settings and db.settings.lootSettings
    return s or {}
end
local function now() return (GetTime and GetTime()) or (time and time()) or (os and os.time and os.time()) or 0 end
local function Players() return ns.GetModule and ns:GetModule("Players") or nil end
local function shortLower(name)
    local players = Players()
    if players and players.ShortName then return players:ShortName(name):lower() end
    name = tostring(name or "")
    return (name:match("^([^-]+)") or name):lower()
end

local function lower(value) return tostring(value or ""):lower() end

local HEALER_CLASSES = { PRIEST=true, DRUID=true, SHAMAN=true, PALADIN=true, MONK=true, EVOKER=true }
local CASTER_CLASSES = { MAGE=true, WARLOCK=true, PRIEST=true, DRUID=true, SHAMAN=true, PALADIN=true, EVOKER=true }
local PHYSICAL_CLASSES = { WARRIOR=true, ROGUE=true, HUNTER=true, DRUID=true, SHAMAN=true, PALADIN=true, DEATHKNIGHT=true, MONK=true }
local TANK_CLASSES = { WARRIOR=true, PALADIN=true, DRUID=true, DEATHKNIGHT=true, MONK=true }

local function classFile()
    if not UnitClass then return nil end
    local _, cf = UnitClass("player")
    return cf and tostring(cf):upper() or nil
end

local function statFlags(stats)
    local flags = {
        explicitHealing = false,
        explicitSpell = false,
        mana = false,
        intellectSpirit = false,
        physical = false,
        tank = false,
    }
    for key, value in pairs(stats or {}) do
        if tonumber(value) and tonumber(value) > 0 then
            local k = lower(key)
            if k:find("healing", 1, true) then flags.explicitHealing = true end
            if k:find("spell", 1, true) and (k:find("power", 1, true) or k:find("damage", 1, true) or k:find("crit", 1, true) or k:find("hit", 1, true)) then
                flags.explicitSpell = true
            end
            if k:find("mana", 1, true) or k:find("mp5", 1, true) then flags.mana = true end
            if k:find("intellect", 1, true) or k:find("spirit", 1, true) then flags.intellectSpirit = true end
            if k:find("strength", 1, true) or k:find("agility", 1, true) or k:find("attack_power", 1, true) or k:find("ranged_attack_power", 1, true) or k:find("expertise", 1, true) or k:find("armor_penetration", 1, true) then
                flags.physical = true
            end
            if k:find("defense", 1, true) or k:find("dodge", 1, true) or k:find("parry", 1, true) or k:find("block", 1, true) then
                flags.tank = true
            end
        end
    end
    return flags
end

local function classMatchesStats(class, flags)
    if not class then return true end
    local hasRoleSignal = flags.explicitHealing or flags.explicitSpell or flags.mana or flags.intellectSpirit or flags.physical or flags.tank
    if not hasRoleSignal then return true end

    -- TBC-style healing gear often has +healing and caster base stats. Treat healing-only
    -- items as healer-only so leather/mail/cloth healing pieces do not appear for Warriors,
    -- Rogues, Hunters, Mages, or Warlocks just because they can equip the armor type.
    if flags.explicitHealing and not flags.explicitSpell and not flags.physical and not flags.tank then
        return HEALER_CLASSES[class] == true
    end

    if flags.physical and PHYSICAL_CLASSES[class] then return true end
    if flags.tank and TANK_CLASSES[class] then return true end
    if (flags.explicitSpell or flags.intellectSpirit) and CASTER_CLASSES[class] then return true end
    if (flags.explicitHealing or flags.mana) and HEALER_CLASSES[class] then return true end
    return false
end

-- The responses, in display order. The colour matches the Loot tab's response text
-- (ActivePanel responseColor) so the mini-loot buttons read the same as the officer view.
local BUTTONS = {
    { key = "bis",     label = "BiS",      color = { 0.96, 0.46, 0.86 } },  -- pink
    { key = "upgrade", label = "Upgrade",  color = { 0.36, 0.86, 0.54 } },  -- green
    { key = "minor",   label = "Minor",    color = { 0.94, 0.73, 0.28 } },  -- yellow
    { key = "offspec", label = "Off-Spec", color = { 0.36, 0.62, 0.95 } },  -- blue
    { key = "pvp",     label = "PvP",       color = { 0.95, 0.55, 0.28 } },  -- orange
}
local PASS_COLOR = { 1, 1, 1 }

-- ---------------------------------------------------------------------------
-- Settings gate. Returns true if the popup should auto-open for this item.
-- Reads lootSettings + live game/Council state. Defensive: any missing dependency
-- collapses to the safe default (canManage=false, assigned=false, not boss).
-- ---------------------------------------------------------------------------
function Popup:ShouldShow(itemId)
    -- The mini-loot window opens for EVERYONE by default. The only gate is a single opt-out:
    -- db.settings.lootSettings.disableMiniLoot = true to suppress it. (Test mode always shows.)
    if ns.LOOT_DIST_TEST then return true end
    local s = lootSettings()
    if s.disableMiniLoot == true then return false end
    return self:IsItemRelevant(itemId)
end

function Popup:IsItemRelevant(itemId)
    local s = lootSettings()
    if s.smartMiniLootFilter == true and not self:ClassCanUse(itemId) then return false end
    return true
end

function Popup:ShouldAutoOpenOnEntryAdded()
    local s = lootSettings()
    return s.autoOpenMiniLootOnAdd == true and s.disableMiniLoot ~= true
end

-- IO: resolve usability of a concrete item for the local class via GetItemInfo.
-- Returns true when usable or unknown (never hides what we can't classify).
function Popup:ClassCanUse(itemId)
    if not GetItemInfo or not itemId or not UnitClass then return true end
    local _, itemType, itemSubType, equipLoc, classID
    do
        local r1, _, _, _, _, r6, r7, _, r9, _, _, r12 = GetItemInfo(itemId)
        if not r1 then return true end          -- uncached -> usable
        itemType, itemSubType, equipLoc, classID = r6, r7, r9, r12
    end
    if not itemType then return true end
    local myClass = classFile()
    if ns.tierTokens and ns.tierTokens.ClassCanUseLootItem then
        local tokenAllowed = ns.tierTokens.ClassCanUseLootItem(itemId, myClass)
        if tokenAllowed ~= nil then return tokenAllowed end
    end
    local store = Store()
    local isGear = (equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" and equipLoc ~= "INVTYPE_BAG") or itemType == "Weapon"
    if classID == 15 or not isGear then return true end -- tokens/misc/non-gear stay visible

    if itemType == "Armor" then
        if equipLoc ~= "INVTYPE_CLOAK" and equipLoc ~= "INVTYPE_FINGER" and equipLoc ~= "INVTYPE_NECK"
            and equipLoc ~= "INVTYPE_TRINKET" and equipLoc ~= "INVTYPE_HOLDABLE" then
            if store and not store:ArmorUsable(itemSubType, myClass) then return false end
        end
    elseif itemType == "Weapon" then
        if store and not store:WeaponUsable(itemSubType, myClass) then return false end
    else
        return true
    end

    local stats = GetItemStats and GetItemStats(itemId) or nil
    if not stats then return true end
    return classMatchesStats(myClass, statFlags(stats))
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------
-- Officer asked the raid. items = list of { id, itemId, quality } (no link — resolve).
function Popup:OnAsk(items)
    local store = Store(); if not store then return end
    self.active = self.active or {}
    local anyShown = false
    for _, item in ipairs(items or {}) do
        if item.id and item.itemId then   -- ignore malformed asks with no itemId
            store:EnsureEntry(item.id, { itemId = item.itemId, quality = item.quality })
            local show = self:ShouldShow(item.itemId)
            if ns.LOOT_DIST_TEST then ns:Print(("|cffaa88ffldist|r OnAsk item %s shouldShow=%s"):format(tostring(item.itemId), tostring(show))) end
            if show then
                self.active[item.id] = true
                anyShown = true
            end
        end
    end
    if ns.LOOT_DIST_TEST then ns:Print(("|cffaa88ffldist|r OnAsk: %d item(s), anyShown=%s"):format(#(items or {}), tostring(anyShown))) end
    if anyShown then self:Show() end
end

-- Self-open via slash: populate from all un-awarded entries and show. Rendering still applies
-- the live smart relevance filter, so toggling that setting can hide/show existing active rows.
function Popup:ShowCurrent()
    local store = Store(); if not store then return end
    self.active = {}
    for id, e in pairs(store:Entries()) do
        if e.award == nil then self.active[id] = true end
    end
    self:Show()
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------
function Popup:BuildFrame()
    if self.frame or not CreateFrame then return self.frame end
    local W = ns:GetModule("Widgets")
    if not W then return nil end

    local f = W:Card(UIParent, "float", false)
    f:SetSize(656, 70)   -- a touch wider so the response buttons + scrollbar both fit
    -- Drop the card's drop-shadow texture for this window (it bled out behind the frame).
    if f._shadow then f._shadow:Hide() end
    -- Darker-grey window background — darker than the default float tone, but still LIGHTER
    -- than the near-black item-row panels (0.04) so the rows read as insets on top of it.
    if f._bg then f._bg:SetVertexColor(0.075, 0.075, 0.085, 1) end
    -- Always render ABOVE the main addon window (which is HIGH strata). Use FULLSCREEN_DIALOG
    -- + Toplevel so the popup and ALL its child buttons sit cleanly on top — at equal strata
    -- the buttons' frame levels could fall behind the main window and "bleed through".
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    -- Start moving immediately on mouse-down rather than via RegisterForDrag, whose
    -- built-in threshold causes the "window doesn't move until you've dragged a few
    -- pixels, then snaps to the cursor" behaviour. Persist the position on mouse-up.
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local db = DB()
        if db then
            local p, _, rp, x, y = self:GetPoint()
            db.settings = db.settings or {}
            db.settings.lootSettings = db.settings.lootSettings or {}
            db.settings.lootSettings.lootWindow = db.settings.lootSettings.lootWindow or {}
            db.settings.lootSettings.lootWindow.point = { p, rp, x, y }
        end
    end)
    -- Restore saved position, else center-ish.
    local lw = lootSettings().lootWindow or {}
    if lw.point then
        f:SetPoint(lw.point[1] or "CENTER", UIParent, lw.point[2] or "CENTER", lw.point[3] or 0, lw.point[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end

    local title = W:Eyebrow(f, "Loot")
    title:SetPoint("TOPLEFT", 12, -10)
    local close = W:Button(f, "x", 20, 18)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() Popup:Hide() end)

    -- Scrollable item area: rows live in `content`, so the window caps at MAX_VISIBLE_ROWS and a
    -- scrollbar appears when there are more items than that.
    local sf, content = W:ScrollHost(f)
    sf:SetPoint("TOPLEFT", 8, -28)
    sf:SetPoint("BOTTOMRIGHT", -8, 8)
    f.scroll = sf
    f.content = content
    f.bar = W:ScrollBar(sf, content)

    f.rows = {}
    self.frame = f
    return f
end

-- The local player's recorded response for an entry (short-name lower key), or nil.
function Popup:MyChoice(id)
    local store = Store(); if not store then return nil end
    local e = store:Entries()[id]
    if not e or not e.responses then return nil end
    local me = (UnitName and UnitName("player")) or "me"
    local r = e.responses[shortLower(me)]
    return r and r.response or nil
end

function Popup:VisibleActiveIds()
    local store = Store()
    if not store then return {}, 0 end
    self.active = self.active or {}
    local entries = store:Entries()
    local ids, activeCount = {}, 0
    for id in pairs(self.active) do
        local e = entries[id]
        if e then
            activeCount = activeCount + 1
            if self:IsItemRelevant(e.itemId) then ids[#ids + 1] = id end
        end
    end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    return ids, activeCount
end

function Popup:OnFilterChanged()
    if not self.frame then return end
    if not (self.frame:IsShown() or self._hiddenByFilter) then return end
    local ids = self:VisibleActiveIds()
    if #ids > 0 and self._hiddenByFilter then
        self._hiddenByFilter = nil
        self:Show()
    else
        self:Refresh()
    end
end

function Popup:Refresh()
    local f = self.frame
    if not f then return end
    local W = ns:GetModule("Widgets")
    local store = Store()
    if not W or not store then return end
    local entries = store:Entries()

    -- Active entries that still exist, filtered live by the same relevance setting as the Loot tab.
    local ids, activeCount = self:VisibleActiveIds()

    for _, row in ipairs(f.rows) do row:Hide() end

    -- Single-line table rows, inside the scroll content frame. Window caps at MAX_VISIBLE_ROWS.
    local content = f.content or f
    local ROW_W, ROW_H = 620, 26
    local NAME_W = 140
    local BTN_W, BTN_GAP = 54, 4
    local PASS_W = 50
    local NOTE_W = 70
    local ROW_STEP = ROW_H + 4
    local MAX_VISIBLE_ROWS = 12
    local y = 0
    for i, id in ipairs(ids) do
        local e = entries[id]
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(ROW_W, ROW_H)

            -- Banded background for the table look.
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            row.bg:SetAllPoints(row)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 4, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.iconBorder = W:IconBorder(row.icon)

            -- Item name (left), hoverable for the item tooltip.
            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.nameBtn:SetSize(NAME_W, ROW_H)
            row.name = row.nameBtn:CreateFontString(nil, "OVERLAY")
            ns:GetModule("Theme"):Text(row.name, "caption", "ink")
            row.name:SetAllPoints(row.nameBtn)
            row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
            row.nameBtn:SetScript("OnEnter", function(self)
                if not GameTooltip or not row._e then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if row._e.itemLink then GameTooltip:SetHyperlink(row._e.itemLink)
                elseif row._e.itemId then GameTooltip:SetHyperlink("item:" .. tostring(row._e.itemId))
                else GameTooltip:SetText(row._e.itemName or "Loot") end
                GameTooltip:Show()
            end)
            row.nameBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

            -- Record + broadcast a response for this row. `response` may be a button key, or
            -- nil to re-send the EXISTING choice with whatever's currently in the note box
            -- (used when the note is edited after a button was already pressed).
            row.submit = function(response)
                local resp = response or Popup:MyChoice(row._id)
                if not resp then return false end   -- no selection yet: a bare note does nothing
                local note = row.noteInput and row.noteInput:GetText() or ""
                local me = (UnitName and UnitName("player")) or "me"
                -- NB: `local _, c = UnitClass and UnitClass("player")` truncates the multi-return
                -- via `and`, leaving c nil — which is why class colours never showed. Guard, then
                -- select the 2nd return explicitly.
                local myClass
                if UnitClass then local _, cf = UnitClass("player"); myClass = cf end
                store:SetResponse(row._id, me, myClass, resp, note, now())
                local s = Sync()
                if s and s.BroadcastResponse then s:BroadcastResponse(row._id, resp, note) end
                Popup:Refresh()
                return true
            end

            -- Response buttons (middle), anchored after the name column.
            row.btns = {}
            local prev
            for _, def in ipairs(BUTTONS) do
                local b = W:Button(row, def.label, BTN_W, 18)
                if prev then b:SetPoint("LEFT", prev, "RIGHT", BTN_GAP, 0)
                else b:SetPoint("LEFT", row.nameBtn, "RIGHT", 8, 0) end
                b._respColor = def.color   -- remembered so render can restore it / grey it out
                if def.color and b.SetLabelColor then b:SetLabelColor(def.color[1], def.color[2], def.color[3]) end
                b:SetScript("OnClick", function() row.submit(def.key) end)
                row.btns[def.key] = b
                prev = b
            end
            row.passBtn = W:Button(row, "Pass", PASS_W, 18)
            row.passBtn:SetPoint("LEFT", prev, "RIGHT", BTN_GAP, 0)
            if row.passBtn.SetLabelColor then row.passBtn:SetLabelColor(PASS_COLOR[1], PASS_COLOR[2], PASS_COLOR[3]) end

            -- Note field (right), inside the row's right edge. Editing the note after a button
            -- is already selected re-sends the response with the updated note — on Enter and
            -- when focus leaves the box — so the officer sees the note without a button dance.
            row.noteInput = W:TextInput(row, {
                placeholder = "note", width = NOTE_W, height = 18,
                onEnter = function() row.submit(nil) end,
            })
            row.noteInput:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            if row.noteInput.edit then
                row.noteInput.edit:HookScript("OnEditFocusLost", function() row.submit(nil) end)
            end

            f.rows[i] = row
        end
        row._id = id
        row._e = e
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y); row:Show()

        -- Solid, much darker grey row background (the panel the item name + buttons sit on).
        row.bg:SetVertexColor(0.04, 0.04, 0.05, 1)

        local icon = (GetItemIcon and e.itemId and GetItemIcon(e.itemId)) or nil
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local link, quality = nil, e.quality
        if GetItemInfo and e.itemId then
            local n, l, q = GetItemInfo(e.itemId)
            link = l; quality = quality or q
        end
        if row.iconBorder then row.iconBorder:SetQuality(quality) end
        local nm = link or e.itemLink or e.itemName or ("Item " .. tostring(e.itemId))
        local qty = tonumber(e.quantity) or 1
        if qty > 1 then nm = nm .. ("  |cffaaaaaax%d|r"):format(qty) end
        row.name:SetText(nm)

        -- Reflect the local player's choice: once a selection is made, the non-selected buttons
        -- have their TEXT greyed out (and dimmed) so it's obvious this item is already answered;
        -- the chosen button keeps its full response colour. No selection yet -> all coloured.
        local mine = self:MyChoice(id)
        for key, b in pairs(row.btns) do
            local selected = (mine == key)
            b:SetAlpha(mine == nil and 1 or (selected and 1 or 0.55))
            if b.SetLabelColor then
                if mine ~= nil and not selected then
                    b:SetLabelColor(0.45, 0.45, 0.45)                 -- greyed out: answered, not this one
                elseif b._respColor then
                    b:SetLabelColor(b._respColor[1], b._respColor[2], b._respColor[3])
                end
            end
        end
        if row.passBtn then
            row.passBtn:Show()
            if row.passBtn.SetLabelColor then row.passBtn:SetLabelColor(PASS_COLOR[1], PASS_COLOR[2], PASS_COLOR[3]) end
            row.passBtn:SetAlpha(mine and 1 or 0.35)
            if mine then row.passBtn:Enable() else row.passBtn:Disable() end
            row.passBtn:SetScript("OnClick", function()
                if not Popup:MyChoice(row._id) then return end
                local me = (UnitName and UnitName("player")) or "me"
                if store.ClearResponse then store:ClearResponse(row._id, me, now()) end
                local s = Sync()
                if s and s.BroadcastClearResponse then s:BroadcastClearResponse(row._id) end
                Popup:Refresh()
            end)
        end
        y = y - ROW_STEP
    end

    -- Content holds ALL rows (so the scrollbar can reach them); the WINDOW caps at the first
    -- MAX_VISIBLE_ROWS so it never grows past 12 items tall — extra items scroll.
    local n = #ids
    local fullH = n * ROW_STEP
    content:SetHeight(math.max(1, fullH))
    if content.SetWidth then content:SetWidth((f.scroll and f.scroll:GetWidth()) or ROW_W) end
    local visibleRows = math.min(n, MAX_VISIBLE_ROWS)
    -- Window chrome above the scroll area is 28px (title), 8px bottom pad.
    f:SetHeight(math.max(48, 28 + visibleRows * ROW_STEP + 8))
    if f.bar and f.bar.Update then
        f.bar:Update()
        if n <= MAX_VISIBLE_ROWS then f.bar:Hide() end
    end
    if n == 0 then
        self._hiddenByFilter = activeCount > 0
        self:Hide()
    else
        self._hiddenByFilter = nil
    end
end

function Popup:Show()
    if not self:BuildFrame() then return end
    self.frame:Show()
    if self.frame.Raise then self.frame:Raise() end   -- bring to front each time it opens
    self:Refresh()
end

function Popup:Hide()
    if self.frame then self.frame:Hide() end
end

-- A loot entry was created or updated. If the popup is open, append/refresh it live. If it is
-- hidden, only open it for users who opted into local "open on added loot" behaviour.
function Popup:OnEntryAdded(id)
    if not id then return end
    local store = Store(); if not store then return end
    local e = store:Entries()[id]
    if not e then return end

    local isOpen = self.frame and self.frame:IsShown()
    self.active = self.active or {}
    if isOpen and self.active[id] then
        self:Refresh()
        return
    end

    if store.IsFullyAwarded and store:IsFullyAwarded(id) then return end
    if e.award ~= nil and not store.IsFullyAwarded then return end
    if isOpen then
        if not self:IsItemRelevant(e.itemId) then return end
    else
        if not self:ShouldAutoOpenOnEntryAdded() or not self:ShouldShow(e.itemId) then return end
    end

    self.active[id] = true
    if isOpen then self:Refresh() else self:Show() end
end

-- An entry was removed elsewhere (officer Remove/Clear). Drop it from the active set and
-- refresh; if nothing's left, the window hides itself (Refresh does this when #ids == 0).
function Popup:OnRemoved(id)
    if not id then return end
    if self.active then self.active[id] = nil end
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

-- The local player left the group (or the group dissolved): the loot list no longer applies
-- to them, so clear the popup's active items and hide the window.
function Popup:OnLeftGroup()
    self.active = {}
    self:Hide()
end

-- ---------------------------------------------------------------------------
-- Lifecycle: combat-close + self-open slash.
-- ---------------------------------------------------------------------------
function Popup:OnEnable()
    if self._enabled then return end
    self._enabled = true

    local e = ns:GetModule("Events")
    if e and e.On then
        e:On("PLAYER_REGEN_DISABLED", function()
            local lw = lootSettings().lootWindow or {}
            if lw.closeOnCombat ~= false then self:Hide() end
        end, "LootDistPopup")

        -- Left the group entirely -> the loot list no longer applies; clear + hide the popup.
        e:On("GROUP_ROSTER_UPDATE", function()
            local inGroup = (IsInGroup and IsInGroup()) or (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0)
            if not inGroup then self:OnLeftGroup() end
        end, "LootDistPopup")
    end

    local slash = ns:GetModule("Slash")
    if slash and slash.Register then
        slash:Register("loot", function() self:ShowCurrent() end)
    end
end

ns.LootDistPopup = Popup
return Popup
