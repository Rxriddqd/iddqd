local ADDON, ns = ...

local VersionCheck = ns:NewModule("VersionCheck")

local COMM_PREFIX = "IDDQD_VER"
local REQUEST_OP = "REQ"
local RESPONSE_OP = "RES"
local REQUEST_COOLDOWN = 20

local function now()
    return (time and time()) or 0
end

local function trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function currentRealm()
    local Players = ns:GetModule("Players")
    if Players and Players.CurrentRealm then return Players:CurrentRealm() end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    return (realm or ""):gsub("%s+", "")
end

local function fullName(name, realm)
    local Players = ns:GetModule("Players")
    if Players and Players.FullName then return Players:FullName(name, realm) end
    name = trim(name)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = trim(realm or currentRealm())
    return realm ~= "" and (name .. "-" .. realm) or name
end

local function shortName(value)
    local Players = ns:GetModule("Players")
    if Players and Players.ShortName then return Players:ShortName(value) end
    value = trim(value)
    local name = strsplit("-", value)
    return name or value
end

local function localPlayer()
    local Players = ns:GetModule("Players")
    if Players and Players.LocalName then return Players:LocalName() end
    return fullName(UnitName("player"), currentRealm())
end

local function cleanField(value)
    value = tostring(value or "")
    value = value:gsub("[|\n\r]", " ")
    return trim(value)
end

local function registerPrefix(prefix)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then return Comm:RegisterPrefix(prefix) end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, prefix)
    end
end

local function sendAddon(message, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, message, channel, target) end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, message, channel, target)
    elseif SendAddonMessage then
        return pcall(SendAddonMessage, COMM_PREFIX, message, channel, target)
    end
    return false
end

