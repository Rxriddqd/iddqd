local ADDON, ns = ...

local Gamba = ns:NewModule("GambaProvider")

local unpack = unpack or table.unpack

local PREFIX = "IDDQDGAMBA2"
local PROTOCOL_VERSION = 2
local ADDON_VERSION = "1.4.0"
local DISPLAY_VERSION = "v1.4"
local ROLL_TIMEOUT = 14 * 60
local ROLL_GRACE_TIMEOUT = 60
local MAX_SESSIONS = 250
local MAX_GAMBA_AMOUNT = 10000000

local OP = {
    VERSION = "VERSION",
    CREATE = "CREATE",
    JOIN = "JOIN",
    JOINED = "JOINED",
    LEAVE = "LEAVE",
    START = "START",
    ROLL = "ROLL",
    TIE = "TIE",
    REROLL = "REROLL",
    RESULT = "RESULT",
    RESULT_GOON = "RESULT_GOON",
    RESULT_ACK = "RESULT_ACK",
    PAYMENT = "PAYMENT",
    PAYMENT_ACK = "PAYMENT_ACK",
    CANCEL = "CANCEL",
    SYNC = "SYNC",
    LAST_CALL = "LAST_CALL",
    DEBT_SYNC = "DEBT_SYNC",
    ACCOUNT = "ACCOUNT",
}

