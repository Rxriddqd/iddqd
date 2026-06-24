local ADDON, ns = ...

local Panel = ns:NewModule("CouncilPanel")

local function provider()
    return ns:GetModule("Council")
end

local function short(value, maxLen)
    value = tostring(value or "")
    maxLen = maxLen or 18
    if #value <= maxLen then return value end
    return value:sub(1, maxLen - 1) .. "."
end

local function classColorCode(classFile)
    classFile = tostring(classFile or ""):upper()
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not color then return nil end
    return ("|cff%02x%02x%02x"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

local function playerText(row)
    local name = short(row.character, 16)
    local color = classColorCode(row.class)
    return color and (color .. name .. "|r") or name
end

local function itemText(row)
    return short(row.lootItemName or row.itemName or ("Item " .. tostring(row.lootItemId or row.itemId or "?")), 30)
end

local function qualityColor(q)
    q = tonumber(q)
    if q == 5 then return 1.00, 0.50, 0.00 end
    if q == 4 then return 0.64, 0.21, 0.93 end
    if q == 3 then return 0.00, 0.44, 0.87 end
    if q == 2 then return 0.12, 1.00, 0.00 end
    if q == 1 then return 1.00, 1.00, 1.00 end
    return 0.62, 0.62, 0.62
end

local function itemInfo(row)
    local query = row and (row.lootItemId or row.itemLink or row.itemId)
    local fallbackLink = row and (row.lootItemName or row.itemName or row.itemLink)
    local fallbackQuality = row and (row.lootItemQuality or row.itemQuality)
    local fallbackIcon = row and (row.lootItemIcon or row.itemIcon)
    if not query or not GetItemInfo then return fallbackLink, fallbackQuality, fallbackIcon end
    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(query)
    if not name and row and (row.lootItemId or row.itemId) and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, row.lootItemId or row.itemId)
    end
    return link or fallbackLink, quality or fallbackQuality, icon or fallbackIcon
end

local function slotText(value)
    value = tostring(value or "-")
    value = value:gsub("_", " "):gsub("%s+", " ")
    local clean = string.lower(value):gsub("%s+", "")
    if clean:match("^ring%d*$") then return "Ring" end
    if clean:match("^trinket%d*$") then return "Trinket" end
    return (value:gsub("(%a)([%w']*)", function(a, rest) return string.upper(a) .. string.lower(rest) end))
end

local function sourceText(row)
    local boss = row.bossName and row.bossName ~= "" and row.bossName or nil
    local instance = row.sourceInstance and row.sourceInstance ~= "" and row.sourceInstance or nil
    if boss and instance then return short(instance, 16) .. " |cff646a76" .. short(boss, 14) .. "|r" end
    return short(boss or instance or "-", 30)
end

local function statusText(value)
    value = tostring(value or "assigned")
    local lower = string.lower(value)
    local color = lower == "obtained" and "5fbf8a" or lower == "deleted" and "d4756b" or "caa65a"
    return "|cff" .. color .. short(value, 12) .. "|r"
end

local RAID_ORDER = {
    ["karazhan"] = 10,
    ["gruul's lair"] = 20,
    ["magtheridon's lair"] = 30,
    ["serpentshrine cavern"] = 40,
    ["tempest keep"] = 50,
    ["hyjal summit"] = 60,
    ["black temple"] = 70,
    ["sunwell plateau"] = 80,
}

local BOSS_ORDER = {
    ["serpentshrine cavern"] = {
        trash = 0,
        hydross = 10,
        ["lurker below"] = 20,
        morogrim = 30,
        karathress = 40,
        leotheras = 50,
        ["lady vashj"] = 60,
    },
    ["tempest keep"] = {
        trash = 0,
        ["al'ar"] = 10,
        ["void reaver"] = 20,
        solarian = 30,
        ["kael'thas"] = 40,
        ["kael'thas sunstrider"] = 40,
    },
    ["karazhan"] = {
        trash = 0,
        attumen = 10,
        moroes = 20,
        maiden = 30,
        opera = 40,
        curator = 50,
        illhoof = 60,
        aran = 70,
        netherspite = 80,
        chess = 90,
        malchezaar = 100,
    },
    ["gruul's lair"] = {
        trash = 0,
        maulgar = 10,
        gruul = 20,
    },
    ["magtheridon's lair"] = {
        trash = 0,
        magtheridon = 10,
    },
    ["hyjal summit"] = {
        trash = 0,
        winterchill = 10,
        anetheron = 20,
        ["kaz'rogal"] = 30,
        azgalor = 40,
        archimonde = 50,
    },
    ["black temple"] = {
        trash = 0,
        ["naj'entus"] = 10,
        supremus = 20,
        shade = 30,
        gorefiend = 40,
        gurtogg = 50,
        reliquary = 60,
        shahraz = 70,
        council = 80,
        illidan = 90,
    },
    ["sunwell plateau"] = {
        trash = 0,
        kalecgos = 10,
        brutallus = 20,
        felmyst = 30,
        twins = 40,
        ["eredar twins"] = 40,
        muru = 50,
        ["m'uru"] = 50,
        kiljaeden = 60,
        ["kil'jaeden"] = 60,
    },
}

