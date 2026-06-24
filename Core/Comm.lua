local ADDON, ns = ...

local Comm = ns:NewModule("Comm")

function Comm:RegisterPrefix(prefix)
    if not prefix or prefix == "" then return false end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        return pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    elseif RegisterAddonMessagePrefix then
        return pcall(RegisterAddonMessagePrefix, prefix)
    end
    return false, "RegisterAddonMessagePrefix unavailable"
end

function Comm:SendAddon(prefix, message, channel, target, priority)
    if not prefix or prefix == "" or not channel then return false end
    message = tostring(message or "")
    if priority and ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        return pcall(ChatThrottleLib.SendAddonMessage, ChatThrottleLib, priority, prefix, message, channel, target)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
    elseif SendAddonMessage then
        return pcall(SendAddonMessage, prefix, message, channel, target)
    end
    return false, "SendAddonMessage unavailable"
end

function Comm:ChunkPayload(payload, chunkSize)
    payload = tostring(payload or "")
    chunkSize = tonumber(chunkSize) or 185
    local chunks = {}
    if #payload == 0 then return chunks end
    local pos = 1
    while pos <= #payload do
        chunks[#chunks + 1] = payload:sub(pos, pos + chunkSize - 1)
        pos = pos + chunkSize
    end
    return chunks
end

function Comm:SplitDelimited(value, delimiter)
    value = tostring(value or "")
    delimiter = delimiter or "|"
    local out = {}
    if delimiter == "|" then
        for part in (value .. "|"):gmatch("([^|]*)|") do out[#out + 1] = part end
        return out
    end
    local plain = delimiter:gsub("(%W)", "%%%1")
    for part in (value .. delimiter):gmatch("(.-)" .. plain) do out[#out + 1] = part end
    return out
end

function Comm:CleanField(value, pattern)
    value = tostring(value or "")
    value = value:gsub(pattern or "[|\n\r]", " ")
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

return Comm
