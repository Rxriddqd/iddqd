local ADDON, ns = ...

local Panel = ns:NewModule("GambaPanel")

local function provider()
    return _G.IDDQD_GAMBA_PROVIDER or ns:GetModule("GambaProvider")
end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function stripRealm(name)
    local players = Players()
    if players and players.ShortName then return players:ShortName(name) end
    name = tostring(name or "")
    return name:match("^([^%-]+)") or name
end

local function playerName()
    return stripRealm(UnitName("player"))
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function shortName(name, maxLen)
    name = tostring(name or "?")
    maxLen = maxLen or 14
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 1) .. "."
end

local function classColorCode(classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not color then return nil end
    return ("|cff%02x%02x%02x"):format(
        math.floor(color.r * 255 + 0.5),
        math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5))
end

local function playerClassColor(name)
    local wanted = lower(stripRealm(name))
    local player = UnitName("player")
    if player and lower(stripRealm(player)) == wanted then
        local _, classFile = UnitClass("player")
        return classColorCode(classFile)
    end

    local groupCount = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, groupCount do
        local unit = prefix .. i
        local unitName = UnitName(unit)
        if unitName and lower(stripRealm(unitName)) == wanted then
            local _, classFile = UnitClass(unit)
            return classColorCode(classFile)
        end
    end

    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() do
            local guildName, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
            if guildName and lower(stripRealm(guildName)) == wanted then
                return classColorCode(classFile)
            end
        end
    end
end

local function coloredName(name, maxLen)
    if tostring(name or "") == "Me" then return "|cff5fbf8aMe|r" end
    local display = shortName(name, maxLen or 14)
    local color = playerClassColor(name)
    return color and (color .. display .. "|r") or display
end

local function countTable(t)
    local count = 0
    for _ in pairs(t or {}) do count = count + 1 end
    return count
end

local function hasPlayer(session, name)
    name = lower(stripRealm(name))
    for player in pairs((session and session.players) or {}) do
        if lower(stripRealm(player)) == name then return true end
    end
    return false
end

local function isHost(session)
    return session and lower(stripRealm(session.host)) == lower(playerName())
end

local function setButtonEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function installImmediateDrag(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self, buttonName)
        if buttonName ~= "LeftButton" then return end
        self._moving = true
        self:StartMoving()
    end)
    local function stopMoving(self)
        if not self._moving then return end
        self._moving = false
        self:StopMovingOrSizing()
    end
    frame:SetScript("OnMouseUp", stopMoving)
    frame:HookScript("OnHide", stopMoving)
end

local MAX_GAMBA_AMOUNT = 10000000
local MAX_GAMBA_AMOUNT_DIGITS = 8

local function makeEditBox(parent, value, opts)
    opts = opts or {}
    local Theme = ns:GetModule("Theme")
    local host = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    host:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 9,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    host:SetBackdropColor(0.020, 0.020, 0.024, 1)
    host:SetBackdropBorderColor(1, 1, 1, 0.045)
    host:EnableMouse(true)
    local rightInset = 8
    if opts.icon ~= false then
        local icon = host:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        icon:SetSize(12, 12)
        icon:SetPoint("RIGHT", -8, 0)
        rightInset = 24
    end
    local box = CreateFrame("EditBox", nil, host)
    box:SetPoint("TOPLEFT", 8, 0)
    box:SetPoint("BOTTOMRIGHT", -rightInset, 0)
    box:SetAutoFocus(false)
    box:SetMultiLine(false)
    box:SetFont(Theme.font, 12, "")
    box:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
    box:SetJustifyH("RIGHT")
    box:SetText(tostring(value or ""))
    box:SetMaxLetters(opts.maxLetters or MAX_GAMBA_AMOUNT_DIGITS)
    if opts.numeric ~= false then
        box:SetScript("OnTextChanged", function(self)
            if self._cleaning then return end
            local text = self:GetText() or ""
            local digits = text:gsub("[^0-9]", "")
            if #digits > MAX_GAMBA_AMOUNT_DIGITS then digits = digits:sub(1, MAX_GAMBA_AMOUNT_DIGITS) end
            local amount = tonumber(digits) or 0
            if amount > MAX_GAMBA_AMOUNT then digits = tostring(MAX_GAMBA_AMOUNT) end
            if digits ~= text then
                self._cleaning = true
                self:SetText(digits)
                self:SetCursorPosition(#digits)
                self._cleaning = false
            end
        end)
    end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    host:SetScript("OnMouseDown", function() box:SetFocus() end)
    host.box = box
    return host, box
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local DICE_ICON = "|TInterface\\Buttons\\UI-GroupLoot-Dice-Up:16:16:0:0|t"
local CHANNEL_ICON_ATLAS = "voicechat-channellist-icon-STT-off"
local CHEVRON_ICON_ATLAS = "MiniMap-PositionArrowDown"
local ROUND_BUTTON = ("Interface\\AddOns\\%s\\Media\\button-round-mask.tga"):format(ADDON)
local GAMBA_ICON = ("Interface\\AddOns\\%s\\Media\\gamba"):format(ADDON)

local function iconBadge(parent, size)
    local Theme = ns:GetModule("Theme")
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size or 32, size or 32)
    local shadow = frame:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(ROUND_BUTTON)
    shadow:SetPoint("TOPLEFT", 0, -1)
    shadow:SetPoint("BOTTOMRIGHT", 0, -2)
    shadow:SetVertexColor(0, 0, 0, 0.42)
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetTexture(ROUND_BUTTON)
    edge:SetAllPoints(frame)
    edge:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.42)
    local bg = frame:CreateTexture(nil, "ARTWORK")
    bg:SetTexture(ROUND_BUTTON)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetVertexColor(0.065, 0.058, 0.045, 1)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(GAMBA_ICON)
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    return frame
end

local function fmtGold(value)
    return ("%d %s"):format(tonumber(value) or 0, GOLD_ICON)
end

local function fmtStakeGold(value)
    return ("|cFFFFFFFF%d|r %s"):format(tonumber(value) or 0, GOLD_ICON)
end

local function syncAmountBox(box, session, defaultAmount)
    if not box then return end
    local value = session and session.amount or defaultAmount
    if session or not box:HasFocus() then
        local text = tostring(value or "")
        if (box:GetText() or "") ~= text then box:SetText(text) end
    end
end

local function fmtGoldStat(label, value, tone)
    local color = tone == "good" and "5FBF8A" or tone == "bad" and "D4756B" or "BDB4A2"
    return ("|cFF646A76%s:|r |cFF%s%s|r"):format(label, color, fmtGold(value))
end

local function fmtRoll(value)
    return ("%s |cFFCAA65A%s|r"):format(DICE_ICON, tostring(value or "?"))
end

