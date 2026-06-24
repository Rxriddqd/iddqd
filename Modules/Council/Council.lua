local ADDON, ns = ...

local Council = ns:NewModule("Council")

local b64url = ns.raid_assignments_b64url
local json = ns.raid_assignments_json

local TEXT_PREFIX = "!iddqd-council!"
local LEGACY_TEXT_PREFIX = "!iddqd-lc!"
local OLD_IDDQD_TEXT_PREFIX = "!iddqd!"
local COMM_PREFIX = "IDDQDCOUNCIL2"
local PROTOCOL_VERSION = 1
local CHUNK_SIZE = 180
local CHUNK_DELAY = 0.10
local SHARE_STREAM_GAP = 0.50
local REQUEST_COOLDOWN = 12
local REQUEST_PENDING_TTL = 45
local RESPONSE_COOLDOWN = 30
local PROGRESS_REFRESH_INTERVAL = 0.25
local MAX_HISTORY = 20
local POPUP_DURATION = 8
local AUTO_NEED_RETRIES = 8
local AUTO_NEED_RETRY_DELAY = 0.25
local INCOMING_TTL = 120

local OP = {
    SYNC = "SYNC",
    CHUNK = "CHUNK",
    DONE = "DONE",
    REQUEST = "REQ",
}

local function now()
    return (time and time()) or os.time()
end

local function preciseNow()
    return (GetTime and GetTime()) or now()
end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function shortPlayerName(value)
    local players = Players()
    if players and players.ShortName then return players:ShortName(value) end
    value = tostring(value or "")
    return value:match("^([^%-]+)") or value
end

local function playerName()
    local name = UnitName and UnitName("player")
    return name and shortPlayerName(name) or "Unknown"
end

local function samePlayer(a, b)
    local players = Players()
    if players and players.Same then return players:Same(a, b) end
    return lower(shortPlayerName(a)) == lower(shortPlayerName(b))
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function numberOrNil(value)
    if value == nil or value == "" then return nil end
    return tonumber(value)
end

local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    return numberOrNil(link:match("item:(%d+)"))
end

local function trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function short(value, maxLen)
    value = tostring(value or "")
    maxLen = maxLen or 32
    if #value <= maxLen then return value end
    return value:sub(1, maxLen - 1) .. "."
end

