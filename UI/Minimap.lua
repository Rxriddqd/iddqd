local ADDON, ns = ...

local Minimap = ns:NewModule("Minimap")
local LDB_NAME = ADDON

local function db()
    local DB = ns:GetModule("DB")
    return DB and DB.db
end

local function icon()
    return LibStub and LibStub("LibDBIcon-1.0", true)
end

function Minimap:OnEnable()
    if self.registered then return end
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local dbi = icon()
    local d = db()
    if not (ldb and dbi and d) then return end

    d.minimap = d.minimap or {}

    local obj = ldb:NewDataObject(LDB_NAME, {
        type = "launcher",
        icon = ("Interface\\AddOns\\%s\\Media\\logo"):format(ADDON),
        OnClick = function(_, button)
            if button == "LeftButton" then
                local shell = ns:GetModule("Shell")
                if shell then shell:Toggle() end
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("iddqd")
            tt:AddLine("|cff9aa0adClick:|r open dashboard")
        end,
    })

    dbi:Register(LDB_NAME, obj, d.minimap)
    self.registered = true
end

function Minimap:SetHidden(hidden)
    local d = db()
    if d and d.minimap then d.minimap.hide = hidden and true or false end
    local dbi = icon()
    if not dbi then return end
    if hidden then dbi:Hide(LDB_NAME) else dbi:Show(LDB_NAME) end
end

function Minimap:IsHidden()
    local d = db()
    return d and d.minimap and d.minimap.hide or false
end