local function soundItems()
    local items = {
        { value = "NONE", label = "None" },
        { value = "RAID_WARNING", label = "Raid Warning" },
        { value = "READY_CHECK", label = "Ready Check" },
        { value = "TELL_MESSAGE", label = "Whisper" },
        { value = "IG_PLAYER_INVITE", label = "Invite" },
        { value = "AUCTION_WINDOW_OPEN", label = "Bell" },
    }
    local seen = {}
    for _, item in ipairs(items) do seen[item.value] = true end
    if LibStub then
        local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok and lib and lib.List then
            local listOk, sounds = pcall(lib.List, lib, "sound")
            if listOk and type(sounds) == "table" then
                table.sort(sounds)
                for _, name in ipairs(sounds) do
                    local value = "LSM:" .. tostring(name)
                    if not seen[value] then
                        items[#items + 1] = { value = value, label = "Shared: " .. tostring(name) }
                        seen[value] = true
                    end
                end
            end
        end
    end
    local g = provider()
    local settings = g and g:Settings()
    for _, value in ipairs({ settings and settings.soundNew, settings and settings.soundWon, settings and settings.soundLost }) do
        value = tostring(value or "")
        if value:match("^LSM:") and not seen[value] then
            items[#items + 1] = { value = value, label = "Shared: " .. value:gsub("^LSM:", "") }
            seen[value] = true
        end
    end
    return items
end

local function previewSound(value)
    local g = provider()
    if g and g.PreviewSound then g:PreviewSound(value) end
end

local function fmtTime(value)
    value = tonumber(value)
    if not value or value <= 0 then return "-" end
    return date("%d %b %H:%M", value)
end

local function statusText(value)
    if value == "verified" then return "|cFF5FBF8AVerified|r" end
    if value == "paid" then return "|cFF5FBF8APaid|r" end
    if value == "payment_pending" then return "|cFFCAA65APending|r" end
    if value == "unpaid" then return "|cFFD4756BUnpaid|r" end
    return "|cFFCAA65APending|r"
end

local function stateText(value)
    if value == "lobby" then return "Lobby" end
    if value == "rolling" then return "Rolling" end
    if value == "reroll" then return "Reroll" end
    if value == "payment" then return "Payment" end
    if value == "complete" then return "Complete" end
    if value == "cancelled" then return "Cancelled" end
    return "Idle"
end

local function clearColumns(row)
    if not row.cols then return end
    for _, col in ipairs(row.cols) do
        col:SetText("")
        col:Hide()
    end
end

local function resetRow(row)
    if not row then return end
    row:ClearAllPoints()
    row:SetHeight(22)
    if row.text then
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetText("")
        row.text:Show()
    end
    clearColumns(row)
    if row.clearButton then row.clearButton:Hide() end
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
            row.cols[i] = col
        end
        col:ClearAllPoints()
        col:SetPoint("LEFT", row, "LEFT", spec.x or 8, 0)
        if spec.w then col:SetWidth(spec.w) else col:SetPoint("RIGHT", row, "RIGHT", -8, 0) end
        col:SetJustifyH(spec.justify or "LEFT")
        col:SetText(spec.text or "")
        col:Show()
    end
    for i = #(specs or {}) + 1, #(row.cols or {}) do row.cols[i]:Hide() end
end

local function stateLabel(session)
    if not session then return "No active game" end
    if session.result then
        local loserText = (session.result.mode == "goon" or session.goonMode) and "GOON table" or (session.result.loser or "?")
        return ("%s wins, %s owes %s | Result %s | Payment %s"):format(
            session.result.winner or "?",
            loserText,
            fmtGold(session.result.owed),
            statusText(session.result.verificationStatus),
            statusText(session.result.paymentStatus))
    end
    local modeText = session.goonMode and " | GOON" or ((session.state == "lobby" and (tonumber(session.goonChance) or 0) > 0) and (" | GOON " .. tostring(session.goonChance) .. "%") or "")
    return ("%s | Host %s | Stake %s%s | /roll %d"):format(stateText(session.state), session.host or "?", fmtStakeGold(session.amount), modeText, session.amount or 0)
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = W:Card(parent, "base", true)

    local titleIcon = iconBadge(f, 42)
    titleIcon:SetPoint("TOPLEFT", 18, -8)
    local title = W:Title(f, "Gamba")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 12, -1)

    local p = provider()
    local settings = p and p:Settings() or {}
    local version = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(version, "caption", "dim")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText((p and p.displayVersion) or "v1.4")

    local mini = W:Button(f, "Mini", 56, 24)
    mini:SetPoint("TOPRIGHT", -18, -16)
    mini:SetScript("OnClick", function()
        local shell = ns:GetModule("Shell")
        if shell and shell.frame then shell.frame:Hide() end
        Panel:ToggleMini()
    end)

    local amountHost, amountBox = makeEditBox(f, settings.defaultAmount or 100)
    amountHost:SetPoint("TOPLEFT", 18, -70)
    amountHost:SetSize(124, 24)
    f.amountBox = amountBox

    local ACTION_W = 68
    local new = W:Button(f, "Start", ACTION_W, 24)
    if new.SetTone then new:SetTone("blue") end
    new:SetPoint("LEFT", amountHost, "RIGHT", 8, 0)
    new:SetScript("OnClick", function()
        local g = provider()
        if not g then return end
        local s = g:Current()
        local cancellable = s and (s.state == "lobby" or s.state == "rolling" or s.state == "reroll")
        if cancellable then
            g:Cancel("manual")
            return
        end
        g:CreateSession(tonumber(amountBox:GetText()) or g:Settings().defaultAmount or 100, g:Settings().channel)
    end)

    local join = W:Button(f, "Join", ACTION_W, 24)
    join:SetPoint("LEFT", new, "RIGHT", 4, 0)
    join:SetScript("OnClick", function()
        local g = provider()
        local s = g and g:Current()
        if not g then return end
        if s and hasPlayer(s, playerName()) then g:Leave() else g:Join() end
    end)

    local start = W:Button(f, "Lock In!", ACTION_W, 24)
    if start.SetTone then start:SetTone("green") end
    start:SetPoint("LEFT", join, "RIGHT", 4, 0)
    start:SetScript("OnClick", function() if provider() then provider():StartRolling() end end)

    local lastCall = W:Button(f, "Last Call", ACTION_W, 24)
    lastCall:SetPoint("LEFT", start, "RIGHT", 4, 0)
    lastCall:SetScript("OnClick", function()
        local g = provider()
        if not g then return end
        local s = g:Current()
        if s and s.state == "rolling" then g:WarnMissingRolls() else g:LastCall() end
    end)

    local roll = W:Button(f, "", 38, 32)
    if roll._shadow then roll._shadow:Hide() end
    if roll._edge then roll._edge:Hide() end
    if roll._fill then roll._fill:Hide() end
    if roll._hl then roll._hl:Hide() end
    local rollGlow = roll:CreateTexture(nil, "ARTWORK")
    if rollGlow.SetAtlas then
        local ok = pcall(rollGlow.SetAtlas, rollGlow, "shop-toast-token-glow")
        if not ok then rollGlow:SetTexture("Interface\\Buttons\\WHITE8X8") end
    else
        rollGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    rollGlow:SetBlendMode("ADD")
    rollGlow:SetSize(44, 44)
    rollGlow:SetPoint("CENTER")
    rollGlow:SetVertexColor(1, 0.88, 0.34, 0.78)
    rollGlow:Hide()
    roll._glow = rollGlow
    local rollIcon = roll:CreateTexture(nil, "OVERLAY")
    rollIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
    rollIcon:SetSize(26, 26)
    rollIcon:SetPoint("CENTER")
    roll._icon = rollIcon
    function roll:SetRollReady(ready)
        if ready then
            self._icon:SetVertexColor(1, 1, 1, 1)
            self._icon:SetAlpha(1)
            if self._glow then self._glow:Show() end
        else
            self._icon:SetVertexColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], 1)
            self._icon:SetAlpha(0.42)
            if self._glow then self._glow:Hide() end
        end
    end
    roll:SetScript("OnClick", function() if provider() then provider():Roll() end end)

    f.actionButtons = { new = new, join = join, start = start, lastCall = lastCall, roll = roll }

    local status = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "section", "gold")
    status:SetPoint("TOPLEFT", 18, -108)
    status:SetPoint("RIGHT", -18, 0)
    status:SetJustifyH("LEFT")
    f.status = status

    local playersTitle = W:Eyebrow(f, "Players / Rolls")
    playersTitle:SetPoint("TOPLEFT", 18, -146)
    local players = W:Card(f, "raised", true)
    players:SetPoint("TOPLEFT", 18, -166)
    players:SetPoint("BOTTOMLEFT", 18, 56)
    players:SetWidth(290)
    f.playerRows = {}
    roll:SetPoint("BOTTOMRIGHT", players, "TOPRIGHT", 0, 6)

    local debtsTab = W:Button(f, "Debts", 62, 22)
    debtsTab:SetPoint("TOPLEFT", 328, -144)
    local historyTab = W:Button(f, "History", 74, 22)
    historyTab:SetPoint("LEFT", debtsTab, "RIGHT", 8, 0)
    local totalsTab = W:Button(f, "Totals", 66, 22)
    totalsTab:SetPoint("LEFT", historyTab, "RIGHT", 8, 0)
    local settingsTab = W:Button(f, "Settings", 82, 22)
    settingsTab:SetPoint("LEFT", totalsTab, "RIGHT", 8, 0)
    local howTab = W:Button(f, "How To", 70, 22)
    howTab:SetPoint("LEFT", settingsTab, "RIGHT", 8, 0)
    f.rightTabs = { debts = debtsTab, history = historyTab, totals = totalsTab, settings = settingsTab, how = howTab }

    local debts = W:Card(f, "raised", true)
    debts:SetPoint("TOPLEFT", 328, -174)
    debts:SetPoint("BOTTOMRIGHT", -18, 56)
    f.rightRows = {}
    f.historyPage = 0

    local historyPrev = W:Button(debts, "Prev", 50, 22)
    historyPrev:SetPoint("BOTTOMRIGHT", debts, "BOTTOMRIGHT", -104, 10)
    local historyPageText = debts:CreateFontString(nil, "OVERLAY")
    Theme:Text(historyPageText, "caption", "dim")
    historyPageText:SetPoint("LEFT", historyPrev, "RIGHT", 8, 0)
    historyPageText:SetWidth(38)
    historyPageText:SetJustifyH("CENTER")
    local historyNext = W:Button(debts, "Next", 50, 22)
    historyNext:SetPoint("LEFT", historyPageText, "RIGHT", 8, 0)
    historyPrev:SetScript("OnClick", function()
        f.historyPage = math.max(0, (f.historyPage or 0) - 1)
        f:Refresh()
    end)
    historyNext:SetScript("OnClick", function()
        f.historyPage = (f.historyPage or 0) + 1
        f:Refresh()
    end)
    f.historyPager = { prev = historyPrev, next = historyNext, label = historyPageText }

    local settingsScroll, settingsContent = W:ScrollHost(debts)
    settingsScroll:SetPoint("TOPLEFT", 0, 0)
    settingsScroll:SetPoint("BOTTOMRIGHT", -12, 0)
    settingsScroll:Hide()
    settingsContent:SetSize(1, 360)
    local settingsBar = W:ScrollBar(settingsScroll, settingsContent)
    settingsBar:Hide()
    f.settingsScroll = settingsScroll
    f.settingsContent = settingsContent
    f.settingsBar = settingsBar

    local settingsParent = settingsContent

    local channelLabel = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(channelLabel, "caption", "dim")
    channelLabel:SetPoint("TOPLEFT", 12, -12)
    channelLabel:SetWidth(68)
    channelLabel:SetJustifyH("LEFT")
    channelLabel:SetText("Channel")

    local channel = W:Dropdown(settingsParent, {
        width = 180,
        sharp = true,
        iconAtlas = CHANNEL_ICON_ATLAS,
        chevronAtlas = CHEVRON_ICON_ATLAS,
        get = function() return (provider() and provider():Settings().channel) or "AUTO" end,
        set = function(v) if provider() then provider():Settings().channel = v end end,
        items = function()
            return {
                { value = "AUTO", label = "Auto" },
                { value = "GUILD", label = "Guild" },
                { value = "RAID", label = "Raid" },
                { value = "PARTY", label = "Party" },
                { value = "ADDON", label = "Addon" },
            }
        end,
    })
    channel:SetPoint("LEFT", channelLabel, "RIGHT", 12, 0)

    local normalChat = W:Checkbox(settingsParent, "Send normal chat announcements", function()
        local g = provider()
        return g and g:Settings().announce ~= false
    end, function(value)
        local g = provider()
        if g then g:Settings().announce = value end
    end)
    normalChat:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -10)

    local addonNotices = W:Checkbox(settingsParent, "Show addon-only notices", function()
        local g = provider()
        return g and g:Settings().addonNotices == true
    end, function(value)
        local g = provider()
        if g then g:Settings().addonNotices = value end
    end)
    addonNotices:SetPoint("TOPLEFT", normalChat, "BOTTOMLEFT", 0, -6)

    local autoRoll = W:Checkbox(settingsParent, "Auto-roll when rolling starts", function()
        local g = provider()
        return g and g:Settings().autoRoll == true
    end, function(value)
        local g = provider()
        if g then g:Settings().autoRoll = value end
    end)
    autoRoll:SetPoint("TOPLEFT", addonNotices, "BOTTOMLEFT", 0, -6)

    local autoJoin = W:Checkbox(settingsParent, "Auto-join new Gamba games", function()
        local g = provider()
        return g and g:Settings().autoJoin == true
    end, function(value)
        local g = provider()
        if g then g:Settings().autoJoin = value end
    end)
    autoJoin:SetPoint("TOPLEFT", autoRoll, "BOTTOMLEFT", 0, -6)

    local accountMode = W:Checkbox(settingsParent, "Account-wide stats and debt settlement", function()
        local g = provider()
        return g and g:Settings().accountMode == true
    end, function(value)
        local g = provider()
        if g then
            g:Settings().accountMode = value
            if g.RegisterAccountCharacter then g:RegisterAccountCharacter(playerName()) end
            if g.Notify then g:Notify() end
        end
    end)
    accountMode:SetPoint("TOPLEFT", autoJoin, "BOTTOMLEFT", 0, -6)

    local goonMode = W:Checkbox(settingsParent, "Enable GOON mode chance", function()
        local g = provider()
        return g and g:Settings().goonEnabled == true
    end, function(value)
        local g = provider()
        if g then g:Settings().goonEnabled = value end
    end)
    goonMode:SetPoint("TOPLEFT", accountMode, "BOTTOMLEFT", 0, -6)
    local goonHost, goonBox = makeEditBox(settingsParent, settings.goonChance or 5, { icon = false })
    goonHost:SetPoint("LEFT", goonMode, "RIGHT", 8, 0)
    goonHost:SetSize(54, 22)
    local goonSuffix = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(goonSuffix, "caption", "dim")
    goonSuffix:SetPoint("LEFT", goonHost, "RIGHT", 6, 0)
    goonSuffix:SetText("%")
    goonBox:SetScript("OnTextChanged", function(self)
        local g = provider()
        local value = math.floor(tonumber(self:GetText()) or 0)
        if value < 0 then value = 0 elseif value > 100 then value = 100 end
        if g then g:Settings().goonChance = value end
    end)

    local lobbyTimeout = W:Checkbox(settingsParent, "Auto-cancel lobby after", function()
        local g = provider()
        return g and g:Settings().lobbyTimeoutEnabled ~= false
    end, function(value)
        local g = provider()
        if g then g:Settings().lobbyTimeoutEnabled = value end
    end)
    lobbyTimeout:SetPoint("TOPLEFT", goonMode, "BOTTOMLEFT", 0, -6)
    local timeoutHost, timeoutBox = makeEditBox(settingsParent, settings.lobbyTimeoutMinutes or 10, { icon = false })
    timeoutHost:SetPoint("LEFT", lobbyTimeout, "RIGHT", 8, 0)
    timeoutHost:SetSize(54, 22)
    local timeoutSuffix = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(timeoutSuffix, "caption", "dim")
    timeoutSuffix:SetPoint("LEFT", timeoutHost, "RIGHT", 6, 0)
    timeoutSuffix:SetText("minutes")
    timeoutBox:SetScript("OnTextChanged", function(self)
        local g = provider()
        local value = math.max(1, math.floor(tonumber(self:GetText()) or 10))
        if g then g:Settings().lobbyTimeoutMinutes = value end
    end)

    local settingsNote = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(settingsNote, "caption", "dim")
    settingsNote:SetPoint("TOPLEFT", lobbyTimeout, "BOTTOMLEFT", 0, -6)
    settingsNote:SetPoint("RIGHT", -12, 0)
    settingsNote:SetJustifyH("LEFT")
    settingsNote:SetText("Empty lobbies always cancel after 2 minutes. Addon channel mode syncs silently.")

    local soundTitle = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(soundTitle, "caption", "warm")
    soundTitle:SetPoint("TOPLEFT", settingsNote, "BOTTOMLEFT", 0, -8)
    soundTitle:SetText("Optional sound warnings")

    local soundNewLabel = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(soundNewLabel, "caption", "dim")
    soundNewLabel:SetPoint("TOPLEFT", soundTitle, "BOTTOMLEFT", 0, -10)
    soundNewLabel:SetWidth(68)
    soundNewLabel:SetJustifyH("LEFT")
    soundNewLabel:SetText("New")
    local soundNew = W:Dropdown(settingsParent, {
        width = 246,
        height = 22,
        sharp = true,
        maxVisible = 15,
        keepOpenOnRefresh = true,
        labelFontSize = 10,
        rowFontSize = 10,
        preview = previewSound,
        get = function()
            local g = provider()
            return (g and g:Settings().soundNew) or "NONE"
        end,
        set = function(value)
            local g = provider()
            if g then g:Settings().soundNew = value end
        end,
        items = soundItems,
    })
    soundNew:SetPoint("LEFT", soundNewLabel, "RIGHT", 12, 0)

    local soundWonLabel = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(soundWonLabel, "caption", "dim")
    soundWonLabel:SetPoint("TOPLEFT", soundNewLabel, "BOTTOMLEFT", 0, -12)
    soundWonLabel:SetWidth(68)
    soundWonLabel:SetJustifyH("LEFT")
    soundWonLabel:SetText("Won")
    local soundWon = W:Dropdown(settingsParent, {
        width = 246,
        height = 22,
        sharp = true,
        maxVisible = 15,
        keepOpenOnRefresh = true,
        labelFontSize = 10,
        rowFontSize = 10,
        preview = previewSound,
        get = function()
            local g = provider()
            return (g and g:Settings().soundWon) or "NONE"
        end,
        set = function(value)
            local g = provider()
            if g then g:Settings().soundWon = value end
        end,
        items = soundItems,
    })
    soundWon:SetPoint("LEFT", soundWonLabel, "RIGHT", 12, 0)

    local soundLostLabel = settingsParent:CreateFontString(nil, "OVERLAY")
    Theme:Text(soundLostLabel, "caption", "dim")
    soundLostLabel:SetPoint("TOPLEFT", soundWonLabel, "BOTTOMLEFT", 0, -12)
    soundLostLabel:SetWidth(68)
    soundLostLabel:SetJustifyH("LEFT")
    soundLostLabel:SetText("Lost")
    local soundLost = W:Dropdown(settingsParent, {
        width = 246,
        height = 22,
        sharp = true,
        maxVisible = 15,
        keepOpenOnRefresh = true,
        labelFontSize = 10,
        rowFontSize = 10,
        preview = previewSound,
        get = function()
            local g = provider()
            return (g and g:Settings().soundLost) or "NONE"
        end,
        set = function(value)
            local g = provider()
            if g then g:Settings().soundLost = value end
        end,
        items = soundItems,
    })
    soundLost:SetPoint("LEFT", soundLostLabel, "RIGHT", 12, 0)
    f.settingControls = { channelLabel, channel, normalChat, addonNotices, autoRoll, autoJoin, accountMode, goonMode, goonHost, goonSuffix, lobbyTimeout, timeoutHost, timeoutSuffix, soundTitle, soundNewLabel, soundNew, soundWonLabel, soundWon, soundLostLabel, soundLost, settingsNote }

    local summary = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(summary, "body", "dim")
    summary:SetPoint("BOTTOMLEFT", 18, 20)
    summary:SetPoint("RIGHT", -18, 0)
    summary:SetJustifyH("LEFT")
    f.summary = summary

    local function ensureRow(rows, host, i)
        local row = rows[i]
        if row then
            resetRow(row)
            return row
        end
        row = W:ListRow(host)
        row:SetHeight(22)
        row.text = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.text, "caption", "dim")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:HookScript("OnHide", clearColumns)
        rows[i] = row
        return row
    end

    local clearDebtPopup = "IDDQD_GAMBA_CONFIRM_CLEAR_DEBT_" .. ADDON
    local function confirmClearDebt(g, debt)
        if not (g and debt) then return end
        if StaticPopupDialogs and StaticPopup_Show then
            StaticPopupDialogs[clearDebtPopup] = {
                text = "Mark this debt as paid?\n\n%s owes you %s.",
                button1 = "Mark Paid",
                button2 = "Cancel",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnAccept = function(_, data)
                    if data and data.provider and data.debt then
                        data.provider:SettleDebtRowAsCreditor(data.debt)
                    end
                end,
            }
            StaticPopup_Show(clearDebtPopup, debt.debtor or "?", fmtGold(debt.amount), { provider = g, debt = debt })
        else
            g:SettleDebtRowAsCreditor(debt)
        end
    end

    function f:SetRightTab(tab)
        self.rightTab = tab
        for key, tabButton in pairs(self.rightTabs) do
            if tabButton.SetTone then
                tabButton:SetTone(key == tab and "blue" or nil)
            end
            if tabButton.label then
                local c = key == tab and Theme.color.ink or Theme.color.dim
                tabButton.label:SetTextColor(c[1], c[2], c[3], 1)
            end
        end
        self:Refresh()
    end

    debtsTab:SetScript("OnClick", function() f:SetRightTab("debts") end)
    historyTab:SetScript("OnClick", function() f:SetRightTab("history") end)
    totalsTab:SetScript("OnClick", function() f:SetRightTab("totals") end)
    settingsTab:SetScript("OnClick", function() f:SetRightTab("settings") end)
    howTab:SetScript("OnClick", function() f:SetRightTab("how") end)

    function f:Refresh()
        local g = provider()
        if not g then return end
        local session = g:Current()
        local me = playerName()
        local isCancellableGame = session and (session.state == "lobby" or session.state == "rolling" or session.state == "reroll")
        local canCreate = not isCancellableGame
        local canJoin = session and session.state == "lobby" and not hasPlayer(session, me)
        local canLeave = session and session.state == "lobby" and hasPlayer(session, me)
        local canJoinLeave = canJoin or (canLeave and not isHost(session))
        local canStart = session and session.state == "lobby" and isHost(session) and countTable(session.players) >= 2
        local canLastCall = session and (session.state == "lobby" or session.state == "rolling") and isHost(session)
        local canRoll = g.CanRoll and g:CanRoll(me)
        local canCancel = isCancellableGame and isHost(session)
        f.actionButtons.new:SetText(isCancellableGame and "Cancel" or "Start")
        if f.actionButtons.new.SetTone then f.actionButtons.new:SetTone(isCancellableGame and nil or "blue") end
        if f.actionButtons.start.SetTone then f.actionButtons.start:SetTone("green") end
        f.actionButtons.join:SetText(canLeave and "Leave" or "Join")
        f.actionButtons.lastCall:SetText((session and session.state == "rolling") and "Roll Now!" or "Last Call")
        setButtonEnabled(f.actionButtons.new, isCancellableGame and canCancel or canCreate)
        setButtonEnabled(f.actionButtons.join, canJoinLeave)
        setButtonEnabled(f.actionButtons.start, canStart)
        setButtonEnabled(f.actionButtons.lastCall, canLastCall)
        setButtonEnabled(f.actionButtons.roll, canRoll)
        if f.actionButtons.roll.SetRollReady then f.actionButtons.roll:SetRollReady(canRoll) end
        syncAmountBox(amountBox, session, g:Settings().defaultAmount or 100)
        status:SetText(stateLabel(session))

        for _, row in ipairs(f.playerRows) do row:Hide() end
        local names = session and sortedKeys(session.players) or {}
        if #names == 0 then
            local row = ensureRow(f.playerRows, players, 1)
            row:SetHeight(28)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, -8)
            row:SetPoint("TOPRIGHT", -8, -8)
            row:SetRowVisual(1, false)
            row.text:SetFont(Theme.font, 13, "")
            row.text:SetText("No players yet.")
            row:Show()
        else
            for i, name in ipairs(names) do
                local roll = (session.rolls and session.rolls[name]) or (session.reroll and session.reroll.rolls and session.reroll.rolls[name])
                local row = ensureRow(f.playerRows, players, i)
                row:SetHeight(28)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 30)
                row:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * 30)
                row:SetRowVisual(i, false)
                row.text:SetFont(Theme.font, 13, "")
                row.text:SetText(("%s%s"):format(coloredName(name, 17), roll and ("  " .. fmtRoll(roll)) or ""))
                row:Show()
            end
        end

        for _, row in ipairs(f.rightRows) do row:Hide() end
        if f.settingsScroll then f.settingsScroll:Hide() end
        if f.settingsBar then f.settingsBar:Hide() end
        for _, control in ipairs(f.settingControls or {}) do control:Hide() end
        if f.historyPager then
            local showPager = (f.rightTab or "debts") == "history"
            if showPager then
                f.historyPager.prev:Show()
                f.historyPager.next:Show()
                f.historyPager.label:Show()
            else
                f.historyPager.prev:Hide()
                f.historyPager.next:Hide()
                f.historyPager.label:Hide()
            end
        end
        local summaryData = g:Finances()
        local rightTab = f.rightTab or "debts"
        if rightTab == "settings" then
            if f.settingsScroll then
                f.settingsScroll:Show()
                if f.settingsContent then
                    f.settingsContent:SetWidth(math.max(1, (f.settingsScroll:GetWidth() or 1) - 2))
                end
            end
            normalChat:SetChecked(g:Settings().announce ~= false)
            addonNotices:SetChecked(g:Settings().addonNotices == true)
            autoRoll:SetChecked(g:Settings().autoRoll == true)
            autoJoin:SetChecked(g:Settings().autoJoin == true)
            accountMode:SetChecked(g:Settings().accountMode == true)
            goonMode:SetChecked(g:Settings().goonEnabled == true)
            lobbyTimeout:SetChecked(g:Settings().lobbyTimeoutEnabled ~= false)
            if goonBox and not goonBox:HasFocus() then goonBox:SetText(tostring(g:Settings().goonChance or 5)) end
            if not timeoutBox:HasFocus() then timeoutBox:SetText(tostring(g:Settings().lobbyTimeoutMinutes or 10)) end
            for _, control in ipairs(f.settingControls or {}) do
                if control.Refresh then control:Refresh() end
                control:Show()
            end
            if f.settingsBar and f.settingsBar.Update then f.settingsBar:Update() end
        elseif rightTab == "how" then
            local lines = {
                "|cFFCAA65AMade by Rxr <iddqd> Spineshatter EU|r",
                "Pick gold and channel, then press Start. Players join with 1 and leave with -1.",
                "Use Last Call before Lock In! During rolling, joined players /roll the selected amount.",
                "The dice button rolls for you when it is your turn. Roll Now reminds missing rollers.",
                "Highest roll wins, lowest roll loses, and the loser owes the difference.",
                "GOON mode is optional. If it triggers, everyone below the highest roller owes that winner their roll difference.",
                "Ties reroll only the tied players. Locked winners or losers stay locked.",
                "Debts are netted account-wide by default, so repeated games across alts keep one running balance.",
                "Addon channel mode keeps notices local to addon users instead of spamming chat.",
            }
            for i, text in ipairs(lines) do
                local row = ensureRow(f.rightRows, debts, i)
                row:SetHeight(i == 1 and 26 or 34)
                row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 35)
                row:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * 35)
                row:SetRowVisual(i, i == 1, i == 1 and "group" or nil)
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetPoint("RIGHT", -8, 0)
                row.text:SetText(text)
                row:Show()
            end
        elseif rightTab == "history" then
            local historyPageSize = 8
            local historyCount = g.HistoryCount and g:HistoryCount() or 0
            local maxHistoryPage = math.max(0, math.ceil(historyCount / historyPageSize) - 1)
            f.historyPage = math.min(math.max(0, f.historyPage or 0), maxHistoryPage)
            local historyRows = g:HistoryRows(historyPageSize, (f.historyPage or 0) * historyPageSize)
            if f.historyPager then
                f.historyPager.label:SetText(("%d/%d"):format((f.historyPage or 0) + 1, maxHistoryPage + 1))
                setButtonEnabled(f.historyPager.prev, (f.historyPage or 0) > 0)
                setButtonEnabled(f.historyPager.next, (f.historyPage or 0) < maxHistoryPage)
            end
            if #historyRows == 0 then
                local row = ensureRow(f.rightRows, debts, 1)
                row:SetPoint("TOPLEFT", 8, -8)
                row:SetPoint("TOPRIGHT", -8, -8)
                row:SetRowVisual(1, false)
                row.text:SetText("No completed sessions yet.")
                row:Show()
            else
                local head = ensureRow(f.rightRows, debts, 1)
                head:SetPoint("TOPLEFT", 8, -8)
                head:SetPoint("TOPRIGHT", -8, -8)
                head:SetRowVisual(1, false)
                setColumns(head, {
                    { x = 8, w = 70, text = "|cFF646A76TIME|r" },
                    { x = 82, w = 80, text = "|cFF646A76WINNER|r" },
                    { x = 166, w = 80, text = "|cFF646A76LOSER|r" },
                    { x = 250, w = 50, text = "|cFF646A76ROLL|r" },
                    { x = 318, w = 70, text = "|cFF646A76GOLD|r", justify = "RIGHT" },
                    { x = 398, w = 64, text = "|cFF646A76STATUS|r" },
                }, Theme)
                head:Show()
                for i, entry in ipairs(historyRows) do
                    local row = ensureRow(f.rightRows, debts, i + 1)
                    row:SetPoint("TOPLEFT", 8, -8 - i * 24)
                    row:SetPoint("TOPRIGHT", -8, -8 - i * 24)
                    row:SetRowVisual(i + 1, false)
                    setColumns(row, {
                        { x = 8, w = 70, text = fmtTime(entry.completedAt or entry.createdAt) },
                        { x = 82, w = 80, text = coloredName(entry.winner, 12) },
                        { x = 166, w = 80, text = entry.goonMode and "|cFFCAA65AGOON|r" or coloredName(entry.loser, 12) },
                        { x = 250, w = 50, text = ("%s-%s"):format(tostring(entry.winnerRoll or "?"), tostring(entry.loserRoll or "?")) },
                        { x = 318, w = 70, text = fmtGold(entry.owed), justify = "RIGHT" },
                        { x = 398, w = 64, text = statusText(entry.paymentStatus or (entry.paid and "paid" or "unpaid")) },
                    }, Theme)
                    row:Show()
                end
            end
        elseif rightTab == "totals" then
            local totalRows = g:PlayerTotals(10)
            if #totalRows == 0 then
                local row = ensureRow(f.rightRows, debts, 1)
                row:SetPoint("TOPLEFT", 8, -8)
                row:SetPoint("TOPRIGHT", -8, -8)
                row:SetRowVisual(1, false)
                row.text:SetText("No player totals yet.")
                row:Show()
            else
                local head = ensureRow(f.rightRows, debts, 1)
                head:SetPoint("TOPLEFT", 8, -8)
                head:SetPoint("TOPRIGHT", -8, -8)
                head:SetRowVisual(1, false)
                setColumns(head, {
                    { x = 8, w = 112, text = "|cFF646A76PLAYER|r" },
                    { x = 126, w = 56, text = "|cFF646A76W-L|r", justify = "RIGHT" },
                    { x = 188, w = 78, text = "|cFF646A76WON|r", justify = "RIGHT" },
                    { x = 272, w = 78, text = "|cFF646A76LOST|r", justify = "RIGHT" },
                    { x = 356, w = 86, text = "|cFF646A76NET|r", justify = "RIGHT" },
                }, Theme)
                head:Show()
                for i, total in ipairs(totalRows) do
                    local row = ensureRow(f.rightRows, debts, i + 1)
                    row:SetPoint("TOPLEFT", 8, -8 - i * 24)
                    row:SetPoint("TOPRIGHT", -8, -8 - i * 24)
                    row:SetRowVisual(i + 1, false)
                    setColumns(row, {
                        { x = 8, w = 112, text = coloredName(total.name, 14) },
                        { x = 126, w = 56, text = ("%d-%d"):format(total.wins or 0, total.losses or 0), justify = "RIGHT" },
                        { x = 188, w = 78, text = fmtGold(total.goldWon), justify = "RIGHT" },
                        { x = 272, w = 78, text = fmtGold(total.goldLost), justify = "RIGHT" },
                        { x = 356, w = 86, text = fmtGold(total.net), justify = "RIGHT" },
                    }, Theme)
                    row:Show()
                end
            end
        else
            local debtRows = g:PairDebtRows(10)
            if #debtRows == 0 then
                local row = ensureRow(f.rightRows, debts, 1)
                row:SetPoint("TOPLEFT", 8, -8)
                row:SetPoint("TOPRIGHT", -8, -8)
                row:SetRowVisual(1, false)
                row.text:SetText("No debts recorded yet.")
                row:Show()
            else
                local head = ensureRow(f.rightRows, debts, 1)
                head:SetPoint("TOPLEFT", 8, -8)
                head:SetPoint("TOPRIGHT", -8, -8)
                head:SetRowVisual(1, false)
                setColumns(head, {
                    { x = 8, w = 70, text = "|cFF646A76TIME|r" },
                    { x = 82, w = 74, text = "|cFF646A76DEBTOR|r" },
                    { x = 160, w = 74, text = "|cFF646A76WINNER|r" },
                    { x = 238, w = 96, text = "|cFF646A76GOLD|r", justify = "RIGHT" },
                    { x = 344, w = 42, text = "|cFF646A76GAMES|r" },
                    { x = 398, w = 46, text = "|cFF646A76PAID|r", justify = "CENTER" },
                }, Theme)
                head:Show()
                for i, d in ipairs(debtRows) do
                    local row = ensureRow(f.rightRows, debts, i + 1)
                    row:SetPoint("TOPLEFT", 8, -8 - i * 24)
                    row:SetPoint("TOPRIGHT", -8, -8 - i * 24)
                    row:SetRowVisual(i + 1, false)
                    setColumns(row, {
                        { x = 8, w = 70, text = fmtTime(d.updatedAt or d.createdAt) },
                        { x = 82, w = 74, text = coloredName(d.debtor, 11) },
                        { x = 160, w = 74, text = coloredName(d.creditor, 11) },
                        { x = 238, w = 96, text = fmtGold(d.amount), justify = "RIGHT" },
                        { x = 344, w = 42, text = tostring(d.sessionCount or 1) },
                    }, Theme)
                    if g.CanSettleDebtRow and g:CanSettleDebtRow(d) then
                        if not row.clearButton then
                            row.clearButton = W:Button(row, "Paid", 42, 18)
                            row.clearButton:SetPoint("LEFT", row, "LEFT", 398, 0)
                        end
                        row.clearButton:SetScript("OnClick", function() confirmClearDebt(g, d) end)
                        row.clearButton:Show()
                    end
                    row:Show()
                end
            end
        end
        local netTone = (summaryData.net or 0) > 0 and "good" or (summaryData.net or 0) < 0 and "bad" or "neutral"
        summary:SetText(("%s   %s   %s   %s   %s   |cFF646A76Provider:|r |cFFBDB4A2%s|r"):format(
            fmtGoldStat("Net", summaryData.net, netTone),
            fmtGoldStat("Won", summaryData.won, "good"),
            fmtGoldStat("Lost", summaryData.lost, "bad"),
            fmtGoldStat("Owed to you", summaryData.owedToYou, (summaryData.owedToYou or 0) > 0 and "good" or "neutral"),
            fmtGoldStat("You owe", summaryData.youOwe, (summaryData.youOwe or 0) > 0 and "bad" or "neutral"),
            g.addonId or "unknown"))
    end

    local g = provider()
    if g then
        if g.RegisterPanel then g:RegisterPanel(f) else g.panel = f end
    end
    f:SetRightTab("debts")
    return f