local function first(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil and value ~= "" then return value end
    end
end

local function decodeBase64(data)
    if type(data) ~= "string" then return nil end
    data = data:gsub("%s+", "")
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #chars do lookup[chars:sub(i, i)] = i - 1 end
    local out, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local ch = data:sub(i, i)
        if ch == "=" then break end
        local value = lookup[ch]
        if value == nil then return nil end
        buffer = buffer * 64 + value
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(buffer / (2 ^ bits))
            out[#out + 1] = string.char(byte)
            buffer = buffer - byte * (2 ^ bits)
        end
    end
    return table.concat(out)
end

local function sendAddon(prefix, message, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(prefix, message, channel, target) end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, message, channel, target)
    end
end

local function registerPrefix(prefix)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then return Comm:RegisterPrefix(prefix) end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(prefix)
    end
end

local function splitPipe(message)
    local parts = {}
    message = tostring(message or "")
    local start = 1
    while start <= #message + 1 do
        local stop = message:find("|", start, true)
        if stop then
            parts[#parts + 1] = message:sub(start, stop - 1)
            start = stop + 1
        else
            parts[#parts + 1] = message:sub(start)
            break
        end
        if #parts > 64 then break end
    end
    return parts
end

local function canSendGuild()
    return IsInGuild and IsInGuild()
end

local function activeChannel(channel)
    channel = tostring(channel or "GUILD"):upper()
    if channel == "GUILD" and canSendGuild() then return "GUILD" end
    if channel == "RAID" and IsInRaid and IsInRaid() then return "RAID" end
    if channel == "PARTY" and IsInGroup and IsInGroup() then return "PARTY" end
    if canSendGuild() then return "GUILD" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function tierLootItem(itemId)
    local resolver = ns.tierTokens and ns.tierTokens.ResolveLootItem
    if not resolver then return nil end
    return resolver(itemId)
end

local function itemNameFromId(itemId)
    if not itemId or not GetItemInfo then return nil end
    local name = GetItemInfo(itemId)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemId)
    end
    return name
end

local function qualityColor(q)
    q = tonumber(q)
    if q == 5 then return 1.00, 0.50, 0.00 end
    if q == 4 then return 0.64, 0.21, 0.93 end
    if q == 3 then return 0.00, 0.44, 0.87 end
    if q == 2 then return 0.12, 1.00, 0.00 end
    if q == 1 then return 1.00, 1.00, 1.00 end
    return 0.72, 0.76, 0.84
end

local function itemVisual(row)
    local itemId = row and (row.lootItemId or row.itemId)
    local name = row and (row.lootItemName or row.itemName)
    local quality = row and (row.lootItemQuality or row.itemQuality)
    local icon = row and (row.lootItemIcon or row.itemIcon)
    if GetItemInfo and itemId then
        local cachedName, _, cachedQuality, _, _, _, _, _, _, cachedIcon = GetItemInfo(itemId)
        name = cachedName or name
        quality = cachedQuality or quality
        icon = cachedIcon or icon
        if not cachedName and C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemId)
        end
    end
    return name or ("Item " .. tostring(itemId or "?")), quality, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function normalizeAssignment(row, index)
    if type(row) ~= "table" then return nil end
    local item = row.item
    if type(item) ~= "table" then item = row.drop or row.loot or {} end
    local character = row.character or row.player or row.assignee or row.to
    if type(character) ~= "table" then character = { name = character } end
    local itemId = numberOrNil(first(row.itemId, row.item_id, row.i, item.id, item.itemId, item.item_id))
    local characterName = first(row.characterName, row.character_name, row.playerName, row.player_name, row.assignedTo, row.assigned_to, row.n, character.name, character.nm)
    if not itemId or not characterName then return nil end

    local assignment = {
        id = tostring(first(row.id, row.assignmentId, row.assignment_id, index)),
        character = tostring(characterName),
        realm = first(row.realm, character.realm, character.rlm),
        class = first(row.class, row.c, character.class, character.cls),
        spec = first(row.spec, row.s, row.specSnapshot, row.spec_snapshot, character.spec, character.spc),
        itemId = itemId,
        itemName = tostring(first(row.itemName, row.item_name, row.t, item.name, item.itemName, item.nm, ("Item " .. itemId))),
        itemLink = first(row.itemLink, row.item_link, item.link, item.itemLink),
        slot = tostring(first(row.slot, row.l, row.gearSlot, row.gear_slot, item.slot, "Unknown")),
        sourceInstance = first(row.sourceInstance, row.source_instance, row.r, row.instance, item.instance),
        bossName = first(row.bossName, row.boss_name, row.b, row.boss, item.boss, item.source),
        status = tostring(first(row.status, "assigned")),
        note = first(row.note, row.notes),
    }
    assignment.lootItemId = numberOrNil(first(row.lootItemId, row.loot_item_id, row.tokenItemId, row.token_item_id, item.lootItemId, item.tokenItemId)) or assignment.itemId
    assignment.lootItemName = first(row.lootItemName, row.loot_item_name, row.tokenItemName, row.token_item_name, item.lootItemName, item.tokenItemName)
    assignment.itemQuality = numberOrNil(first(row.itemQuality, row.item_quality, row.q, item.quality, item.itemQuality))
    assignment.itemIcon = first(row.itemIcon, row.item_icon, item.icon, item.itemIcon)
    assignment.lootItemQuality = numberOrNil(first(row.lootItemQuality, row.loot_item_quality, row.tokenItemQuality, row.token_item_quality, item.lootItemQuality, item.tokenItemQuality)) or assignment.itemQuality
    assignment.lootItemIcon = first(row.lootItemIcon, row.loot_item_icon, row.tokenItemIcon, row.token_item_icon, item.lootItemIcon, item.tokenItemIcon) or assignment.itemIcon

    local token = tierLootItem(assignment.lootItemId)
    if token then
        if token.tokenId and token.tokenId ~= assignment.itemId then
            assignment.originalItemId = assignment.itemId
            assignment.originalItemName = assignment.itemName
        end
        assignment.lootItemId = token.tokenId
        assignment.lootItemName = assignment.lootItemName or token.name or itemNameFromId(token.tokenId) or ("Item " .. tostring(token.tokenId))
        assignment.lootItemQuality = assignment.lootItemQuality or token.quality
        assignment.lootItemIcon = assignment.lootItemIcon or token.icon
        assignment.tierToken = true
    elseif assignment.lootItemId == assignment.itemId then
        token = tierLootItem(assignment.itemId)
        if token and token.tokenId and token.tokenId ~= assignment.itemId then
            assignment.originalItemId = assignment.itemId
            assignment.originalItemName = assignment.itemName
            assignment.lootItemId = token.tokenId
            assignment.lootItemName = token.name or itemNameFromId(token.tokenId) or ("Item " .. tostring(token.tokenId))
            assignment.lootItemQuality = assignment.lootItemQuality or token.quality
            assignment.lootItemIcon = assignment.lootItemIcon or token.icon
            assignment.tierToken = true
        end
    end

    if assignment.tierToken then
        local source = ns.raidLootSources and ns.raidLootSources.byItemId and ns.raidLootSources.byItemId[assignment.lootItemId]
        if (not assignment.sourceInstance or assignment.sourceInstance == "") and source then assignment.sourceInstance = source.instance end
        if (not assignment.bossName or assignment.bossName == "") and source then assignment.bossName = source.source end
    end

    return assignment
end

local function normalizePayload(payload)
    if type(payload) ~= "table" then return nil, "The council import did not contain data." end
    local rows = payload.assignments or payload.items or payload.loot or payload.a
    if type(rows) ~= "table" then return nil, "The council import has no assignments." end

    local assignments = {}
    for i, row in ipairs(rows) do
        local assignment = normalizeAssignment(row, i)
        if assignment then assignments[#assignments + 1] = assignment end
    end
    if #assignments == 0 then return nil, "The council import has no readable assignments." end

    return {
        v = 1,
        id = tostring(first(payload.id, payload.assignmentSetId, payload.assignment_set_id, payload.setId, payload.set_id, ("council-" .. now()))),
        title = tostring(first(payload.title, payload.name, payload.rosterSetTitle, payload.roster_set_title, payload.g and (tostring(payload.g) .. " loot assignments"), "Loot assignments")),
        guild = first(payload.guild, payload.guildName, payload.guild_name, payload.g),
        raid = first(payload.raid, payload.raidName, payload.raid_name, payload.instance),
        rosterSet = first(payload.rosterSet, payload.rosterSetTitle, payload.roster_set_title),
        exportedAt = first(payload.exportedAt, payload.exported_at),
        importedAt = numberOrNil(payload.importedAt),
        assignments = assignments,
    }
end

function Council:Store()
    local DB = ns:GetModule("DB")
    local db = DB and DB.db
    if type(db) ~= "table" then return nil end
    db.council = db.council or { active = nil, history = {}, received = {}, settings = {} }
    db.council.history = db.council.history or {}
    db.council.received = db.council.received or {}
    db.council.settings = db.council.settings or {}
    if db.council.settings.autoShareOnImport == nil then db.council.settings.autoShareOnImport = true end
    if db.council.settings.announceImports == nil then db.council.settings.announceImports = true end
    return db.council
end

function Council:Settings()
    local store = self:Store()
    return store and store.settings or {}
end

function Council:EncodePayload(payload)
    if not json or not b64url then return nil end
    return TEXT_PREFIX .. b64url.encode(json.encode(payload))
end

function Council:DecodeText(text)
    text = trim(text)
    if text == "" then return nil, "Paste a website council export first." end

    local raw
    if text:sub(1, #TEXT_PREFIX) == TEXT_PREFIX then
        raw = b64url.decode(text:sub(#TEXT_PREFIX + 1))
    elseif text:sub(1, #LEGACY_TEXT_PREFIX) == LEGACY_TEXT_PREFIX then
        raw = b64url.decode(text:sub(#LEGACY_TEXT_PREFIX + 1))
    elseif text:sub(1, #OLD_IDDQD_TEXT_PREFIX) == OLD_IDDQD_TEXT_PREFIX then
        raw = decodeBase64(text:sub(#OLD_IDDQD_TEXT_PREFIX + 1))
    elseif text:sub(1, 1) == "{" or text:sub(1, 1) == "[" then
        raw = text
    else
        return nil, "This is not a council export string."
    end
    if not raw then return nil, "Could not decode the council export string." end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then return nil, "Could not read the council export JSON." end
    return normalizePayload(decoded)
end

function Council:ApplyImport(payload, source, encoded)
    local store = self:Store()
    if not store then return nil, "Database is not ready." end
    payload.importedAt = numberOrNil(payload.importedAt) or now()
    payload.appliedAt = now()
    payload.importedBy = source or playerName()
    payload.encoded = encoded or self:EncodePayload(payload)
    store.active = payload
    store.history[#store.history + 1] = {
        id = payload.id,
        title = payload.title,
        raid = payload.raid,
        count = #(payload.assignments or {}),
        importedAt = payload.importedAt,
        importedBy = payload.importedBy,
    }
    while #store.history > MAX_HISTORY do table.remove(store.history, 1) end
    self:NotifyPanels()
    self:NotifyLocalAssignments(payload)
    -- Announce manual assignments: when a loot manager applies a plan and the setting is on,
    -- post a one-line summary to the group so the raid knows assignments were updated.
    if self:LootSettings().announceAssignments == true and self:CanManageLoot() then
        local count = #((payload and payload.assignments) or {})
        if count > 0 then
            local title = payload.title or payload.raid
            self:SendToAnnounceChannel(("Council loot plan updated%s: %d assignment%s.")
                :format(title and (" (" .. title .. ")") or "", count, count == 1 and "" or "s"))
        end
    end
    return payload
end

function Council:ImportText(text, opts)
    opts = opts or {}
    local payload, err = self:DecodeText(text)
    if not payload then return nil, err end
    local imported, applyErr = self:ApplyImport(payload, playerName())
    if not imported then return nil, applyErr end
    if opts.share ~= false and self:Settings().autoShareOnImport ~= false then
        self:ShareActive("GUILD")
    end
    return imported
end

function Council:Active()
    local store = self:Store()
    return store and store.active or nil
end

function Council:Assignments()
    local active = self:Active()
    return active and active.assignments or {}
end

function Council:AssignmentsFor(name)
    local wanted = lower(name or playerName())
    local out = {}
    for _, row in ipairs(self:Assignments()) do
        if lower(row.character) == wanted then out[#out + 1] = row end
    end
    return out
end

function Council:AssignmentsForItem(itemId)
    itemId = numberOrNil(itemId)
    local out = {}
    if not itemId then return out end
    for _, row in ipairs(self:Assignments()) do
        if numberOrNil(row.lootItemId) == itemId
            or numberOrNil(row.itemId) == itemId
            or numberOrNil(row.originalItemId) == itemId then
            out[#out + 1] = row
        end
    end
    return out
end

function Council:ClearActive()
    local store = self:Store()
    if not store then return end
    store.active = nil
    self:NotifyPanels()
end

function Council:AssignmentText(row)
    if not row then return "" end
    return tostring(row.character or "?")
end

function Council:ItemText(row)
    if not row then return "Unknown item" end
    return row.lootItemName or row.itemLink or row.itemName or ("Item " .. tostring(row.lootItemId or row.itemId or "?"))
end

function Council:FormatAssignmentsForItem(itemId, maxRows)
    local rows = self:AssignmentsForItem(itemId)
    local lines = {}
    maxRows = maxRows or 5
    for i, row in ipairs(rows) do
        if i > maxRows then
            lines[#lines + 1] = ("+ %d more"):format(#rows - maxRows)
            break
        end
        lines[#lines + 1] = self:AssignmentText(row)
    end
    return lines, rows
end

function Council:CurrentPlayerAssigned(rows)
    local me = lower(playerName())
    for _, row in ipairs(rows or {}) do
        if lower(row.character) == me then return true end
    end
    return false
end

-- Is the given itemId assigned to the local player (per council assignments)?
-- (Kept: used by the loot-distribution popup's settings gate.)
function Council:CurrentPlayerAssignedItem(itemId)
    return self:CurrentPlayerAssigned(self:AssignmentsForItem(itemId))
end

function Council:SettingsNotification()
    local DB = ns:GetModule("DB")
    local settings = DB and DB.db and DB.db.settings or {}
    return settings.notificationSettings or {}
end

function Council:LootSettings()
    local DB = ns:GetModule("DB")
    local settings = DB and DB.db and DB.db.settings or {}
    settings.lootSettings = settings.lootSettings or {}
    return settings.lootSettings
end

function Council:ShowAssignmentPopup(rows)
    if not rows or #rows == 0 then return end
    local notification = self:SettingsNotification()
    if notification.showLootPopup == false then return end

    local Theme = ns:GetModule("Theme")
    local W = ns:GetModule("Widgets")
    if not Theme or not W then return end

    local f = self.assignmentPopup
    if not f then
        f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetSize(430, 212)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        Theme:Surface(f, "float")
        W:CardEdge(f, 0.16)
        f:EnableMouse(true)

        f.eyebrow = W:Eyebrow(f, "Loot Assigned")
        f.eyebrow:SetPoint("TOPLEFT", 14, -14)
        f.title = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(f.title, "body", "ink")
        f.title:SetPoint("TOPLEFT", f.eyebrow, "BOTTOMLEFT", 0, -8)
        f.title:SetPoint("RIGHT", -14, 0)
        f.title:SetJustifyH("LEFT")

        f.rows = {}
        for i = 1, 5 do
            local row = W:ListRow(f)
            row:SetHeight(28)
            row:SetPoint("TOPLEFT", 12, -62 - ((i - 1) * 30))
            row:SetPoint("RIGHT", -12, 0)
            row:SetRowVisual(i, false)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", 6, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.item = row:CreateFontString(nil, "OVERLAY")
            Theme:Text(row.item, "caption", "ink")
            row.item:SetPoint("LEFT", row.icon, "RIGHT", 8, 5)
            row.item:SetPoint("RIGHT", -8, 0)
            row.item:SetJustifyH("LEFT")
            row.item:SetWordWrap(false)

            row.source = row:CreateFontString(nil, "OVERLAY")
            Theme:Text(row.source, "caption", "faint")
            row.source:SetPoint("LEFT", row.icon, "RIGHT", 8, -7)
            row.source:SetPoint("RIGHT", -8, 0)
            row.source:SetJustifyH("LEFT")
            row.source:SetWordWrap(false)

            row:Hide()
            f.rows[i] = row
        end

        f.more = f:CreateFontString(nil, "OVERLAY")
        Theme:Text(f.more, "caption", "dim")
        f.more:SetPoint("LEFT", 16, 0)
        f.more:SetPoint("RIGHT", -86, 0)
        f.more:SetJustifyH("LEFT")

        f.close = W:Button(f, "Close", 56, 22)
        f.close:SetPoint("BOTTOMRIGHT", -12, 10)
        f.close:SetScript("OnClick", function() f:Hide() end)

        self.assignmentPopup = f
    end

    f.title:SetText(("You have %d council assignment%s."):format(#rows, #rows == 1 and "" or "s"))
    local visible = math.min(5, #rows)
    local hasMore = #rows > visible
    f:SetSize(430, 94 + (visible * 30) + (hasMore and 16 or 0))
    for i = 1, 5 do
        local popupRow = f.rows[i]
        local row = rows[i]
        if popupRow and row and i <= visible then
            local itemName, quality, icon = itemVisual(row)
            local r, g, b = qualityColor(quality)
            local source = row.bossName or row.sourceInstance or "Council assignment"
            popupRow.icon:SetTexture(icon)
            popupRow.item:SetText(short(itemName, 42))
            popupRow.item:SetTextColor(r, g, b, 1)
            popupRow.source:SetText(short(source, 52))
            popupRow:SetRowVisual(i, false)
            popupRow:Show()
        elseif popupRow then
            popupRow:Hide()
        end
    end
    if hasMore then
        f.more:ClearAllPoints()
        f.more:SetPoint("BOTTOMLEFT", 16, 38)
        f.more:SetText(("Plus %d more assignment%s."):format(#rows - visible, (#rows - visible) == 1 and "" or "s"))
        f.more:Show()
    else
        f.more:Hide()
    end
    f:Show()
    if C_Timer and C_Timer.After then
        local shownAt = now()
        f._shownAt = shownAt
        C_Timer.After(POPUP_DURATION, function()
            if f._shownAt == shownAt then f:Hide() end
        end)
    end
end

function Council:NotifyLocalAssignments(payload)
    local notification = self:SettingsNotification()
    local mine = {}
    local me = lower(playerName())
    for _, row in ipairs((payload and payload.assignments) or {}) do
        if lower(row.character) == me then mine[#mine + 1] = row end
    end
    if #mine == 0 then return end

    if notification.showLootChatMessage ~= false then
        for i, row in ipairs(mine) do
            if i > 5 then
                ns:Print(("Council has %d more assignments for you."):format(#mine - 5), "success")
                break
            end
            local source = row.bossName or row.sourceInstance
            ns:Print(("Assigned to you: %s%s"):format(self:ItemText(row), source and (" from " .. source) or ""), "success")
        end
    end
    self:ShowAssignmentPopup(mine)
end

function Council:RegisterPanel(panel)
    self.panels = self.panels or {}
    self.panels[#self.panels + 1] = panel
end

function Council:NotifyPanels(reason)
    for _, panel in ipairs(self.panels or {}) do
        if reason == "progress" and panel.UpdateProgress then
            panel:UpdateProgress()
        elseif panel.Refresh then
            panel:Refresh()
        end
    end
end

function Council:SchedulePanelRefresh(reason)
    if self.panelRefreshPending then return end
    self.panelRefreshPending = true
    local function refresh()
        self.panelRefreshPending = nil
        self:NotifyPanels(reason or "refresh")
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, refresh)
    else
        refresh()
    end
end

function Council:SetPanelNotice(text, tone)
    self.panelNotice = { text = text, tone = tone, at = now() }
end

function Council:PanelNotice(maxAge)
    local notice = self.panelNotice
    if not notice or not notice.text then return nil end
    if maxAge and notice.at and now() - notice.at > maxAge then return nil end
    return notice.text, notice.tone
end

function Council:IncomingProgress()
    local syncId = self.activeIncomingSyncId
    local incoming = syncId and self.incoming and self.incoming[syncId]
    if not incoming then return nil end
    local total = math.max(1, incoming.total or 1)
    local received = math.min(total, incoming.received or 0)
    return {
        syncId = syncId,
        sender = incoming.sender,
        title = incoming.title,
        received = received,
        total = total,
        percent = received / total,
    }
end

function Council:HasIncomingSync()
    return self:IncomingProgress() ~= nil
end

function Council:RequestPending()
    return self.requestedSyncAt and (now() - self.requestedSyncAt) <= REQUEST_PENDING_TTL
end

function Council:NotifyProgressThrottled()
    local at = preciseNow()
    if self.lastProgressNotifyAt and (at - self.lastProgressNotifyAt) < PROGRESS_REFRESH_INTERVAL then return end
    self.lastProgressNotifyAt = at
    self:NotifyPanels("progress")
end

function Council:SendSharedText(text, sendChannel, target, title, count)
    self.outgoingShares = self.outgoingShares or {}
    local outgoingKey = tostring(sendChannel or "") .. ":" .. tostring(target or "")
    if self.outgoingShares[outgoingKey] then
        return nil, "Council assignments are already being shared to this target."
    end
    self.outgoingShares[outgoingKey] = true

    local syncId = tostring(now()) .. "-" .. tostring(math.random and math.random(1000000) or 0)
    local total = math.max(1, math.ceil(#text / CHUNK_SIZE))
    local streamDuration = total * CHUNK_DELAY + CHUNK_DELAY
    local startDelay = 0
    if C_Timer and C_Timer.After then
        local at = preciseNow()
        local nextAt = math.max(at, self.nextCouncilShareAt or at)
        startDelay = math.max(0, nextAt - at)
        self.nextCouncilShareAt = nextAt + streamDuration + SHARE_STREAM_GAP
    end

    local function sendStart()
        sendAddon(COMM_PREFIX, table.concat({ PROTOCOL_VERSION, OP.SYNC, syncId, total, playerName(), title or "Loot assignments" }, "|"), sendChannel, target)
    end

    local function sendChunk(i)
        local chunk = text:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
        sendAddon(COMM_PREFIX, table.concat({ PROTOCOL_VERSION, OP.CHUNK, syncId, i, total, chunk }, "|"), sendChannel, target)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(startDelay, sendStart)
        for i = 1, total do
            C_Timer.After(startDelay + ((i - 1) * CHUNK_DELAY), function() sendChunk(i) end)
        end
        C_Timer.After(startDelay + streamDuration, function()
            sendAddon(COMM_PREFIX, table.concat({ PROTOCOL_VERSION, OP.DONE, syncId }, "|"), sendChannel, target)
            self.outgoingShares[outgoingKey] = nil
            self:SetPanelNotice(("Shared %d council assignment%s to %s."):format(count or 0, (count or 0) == 1 and "" or "s", target or sendChannel), "success")
            self:NotifyPanels()
        end)
    else
        sendStart()
        for i = 1, total do sendChunk(i) end
        sendAddon(COMM_PREFIX, table.concat({ PROTOCOL_VERSION, OP.DONE, syncId }, "|"), sendChannel, target)
        self.outgoingShares[outgoingKey] = nil
    end
    return total
end

function Council:ShareActive(channel, target)
    local active = self:Active()
    if not active then return nil, "No council assignments to share." end
    local text = active.encoded or self:EncodePayload(active)
    if not text then return nil, "Could not encode council assignments." end
    local sendChannel = channel == "WHISPER" and target and "WHISPER" or activeChannel(channel or "GUILD")
    if not sendChannel then return nil, "You need to be in a guild, raid, or party to share." end
    local count = #(active.assignments or {})
    local total, sendErr = self:SendSharedText(text, sendChannel, target, active.title, count)
    if not total then return nil, sendErr or "Could not start council share." end
    self:SetPanelNotice(("Sharing %d council assignment%s to %s..."):format(count, count == 1 and "" or "s", target or sendChannel), "warning")
    ns:Print(("Sharing %d council assignment%s to %s in %d chunk%s."):format(count, count == 1 and "" or "s", target or sendChannel, total, total == 1 and "" or "s"), "success")
    self:NotifyPanels()
    return true
end

function Council:ReceiveSharedText(text, sender)
    local payload, err = self:DecodeText(text)
    if not payload then return nil, err end
    local active = self:Active()
    if active and active.importedAt and payload.importedAt and active.importedAt > payload.importedAt then
        self:SetPanelNotice(("Ignored older council assignments from %s."):format(sender or "unknown"), "warning")
        self:NotifyPanels()
        if self:Settings().announceImports ~= false then
            ns:Print(("Ignored older council assignments from %s."):format(sender or "unknown"))
        end
        return active
    end
    self:SetPanelNotice(("Synced %d council assignment%s from %s."):format(#(payload.assignments or {}), #(payload.assignments or {}) == 1 and "" or "s", sender or "unknown"), "success")
    local imported = self:ApplyImport(payload, sender)
    local store = self:Store()
    if store then store.received[imported.id] = { from = sender, at = now(), count = #(imported.assignments or {}) } end
    if self:Settings().announceImports ~= false then
        ns:Print(("Received %d council assignment%s from %s."):format(#(imported.assignments or {}), #(imported.assignments or {}) == 1 and "" or "s", sender or "unknown"), "success")
    end
    return imported
end

function Council:CleanupIncoming()
    if not self.incoming then return end
    local cutoff = now() - INCOMING_TTL
    for syncId, incoming in pairs(self.incoming) do
        if (incoming.at or 0) < cutoff then
            self.incoming[syncId] = nil
            if self.activeIncomingSyncId == syncId then
                self.activeIncomingSyncId = nil
                self.requestedSyncAt = nil
                self:SetPanelNotice("Council sync timed out before all data was received.", "warning")
                self:NotifyPanels()
            end
        end
    end
end

function Council:TryFinishIncoming(syncId)
    local incoming = self.incoming and self.incoming[syncId]
    if not incoming or not incoming.done or (incoming.received or 0) < (incoming.total or 0) then return end
    local text = table.concat(incoming.chunks, "")
    self.incoming[syncId] = nil
    if self.activeIncomingSyncId == syncId then self.activeIncomingSyncId = nil end
    self.requestedSyncAt = nil
    self.lastProgressNotifyAt = nil
    self:ReceiveSharedText(text, incoming.sender)
end

function Council:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX or samePlayer(sender, playerName()) then return end
    self:CleanupIncoming()
    local parts = splitPipe(message)
    if numberOrNil(parts[1]) ~= PROTOCOL_VERSION then return end
    local op = parts[2]
    if op == OP.SYNC then
        local syncId, total, owner, title = parts[3], numberOrNil(parts[4]) or 0, parts[5], parts[6]
        if not syncId or total <= 0 then return end
        self.incoming = self.incoming or {}
        local incoming = self.incoming[syncId] or { chunks = {}, received = 0 }
        incoming.total = total
        incoming.sender = sender
        incoming.owner = owner
        incoming.title = title
        incoming.at = now()
        self.incoming[syncId] = incoming
        self.activeIncomingSyncId = syncId
        self:SetPanelNotice(("Receiving council assignments from %s..."):format(sender or "unknown"), "warning")
        self:NotifyPanels("progress")
    elseif op == OP.CHUNK then
        local syncId, index, total, chunk = parts[3], numberOrNil(parts[4]), numberOrNil(parts[5]), parts[6]
        if not syncId or not index or not chunk then return end
        self.incoming = self.incoming or {}
        local incoming = self.incoming[syncId] or { total = total or 0, chunks = {}, received = 0, sender = sender, at = now() }
        self.incoming[syncId] = incoming
        if not incoming.chunks[index] then incoming.received = (incoming.received or 0) + 1 end
        incoming.chunks[index] = chunk
        incoming.total = incoming.total > 0 and incoming.total or total
        incoming.at = now()
        self.activeIncomingSyncId = syncId
        self:NotifyProgressThrottled()
        self:TryFinishIncoming(syncId)
    elseif op == OP.DONE then
        local syncId = parts[3]
        local incoming = self.incoming and self.incoming[syncId]
        if not incoming then return end
        incoming.done = true
        self:TryFinishIncoming(syncId)
    elseif op == OP.REQUEST then
        local requesterImportedAt = numberOrNil(parts[4]) or 0
        local active = self:Active()
        if sender and sender ~= "" and active and (numberOrNil(active.importedAt) or 0) > requesterImportedAt then
            self.lastSyncResponseByTarget = self.lastSyncResponseByTarget or {}
            local responseKey = lower(sender)
            local lastResponse = self.lastSyncResponseByTarget[responseKey]
            if lastResponse and now() - lastResponse < RESPONSE_COOLDOWN then return end
            self.lastSyncResponseByTarget[responseKey] = now()
            self:ShareActive("WHISPER", sender)
        end
    end
end

function Council:RequestSync()
    if self:HasIncomingSync() then
        self:SetPanelNotice("Council sync is already receiving. Please wait for it to finish.", "warning")
        self:NotifyPanels("progress")
        return nil, "Council sync is already receiving."
    end
    if self:RequestPending() then
        self:SetPanelNotice("Council sync already requested. Waiting for a response...", "warning")
        self:NotifyPanels()
        return nil, "Council sync already requested."
    end
    if self.lastRequestAt and now() - self.lastRequestAt < REQUEST_COOLDOWN then
        local remaining = math.ceil(REQUEST_COOLDOWN - (now() - self.lastRequestAt))
        self:SetPanelNotice(("Please wait %d sec before requesting council sync again."):format(math.max(1, remaining)), "warning")
        self:NotifyPanels()
        return nil, "Council sync request is on cooldown."
    end
    local channel = activeChannel("GUILD")
    local active = self:Active()
    local importedAt = active and active.importedAt or 0
    if channel then
        sendAddon(COMM_PREFIX, table.concat({ PROTOCOL_VERSION, OP.REQUEST, playerName(), importedAt }, "|"), channel)
        self.lastRequestAt = now()
        self.requestedSyncAt = now()
        local requestedAt = self.requestedSyncAt
        if C_Timer and C_Timer.After then
            C_Timer.After(REQUEST_PENDING_TTL + 0.2, function()
                if self.requestedSyncAt == requestedAt and not self:HasIncomingSync() then
                    self.requestedSyncAt = nil
                    self:SetPanelNotice("Council sync request expired. You can request again.", "warning")
                    self:NotifyPanels()
                end
            end)
        end
        self:SetPanelNotice("Requested council sync from guild members.", "warning")
        self:NotifyPanels()
        return true
    end
    self:SetPanelNotice("You need to be in a guild, raid, or party to request council sync.", "danger")
    self:NotifyPanels()
    return nil, "You need to be in a guild, raid, or party to request council sync."
end

function Council:AddTooltipLines(tooltip, itemId)
    if not tooltip or not itemId then return end
    local rows = self:AssignmentsForItem(itemId)
    if not rows or #rows == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("iddqd Council", 0.80, 0.65, 0.35)
    for i, row in ipairs(rows) do
        if i > 6 then
            tooltip:AddLine(("+ %d more"):format(#rows - 6), 0.72, 0.76, 0.84)
            break
        end
        tooltip:AddLine("Assigned to: " .. tostring(row.character or "?"), 0.72, 0.76, 0.84)
    end
    tooltip:Show()
end

function Council:InstallTooltipHooks()
    if self.tooltipHooksInstalled then return end
    self.tooltipHooksInstalled = true
    local function hookTooltip(tooltip)
        if not tooltip or not tooltip.HookScript then return end
        tooltip:HookScript("OnTooltipSetItem", function(tip)
            local _, link = tip:GetItem()
            self:AddTooltipLines(tip, itemIdFromLink(link))
        end)
    end
    hookTooltip(GameTooltip)
    hookTooltip(ItemRefTooltip)
    hookTooltip(ShoppingTooltip1)
    hookTooltip(ShoppingTooltip2)
end

function Council:AnnounceItemAssignments(itemId, itemName, contextKey)
    local lines, rows = self:FormatAssignmentsForItem(itemId, 5)
    if not rows or #rows == 0 then return end
    self.recentItemNotices = self.recentItemNotices or {}
    contextKey = tostring(contextKey or itemId or itemName or "")
    local at = self.recentItemNotices[contextKey]
    if at and now() - at < 8 then return end
    self.recentItemNotices[contextKey] = now()

    local label = itemName or (rows[1] and self:ItemText(rows[1])) or ("Item " .. tostring(itemId))
    ns:Print(("Council assignment for %s: %s"):format(label, table.concat(lines, ", ")), self:CurrentPlayerAssigned(rows) and "success" or nil)
    -- Optional chat-channel announcement of the assignment.
    local s = self:AnnounceSettings()
    if s and s.enabled == true and s.announceAssignments == true then
        self:ChannelAnnounce(("Council: %s -> %s"):format(label, table.concat(lines, ", ")))
    end
end

-- ---------------------------------------------------------------------------
-- Loot announcements (settings.lootSettings.announceLoot.*)
-- Posts to a chat channel when enabled. Channel falls back to RAID->PARTY->SAY as
-- appropriate for the current group; only the leader/assist should spam group channels.
-- ---------------------------------------------------------------------------
function Council:AnnounceSettings()
    local s = self:LootSettings().announceLoot
    if type(s) ~= "table" then return nil end
    return s
end

-- Resolve the configured channel to a usable SendChatMessage channel for the current group.
local function resolveAnnounceChannel(channel)
    local inRaid = IsInRaid and IsInRaid()
    local inParty = (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
    if channel == "GUILD" then
        return (IsInGuild and IsInGuild()) and "GUILD" or nil
    elseif channel == "RAID_WARNING" then
        -- Raid warning needs lead/assist; fall back to RAID if not eligible.
        if inRaid and (UnitIsGroupLeader and UnitIsGroupLeader("player") or UnitIsGroupAssistant and UnitIsGroupAssistant("player")) then
            return "RAID_WARNING"
        end
        return inRaid and "RAID" or (inParty and "PARTY" or nil)
    elseif channel == "RAID" then
        return inRaid and "RAID" or (inParty and "PARTY" or nil)
    elseif channel == "PARTY" then
        return inParty and "PARTY" or nil
    end
    return inRaid and "RAID" or (inParty and "PARTY" or nil)
end

-- Prefix every outgoing announcement with [iddqd] so recipients can see where it came
-- from. Idempotent: messages that already carry the tag are left alone.
local IDDQD_TAG = "[iddqd] "
local function withTag(message)
    message = tostring(message or "")
    if message:sub(1, #IDDQD_TAG) == IDDQD_TAG then return message end
    return IDDQD_TAG .. message
end

-- Low-level: send to the configured announce channel WITHOUT the announceLoot.enabled gate.
-- Used by features that have their own enable flag (e.g. announce-manual-assignments).
function Council:SendToAnnounceChannel(message)
    if not SendChatMessage or not message or message == "" then return false end
    local s = self:AnnounceSettings()
    local channel = resolveAnnounceChannel((s and s.channel) or "RAID")
    if not channel then return false end
    pcall(SendChatMessage, withTag(message), channel)
    return true
end

-- Gated by announceLoot.enabled (the Loot Announcements section master switch).
function Council:ChannelAnnounce(message)
    local s = self:AnnounceSettings()
    if not s or s.enabled ~= true then return false end
    return self:SendToAnnounceChannel(message)
end

function Council:IsMasterLootMethod()
    local m = GetLootMethod and GetLootMethod()
    return m == "master" or m == 2
end

function Council:IsPlayerMasterLooter()
    if IsMasterLooter and IsMasterLooter() == true then return true end

    local method, partyMaster, raidMaster = nil, nil, nil
    if GetLootMethod then method, partyMaster, raidMaster = GetLootMethod() end
    if method ~= "master" and method ~= 2 then return false end

    if IsInRaid and IsInRaid() then
        local playerIndex = UnitInRaid and UnitInRaid("player")
        if playerIndex and raidMaster and tonumber(raidMaster) == tonumber(playerIndex) then return true end
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do
            if GetRaidRosterInfo and select(11, GetRaidRosterInfo(i)) then
                local name = GetRaidRosterInfo(i)
                local short = name and shortPlayerName(name)
                return lower(short) == lower(playerName())
            end
        end
    else
        -- In party master-loot APIs, party master 0 usually means the player.
        if tonumber(partyMaster) == 0 then return true end
    end

    return false
end

-- Which event source is AUTHORITATIVE for announcing drops, so the same item is never announced
-- from two sources (the cause of the double announces). This mirrors Gargul's master-loot behavior:
--   * local player is the master looter -> the loot WINDOW when it is ready (LOOT_READY).
--   * master loot but someone else is ML -> no drop announcement from this client.
--   * everything else -> the ROLL popup (START_LOOT_ROLL) for items that roll, plus CHAT fallback
--     for items that don't roll (greys/quest/auto-loot, BoE personal loot).
-- Returns "window", "roll", or "none".
function Council:AnnounceSource()
    if self:IsPlayerMasterLooter() then return "window" end
    if self:IsMasterLootMethod() then return "none" end
    return "roll"
end

-- Announce a dropped item ONCE per physical drop. `quality` may be nil (uncached). `dropKey`
-- uniquely identifies this item-off-this-corpse (loot-source GUID + itemId) so re-opening the
-- same corpse — which re-fires LOOT_OPENED — does not re-announce. Two different corpses
-- dropping the same item type still announce separately (distinct GUIDs). `quantity` appends
-- "xN" for stacks (e.g. "[Tin Ore] x4").
function Council:AnnounceLootDrop(link, quality, dropKey, quantity, itemId)
    local s = self:AnnounceSettings()
    if not s or s.enabled ~= true or s.announceDrops ~= true then return end
    if not link then return end

    -- Quality gate. If a link resolves but we still can't read its quality, fall back to a
    -- GetItemInfo lookup; then apply the floor. When a minimum is set and quality is STILL
    -- unknown, skip rather than announce — better to miss a rare uncached item than to spam
    -- every Poor/Common drop (which is the bug this guards against).
    local minQ = tonumber(s.minQuality) or 4
    local q = tonumber(quality)
    if q == nil and GetItemInfo then
        -- Bind the quality to a single local first: passing select(3, GetItemInfo(...)) straight
        -- into tonumber() leaks the FOLLOWING return (itemLevel) as tonumber's 2nd arg (base),
        -- which errors "base out of range".
        local _, _, cq = GetItemInfo(link)
        q = tonumber(cq)
    end
    if minQ > 0 then
        if q == nil then return end
        if q < minQ then return end
    end

    -- Dedup. The SAME physical drop reaches us from up to three events: the loot window opening
    -- (LOOT_OPENED), a group-loot roll popup (START_LOOT_ROLL), and the "you receive loot" chat
    -- line (CHAT_MSG_LOOT — the auto-loot fallback). Announce each drop EXACTLY once:
    --
    --  * per-source `dropKey` (DURABLE): the loot-window key is the corpse GUID + itemId, so
    --    re-opening the SAME corpse and taking the item later never re-announces (this fixes the
    --    "re-loot the same corpse" double). The roll key is the rollID.
    --  * CHAT fallback suppression: the chat line carries no GUID/rollID, so it can't match those
    --    keys. Instead, when a drop is announced from a window/roll we stamp a per-itemId marker
    --    with a timestamp; the chat line for that item is suppressed for SUPPRESS_SECS afterwards
    --    (covers auto-loot's instant chat line AND a roll won minutes later). A genuinely new drop
    --    of the same item from a LATER corpse, looted past the window, is the rare case that may
    --    re-announce — acceptable, and if you open its window the GUID key handles it.
    local SUPPRESS_SECS = 180
    local nowT = (time and time()) or 0
    self.announcedDrops = self.announcedDrops or {}
    self.windowAnnouncedItems = self.windowAnnouncedItems or {}
    itemId = tonumber(itemId) or tonumber(tostring(link):match("item:(%d+)"))
    local fromChat = dropKey and tostring(dropKey):find("^chatloot:") ~= nil

    -- Per-source replay guard.
    if dropKey and self.announcedDrops[dropKey] then return end

    -- Chat fallback: skip if a window/roll already announced this item recently.
    if fromChat and itemId then
        local stamp = self.windowAnnouncedItems[itemId]
        if stamp and (nowT - stamp) <= SUPPRESS_SECS then return end
    end

    if dropKey then self.announcedDrops[dropKey] = nowT end
    -- Window/roll announce -> stamp the per-item marker that suppresses the matching chat line.
    if itemId and not fromChat then self.windowAnnouncedItems[itemId] = nowT end

    local text = link
    local n = tonumber(quantity)
    if n and n > 1 then text = ("%s x%d"):format(link, n) end
    self:ChannelAnnounce(("Loot dropped: %s"):format(text))
end

-- Forget drop-announce keys older than maxAge seconds so the dedup set can't grow unbounded
-- across a long session. An item not seen for this long is effectively a fresh drop again.
function Council:PruneAnnouncedDrops(maxAge)
    maxAge = tonumber(maxAge) or 3600
    local nowT = (time and time()) or 0
    local cutoff = nowT - maxAge
    if self.announcedDrops then
        for k, t in pairs(self.announcedDrops) do
            if (tonumber(t) or 0) < cutoff then self.announcedDrops[k] = nil end
        end
    end
    -- Also prune the per-item chat-suppression markers.
    if self.windowAnnouncedItems then
        for id, t in pairs(self.windowAnnouncedItems) do
            if (tonumber(t) or 0) < cutoff then self.windowAnnouncedItems[id] = nil end
        end
    end
end

function Council:AttachRollFrameHint(rollID, itemId)
    local lines, rows = self:FormatAssignmentsForItem(itemId, 3)
    if not rows or #rows == 0 then return end
    local text = "Assigned: " .. table.concat(lines, ", ")
    local isMine = self:CurrentPlayerAssigned(rows)
    local function apply()
        local maxFrames = NUM_GROUP_LOOT_FRAMES or 4
        for i = 1, maxFrames do
            local frame = _G and _G["GroupLootFrame" .. i]
            if frame and frame:IsShown() and (frame.rollID == rollID or frame.id == rollID) then
                local fs = frame.iddqdCouncilText
                if not fs then
                    fs = frame:CreateFontString(nil, "OVERLAY")
                    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
                    fs:SetPoint("TOP", frame, "BOTTOM", 0, -2)
                    fs:SetJustifyH("CENTER")
                    frame.iddqdCouncilText = fs
                    frame:HookScript("OnHide", function(self)
                        if self.iddqdCouncilText then self.iddqdCouncilText:Hide() end
                    end)
                end
                fs:SetText(text)
                fs:SetTextColor(isMine and 0.38 or 0.80, isMine and 0.84 or 0.65, isMine and 0.55 or 0.35, 1)
                fs:Show()
            end
        end
    end
    apply()
    if C_Timer and C_Timer.After then C_Timer.After(0.15, apply) end
end

function Council:CanManageLoot()
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
end

-- ---------------------------------------------------------------------------
-- Auto-assist (settings.lootSettings.autoAssistEnabled / autoAssistNames)
-- When you are the RAID LEADER, promote the configured characters to assistant.
-- ---------------------------------------------------------------------------
function Council:MaybeAutoAssist()
    local ls = self:LootSettings()
    if ls.autoAssistEnabled ~= true then return end
    local names = ls.autoAssistNames
    if type(names) ~= "table" or #names == 0 then return end
    if not (UnitIsGroupLeader and UnitIsGroupLeader("player")) then return end   -- only the leader can promote
    if not IsInRaid or not IsInRaid() then return end                            -- assistants are a raid concept
    if not GetRaidRosterInfo or not PromoteToAssistant then return end

    -- Build a wanted-set of short names (case-insensitive).
    local wanted = {}
    for _, n in ipairs(names) do
        local short = lower(shortPlayerName(n))
        if short ~= "" then wanted[short] = true end
    end

    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, n do
        local name, rank = GetRaidRosterInfo(i)   -- rank: 2=leader, 1=assistant, 0=none
        if name then
            local short = lower(shortPlayerName(name))
            if wanted[short] and (rank or 0) < 1 then
                pcall(PromoteToAssistant, name)
            end
        end
    end
end

-- Debounced: roster updates can fire in bursts; coalesce into one promotion pass.
function Council:ScheduleAutoAssist()
    self._autoAssistToken = (self._autoAssistToken or 0) + 1
    local token = self._autoAssistToken
    if C_Timer and C_Timer.After then
        C_Timer.After(1.0, function() if token == self._autoAssistToken then self:MaybeAutoAssist() end end)
    else
        self:MaybeAutoAssist()
    end
end

function Council:RoleRequirementMet(requirement)
    requirement = requirement or "assist"
    if requirement == "any" then return true end
    if requirement == "leader" then return UnitIsGroupLeader and UnitIsGroupLeader("player") end
    return self:CanManageLoot()
end

function Council:IsEquippableItem(itemId)
    if not itemId or not GetItemInfo then return false, "missing item" end
    if tierLootItem(itemId) then return true end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
    if equipLoc == nil then return nil, "uncached" end
    if equipLoc == "" then return false, "not equippable" end
    return true
end

function Council:TryAutoNeed(rollID, attempt)
    local settings = self:LootSettings().autoNeed or {}
    if settings.enabled ~= true then return end
    local texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE, deColor, itemLink
    if GetLootRollItemInfo then
        texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE, deColor, itemLink =
            GetLootRollItemInfo(rollID)
    end
    itemLink = itemLink or (GetLootRollItemLink and GetLootRollItemLink(rollID))
    local itemId = itemIdFromLink(itemLink)
    attempt = attempt or 1
    if (not itemId or quality == nil) and C_Timer and attempt < AUTO_NEED_RETRIES then
        C_Timer.After(AUTO_NEED_RETRY_DELAY, function() self:TryAutoNeed(rollID, attempt + 1) end)
        return
    end
    if not itemId or not canNeed then return end

    local rows = self:AssignmentsForItem(itemId)
    if not self:CurrentPlayerAssigned(rows) then return end
    if not self:RoleRequirementMet(settings.roleRequirement or "assist") then return end
    local rarities = settings.rarities or {}
    if rarities[quality] ~= true then return end

    local equippable, reason = self:IsEquippableItem(itemId)
    if equippable == nil and C_Timer and attempt < AUTO_NEED_RETRIES then
        C_Timer.After(AUTO_NEED_RETRY_DELAY, function() self:TryAutoNeed(rollID, attempt + 1) end)
        return
    end
    if equippable ~= true then return end

    self.autoNeedRolls = self.autoNeedRolls or {}
    local key = tostring(rollID) .. ":" .. tostring(itemId)
    if self.autoNeedRolls[key] then return end
    self.autoNeedRolls[key] = true
    RollOnLoot(rollID, 1)
    ns:Print(("Auto-need rolled for assigned loot: %s"):format(itemLink or name or ("Item " .. itemId)), "success")
    if C_Timer then C_Timer.After(60, function() self.autoNeedRolls[key] = nil end) end
end

function Council:CandidateIndexFor(slot, player)
    if not GetNumGroupMembers or not GetMasterLootCandidate then return nil end
    local wanted = lower(shortPlayerName(player))
    for i = 1, math.max(0, GetNumGroupMembers()) do
        local candidate = GetMasterLootCandidate(slot, i)
        local shortName = candidate and shortPlayerName(candidate)
        if shortName and lower(shortName) == wanted then return i end
    end
end

function Council:TryAutoMasterLoot()
    local lootSettings = self:LootSettings()
    if lootSettings.autoMasterLoot ~= true then return end
    if not self:CanManageLoot() then return end
    local method = GetLootMethod and GetLootMethod()
    if method ~= "master" and method ~= 2 then return end
    if not GetNumLootItems or not GetLootSlotLink then return end

    local used = {}
    for slot = GetNumLootItems(), 1, -1 do
        local _, lootName, _, _, _, locked = GetLootSlotInfo(slot)
        if lootName and not locked then
            local link = GetLootSlotLink(slot)
            local itemId = itemIdFromLink(link)
            local rows = self:AssignmentsForItem(itemId)
            if itemId and #rows > 0 then
                used[itemId] = used[itemId] or {}
                table.sort(rows, function(a, b) return lower(a.character) < lower(b.character) end)
                for idx, row in ipairs(rows) do
                    if not used[itemId][idx] then
                        local candidate = self:CandidateIndexFor(slot, row.character)
                        if candidate then
                            used[itemId][idx] = true
                            GiveMasterLoot(slot, candidate)
                            ns:Print(("Master-looted %s to %s."):format(link or lootName, row.character or "?"), "success")
                            local s = self:AnnounceSettings()
                            if s and s.enabled == true and s.announceMasterLoot == true then
                                self:ChannelAnnounce(("Master-looted %s to %s."):format(link or lootName, row.character or "?"))
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

function Council:OnStartLootRoll(rollID)
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    local itemId = itemIdFromLink(link)
    local name, count, quality
    if GetLootRollItemInfo then
        local _, itemName, itemCount, itemQuality = GetLootRollItemInfo(rollID)
        name = itemName
        count = itemCount
        quality = itemQuality
    end
    self:AnnounceItemAssignments(itemId, link or name, "roll:" .. tostring(rollID))
    -- Announce from the roll popup ONLY when rolls are the authoritative source (non-master loot).
    -- Under master loot the window is authoritative (and ML items don't roll anyway).
    if itemId and self:AnnounceSource() == "roll" then
        self:AnnounceLootDrop(link, quality, "roll:" .. tostring(rollID), count or 1, itemId)
    end
    self:AttachRollFrameHint(rollID, itemId)
    self:TryAutoNeed(rollID, 1)
end

-- The loot-source GUID for a slot (the corpse/container the item is on). Uniquely identifies a
-- physical drop so re-opening the same corpse doesn't re-announce. nil when unavailable.
local function lootSourceGUID(slot)
    if not GetLootSourceInfo then return nil end
    local ok, guid = pcall(GetLootSourceInfo, slot)
    if ok and type(guid) == "string" and guid ~= "" then return guid end
    return nil
end

local function lootSlotQuantityQuality(slot)
    if not GetLootSlotInfo then return nil, nil end
    local _, _, quantity, fourth, fifth = GetLootSlotInfo(slot)
    -- Classic clients have returned both:
    --   texture, item, quantity, quality, locked
    --   texture, item, quantity, currencyID, quality, locked
    local quality = nil
    if type(fourth) == "number" and (type(fifth) == "boolean" or fifth == nil) then
        quality = fourth
    elseif type(fifth) == "number" then
        quality = fifth
    end
    return quantity, quality
end

function Council:ProcessLootWindowOpen(attempt)
    if not GetNumLootItems or not GetLootSlotLink then return end
    attempt = tonumber(attempt) or 1
    local source = self:AnnounceSource()
    local retry = false
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemId = itemIdFromLink(link)
        local quantity, quality = lootSlotQuantityQuality(slot)
        if itemId then
            self:AnnounceItemAssignments(itemId, link, "loot:" .. self.lootOpenNonce .. ":" .. tostring(slot))
            -- Announce from the loot WINDOW only when this client is the master looter. LOOT_READY
            -- is the authoritative event, with LOOT_OPENED as an early best-effort pass. Under
            -- group/personal/FFA loot the roll popup + chat line are authoritative instead, so we
            -- DON'T announce here (announcing from both the window AND the roll popup was the
            -- double-announce bug).
            if source == "window" then
                if quality == nil then retry = true end
                local src = lootSourceGUID(slot)
                local dropKey = (src and (src .. ":" .. itemId)) or ("open:" .. self.lootOpenNonce .. ":" .. slot)
                self:AnnounceLootDrop(link, quality, dropKey, quantity, itemId)
            end
        elseif source == "window" then
            local slotType = GetLootSlotType and GetLootSlotType(slot)
            if slotType == nil or slotType == _G.LOOT_SLOT_ITEM or slotType == 1 then
                retry = true
            end
        end
    end
    self:TryAutoMasterLoot()

    if source == "window" and retry and C_Timer and C_Timer.After and attempt < 6 then
        local nonce = self.lootOpenNonce
        C_Timer.After(0.15, function()
            if self.lootOpenNonce == nonce then self:ProcessLootWindowOpen(attempt + 1) end
        end)
    end
end

function Council:BeginLootWindowSession()
    if self.lootWindowIsOpen and self.lootOpenNonce then return end
    self.lootWindowIsOpen = true
    self.lootOpenNonce = tostring(now()) .. ":" .. tostring(math.random and math.random(100000) or 0)
    self:PruneAnnouncedDrops()
end

function Council:OnLootOpened()
    self:BeginLootWindowSession()
    self:ProcessLootWindowOpen(1)
end

function Council:OnLootReady()
    self:BeginLootWindowSession()
    self:ProcessLootWindowOpen(1)
end

function Council:OnLootClosed()
    self.lootWindowIsOpen = false
    self.lootOpenNonce = nil
end

-- ---------------------------------------------------------------------------
-- Auto-trade helper (settings.lootSettings.autoTradeEnabled)
-- Modern WoW forbids programmatically opening a trade or moving items into it (those need a
-- hardware click), so a true auto-trade is impossible. This helper instead REMINDS you when
-- you loot an item the council assigned to someone ELSE in your group, and soft-targets the
-- assignee so the trade is one click away.
-- ---------------------------------------------------------------------------
function Council:GroupMemberPresent(shortName)
    shortName = lower(shortName or "")
    if shortName == "" then return false end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local name = GetRaidRosterInfo and GetRaidRosterInfo(i)
            if name and lower(shortPlayerName(name)) == shortName then return true end
        end
    else
        for i = 1, n - 1 do
            local name = UnitName and UnitName("party" .. i)
            if name and lower(shortPlayerName(name)) == shortName then return true end
        end
    end
    return false
end

-- Called when the LOCAL player receives an item (parsed from CHAT_MSG_LOOT).
function Council:OnSelfReceivedItem(itemId, link)
    if self:LootSettings().autoTradeEnabled ~= true then return end
    if not itemId then return end
    local rows = self:AssignmentsForItem(itemId)
    if not rows or #rows == 0 then return end
    local me = lower(playerName())
    for _, row in ipairs(rows) do
        local target = row.character
        local short = target and lower(shortPlayerName(target))
        if short and short ~= me and self:GroupMemberPresent(short) then
            ns:Print(("Trade %s to %s (council assignment)."):format(link or ("item " .. itemId), target), "success")
            -- Soft-target the assignee so the trade is one click away (only out of combat).
            if TargetUnit and not (InCombatLockdown and InCombatLockdown()) then
                pcall(TargetUnit, target)
            end
            return
        end
    end
end

-- Parse "you receive" loot lines for the LOCAL player only. Returns link, quantity (or nil).
-- The MULTIPLE format embeds a %d count (e.g. "You receive loot: %sx%d."); capture it so drop
-- announcements can show "[Item] xN".
local function parseSelfLoot(message)
    if type(message) ~= "string" then return nil end
    local selfMulti = _G and _G.LOOT_ITEM_SELF_MULTIPLE   -- has %s (link) AND %d (count)
    local selfPat   = _G and _G.LOOT_ITEM_SELF            -- has %s only
    -- Try the MULTIPLE pattern first, capturing both link and count.
    if selfMulti then
        local pat = "^" .. selfMulti:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
        local a, b = message:match(pat)
        if a and b then return a, tonumber(b) end          -- link, count
        if a then return a, nil end
    end
    if selfPat then
        local pat = "^" .. selfPat:gsub("%%s", "(.+)") .. "$"
        local cap = message:match(pat)
        if cap then return cap, nil end
    end
    -- Fallbacks for the plain enUS phrasings.
    local linkN, n = message:match("^You receive loot: (.+)x(%d+)%.?$")
    if linkN then return linkN, tonumber(n) end
    local link = message:match("^You receive loot: (.+)%.?$")
    if link then return link, nil end
    return nil
end

function Council:OnChatLoot(message)
    local link, count = parseSelfLoot(message)
    if not link then return end
    local itemId = itemIdFromLink(link)
    self:OnSelfReceivedItem(itemId, link)

    -- Drop announcement FALLBACK for non-master loot only: with auto-loot the loot window can
    -- empty before a roll/window source sees the item, so CHAT_MSG_LOOT catches those. Under
    -- master loot, the loot window is the single authoritative source; never announce later when
    -- the item is actually awarded/looted.
    if itemId and self:AnnounceSource() == "roll" then
        local bucket = math.floor(((time and time()) or 0))
        local dropKey = "chatloot:" .. tostring(itemId) .. ":" .. tostring(bucket)
        self:AnnounceLootDrop(link, nil, dropKey, count, itemId)
    end
end

function Council:OnInit()
    self:Store()
    registerPrefix(COMM_PREFIX)
    ns:GetModule("Nav"):RegisterPanel("council", function(parent)
        return ns:GetModule("CouncilPanel"):Build(parent)
    end)
end

function Council:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Events = ns:GetModule("Events")
    if Events then
        Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender) self:OnAddonMessage(prefix, message, channel, sender) end, "Council")
        Events:On("START_LOOT_ROLL", function(rollID) self:OnStartLootRoll(rollID) end, "Council")
        Events:On("LOOT_OPENED", function() self:OnLootOpened() end, "Council")
        Events:On("LOOT_READY", function() self:OnLootReady() end, "Council")
        Events:On("LOOT_CLOSED", function() self:OnLootClosed() end, "Council")
        Events:On("GET_ITEM_INFO_RECEIVED", function(_, success)
            if success then self:SchedulePanelRefresh("item_info") end
        end, "Council")
        -- Auto-assist: re-evaluate promotions on roster changes (debounced to coalesce churn).
        Events:On("GROUP_ROSTER_UPDATE", function() self:ScheduleAutoAssist() end, "Council")
        -- Auto-trade helper: remind to trade items the council assigned to others.
        Events:On("CHAT_MSG_LOOT", function(message) self:OnChatLoot(message) end, "Council")
    end
    self:InstallTooltipHooks()
    local slash = ns:GetModule("Slash")
    if slash then
        slash:Register("councilshare", function()
            local ok, err = self:ShareActive("GUILD")
            if not ok and err then ns:Print(err, "error") end
        end)
        slash:Register("councilsync", function() self:RequestSync() end)
    end
end
