local ADDON, ns = ...

local Players = ns:NewModule("Players")

function Players:Trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function Players:CurrentRealm()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    return self:Trim(realm):gsub("%s+", "")
end

function Players:FullName(name, realm)
    name = self:Trim(name)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = self:Trim(realm or self:CurrentRealm())
    return realm ~= "" and (name .. "-" .. realm) or name
end

function Players:ShortName(value)
    value = self:Trim(value)
    return value:match("^([^-]+)") or value
end

function Players:LocalName()
    local name = UnitName and UnitName("player")
    return self:FullName(name)
end

function Players:Same(a, b)
    a = self:Trim(a):lower()
    b = self:Trim(b):lower()
    if a == "" or b == "" then return false end
    if a == b then return true end

    local shortA, realmA = a:match("^([^-]+)%-(.+)$")
    local shortB, realmB = b:match("^([^-]+)%-(.+)$")
    shortA = shortA or a
    shortB = shortB or b

    if realmA and realmB and realmA ~= realmB then return false end
    return shortA == shortB
end

return Players
