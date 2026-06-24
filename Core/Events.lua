local ADDON, ns = ...

local Events = ns:NewModule("Events")
local frame = CreateFrame("Frame")
local handlers = {}   -- [event] = { {fn=, owner=}, ... }

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i].fn, ...)
        if not ok then
            ns:Print(("event %s handler error: %s"):format(event, tostring(err)), "error")
        end
    end
end)

function Events:On(event, fn, owner)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        frame:RegisterEvent(event)
    end
    list[#list + 1] = { fn = fn, owner = owner }
end

function Events:OffAll(owner)
    for event, list in pairs(handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then table.remove(list, i) end
        end
        if #list == 0 then
            handlers[event] = nil
            frame:UnregisterEvent(event)
        end
    end
end
