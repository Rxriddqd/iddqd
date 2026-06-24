# iddqd Addon Architecture

This addon uses a small custom module system instead of AceAddon. Files are loaded in
`Includes.xml`; modules are created with `ns:NewModule(name)` and receive lifecycle calls from
`Core/Bootstrap.lua`.

## Lifecycle

- `OnInit` is for DB setup, prefix registration, and panel registration.
- `OnEnable` is for runtime event registration and delayed startup work.
- `OnEnable` methods that register events or slash commands should be idempotent:
  `if self._enabled then return end`.
- `Data/DB.lua` must initialize before feature modules read persisted data.

## Shared Services

- `Core/Events.lua` owns WoW event registration and dispatch.
- `Core/Comm.lua` owns addon-message prefix registration, addon-message sending, chunk splitting,
  and small transport-safe field helpers.
- `Core/Timers.lua` owns timer wrappers, debouncing, and repeat intervals.
- `Core/Players.lua` owns player-name normalization, short/full name conversion, and
  compatibility-safe player comparisons.
- Feature modules should prefer these services over direct `C_ChatInfo`, `SendAddonMessage`, or
  ad hoc timer token code, while preserving existing wire formats.

## Persistence

- `Data/Defaults.lua` is the account-wide default schema.
- `Data/DB.lua` owns additive default backfill and destructive/non-additive migrations.
- Feature stores may own sub-schema protocol resets when a feature's data shape breaks, but the
  owning module must make that explicit with a local protocol/schema version.

## Feature Boundaries

- Store modules own persisted data shape and deterministic merge/compute logic.
- Sync modules own wire protocol, chunking, manifests, retry/NAK behavior, and sender isolation.
- Scanner/tracker modules own WoW API/event capture.
- Panels own presentation and call feature APIs; panels should not own sync or persistence rules.

## Current Legacy Boundaries

- `Modules/Professions/Professions.lua` is the legacy v5 professions controller/sync path.
- `Modules/Professions/Store.lua`, `Scanner.lua`, and `Sync.lua` are the canonical v7 path.
- The legacy path stays compatibility-safe until it can be removed deliberately. Do not add new
  professions sync behavior to the legacy module.

## Comm Rules

- Do not change a `COMM_PREFIX`, op name, field order, delimiter, or protocol version as part of a
  mechanical refactor.
- Use `ChatThrottleLib` through `Core/Comm.lua` for bulk or normal addon traffic when possible.
- Always ignore unrelated prefixes and incompatible protocol versions before parsing payloads.
- Namespace incoming streams by sender when stream IDs are locally generated.

## UI Rules

- UI panels register with `UI/Nav.lua`.
- Long-lived UI modules should expose `Refresh` or a small explicit update API.
- Runtime modules should notify panels through those APIs; panels should not poll business state
  unless the interaction is inherently live.
