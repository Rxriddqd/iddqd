local ADDON, ns = ...

ns.DB_DEFAULTS = {
    version = 10,
    debug = false,
    assignments = {},       -- Imported from website
    raidAssignments = {
        sets = {},
        lastSelectedSetId = nil,
        lastSelectedBossKey = nil,
    },
    lootHistory = {},       -- Tracked in-game (legacy source for old loot UI)
    raidLootLedger = {
        protocolVersion = 2,   -- bump with LootStore PROTOCOL_VERSION on any data-shape break
        drops = {},        -- [dropID] = drop record (append-only events)
        sessions = {},     -- [sessionID] = session record with scope
        settings = { guildRaidThreshold = 0.60 },
    },
    lootDistribution = {
        protocolVersion = 1,
        entries = {},      -- [lootListId] = entry
    },
    council = {
        active = nil,       -- Latest website loot-assignment import shared through the addon
        history = {},
        received = {},
        settings = {
            autoShareOnImport = true,
            announceImports = true,
        },
    },
    professions = {
        profiles = {},      -- [Character-Realm] = profession scan profile shared by addon users
        lastScanAt = 0,
        dataGeneration = 6,
        settings = {
            autoGuildSync = true,
        },
    },
    gamba = {
        version = 1,
        current = nil,
        sessions = {},
        balances = {},
        debts = {},
        settings = {
            defaultAmount = 100,
            channel = "AUTO",
            announce = true,
            autoRoll = false,
        },
    },
    settings = {
        minQuality = 0,             -- Legacy global minimum quality (0 = Poor/Grey)
        trackBossKills = true,
        autoTrackLoot = true,
        announceAssignments = false,
        raidLootLedger = {
            trackDungeonLoot = true,     -- Track personal rare+ dungeon sessions
            dungeonMinQuality = 3,       -- Rare
            raidMinQuality = 4,          -- Epic unless explicitly whitelisted
            allowGargulFallback = false, -- iddqd is authoritative; Gargul chat is ignored unless explicitly enabled
        },
        showMinimapButton = true,
        minimapPosition = 225,      -- Angle around minimap (degrees)
        syncSettings = {
            autoSync = true,            -- Auto-sync on login
            minRankToBroadcast = 2,     -- Guild rank required to broadcast (0 = GM)
            announceSync = true,        -- Print sync messages
        },
        syncDataVersion = 0,            -- Current data version
        syncLastTime = 0,               -- Last sync timestamp
        syncLastFrom = nil,             -- Who sent last sync
        lootSettings = {
            filterByClass = true,           -- Filter items by player class (smart filter)
            showAllItems = false,           -- Override filter to show all
            autoTradeEnabled = true,        -- Enable auto-trade functionality
            announceAssignments = false,    -- Announce in raid chat when assigning
            autoAssistNames = {},           -- List of player names to auto-promote to assist
            autoAssistEnabled = true,       -- Whether auto-assist is enabled
            distributePermission = "assist",-- Who may add/remove/award loot. Supported modes:
                                            -- leader, assist, guild, assist_and_guild,
                                            -- assist_or_guild. Set by the raid leader and
                                            -- broadcast to the group.
            distributeGuildRank = 2,        -- Highest allowed guild rank index for guild-rank
                                            -- distribution modes. 0 is guild master/highest.
            disableMiniLoot = false,        -- Mini-loot window auto-opens for EVERYONE by default;
                                            -- set true to opt out. (Replaces the old autoOpenMiniLoot
                                            -- + lootWindow.autoOpen* gates, which were confusing.)
            autoOpenMiniLootOnAdd = false,  -- Optional local preference: open the mini-loot window
                                            -- as soon as loot is added/synced into the loot tab.
            smartMiniLootFilter = false,    -- Optional: hide mini-loot rows that are clearly unusable/irrelevant for this class.
            autoNeed = {
                enabled = false,
                roleRequirement = "assist",  -- "any", "assist", "leader"
                rarities = {
                    [2] = false,    -- Uncommon (green) OFF
                    [3] = true,     -- Rare (blue) ON
                    [4] = true,     -- Epic (purple) ON
                    [5] = false,    -- Legendary (orange) OFF by default (safety)
                },
            },
            autoMasterLoot = false,
            announceLoot = {
                enabled = false,
                channel = "RAID",           -- "RAID" or "RAID_WARNING"
                announceDrops = false,      -- Announce when boss loot drops
                announceAssignments = false,-- Announce when items are assigned
                announceMasterLoot = false, -- Announce when items are distributed via ML
                minQuality = 4,             -- Minimum quality to announce (4 = Epic)
            },
            lootWindow = {
                closeOnCombat = true,           -- Auto-close the mini-loot window when entering combat
            },
        },
        notificationSettings = {
            showLootChatMessage = true,     -- Show "X has been assigned to you!" in chat
            showLootPopup = true,           -- Show centered screen popup for loot assignments
            popupOffsetX = 0,               -- Popup X offset from center
            popupOffsetY = 200,             -- Popup Y offset from center (positive = up)
            popupScale = 100,               -- Popup scale percentage (20-200)
        },
        readyCheck = {
            enabled = true,
            showOnlyLeader = false,
            checkFood = true,
            checkFlask = true,
            opacity = 100,
            announceOnReadyCheck = false,
            announceMissingFood = false,
            announceMissingFlask = false,
            announceMissingRaidBuffs = false,
            lowBuffMinutes = 10,
            autoHideSeconds = 8,
            sort = "roster",
        },
        permissionSettings = {
            canBroadcastMaxRank = 2,        -- Max rank that can sync from dashboard (0=GM, 1=officers, etc.)
        },
    },
    lastSync = 0,
    lastExport = 0,
    characterData = {},     -- Per-character settings
    raidMapPins = {},       -- [zoneName] = { { x, y, marker, text }, ... } strategy-board pins
    visualNote = { text = "" },   -- free-form account-wide scratchpad
    lootFilters = {},           -- { [itemId] = true } items to hide from loot window
    minimap = {
        hide = false,           -- Whether to hide minimap button
    },
}