Gamba.STATE = {
    IDLE = "idle",
    LOBBY = "lobby",
    ROLLING = "rolling",
    REROLL = "reroll",
    PAYMENT = "payment",
    COMPLETE = "complete",
    CANCELLED = "cancelled",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function Players()
    return ns.GetModule and ns:GetModule("Players") or nil
end

local function stripRealm(name)
    local players = Players()
    if players and players.ShortName then
        local short = players:ShortName(name)
        return short ~= "" and short or nil
    end
    name = trim(name)
    if name == "" then return nil end
    return name:match("^([^%-]+)") or name
end

local function currentRealmKey()
    local players = Players()
    if players and players.CurrentRealm then
        local realm = players:CurrentRealm()
        return realm ~= "" and lower(realm) or "unknown"
    end
    local realm
    if GetNormalizedRealmName then realm = GetNormalizedRealmName() end
    if (not realm or realm == "") and GetRealmName then realm = GetRealmName() end
    realm = trim(realm or "unknown"):gsub("%s+", "")
    if realm == "" then realm = "unknown" end
    return lower(realm)
end

local function tradeTargetName()
    local target = UnitName("NPC") or UnitName("target")
    if (not target or target == "") and TradeFrameRecipientNameText and TradeFrameRecipientNameText.GetText then
        target = TradeFrameRecipientNameText:GetText()
    end
    return stripRealm(target)
end

local function playerName()
    return stripRealm(UnitName("player")) or "player"
end

local function newAccountId()
    local seed = ("%s-%s-%s-%s"):format(playerName(), currentRealmKey(), tostring(time()), tostring(math.random(100000, 999999)))
    return seed:gsub("[^%w]", ""):sub(1, 48)
end

local function goldText(value)
    return ("%dg"):format(tonumber(value) or 0)
end

local function percentChance(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

local function uiGoldText(value)
    return ("%d |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"):format(tonumber(value) or 0)
end

local function setVGradient(tex, top, bottom)
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL",
            bottom[1], bottom[2], bottom[3], bottom[4] or 1,
            top[1], top[2], top[3], top[4] or 1)
        if ok then return end
    end
    tex:SetVertexColor(top[1], top[2], top[3], top[4] or 1)
end

local function now()
    return time()
end

local function splitMessage(message)
    local out = {}
    message = tostring(message or "") .. "|"
    for part in message:gmatch("(.-)|") do
        out[#out + 1] = part
        if #out > 32 then break end
    end
    return out
end

local function activeChannel(setting)
    setting = setting or "AUTO"
    if setting == "RAID" then return IsInRaid() and "RAID" or nil end
    if setting == "PARTY" then return IsInGroup() and "PARTY" or nil end
    if setting == "GUILD" then return (IsInGuild and IsInGuild()) and "GUILD" or nil end
    if setting == "ADDON" then
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        if IsInGuild and IsInGuild() then return "GUILD" end
        return nil
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    if IsInGuild and IsInGuild() then return "GUILD" end
    return nil
end

local function normalizeChannel(channel)
    channel = tostring(channel or ""):upper()
    if channel == "RAID_LEADER" then return "RAID" end
    if channel == "PARTY_LEADER" then return "PARTY" end
    return channel
end

local function groupedChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function groupedChannelWith(name)
    name = lower(stripRealm(name))
    if not name or name == "" then return nil end
    if IsInRaid and IsInRaid() then
        local total = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, total do
            local unitName = UnitName("raid" .. i)
            if unitName and lower(stripRealm(unitName)) == name then return "RAID" end
        end
        return nil
    end
    if IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unitName = UnitName("party" .. i)
            if unitName and lower(stripRealm(unitName)) == name then return "PARTY" end
        end
    end
    return nil
end

local function sendAddon(prefix, message, channel, target)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(prefix, message, channel, target, "NORMAL") end
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

local function rollPattern(message)
    if not message then return nil end
    local name, roll, minRoll, maxRoll = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
    if not name then return nil end
    return stripRealm(name), tonumber(roll), tonumber(minRoll), tonumber(maxRoll)
end

local function countTable(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function debtIdFor(sessionId, debtor, creditor)
    debtor = stripRealm(debtor) or "unknown"
    creditor = stripRealm(creditor) or "unknown"
    return ("%s~%s~%s"):format(tostring(sessionId or ""), lower(debtor), lower(creditor))
end

local function debtBelongsToSession(debt, sessionId)
    if not debt or not sessionId then return false end
    if debt.sessionId == sessionId then return true end
    return debt.parentSessionId == sessionId
end

local function serializeGoonDebts(debts)
    local out = {}
    for _, debt in ipairs(debts or {}) do
        out[#out + 1] = table.concat({
            debt.debtor or "",
            tostring(debt.roll or 0),
            tostring(debt.amount or 0),
        }, ":")
    end
    return table.concat(out, ",")
end

local function parseGoonDebts(value)
    local debts = {}
    for part in tostring(value or ""):gmatch("([^,;]+)") do
        local debtor, roll, amount = part:match("^([^:]+):(%d+):(%d+)$")
        if debtor then
            debts[#debts + 1] = {
                debtor = stripRealm(debtor),
                roll = tonumber(roll) or 0,
                amount = tonumber(amount) or 0,
            }
        end
    end
    return debts
end

local function compareVersion(a, b)
    local function parts(value)
        local out = {}
        for part in tostring(value or ""):gmatch("(%d+)") do out[#out + 1] = tonumber(part) or 0 end
        return out
    end
    local av, bv = parts(a), parts(b)
    for i = 1, math.max(#av, #bv, 3) do
        local left, right = av[i] or 0, bv[i] or 0
        if left > right then return 1 end
        if left < right then return -1 end
    end
    return 0
end

local function sharedMediaSound(name)
    if not (LibStub and name and name ~= "") then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok or not lib or not lib.Fetch then return nil end
    local fetchedOk, sound = pcall(lib.Fetch, lib, "sound", name, true)
    return fetchedOk and sound or nil
end

local function configuredSoundValue(key)
    key = tostring(key or "")
    if key == "" or key == "NONE" then return nil end
    local sharedName = key:match("^LSM:(.+)$")
    if sharedName then return sharedMediaSound(sharedName), true end
    if not SOUNDKIT then return nil end
    return SOUNDKIT[key], false
end

function Gamba:DefaultDB()
    return {
        version = 1,
        current = nil,
        sessions = {},
        balances = {},
        debts = {},
        remoteAccounts = {},
        remoteAccountByChar = {},
        settings = {
            defaultAmount = 100,
            channel = "AUTO",
            announce = true,
            addonNotices = false,
            autoRoll = false,
            autoJoin = false,
            accountMode = false,
            accountModeDefaulted = true,
            accountId = "",
            accountCharacters = {},
            accountRealms = {},
            lobbyTimeoutEnabled = true,
            lobbyTimeoutMinutes = 10,
            goonEnabled = false,
            goonChance = 5,
            soundNew = "NONE",
            soundWon = "NONE",
            soundLost = "NONE",
        },
    }
end

local function ensure(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ensure(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Gamba:Store()
    local DB = ns:GetModule("DB")
    local db = DB and DB.db
    if type(db) ~= "table" then return self:DefaultDB() end
    if type(db.gamba) ~= "table" then db.gamba = self:DefaultDB() end
    ensure(db.gamba, self:DefaultDB())
    local settings = db.gamba.settings or {}
    if settings.accountModeDefaulted ~= true then settings.accountModeDefaulted = true end
    if not settings.accountId or settings.accountId == "" then settings.accountId = newAccountId() end
    return db.gamba
end

function Gamba:Settings()
    return self:Store().settings
end

Gamba.version = ADDON_VERSION
Gamba.displayVersion = DISPLAY_VERSION

function Gamba:RegisterAccountCharacter(name)
    name = stripRealm(name or playerName())
    if not name or name == "" or lower(name) == "player" then return false end
    local settings = self:Settings()
    settings.accountCharacters = settings.accountCharacters or {}
    settings.accountRealms = settings.accountRealms or {}
    local realm = currentRealmKey()
    settings.accountRealms[realm] = settings.accountRealms[realm] or {}
    for key, value in pairs(settings.accountCharacters or {}) do
        settings.accountRealms[realm][key] = settings.accountRealms[realm][key] or value
    end
    settings.accountCharacters[lower(name)] = name
    settings.accountRealms[realm][lower(name)] = name
    return true
end

function Gamba:IsAccountCharacter(name)
    name = stripRealm(name)
    if not name then return false end
    if lower(name) == lower(playerName()) then return true end
    local settings = self:Settings()
    local realmChars = (settings.accountRealms or {})[currentRealmKey()]
    if realmChars and realmChars[lower(name)] ~= nil then return true end
    return false
end

function Gamba:IsScopedCharacter(name)
    if self:Settings().accountMode == true then return self:IsAccountCharacter(name) end
    return lower(stripRealm(name)) == lower(playerName())
end

function Gamba:ScopeName()
    return self:Settings().accountMode == true and "Account" or "Character"
end

function Gamba:AccountToken()
    return "acct:" .. tostring(self:Settings().accountId or "")
end

function Gamba:RegisterRemoteAccount(character, token, rosterCsv)
    character = stripRealm(character)
    token = tostring(token or "")
    local accountId = token:match("^acct:([%w_%-]+)$")
    if not character or not accountId or accountId == "" or accountId == tostring(self:Settings().accountId or "") then return false end
    local store = self:Store()
    store.remoteAccountByChar = store.remoteAccountByChar or {}
    store.remoteAccounts = store.remoteAccounts or {}
    local key = lower(character)
    local account = store.remoteAccounts[accountId] or { id = accountId, chars = {}, label = character }
    account.chars = account.chars or {}
    account.chars[key] = character
    account.label = account.label or character
    for rosterName in tostring(rosterCsv or ""):gmatch("([^~]+)") do
        rosterName = stripRealm(rosterName)
        if rosterName and rosterName ~= "" then
            local rosterKey = lower(rosterName)
            account.chars[rosterKey] = rosterName
            store.remoteAccountByChar[rosterKey] = accountId
        end
    end
    store.remoteAccounts[accountId] = account
    store.remoteAccountByChar[key] = accountId
    return true
end

function Gamba:RemoteAccountId(character)
    character = stripRealm(character)
    if not character then return nil end
    local map = self:Store().remoteAccountByChar or {}
    return map[lower(character)]
end

function Gamba:RemoteAccountKey(character)
    local accountId = self:RemoteAccountId(character)
    if accountId then return "account:" .. accountId end
    return "char:" .. lower(stripRealm(character) or "")
end

function Gamba:RemoteAccountLabel(character)
    local accountId = self:RemoteAccountId(character)
    if accountId then
        local account = (self:Store().remoteAccounts or {})[accountId]
        if account and account.label then return account.label end
    end
    return stripRealm(character) or tostring(character or "?")
end

function Gamba:PlayConfiguredSound(kind)
    local settings = self:Settings()
    local key = kind == "new" and settings.soundNew or kind == "won" and settings.soundWon or settings.soundLost
    return self:PreviewSound(key)
end

function Gamba:PreviewSound(key)
    local sound, isFile = configuredSoundValue(key)
    if not sound then return false end
    if isFile and PlaySoundFile then
        pcall(PlaySoundFile, sound, "Master")
        return true
    end
    if PlaySound then
        pcall(PlaySound, sound, "Master")
        return true
    end
    return false
end

function Gamba:PlayNewGameSound(session)
    if not session or not session.id then return end
    self.playedSounds = self.playedSounds or {}
    local marker = session.id .. ":new"
    if self.playedSounds[marker] then return end
    self.playedSounds[marker] = true
    self:PlayConfiguredSound("new")
end

function Gamba:PlayResultSound(session)
    local result = session and session.result
    if not result or not session.id then return end
    local me = lower(playerName())
    local kind
    if lower(stripRealm(result.winner)) == me then kind = "won"
    elseif lower(stripRealm(result.loser)) == me then kind = "lost"
    else
        for _, debt in ipairs(result.debts or {}) do
            if lower(stripRealm(debt.debtor)) == me and (tonumber(debt.amount) or 0) > 0 then
                kind = "lost"
                break
            end
        end
    end
    if not kind then return end
    self.playedSounds = self.playedSounds or {}
    local marker = session.id .. ":" .. kind
    if self.playedSounds[marker] then return end
    self.playedSounds[marker] = true
    self:PlayConfiguredSound(kind)
end

function Gamba:Current()
    return self:Store().current
end

function Gamba:CancelMessage(reason)
    if reason == "no_players_timeout" then return "[Gamba] Gamba canceled: no players joined within 2 minutes." end
    if reason == "lobby_timeout" then return "[Gamba] Gamba canceled: lobby timed out." end
    if reason == "not_enough_rolls" then return "[Gamba] Gamba canceled: not enough players rolled." end
    return "[Gamba] Gamba canceled."
end

function Gamba:CancelNoJoinTimer()
    if self.noJoinTimer and self.noJoinTimer.Cancel then self.noJoinTimer:Cancel() end
    self.noJoinTimer = nil
end

function Gamba:CancelLobbyTimers()
    self:CancelNoJoinTimer()
    if self.lobbyTimer and self.lobbyTimer.Cancel then self.lobbyTimer:Cancel() end
    self.lobbyTimer = nil
end

function Gamba:CancelRollTimers()
    if self.rollTimer and self.rollTimer.Cancel then self.rollTimer:Cancel() end
    self.rollTimer = nil
    if self.rollExpireTimer and self.rollExpireTimer.Cancel then self.rollExpireTimer:Cancel() end
    self.rollExpireTimer = nil
    if self.rerollTimer and self.rerollTimer.Cancel then self.rerollTimer:Cancel() end
    self.rerollTimer = nil
    if self.rerollExpireTimer and self.rerollExpireTimer.Cancel then self.rerollExpireTimer:Cancel() end
    self.rerollExpireTimer = nil
end

function Gamba:ScheduleNoJoinTimeout(session)
    self:CancelNoJoinTimer()
    if not (C_Timer and C_Timer.NewTimer) then return end
    if not session or session.state ~= self.STATE.LOBBY or lower(session.host) ~= lower(playerName()) then return end
    local sessionId = session.id
    self.noJoinTimer = C_Timer.NewTimer(120, function()
        local current = self:Current()
        if current and current.id == sessionId and current.state == self.STATE.LOBBY and self:IsHost() and countTable(current.players) <= 1 then
            self:Cancel("no_players_timeout")
        end
    end)
end

function Gamba:StartLobbyTimers(session)
    self:CancelLobbyTimers()
    if not session or session.state ~= self.STATE.LOBBY or lower(session.host) ~= lower(playerName()) then return end
    self:ScheduleNoJoinTimeout(session)
    local settings = self:Settings()
    local minutes = math.max(1, tonumber(settings.lobbyTimeoutMinutes) or 10)
    if settings.lobbyTimeoutEnabled == false or not (C_Timer and C_Timer.NewTimer) then return end
    local sessionId = session.id
    self.lobbyTimer = C_Timer.NewTimer(minutes * 60, function()
        local current = self:Current()
        if current and current.id == sessionId and current.state == self.STATE.LOBBY and self:IsHost() and countTable(current.players) > 1 then
            self:Cancel("lobby_timeout")
        end
    end)
end

function Gamba:SetCurrent(session)
    self:CancelLobbyTimers()
    self:CancelRollTimers()
    self:Store().current = session
    if session and session.state == self.STATE.LOBBY and lower(session.host) == lower(playerName()) then
        self:StartLobbyTimers(session)
    end
    self:Notify()
end

function Gamba:Channel()
    local session = self:Current()
    if session and session.transportChannel then return normalizeChannel(session.transportChannel) end
    return activeChannel((session and session.channel) or self:Settings().channel)
end

function Gamba:ChannelMode()
    local session = self:Current()
    return (session and session.channel) or self:Settings().channel or "AUTO"
end

function Gamba:SessionTransport(session)
    session = session or self:Current()
    if session and session.transportChannel then return normalizeChannel(session.transportChannel) end
    return normalizeChannel(activeChannel((session and session.channel) or self:Settings().channel))
end

function Gamba:ShouldAcceptSessionChannel(gameChannel, transportChannel)
    transportChannel = normalizeChannel(transportChannel)
    if transportChannel == "WHISPER" then return true end
    local setting = tostring(self:Settings().channel or "AUTO"):upper()
    local grouped = groupedChannel()

    if grouped and transportChannel == "GUILD" and setting ~= "GUILD" then
        return false
    end

    if setting == "RAID" then return transportChannel == "RAID" end
    if setting == "PARTY" then return transportChannel == "PARTY" end
    if setting == "GUILD" then return transportChannel == "GUILD" end
    if setting == "ADDON" then return true end

    return transportChannel ~= "" and transportChannel ~= nil
end

function Gamba:ShouldUseChatChannel(session, channel)
    session = session or self:Current()
    if not session or session.channel == "ADDON" then return false end
    local expected = self:SessionTransport(session)
    local actual = normalizeChannel(channel)
    return expected ~= "" and expected == actual
end

function Gamba:Broadcast(op, ...)
    local channel = self:Channel()
    if not channel then return false end
    local parts = { tostring(PROTOCOL_VERSION), op }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)) or "")
    end
    parts[#parts + 1] = self:AccountToken()
    sendAddon(PREFIX, table.concat(parts, "|"), channel)
    return true
end

function Gamba:SendToPlayer(target, op, ...)
    target = stripRealm(target)
    if not target or target == "" then return false end
    local parts = { tostring(PROTOCOL_VERSION), op }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)) or "")
    end
    parts[#parts + 1] = self:AccountToken()
    sendAddon(PREFIX, table.concat(parts, "|"), "WHISPER", target)
    return true
end

function Gamba:SendVersion(channel, target)
    channel = channel or ((IsInGuild and IsInGuild()) and "GUILD" or nil)
    if not channel then return false end
    local parts = { tostring(PROTOCOL_VERSION), OP.VERSION, ADDON_VERSION, DISPLAY_VERSION, self.addonId or ADDON, self:AccountToken() }
    sendAddon(PREFIX, table.concat(parts, "|"), channel, target)
    return true
end

function Gamba:AnnounceVersion()
    if IsInGuild and IsInGuild() then self:SendVersion("GUILD") end
end

function Gamba:HandleVersion(sender, version, displayVersion, addonId, channel)
    sender = stripRealm(sender)
    if not sender or lower(sender) == lower(playerName()) then return end
    version = tostring(version or "")
    if version == "" then return end
    local cmp = compareVersion(version, ADDON_VERSION)
    if cmp > 0 then
        local key = version
        self.versionWarnings = self.versionWarnings or {}
        if self.versionWarnings[key] then return end
        self.versionWarnings[key] = true
        ns:Print(("Gamba %s is available. %s is using %s. You are on %s."):format(displayVersion or version, sender, displayVersion or version, DISPLAY_VERSION), "warning")
    elseif cmp < 0 and channel ~= "WHISPER" then
        self.versionReplies = self.versionReplies or {}
        if self.versionReplies[sender] then return end
        self.versionReplies[sender] = true
        self:SendVersion("WHISPER", sender)
    end
end

local function joinPlayers(players)
    local names = sortedKeys(players)
    return table.concat(names, ",")
end

local function joinRolls(rolls)
    local out = {}
    for _, name in ipairs(sortedKeys(rolls)) do out[#out + 1] = name .. ":" .. tostring(rolls[name]) end
    return table.concat(out, ",")
end

local function joinSet(values)
    local out = {}
    for name in pairs(values or {}) do out[#out + 1] = stripRealm(name) or name end
    table.sort(out)
    return table.concat(out, "~")
end

local function splitCsv(value)
    local out = {}
    for part in tostring(value or ""):gmatch("([^,]+)") do out[#out + 1] = part end
    return out
end

local function splitTilde(value)
    local out = {}
    for part in tostring(value or ""):gmatch("([^~]+)") do out[#out + 1] = part end
    return out
end

function Gamba:AccountRosterCsv()
    local settings = self:Settings()
    local realmChars = (settings.accountRealms or {})[currentRealmKey()] or {}
    local names = {}
    names[lower(playerName())] = playerName()
    for key, value in pairs(realmChars) do names[key] = value end
    local out = {}
    for _, name in pairs(names) do out[#out + 1] = stripRealm(name) or name end
    table.sort(out)
    local packed = {}
    local length = 0
    for _, name in ipairs(out) do
        local nextLength = length + #name + (length > 0 and 1 or 0)
        if nextLength > 180 then break end
        packed[#packed + 1] = name
        length = nextLength
    end
    return table.concat(packed, "~")
end

local function ackHas(acks, name)
    name = lower(stripRealm(name))
    if name == "" then return false end
    for actor in pairs(acks or {}) do
        if lower(stripRealm(actor)) == name then return true end
    end
    return false
end

function Gamba:BroadcastState()
    local session = self:Current()
    if not session then return false end
    local result = session.result
    local resultData = ""
    if result then
        resultData = table.concat({
            result.winner or "",
            result.winnerRoll or "",
            result.loser or "",
            result.loserRoll or "",
            result.owed or "",
            result.paid and "1" or "0",
            result.verificationStatus or "",
            result.paymentStatus or "",
            joinSet(result.verifiedBy),
            joinSet(result.paymentAcks),
            result.mode or session.mode or "",
        }, ",")
    end
    return self:Broadcast(OP.SYNC, "STATE", session.id, session.state, session.host, session.amount, session.channel, joinPlayers(session.players), joinRolls(session.rolls), resultData, session.mode or "", session.goonChance or 0)
end

function Gamba:BroadcastAccount(target)
    local accountId = tostring(self:Settings().accountId or "")
    if accountId == "" then return false end
    if target then return self:SendToPlayer(target, OP.ACCOUNT, accountId, self:AccountRosterCsv()) end
    return self:Broadcast(OP.ACCOUNT, accountId, self:AccountRosterCsv())
end

function Gamba:RequestSync()
    return self:Broadcast(OP.SYNC, "REQ", playerName())
end

function Gamba:RequestDebtSync(target)
    target = stripRealm(target)
    if not target then return false end
    return self:SendToPlayer(target, OP.DEBT_SYNC, "REQ", playerName())
end

function Gamba:BroadcastDebtSync(target)
    local targetName = stripRealm(target)
    local targetAccountKey = targetName and self:RemoteAccountKey(targetName) or nil
    for sessionId, debt in pairs(self:Store().debts or {}) do
        if targetName then
            local debtor = stripRealm(debt.debtor)
            local creditor = stripRealm(debt.creditor)
            local involvesMe = self:IsScopedCharacter(debtor) or self:IsScopedCharacter(creditor)
            local involvesTarget = lower(debtor) == lower(targetName) or lower(creditor) == lower(targetName)
            if not involvesTarget and targetAccountKey then
                involvesTarget = self:RemoteAccountKey(debtor) == targetAccountKey or self:RemoteAccountKey(creditor) == targetAccountKey
            end
            if not (involvesMe and involvesTarget) then
                debt = nil
            end
        end
        if debt then
            local args = {
                "ROW",
                sessionId,
                debt.debtor or "",
                debt.creditor or "",
                debt.amount or 0,
                debt.status or "",
                debt.verificationStatus or "",
                debt.paymentStatus or "",
                debt.paidAmount or 0,
                debt.createdAt or 0,
                debt.updatedAt or debt.createdAt or 0,
            }
            if targetName then self:SendToPlayer(targetName, OP.DEBT_SYNC, unpack(args)) else self:Broadcast(OP.DEBT_SYNC, unpack(args)) end
        end
    end
    if targetName then self:SendToPlayer(targetName, OP.DEBT_SYNC, "DONE", playerName()) else self:Broadcast(OP.DEBT_SYNC, "DONE", playerName()) end
end

function Gamba:MergeDebtSyncRow(parts, sender)
    local sessionId = parts[4]
    if not sessionId or sessionId == "" then return false end
    local debtor = stripRealm(parts[5]) or parts[5]
    local creditor = stripRealm(parts[6]) or parts[6]
    sender = stripRealm(sender)
    if sender then
        local involvesMe = self:IsScopedCharacter(debtor) or self:IsScopedCharacter(creditor)
        local involvesSender = lower(debtor) == lower(sender) or lower(creditor) == lower(sender)
        local senderAccountKey = self:RemoteAccountKey(sender)
        if not involvesSender and senderAccountKey then
            involvesSender = self:RemoteAccountKey(debtor) == senderAccountKey or self:RemoteAccountKey(creditor) == senderAccountKey
        end
        if not (involvesMe and involvesSender) then return false end
    end
    local incomingUpdatedAt = tonumber(parts[13]) or tonumber(parts[12]) or now()
    local incomingStatus = parts[8] ~= "" and parts[8] or "unpaid"
    local debts = self:Store().debts
    local current = debts[sessionId]
    local currentUpdatedAt = current and tonumber(current.updatedAt or current.createdAt or 0) or 0
    if current and current.status == "paid" and incomingStatus ~= "paid" then return false end
    if current and currentUpdatedAt > incomingUpdatedAt and incomingStatus ~= "paid" then return false end

    local debt = current or { sessionId = sessionId, resultAcks = {}, paymentAcks = {}, events = {} }
    debt.sessionId = sessionId
    debt.debtor = debtor
    debt.creditor = creditor
    debt.amount = tonumber(parts[7]) or 0
    debt.status = incomingStatus
    debt.verificationStatus = parts[9] ~= "" and parts[9] or debt.verificationStatus or "pending"
    debt.paymentStatus = parts[10] ~= "" and parts[10] or debt.paymentStatus or debt.status
    debt.paidAmount = tonumber(parts[11]) or debt.paidAmount or 0
    debt.createdAt = tonumber(parts[12]) or debt.createdAt or incomingUpdatedAt
    debt.updatedAt = incomingUpdatedAt
    debt.resultAcks = debt.resultAcks or {}
    debt.paymentAcks = debt.paymentAcks or {}
    debt.events = debt.events or {}
    debts[sessionId] = debt
    local entry = self:FindSessionEntry(sessionId)
    if entry then
        entry.paid = debt.status == "paid"
        entry.paymentStatus = debt.paymentStatus
        entry.verified = debt.verificationStatus == "verified"
        entry.verificationStatus = debt.verificationStatus
        entry.paidAmount = debt.paidAmount
    end
    local session = self:Current()
    if session and session.id == sessionId and session.result then
        session.result.paid = debt.status == "paid"
        session.result.paymentStatus = debt.paymentStatus
        session.result.verified = debt.verificationStatus == "verified"
        session.result.verificationStatus = debt.verificationStatus
        session.result.paidAmount = debt.paidAmount
        if debt.status == "paid" then session.state = self.STATE.COMPLETE end
    end
    return true
end

function Gamba:Announce(message)
    if self:ChannelMode() == "ADDON" then
        self:AddonNotice(message)
        return
    end
    if self:Settings().announce == false then return end
    local channel = self:Channel()
    if channel then SendChatMessage(message, channel) end
end

function Gamba:AddonNotice(message)
    if self:Settings().addonNotices ~= true then return end
    message = tostring(message or ""):gsub("^%[Gamba%]%s*", ""):gsub("^%[iddqd%]%s*", "")
    ns:Print(message, "success")
end

function Gamba:IsHost()
    local session = self:Current()
    return session and lower(session.host) == lower(playerName())
end

function Gamba:AutoJoinSession(session)
    if not session or self:Settings().autoJoin ~= true then return false end
    local me = playerName()
    if lower(session.host or "") == lower(me) or (session.players and session.players[me]) then return false end
    if session.channel == "ADDON" then
        self:BroadcastAccount(session.host)
        return self:SendToPlayer(session.host, OP.JOIN, session.id, me)
    end
    local channel = self:SessionTransport(session)
    if channel and channel ~= "" then
        self:BroadcastAccount()
        SendChatMessage("1", channel)
        return true
    end
    return self:Broadcast(OP.JOIN, session.id, me)
end

function Gamba:CreateSession(amount, channel)
    amount = math.min(MAX_GAMBA_AMOUNT, math.max(2, math.floor(tonumber(amount) or self:Settings().defaultAmount or 100)))
    channel = channel or self:Settings().channel or "AUTO"
    local goonChance = self:Settings().goonEnabled == true and percentChance(self:Settings().goonChance) or 0
    local transportChannel = activeChannel(channel)
    if not transportChannel then
        ns:Print("No usable party, raid, or guild channel for Gamba.", "warning")
        return false
    end

    local host = playerName()
    local session = {
        id = ("%s-%d"):format(host, now()),
        state = self.STATE.LOBBY,
        host = host,
        amount = amount,
        mode = "classic",
        goonChance = goonChance,
        goonMode = false,
        channel = channel,
        transportChannel = transportChannel,
        createdAt = now(),
        updatedAt = now(),
        players = {},
        rolls = {},
    }
    session.players[host] = { name = host, joinedAt = now() }
    self:SetCurrent(session)
    self:BroadcastAccount()
    self:PlayNewGameSound(session)
    self:Broadcast(OP.CREATE, session.id, host, amount, channel, goonChance)
    local goonText = goonChance > 0 and (" GOON chance: " .. tostring(goonChance) .. "%.") or ""
    self:Announce(("[Gamba] %s started a %s Gamba.%s Type 1 to join, -1 to leave."):format(host, goldText(amount), goonText))
    return true
end

function Gamba:AddPlayer(name, remote)
    local session = self:Current()
    name = stripRealm(name)
    if not session or not name or session.state ~= self.STATE.LOBBY then return false end
    if session.players[name] then return false end
    session.players[name] = { name = name, joinedAt = now() }
    session.updatedAt = now()
    if self:IsHost() and countTable(session.players) > 1 then self:CancelNoJoinTimer() end
    if self:IsHost() and not remote then self:Broadcast(OP.JOINED, session.id, name) end
    self:Notify()
    return true
end

function Gamba:RemovePlayer(name, remote)
    local session = self:Current()
    name = stripRealm(name)
    if not session or not name or session.state ~= self.STATE.LOBBY then return false end
    local existed = session.players[name] ~= nil
    session.players[name] = nil
    session.updatedAt = now()
    if self:IsHost() and not remote then self:Broadcast(OP.LEAVE, session.id, name) end
    if self:IsHost() and existed and lower(name) ~= lower(session.host) then
        self:Announce(("[Gamba] %s left the Gamba."):format(name))
        if countTable(session.players) <= 1 then self:ScheduleNoJoinTimeout(session) end
    end
    self:Notify()
    return true
end

function Gamba:SendLobbyCommand(command)
    local session = self:Current()
    if not session or session.state ~= self.STATE.LOBBY then return false end
    if session.channel == "ADDON" then
        local op = command == "-1" and OP.LEAVE or OP.JOIN
        if session.host and lower(session.host) ~= lower(playerName()) then
            self:BroadcastAccount(session.host)
            return self:SendToPlayer(session.host, op, session.id, playerName())
        end
        return self:Broadcast(op, session.id, playerName())
    end
    local channel = self:SessionTransport(session)
    if channel and channel ~= "" then
        self:BroadcastAccount()
        SendChatMessage(command, channel)
        return true
    end
    return self:Broadcast(command == "-1" and OP.LEAVE or OP.JOIN, session.id, playerName())
end

function Gamba:Join()
    local session = self:Current()
    if not session or session.state ~= self.STATE.LOBBY then return false end
    local me = playerName()
    if self:IsHost() then
        self:AddPlayer(me)
    else
        return self:SendLobbyCommand("1")
    end
    return true
end

function Gamba:Leave()
    local session = self:Current()
    if not session then return false end
    local me = playerName()
    if self:IsHost() then
        self:RemovePlayer(me)
    else
        return self:SendLobbyCommand("-1")
    end
    return true
end

function Gamba:StartRolling()
    local session = self:Current()
    if not session or session.state ~= self.STATE.LOBBY or not self:IsHost() then return false end
    if countTable(session.players) < 2 then
        ns:Print("Need at least two players.", "warning")
        return false
    end
    session.state = self.STATE.ROLLING
    session.goonChance = percentChance(session.goonChance)
    session.goonMode = session.goonChance > 0 and math.random(1, 100) <= session.goonChance or false
    session.mode = session.goonMode and "goon" or "classic"
    session.rolls = {}
    session.rollStartedAt = now()
    session.updatedAt = now()
    self:CancelLobbyTimers()
    self:Broadcast(OP.START, session.id, session.mode)
    if session.goonMode then
        self:Announce(("[Gamba] GOON MODE! Highest roller wins. Everyone else owes the difference. /roll %d now."):format(session.amount))
    else
        self:Announce(("[Gamba] Gamba rolling started. /roll %d now."):format(session.amount))
    end
    if self.rollTimer then self.rollTimer:Cancel() end
    self.rollTimer = C_Timer.NewTimer(ROLL_TIMEOUT, function() self:WarnMissingRolls() end)
    if self.rollExpireTimer then self.rollExpireTimer:Cancel() end
    self.rollExpireTimer = C_Timer.NewTimer(ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT, function() self:ExpireMissingRolls() end)
    self:AutoRollIfReady(0.45)
    self:Notify()
    return true
end

function Gamba:CanRoll(name)
    local session = self:Current()
    name = stripRealm(name or playerName())
    if not session or not name then return false end
    if session.state == self.STATE.ROLLING then
        return session.players and session.players[name] and not (session.rolls and session.rolls[name])
    end
    if session.state == self.STATE.REROLL then
        local reroll = session.reroll
        if not reroll or (reroll.rolls and reroll.rolls[name]) then return false end
        for _, player in ipairs(reroll.players or {}) do
            if lower(stripRealm(player)) == lower(name) then return true end
        end
    end
    return false
end

function Gamba:Roll()
    local session = self:Current()
    if not session or not self:CanRoll(playerName()) then return false end
    RandomRoll(1, tonumber(session.amount) or 100)
    return true
end

function Gamba:AutoRollIfReady(delay)
    if self:Settings().autoRoll ~= true then return false end
    local session = self:Current()
    if not session or not self:CanRoll(playerName()) then return false end
    local marker = ("%s:%s"):format(session.id or "unknown", session.state or "unknown")
    if self.autoRollPending == marker then return false end
    self.autoRollPending = marker
    C_Timer.After(delay or 0.45, function()
        if self.autoRollPending ~= marker then return end
        self.autoRollPending = nil
        if self:Settings().autoRoll == true and self:CanRoll(playerName()) then
            self:Roll()
        end
    end)
    return true
end

function Gamba:LastCall()
    local session = self:Current()
    if not session or session.state ~= self.STATE.LOBBY or not self:IsHost() then return false end
    if session.channel == "ADDON" then self:Broadcast(OP.LAST_CALL, session.id, session.amount) end
    self:Announce(("[Gamba] Last call for %s Gamba. Type 1 to join, -1 to leave."):format(goldText(session.amount)))
    return true
end

function Gamba:RecordRoll(name, value, remote)
    local session = self:Current()
    name = stripRealm(name)
    value = tonumber(value)
    if not session or not name or not value then return false end
    if session.state == self.STATE.REROLL then return self:RecordReroll(name, value, remote) end
    if session.state ~= self.STATE.ROLLING or not session.players[name] or session.rolls[name] then return false end
    session.rolls[name] = value
    session.updatedAt = now()
    if not remote then
        local me = playerName()
        if self:IsHost() then
            self:Broadcast(OP.ROLL, session.id, name, value)
        elseif lower(name) == lower(me) then
            if session.channel == "ADDON" and session.host then
                self:SendToPlayer(session.host, OP.ROLL, session.id, name, value)
            else
                self:Broadcast(OP.ROLL, session.id, name, value)
            end
        end
    elseif self:IsHost() then
        self:Broadcast(OP.ROLL, session.id, name, value)
    end
    self:Notify()
    self:CheckRollsComplete()
    return true
end

function Gamba:CheckRollsComplete()
    local session = self:Current()
    if not session or not self:IsHost() then return end
    for name in pairs(session.players) do
        if not session.rolls[name] then return end
    end
    self:CancelRollTimers()
    self:CalculateResult()
end

local function extrema(rolls)
    local high, low, highs, lows = -1, math.huge, {}, {}
    for name, roll in pairs(rolls or {}) do
        if roll > high then high = roll; highs = { name }
        elseif roll == high then highs[#highs + 1] = name end
        if roll < low then low = roll; lows = { name }
        elseif roll == low then lows[#lows + 1] = name end
    end
    table.sort(highs)
    table.sort(lows)
    return high, low, highs, lows
end

function Gamba:StartTie(tieType, players, lockedWinner, lockedLoser)
    local session = self:Current()
    if not session then return end
    self:CancelRollTimers()
    session.state = self.STATE.REROLL
    session.reroll = {
        type = tieType,
        players = players,
        rolls = {},
        lockedWinner = lockedWinner,
        lockedLoser = lockedLoser,
    }
    session.rerollStartedAt = now()
    session.updatedAt = now()
    self:Broadcast(OP.TIE, session.id, tieType, table.concat(players, ","), lockedWinner or "", lockedLoser or "")
    self:Announce(("[Gamba] Tie detected. Reroll: %s."):format(table.concat(players, ", ")))
    if C_Timer and C_Timer.NewTimer then
        self.rerollTimer = C_Timer.NewTimer(ROLL_TIMEOUT, function() self:WarnMissingRerolls() end)
        self.rerollExpireTimer = C_Timer.NewTimer(ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT, function() self:ExpireMissingRerolls() end)
    end
    self:AutoRollIfReady(0.45)
    self:Notify()
end

function Gamba:CalculateResult()
    local session = self:Current()
    if not session or not self:IsHost() then return end
    local high, low, highs, lows = extrema(session.rolls)
    if #highs == 0 or #lows == 0 then return end
    if session.goonMode or session.mode == "goon" then
        if #highs > 1 then self:StartTie("goon_high", highs); return end
        self:FinalizeGoonResult(highs[1], high)
        return
    end
    if #highs > 1 and #lows > 1 and high == low then
        local players = sortedKeys(session.rolls)
        self:StartTie("full", players)
        return
    end
    if #highs > 1 then self:StartTie("high", highs, nil, lows[1]); return end
    if #lows > 1 then self:StartTie("low", lows, highs[1], nil); return end
    self:FinalizeResult(highs[1], high, lows[1], low)
end

function Gamba:RecordReroll(name, value, remote)
    local session = self:Current()
    local reroll = session and session.reroll
    if not reroll then return false end
    name = stripRealm(name)
    local allowed = false
    for _, candidate in ipairs(reroll.players or {}) do
        if lower(candidate) == lower(name) then allowed = true; break end
    end
    if not allowed or reroll.rolls[name] then return false end
    reroll.rolls[name] = tonumber(value)
    if not remote then
        local me = playerName()
        if self:IsHost() then
            self:Broadcast(OP.REROLL, session.id, name, value)
        elseif lower(name) == lower(me) then
            if session.channel == "ADDON" and session.host then
                self:SendToPlayer(session.host, OP.REROLL, session.id, name, value)
            else
                self:Broadcast(OP.REROLL, session.id, name, value)
            end
        end
    elseif self:IsHost() then
        self:Broadcast(OP.REROLL, session.id, name, value)
    end
    self:Notify()
    for _, candidate in ipairs(reroll.players or {}) do if not reroll.rolls[candidate] then return true end end
    if self:IsHost() then self:CalculateRerollResult() end
    return true
end

function Gamba:CalculateRerollResult()
    local session = self:Current()
    local reroll = session and session.reroll
    if not reroll then return end
    local high, low, highs, lows = extrema(reroll.rolls)
    if #highs == 0 or #lows == 0 then
        if self:IsHost() then self:Cancel("not_enough_rolls") end
        return
    end
    if #highs > 1 and (reroll.type == "high" or reroll.type == "full" or reroll.type == "goon_high") then
        self:StartTie(reroll.type, highs, reroll.lockedWinner, reroll.lockedLoser)
        return
    end
    if #lows > 1 and (reroll.type == "low" or reroll.type == "full") then
        self:StartTie(reroll.type, lows, reroll.lockedWinner, reroll.lockedLoser)
        return
    end
    local winner = reroll.lockedWinner or highs[1]
    local loser = reroll.lockedLoser or lows[1]
    local winnerRoll = reroll.lockedWinner and (session.rolls[winner] or high) or high
    local loserRoll = reroll.lockedLoser and (session.rolls[loser] or low) or low
    if reroll.type == "goon_high" then
        self:FinalizeGoonResult(winner, session.rolls[winner] or winnerRoll)
        return
    end
    self:FinalizeResult(winner, winnerRoll, loser, loserRoll)
end

function Gamba:BuildGoonDebts(winner, winnerRoll, rolls)
    local session = self:Current()
    local debts, total = {}, 0
    winner = stripRealm(winner)
    winnerRoll = tonumber(winnerRoll) or 0
    for name, roll in pairs(rolls or ((session and session.rolls) or {})) do
        name = stripRealm(name)
        roll = tonumber(roll) or 0
        if name and lower(name) ~= lower(winner or "") then
            local amount = math.max(0, winnerRoll - roll)
            debts[#debts + 1] = { debtor = name, roll = roll, amount = amount }
            total = total + amount
        end
    end
    table.sort(debts, function(a, b)
        if (a.amount or 0) ~= (b.amount or 0) then return (a.amount or 0) > (b.amount or 0) end
        return lower(a.debtor or "") < lower(b.debtor or "")
    end)
    return debts, total
end

function Gamba:AnnounceGoonResult(winner, winnerRoll, debts, totalOwed, localOnly)
    local function emit(message)
        if localOnly then self:AddonNotice(message) else self:Announce(message) end
    end
    emit(("[Gamba] GOON result: %s wins (%d). Total owed: %s."):format(winner, tonumber(winnerRoll) or 0, goldText(totalOwed)))
    if not debts or #debts == 0 then
        emit("[Gamba] No GOON debts were created.")
        return
    end
    for _, debt in ipairs(debts) do
        if (tonumber(debt.amount) or 0) > 0 then
            emit(("[Gamba] %s owes %s %s."):format(debt.debtor or "?", winner or "?", goldText(debt.amount)))
        end
    end
end

function Gamba:FinalizeGoonResult(winner, winnerRoll)
    local session = self:Current()
    if not session then return end
    local debts, totalOwed = self:BuildGoonDebts(winner, winnerRoll)
    session.state = self.STATE.PAYMENT
    session.mode = "goon"
    session.goonMode = true
    session.result = {
        mode = "goon",
        winner = winner,
        winnerRoll = tonumber(winnerRoll),
        loser = debts[1] and debts[1].debtor or "",
        loserRoll = debts[1] and debts[1].roll or 0,
        owed = totalOwed,
        debts = debts,
        paid = false,
        verified = false,
        verificationStatus = "pending",
        paymentStatus = totalOwed > 0 and "unpaid" or "paid",
        verifiedBy = {},
        paymentAcks = {},
    }
    session.updatedAt = now()
    self:CancelRollTimers()
    if self:IsHost() then
        self:Broadcast(OP.RESULT_GOON, session.id, winner, winnerRoll, totalOwed)
        self:AnnounceGoonResult(winner, winnerRoll, debts, totalOwed)
    end
    self:PlayResultSound(session)
    self:ApplyResultToLedger(session)
    if lower(stripRealm(winner)) == lower(playerName()) then
        self:AcknowledgeResult(session.id, playerName())
    else
        for _, debt in ipairs(debts) do
            if lower(stripRealm(debt.debtor)) == lower(playerName()) then
                self:AcknowledgeResult(session.id, playerName())
                break
            end
        end
    end
    self:Notify()
end

function Gamba:FinalizeResult(winner, winnerRoll, loser, loserRoll)
    local session = self:Current()
    if not session then return end
    local owed = math.max(0, (tonumber(winnerRoll) or 0) - (tonumber(loserRoll) or 0))
    session.state = self.STATE.PAYMENT
    session.result = {
        winner = winner,
        winnerRoll = tonumber(winnerRoll),
        loser = loser,
        loserRoll = tonumber(loserRoll),
        owed = owed,
        paid = false,
        verified = false,
        verificationStatus = "pending",
        paymentStatus = owed > 0 and "unpaid" or "paid",
        verifiedBy = {},
        paymentAcks = {},
    }
    session.updatedAt = now()
    self:CancelRollTimers()
    if self:IsHost() then
        self:Broadcast(OP.RESULT, session.id, winner, winnerRoll, loser, loserRoll, owed)
        self:Announce(("[Gamba] %s wins (%d). %s loses (%d) and owes %s."):format(winner, winnerRoll, loser, loserRoll, goldText(owed)))
    end
    self:PlayResultSound(session)
    self:ApplyResultToLedger(session)
    if lower(winner) == lower(playerName()) or lower(loser) == lower(playerName()) then
        self:AcknowledgeResult(session.id, playerName())
    end
    self:Notify()
end

function Gamba:Balance(name)
    name = stripRealm(name)
    if not name then return nil end
    local balances = self:Store().balances
    balances[name] = balances[name] or { wins = 0, losses = 0, goldWon = 0, goldLost = 0, net = 0 }
    return balances[name]
end

function Gamba:FindSessionEntry(sessionId)
    for _, entry in ipairs(self:Store().sessions) do
        if entry.id == sessionId then return entry end
    end
    return nil
end

function Gamba:SessionDebtRows(sessionId)
    local rows = {}
    for debtId, debt in pairs(self:Store().debts or {}) do
        if debtBelongsToSession(debt, sessionId) or debtId == sessionId then rows[#rows + 1] = debt end
    end
    return rows
end

function Gamba:RefreshSessionEntryAggregate(sessionId)
    local entry = self:FindSessionEntry(sessionId)
    if not entry then return end
    local debts = self:SessionDebtRows(sessionId)
    if #debts == 0 then return end
    local allPaid, anyPaymentPending, allVerified, paidAmount = true, false, true, 0
    for _, debt in ipairs(debts) do
        if debt.status ~= "paid" then allPaid = false end
        if debt.status == "payment_pending" then anyPaymentPending = true end
        if debt.verificationStatus ~= "verified" then allVerified = false end
        paidAmount = paidAmount + (tonumber(debt.paidAmount) or 0)
    end
    entry.paid = allPaid
    entry.paymentStatus = allPaid and "paid" or (anyPaymentPending and "payment_pending" or "unpaid")
    entry.verified = allVerified
    entry.verificationStatus = allVerified and "verified" or "pending"
    entry.paidAmount = paidAmount

    local session = self:Current()
    if session and session.id == sessionId and session.result then
        session.result.paid = allPaid
        session.result.paymentStatus = entry.paymentStatus
        session.result.verified = allVerified
        session.result.verificationStatus = entry.verificationStatus
        session.result.paidAmount = paidAmount
        if allPaid then session.state = self.STATE.COMPLETE end
    end
end

function Gamba:ApplyResultToLedger(session)
    if not (session and session.result and session.id) then return end
    if self:FindSessionEntry(session.id) then return end
    local r = session.result
    r.verifiedBy = r.verifiedBy or {}
    r.paymentAcks = r.paymentAcks or {}
    r.verificationStatus = r.verificationStatus or "pending"
    r.paymentStatus = r.paymentStatus or (r.paid and "paid" or "unpaid")
    local entry = {
        id = session.id,
        host = session.host,
        amount = session.amount,
        channel = session.channel,
        mode = r.mode or session.mode or "classic",
        goonMode = r.mode == "goon" or session.goonMode or nil,
        createdAt = session.createdAt,
        completedAt = now(),
        winner = r.winner,
        winnerRoll = r.winnerRoll,
        loser = r.loser,
        loserRoll = r.loserRoll,
        owed = r.owed,
        paid = false,
        verified = false,
        verificationStatus = r.verificationStatus,
        paymentStatus = r.paymentStatus,
        resultAcks = {},
        paymentAcks = {},
        rolls = {},
        debts = r.debts,
    }
    for name, roll in pairs(session.rolls or {}) do entry.rolls[name] = roll end
    table.insert(self:Store().sessions, 1, entry)
    while #self:Store().sessions > MAX_SESSIONS do table.remove(self:Store().sessions) end

    if r.mode == "goon" or r.debts then
        local totalOwed = 0
        local wb = self:Balance(r.winner)
        wb.wins = (wb.wins or 0) + 1
        for _, row in ipairs(r.debts or {}) do
            local amount = tonumber(row.amount) or 0
            totalOwed = totalOwed + amount
            local debtor = stripRealm(row.debtor)
            if debtor and amount > 0 then
                local lb = self:Balance(debtor)
                lb.losses = (lb.losses or 0) + 1
                lb.goldLost = (lb.goldLost or 0) + amount
                lb.net = (lb.net or 0) - amount
                local debtId = debtIdFor(session.id, debtor, r.winner)
                self:Store().debts[debtId] = {
                    sessionId = debtId,
                    parentSessionId = session.id,
                    debtor = debtor,
                    creditor = r.winner,
                    amount = amount,
                    status = "unpaid",
                    verified = false,
                    verificationStatus = "pending",
                    resultAcks = {},
                    paymentAcks = {},
                    createdAt = now(),
                    updatedAt = now(),
                    events = {},
                }
            end
        end
        wb.goldWon = (wb.goldWon or 0) + totalOwed
        wb.net = (wb.net or 0) + totalOwed
        if totalOwed <= 0 then
            entry.paid = true
            entry.paymentStatus = "paid"
        end
        return
    end

    local wb = self:Balance(r.winner)
    wb.wins = (wb.wins or 0) + 1
    wb.goldWon = (wb.goldWon or 0) + r.owed
    wb.net = (wb.net or 0) + r.owed
    local lb = self:Balance(r.loser)
    lb.losses = (lb.losses or 0) + 1
    lb.goldLost = (lb.goldLost or 0) + r.owed
    lb.net = (lb.net or 0) - r.owed

    self:Store().debts[session.id] = {
        sessionId = session.id,
        debtor = r.loser,
        creditor = r.winner,
        amount = r.owed,
        status = r.owed > 0 and "unpaid" or "paid",
        verified = false,
        verificationStatus = "pending",
        resultAcks = {},
        paymentAcks = {},
        createdAt = now(),
        updatedAt = now(),
        events = {},
    }
    if r.owed <= 0 then
        self:RecordPaymentAck(session.id, 0, r.loser, true)
        self:RecordPaymentAck(session.id, 0, r.winner, true)
    end
end

function Gamba:RefreshVerification(sessionId)
    local debt = self:Store().debts[sessionId]
    if not debt then return end
    local verified = ackHas(debt.resultAcks, debt.debtor) and ackHas(debt.resultAcks, debt.creditor)
    debt.verified = verified
    debt.verificationStatus = verified and "verified" or "pending"
    debt.updatedAt = now()

    local entry = self:FindSessionEntry(sessionId)
    if entry then
        entry.verified = verified
        entry.verificationStatus = debt.verificationStatus
        entry.resultAcks = debt.resultAcks
    end

    local session = self:Current()
    if session and session.id == sessionId and session.result then
        session.result.verified = verified
        session.result.verificationStatus = debt.verificationStatus
        session.result.verifiedBy = debt.resultAcks
    end
    if debt.parentSessionId then self:RefreshSessionEntryAggregate(debt.parentSessionId) end
end

function Gamba:AcknowledgeResult(sessionId, actor, remote)
    local session = self:Current()
    if session and session.id == sessionId then self:ApplyResultToLedger(session) end
    local debt = self:Store().debts[sessionId]
    actor = stripRealm(actor or playerName())
    if not actor then return false end
    if not debt then
        local changed = false
        for _, row in ipairs(self:SessionDebtRows(sessionId)) do
            if lower(actor) == lower(row.debtor) or lower(actor) == lower(row.creditor) then
                row.resultAcks = row.resultAcks or {}
                local firstAck = not ackHas(row.resultAcks, actor)
                row.resultAcks[actor] = now()
                row.events = row.events or {}
                if firstAck then row.events[#row.events + 1] = { at = now(), actor = actor, status = "result_ack" } end
                self:RefreshVerification(row.sessionId)
                changed = true
            end
        end
        if changed then
            self:RefreshSessionEntryAggregate(sessionId)
            if not remote then self:Broadcast(OP.RESULT_ACK, sessionId, actor) end
            self:Notify()
        end
        return changed
    end
    if lower(actor) ~= lower(debt.debtor) and lower(actor) ~= lower(debt.creditor) then return false end
    debt.resultAcks = debt.resultAcks or {}
    local firstAck = not ackHas(debt.resultAcks, actor)
    debt.resultAcks[actor] = now()
    debt.events = debt.events or {}
    if firstAck then debt.events[#debt.events + 1] = { at = now(), actor = actor, status = "result_ack" } end
    self:RefreshVerification(sessionId)
    if not remote then self:Broadcast(OP.RESULT_ACK, sessionId, actor) end
    self:Notify()
    return true
end

function Gamba:RefreshPaymentStatus(sessionId)
    local debt = self:Store().debts[sessionId]
    if not debt then return end
    local paid = ackHas(debt.paymentAcks, debt.debtor) and ackHas(debt.paymentAcks, debt.creditor)
    debt.status = paid and "paid" or "payment_pending"
    debt.paymentStatus = debt.status
    debt.updatedAt = now()

    local entry = self:FindSessionEntry(sessionId)
    if entry then
        entry.paid = paid
        entry.paymentStatus = debt.paymentStatus
        entry.paidAmount = debt.paidAmount
        entry.paymentAcks = debt.paymentAcks
    end

    local session = self:Current()
    if session and session.id == sessionId and session.result then
        session.result.paid = paid
        session.result.paymentStatus = debt.paymentStatus
        session.result.paidAmount = debt.paidAmount
        session.result.paymentAcks = debt.paymentAcks
        if paid then session.state = self.STATE.COMPLETE end
    end
    if debt.parentSessionId then self:RefreshSessionEntryAggregate(debt.parentSessionId) end
end

function Gamba:RecordPaymentAck(sessionId, amount, actor, remote)
    local debt = self:Store().debts[sessionId]
    if not debt then return false end
    actor = stripRealm(actor or playerName())
    if not actor then return false end
    if lower(actor) ~= lower(debt.debtor) and lower(actor) ~= lower(debt.creditor) then return false end
    amount = tonumber(amount) or debt.amount or 0
    debt.paymentAcks = debt.paymentAcks or {}
    local firstAck = not ackHas(debt.paymentAcks, actor)
    debt.paymentAcks[actor] = now()
    debt.paidAmount = math.max(tonumber(debt.paidAmount) or 0, amount)
    debt.events = debt.events or {}
    if firstAck then debt.events[#debt.events + 1] = { at = now(), actor = actor, status = "payment_ack", amount = amount } end
    self:RefreshPaymentStatus(sessionId)
    if not remote then
        self:Broadcast(OP.PAYMENT_ACK, sessionId, actor, amount)
        self:Broadcast(OP.PAYMENT, sessionId, debt.debtor, debt.creditor, amount, self:Store().debts[sessionId].paymentStatus or "payment_pending", actor)
    end
    self:Notify()
    return true
end

local function pairKey(a, b)
    a = stripRealm(a) or ""
    b = stripRealm(b) or ""
    if lower(a) <= lower(b) then return lower(a) .. "~" .. lower(b), a, b end
    return lower(b) .. "~" .. lower(a), b, a
end

local ACCOUNT_LABEL = "Me"

function Gamba:PairDebtFor(playerA, playerB)
    local key = pairKey(playerA, playerB)
    local net, newest, count, anyPending = 0, 0, 0, false
    local left, right
    for _, debt in pairs(self:Store().debts or {}) do
        local debtKey, a, b = pairKey(debt.debtor, debt.creditor)
        if debtKey == key and debt.status ~= "paid" then
            left, right = a, b
            local amount = tonumber(debt.amount) or 0
            if lower(stripRealm(debt.creditor)) == lower(a) then net = net + amount else net = net - amount end
            newest = math.max(newest, debt.updatedAt or debt.createdAt or 0)
            count = count + 1
            if debt.verificationStatus ~= "verified" or debt.status == "payment_pending" then anyPending = true end
        end
    end
    if net == 0 or count == 0 then return nil end
    local creditor, debtor = left, right
    if net < 0 then creditor, debtor, net = right, left, -net end
    return {
        key = key,
        debtor = debtor,
        creditor = creditor,
        amount = net,
        status = anyPending and "pending" or "unpaid",
        verificationStatus = anyPending and "pending" or "verified",
        paymentStatus = "unpaid",
        sessionCount = count,
        updatedAt = newest,
    }
end

function Gamba:PairDebtRows(limit)
    if self:Settings().accountMode == true then return self:AccountDebtRows(limit) end
    local pairMap = {}
    for _, debt in pairs(self:Store().debts or {}) do
        if debt.status ~= "paid" then pairMap[pairKey(debt.debtor, debt.creditor)] = { debt.debtor, debt.creditor } end
    end
    local rows = {}
    for _, players in pairs(pairMap) do
        local row = self:PairDebtFor(players[1], players[2])
        if row and (self:IsScopedCharacter(row.debtor) or self:IsScopedCharacter(row.creditor)) then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Gamba:AccountDebtRows(limit)
    local aggregates = {}
    for _, debt in pairs(self:Store().debts or {}) do
        if debt.status ~= "paid" then
            local debtorScoped = self:IsScopedCharacter(debt.debtor)
            local creditorScoped = self:IsScopedCharacter(debt.creditor)
            if debtorScoped ~= creditorScoped then
                local target = debtorScoped and stripRealm(debt.creditor) or stripRealm(debt.debtor)
                if target and target ~= "" then
                    local key = self:RemoteAccountKey(target)
                    local row = aggregates[key]
                    if not row then
                        row = { target = self:RemoteAccountLabel(target), targetKey = key, net = 0, count = 0, updatedAt = 0, anyPending = false, pairs = {} }
                        aggregates[key] = row
                    end
                    local amount = tonumber(debt.amount) or 0
                    if debtorScoped then row.net = row.net - amount else row.net = row.net + amount end
                    row.count = row.count + 1
                    row.updatedAt = math.max(row.updatedAt, debt.updatedAt or debt.createdAt or 0)
                    if debt.verificationStatus ~= "verified" or debt.status == "payment_pending" then row.anyPending = true end
                    local pkey = pairKey(debt.debtor, debt.creditor)
                    row.pairs[pkey] = { debt.debtor, debt.creditor }
                end
            end
        end
    end

    local rows = {}
    for _, aggregate in pairs(aggregates) do
        if aggregate.net ~= 0 then
            local settlementPairs = {}
            for _, players in pairs(aggregate.pairs) do
                local pair = self:PairDebtFor(players[1], players[2])
                if pair then settlementPairs[#settlementPairs + 1] = pair end
            end
            local amount = math.abs(aggregate.net)
            local direction = aggregate.net > 0 and "receive" or "pay"
            rows[#rows + 1] = {
                key = "account~" .. lower(aggregate.target),
                debtor = direction == "receive" and aggregate.target or ACCOUNT_LABEL,
                creditor = direction == "receive" and ACCOUNT_LABEL or aggregate.target,
                target = aggregate.target,
                targetKey = aggregate.targetKey,
                amount = amount,
                status = aggregate.anyPending and "pending" or "unpaid",
                verificationStatus = aggregate.anyPending and "pending" or "verified",
                paymentStatus = "unpaid",
                sessionCount = aggregate.count,
                updatedAt = aggregate.updatedAt,
                accountRow = true,
                direction = direction,
                settlementPairs = settlementPairs,
            }
        end
    end
    table.sort(rows, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Gamba:TradeDebtFor(target)
    target = stripRealm(target)
    if not target then return nil end
    local targetKey = self:RemoteAccountKey(target)
    local rows = {}
    if self:Settings().accountMode == true then
        for _, row in ipairs(self:PairDebtRows()) do
            if row.targetKey == targetKey or lower(row.target or "") == lower(target) or lower(row.debtor) == lower(target) or lower(row.creditor) == lower(target) then
                rows[#rows + 1] = row
            end
        end
    else
        local row = self:PairDebtFor(playerName(), target)
        if row then rows[#rows + 1] = row end
    end
    local debt = { target = target, youOwe = 0, owesYou = 0, payRows = {}, receiveRows = {} }
    for _, row in ipairs(rows) do
        if row.accountRow and row.direction == "receive" then
            debt.owesYou = debt.owesYou + (row.amount or 0)
            debt.receiveRows[#debt.receiveRows + 1] = row
        elseif row.accountRow and row.direction == "pay" then
            debt.youOwe = debt.youOwe + (row.amount or 0)
            debt.payRows[#debt.payRows + 1] = row
        elseif lower(row.debtor) == lower(target) and self:IsScopedCharacter(row.creditor) then
            debt.owesYou = debt.owesYou + (row.amount or 0)
            debt.receiveRows[#debt.receiveRows + 1] = row
        elseif lower(row.creditor) == lower(target) and self:IsScopedCharacter(row.debtor) then
            debt.youOwe = debt.youOwe + (row.amount or 0)
            debt.payRows[#debt.payRows + 1] = row
        end
    end
    if debt.youOwe <= 0 and debt.owesYou <= 0 then return nil end
    return debt
end

function Gamba:EnsureTradeDebtFrame()
    if self.tradeDebtFrame then return self.tradeDebtFrame end
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(306, 70)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(80)
    frame.fill = frame:CreateTexture(nil, "BACKGROUND")
    frame.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.fill:SetAllPoints(frame)
    setVGradient(frame.fill, { 0.125, 0.130, 0.158, 0.98 }, { 0.035, 0.036, 0.046, 0.98 })
    frame.inner = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.inner:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.inner:SetPoint("TOPLEFT", 2, -2)
    frame.inner:SetPoint("BOTTOMRIGHT", -2, 2)
    setVGradient(frame.inner, { 0.180, 0.185, 0.220, 0.16 }, { 0.020, 0.020, 0.025, 0.08 })
    frame.accent = frame:CreateTexture(nil, "BORDER")
    frame.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.accent:SetHeight(1)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -21)
    frame.accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -21)
    frame.accent:SetVertexColor(0.78, 0.60, 0.24, 0.42)
    frame.rail = frame:CreateTexture(nil, "ARTWORK")
    frame.rail:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.rail:SetWidth(3)
    frame.rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -7)
    frame.rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 7)
    frame.topLight = frame:CreateTexture(nil, "BORDER")
    frame.topLight:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.topLight:SetHeight(1)
    frame.topLight:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -2)
    frame.topLight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -2)
    frame.topLight:SetVertexColor(1, 1, 1, 0.085)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 11,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropBorderColor(0.76, 0.66, 0.44, 0.28)
    end
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    frame.title:SetPoint("TOP", 0, -8)
    frame.title:SetTextColor(0.78, 0.70, 0.55, 1)
    frame.title:SetText("GAMBA TRADE BALANCE")
    frame.youOweText = frame:CreateFontString(nil, "OVERLAY")
    frame.youOweText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    frame.youOweText:SetPoint("TOP", 0, -30)
    frame.youOweText:SetWidth(276)
    frame.youOweText:SetJustifyH("CENTER")
    frame.owesYouText = frame:CreateFontString(nil, "OVERLAY")
    frame.owesYouText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    frame.owesYouText:SetPoint("TOP", frame.youOweText, "BOTTOM", 0, -6)
    frame.owesYouText:SetWidth(276)
    frame.owesYouText:SetJustifyH("CENTER")
    frame:Hide()
    self.tradeDebtFrame = frame
    return frame
end

function Gamba:UpdateTradeDebtFrame()
    local frame = self:EnsureTradeDebtFrame()
    local target = self.tradeTarget or tradeTargetName()
    local debt = self:TradeDebtFor(target)
    if not debt then frame:Hide(); return end
    frame:ClearAllPoints()
    if TradeFrame and TradeFrame:IsShown() then
        frame:SetPoint("BOTTOM", TradeFrame, "TOP", 0, 8)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    if (debt.youOwe or 0) > 0 then
        frame.youOweText:ClearAllPoints()
        frame.youOweText:SetTextColor(0.88, 0.32, 0.28, 1)
        frame.youOweText:SetText(((self:Settings().accountMode == true and "Your account owes %s: %s") or "You owe %s: %s"):format(debt.target, uiGoldText(debt.youOwe)))
        frame.youOweText:Show()
    else
        frame.youOweText:Hide()
    end
    if (debt.owesYou or 0) > 0 then
        frame.owesYouText:ClearAllPoints()
        frame.owesYouText:SetTextColor(0.40, 0.86, 0.55, 1)
        frame.owesYouText:SetText(((self:Settings().accountMode == true and "%s owes your account: %s") or "%s owes you: %s"):format(debt.target, uiGoldText(debt.owesYou)))
        frame.owesYouText:Show()
    else
        frame.owesYouText:Hide()
    end
    local hasBoth = (debt.youOwe or 0) > 0 and (debt.owesYou or 0) > 0
    frame:SetHeight(hasBoth and 70 or 52)
    if (debt.youOwe or 0) > 0 then
        frame.rail:SetVertexColor(0.88, 0.32, 0.28, 0.92)
    else
        frame.rail:SetVertexColor(0.40, 0.86, 0.55, 0.92)
    end
    if hasBoth then
        frame.youOweText:SetPoint("TOP", 0, -30)
        frame.owesYouText:SetPoint("TOP", frame.youOweText, "BOTTOM", 0, -6)
    elseif (debt.youOwe or 0) > 0 then
        frame.youOweText:SetPoint("TOP", 0, -30)
    else
        frame.owesYouText:SetPoint("TOP", 0, -30)
    end
    frame:Show()
end

function Gamba:HideTradeDebtFrame()
    if self.tradeDebtFrame then self.tradeDebtFrame:Hide() end
end

function Gamba:SettlePair(debtor, creditor, amount, actor, remote)
    local row = self:PairDebtFor(debtor, creditor)
    amount = tonumber(amount) or 0
    if not row or amount < row.amount then return false end
    actor = stripRealm(actor or playerName())
    local settledAt = now()
    local touchedParents = {}
    for sessionId, debt in pairs(self:Store().debts or {}) do
        local samePair = pairKey(debt.debtor, debt.creditor) == row.key
        if samePair and debt.status ~= "paid" then
            debt.status = "paid"
            debt.paymentStatus = "paid"
            debt.paidAmount = debt.amount
            debt.updatedAt = settledAt
            debt.paymentAcks = debt.paymentAcks or {}
            if row.debtor then debt.paymentAcks[row.debtor] = settledAt end
            if row.creditor then debt.paymentAcks[row.creditor] = settledAt end
            debt.events = debt.events or {}
            debt.events[#debt.events + 1] = { at = settledAt, actor = actor, status = "pair_settled", amount = amount }
            if debt.parentSessionId then touchedParents[debt.parentSessionId] = true end
            local entry = self:FindSessionEntry(sessionId)
            if entry then
                entry.paid = true
                entry.paymentStatus = "paid"
                entry.paidAmount = entry.owed
                entry.pairSettled = true
            end
        end
    end
    local session = self:Current()
    if session and session.result and pairKey(session.result.loser, session.result.winner) == row.key then
        session.result.paid = true
        session.result.paymentStatus = "paid"
        session.result.pairSettled = true
        session.state = self.STATE.COMPLETE
    end
    for parentSessionId in pairs(touchedParents) do self:RefreshSessionEntryAggregate(parentSessionId) end
    if not remote then
        self:Broadcast(OP.PAYMENT, "PAIR", row.debtor, row.creditor, row.amount, "paid", actor or playerName())
        if self:IsScopedCharacter(row.creditor) then
            local channel = groupedChannelWith(row.debtor)
            if channel then
                SendChatMessage(("[Gamba] Payment verified: %s paid %s %s."):format(row.debtor or "?", row.creditor or "?", goldText(row.amount)), channel)
            end
        end
    end
    self:Notify()
    self:NotifySoon(0.08)
    return true
end

function Gamba:SettleDebtRow(row, actor)
    if not row then return false end
    if row.accountRow and row.settlementPairs then
        local changed = false
        for _, pair in ipairs(row.settlementPairs) do
            if self:SettlePair(pair.debtor, pair.creditor, pair.amount, actor) then changed = true end
        end
        return changed
    end
    return self:SettlePair(row.debtor, row.creditor, row.amount, actor)
end

function Gamba:CanSettleDebtRow(row)
    if not row or (tonumber(row.amount) or 0) <= 0 then return false end
    if row.accountRow then return row.direction == "receive" end
    return self:IsScopedCharacter(row.creditor)
end

function Gamba:SettleDebtRowAsCreditor(row)
    if not self:CanSettleDebtRow(row) then return false end
    return self:SettleDebtRow(row, playerName())
end

function Gamba:MarkPayment(sessionId, status, amount, actor, remote)
    local debt = self:Store().debts[sessionId]
    if debt then
        local pair = self:PairDebtFor(debt.debtor, debt.creditor)
        if pair and pair.amount > 0 then
            return self:SettlePair(pair.debtor, pair.creditor, pair.amount, actor or playerName(), remote)
        end
    end
    return self:RecordPaymentAck(sessionId, amount, actor or playerName(), remote)
end

function Gamba:Cancel(reason)
    local session = self:Current()
    if not session then return end
    if self:IsHost() then
        self:Broadcast(OP.CANCEL, session.id, reason or "cancelled")
        self:Announce(self:CancelMessage(reason))
    end
    self:SetCurrent(nil)
end

function Gamba:WarnMissingRolls()
    local session = self:Current()
    if not session or session.state ~= self.STATE.ROLLING or not self:IsHost() then return end
    local missing = {}
    for name in pairs(session.players or {}) do if not session.rolls[name] then missing[#missing + 1] = name end end
    if #missing > 0 then
        table.sort(missing)
        self:Announce(("[Gamba] Waiting on rolls: %s. /roll %d now. Missing players are removed in %d seconds."):format(table.concat(missing, ", "), session.amount, ROLL_GRACE_TIMEOUT))
    end
end

function Gamba:ExpireMissingRolls()
    local session = self:Current()
    if not session or session.state ~= self.STATE.ROLLING or not self:IsHost() then return end
    local missing = {}
    for name in pairs(session.players or {}) do
        if not session.rolls[name] then missing[#missing + 1] = name end
    end
    if #missing == 0 then
        self:CheckRollsComplete()
        return
    end

    table.sort(missing)
    for _, name in ipairs(missing) do
        session.players[name] = nil
    end
    session.updatedAt = now()
    self:Announce(("[Gamba] Removed missing rollers: %s."):format(table.concat(missing, ", ")))

    if countTable(session.players) < 2 then
        self:Cancel("not_enough_rolls")
        return
    end

    self:BroadcastState()
    self:Notify()
    self:CheckRollsComplete()
end

function Gamba:WarnMissingRerolls()
    local session = self:Current()
    local reroll = session and session.reroll
    if not session or session.state ~= self.STATE.REROLL or not reroll or not self:IsHost() then return end
    local missing = {}
    for _, name in ipairs(reroll.players or {}) do
        if not reroll.rolls[name] then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        table.sort(missing)
        self:Announce(("[Gamba] Waiting on rerolls: %s. Missing players are removed in %d seconds."):format(table.concat(missing, ", "), ROLL_GRACE_TIMEOUT))
    end
end

function Gamba:ExpireMissingRerolls()
    local session = self:Current()
    local reroll = session and session.reroll
    if not session or session.state ~= self.STATE.REROLL or not reroll or not self:IsHost() then return end
    local missing = {}
    local remaining = {}
    for _, name in ipairs(reroll.players or {}) do
        if reroll.rolls[name] then
            remaining[#remaining + 1] = name
        else
            missing[#missing + 1] = name
        end
    end
    if #missing == 0 then
        self:CalculateRerollResult()
        return
    end

    table.sort(missing)
    table.sort(remaining)
    reroll.players = remaining
    session.updatedAt = now()
    self:Announce(("[Gamba] Removed missing rerollers: %s."):format(table.concat(missing, ", ")))

    if (reroll.type == "full" and #remaining < 2) or (reroll.type ~= "full" and #remaining < 1) then
        self:Cancel("not_enough_rolls")
        return
    end

    self:CalculateRerollResult()
end

function Gamba:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    local parts = splitMessage(message)
    if tonumber(parts[1]) ~= PROTOCOL_VERSION then return end
    local op = parts[2]
    sender = stripRealm(sender)
    self:RegisterRemoteAccount(sender, parts[#parts])
    if op == OP.CREATE then
        local _, _, id, host, amount, gameChannel, goonChance = unpack(parts)
        if lower(host) == lower(playerName()) then return end
        if not self:ShouldAcceptSessionChannel(gameChannel, channel) then return end
        amount = math.min(MAX_GAMBA_AMOUNT, math.max(2, math.floor(tonumber(amount) or 100)))
        local current = self:Current()
        if current and current.state ~= self.STATE.COMPLETE and current.state ~= self.STATE.CANCELLED then
            local currentTransport = self:SessionTransport(current)
            local incomingTransport = normalizeChannel(channel)
            if currentTransport ~= "GUILD" and incomingTransport == "GUILD" then return end
        end
        goonChance = percentChance(goonChance)
        local session = { id = id, state = self.STATE.LOBBY, host = host, amount = amount, mode = "classic", goonChance = goonChance, goonMode = false, channel = gameChannel or "AUTO", transportChannel = normalizeChannel(channel), createdAt = now(), updatedAt = now(), players = { [host] = { name = host, joinedAt = now() } }, rolls = {} }
        self:SetCurrent(session)
        self:PlayNewGameSound(session)
        if gameChannel == "ADDON" then
            local goonText = goonChance > 0 and (" GOON chance: " .. tostring(goonChance) .. "%.") or ""
            self:AddonNotice(("[Gamba] %s started a %s Gamba.%s Open Gamba to join."):format(host, goldText(session.amount), goonText))
        end
        self:BroadcastAccount(host)
        self:AutoJoinSession(session)
    elseif op == OP.VERSION then
        local _, _, version, displayVersion, addonId = unpack(parts)
        self:HandleVersion(sender, version, displayVersion, addonId, channel)
    elseif op == OP.ACCOUNT then
        local _, _, accountId, rosterCsv = unpack(parts)
        if self:RegisterRemoteAccount(sender, "acct:" .. tostring(accountId or ""), rosterCsv) then
            if self.tradeTarget or (TradeFrame and TradeFrame:IsShown()) then self:UpdateTradeDebtFrame() end
            self:NotifySoon(0.05)
        end
    elseif op == OP.JOIN and self:IsHost() then
        local _, _, sessionId, name = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId and self:AddPlayer(name, true) then self:Broadcast(OP.JOINED, sessionId, stripRealm(name)) end
    elseif op == OP.JOINED then
        local _, _, sessionId, name = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then self:AddPlayer(name, true) end
    elseif op == OP.LEAVE then
        local _, _, sessionId, name = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then self:RemovePlayer(name, true) end
    elseif op == OP.START then
        local _, _, sessionId, mode = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then
            s.state = self.STATE.ROLLING
            s.mode = mode == "goon" and "goon" or "classic"
            s.goonMode = s.mode == "goon"
            s.rolls = {}
            s.rollStartedAt = now()
            s.updatedAt = now()
            if s.channel == "ADDON" then
                if s.goonMode then
                    self:AddonNotice(("[Gamba] GOON MODE! Highest roller wins. Everyone else owes the difference. /roll %d now."):format(s.amount or 0))
                else
                    self:AddonNotice(("[Gamba] Gamba rolling started. /roll %d now."):format(s.amount or 0))
                end
            end
            self:AutoRollIfReady(0.45)
            self:Notify()
        end
    elseif op == OP.ROLL then
        local _, _, sessionId, name, value = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId and (lower(stripRealm(sender)) == lower(stripRealm(name)) or lower(stripRealm(sender)) == lower(stripRealm(s.host))) then
            self:RecordRoll(name, tonumber(value), true)
        end
    elseif op == OP.TIE then
        local _, _, sessionId, tieType, names, lockedWinner, lockedLoser = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId and not self:IsHost() then
            local players = {}
            for name in tostring(names or ""):gmatch("([^,]+)") do players[#players + 1] = name end
            s.state = self.STATE.REROLL
            s.rerollStartedAt = now()
            s.updatedAt = now()
            s.reroll = { type = tieType, players = players, rolls = {}, lockedWinner = lockedWinner ~= "" and lockedWinner or nil, lockedLoser = lockedLoser ~= "" and lockedLoser or nil }
            if s.channel == "ADDON" then self:AddonNotice(("[Gamba] Tie detected. Reroll: %s."):format(table.concat(players, ", "))) end
            self:AutoRollIfReady(0.45)
            self:Notify()
        end
    elseif op == OP.REROLL then
        local _, _, sessionId, name, value = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId and (lower(stripRealm(sender)) == lower(stripRealm(name)) or lower(stripRealm(sender)) == lower(stripRealm(s.host))) then
            self:RecordReroll(name, tonumber(value), true)
        end
    elseif op == OP.RESULT then
        local _, _, sessionId, winner, winnerRoll, loser, loserRoll, owed = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then
            s.result = {
                winner = winner,
                winnerRoll = tonumber(winnerRoll),
                loser = loser,
                loserRoll = tonumber(loserRoll),
                owed = tonumber(owed) or 0,
                paid = false,
                verified = false,
                verificationStatus = "pending",
                paymentStatus = "unpaid",
                verifiedBy = {},
                paymentAcks = {},
            }
            s.state = self.STATE.PAYMENT
            self:PlayResultSound(s)
            self:ApplyResultToLedger(s)
            if s.channel == "ADDON" then
                self:AddonNotice(("[Gamba] %s wins (%d). %s loses (%d) and owes %s."):format(winner, tonumber(winnerRoll) or 0, loser, tonumber(loserRoll) or 0, goldText(owed)))
            end
            if lower(winner) == lower(playerName()) or lower(loser) == lower(playerName()) then
                self:AcknowledgeResult(sessionId, playerName())
            end
            self:Notify()
        end
    elseif op == OP.RESULT_GOON then
        local _, _, sessionId, winner, winnerRoll, totalOwed, debtCsv = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then
            local debts = parseGoonDebts(debtCsv)
            if #debts == 0 then debts = self:BuildGoonDebts(winner, winnerRoll, s.rolls) end
            s.mode = "goon"
            s.goonMode = true
            s.result = {
                mode = "goon",
                winner = winner,
                winnerRoll = tonumber(winnerRoll),
                loser = debts[1] and debts[1].debtor or "",
                loserRoll = debts[1] and debts[1].roll or 0,
                owed = tonumber(totalOwed) or 0,
                debts = debts,
                paid = false,
                verified = false,
                verificationStatus = "pending",
                paymentStatus = (tonumber(totalOwed) or 0) > 0 and "unpaid" or "paid",
                verifiedBy = {},
                paymentAcks = {},
            }
            s.state = self.STATE.PAYMENT
            self:PlayResultSound(s)
            self:ApplyResultToLedger(s)
            if s.channel == "ADDON" then
                self:AnnounceGoonResult(winner, winnerRoll, debts, totalOwed, true)
            end
            if lower(stripRealm(winner)) == lower(playerName()) then
                self:AcknowledgeResult(sessionId, playerName())
            else
                for _, debt in ipairs(debts) do
                    if lower(stripRealm(debt.debtor)) == lower(playerName()) then
                        self:AcknowledgeResult(sessionId, playerName())
                        break
                    end
                end
            end
            self:Notify()
        end
    elseif op == OP.RESULT_ACK then
        local _, _, sessionId, actor = unpack(parts)
        self:AcknowledgeResult(sessionId, actor or sender, true)
    elseif op == OP.PAYMENT then
        local _, _, sessionId, debtor, creditor, amount, status, actor = unpack(parts)
        if sessionId == "PAIR" then
            self:SettlePair(debtor, creditor, tonumber(amount), actor, true)
        else
            self:MarkPayment(sessionId, status, tonumber(amount), actor, true)
        end
    elseif op == OP.PAYMENT_ACK then
        local _, _, sessionId, actor, amount = unpack(parts)
        self:RecordPaymentAck(sessionId, tonumber(amount), actor or sender, true)
    elseif op == OP.CANCEL then
        local _, _, sessionId, reason = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId then
            if s.channel == "ADDON" then self:AddonNotice(self:CancelMessage(reason)) end
            self:SetCurrent(nil)
        end
    elseif op == OP.LAST_CALL then
        local _, _, sessionId, amount = unpack(parts)
        local s = self:Current()
        if s and s.id == sessionId and s.channel == "ADDON" then
            self:AddonNotice(("[Gamba] Last call for %s Gamba. Open Gamba to join."):format(goldText(amount or s.amount)))
        end
    elseif op == OP.DEBT_SYNC then
        local mode = parts[3]
        if mode == "REQ" then
            if lower(sender or "") ~= lower(playerName()) then self:BroadcastDebtSync(sender) end
        elseif mode == "ROW" then
            if self:MergeDebtSyncRow(parts, sender) then
                self:UpdateTradeDebtFrame()
                self:Notify()
            end
        elseif mode == "DONE" then
            self:UpdateTradeDebtFrame()
        end
    elseif op == OP.SYNC then
        local mode = parts[3]
        if mode == "REQ" then
            if self:IsHost() and self:Current() then self:BroadcastState() end
        elseif mode == "STATE" then
            local sessionId, state, host, amount, gameChannel, playersCsv, rollsCsv, resultCsv =
                parts[4], parts[5], parts[6], parts[7], parts[8], parts[9], parts[10], parts[11]
            local sessionMode, goonChance = parts[12], percentChance(parts[13])
            if not sessionId or sessionId == "" then return end
            if not self:ShouldAcceptSessionChannel(gameChannel, channel) then return end
            local session = {
                id = sessionId,
                state = state or self.STATE.LOBBY,
                host = host,
                amount = tonumber(amount) or 100,
                mode = sessionMode == "goon" and "goon" or "classic",
                goonMode = sessionMode == "goon",
                goonChance = goonChance,
                channel = gameChannel or "AUTO",
                transportChannel = normalizeChannel(channel),
                createdAt = now(),
                updatedAt = now(),
                players = {},
                rolls = {},
            }
            for _, name in ipairs(splitCsv(playersCsv)) do session.players[name] = { name = name, joinedAt = now() } end
            for _, pair in ipairs(splitCsv(rollsCsv)) do
                local name, roll = pair:match("^([^:]+):(%d+)$")
                if name and roll then session.rolls[name] = tonumber(roll) end
            end
            local resultParts = splitCsv(resultCsv)
            if resultParts[1] and resultParts[1] ~= "" then
                local resultMode = resultParts[11] == "goon" and "goon" or session.mode
                local debts, goonTotal = nil, nil
                if resultMode == "goon" then
                    debts, goonTotal = self:BuildGoonDebts(resultParts[1], resultParts[2], session.rolls)
                end
                session.result = {
                    mode = resultMode,
                    winner = resultParts[1],
                    winnerRoll = tonumber(resultParts[2]),
                    loser = debts and debts[1] and debts[1].debtor or resultParts[3],
                    loserRoll = debts and debts[1] and debts[1].roll or tonumber(resultParts[4]),
                    owed = goonTotal or tonumber(resultParts[5]) or 0,
                    debts = debts,
                    paid = resultParts[6] == "1",
                    verified = resultParts[7] == "verified",
                    verificationStatus = resultParts[7] ~= "" and resultParts[7] or "pending",
                    paymentStatus = resultParts[8] ~= "" and resultParts[8] or (resultParts[6] == "1" and "paid" or "unpaid"),
                    verifiedBy = {},
                    paymentAcks = {},
                }
                for _, actor in ipairs(splitTilde(resultParts[9])) do session.result.verifiedBy[actor] = now() end
                for _, actor in ipairs(splitTilde(resultParts[10])) do session.result.paymentAcks[actor] = now() end
                self:ApplyResultToLedger(session)
                for actor in pairs(session.result.verifiedBy) do self:AcknowledgeResult(session.id, actor, true) end
                for actor in pairs(session.result.paymentAcks) do self:RecordPaymentAck(session.id, session.result.owed, actor, true) end
            end
            if lower(host or "") ~= lower(playerName()) then self:SetCurrent(session) end
        end
    end
end

function Gamba:OnSystemMessage(message)
    local session = self:Current()
    if not session or (session.state ~= self.STATE.ROLLING and session.state ~= self.STATE.REROLL) then return end
    local name, roll, minRoll, maxRoll = rollPattern(message)
    if not name or minRoll ~= 1 or maxRoll ~= tonumber(session.amount) then return end
    self:RecordRoll(name, roll)
end

function Gamba:OnChat(message, sender, channel)
    local session = self:Current()
    if not session or session.state ~= self.STATE.LOBBY then return end
    if not self:ShouldUseChatChannel(session, channel) then return end
    local text = lower(trim(message))
    local name = stripRealm(sender)
    if text == "1" or text == "+1" then
        if self:IsHost() then
            if self:AddPlayer(name, true) then self:Broadcast(OP.JOINED, session.id, name) end
        end
    elseif text == "-1" or text == "leave" then
        if self:IsHost() then
            if self:RemovePlayer(name, true) then self:Broadcast(OP.LEAVE, session.id, name) end
        end
    end
end

function Gamba:SyncTradeAccount()
    local target = self.tradeTarget or tradeTargetName()
    if not target then return false end
    local key = lower(target)
    if self.tradeAccountSyncTarget == key then return false end
    self.tradeAccountSyncTarget = key
    return self:BroadcastAccount(target)
end

function Gamba:OnTradeShow()
    self.tradeCloseSerial = (self.tradeCloseSerial or 0) + 1
    self.tradeTarget = tradeTargetName()
    self.tradeMoney = nil
    self.tradeAccountSyncTarget = nil
    self.tradeCompleted = false
    self.tradeSettled = false
    self:SyncTradeAccount()
    self:RequestDebtSync(self.tradeTarget)
    self:UpdateTradeDebtFrame()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            self.tradeTarget = self.tradeTarget or tradeTargetName()
            self:SyncTradeAccount()
            self:RequestDebtSync(self.tradeTarget)
            self:UpdateTradeDebtFrame()
        end)
        C_Timer.After(0.45, function()
            self.tradeTarget = self.tradeTarget or tradeTargetName()
            self:UpdateTradeDebtFrame()
        end)
    end
end

function Gamba:OnTradeAcceptUpdate()
    self.tradeTarget = self.tradeTarget or tradeTargetName()
    self:SyncTradeAccount()
    self.tradeMoney = {
        target = self.tradeTarget,
        targetMoney = GetTargetTradeMoney and GetTargetTradeMoney() or 0,
        playerMoney = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0,
    }
    self:UpdateTradeDebtFrame()
end

function Gamba:OnTradeComplete()
    if not self.tradeCompleted or self.tradeSettled then return end
    local snap = self.tradeMoney
    if not snap then return end
    local me = playerName()
    local target = stripRealm(snap.target)
    if not target or target == "" then return end
    if self:Settings().accountMode == true then
        local debt = self:TradeDebtFor(target)
        if debt and (debt.youOwe or 0) > 0 and (snap.playerMoney or 0) >= (debt.youOwe or 0) * 10000 then
            for _, pair in ipairs(debt.payRows or {}) do
                self:SettleDebtRow(pair, me)
            end
            self.tradeSettled = true
            return
        elseif debt and (debt.owesYou or 0) > 0 and (snap.targetMoney or 0) >= (debt.owesYou or 0) * 10000 then
            for _, pair in ipairs(debt.receiveRows or {}) do
                self:SettleDebtRow(pair, me)
            end
            self.tradeSettled = true
            return
        end
    end
    for _, pair in ipairs(self:PairDebtRows()) do
        if lower(me) == lower(pair.creditor) and lower(target) == lower(pair.debtor) and (snap.targetMoney or 0) >= (pair.amount or 0) * 10000 then
            self:SettlePair(pair.debtor, pair.creditor, pair.amount, me)
            self.tradeSettled = true
            return
        elseif lower(me) == lower(pair.debtor) and lower(target) == lower(pair.creditor) and (snap.playerMoney or 0) >= (pair.amount or 0) * 10000 then
            self:SettlePair(pair.debtor, pair.creditor, pair.amount, me)
            self.tradeSettled = true
            return
        end
    end
end

function Gamba:ClearTradeState()
    self.tradeTarget = nil
    self.tradeAccountSyncTarget = nil
    self.tradeMoney = nil
    self.tradeCompleted = false
    self.tradeSettled = false
    self:HideTradeDebtFrame()
    self:NotifySoon(0.12)
end

function Gamba:OnTradeClosed()
    if self.tradeCompleted then self:OnTradeComplete() end
    if self.tradeCompleted or not C_Timer or not C_Timer.After then
        self:ClearTradeState()
        return
    end
    self.tradeCloseSerial = (self.tradeCloseSerial or 0) + 1
    local serial = self.tradeCloseSerial
    C_Timer.After(0.75, function()
        if self.tradeCloseSerial ~= serial then return end
        if self.tradeCompleted then self:OnTradeComplete() end
        self:ClearTradeState()
    end)
end

function Gamba:Finances()
    local store = self:Store()
    local summary = { owedToYou = 0, youOwe = 0, net = 0, won = 0, lost = 0 }
    local rows = self:PairDebtRows()
    for _, debt in ipairs(rows) do
        if debt.accountRow and debt.direction == "receive" then summary.owedToYou = summary.owedToYou + (debt.amount or 0)
        elseif debt.accountRow and debt.direction == "pay" then summary.youOwe = summary.youOwe + (debt.amount or 0)
        else
            if self:IsScopedCharacter(debt.creditor) then summary.owedToYou = summary.owedToYou + (debt.amount or 0) end
            if self:IsScopedCharacter(debt.debtor) then summary.youOwe = summary.youOwe + (debt.amount or 0) end
        end
    end
    for name, balance in pairs(store.balances or {}) do
        if self:IsScopedCharacter(name) then
            summary.net = summary.net + (balance.net or 0)
            summary.won = summary.won + (balance.goldWon or 0)
            summary.lost = summary.lost + (balance.goldLost or 0)
        end
    end
    return summary, rows
end

function Gamba:DebtRows(limit, includePaid)
    local rows = {}
    for _, debt in pairs(self:Store().debts or {}) do
        if includePaid or debt.status ~= "paid" then rows[#rows + 1] = debt end
    end
    table.sort(rows, function(a, b)
        if (a.status == "paid") ~= (b.status == "paid") then return a.status ~= "paid" end
        return (a.updatedAt or a.createdAt or 0) > (b.updatedAt or b.createdAt or 0)
    end)
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Gamba:HistoryCount()
    return #self:HistoryRows()
end

function Gamba:HistoryRows(limit, offset)
    local rows = {}
    for _, entry in ipairs(self:Store().sessions or {}) do
        if self:IsScopedCharacter(entry.winner) or self:IsScopedCharacter(entry.loser) then rows[#rows + 1] = entry end
    end
    table.sort(rows, function(a, b) return (a.completedAt or a.createdAt or 0) > (b.completedAt or b.createdAt or 0) end)
    offset = math.max(0, tonumber(offset) or 0)
    if offset > 0 then
        for i = 1, offset do table.remove(rows, 1) end
    end
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Gamba:PlayerTotals(limit)
    local rows = {}
    local account = { name = ACCOUNT_LABEL, wins = 0, losses = 0, goldWon = 0, goldLost = 0, net = 0, account = true }
    for name, balance in pairs(self:Store().balances or {}) do
        if self:Settings().accountMode == true and self:IsAccountCharacter(name) then
            account.wins = account.wins + (balance.wins or 0)
            account.losses = account.losses + (balance.losses or 0)
            account.goldWon = account.goldWon + (balance.goldWon or 0)
            account.goldLost = account.goldLost + (balance.goldLost or 0)
            account.net = account.net + (balance.net or 0)
        elseif self:Settings().accountMode ~= true or self:IsScopedCharacter(name) then
            rows[#rows + 1] = {
                name = name,
                wins = balance.wins or 0,
                losses = balance.losses or 0,
                goldWon = balance.goldWon or 0,
                goldLost = balance.goldLost or 0,
                net = balance.net or 0,
            }
        end
    end
    if self:Settings().accountMode == true then table.insert(rows, 1, account) end
    table.sort(rows, function(a, b)
        if (a.net or 0) == (b.net or 0) then return tostring(a.name) < tostring(b.name) end
        return (a.net or 0) > (b.net or 0)
    end)
    if limit and #rows > limit then
        for i = #rows, limit + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Gamba:PruneStaleCurrent()
    local session = self:Current()
    if not session then return false end
    local setting = tostring(self:Settings().channel or "AUTO"):upper()
    if groupedChannel() and self:SessionTransport(session) == "GUILD" and setting ~= "GUILD" then
        self:SetCurrent(nil)
        return true
    end
    local age = now() - (tonumber(session.rollStartedAt or session.rerollStartedAt or session.updatedAt or session.createdAt) or now())
    if self:IsHost() then
        if session.state == self.STATE.ROLLING and age > (ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) then
            self:ExpireMissingRolls()
            return true
        elseif session.state == self.STATE.REROLL and age > (ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) then
            self:ExpireMissingRerolls()
            return true
        end
        return false
    end
    local stale = false
    if session.state == self.STATE.ROLLING or session.state == self.STATE.REROLL then
        stale = age > (ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT + 60)
    elseif session.state == self.STATE.LOBBY then
        local minutes = math.max(1, tonumber(self:Settings().lobbyTimeoutMinutes) or 10)
        stale = age > math.max(180, (minutes * 60) + 60)
    end
    if not stale then return false end
    self:SetCurrent(nil)
    return true
end

function Gamba:ResumeSessionTimers()
    if not (C_Timer and C_Timer.NewTimer) then return end
    local session = self:Current()
    if not session or not self:IsHost() then return end
    self:CancelRollTimers()
    if session.state == self.STATE.LOBBY then
        self:StartLobbyTimers(session)
        return
    end
    if session.state == self.STATE.ROLLING then
        local elapsed = now() - (tonumber(session.rollStartedAt or session.updatedAt or session.createdAt) or now())
        if elapsed >= ROLL_TIMEOUT then self:WarnMissingRolls() else self.rollTimer = C_Timer.NewTimer(ROLL_TIMEOUT - elapsed, function() self:WarnMissingRolls() end) end
        if elapsed >= (ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) then self:ExpireMissingRolls() else self.rollExpireTimer = C_Timer.NewTimer((ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) - elapsed, function() self:ExpireMissingRolls() end) end
    elseif session.state == self.STATE.REROLL then
        local elapsed = now() - (tonumber(session.rerollStartedAt or session.updatedAt or session.createdAt) or now())
        if elapsed >= ROLL_TIMEOUT then self:WarnMissingRerolls() else self.rerollTimer = C_Timer.NewTimer(ROLL_TIMEOUT - elapsed, function() self:WarnMissingRerolls() end) end
        if elapsed >= (ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) then self:ExpireMissingRerolls() else self.rerollExpireTimer = C_Timer.NewTimer((ROLL_TIMEOUT + ROLL_GRACE_TIMEOUT) - elapsed, function() self:ExpireMissingRerolls() end) end
    end
end

function Gamba:Snapshot()
    self:PruneStaleCurrent()
    return {
        current = self:Current(),
        sessions = self:Store().sessions,
        balances = self:Store().balances,
        debts = self:Store().debts,
        settings = self:Settings(),
        finances = self:Finances(),
        provider = self.addonId or ADDON,
    }
end

function Gamba:SetCallback(fn)
    self.callback = fn
end

function Gamba:RegisterPanel(panel)
    if not panel then return end
    self.panels = self.panels or {}
    for _, existing in ipairs(self.panels) do
        if existing == panel then return end
    end
    self.panels[#self.panels + 1] = panel
end

function Gamba:Notify()
    if self.callback then pcall(self.callback) end
    if self.panel and self.panel.Refresh then self:RegisterPanel(self.panel); self.panel = nil end
    for _, panel in ipairs(self.panels or {}) do
        if panel and panel.Refresh then panel:Refresh() end
    end
end

function Gamba:NotifySoon(delay)
    if not (C_Timer and C_Timer.After) then self:Notify(); return end
    if self.notifySoonPending then return end
    self.notifySoonPending = true
    C_Timer.After(delay or 0.05, function()
        self.notifySoonPending = nil
        self:Notify()
    end)
end

function Gamba:OnInit()
    self.addonId = ADDON
    self:Store()
    self:RegisterAccountCharacter(playerName())
    registerPrefix(PREFIX)
    ns:GetModule("Nav"):RegisterPanel("gamba", function(parent)
        return ns:GetModule("GambaPanel"):Build(parent)
    end)
end

function Gamba:OnEnable()
    if self._enabled then return end
    self._enabled = true
    if _G.IDDQD_GAMBA_PROVIDER and _G.IDDQD_GAMBA_PROVIDER ~= self then
        self.externalProvider = _G.IDDQD_GAMBA_PROVIDER
        ns:Print("Standalone Gamba detected; app page will use that provider.", "success")
        return
    end
    _G.IDDQD_GAMBA_PROVIDER = self
    local Events = ns:GetModule("Events")
    if not Events then return end
    local function isActiveProvider()
        return _G.IDDQD_GAMBA_PROVIDER == self
    end
    Events:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender) if isActiveProvider() then self:OnAddonMessage(prefix, message, channel, sender) end end, "Gamba")
    Events:On("CHAT_MSG_SYSTEM", function(message) if isActiveProvider() then self:OnSystemMessage(message) end end, "Gamba")
    Events:On("CHAT_MSG_RAID", function(message, sender) if isActiveProvider() then self:OnChat(message, sender, "RAID") end end, "Gamba")
    Events:On("CHAT_MSG_RAID_LEADER", function(message, sender) if isActiveProvider() then self:OnChat(message, sender, "RAID") end end, "Gamba")
    Events:On("CHAT_MSG_PARTY", function(message, sender) if isActiveProvider() then self:OnChat(message, sender, "PARTY") end end, "Gamba")
    Events:On("CHAT_MSG_PARTY_LEADER", function(message, sender) if isActiveProvider() then self:OnChat(message, sender, "PARTY") end end, "Gamba")
    Events:On("CHAT_MSG_GUILD", function(message, sender) if isActiveProvider() then self:OnChat(message, sender, "GUILD") end end, "Gamba")
    Events:On("TRADE_SHOW", function() if isActiveProvider() then self:OnTradeShow() end end, "Gamba")
    Events:On("TRADE_ACCEPT_UPDATE", function() if isActiveProvider() then self:OnTradeAcceptUpdate() end end, "Gamba")
    Events:On("UI_INFO_MESSAGE", function(a, b)
        if not isActiveProvider() then return end
        local message = b or a
        if message == ERR_TRADE_COMPLETE then
            self.tradeCompleted = true
            self:OnTradeComplete()
        end
    end, "Gamba")
    Events:On("TRADE_CLOSED", function() if isActiveProvider() then self:OnTradeClosed() end end, "Gamba")
    self:RegisterAccountCharacter(playerName())
    self:ResumeSessionTimers()
    C_Timer.After(2, function() if isActiveProvider() and not self:Current() then self:RequestSync() end end)
    C_Timer.After(4, function() if isActiveProvider() then self:AnnounceVersion(); self:BroadcastAccount() end end)
end