end

function Panel:BuildMini()
    if self.miniFrame then return self.miniFrame end
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local Gamba = provider()
    local f = W:Card(UIParent, "base", true)
    f:SetSize(318, 246)
    f:SetPoint("CENTER", UIParent, "CENTER", 220, 20)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    installImmediateDrag(f)
    f:Hide()

    local titleIcon = iconBadge(f, 24)
    titleIcon:SetPoint("TOPLEFT", 12, -8)
    local title = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(title, "section", "ink")
    title:SetPoint("LEFT", titleIcon, "RIGHT", 7, -1)
    title:SetText("Gamba")
    local subtitle = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(subtitle, "caption", "dim")
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, -3)
    subtitle:SetText("mini")

    local close = W:Button(f, "Close", 52, 20)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    local full = W:Button(f, "Full", 48, 20)
    full:SetPoint("RIGHT", close, "LEFT", -6, 0)
    full:SetScript("OnClick", function()
        f:Hide()
        local shell = ns:GetModule("Shell")
        if shell then
            shell:Show()
            shell:Select("gamba")
        end
    end)

    local amountHost, amountBox = makeEditBox(f, Gamba and Gamba:Settings().defaultAmount or 100)
    amountHost:SetPoint("TOPLEFT", 12, -42)
    amountHost:SetSize(104, 22)
    f.amountBox = amountBox

    local ACTION_W = 44
    local ACTION_H = 21
    local new = W:Button(f, "Start", ACTION_W, ACTION_H)
    if new.SetTone then new:SetTone("blue") end
    new:SetPoint("LEFT", amountHost, "RIGHT", 5, 0)
    new:SetScript("OnClick", function()
        local P = provider()
        if not P then return end
        local s = P:Current()
        local cancellable = s and (s.state == "lobby" or s.state == "rolling" or s.state == "reroll")
        if cancellable then
            P:Cancel("manual")
            return
        end
        local amount = tonumber(amountBox:GetText()) or P:Settings().defaultAmount or 100
        P:CreateSession(amount, P:Settings().channel)
    end)

    local join = W:Button(f, "Join", ACTION_W, ACTION_H)
    join:SetPoint("LEFT", new, "RIGHT", 4, 0)
    join:SetScript("OnClick", function()
        local P = provider()
        local s = P and P:Current()
        if not P then return end
        if s and hasPlayer(s, playerName()) then P:Leave() else P:Join() end
    end)

    local start = W:Button(f, "Lock", ACTION_W, ACTION_H)
    if start.SetTone then start:SetTone("green") end
    start:SetPoint("LEFT", join, "RIGHT", 4, 0)
    start:SetScript("OnClick", function()
        local P = provider()
        if P then P:StartRolling() end
    end)

    local lastCall = W:Button(f, "Call", ACTION_W, ACTION_H)
    lastCall:SetPoint("LEFT", start, "RIGHT", 4, 0)
    lastCall:SetScript("OnClick", function()
        local P = provider()
        if not P then return end
        local s = P:Current()
        if s and s.state == "rolling" then P:WarnMissingRolls() else P:LastCall() end
    end)

    local status = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(status, "caption", "gold")
    status:SetPoint("TOPLEFT", 12, -72)
    status:SetPoint("RIGHT", -54, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    f.status = status

    local roll = W:Button(f, "", 34, 30)
    roll:SetPoint("TOPRIGHT", -12, -66)
    if roll._shadow then roll._shadow:Hide() end
    if roll._edge then roll._edge:Hide() end
    if roll._fill then roll._fill:Hide() end
    if roll._hl then roll._hl:Hide() end
    local rollGlow = roll:CreateTexture(nil, "ARTWORK")
    if rollGlow.SetAtlas then
        local ok = pcall(rollGlow.SetAtlas, rollGlow, "shop-toast-token-glow")
        if not ok then rollGlow:SetTexture("Interface\\Buttons\\WHITE8X8") end
    else
        rollGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    rollGlow:SetBlendMode("ADD")
    rollGlow:SetSize(40, 40)
    rollGlow:SetPoint("CENTER")
    rollGlow:SetVertexColor(1, 0.88, 0.34, 0.78)
    rollGlow:Hide()
    roll._glow = rollGlow
    local rollIcon = roll:CreateTexture(nil, "OVERLAY")
    rollIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
    rollIcon:SetSize(24, 24)
    rollIcon:SetPoint("CENTER")
    roll._icon = rollIcon
    function roll:SetRollReady(ready)
        if ready then
            self._icon:SetVertexColor(1, 1, 1, 1)
            self._icon:SetAlpha(1)
            if self._glow then self._glow:Show() end
        else
            self._icon:SetVertexColor(Theme.color.faint[1], Theme.color.faint[2], Theme.color.faint[3], 1)
            self._icon:SetAlpha(0.42)
            if self._glow then self._glow:Hide() end
        end
    end
    roll:SetScript("OnClick", function()
        local P = provider()
        if P then P:Roll() end
    end)

    local playersTitle = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(playersTitle, "eyebrow", "warm")
    playersTitle:SetPoint("TOPLEFT", 12, -102)
    playersTitle:SetText("PLAYERS / ROLLS")

    local players = W:Card(f, "raised", true)
    players:SetPoint("TOPLEFT", 12, -118)
    players:SetPoint("BOTTOMRIGHT", -12, 12)
    players:EnableMouse(true)
    players:EnableMouseWheel(true)
    f.playerRows = {}
    f.miniScrollOffset = 0
    f.actionButtons = { new = new, join = join, start = start, lastCall = lastCall, roll = roll }

    local scrollTrack = players:CreateTexture(nil, "ARTWORK")
    scrollTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
    scrollTrack:SetPoint("TOPRIGHT", -6, -6)
    scrollTrack:SetPoint("BOTTOMRIGHT", -6, 6)
    scrollTrack:SetWidth(4)
    scrollTrack:SetVertexColor(1, 1, 1, 0.07)
    scrollTrack:Hide()
    players.scrollTrack = scrollTrack

    local scrollThumb = players:CreateTexture(nil, "OVERLAY")
    scrollThumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    scrollThumb:SetWidth(4)
    scrollThumb:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.70)
    scrollThumb:Hide()
    players.scrollThumb = scrollThumb

    players:SetScript("OnMouseWheel", function(_, delta)
        local total = f.miniPlayerCount or 0
        local visible = f.miniVisibleRows or 5
        local maxOffset = math.max(0, total - visible)
        if maxOffset <= 0 then return end
        f.miniScrollOffset = math.min(maxOffset, math.max(0, (f.miniScrollOffset or 0) - (delta or 0)))
        f:Refresh()
    end)

    local function ensureMiniRow(rows, host, i)
        local row = rows[i]
        if row then
            resetRow(row)
            return row
        end
        row = W:ListRow(host)
        row:SetHeight(20)
        row.text = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.text, "caption", "dim")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:HookScript("OnHide", clearColumns)
        rows[i] = row
        return row
    end

    function f:Refresh()
        local P = provider()
        if not P then return end
        local s = P:Current()
        local me = playerName()
        local isCancellableGame = s and (s.state == "lobby" or s.state == "rolling" or s.state == "reroll")
        local canCreate = not isCancellableGame
        local canJoin = s and s.state == "lobby" and not hasPlayer(s, me)
        local canLeave = s and s.state == "lobby" and hasPlayer(s, me)
        local canJoinLeave = canJoin or (canLeave and not isHost(s))
        local canStart = s and s.state == "lobby" and isHost(s) and countTable(s.players) >= 2
        local canLastCall = s and (s.state == "lobby" or s.state == "rolling") and isHost(s)
        local canRoll = P.CanRoll and P:CanRoll(me)
        local canCancel = isCancellableGame and isHost(s)

        new:SetText(isCancellableGame and "Cancel" or "Start")
        if new.SetTone then new:SetTone(isCancellableGame and nil or "blue") end
        if start.SetTone then start:SetTone("green") end
        join:SetText(canLeave and "Leave" or "Join")
        start:SetText("Lock")
        lastCall:SetText((s and s.state == "rolling") and "Roll!" or "Call")
        setButtonEnabled(new, isCancellableGame and canCancel or canCreate)
        setButtonEnabled(join, canJoinLeave)
        setButtonEnabled(start, canStart)
        setButtonEnabled(lastCall, canLastCall)
        setButtonEnabled(roll, canRoll)
        if roll.SetRollReady then roll:SetRollReady(canRoll) end

        syncAmountBox(amountBox, s, P:Settings().defaultAmount or 100)

        if not s then
            status:SetText("No active game.")
        elseif s.result then
            local loserText = (s.result.mode == "goon" or s.goonMode) and "GOON" or shortName(s.result.loser, 10)
            status:SetText(("%s wins. %s owes %s."):format(
                shortName(s.result.winner, 10),
                loserText,
                fmtGold(s.result.owed)))
        else
            local modeText = s.goonMode and " | GOON" or ((s.state == "lobby" and (tonumber(s.goonChance) or 0) > 0) and (" | GOON " .. tostring(s.goonChance) .. "%") or "")
            status:SetText(("%s | Host %s | Stake %s | /roll %d"):format(
                stateText(s.state),
                shortName(s.host or "?", 10),
                fmtStakeGold(s.amount) .. modeText,
                s.amount or 0))
        end

        for _, row in ipairs(f.playerRows) do row:Hide() end
        local names = s and sortedKeys(s.players) or {}
        if #names == 0 then
            f.miniScrollOffset = 0
            f.miniPlayerCount = 0
            f.miniVisibleRows = 5
            playersTitle:SetText("PLAYERS / ROLLS")
            if players.scrollTrack then players.scrollTrack:Hide() end
            if players.scrollThumb then players.scrollThumb:Hide() end
            local row = ensureMiniRow(f.playerRows, players, 1)
            row:ClearAllPoints()
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", 6, -6)
            row:SetPoint("TOPRIGHT", -18, -6)
            row:SetRowVisual(1, false)
            row.text:SetText("No players yet.")
            row:Show()
        else
            local rowHeight = 20
            local hostHeight = players:GetHeight() or 116
            local visibleRows = math.max(1, math.floor((math.max(1, hostHeight) - 12) / rowHeight))
            visibleRows = math.min(visibleRows, #names)
            local maxOffset = math.max(0, #names - visibleRows)
            f.miniScrollOffset = math.min(maxOffset, math.max(0, f.miniScrollOffset or 0))
            f.miniPlayerCount = #names
            f.miniVisibleRows = visibleRows
            playersTitle:SetText(("PLAYERS / ROLLS  %d"):format(#names))

            if players.scrollTrack and players.scrollThumb then
                if maxOffset > 0 then
                    local trackHeight = math.max(1, (players:GetHeight() or 116) - 12)
                    local thumbHeight = math.max(18, trackHeight * (visibleRows / #names))
                    local scrollPct = maxOffset > 0 and ((f.miniScrollOffset or 0) / maxOffset) or 0
                    local topOffset = 6 + (trackHeight - thumbHeight) * scrollPct
                    players.scrollTrack:Show()
                    players.scrollThumb:ClearAllPoints()
                    players.scrollThumb:SetPoint("TOPRIGHT", players, "TOPRIGHT", -6, -topOffset)
                    players.scrollThumb:SetHeight(thumbHeight)
                    players.scrollThumb:Show()
                else
                    players.scrollTrack:Hide()
                    players.scrollThumb:Hide()
                end
            end

            local startIndex = (f.miniScrollOffset or 0) + 1
            local endIndex = math.min(#names, startIndex + visibleRows - 1)
            local rowIndex = 1
            for sourceIndex = startIndex, endIndex do
                local name = names[sourceIndex]
                local value = (s.rolls and s.rolls[name]) or (s.reroll and s.reroll.rolls and s.reroll.rolls[name])
                local row = ensureMiniRow(f.playerRows, players, rowIndex)
                row:ClearAllPoints()
                row:SetHeight(18)
                row:SetPoint("TOPLEFT", 6, -6 - (rowIndex - 1) * rowHeight)
                row:SetPoint("TOPRIGHT", -18, -6 - (rowIndex - 1) * rowHeight)
                row:SetRowVisual(rowIndex, false)
                setColumns(row, {
                    { x = 7, w = 132, text = coloredName(name, 15) },
                    { x = 148, w = 58, text = value and fmtRoll(value) or "|cFF646A76Wait|r" },
                    { x = 214, w = 42, text = value and "|cFF5FBF8ADone|r" or "|cFFCAA65AOpen|r", justify = "RIGHT" },
                }, Theme)
                row:Show()
                rowIndex = rowIndex + 1
            end
        end
    end

    self.miniFrame = f
    if Gamba and Gamba.RegisterPanel then Gamba:RegisterPanel(f) end
    return f
end

function Panel:ToggleMini()
    local f = self:BuildMini()
    if f:IsShown() then
        f:Hide()
        return
    end
    local shell = ns:GetModule("Shell")
    if shell and shell.frame and shell.frame:IsShown() then shell.frame:Hide() end
    f:Show()
    f:Refresh()
end

function Panel:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local slash = ns:GetModule("Slash")
    if slash then
        slash:Register("gambamini", function() self:ToggleMini() end)
    end
end
