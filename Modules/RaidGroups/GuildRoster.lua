local ADDON, ns = ...

local GuildRoster = ns:NewModule("RaidGroupsGuildRoster")

-- Injected seam (real WoW globals by default; a fake roster in tests). Mirrors the
-- invite.lua pattern: request async, then read GetGuildRosterInfo by index.
GuildRoster._q = {
    request    = function()
        local fn = (C_GuildInfo and C_GuildInfo.GuildRoster) or _G.GuildRoster_Request or _G.GuildRoster
        if fn then fn() end
    end,
    numMembers = function() return GetNumGuildMembers() or 0 end,
    info       = function(i) return GetGuildRosterInfo(i) end,
}

local function stripRealm(name)
    if not name then return name end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(name) end
    return name:match("^([^%-]+)") or name
end

-- Ask the client to refresh the roster (data arrives async via GUILD_ROSTER_UPDATE).
function GuildRoster:Request() self._q.request() end

-- Map the guild roster to { name, class(token), level, online }, sorted online-first
-- then by name. classFile (position 11) is the class TOKEN, which classColor accepts.
function GuildRoster:List()
    local q = self._q
    local out = {}
    for i = 1, q.numMembers() do
        local name, _, _, level, _, _, _, _, online, _, classFile = q.info(i)
        if name then
            out[#out + 1] = {
                name   = stripRealm(name),
                class  = classFile,
                level  = level,
                online = online and true or false,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

if type(ns) == "table" then ns.raid_groups_guildroster = GuildRoster end
return GuildRoster