local function versionParts(version)
    local major, minor, patch = tostring(version or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
end

local function compareVersions(a, b)
    local a1, a2, a3 = versionParts(a)
    local b1, b2, b3 = versionParts(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

function VersionCheck:Results()
    self.results = self.results or {}
    return self.results
end

function VersionCheck:OnlineGuildMembers()
    local rows = {}
    if IsInGuild and IsInGuild() and GuildRoster then pcall(GuildRoster) end
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local count = tonumber(GetNumGuildMembers() or 0) or 0
        for i = 1, count do
            local name, rankName, rankIndex, level, className, zone, note, officerNote, online, status, classFile = GetGuildRosterInfo(i)
            if name and online then
                local key = fullName(name)
                if key then
                    rows[#rows + 1] = {
                        key = key,
                        name = shortName(key),
                        class = classFile or className,
                        level = level,
                        zone = zone,
                    }
                end
            end
        end
    end

    local player = localPlayer()
    if player then
        local found
        for _, row in ipairs(rows) do
            if row.key == player then found = true; break end
        end
        if not found then
            local _, classFile = UnitClass and UnitClass("player")
            rows[#rows + 1] = {
                key = player,
                name = shortName(player),
                class = classFile,
                level = UnitLevel and UnitLevel("player") or nil,
                zone = GetZoneText and GetZoneText() or nil,
            }
        end
    end

    table.sort(rows, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    return rows
end

function VersionCheck:VersionState(version)
    if not version or version == "" then return "unknown" end
    local cmp = compareVersions(version, ns.version)
    if cmp == 0 then return "current" end
    if cmp > 0 then return "newer" end
    return "old"
end

function VersionCheck:NotifyPanel()
    if self.panel and self.panel.Refresh then self.panel:Refresh() end
end

function VersionCheck:RegisterPanel(panel)
    self.panel = panel
end

function VersionCheck:Request()
    if not IsInGuild or not IsInGuild() then
        ns:Print("Join a guild before checking addon versions.", "warning")
        return false
    end
    local at = now()
    if self.lastRequestAt and at - self.lastRequestAt < REQUEST_COOLDOWN then
        ns:Print("Version check was already requested. Please wait a moment.", "warning")
        return false
    end
    self.lastRequestAt = at
    self.requestedAt = at
    self.results = {}
    local player = localPlayer()
    if player then
        self.results[player] = { version = ns.version, at = at, source = "self" }
    end
    sendAddon(("%s|%s|%s"):format(REQUEST_OP, cleanField(ns.version), cleanField(player or "")), "GUILD")
    ns:Print("Addon version check requested.", "success")
    self:NotifyPanel()
    return true
end

function VersionCheck:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local op, version, requester = strsplit("|", message or "", 3)
    local senderKey = fullName(sender)
    if not senderKey or senderKey == localPlayer() then return end

    if op == REQUEST_OP then
        sendAddon(("%s|%s|%s"):format(RESPONSE_OP, cleanField(ns.version), cleanField(localPlayer() or "")), "WHISPER", sender)
        return
    end

    if op == RESPONSE_OP then
        local results = self:Results()
        results[senderKey] = {
            version = cleanField(version),
            at = now(),
            source = "response",
        }
        self:NotifyPanel()
    end
end

local function classColor(classFile)
    local token = classFile and tostring(classFile):upper():gsub("%s+", "")
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.86, 0.88, 0.92
end

local CHANGELOG_VERSIONS = {
    {
        version = "1.2.35",
        summary = "Raid loot finalization hotfix",
        details = {
            "Fixed raid loot being finalized immediately when an epic item showed Binds when picked up while still having a trade window.",
            "Trade-window finalization now requires a positive trade timer to be observed first, followed by an explicit 0 second timer later.",
            "Unknown or temporarily unavailable trade timer data no longer counts as an expired trade window.",
            "Removed unsafe legacy bop_finalized events from saved loot history and blocked them from guild sync so old false finals do not come back.",
        },
    },
    {
        version = "1.2.34",
        summary = "Protected action hotfix",
        details = {
            "Removed protected automatic targeting/trade actions from Loot Council assignment reminders.",
            "Removed protected automatic trade-opening and item-placement calls from Loot Distribution awards.",
            "Loot assignment trade helpers now print safe reminders instead of asking Blizzard's secure UI to target, open trade, or move bag items automatically.",
        },
    },
    {
        version = "1.2.33",
        summary = "Loot Council self-sync hotfix",
        details = {
            "Fixed Loot Council assignment sync accepting the local player's own guild addon messages when the sender included a realm name.",
            "Prevented the Council tab from getting stuck on a partial incoming assignment stream from yourself.",
        },
    },
    {
        version = "1.2.32",
        summary = "Version detection hotfix",
        details = {
            "Re-released the 1.2.4 changes as 1.2.32 so clients on the previous 1.2.31 hotfix correctly detect this build as newer.",
            "No gameplay changes from 1.2.4.",
        },
    },
    {
        version = "1.2.4",
        summary = "Loot History lifecycle fixes and Mount Hyjal auto-marking data",
        details = {
            "Fixed vendoring received traded items so History updates to Vendored correctly.",
            "Stopped inactive loot from auto-displaying as Final after time passes.",
            "Made the Final column display only for true finalizing events.",
            "Added recipe-learned and tier-token turn-in finalization handling.",
            "Improved traded-item matching so current holders remain trackable after receiving items back.",
            "Added Mount Hyjal Trash and Bosses auto-marking categories with wave-trash NPC IDs.",
            "Added a collapsible Mount Hyjal Trash Wave Info guide with paired boss tables and right-aligned wave labels.",
        },
    },
    {
        version = "1.2.31",
        summary = "Ready Check and Gamba hotfixes",
        details = {
            "Fixed Prayer of Spirit being displayed under the wrong Ready Check buff group.",
            "Added a dedicated Spirit column with the correct icon and tooltip support.",
            "Excluded Warriors and Rogues from missing Spirit announcements, matching the Arcane Intellect mana-user filter.",
            "Kept Ready Check player rows in stable roster positions when players respond.",
            "Fixed Gamba Settings overflowing outside the addon frame at smaller window sizes.",
        },
    },
    {
        version = "1.2.3",
        summary = "Loot filtering, ready checks, attendance, invite fixes, and UI polish",
        details = {
            "Added smart usable-loot filtering in Loot and mini-loot, including tier-token filtering.",
            "Added Pass responses, live mini-loot updates, and optional local auto-open on new loot.",
            "Moved Loot options into Loot Settings and added guild-rank distribution permissions.",
            "Added a Ready Check raid tool with status monitoring and food/flask warnings.",
            "Expanded Ready Check with a compact movable monitor, remembered position, live opacity control, countdown bar, and right-click dismiss.",
            "Added smart Ready Check buff tracking for food in progress, flasks or battle plus guardian elixirs, and provider-gated raid buffs.",
            "Added Ready Check buff icons and spell tooltips for food, elixirs, Stamina, Shadow Protection, Mark/Gift, Blessings, and Intellect.",
            "Added Ready Check announcements for missing buffs/consumables, end-of-check Ready/Not Ready/AFK status, and everyone-ready reports.",
            "Added Ready Check announcement coordination so only one updated addon client reports automatically, preferring raid leader, then assists, then one fallback user.",
            "Added /iddqd check and /id check to announce configured Ready Check reports without starting a ready check.",
            "Added a Ready Check Settings popup and info tooltip matching the Loot tab help button.",
            "Expanded Attendance with auto-snapshot modes, raid-group views, class icons, and exports.",
            "Improved guild-only keyword invites by retrying pending whispers from guild roster updates and clarified the Auto-invite whispers setting.",
            "Rebuilt Overview with version check and collapsible changelog tables.",
            "Fixed Loot Settings outside-click behavior, dropdown refresh closing, dropdown corners, export modal overflow, and slider styling.",
        },
    },
    {
        version = "1.2.2",
        summary = "Loot distribution, history, and raid tools",
        details = {
            "Much faster loot distribution sync for manually added items.",
            "Added BiS responses in the Loot tab and mini-loot window.",
            "Added raid-leader loot distribution permissions for leader-only or leader-plus-assist modes.",
            "Redesigned loot history session cards with instance icons and better session labels.",
            "Kept 5-man dungeon loot private and restricted guild sharing to eligible raid sessions.",
            "Added raid tools: attendance, assignments, raid map, visual note, permissions, import/export.",
            "Fixed loot announcement quality filtering, duplicate announcements, and stack-size display.",
        },
    },
    {
        version = "1.2.1",
        summary = "Loot Distribution and raid-tool foundations",
        details = {
            "First pass of the Loot Distribution system.",
            "Added Set Role and the initial raid-tool pages.",
            "Prepared the later 1.2.2 loot distribution refinements.",
        },
    },
    {
        version = "1.2.0",
        summary = "Loot ledger and professions sync rewrite",
        details = {
            "Rebuilt raid loot tracking around an event-sourced loot ledger.",
            "Added automatic guild-scale loot sharing with throttled sync.",
            "Improved boss and instance attribution using baked loot source data.",
            "Added privacy rules so non-guild/PuG sessions stay private.",
            "Rebuilt the History panel with boss grouping and live updates.",
            "Added guild-scale professions sync and a rebuilt Professions panel.",
            "Hardened player-name normalization, sync convergence, and login performance.",
        },
    },
}

local function changelogDetailText(item)
    local lines = {}
    for _, detail in ipairs((item and item.details) or {}) do
        lines[#lines + 1] = "- " .. tostring(detail or "")
    end
    return table.concat(lines, "\n")
end

local function buildOverviewPanel(parent)
    local W = ns:GetModule("Widgets")
    local Theme = ns:GetModule("Theme")
    local f = CreateFrame("Frame", nil, parent)
    f.versionRows = {}
    f.changelogRows = {}
    f.expandedChangelog = {}

    local eyebrow = W:Eyebrow(f, "iddqd")
    eyebrow:SetPoint("TOPLEFT", 18, -18)

    local title = W:Title(f, "Overview")
    title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -4)

    local subtitle = f:CreateFontString(nil, "OVERLAY")
    Theme:Text(subtitle, "body", "dim")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Guild version readiness and recent addon changes.")

    local versionCard = W:Card(f, "overlay", true)
    versionCard:SetPoint("TOPLEFT", 18, -96)
    versionCard:SetPoint("BOTTOMLEFT", 18, 18)
    versionCard:SetPoint("TOPRIGHT", f, "TOP", -6, -96)
    versionCard:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
    f.versionCard = versionCard

    local cardTitle = W:Eyebrow(versionCard, "Version Check")
    cardTitle:SetPoint("TOPLEFT", 12, -10)

    local localVersion = versionCard:CreateFontString(nil, "OVERLAY")
    Theme:Text(localVersion, "body", "ink")
    localVersion:SetPoint("TOPLEFT", cardTitle, "BOTTOMLEFT", 0, -8)
    localVersion:SetText("Local: v" .. tostring(ns.version or "unknown"))
    f.localVersion = localVersion

    local checkBtn = W:Button(versionCard, "Check Guild Versions", 168, 24)
    checkBtn:SetTone("blue")
    checkBtn:SetPoint("TOPRIGHT", -12, -14)
    checkBtn:SetScript("OnClick", function() VersionCheck:Request() end)
    localVersion:SetPoint("RIGHT", checkBtn, "LEFT", -10, 0)

    local checked = versionCard:CreateFontString(nil, "OVERLAY")
    Theme:Text(checked, "caption", "dim")
    checked:SetPoint("TOPLEFT", cardTitle, "BOTTOMLEFT", 0, -30)
    checked:SetPoint("RIGHT", -12, 0)
    checked:SetJustifyH("LEFT")
    checked:SetText("Press the button to ask online guild members for their addon version.")
    f.checked = checked

    local header = W:ListRow(versionCard)
    header:SetPoint("TOPLEFT", versionCard, "TOPLEFT", 10, -72)
    header:SetPoint("TOPRIGHT", versionCard, "TOPRIGHT", -10, -72)
    header:SetHeight(24)
    header:SetRowVisual(1, false, "group")
    f.versionHeader = header

    header.name = header:CreateFontString(nil, "OVERLAY")
    Theme:Text(header.name, "caption", "warm")
    header.name:SetPoint("LEFT", 10, 0)
    header.name:SetText("PLAYER")

    header.version = header:CreateFontString(nil, "OVERLAY")
    Theme:Text(header.version, "caption", "warm")
    header.version:SetPoint("LEFT", 170, 0)
    header.version:SetText("VERSION")

    header.status = header:CreateFontString(nil, "OVERLAY")
    Theme:Text(header.status, "caption", "warm")
    header.status:SetPoint("LEFT", 270, 0)
    header.status:SetText("STATUS")

    local scroll, content = W:ScrollHost(versionCard)
    scroll:SetPoint("TOPLEFT", 10, -100)
    scroll:SetPoint("BOTTOMRIGHT", -16, 10)
    local bar = W:ScrollBar(scroll, content)
    f.scroll = scroll
    f.scrollBar = bar
    f.content = content

    local changelogCard = W:Card(f, "overlay", true)
    changelogCard:SetPoint("TOPLEFT", f, "TOP", 6, -96)
    changelogCard:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 18)
    changelogCard:SetPoint("TOPRIGHT", -18, -96)
    changelogCard:SetPoint("BOTTOMRIGHT", -18, 18)
    f.changelogCard = changelogCard

    local changeTitle = W:Eyebrow(changelogCard, "Changelog")
    changeTitle:SetPoint("TOPLEFT", 12, -10)

    local changeSub = changelogCard:CreateFontString(nil, "OVERLAY")
    Theme:Text(changeSub, "caption", "dim")
    changeSub:SetPoint("TOPLEFT", changeTitle, "BOTTOMLEFT", 0, -8)
    changeSub:SetPoint("RIGHT", -12, 0)
    changeSub:SetJustifyH("LEFT")
    changeSub:SetText("Click a version to expand its full notes.")

    local changeHeader = W:ListRow(changelogCard)
    changeHeader:SetPoint("TOPLEFT", 10, -72)
    changeHeader:SetPoint("TOPRIGHT", -10, -72)
    changeHeader:SetHeight(24)
    changeHeader:SetRowVisual(1, false, "group")
    f.changelogHeader = changeHeader

    changeHeader.version = changeHeader:CreateFontString(nil, "OVERLAY")
    Theme:Text(changeHeader.version, "caption", "warm")
    changeHeader.version:SetPoint("LEFT", 26, 0)
    changeHeader.version:SetText("VERSION")

    changeHeader.change = changeHeader:CreateFontString(nil, "OVERLAY")
    Theme:Text(changeHeader.change, "caption", "warm")
    changeHeader.change:SetPoint("LEFT", 90, 0)
    changeHeader.change:SetText("CHANGE")

    local changeScroll, changeContent = W:ScrollHost(changelogCard)
    changeScroll:SetPoint("TOPLEFT", 10, -100)
    changeScroll:SetPoint("BOTTOMRIGHT", -16, 10)
    local changeBar = W:ScrollBar(changeScroll, changeContent)
    f.changelogScroll = changeScroll
    f.changelogContent = changeContent
    f.changelogBar = changeBar

    local function ensureRow(index)
        local row = f.versionRows[index]
        if row then return row end
        row = W:ListRow(content)
        row:SetHeight(26)
        row.name = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.name, "body", "ink")
        row.name:SetPoint("LEFT", 10, 0)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")

        row.version = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.version, "body", "dim")
        row.version:SetPoint("LEFT", 170, 0)
        row.version:SetWidth(80)
        row.version:SetJustifyH("LEFT")

        row.status = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.status, "body", "dim")
        row.status:SetPoint("LEFT", 270, 0)
        row.status:SetWidth(150)
        row.status:SetJustifyH("LEFT")

        f.versionRows[index] = row
        return row
    end

    local function ensureChangelogRow(index)
        local row = f.changelogRows[index]
        if row and row._kind == "version" then return row end
        if row then row:Hide(); f.changelogRows[index] = nil end
        row = W:ListRow(changeContent, true)
        row._kind = "version"
        row:SetHeight(28)
        row.caret = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.caret, "body", "warm")
        row.caret:SetPoint("LEFT", 8, 0)
        row.caret:SetWidth(12)
        row.caret:SetJustifyH("CENTER")

        row.version = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.version, "body", "warm")
        row.version:SetPoint("LEFT", 26, 0)
        row.version:SetWidth(56)
        row.version:SetJustifyH("LEFT")

        row.change = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.change, "caption", "ink")
        row.change:SetPoint("LEFT", 90, 0)
        row.change:SetPoint("RIGHT", -10, 0)
        row.change:SetJustifyH("LEFT")
        row.change:SetWordWrap(true)
        row:SetScript("OnClick", function(self) if self._toggle then self:_toggle() end end)

        f.changelogRows[index] = row
        return row
    end

    local function ensureChangelogDetail(index)
        local row = f.changelogRows[index]
        if row and row._kind == "detail" then return row end
        if row then row:Hide(); f.changelogRows[index] = nil end
        row = CreateFrame("Frame", nil, changeContent)
        row._kind = "detail"
        row:SetHeight(112)
        row.text = row:CreateFontString(nil, "OVERLAY")
        Theme:Text(row.text, "caption", "dim")
        row.text:SetPoint("TOPLEFT", 18, -8)
        row.text:SetPoint("BOTTOMRIGHT", -12, 8)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("TOP")
        row.text:SetWordWrap(true)
        f.changelogRows[index] = row
        return row
    end

    local function setStatus(row, state, version)
        if state == "current" then
            row.status:SetText("Current")
            row.status:SetTextColor(0.34, 0.92, 0.55, 1)
        elseif state == "old" then
            row.status:SetText("Needs update")
            row.status:SetTextColor(0.95, 0.68, 0.30, 1)
        elseif state == "newer" then
            row.status:SetText("Newer than you")
            row.status:SetTextColor(0.42, 0.72, 1.00, 1)
        elseif VersionCheck.requestedAt then
            row.status:SetText("No response")
            row.status:SetTextColor(0.78, 0.30, 0.30, 1)
        else
            row.status:SetText("Not checked")
            row.status:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
        end
        row.version:SetText(version and version ~= "" and ("v" .. version) or "-")
    end

    function f:Refresh()
        local members = VersionCheck:OnlineGuildMembers()
        local results = VersionCheck:Results()
        self.localVersion:SetText("Local: v" .. tostring(ns.version or "unknown"))
        self.checked:SetText(VersionCheck.requestedAt and ("Last check: " .. date("%H:%M:%S", VersionCheck.requestedAt)) or "Press the button to ask online guild members for their addon version.")

        for _, row in ipairs(self.versionRows) do row:Hide() end
        for _, row in ipairs(self.changelogRows) do row:Hide() end

        local versionW = math.max(420, (self.scroll:GetWidth() or 420) - 2)
        self.content:SetWidth(versionW)

        if #members == 0 then
            local row = ensureRow(1)
            row:SetPoint("TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", 0, 0)
            row:SetWidth(versionW)
            row:SetRowVisual(1, false)
            row.name:SetText("No online guild members found")
            row.name:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            row.version:SetText("-")
            row.status:SetText("Join a guild")
            row.status:SetTextColor(Theme.color.dim[1], Theme.color.dim[2], Theme.color.dim[3], 1)
            row:Show()
            self.content:SetHeight(28)
            self.scrollBar:Update()
        else
            for i, member in ipairs(members) do
                local row = ensureRow(i)
                row:SetPoint("TOPLEFT", 0, -((i - 1) * 27))
                row:SetPoint("TOPRIGHT", 0, -((i - 1) * 27))
                row:SetWidth(versionW)
                row:SetRowVisual(i, false)
                local r, g, b = classColor(member.class)
                row.name:SetText(member.name or member.key)
                row.name:SetTextColor(r, g, b, 1)
                local result = results[member.key]
                local version = result and result.version
                setStatus(row, VersionCheck:VersionState(version), version)
                row:Show()
            end
            self.content:SetHeight(math.max(self.scroll:GetHeight() or 1, #members * 27))
            self.scrollBar:Update()
        end

        local changeW = math.max(360, (self.changelogScroll:GetWidth() or 360) - 2)
        self.changelogContent:SetWidth(changeW)
        local rendered, y = 0, 0
        for versionIndex, item in ipairs(CHANGELOG_VERSIONS) do
            rendered = rendered + 1
            local row = ensureChangelogRow(rendered)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            row:SetWidth(changeW)
            row:SetHeight(28)
            row:SetRowVisual(versionIndex, false)
            row.caret:SetText(self.expandedChangelog[item.version] and "-" or "+")
            row.version:SetText(item.version)
            row.version:SetTextColor(Theme.color.warm[1], Theme.color.warm[2], Theme.color.warm[3], 1)
            row.change:SetText(item.summary)
            row.change:SetTextColor(Theme.color.ink[1], Theme.color.ink[2], Theme.color.ink[3], 1)
            row._toggle = function()
                self.expandedChangelog[item.version] = not self.expandedChangelog[item.version]
                self:Refresh()
            end
            row:Show()
            y = y - 29

            if self.expandedChangelog[item.version] then
                rendered = rendered + 1
                local detailRow = ensureChangelogDetail(rendered)
                local detailH = item.version == "1.2.1" and 66 or 112
                detailRow:SetPoint("TOPLEFT", 0, y)
                detailRow:SetPoint("TOPRIGHT", 0, y)
                detailRow:SetWidth(changeW)
                detailRow:SetHeight(detailH)
                detailRow.text:SetText(changelogDetailText(item))
                detailRow:Show()
                y = y - detailH - 6
            end
        end
        self.changelogContent:SetHeight(math.max(self.changelogScroll:GetHeight() or 1, -y))
        self.changelogBar:Update()
    end

    VersionCheck:RegisterPanel(f)
    f:Refresh()
    return f
end

function VersionCheck:OnInit()
    registerPrefix(COMM_PREFIX)
    local Nav = ns:GetModule("Nav")
    if Nav then Nav:RegisterPanel("overview", buildOverviewPanel) end
end

function VersionCheck:OnEnable()
    if self._enabled then return end
    self._enabled = true
    registerPrefix(COMM_PREFIX)
    local Events = ns:GetModule("Events")
    if Events then
        Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
            self:OnAddonMessage(prefix, message, channel, sender)
        end, "VersionCheck")
        Events:On("GUILD_ROSTER_UPDATE", function() self:NotifyPanel() end, "VersionCheck")
    end
end