ns.DB_DEFAULTS.settings.invite = {
    ranks             = {},
    words             = "inv 123",
    invByChat         = false,
    invByChatSay      = false,
    onlyGuild         = true,
    autoInvAccept     = false,
    autoPromote       = false,
    promoteRank       = 2,
    promoteNames      = "",
    lootMethodEnabled = false,
    lootMethod        = "group",
    masterLooters     = "",
    lootThreshold     = 2,
    listInv1          = "",
    listInv2          = "",
    listInv3          = "",
    listInv4          = "",
}

ns.DB_DEFAULTS.settings.attendance = {
    autoMode = "disabled",      -- disabled, first_pull, first_kill, every_pull, every_kill
    enabled = nil,              -- legacy: nil=disabled, 1-4=mode, string=custom conditions
    data = {},                  -- Array of roster snapshots
    alts = {},                  -- { { "AltName", "MainName" }, ... }
    specialEdit = "",           -- Custom condition string
}

ns.DB_DEFAULTS.settings.raidGroups = {
    profiles = {},              -- Saved group layouts
    keepPosInGroup = true,      -- Maintain position within groups on apply
}

ns.DB_DEFAULTS.settings.autoMarking = {
    version = 4,
    gruulNpcFixVersion = 1,
    enabled = false,                -- opt-in
    activeProfileId = "default",
    profiles = {
        {
            id = "default",
            name = "Default",
            createdAt = 0,
            updatedAt = 0,
            modifierEnabled = false,        -- only mark while a modifier is held
            modifierKey = "ALT",            -- "ALT" | "SHIFT" | "CTRL"
            lockAfterUse = false,           -- when true, don't wrap when all priority slots are taken
            raids = { kara = {}, gruul = {}, mag = {}, ssc = {}, tk = {}, hyjal = {}, bt = {}, za = {}, swp = {} },
            -- raids[raidKey][npcID] = { marker1, marker2, ... } (priority list, <= 8)
        },
    },
}

return ns.DB_DEFAULTS
