local ADDON, ns = ...

local Client = ns:NewModule("Client")

local PROJECT = _G.WOW_PROJECT_ID
local ERA = _G.WOW_PROJECT_CLASSIC
local TBC = _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC

Client.isEra = (PROJECT == ERA)
Client.isTBC = (PROJECT == TBC)

-- Capability flags — every version-specific decision routes through here so
-- features never branch on the client directly.
Client.hasDualSpec = Client.isTBC          -- dual spec is a TBC feature
Client.flavor = Client.isTBC and "tbc" or "era"

function Client:Describe()
    return ("%s (project %s, interface %s)"):format(
        self.flavor, tostring(PROJECT), tostring((select(4, GetBuildInfo()))))
end
