local ADDON, ns = ...

local Timers = ns:NewModule("Timers")

function Timers:After(delay, fn)
    if type(fn) ~= "function" then return nil end
    if C_Timer and C_Timer.After then
        return C_Timer.After(tonumber(delay) or 0, fn)
    end
    return fn()
end

function Timers:NewTimer(delay, fn)
    if type(fn) ~= "function" then return nil end
    if C_Timer and C_Timer.NewTimer then
        return C_Timer.NewTimer(tonumber(delay) or 0, fn)
    end
    self:After(delay, fn)
    return nil
end

function Timers:Cancel(timer)
    if timer and timer.Cancel then
        pcall(timer.Cancel, timer)
        return true
    end
    return false
end

function Timers:Debounce(owner, key, delay, fn)
    if type(owner) ~= "table" or type(fn) ~= "function" then return nil end
    owner.__iddqdTimerTokens = owner.__iddqdTimerTokens or {}
    key = tostring(key or "default")
    owner.__iddqdTimerTokens[key] = (owner.__iddqdTimerTokens[key] or 0) + 1
    local token = owner.__iddqdTimerTokens[key]
    return self:After(delay, function()
        if owner.__iddqdTimerTokens and owner.__iddqdTimerTokens[key] == token then
            fn()
        end
    end)
end

function Timers:Interval(owner, key, delay, fn)
    if type(owner) ~= "table" or type(fn) ~= "function" then return nil end
    key = tostring(key or "interval")
    owner.__iddqdIntervals = owner.__iddqdIntervals or {}
    owner.__iddqdIntervals[key] = true
    local function tick()
        if not owner.__iddqdIntervals or owner.__iddqdIntervals[key] ~= true then return end
        fn()
        Timers:After(delay, tick)
    end
    return self:After(delay, tick)
end

function Timers:CancelInterval(owner, key)
    if type(owner) ~= "table" or not owner.__iddqdIntervals then return false end
    owner.__iddqdIntervals[tostring(key or "interval")] = nil
    return true
end

return Timers
