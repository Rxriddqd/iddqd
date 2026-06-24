local ADDON, ns = ...

local Panel = ns:NewModule("InvitePanel")

local function db() return ns:GetModule("DB").db end

local function inviteSettings()
    local s = db().settings.invite
    if s.words == nil then s.words = "inv 123" end
    if s.invByChat == nil then s.invByChat = false end
    if s.invByChatSay == nil then s.invByChatSay = false end
    if s.onlyGuild == nil then s.onlyGuild = true end
    return s
end

local function makeEditBox(parent, placeholderText)
    local host = ns:GetModule("Widgets"):TextInput(parent, { placeholder = placeholderText })
    host.box = host.edit  -- back-compat alias for any `.box` callers
    return host, host.edit
end

local function guildRanks()
    local n = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
    local out = {}
    for i = 1, n do
        out[i] = (GuildControlGetRankName and GuildControlGetRankName(i)) or ("Rank " .. i)
    end
    return out
end

function Panel:Build(parent)
    local W = ns:GetModule("Widgets")
    local Invite = ns:GetModule("Invite")
    local f = W:Card(parent, "base", true)  -- flat: no top-light line across the panel top

    local actions = W:SectionHeader(f, "Mass Invites", "Select guild ranks, then form and manage your raid.")
    actions:SetPoint("TOPLEFT", 24, -20)
    actions:SetPoint("RIGHT", -24, 0)

    local mass = W:Button(f, "Mass Invite (10s)", 150, 26)
    mass:SetPoint("TOPLEFT", 24, -58)
    mass:SetScript("OnClick", function()
        if Invite:IsCountingDown() then Invite:CancelMassInvite() else Invite:StartMassInvite(10) end
    end)
    f._mass = mass

    Invite.onCountdown = function(remaining)
        if remaining then mass:SetText("Cancel (" .. remaining .. "s)") else mass:SetText("Mass Invite (10s)") end
    end

    local disband = W:Button(f, "Disband", 90, 26)
    disband:SetPoint("LEFT", mass, "RIGHT", 8, 0)
    disband:SetScript("OnClick", function()
        W:Confirm("IDDQD_INVITE_DISBAND", "Disband the raid?", function() Invite:DisbandRaid() end)
    end)

    local reinvite = W:Button(f, "Reinvite", 90, 26)
    reinvite:SetPoint("LEFT", disband, "RIGHT", 8, 0)
    reinvite:SetScript("OnClick", function()
        W:Confirm("IDDQD_INVITE_REINVITE", "Disband and reinvite everyone?", function() Invite:Reinvite() end)
    end)

    local demote = W:Button(f, "Demote All", 100, 26)
    demote:SetPoint("LEFT", reinvite, "RIGHT", 8, 0)
    demote:SetScript("OnClick", function() Invite:DemoteAll() end)

    local ranksHdr = W:SectionHeader(f, "Target Ranks", "Which guild ranks Mass Invite targets.")
    ranksHdr:SetPoint("TOPLEFT", 24, -104)
    ranksHdr:SetPoint("RIGHT", -24, 0)

    f._rankChecks = {}
    local ranks = guildRanks()
    if #ranks == 0 then
        local msg = f:CreateFontString(nil, "OVERLAY")
        ns:GetModule("Theme"):Text(msg, "body", "dim")
        msg:SetText("Join a guild to configure invite ranks.")
        msg:SetPoint("TOPLEFT", 24, -150)
    else
        local COLS, x0, y0, colW, rowH = 2, 24, -148, 200, 24
        for i, rankName in ipairs(ranks) do
            local col = (i - 1) % COLS
            local rowi = math.floor((i - 1) / COLS)
            local idx = i
            local cb = W:Checkbox(f, rankName,
                function() local r = db().settings.invite.ranks or {}; return r[idx] end,
                function(v)
                    local s = db().settings.invite
                    s.ranks = s.ranks or {}
                    s.ranks[idx] = v or nil
                end)
            cb:SetPoint("TOPLEFT", x0 + col * colW, y0 - rowi * rowH)
            f._rankChecks[idx] = cb
        end
    end

    local chatHdr = W:SectionHeader(f, "Keyword Invites", "Invite players when they whisper a configured word.")
    chatHdr:SetPoint("TOPLEFT", 24, -292)
    chatHdr:SetPoint("RIGHT", -24, 0)

    local whisper = W:Checkbox(f, "Auto-invite whispers",
        function() return inviteSettings().invByChat end,
        function(v) Invite:SetOpt("invByChat", v and true or false) end)
    whisper:SetPoint("TOPLEFT", 24, -334)

    local sayYell = W:Checkbox(f, "Say/Yell keywords",
        function() return inviteSettings().invByChatSay end,
        function(v) Invite:SetOpt("invByChatSay", v and true or false) end)
    sayYell:SetPoint("LEFT", whisper, "RIGHT", 18, 0)

    local onlyGuild = W:Checkbox(f, "Guild members only",
        function() return inviteSettings().onlyGuild end,
        function(v) Invite:SetOpt("onlyGuild", v and true or false) end)
    onlyGuild:SetPoint("LEFT", sayYell, "RIGHT", 18, 0)

    local wordHost, wordBox = makeEditBox(f, "inv 123")
    wordHost:SetPoint("TOPLEFT", 24, -366)
    wordHost:SetSize(250, 24)
    wordBox:SetText(inviteSettings().words or "inv 123")
    wordHost._onChange = function(text, userInput)
        if userInput then Invite:SetOpt("words", text) end
    end

    local saveWords = W:Button(f, "Save Keywords", 116, 24)
    saveWords:SetPoint("LEFT", wordHost, "RIGHT", 8, 0)
    local function persistWords()
        Invite:SetOpt("words", wordBox:GetText())
        wordBox:ClearFocus()
    end
    saveWords:SetScript("OnClick", persistWords)
    wordBox:SetScript("OnEnterPressed", persistWords)

    local hint = f:CreateFontString(nil, "OVERLAY")
    ns:GetModule("Theme"):Text(hint, "caption", "faint")
    hint:SetText("Enable whisper invites, then separate multiple exact keywords with spaces. Example: inv 123")
    hint:SetPoint("TOPLEFT", wordHost, "BOTTOMLEFT", 0, -6)

    function f:Refresh()
        if not Invite:IsCountingDown() then f._mass:SetText("Mass Invite (10s)") end
        whisper:SetChecked(inviteSettings().invByChat)
        sayYell:SetChecked(inviteSettings().invByChatSay)
        onlyGuild:SetChecked(inviteSettings().onlyGuild)
        if not wordBox:HasFocus() then wordBox:SetText(inviteSettings().words or "inv 123") end
        for idx, cb in pairs(f._rankChecks) do
            local r = db().settings.invite.ranks or {}
            cb:SetChecked(r[idx] and true or false)
        end
    end

    return f
end
