local ADDON, ns = ...

ns.raidLootSources = ns.raidLootSources or {}
ns.raidLootSources.byItemId = ns.raidLootSources.byItemId or {}

-- Loot-history BLACKLIST: item IDs that must NEVER be recorded in History sessions, even though
-- they're high quality and/or in a loot table. The Tracker skips capturing any blacklisted id.
--   * Kael'thas (Tempest Keep) conjured encounter weapons (30311-30318): legendary-quality items
--     that exist only during the fight — never real loot.
--   * Boss-dropped QUEST items that aren't loot worth tracking (e.g. Vashj's Vial Remnant, a
--     Mount Hyjal attunement quest item).
ns.lootBlacklist = ns.lootBlacklist or {}
do
    local B = ns.lootBlacklist
    -- Kael'thas conjured legendaries (Warp Slicer, Infinity Blade, Staff of Disintegration,
    -- Phaseshift Bulwark, Devastation, Cosmic Infuser, Netherstrand Longbow + 30315 Nether Spike).
    for id = 30311, 30318 do B[id] = true end
    -- Quest items from bosses.
    B[29906] = true   -- Vashj's Vial Remnant (Lady Vashj, SSC) — Mount Hyjal attunement
end

ns.raidLootSources.byItemId[21903] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[21904] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[22545] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[22559] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[22560] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[22561] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[23631] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[28453] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28454] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28477] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28502] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28503] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28504] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28505] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28506] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28507] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28508] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28509] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28510] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[28511] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28512] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28514] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28515] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28516] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28517] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28518] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28519] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28520] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28521] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28522] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28523] = { instance = "Karazhan", source = "Maiden" }
ns.raidLootSources.byItemId[28524] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28525] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28528] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28529] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28530] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28545] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28565] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28566] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28567] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28568] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28569] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28570] = { instance = "Karazhan", source = "Moroes" }
ns.raidLootSources.byItemId[28572] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28573] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28578] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28579] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28581] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28582] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28583] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28584] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28585] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28586] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28587] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28588] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28589] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28590] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28591] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28592] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28593] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28594] = { instance = "Karazhan", source = "Opera Event" }
ns.raidLootSources.byItemId[28597] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28599] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28600] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28601] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28602] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28603] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28604] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28606] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28608] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28609] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28610] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28611] = { instance = "Karazhan", source = "Nightbane" }
ns.raidLootSources.byItemId[28612] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28621] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28631] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28633] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28647] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28649] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[28652] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28653] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28654] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28655] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28656] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28657] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28658] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28659] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28660] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28661] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28662] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28663] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28666] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28669] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28670] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28671] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28672] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28673] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28674] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28675] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28726] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28727] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28728] = { instance = "Karazhan", source = "Shade of Aran" }
ns.raidLootSources.byItemId[28729] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28730] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28731] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28732] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28733] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28734] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28735] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28740] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28741] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28742] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28743] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28744] = { instance = "Karazhan", source = "Netherspite" }
ns.raidLootSources.byItemId[28745] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28746] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28747] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28748] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28749] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28750] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28751] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28752] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28753] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28754] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28755] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28756] = { instance = "Karazhan", source = "Chess Event" }
ns.raidLootSources.byItemId[28757] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28762] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28763] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28764] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28765] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28766] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28767] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28768] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28770] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28771] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28772] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28773] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[28774] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28775] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28776] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28777] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28778] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28779] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28780] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28781] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28782] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28783] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28785] = { instance = "Karazhan", source = "Illhoof" }
ns.raidLootSources.byItemId[28789] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[28794] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28795] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28796] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28797] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28799] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28800] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28801] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[28802] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28803] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28804] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28810] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28822] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28823] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28824] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28825] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28826] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28827] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28828] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[28830] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[29458] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[29753] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[29754] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[29755] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[29756] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[29757] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[29758] = { instance = "Karazhan", source = "The Curator" }
ns.raidLootSources.byItemId[29759] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[29760] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[29761] = { instance = "Karazhan", source = "Malchezaar" }
ns.raidLootSources.byItemId[29762] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[29763] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[29764] = { instance = "Gruul's Lair", source = "Maulgar" }
ns.raidLootSources.byItemId[29765] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[29766] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[29767] = { instance = "Gruul's Lair", source = "Gruul" }
ns.raidLootSources.byItemId[29918] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29920] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29921] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29922] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29923] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29924] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29925] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29947] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29948] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29949] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[29950] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29951] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29962] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29965] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29966] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29972] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29976] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29977] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29981] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29982] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[29983] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[29984] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[29985] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[29986] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[29987] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29988] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29989] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29990] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29991] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29992] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29993] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29994] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29995] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29996] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29997] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[29998] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[30008] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30020] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30021] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30022] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30023] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30024] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30025] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30026] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30027] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30028] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30029] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30030] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30047] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30048] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30049] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30050] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30051] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30052] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30053] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30054] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30055] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30056] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30057] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30058] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30059] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30060] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30061] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30062] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30063] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30064] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30065] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30066] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30067] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30068] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30075] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30079] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30080] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30081] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30082] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30083] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30084] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30085] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30090] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30091] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30092] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30095] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30096] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30097] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30098] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30099] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30100] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30101] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30102] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30103] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30104] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30105] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30106] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30107] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30108] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30109] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30110] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30111] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30112] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30183] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30183] = { instance = "Tempest Keep", source = "Trash" }
ns.raidLootSources.byItemId[30236] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[30237] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[30238] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[30239] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30240] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30241] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30242] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30243] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30244] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30245] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30246] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30247] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30248] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[30249] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[30250] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[30280] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30280] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30281] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30281] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30282] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30282] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30283] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30283] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30301] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30301] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30302] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30302] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30303] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30303] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30304] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30304] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30305] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30305] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30306] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30306] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30307] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30307] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30308] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30308] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30321] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30321] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30322] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30322] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30323] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30323] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30324] = { instance = "Tempest Keep", source = "Recipes" }
ns.raidLootSources.byItemId[30324] = { instance = "Serpentshrine Cavern", source = "Recipes" }
ns.raidLootSources.byItemId[30446] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[30447] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[30448] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[30449] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[30450] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[30480] = { instance = "Karazhan", source = "Attumen" }
ns.raidLootSources.byItemId[30619] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[30620] = { instance = "Serpentshrine Cavern", source = "Trash" }
ns.raidLootSources.byItemId[30621] = { instance = "Serpentshrine Cavern", source = "Lady Vashj" }
ns.raidLootSources.byItemId[30626] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30627] = { instance = "Serpentshrine Cavern", source = "Leotheras" }
ns.raidLootSources.byItemId[30629] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30641] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30642] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30643] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30644] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30663] = { instance = "Serpentshrine Cavern", source = "Karathress" }
ns.raidLootSources.byItemId[30664] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[30665] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[30666] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30667] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30668] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30673] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30674] = { instance = "Karazhan", source = "Trash" }
ns.raidLootSources.byItemId[30675] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30676] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30677] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30678] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30680] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30681] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30682] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30683] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30684] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30685] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30686] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30687] = { instance = "Karazhan", source = "Servants" }
ns.raidLootSources.byItemId[30720] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[30722] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30723] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30724] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30725] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30726] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30727] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30728] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30729] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30730] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30731] = { instance = "World Bosses", source = "Doomwalker" }
ns.raidLootSources.byItemId[30732] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30733] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30734] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30735] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30736] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30737] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30738] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30739] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30740] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30741] = { instance = "World Bosses", source = "Doom Lord Kazzak" }
ns.raidLootSources.byItemId[30861] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30862] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30863] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30864] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30865] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30866] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30868] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30869] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30870] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30871] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30872] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30873] = { instance = "Hyjal Summit", source = "Winterchill" }
ns.raidLootSources.byItemId[30874] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30878] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30879] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30880] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30881] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30882] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30883] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30884] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30885] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30886] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30887] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30888] = { instance = "Hyjal Summit", source = "Anetheron" }
ns.raidLootSources.byItemId[30889] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30891] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30892] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30893] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30894] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30895] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30896] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30897] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30898] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30899] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30900] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30901] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[30902] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30903] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30904] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30905] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30906] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30907] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30908] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30909] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30910] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30911] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30912] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30913] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[30914] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30915] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30916] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30917] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30918] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[30919] = { instance = "Hyjal Summit", source = "Kaz'rogal" }
ns.raidLootSources.byItemId[31089] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[31090] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[31091] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[31092] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[31093] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[31094] = { instance = "Hyjal Summit", source = "Azgalor" }
ns.raidLootSources.byItemId[31095] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[31096] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[31097] = { instance = "Hyjal Summit", source = "Archimonde" }
ns.raidLootSources.byItemId[31098] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[31099] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[31100] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[31101] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[31102] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[31103] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32232] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32234] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32235] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32236] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32237] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32238] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32239] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32240] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32241] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32242] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32243] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32245] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32247] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32248] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32250] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32251] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32252] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32253] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32254] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32255] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32256] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32257] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32258] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32259] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32260] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32261] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32262] = { instance = "Black Temple", source = "Supremus" }
ns.raidLootSources.byItemId[32263] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32264] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32265] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32266] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32267] = { instance = "Tempest Keep", source = "Solarian" }
ns.raidLootSources.byItemId[32268] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32269] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32270] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32271] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32273] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32275] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32276] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32278] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32279] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32280] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32285] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32289] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32295] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32296] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32297] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32298] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32303] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32307] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32323] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32324] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32325] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32326] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32327] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32328] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32329] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32330] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32331] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32332] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32333] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32334] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32335] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32336] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32337] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32338] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32339] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32340] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32341] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32342] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32343] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32344] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32345] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32346] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32347] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32348] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32349] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32350] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32351] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32352] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32353] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32354] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32361] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32362] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32363] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32365] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32366] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32367] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32368] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32369] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32370] = { instance = "Black Temple", source = "Shahraz" }
ns.raidLootSources.byItemId[32373] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32374] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32375] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32376] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32377] = { instance = "Black Temple", source = "Naj'entus" }
ns.raidLootSources.byItemId[32385] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[32405] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[32458] = { instance = "Tempest Keep", source = "Kael'thas" }
ns.raidLootSources.byItemId[32471] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32483] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32496] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32497] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32500] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32501] = { instance = "Black Temple", source = "Gurtogg" }
ns.raidLootSources.byItemId[32505] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32510] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32512] = { instance = "Black Temple", source = "Gorefiend" }
ns.raidLootSources.byItemId[32513] = { instance = "Black Temple", source = "Shade" }
ns.raidLootSources.byItemId[32515] = { instance = "Tempest Keep", source = "Void Reaver" }
ns.raidLootSources.byItemId[32516] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[32517] = { instance = "Black Temple", source = "Reliquary" }
ns.raidLootSources.byItemId[32518] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32519] = { instance = "Black Temple", source = "Council" }
ns.raidLootSources.byItemId[32521] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32524] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32525] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32526] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32527] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32528] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32589] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32589] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32590] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32590] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32591] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32591] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32592] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32593] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32606] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32608] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32609] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32609] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32736] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32737] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32738] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32739] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32744] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32745] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32746] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32747] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32748] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32749] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32750] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32751] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32752] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32753] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32754] = { instance = "Black Temple", source = "Recipes" }
ns.raidLootSources.byItemId[32755] = { instance = "Hyjal Summit", source = "Recipes" }
ns.raidLootSources.byItemId[32837] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32838] = { instance = "Black Temple", source = "Illidan" }
ns.raidLootSources.byItemId[32943] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32944] = { instance = "Tempest Keep", source = "Al'ar" }
ns.raidLootSources.byItemId[32945] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[32945] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32946] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[32946] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[33054] = { instance = "Serpentshrine Cavern", source = "Lurker Below" }
ns.raidLootSources.byItemId[33055] = { instance = "Serpentshrine Cavern", source = "Hydross" }
ns.raidLootSources.byItemId[33058] = { instance = "Serpentshrine Cavern", source = "Morogrim" }
ns.raidLootSources.byItemId[33102] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33191] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33203] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33206] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33211] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33214] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33215] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33216] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33281] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33283] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33285] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33286] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33293] = { instance = "Zul'Aman", source = "Akil'zon" }
ns.raidLootSources.byItemId[33297] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33298] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33299] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33300] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33303] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33307] = { instance = "Zul'Aman", source = "Recipes" }
ns.raidLootSources.byItemId[33317] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33322] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33326] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33327] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33328] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33329] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33332] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33354] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33356] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33357] = { instance = "Zul'Aman", source = "Jan'alai" }
ns.raidLootSources.byItemId[33388] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33389] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33421] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33432] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33446] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33453] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33463] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33464] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33465] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33466] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33467] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33468] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33469] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33471] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33473] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33474] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33476] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33478] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33479] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33480] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33481] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33483] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33489] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33490] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33491] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33492] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33493] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33494] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33495] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33496] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33497] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33498] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33499] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33500] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33533] = { instance = "Zul'Aman", source = "Halazzi" }
ns.raidLootSources.byItemId[33590] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33591] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33592] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33640] = { instance = "Zul'Aman", source = "Nalorakk" }
ns.raidLootSources.byItemId[33805] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33809] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[33828] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33829] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[33830] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33831] = { instance = "Zul'Aman", source = "Zul'jin" }
ns.raidLootSources.byItemId[33971] = { instance = "Zul'Aman", source = "Timed Event" }
ns.raidLootSources.byItemId[34009] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[34009] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[34010] = { instance = "Hyjal Summit", source = "Trash" }
ns.raidLootSources.byItemId[34010] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[34011] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[34012] = { instance = "Black Temple", source = "Trash" }
ns.raidLootSources.byItemId[34029] = { instance = "Zul'Aman", source = "Malacrass" }
ns.raidLootSources.byItemId[34164] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34165] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34166] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34167] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34168] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34169] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34170] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34176] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34177] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34178] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34179] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34180] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34181] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34182] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34183] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34184] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34185] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34186] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34188] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34189] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34190] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34192] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34193] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34194] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34195] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34196] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34197] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34198] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34199] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34202] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34203] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34204] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34205] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34206] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34208] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34209] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34210] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34211] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34212] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34213] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34214] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34215] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34216] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34228] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34229] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34230] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34231] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34232] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34233] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34234] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34240] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34241] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34242] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34243] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34244] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34245] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34247] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34329] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34331] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34332] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34333] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34334] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34335] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34336] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34337] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34339] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34340] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34341] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34342] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34343] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34344] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34345] = { instance = "Sunwell Plateau", source = "Kil'Jaeden" }
ns.raidLootSources.byItemId[34346] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34347] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34348] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34349] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34350] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34351] = { instance = "Sunwell Plateau", source = "Trash" }
ns.raidLootSources.byItemId[34352] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34427] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34428] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34429] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34430] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[34845] = { instance = "Magtheridon's Lair", source = "Magtheridon" }
ns.raidLootSources.byItemId[34848] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34848] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34851] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34851] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34852] = { instance = "Sunwell Plateau", source = "Kalecgos" }
ns.raidLootSources.byItemId[34852] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34853] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34853] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34854] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34854] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34855] = { instance = "Sunwell Plateau", source = "Brutallus" }
ns.raidLootSources.byItemId[34855] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34856] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34856] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34857] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[34857] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34858] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[34858] = { instance = "Sunwell Plateau", source = "Felmyst" }
ns.raidLootSources.byItemId[35186] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35189] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35190] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35192] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35193] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35194] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35195] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35196] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35198] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35199] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35200] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35201] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35202] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35203] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35204] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35205] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35206] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35207] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35208] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35209] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35210] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35211] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35212] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35213] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35214] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35215] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35216] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35217] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35218] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35219] = { instance = "Sunwell Plateau", source = "Recipes" }
ns.raidLootSources.byItemId[35282] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[35283] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[35284] = { instance = "Sunwell Plateau", source = "M'uru" }
ns.raidLootSources.byItemId[35290] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[35291] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[35292] = { instance = "Sunwell Plateau", source = "Eredar Twins" }
ns.raidLootSources.byItemId[35733] = { instance = "Sunwell Plateau", source = "Trash" }
