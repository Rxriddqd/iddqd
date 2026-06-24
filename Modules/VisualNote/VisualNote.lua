local ADDON, ns = ...

-- Visual Note: a persistent free-form notepad (account-wide) for raid plans, reminders, links,
-- etc. Optionally post the note to chat. Data: db.visualNote = { text = "" }.

local VisualNote = ns:NewModule("VisualNote")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

function VisualNote:Get()
    local d = db()
    if not d then return "" end
    d.visualNote = d.visualNote or { text = "" }
    return d.visualNote.text or ""
end

function VisualNote:Set(text)
    local d = db()
    if not d then return end
    d.visualNote = d.visualNote or {}
    d.visualNote.text = text or ""
end

-- Post the note to a chat channel, one line per row. channel = "RAID"|"PARTY"|"GUILD"|"SAY".
function VisualNote:Post(channel)
    local text = self:Get()
    if text == "" or not SendChatMessage then return false end
    channel = channel or "RAID"
    if channel == "RAID" and not (IsInRaid and IsInRaid()) then
        channel = (IsInGroup and IsInGroup()) and "PARTY" or nil
    elseif channel == "PARTY" and not (IsInGroup and IsInGroup()) then
        channel = nil
    elseif channel == "GUILD" and not (IsInGuild and IsInGuild()) then
        channel = nil
    end
    if not channel then return false end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then pcall(SendChatMessage, "[iddqd] " .. line, channel) end
    end
    return true
end

return VisualNote