local function norm(value)
    return string.lower(tostring(value or "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function bossKey(value)
    local b = norm(value)
    if b == "" then return "" end
    if b:find("trash", 1, true) then return "trash" end
    if b:find("hydross", 1, true) then return "hydross" end
    if b:find("lurker", 1, true) then return "lurker below" end
    if b:find("morogrim", 1, true) then return "morogrim" end
    if b:find("karathress", 1, true) then return "karathress" end
    if b:find("leotheras", 1, true) then return "leotheras" end
    if b:find("vashj", 1, true) then return "lady vashj" end
    if b:find("void reaver", 1, true) then return "void reaver" end
    if b:find("kael", 1, true) then return "kael'thas" end
    if b:find("illidari council", 1, true) then return "council" end
    if b:find("illidan", 1, true) then return "illidan" end
    return b
end

local function raidRank(row)
    return RAID_ORDER[norm(row and row.sourceInstance)] or 999
end

local function bossRank(row)
    local raid = norm(row and row.sourceInstance)
    local boss = bossKey(row and row.bossName)
    local order = BOSS_ORDER[raid]
    if order and order[boss] ~= nil then return order[boss] end
    if boss == "trash" then return 0 end
    return 500
end

local function groupLabel(row)
    local raid = row and row.sourceInstance and row.sourceInstance ~= "" and row.sourceInstance or "Unknown Raid"
    local boss = row and row.bossName and row.bossName ~= "" and row.bossName or "Unknown Source"
    return raid .. " - " .. slotText(boss)
end

local function sortedAssignments(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = row end
    table.sort(out, function(a, b)
        local ar, br = raidRank(a), raidRank(b)
        if ar ~= br then return ar < br end
        local ai, bi = norm(a.sourceInstance), norm(b.sourceInstance)
        if ar == 999 and ai ~= bi then return ai < bi end
        local ab, bb = bossRank(a), bossRank(b)
        if ab ~= bb then return ab < bb end
        local ak, bk = bossKey(a.bossName), bossKey(b.bossName)
        if ak ~= bk then return ak < bk end
        local aslot, bslot = norm(a.slot), norm(b.slot)
        if aslot ~= bslot then return aslot < bslot end
        return norm(a.character) < norm(b.character)
    end)
    return out
end

local function setColumns(row, specs, Theme)
    row.text:SetText("")
    row.cols = row.cols or {}
    for i, spec in ipairs(specs or {}) do
        local col = row.cols[i]
        if not col then
            col = row:CreateFontString(nil, "OVERLAY")
            Theme:Text(col, "caption", "dim")
            col:SetWordWrap(false)
            if col.SetNonSpaceWrap then col:SetNonSpaceWrap(false) end
            row.cols[i] = col
        end
        Theme:Text(col, "caption", "dim")
        col:ClearAllPoints()
        col:SetPoint("LEFT", row, "LEFT", spec.x or 8, 0)
        col:SetWidth(spec.w or 80)
        col:SetJustifyH(spec.justify or "LEFT")
        col:SetText(spec.text or "")
        col:Show()
    end
    for i = #(specs or {}) + 1, #(row.cols or {}) do row.cols[i]:Hide() end
end

local function hideRows(rows)
    for _, row in ipairs(rows or {}) do row:Hide() end
end

local function modalBackdrop(parent)
    local blocker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    blocker:SetFrameStrata("DIALOG")
    blocker:SetFrameLevel(900)
    blocker:SetAllPoints(UIParent)
    blocker:EnableMouse(true)
    blocker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    blocker:SetBackdropColor(0, 0, 0, 0.50)
    blocker.owner = parent
    return blocker
end

local function makeImportModal(owner, onImport)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local Council = provider()

    local blocker = modalBackdrop(owner)
    if blocker.EnableKeyboard then blocker:EnableKeyboard(true) end
    local modal = W:Card(blocker, "float", false)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(910)
    modal:SetSize(420, 202)
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 24)
    modal:EnableMouse(true)

    local title = W:Title(modal, "Import Loot Assignments")
    title:SetPoint("TOPLEFT", 18, -16)

    local close = W:Button(modal, "Close", 58, 22)
    close:SetPoint("TOPRIGHT", -14, -14)

    local hint = modal:CreateFontString(nil, "OVERLAY")
    Theme:Text(hint, "caption", "dim")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", -18, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Paste the website export string into the box below.")

    local target = W:Card(modal, "base", true)
    target:SetPoint("TOPLEFT", 18, -76)
    target:SetPoint("RIGHT", -18, 0)
    target:SetHeight(60)
    target:EnableMouse(true)

    local status = target:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "body", "dim")
    status:SetPoint("CENTER")
    status:SetText("Paste Import String")

    local edit = CreateFrame("EditBox", nil, target)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(Theme.font, 12, "")
    edit:SetTextColor(0, 0, 0, 0.01)
    edit:SetTextInsets(0, 0, 0, 0)
    edit:SetPoint("TOPLEFT", 6, -6)
    edit:SetPoint("BOTTOMRIGHT", -6, 6)
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

    local decodedText
    local function closeModal()
        blocker:Hide()
        blocker:SetParent(nil)
    end
    close:SetScript("OnClick", closeModal)
    cancel:SetScript("OnClick", closeModal)
    blocker:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then closeModal() end end)

    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        decodedText = nil
        if text == "" then
            status:SetText("Paste Import String")
            status:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            import:Disable()
            return
        end
        local payload = Council:DecodeText(text)
        if payload then
            decodedText = text
            status:SetText("Valid Import.")
            status:SetTextColor(Theme.color.success[1], Theme.color.success[2], Theme.color.success[3], 1)
            import:Enable()
        else
            status:SetText("Invalid Import String")
            status:SetTextColor(Theme.color.danger[1], Theme.color.danger[2], Theme.color.danger[3], 1)
            import:Disable()
        end
    end)

    import:SetScript("OnClick", function()
        if not decodedText then return end
        onImport(decodedText)
        closeModal()
    end)

    blocker:Show()
    modal:Show()
    edit:SetFocus()
    return blocker
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local Council = provider()
    local f = W:Card(parent, "base", true)

    local eyebrow = W:Eyebrow(f, "Loot Council")
    eyebrow:SetPoint("TOPLEFT", 12, -12)
    local title = W:Title(f, "Assignments")
    title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -3)

    local subtitle = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(subtitle, "caption", "dim")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Import website assignments, share them to guild members, and annotate loot in-game.")

    local actions = W:Card(f, "raised", true)
    actions:SetPoint("TOPRIGHT", -12, -14)
    actions:SetSize(438, 62)

    local importBtn = W:Button(actions, "Import + Share", 118, 24)
    importBtn:SetTone("blue")
    importBtn:SetPoint("TOPLEFT", 10, -8)
    local shareBtn = W:Button(actions, "Share", 72, 24)
    shareBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    local requestBtn = W:Button(actions, "Request Sync", 106, 24)
    requestBtn:SetPoint("LEFT", shareBtn, "RIGHT", 8, 0)
    local clearBtn = W:Button(actions, "Clear", 72, 24)
    clearBtn:SetPoint("LEFT", requestBtn, "RIGHT", 8, 0)

    local activeMeta = actions:CreateFontString(nil, "OVERLAY")
    Theme:Text(activeMeta, "caption", "dim")
    activeMeta:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -5)
    activeMeta:SetPoint("RIGHT", -10, 0)
    activeMeta:SetJustifyH("LEFT")
    activeMeta:SetWordWrap(false)
    f.activeMeta = activeMeta

    local status = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "caption", "dim")
    status:SetPoint("TOPLEFT", 12, -72)
    status:SetPoint("RIGHT", -12, 0)
    status:SetJustifyH("LEFT")
    f.status = status

    local progress = CreateFrame("Frame", nil, f)
    progress:SetPoint("TOPLEFT", 12, -89)
    progress:SetPoint("TOPRIGHT", -12, -89)
    progress:SetHeight(5)
    progress.bg = progress:CreateTexture(nil, "BACKGROUND")
    progress.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    progress.bg:SetAllPoints(progress)
    progress.bg:SetVertexColor(1, 1, 1, 0.045)
    progress.fill = progress:CreateTexture(nil, "ARTWORK")
    progress.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    progress.fill:SetPoint("LEFT", progress, "LEFT", 0, 0)
    progress.fill:SetHeight(5)
    progress.fill:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.95)
    progress:Hide()
    f.progress = progress

    local mineHost = W:Card(f, "overlay", true)
    mineHost:SetPoint("TOPLEFT", 12, -104)
    mineHost:SetPoint("TOPRIGHT", -12, -104)
    mineHost:SetHeight(230)
    f.mineRows = {}

    local mineTitle = W:Eyebrow(mineHost, "Assigned To Me")
    mineTitle:SetPoint("TOPLEFT", 10, -10)

    local mineCount = mineHost:CreateFontString(nil, "OVERLAY")
    Theme:Text(mineCount, "caption", "dim")
    mineCount:SetPoint("TOPRIGHT", -14, -10)
    mineCount:SetJustifyH("RIGHT")
    f.mineCount = mineCount

    local mineHeader = W:ListRow(mineHost)
    mineHeader:SetPoint("TOPLEFT", 10, -30)
    mineHeader:SetPoint("TOPRIGHT", -14, -30)
    mineHeader:SetHeight(24)
    mineHeader:SetRowVisual(1, false, "group")
    mineHeader.text = mineHeader:CreateFontString(nil, "OVERLAY")
    Theme:Text(mineHeader.text, "caption", "dim")
    mineHeader.text:SetPoint("LEFT", 8, 0)
    mineHeader.text:SetPoint("RIGHT", -8, 0)
    mineHeader.text:SetWordWrap(false)
    f.mineHeader = mineHeader

    local mineScroll, mineContent = W:ScrollHost(mineHost)
    mineScroll:SetPoint("TOPLEFT", 10, -56)
    mineScroll:SetPoint("BOTTOMRIGHT", -14, 10)
    f.mineScroll = mineScroll
    f.mineContent = mineContent
    f.mineScrollBar = W:ScrollBar(mineScroll, mineContent)

    local listHost = W:Card(f, "overlay", true)
    listHost:SetPoint("TOPLEFT", 12, -346)
    listHost:SetPoint("BOTTOMRIGHT", -12, 12)
    f.rows = {}

    local listTitle = W:Eyebrow(listHost, "Guild Assignments")
    listTitle:SetPoint("TOPLEFT", 10, -10)

    local listHeader = W:ListRow(listHost)
    listHeader:SetPoint("TOPLEFT", 10, -30)
    listHeader:SetPoint("TOPRIGHT", -14, -30)
    listHeader:SetHeight(24)
    listHeader:SetRowVisual(1, false, "group")
    listHeader.text = listHeader:CreateFontString(nil, "OVERLAY")
    Theme:Text(listHeader.text, "caption", "dim")
    listHeader.text:SetPoint("LEFT", 8, 0)
    listHeader.text:SetPoint("RIGHT", -8, 0)
    listHeader.text:SetWordWrap(false)
    f.listHeader = listHeader

    local scroll, content = W:ScrollHost(listHost)
    scroll:SetPoint("TOPLEFT", 10, -56)
    scroll:SetPoint("BOTTOMRIGHT", -14, 10)
    f.scroll = scroll
    f.content = content
    f.scrollBar = W:ScrollBar(scroll, content)

    local function ensureRow(rows, host, i)
        local row = rows[i]
        if row then
            row:SetRowVisual(i, false)
            return row
        end
        row = W:ListRow(host)
        row:SetHeight(24)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:Hide()
        row.iconBorder = W:IconBorder(row.icon)
        row.specIcon = row:CreateTexture(nil, "ARTWORK")
        row.specIcon:SetSize(16, 16)
        row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.specIcon:Hide()
        row.text = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.text, "caption", "dim")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetWordWrap(false)
        rows[i] = row
        return row
    end

    local function renderTableHeader(header, width, showPlayer)
        if not header then return end
        local playerX = showPlayer and 30 or nil
        local slotX = showPlayer and 146 or 8
        local itemTextX = showPlayer and 260 or 122
        local sourceX = math.max(showPlayer and 490 or 352, width - 250)
        local statusX = math.max(showPlayer and 650 or 520, width - 92)
        header:SetRowVisual(1, false, "group")
        if showPlayer then
            setColumns(header, {
                { x = playerX, w = 108, text = "|cff646a76PLAYER|r" },
                { x = slotX, w = 82, text = "|cff646a76SLOT|r" },
                { x = itemTextX, w = math.max(190, sourceX - itemTextX - 10), text = "|cff646a76ITEM|r" },
                { x = sourceX, w = math.max(130, statusX - sourceX - 10), text = "|cff646a76SOURCE|r" },
                { x = statusX, w = 84, text = "|cff646a76STATUS|r" },
            }, Theme)
        else
            setColumns(header, {
                { x = slotX, w = 82, text = "|cff646a76SLOT|r" },
                { x = itemTextX, w = math.max(190, sourceX - itemTextX - 10), text = "|cff646a76ITEM|r" },
                { x = sourceX, w = math.max(130, statusX - sourceX - 10), text = "|cff646a76SOURCE|r" },
                { x = statusX, w = 84, text = "|cff646a76STATUS|r" },
            }, Theme)
        end
    end

    local function renderTable(rows, scrollFrame, contentFrame, headerFrame, assignments, emptyText, showPlayer)
        contentFrame:SetWidth(math.max(1, (scrollFrame:GetWidth() or 680) - 4))
        hideRows(rows)
        assignments = sortedAssignments(assignments)
        local width = contentFrame:GetWidth() or 760
        renderTableHeader(headerFrame, width, showPlayer)
        local specIconX = showPlayer and 8 or nil
        local playerX = showPlayer and 30 or nil
        local slotX = showPlayer and 146 or 8
        local itemIconX = showPlayer and 236 or 98
        local itemTextX = showPlayer and 260 or 122
        local sourceX = math.max(showPlayer and 490 or 352, width - 250)
        local statusX = math.max(showPlayer and 650 or 520, width - 92)
        local rowIndex = 1
        local y = 0

        if #assignments == 0 then
            local row = ensureRow(rows, contentFrame, rowIndex)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", -2, 0)
            row:SetHeight(24)
            row.icon:Hide()
            if row.iconBorder then row.iconBorder:Hide() end
            if row.specIcon then row.specIcon:Hide() end
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            setColumns(row, { { x = 8, w = width - 16, text = emptyText or "No assignments." } }, Theme)
            row:Show()
            contentFrame:SetHeight(math.max(scrollFrame:GetHeight() or 1, 52))
            return
        end

        local lastGroup
        for _, assignment in ipairs(assignments) do
            local group = groupLabel(assignment)
            if group ~= lastGroup then
                local groupRow = ensureRow(rows, contentFrame, rowIndex)
                groupRow:SetPoint("TOPLEFT", 0, y)
                groupRow:SetPoint("RIGHT", -2, 0)
                groupRow:SetHeight(22)
                groupRow:SetRowVisual(rowIndex, false, "group")
                groupRow.icon:Hide()
                if groupRow.iconBorder then groupRow.iconBorder:Hide() end
                if groupRow.specIcon then groupRow.specIcon:Hide() end
                groupRow:SetScript("OnEnter", nil)
                groupRow:SetScript("OnLeave", nil)
                setColumns(groupRow, { { x = 8, w = width - 16, text = "|cffcaa65a" .. group .. "|r" } }, Theme)
                groupRow:Show()
                y = y - 23
                rowIndex = rowIndex + 1
                lastGroup = group
            end

            local row = ensureRow(rows, contentFrame, rowIndex)
            local itemLink, quality, icon = itemInfo(assignment)
            local r, g, b = qualityColor(quality)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", -2, 0)
            row:SetHeight(24)
            row:SetRowVisual(rowIndex, false)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", itemIconX, 0)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:Show()
            if row.iconBorder then row.iconBorder:SetQuality(quality) end
            if row.specIcon then
                row.specIcon:ClearAllPoints()
                row.specIcon:SetPoint("LEFT", specIconX or 8, 0)
                if showPlayer and ns.classSpec and ns.classSpec.hasSpec and ns.classSpec.hasSpec(assignment.class, assignment.spec) then
                    row.specIcon:SetTexture(ns.classSpec.specIcon(assignment.class, assignment.spec))
                    row.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.specIcon:Show()
                elseif showPlayer and ns.classSpec and ns.classSpec.classIcon then
                    local path, l, r2, t, b2 = ns.classSpec.classIcon(assignment.class)
                    row.specIcon:SetTexture(path)
                    row.specIcon:SetTexCoord(l, r2, t, b2)
                    row.specIcon:Show()
                else
                    row.specIcon:Hide()
                end
            end
            if showPlayer then
                setColumns(row, {
                    { x = playerX, w = 108, text = playerText(assignment) },
                    { x = slotX, w = 82, text = short(slotText(assignment.slot), 12) },
                    { x = itemTextX, w = math.max(190, sourceX - itemTextX - 10), text = itemLink or itemText(assignment) },
                    { x = sourceX, w = math.max(130, statusX - sourceX - 10), text = sourceText(assignment) },
                    { x = statusX, w = 84, text = statusText(assignment.status) },
                }, Theme)
                if row.cols and row.cols[3] then row.cols[3]:SetTextColor(r, g, b, 1) end
            else
                setColumns(row, {
                    { x = slotX, w = 82, text = short(slotText(assignment.slot), 12) },
                    { x = itemTextX, w = math.max(190, sourceX - itemTextX - 10), text = itemLink or itemText(assignment) },
                    { x = sourceX, w = math.max(130, statusX - sourceX - 10), text = sourceText(assignment) },
                    { x = statusX, w = 84, text = statusText(assignment.status) },
                }, Theme)
                if row.cols and row.cols[2] then row.cols[2]:SetTextColor(r, g, b, 1) end
            end
            row:SetScript("OnEnter", function(self)
                self:SetRowHover(true)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- Prefer the real in-game item tooltip (stats, ilvl, BoP, etc.) by feeding a
                -- hyperlink. itemInfo() returns a full link when GetItemInfo is cached; fall
                -- back to "item:<id>" when only the id is known. If neither resolves, drop to a
                -- plain name header so the row still shows *something*.
                local hyperlink = itemLink
                if not hyperlink then
                    local id = assignment.lootItemId or assignment.itemId
                    if id then hyperlink = "item:" .. tostring(id) end
                end
                local shownItem = false
                if hyperlink then
                    local ok = pcall(function() GameTooltip:SetHyperlink(hyperlink) end)
                    shownItem = ok
                end
                if not shownItem then
                    GameTooltip:SetText(assignment.lootItemName or assignment.itemName or ("Item " .. tostring(assignment.lootItemId or assignment.itemId)), 1, 1, 1)
                end
                -- Assignment metadata appended below the item tooltip.
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(("Assigned to %s"):format(assignment.character or "?"), 0.75, 0.75, 0.75)
                if assignment.slot then GameTooltip:AddLine(("Slot: %s"):format(slotText(assignment.slot)), 0.75, 0.75, 0.75) end
                if assignment.bossName or assignment.sourceInstance then GameTooltip:AddLine(sourceText(assignment), 0.75, 0.75, 0.75) end
                if assignment.originalItemName then GameTooltip:AddLine(("Tier item: %s"):format(assignment.originalItemName), 0.75, 0.75, 0.75, true) end
                if assignment.note then GameTooltip:AddLine(assignment.note, 0.75, 0.75, 0.75, true) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self:SetRowHover(false)
                GameTooltip:Hide()
            end)
            row:Show()
            y = y - 26
            rowIndex = rowIndex + 1
        end
        contentFrame:SetHeight(math.max(scrollFrame:GetHeight() or 1, -y + 2))
    end

    local function setStatusTone(text, tone)
        local color = Theme.color[tone or "dim"] or Theme.color.dim
        status:SetText(text or "")
        status:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end

    local function setButtonEnabled(button, enabled)
        if not button then return end
        if enabled then
            button:Enable()
        else
            button:Disable()
        end
    end

    local function updateActionButtons()
        local receiving = Council:HasIncomingSync()
        local pending = Council:RequestPending()
        setButtonEnabled(importBtn, not receiving)
        setButtonEnabled(shareBtn, not receiving)
        setButtonEnabled(clearBtn, not receiving)
        setButtonEnabled(requestBtn, not receiving and not pending)
    end

    function f:UpdateProgress()
        local incoming = Council:IncomingProgress()
        if incoming then
            local pct = math.max(0, math.min(1, incoming.percent or 0))
            local width = math.max(1, self.progress:GetWidth() or 1)
            self.progress.fill:SetWidth(math.max(1, width * pct))
            self.progress:Show()
            setStatusTone(("Receiving council assignments from %s... %d/%d chunks (%d%%)"):format(
                incoming.sender or "unknown",
                incoming.received or 0,
                incoming.total or 0,
                math.floor(pct * 100 + 0.5)
            ), "gold")
        else
            self.progress:Hide()
            local notice, tone = Council:PanelNotice(20)
            if notice then
                setStatusTone(notice, tone or "dim")
            elseif Council:RequestPending() then
                setStatusTone("Council sync requested. Waiting for a guild member with newer data...", "gold")
            end
        end
        updateActionButtons()
    end

    function f:Refresh()
        local active = Council:Active()
        content:SetWidth(math.max(1, (scroll:GetWidth() or 680) - 4))
        mineContent:SetWidth(math.max(1, (mineScroll:GetWidth() or 680) - 4))
        hideRows(self.rows)
        hideRows(self.mineRows)
        if not active then
            setStatusTone("No assignments imported yet.", "dim")
            self.activeMeta:SetText("No active import. Use Import + Share to load website assignments.")
            self.mineCount:SetText("Assigned to you: 0")
            renderTable(self.mineRows, mineScroll, mineContent, self.mineHeader, {}, "No assignments for your character.", true)
            renderTable(self.rows, scroll, content, self.listHeader, {}, "No active council import.", true)
            if self.mineScrollBar then self.mineScrollBar:Update() end
            if self.scrollBar then self.scrollBar:Update() end
            self:UpdateProgress()
            return
        end

        local assignments = active.assignments or {}
        local mineRows = Council:AssignmentsFor(UnitName("player"))
        setStatusTone(("Loaded %d council assignment%s. Tooltips and loot rolls now show assignment info."):format(#assignments, #assignments == 1 and "" or "s"), "dim")
        self.activeMeta:SetText(("Active import: %s  |  |cff646a76%s  |  imported by %s|r"):format(
            active.title or "Loot assignments",
            active.raid or active.guild or "No raid context",
            active.importedBy or "unknown"))
        self.mineCount:SetText(("Assigned to you: %d"):format(#mineRows))
        renderTable(self.mineRows, mineScroll, mineContent, self.mineHeader, mineRows, "No assignments for your character.", true)
        renderTable(self.rows, scroll, content, self.listHeader, assignments, "No guild assignments.", true)
        if self.mineScrollBar then self.mineScrollBar:Update() end
        if self.scrollBar then self.scrollBar:Update() end
        self:UpdateProgress()
    end

    importBtn:SetScript("OnClick", function()
        if f.importModal and f.importModal:IsShown() then f.importModal:Hide() end
        f.importModal = makeImportModal(f, function(text)
            local imported, err = Council:ImportText(text, { share = true })
            if not imported then
                status:SetText("|cffd4756b" .. tostring(err or "Import failed.") .. "|r")
                return
            end
            Council:SetPanelNotice(("Imported and shared %d assignment%s."):format(#(imported.assignments or {}), #(imported.assignments or {}) == 1 and "" or "s"), "success")
            f:Refresh()
        end)
    end)

    shareBtn:SetScript("OnClick", function()
        local ok, err = Council:ShareActive("GUILD")
        if not ok then Council:SetPanelNotice("|cffd4756b" .. tostring(err or "Share failed.") .. "|r", "danger") end
        f:Refresh()
    end)

    requestBtn:SetScript("OnClick", function()
        Council:RequestSync()
    end)

    clearBtn:SetScript("OnClick", function()
        W:Confirm("IDDQD_COUNCIL_CLEAR", "Clear the active council assignments from this addon?", function()
            Council:ClearActive()
            Council:SetPanelNotice("Active council assignments cleared.", "warning")
            f:Refresh()
        end)
    end)

    Council:RegisterPanel(f)
    f:Refresh()
    return f
end
