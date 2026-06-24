local ADDON, ns = ...

local Settings = ns:NewModule("Settings")

function Settings:OnInit()
    -- Late lookup inside the closure: SettingsPanel may load after this file,
    -- and the builder only runs when the user first opens the General tab.
    ns:GetModule("Nav"):RegisterPanel("general", function(parent)
        return ns:GetModule("SettingsPanel"):Build(parent)
    end)
    ns:GetModule("Nav"):RegisterPanel("loot_set", function(parent)
        return ns:GetModule("LootSettingsPanel"):Build(parent)
    end)
end
