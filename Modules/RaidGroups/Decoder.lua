local ADDON, ns = ...

local b64url = (type(ns) == "table" and ns.raid_assignments_b64url) or require("vendor_b64url")
local json   = (type(ns) == "table" and ns.raid_assignments_json)   or require("vendor_json")

local Decoder = {}

local PREFIX = "!iddqd-comp!"
local MAX_VERSION = 1

-- SHORT -> VERBOSE (inverse of the website's wire-format short-key map).
local VERBOSE = {
    v = "v", raid = "raid", sc = "shareCode", inst = "instances", sm = "sizeMode", sets = "sets",
    id = "id", t = "title", ss = "scheduledStart", sz = "size", l = "layout", n = "notes", m = "members",
    nm = "name", rlm = "realm", reg = "region", cls = "class", spc = "spec", r = "role",
    il = "ilvl", g = "group", sl = "slot", bc = "bnetCharId",
}

local function expand(v)
    if type(v) ~= "table" then return v end
    local isArray = (#v > 0) or next(v) == nil
    if isArray then
        local out = {}
        for i = 1, #v do out[i] = expand(v[i]) end
        return out
    end
    local out = {}
    for k, val in pairs(v) do out[VERBOSE[k] or k] = expand(val) end
    return out
end

local function now() return (ns and ns.now and ns.now()) or (time and time()) or os.time() end

function Decoder.Decode(str)
    if type(str) ~= "string" or str:sub(1, #PREFIX) ~= PREFIX then
        return nil, "Not a valid composition string"
    end
    local raw = b64url.decode(str:sub(#PREFIX + 1))
    if not raw then return nil, "Could not read the composition string" end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then return nil, "Could not read the composition string" end
    decoded = expand(decoded)

    if type(decoded.v) ~= "number" then return nil, "Could not read the composition string" end
    if decoded.v > MAX_VERSION then
        return nil, "This composition was exported by a newer website version; update the addon."
    end
    if type(decoded.sets) ~= "table" or #decoded.sets == 0 then
        return nil, "The composition has no roster sets"
    end

    local profiles = {}
    for _, set in ipairs(decoded.sets) do
        local profile = { uuid = set.id, name = set.title or "Imported set", time = now(), slots = {}, members = {} }
        for _, m in ipairs(set.members or {}) do
            if type(m.name) == "string"
               and type(m.group) == "number" and m.group >= 1 and m.group <= 8
               and type(m.slot) == "number" and m.slot >= 0 and m.slot <= 4
            then
                local idx = (m.group - 1) * 5 + (m.slot + 1)
                if idx >= 1 and idx <= 40 then
                    profile.slots[idx] = m.name
                    profile.members[idx] = { name = m.name, class = m.class, spec = m.spec, role = m.role }
                end
            end
        end
        profiles[#profiles + 1] = profile
    end
    return profiles, nil
end

if type(ns) == "table" then ns.raid_groups_decoder = Decoder end
return Decoder
