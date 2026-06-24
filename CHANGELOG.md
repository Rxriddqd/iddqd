# iddqd Changelog

## 1.2.4

### Loot History
- Fixed traded items that are received back or sold after a trade so the History session keeps tracking the correct current holder.
- Fixed vendoring a recently received traded item not updating to **Vendored**.
- Stopped inactive items from being shown as **Final** just because enough time passed.
- The **Final** column now only shows a player after a real finalizing event, such as equip, BoP trade-window expiry, recipe learned, or tier-token turn-in.
- Added explicit recipe-learned and tier-token turn-in finalization handling.
- Kept the 72-hour lifecycle window as a stale-event guard without using it as a display finalizer.

### Auto Marking
- Added Mount Hyjal wave-trash NPC mappings under a dedicated **Trash** category.
- Added Mount Hyjal bosses under a dedicated **Bosses** category.
- Added a collapsible **Trash Wave Info** guide for Rage Winterchill, Anetheron, Kaz'rogal, and Azgalor.
- Reworked the Hyjal wave guide into two-column boss tables with right-aligned wave labels for easier reading.

## 1.2.31

### Hotfix
- Fixed the Ready Check monitor showing Prayer of Spirit under the wrong buff group by adding proper Spirit tracking.
- Added a dedicated Spirit column in Ready Check with the correct icon and tooltip support.
- Excluded Warriors and Rogues from missing Spirit announcements, matching the Arcane Intellect mana-user filter.
- Kept Ready Check player rows in stable roster positions when players press Ready or Not Ready.
- Fixed Gamba Settings overflowing outside the addon frame when the addon window is resized smaller.

## 1.2.3

### Loot Distribution
- Added smart usable-loot filtering for the Loot tab and mini-loot window, including tier-token class filtering.
- Added a **Pass** response in both the Loot tab and mini-loot window so raiders can clear accidental votes.
- Mini-loot now updates live when new loot is added while the window is already open.
- Added an optional local setting to auto-open mini-loot when loot is added.
- Hid the mini-loot scrollbar when there is nothing to scroll.
- Moved Loot-tab options into a dedicated **Loot Settings** popup and removed the old manual-add text box.
- Added an info tooltip next to the Loot title explaining shift-click manual item adding.
- Limited item tooltips in the Loot tab to the item icon/name area instead of the full row.
- Added raid-leader-controlled guild-rank loot permissions, including Guild Rank, Assist AND Guild Rank, and Assist OR Guild Rank modes.
- Loot Settings now closes when clicking outside the popup and stays open while dropdowns are being used during background refreshes.

### Attendance
- Added configurable attendance auto-snapshot modes for raid pulls/kills.
- Expanded attendance snapshots into a compact 8-group raid layout.
- Added class icons and class-colored names to attendance raid groups.
- Added per-snapshot attendance export.
- Improved attendance export modal sizing and scrolling.
- Tightened attendance raid-group spacing and added clearer spacing below group headers.

### Ready Check
- Added a new **Ready Check** raid tool with a Blizzard ready-check monitor, floating status window, test mode, and local display settings.
- Made the Ready Check monitor compact enough for large raids, with dynamic height for small groups.
- Added class-colored names, clearer group labels, status sorting, buff icons, and spell tooltips.
- Added a countdown progress bar and yellow seconds-remaining timer.
- Added remembered monitor position, right-click dismiss, and protection against dismissed monitors reopening from late ready-check responses.
- Enabled the monitor by default and added live opacity control for both test and real monitors.
- Added smart food tracking, including showing when a player has started eating before the food buff is applied.
- Added flask support for either a flask or separate Battle plus Guardian elixirs.
- Added smart raid-buff tracking for Stamina, Shadow Protection, Mark/Gift of the Wild, Paladin Blessings, and Arcane Intellect.
- Added provider-gated raid-buff columns so buffs are only expected when the relevant class exists in the group.
- Added party support for Mark/Gift of the Wild tracking.
- Displayed all Paladin Blessings per player and announced specific missing blessings by blessing/paladin when enough paladins are present.
- Ignored offline players in missing-buff announcements.
- Added Ready Check Settings, matching the Loot Settings popup pattern.
- Added configurable announcements for missing food, flask/elixirs, and raid buffs, with per-buff sub-options.
- Added end-of-ready-check reports for Ready, Not Ready, AFK, and everyone-ready status.
- Added announcement coordination so only one updated addon client announces automatically, preferring raid leader, then assists, then one fallback user.
- Added `/iddqd check` and `/id check` to announce configured missing-buff reports without starting a ready check.
- Added a Ready Check help tooltip next to the tab title.

