local ADDON, ns = ...

local EditProfile = ns:NewModule("RaidGroupsEdit")

-- Slots and members move together. A slot is "occupied" iff slots[idx] ~= nil.
local function stripRealm(name)
    if not name then return nil end
    local Players = ns.GetModule and ns:GetModule("Players") or nil
    if Players and Players.ShortName then return Players:ShortName(name) end
    return name:match("^([^%-]+)") or name
end

-- Swap two slots (either side may be empty — an empty side just carries nil, which
-- mechanically moves the occupant and clears the source).
function EditProfile.swap(profile, a, b)
    if a == b then return end
    profile.slots[a],   profile.slots[b]   = profile.slots[b],   profile.slots[a]
    profile.members[a], profile.members[b] = profile.members[b], profile.members[a]
end

-- Move the occupant of `from` into `to` (which must be empty). No-op on empty source
-- or from==to.
function EditProfile.move(profile, from, to)
    if from == to or not profile.slots[from] then return end
    profile.slots[to],   profile.slots[from]   = profile.slots[from],   nil
    profile.members[to], profile.members[from] = profile.members[from], nil
end

-- Place a roster member into slot idx. Returns false if the slot is already filled.
-- If the member's name already occupies another slot, clear that slot first (a name
-- appears at most once).
function EditProfile.place(profile, idx, member)
    if profile.slots[idx] then return false end
    local target = stripRealm(member.name)
    if target then
        local low = target:lower()
        for i = 1, 40 do
            local n = profile.slots[i]
            if n and (stripRealm(n) or ""):lower() == low then
                profile.slots[i] = nil; profile.members[i] = nil
            end
        end
    end
    profile.slots[idx] = member.name
    profile.members[idx] = { name = member.name, class = member.class, spec = member.spec, role = member.role }
    return true
end

function EditProfile.clear(profile, idx)
    profile.slots[idx] = nil
    profile.members[idx] = nil
end

-- The lowest empty slot index (1..40), or nil if every slot is filled.
function EditProfile.firstEmpty(profile)
    for i = 1, 40 do
        if not profile.slots[i] then return i end
    end
    return nil
end

-- Set the spec of a filled slot's member (no-op if the slot is empty). Name/slots untouched.
function EditProfile.setSpec(profile, idx, spec)
    local m = profile.slots[idx] and profile.members[idx]
    if not m then return end
    m.spec = spec
    if ns.classSpec and ns.classSpec.roleForSpec then
        local inferred = ns.classSpec.roleForSpec(m.class, spec)
        if inferred then m.role = inferred end
    end
end

-- A { [nameLower]=true } set of every occupied slot's name (realm-stripped, lowercased)
-- — used to hide already-placed members from the roster list.
function EditProfile.placedNames(profile)
    local set = {}
    for i = 1, 40 do
        local n = profile.slots[i]
        if n then set[(stripRealm(n) or ""):lower()] = true end
    end
    return set
end

if type(ns) == "table" then ns.raid_groups_edit = EditProfile end
return EditProfile
