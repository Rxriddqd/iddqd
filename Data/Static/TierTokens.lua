local ADDON, ns = ...

ns.tierTokens = ns.tierTokens or {}

ns.tierTokens.byTokenId = {
    [29759] = { tier = "Tier 4", slot = "head", name = "Helm of the Fallen Hero", setPieces = { 29076, 29081, 28963 } },
    [29760] = { tier = "Tier 4", slot = "head", name = "Helm of the Fallen Champion", setPieces = { 29044, 29061, 29068, 29073, 29028, 29035, 29040 } },
    [29761] = { tier = "Tier 4", slot = "head", name = "Helm of the Fallen Defender", setPieces = { 29021, 29011, 29049, 29058, 29086, 29093, 29098 } },
    [29762] = { tier = "Tier 4", slot = "shoulder", name = "Pauldrons of the Fallen Hero", setPieces = { 29079, 29084, 28967 } },
    [29763] = { tier = "Tier 4", slot = "shoulder", name = "Pauldrons of the Fallen Champion", setPieces = { 29047, 29064, 29070, 29075, 29031, 29037, 29043 } },
    [29764] = { tier = "Tier 4", slot = "shoulder", name = "Pauldrons of the Fallen Defender", setPieces = { 29023, 29016, 29054, 29060, 29089, 29095, 29100 } },
    [29755] = { tier = "Tier 4", slot = "chest", name = "Chestguard of the Fallen Hero", setPieces = { 29077, 29082, 28964 } },
    [29754] = { tier = "Tier 4", slot = "chest", name = "Chestguard of the Fallen Champion", setPieces = { 29045, 29062, 29066, 29071, 29029, 29033, 29038 } },
    [29753] = { tier = "Tier 4", slot = "chest", name = "Chestguard of the Fallen Defender", setPieces = { 29019, 29012, 29050, 29056, 29087, 29091, 29096 } },
    [29756] = { tier = "Tier 4", slot = "hands", name = "Gloves of the Fallen Hero", setPieces = { 29080, 29085, 28968 } },
    [29757] = { tier = "Tier 4", slot = "hands", name = "Gloves of the Fallen Champion", setPieces = { 29048, 29065, 29067, 29072, 29032, 29034, 29039 } },
    [29758] = { tier = "Tier 4", slot = "hands", name = "Gloves of the Fallen Defender", setPieces = { 29020, 29017, 29055, 29057, 29090, 29092, 29097 } },
    [29765] = { tier = "Tier 4", slot = "legs", name = "Leggings of the Fallen Hero", setPieces = { 29078, 29083, 28966 } },
    [29766] = { tier = "Tier 4", slot = "legs", name = "Leggings of the Fallen Champion", setPieces = { 29046, 29063, 29069, 29074, 29030, 29036, 29042 } },
    [29767] = { tier = "Tier 4", slot = "legs", name = "Leggings of the Fallen Defender", setPieces = { 29022, 29015, 29053, 29059, 29088, 29094, 29099 } },
    [30242] = { tier = "Tier 5", slot = "head", name = "Helm of the Vanquished Champion", setPieces = { 30125, 30131, 30136, 30146, 30166, 30171, 30190 } },
    [30243] = { tier = "Tier 5", slot = "head", name = "Helm of the Vanquished Defender", setPieces = { 30115, 30120, 30152, 30161, 30219, 30228, 30233 } },
    [30244] = { tier = "Tier 5", slot = "head", name = "Helm of the Vanquished Hero", setPieces = { 30141, 30206, 30212 } },
    [30248] = { tier = "Tier 5", slot = "shoulder", name = "Pauldrons of the Vanquished Champion", setPieces = { 30127, 30133, 30138, 30149, 30168, 30173, 30194 } },
    [30249] = { tier = "Tier 5", slot = "shoulder", name = "Pauldrons of the Vanquished Defender", setPieces = { 30117, 30122, 30154, 30163, 30221, 30230, 30235 } },
    [30250] = { tier = "Tier 5", slot = "shoulder", name = "Pauldrons of the Vanquished Hero", setPieces = { 30143, 30210, 30215 } },
    [30236] = { tier = "Tier 5", slot = "chest", name = "Chestguard of the Vanquished Champion", setPieces = { 30123, 30129, 30134, 30144, 30164, 30169, 30185 } },
    [30237] = { tier = "Tier 5", slot = "chest", name = "Chestguard of the Vanquished Defender", setPieces = { 30113, 30118, 30150, 30159, 30216, 30222, 30231 } },
    [30238] = { tier = "Tier 5", slot = "chest", name = "Chestguard of the Vanquished Hero", setPieces = { 30139, 30196, 30214 } },
    [30239] = { tier = "Tier 5", slot = "hands", name = "Gloves of the Vanquished Champion", setPieces = { 30124, 30130, 30135, 30145, 30165, 30170, 30189 } },
    [30240] = { tier = "Tier 5", slot = "hands", name = "Gloves of the Vanquished Defender", setPieces = { 30114, 30119, 30151, 30160, 30217, 30223, 30232 } },
    [30241] = { tier = "Tier 5", slot = "hands", name = "Gloves of the Vanquished Hero", setPieces = { 30140, 30205, 30211 } },
    [30245] = { tier = "Tier 5", slot = "legs", name = "Leggings of the Vanquished Champion", setPieces = { 30126, 30132, 30137, 30148, 30167, 30172, 30192 } },
    [30246] = { tier = "Tier 5", slot = "legs", name = "Leggings of the Vanquished Defender", setPieces = { 30116, 30121, 30153, 30162, 30220, 30229, 30234 } },
    [30247] = { tier = "Tier 5", slot = "legs", name = "Leggings of the Vanquished Hero", setPieces = { 30142, 30207, 30213 } },
    [31097] = { tier = "Tier 6", slot = "head", name = "Helm of the Forgotten Conqueror", setPieces = { 30987, 30988, 30989, 31051, 31063, 31064 } },
    [31101] = { tier = "Tier 6", slot = "shoulder", name = "Pauldrons of the Forgotten Conqueror", setPieces = { 30996, 30997, 30998, 31054, 31069, 31070 } },
    [31089] = { tier = "Tier 6", slot = "chest", name = "Chestguard of the Forgotten Conqueror", setPieces = { 30990, 30991, 30992, 31052, 31065, 31066 } },
    [31093] = { tier = "Tier 6", slot = "hands", name = "Gloves of the Forgotten Conqueror", setPieces = { 30982, 30983, 30985, 31050, 31060, 31061 } },
    [31098] = { tier = "Tier 6", slot = "legs", name = "Leggings of the Forgotten Conqueror", setPieces = { 30993, 30995, 31053, 31067, 31068 } },
    [31095] = { tier = "Tier 6", slot = "head", name = "Helm of the Forgotten Protector", setPieces = { 30972, 30974, 31003, 31012, 31014, 31015 } },
    [31103] = { tier = "Tier 6", slot = "shoulder", name = "Pauldrons of the Forgotten Protector", setPieces = { 30979, 30980, 31006, 31022, 31023, 31024 } },
    [31091] = { tier = "Tier 6", slot = "chest", name = "Chestguard of the Forgotten Protector", setPieces = { 30975, 30976, 31004, 31016, 31017, 31018 } },
    [31094] = { tier = "Tier 6", slot = "hands", name = "Gloves of the Forgotten Protector", setPieces = { 30969, 30970, 31001, 31007, 31008 } },
    [31100] = { tier = "Tier 6", slot = "legs", name = "Leggings of the Forgotten Protector", setPieces = { 30977, 30978, 31005, 31019, 31020, 31021 } },
    [31096] = { tier = "Tier 6", slot = "head", name = "Helm of the Forgotten Vanquisher", setPieces = { 31027, 31037, 31039, 31040, 31056 } },
    [31102] = { tier = "Tier 6", slot = "shoulder", name = "Pauldrons of the Forgotten Vanquisher", setPieces = { 31030, 31047, 31048, 31049, 31059 } },
    [31090] = { tier = "Tier 6", slot = "chest", name = "Chestguard of the Forgotten Vanquisher", setPieces = { 31028, 31041, 31042, 31043, 31057 } },
    [31092] = { tier = "Tier 6", slot = "hands", name = "Gloves of the Forgotten Vanquisher", setPieces = { 31026, 31032, 31034, 31035, 31055 } },
    [31099] = { tier = "Tier 6", slot = "legs", name = "Leggings of the Forgotten Vanquisher", setPieces = { 31029, 31044, 31045, 31046, 31058 } },
    [34848] = { tier = "Tier 6.5", slot = "wrist", name = "Bracers of the Forgotten Conqueror", setPieces = { 34431, 34432, 34433, 34434, 34435 } },
    [34853] = { tier = "Tier 6.5", slot = "waist", name = "Belt of the Forgotten Conqueror", setPieces = { 34485, 34487, 34488, 34527, 34528 } },
    [34856] = { tier = "Tier 6.5", slot = "feet", name = "Boots of the Forgotten Conqueror", setPieces = { 34559, 34560, 34561, 34562, 34563 } },
    [34851] = { tier = "Tier 6.5", slot = "wrist", name = "Bracers of the Forgotten Protector", setPieces = { 34437, 34438, 34441, 34442, 34443 } },
    [34854] = { tier = "Tier 6.5", slot = "waist", name = "Belt of the Forgotten Protector", setPieces = { 34542, 34543, 34546, 34547, 34549 } },
    [34857] = { tier = "Tier 6.5", slot = "feet", name = "Boots of the Forgotten Protector", setPieces = { 34565, 34566, 34568, 34569, 34570 } },
    [34852] = { tier = "Tier 6.5", slot = "wrist", name = "Bracers of the Forgotten Vanquisher", setPieces = { 34444, 34445, 34446, 34447, 34448 } },
    [34855] = { tier = "Tier 6.5", slot = "waist", name = "Belt of the Forgotten Vanquisher", setPieces = { 34554, 34555, 34556, 34557, 34558 } },
    [34858] = { tier = "Tier 6.5", slot = "feet", name = "Boots of the Forgotten Vanquisher", setPieces = { 34571, 34572, 34573, 34574, 34575 } },
}

