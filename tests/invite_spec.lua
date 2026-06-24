local DIR = "E:/Blizzard/World of Warcraft/_anniversary_/Interface/AddOns/iddqd/"

local invited, converted, afters, requestCount = {}, 0, {}, 0
function InviteUnit(name) invited[#invited + 1] = name end
function ConvertToRaid() converted = converted + 1 end
function GetNormalizedRealmName() return "Realm" end
function UnitName(unit) return unit == "player" and "Alice-Realm" or nil end
function time() return 1000 end
C_Timer = { After = function(_, fn) afters[#afters + 1] = fn end }

local ns = { modules = {} }
function ns:NewModule(n) self.modules[n] = self.modules[n] or { name = n }; return self.modules[n] end
function ns:GetModule(n) return self.modules[n] end
function ns:Debug() end
function ns:Print() end

ns.modules.DB = { db = { settings = { invite = {
    words = "inv 123",
    invByChat = true,
    invByChatSay = false,
    onlyGuild = false,
} } } }

assert(loadfile(DIR .. "Core/Players.lua"))("iddqd", ns)
assert(loadfile(DIR .. "Modules/Invite/Invite.lua"))("iddqd", ns)
local Invite = ns:GetModule("Invite")

local guildNames = {}
Invite._group.InviteUnit = InviteUnit
Invite._group.ConvertToRaid = ConvertToRaid
Invite._q.isInGuild = function() return true end
Invite._q.numGuild = function() return #guildNames end
Invite._q.guildInfo = function(i) return guildNames[i] end
Invite._q.requestGuildRoster = function() requestCount = requestCount + 1 end
Invite._q.after = function(_, fn) afters[#afters + 1] = fn end
Invite._q.inUnitGroup = function() return false end
Invite._q.isInRaid = function() return false end
Invite._q.numGroup = function() return 1 end
Invite._q.playerName = function() return "Alice" end

local pass, fail = 0, 0
local function check(c, m) if c then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. m) end end
local function reset()
    invited, converted, afters, requestCount = {}, 0, {}, 0
    guildNames = {}
end

Invite:RebuildInvWords()
Invite:OnWhisper("inv", "Bob-Realm", "WHISPER")
check(invited[1] == "Bob-Realm", "keyword invite works when guild-only is disabled")

reset()
Invite:OnWhisper("hello", "Bob-Realm", "WHISPER")
check(#invited == 0, "non-keyword whisper is ignored")

reset()
Invite:SetOpt("onlyGuild", true)
guildNames = { "Bob-Realm" }
Invite:OnWhisper("inv", "Bob-Realm", "WHISPER")
check(invited[1] == "Bob-Realm", "guild-only allows guild members")

reset()
guildNames = { "Cara-Realm" }
Invite:OnWhisper("inv", "Bob-Realm", "WHISPER")
check(#invited == 0 and requestCount == 1 and #afters == 1, "guild-only requests a roster retry when sender is not found")
guildNames = { "Bob-Realm" }
afters[1]()
check(invited[1] == "Bob-Realm", "guild-only delayed retry invites after roster refresh")

reset()
guildNames = { "Cara-Realm" }
Invite:OnWhisper("inv", "Bob-Realm", "WHISPER")
afters[1]()
check(#invited == 0, "guild-only still blocks non-guild senders after retry")

reset()
Invite:SetOpt("invByChat", false)
Invite:SetOpt("onlyGuild", false)
Invite:OnWhisper("inv", "Bob-Realm", "WHISPER")
check(#invited == 0, "whisper keyword invites respect the enable setting")

print(("invite_spec: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