### Invite
- Improved guild-only keyword invites so pending whispers are retried from guild roster updates instead of relying on a single delayed retry.
- Clarified the Invite tab checkbox label to **Auto-invite whispers** and updated the keyword hint.

### Overview
- Rebuilt the Overview page into two side-by-side tables: guild version check and changelog.
- Added collapsible changelog version rows with simplified expanded notes.

### UI
- Fixed odd dropdown button/menu corner rendering by using the shared button styling path.
- Improved dropdown chevron readability.
- Fixed export modal text overflow issues.
- Improved slider styling and made the Gamba slider knob match.
- Reduced Gamba sound dropdown text size so long sound names fit better.
- Added **NYI** markers behind Raid Map, Visual Note, and Assignments buttons for unfinished pages.
- Renamed the menu button from **Raid Assignments** to **Assignments**.

## 1.2.2

### Loot Distribution
- **Much faster sync** — manually added items now appear on everyone's Loot tab near-instantly (single-message fast path on a priority queue instead of a slow chunked handshake).
- **New "BiS" response** — a pink BiS button before Upgrade, in both the Loot tab and the mini-loot window.
- **Distribution permissions** — the raid leader can now choose who may add / remove / award loot: **Raid Leader + Assists** (default) or **Raid Leader only**. Set on the Loot tab; broadcast to the whole raid so assists can't act when restricted.
- **Respond directly on the Loot tab** — every item row has inline response buttons (BiS / Upgrade / Minor / Off-Spec / PvP); raiders can respond without an officer pressing Ask Raid. Selected response stays colored, the rest grey out.
- **Mini-loot window** now caps at 12 items with a scrollbar; auto-opens for everyone by default with a single "Don't auto-open" opt-out (moved onto the Loot tab).
- Manually-added items can always be re-added (a previously awarded/removed item from last week's run is no longer blocked), and re-adds reliably reach every raider.
- Clearer item rows: separate Awarded To (class-colored) and Traded columns; awarding to yourself shows as Traded.
- All announcements carry an `[iddqd]` prefix.

### Loot History
- Dungeon and raid **session icons** for every Classic / TBC / WotLK instance (last-boss art).
- Session cards redesigned — larger icons, instance name + date + drop count.
- Synced sessions now show the correct instance name (recovered from the session id) instead of "Loot session".
- **5-man dungeon loot stays private** — only raid sessions from the 9 TBC raids, with ≥60% guild members, are shared to the guild.
- Item icons now load immediately when opening a session (no need to tab away and back).
- Only Rare/Epic gear is tracked (quest items like Coilfang Armaments and greens no longer clutter history); fixed bosses being grouped incorrectly.

### New pages
- **Set Role** (right-click a player), **Attendance** (roster snapshots), **Raid Assignments** (shareable notes), **Raid Map** (strategy board), **Visual Note** (scratchpad), **Permissions**, and **Import / Export**.

### Loot announcements
- Quality filter fixed (now correctly respects the minimum-quality setting), stack sizes shown (e.g. `[Tin Ore] x4`), no duplicate announcements, and the minimum-quality dropdown is rarity-colored.

### UI
- Professions "All Professions" list is much faster (cached); Raid Groups defaults to level 70+ and loads faster.
- Item icons render cleanly without borders.

## 1.2.1

- First pass of the Loot Distribution system, Set Role, and the new raid-tool pages (later refined in 1.2.2).

## 1.2.0

A ground-up rewrite of raid loot tracking and sharing, plus a new guild-scale professions
sync system. Loot data is now event-sourced, automatically synced across the guild, and
dedup-proof at raid scale.

### Raid Loot Ledger — complete overhaul

The loot system was rebuilt from scratch around a convergent, event-sourced model. Every
action on an item (looted, traded, disenchanted, etc.) is recorded as an immutable event;
each client folds those events into the same final state, so the whole guild converges to one
correct loot history — automatically.

**Full item lifecycle tracking**
- Tracks each drop end to end: **looted → traded → finalized**, plus terminal events for
  **disenchant**, **vendor** (sold to an NPC), **delete**, **guild bank deposit**, and
  **tier token turn-in**.
- **Trade tracking:** records the recipient of completed trades only (cancelled trades are
  ignored), so you can see who an item actually ended up with — even across multiple trades.
- **Trade-window timer:** Bind-on-Pickup items with an active trade window show the remaining
  time while still tradeable, and automatically finalize when the window expires.
- **Bind-on-Pickup, no trade window → finalized immediately** on loot (bound to the looter).
  **Bind-on-Equip items stay open** (still tradeable/sellable) until equipped, sold, or
  disenchanted.
- **New `vendored` status** for items sold to a vendor.
- **Correct event precedence:** a more specific disposition always wins — e.g. an item that
  was finalized and then disenchanted shows as *disenchanted*, not *finalized*. A finalized
  item can still be deleted, disenchanted, vendored, or re-traded.

**Automatic, guild-scale, convergent sharing**
- Loot is **shared automatically** with the rest of the guild — online or offline — with no
  need to open a panel or press a button.
- Built on the proven guild sync stack: throttled addon comms (ChatThrottleLib), hash-based
  manifests, owner-first / relay pull for offline owners, and checksum-verified chunked
  transfer. Designed to hold up in 40-person raids without flooding chat.
- **No duplicate data:** every drop is identified deterministically (by its source boss and
  item), so the same item looted or seen by multiple members collapses to a single shared
  record on every client.
- **PuG privacy:** a raid session is only shared with the guild when a sufficient share of the
  raid are guild members. Otherwise the session is **private to you** and is never broadcast,
  served, or applied from anyone else. A session that crosses the threshold mid-run is
  promoted to shared and never demoted.

**Reliable boss & instance attribution**
- Loot is attributed to the **correct boss and instance** using a built-in loot table covering
  all dungeons and raids (Classic, TBC, Wrath) — ~7,000 items — with no dependency on other
  addons being installed by you or your guildmates.
- Attribution is keyed to the looted item itself, not to kill timing, so killing trash mobs
  right after a boss no longer mis-attributes the boss's loot.

**Smart capture filter**
- The ledger records **only items that belong to the instance you're currently in** (its boss
  and instance drops). Trade goods, world-drop greens, consumables, quest items, and vendor
  junk are ignored at the source — keeping the loot history clean, relevant, and free of noise.

