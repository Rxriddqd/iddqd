local ADDON, ns = ...

local PREFIX = "|cFFCAA65A[iddqd]|r "

function ns:Print(msg, kind)
    local color = ""
    if kind == "error" then color = "|cFFD4756B"
    elseif kind == "success" then color = "|cFF5FBF8A"
    elseif kind == "warning" then color = "|cFFCAA65A" end
    local close = color ~= "" and "|r" or ""
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. color .. tostring(msg) .. close)
end

function ns:Printf(fmt, ...)
    self:Print(fmt:format(...))
end

function ns:Debug(...)
    local DB = ns:GetModule("DB")
    local d = (DB and DB.db) or iddqdDB or iddqd_appDevDB
    if not (d and d.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cFF646A76" .. table.concat(parts, " ") .. "|r")
end