local TOKEN_CLASS_GROUPS = {
    ["Fallen Hero"] = { "HUNTER", "MAGE", "WARLOCK" },
    ["Vanquished Hero"] = { "HUNTER", "MAGE", "WARLOCK" },
    ["Fallen Champion"] = { "PALADIN", "ROGUE", "SHAMAN" },
    ["Vanquished Champion"] = { "PALADIN", "ROGUE", "SHAMAN" },
    ["Fallen Defender"] = { "DRUID", "PRIEST", "WARRIOR" },
    ["Vanquished Defender"] = { "DRUID", "PRIEST", "WARRIOR" },
    ["Forgotten Conqueror"] = { "PALADIN", "PRIEST", "WARLOCK" },
    ["Forgotten Protector"] = { "HUNTER", "SHAMAN", "WARRIOR" },
    ["Forgotten Vanquisher"] = { "DRUID", "MAGE", "ROGUE" },
}

ns.tierTokens.bySetPieceId = {}
for tokenId, token in pairs(ns.tierTokens.byTokenId) do
    token.tokenId = tokenId
    for suffix, classes in pairs(TOKEN_CLASS_GROUPS) do
        if token.name and token.name:find(suffix, 1, true) then
            token.classes = classes
            token.classMask = {}
            for _, classFile in ipairs(classes) do token.classMask[classFile] = true end
            break
        end
    end
    for _, setPieceId in ipairs(token.setPieces or {}) do
        ns.tierTokens.bySetPieceId[setPieceId] = token
    end
end

function ns.tierTokens.ResolveLootItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    return ns.tierTokens.byTokenId[itemId] or ns.tierTokens.bySetPieceId[itemId]
end

function ns.tierTokens.ClassCanUseLootItem(itemId, classFile)
    local token = ns.tierTokens.ResolveLootItem(itemId)
    if not token or not token.classMask then return nil end
    return token.classMask[tostring(classFile or ""):upper()] == true
end