**Rebuilt History panel**
- Loot is grouped by boss, shown with readable boss names instead of raw creature IDs.
- Boss groups are **collapsible / expandable** with `+` / `-` toggles and a per-boss drop
  count.
- The window **updates live** as loot is taken, items are traded, and synced changes arrive —
  no more closing and reopening to see updates.
- Status colors: disenchanted shown in blue, vendored in gold, removed in red.

### Professions sync

- New guild-scale professions sharing: recipe knowledge is synced automatically across the
  guild using the same robust, throttled, convergent sync stack used for loot.
- Professions panel rebuilt — filter by profession, browse by category
  (items / slots / enchants / elixirs / potions / etc.), expand a category, and click a
  craftable to see exactly who in the guild can make it.
- Every profession item is mapped by type for accurate categorization; **Fishing** is now
  included.
- Custom themed search box for filtering recipes.

### Fixes & hardening

- **Fixed a login freeze / stutter** caused by processing large loot histories on load
  (replaced an O(n²) merge with bounded, deferred processing).
- **Player-name consistency:** the same player is no longer recorded under two spellings
  (e.g. with vs. without a realm suffix), which previously fragmented trade and loot history.
- **Post-sync updates now propagate:** when loot changes after an initial sync (for example an
  item deleted shortly after looting), the change reliably reaches everyone instead of leaving
  a guildmate on stale data.
- **Convergence at scale:** deterministic ordering and identity throughout the sync path
  prevent two clients from ever settling on different histories for the same session.
- **Sync hardening for large guilds:** jittered login broadcasts and re-advertise handling to
  survive simultaneous logins, owner/relay de-duplication, bounded retries, queue-stall
  protection, and corruption-proof multi-part transfers — all to avoid chat floods and stuck
  syncs in big raids.

### Notes for guild members

- For loot to share, members need iddqd **1.2.0 or later**; older versions won't exchange the
  new loot data.
- Loot from earlier versions is not carried over — the new ledger starts fresh on first load.
