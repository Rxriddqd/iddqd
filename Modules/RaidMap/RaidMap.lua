local ADDON, ns = ...

-- Raid Map: a simple strategy board. Officers drop raid-target markers and text pins onto a
-- canvas (saved per zone) to plan pulls/positioning. Pins persist in db.raidMapPins, keyed by
-- zone name. A pin = { x = 0..1, y = 0..1, marker = 1..8 (or 0 for a text-only pin), text = "" }.

local RaidMap = ns:NewModule("RaidMap")

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

function RaidMap:ZoneKey()
    if GetRealZoneText then
        local z = GetRealZoneText()
        if z and z ~= "" then return z end
    end
    if GetZoneText then
        local z = GetZoneText()
        if z and z ~= "" then return z end
    end
    return "World"
end

function RaidMap:Store()
    local d = db()
    if not d then return nil end
    d.raidMapPins = d.raidMapPins or {}
    return d.raidMapPins
end

function RaidMap:Pins(zone)
    zone = zone or self:ZoneKey()
    local store = self:Store()
    if not store then return {} end
    store[zone] = store[zone] or {}
    return store[zone]
end

function RaidMap:AddPin(zone, x, y, marker, text)
    local pins = self:Pins(zone)
    local pin = { x = x or 0.5, y = y or 0.5, marker = marker or 0, text = text or "" }
    pins[#pins + 1] = pin
    return pin
end

function RaidMap:RemovePin(zone, pin)
    local pins = self:Pins(zone)
    for i, p in ipairs(pins) do
        if p == pin then table.remove(pins, i); return true end
    end
    return false
end

function RaidMap:ClearZone(zone)
    zone = zone or self:ZoneKey()
    local store = self:Store()
    if store then store[zone] = {} end
end

return RaidMap
