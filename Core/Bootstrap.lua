local ADDON, ns = ...

-- GetAddOnMetadata moved under C_AddOns on current clients; tolerate both.
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMeta and getMeta(ADDON, "Version")) or "1.0.0"
ns.modules = {}
ns.moduleOrder = {}

_G[ADDON] = ns
_G.iddqd = ns

function ns:NewModule(name)
    if self.modules[name] then return self.modules[name] end
    local m = { name = name }
    self.modules[name] = m
    self.moduleOrder[#self.moduleOrder + 1] = m
    return m
end

function ns:GetModule(name)
    return self.modules[name]
end

function ns:ForEachModule(fn)
    if type(fn) ~= "function" then return end
    for _, m in ipairs(self.moduleOrder or {}) do fn(m) end
end

local function call(m, method)
    local fn = m[method]
    if not fn then return end
    local ok, err = pcall(fn, m)
    if not ok then
        ns:Print(("module %s:%s failed: %s"):format(m.name, method, tostring(err)), "error")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        local db = ns:GetModule("DB")
        if db then call(db, "OnInit") end
        ns:ForEachModule(function(m)
            if m ~= db then call(m, "OnInit") end
        end)
        boot:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns:ForEachModule(function(m) call(m, "OnEnable") end)
    end
end)
