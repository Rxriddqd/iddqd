local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local frames = {}
function CreateFrame()
    local f = { events = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:SetScript(_, fn) self.script = fn end
    frames[#frames + 1] = f
    return f
end

local ns = {}
_G.iddqd_test = ns

assert(loadfile(DIR .. "Core/Bootstrap.lua"))("iddqd_test", ns)

local calls = {}
local function mod(name)
    local m = ns:NewModule(name)
    function m:OnInit() calls[#calls + 1] = "init:" .. self.name end
    function m:OnEnable() calls[#calls + 1] = "enable:" .. self.name end
    return m
end

mod("Alpha")
local DB = mod("DB")
mod("Beta")
local AlphaAgain = ns:NewModule("Alpha")

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end

check(AlphaAgain.name == "Alpha", "NewModule returns an existing module")
check(#ns.moduleOrder == 3, "moduleOrder contains each module once")
check(ns.moduleOrder[1].name == "Alpha" and ns.moduleOrder[2].name == "DB" and ns.moduleOrder[3].name == "Beta", "moduleOrder preserves registration order")

local boot = frames[1]
boot.script(boot, "ADDON_LOADED", "iddqd_test")
check(table.concat(calls, ",") == "init:DB,init:Alpha,init:Beta", "OnInit runs DB first, then registration order")

calls = {}
boot.script(boot, "PLAYER_LOGIN")
check(table.concat(calls, ",") == "enable:Alpha,enable:DB,enable:Beta", "OnEnable runs in registration order")

print(("bootstrap_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
