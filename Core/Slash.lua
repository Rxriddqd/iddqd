local ADDON, ns = ...

local Slash = ns:NewModule("Slash")
local subcommands = {}   -- [name] = fn(args)

function Slash:Register(name, fn)
    subcommands[name:lower()] = fn
end

function Slash:OnEnable()
    if self._enabled then return end
    self._enabled = true
    SLASH_IDDQD1 = "/iddqd"
    SLASH_IDDQD2 = "/id"
    SlashCmdList["IDDQD"] = function(input)
        local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
        cmd = (cmd or ""):lower()
        local fn = subcommands[cmd] or subcommands[""]
        if fn then fn(rest) end
    end
end
