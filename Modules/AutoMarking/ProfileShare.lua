local ADDON, ns = ...

local Share = ns:NewModule("AutoMarkingProfileShare")

local COMM_PREFIX = "IDDQD_AM"
local LINK_PREFIX = "iddqd-am"
local SAFE_LINK_PREFIX = "garrmission:" .. LINK_PREFIX
local CHUNK_SIZE = 185
local CHUNK_DELAY = 0.08

Share.incoming = {}
Share.received = {}

local function playerName()
    return (UnitName and UnitName("player")) or "player"
end

local function safeName(name)
    name = tostring(name or "Auto Marking Profile"):gsub("[\r\n:|]", " ")
    if #name > 48 then name = name:sub(1, 48) end
    return name
end

local function defaultChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if IsInGuild and IsInGuild() then return "GUILD" end
    return nil
end

local function sendAddon(message, channel)
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.SendAddon then return Comm:SendAddon(COMM_PREFIX, message, channel, nil, "NORMAL") end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, message, channel)
    elseif SendAddonMessage then
        return pcall(SendAddonMessage, COMM_PREFIX, message, channel)
    end
    return false
end

local function after(delay, fn)
    local Timers = ns:GetModule("Timers")
    if Timers and Timers.After then return Timers:After(delay, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(delay, fn) end
    return fn()
end

local function cacheKey(sender, token)
    sender = Ambiguate and Ambiguate(sender or "", "none") or (sender or "")
    return sender .. ":" .. token
end

local function makeLink(sender, token, name)
    return ("|cFFCAA65A|H%s:%s:%s|h[iddqd Auto Marking: %s]|h|r"):format(SAFE_LINK_PREFIX, sender, token, safeName(name))
end

local function makeChatToken(sender, token, name)
    return ("[iddqd Auto Marking: %s - %s - %s]"):format(sender, safeName(name), token)
end

local function slashForChannel(channel)
    if channel == "RAID" then return "/raid " end
    if channel == "PARTY" then return "/party " end
    if channel == "GUILD" then return "/guild " end
    return ""
end

local function profileLinkFilter(_, _, msg, ...)
    if type(msg) ~= "string" or not msg:find("%[iddqd Auto Marking:", 1, false) then return end
    local changed
    local filtered = msg:gsub("%[iddqd Auto Marking: ([^%s%]]+) %- (.-) %- (%d+)%]", function(sender, name, token)
        changed = true
        return makeLink(sender, token, name)
    end)
    if changed then return false, filtered, ... end
end

local function currentChatEditBox()
    if ChatEdit_GetActiveWindow then
        local active = ChatEdit_GetActiveWindow()
        if active then return active end
    end
    if ChatEdit_ChooseBoxForSend then
        local chosen = ChatEdit_ChooseBoxForSend(DEFAULT_CHAT_FRAME)
        if chosen then return chosen end
    end
    return _G.ChatFrame1EditBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
end

function Share:PrintImportLink(entry, incoming)
    if not (entry and DEFAULT_CHAT_FRAME) then return end
    local link = makeLink(entry.sender or playerName(), entry.token, entry.name)
    if incoming then
        local channel = entry.channel or "ADDON"
        local label = channel == "RAID" and "Raid" or channel == "PARTY" and "Party" or channel == "GUILD" and "Guild" or "iddqd"
        DEFAULT_CHAT_FRAME:AddMessage(("[%s] %s shared an iddqd auto-marking profile: %s"):format(label, entry.sender or "A player", link))
    else
        DEFAULT_CHAT_FRAME:AddMessage(("[iddqd] Auto-marking profile ready: %s"):format(link))
    end
end

function Share:Remember(sender, token, name, importString, channel)
    local entry = {
        sender = Ambiguate and Ambiguate(sender or "", "none") or sender,
        token = token,
        name = safeName(name),
        importString = importString,
        channel = channel,
        at = time and time() or 0,
    }
    self.received[cacheKey(sender, token)] = entry
    return entry
end

function Share:PrepareActive(channel)
    channel = channel or defaultChannel()
    if not channel then return nil, "Join a group or guild before sharing." end

    local AM = ns:GetModule("AutoMarking")
    local importString, err = AM and AM:ExportActiveProfileString()
    if not importString then return nil, err or "Could not export profile." end

    local profile = AM:GetActiveProfile()
    local name = safeName(profile and profile.name)
    local token = tostring((time and time()) or 0) .. tostring(math.random(1000, 9999))
    local total = math.ceil(#importString / CHUNK_SIZE)

    sendAddon(("P:%s:%d:%s"):format(token, total, name), channel)
    for i = 1, total do
        local chunk = importString:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
        after((i - 1) * CHUNK_DELAY, function()
            sendAddon(("C:%s:%d:%d:%s"):format(token, i, total, chunk), channel)
        end)
    end

    local entry = self:Remember(playerName(), token, name, importString, channel)
    return entry, nil, channel
end

function Share:ShareActive(channel)
    return self:InsertActiveLink(channel)
end

function Share:InsertActiveLink(channel)
    local activeEditBox = currentChatEditBox()
    if activeEditBox and activeEditBox:IsShown() and (activeEditBox:GetText() or ""):find("%[iddqd Auto Marking:", 1, false) then
        activeEditBox:SetFocus()
        activeEditBox:SetCursorPosition(#(activeEditBox:GetText() or ""))
        ns:Print("A profile link is already waiting in chat. Press Enter to send it.", "warning")
        return true
    end

    local entry, err, resolvedChannel = self:PrepareActive(channel)
    if not entry then ns:Print(err or "Could not prepare profile link.", "error"); return false end

    local text = slashForChannel(resolvedChannel) .. makeChatToken(playerName(), entry.token, entry.name)
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(text, DEFAULT_CHAT_FRAME)
    end

    local editBox = currentChatEditBox()
    if editBox then
        if ChatEdit_ActivateChat then ChatEdit_ActivateChat(editBox) else editBox:Show(); editBox:SetFocus() end
        editBox:SetText(text)
        editBox:SetCursorPosition(#text)
        ns:Print("Profile link inserted into chat. Press Enter to send it.", "success")
        return true
    end

    self:PrintImportLink(entry, false)
    ns:Print("Could not open chat edit box. Use the local profile link above.", "warning")
    return true
end

function Share:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX or type(message) ~= "string" then return end
    sender = Ambiguate and Ambiguate(sender or "", "none") or sender
    if sender == playerName() then return end

    local op, rest = message:match("^(%u):(.*)$")
    if op == "P" then
        local token, total, name = rest:match("^([^:]+):(%d+):(.*)$")
        total = tonumber(total)
        if token and total and total > 0 and total <= 80 then
            self.incoming[cacheKey(sender, token)] = { sender = sender, token = token, total = total, name = safeName(name), chunks = {}, count = 0 }
        end
    elseif op == "C" then
        local token, idx, total, chunk = rest:match("^([^:]+):(%d+):(%d+):(.*)$")
        idx, total = tonumber(idx), tonumber(total)
        if not (token and idx and total and chunk) then return end
        local key = cacheKey(sender, token)
        local entry = self.incoming[key]
        if not entry then
            entry = { sender = sender, token = token, total = total, name = "Auto Marking Profile", chunks = {}, count = 0 }
            self.incoming[key] = entry
        end
        if total ~= entry.total or idx < 1 or idx > total or total > 80 then return end
        if not entry.chunks[idx] then entry.count = entry.count + 1 end
        entry.chunks[idx] = chunk
        if entry.count >= entry.total then
            local parts = {}
            for i = 1, entry.total do
                if not entry.chunks[i] then return end
                parts[i] = entry.chunks[i]
            end
            local importString = table.concat(parts)
            local Codec = ns:GetModule("AutoMarkingProfileCodec")
            if Codec and Codec:IsImportString(importString) then
                self:Remember(sender, token, entry.name, importString, channel)
            end
            self.incoming[key] = nil
        end
    end
end

function Share:HandleLink(link)
    if type(link) ~= "string" then return false end
    local sender, token
    if link:sub(1, #SAFE_LINK_PREFIX + 1) == (SAFE_LINK_PREFIX .. ":") then
        sender, token = link:sub(#SAFE_LINK_PREFIX + 2):match("^([^:]+):(.+)$")
    elseif link:sub(1, #LINK_PREFIX + 1) == (LINK_PREFIX .. ":") then
        sender, token = link:sub(#LINK_PREFIX + 2):match("^([^:]+):(.+)$")
    else
        return false
    end
    if not (sender and token) then return false end
    local entry = self.received[cacheKey(sender, token)]
    if not entry then
        ns:Print("That auto-marking profile is still downloading. Try again in a moment.", "warning")
        return true
    end
    local function importNow()
        local AM = ns:GetModule("AutoMarking")
        local profile, err = AM and AM:ImportProfileString(entry.importString)
        if profile then
            ns:Print(("Imported auto-marking profile: %s"):format(profile.name), "success")
            local Shell = ns:GetModule("Shell")
            if Shell and Shell.current and Shell.current.Refresh then Shell.current:Refresh() end
        else
            ns:Print(err or "Could not import profile.", "error")
        end
    end
    local W = ns:GetModule("Widgets")
    if W and W.Confirm then
        W:Confirm("IDDQD_AM_IMPORT_PROFILE", ("Import '%s' from %s?"):format(entry.name, entry.sender or sender), importNow)
    else
        importNow()
    end
    return true
end

function Share:OnEnable()
    if self._enabled then return end
    self._enabled = true
    local Comm = ns:GetModule("Comm")
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix(COMM_PREFIX)
    elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    end
    local Events = ns:GetModule("Events")
    if Events then Events:On("CHAT_MSG_ADDON", function(...) self:OnAddonMessage(...) end, "AutoMarkingProfileShare") end

    if not ns._autoMarkingLinkHooked then
        ns._autoMarkingLinkHooked = true
        local oldSetItemRef = SetItemRef
        SetItemRef = function(link, text, button, chatFrame)
            local module = ns:GetModule("AutoMarkingProfileShare")
            if module and module:HandleLink(link) then return end
            return oldSetItemRef(link, text, button, chatFrame)
        end
    end

    if ChatFrame_AddMessageEventFilter and not ns._autoMarkingChatFilterHooked then
        ns._autoMarkingChatFilterHooked = true
        ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_OFFICER", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_INSTANCE_CHAT_LEADER", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", profileLinkFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", profileLinkFilter)
    end
end

return Share
