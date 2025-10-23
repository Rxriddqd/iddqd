# Project Architecture (iddqd.app)

> Target runtime: Node.js 22 (ESM). Discord.js v14. Components v2. TypeScript strict mode.

## High-Level Layout
- `src/app.ts`: loads environment (`src/config/env.ts`), constructs the Discord client (`src/core/client.ts`), and logs in.
- `src/config/*`: runtime configuration helpers. `env.ts` for process env validation, `sheets.ts` for raid sheet ranges.
- `src/core/*`: infrastructure concerns (client builder, logger, Google Sheets helpers re-exported via `core/index.ts`).
- `src/interactions/*`: slash/ctx command discovery, interaction router, dashboard renderers, component handlers, and Vitest specs.
- `src/features/*`: self-contained feature domains (auto-react, emotes, games/flaskgamba, logging, reports, roles, softres, summon, tier3, yappers).
- `types/*`: shared runtime type definitions for commands and Components v2 payloads.
- `scripts/*`: operational scripts (command management, summon refresh, sheet diagnostics).
- `docs/*`: architecture notes (this file) and Components v2 reference.

## Boot Sequence
1. **`src/app.ts`**
   - Loads `.env` via `dotenv/config`.
   - Validates required env vars (`DISCORD_TOKEN`, `DISCORD_CLIENT_ID`, optional guild id, DB URL) with `zod`.
   - Builds a `Client` instance through `buildClient()` and logs in; login failures abort the process after logging.
2. **`src/core/client.ts`**
   - Configures intents for guild + message content workflows and enables message/member/channel partials.
   - Registers `InteractionCreate` -> `onInteraction` (`src/interactions/interactionHandler.ts`).
   - On the first `ClientReady`:
     - Refreshes/publishes the pinned admin dashboard in `DASHBOARD_CHANNEL_ID` using Components v2 and preloads separator attachments.
     - Initializes Tier3 review tooling when `TIER3_CHANNEL_ID` is present, pre-registering button handlers and syncing Google Sheet state.
     - Pre-registers FlaskGamba handlers when `FLASKGAMBA_CHANNEL_ID` is configured.
     - Refreshes the summon panel (`refreshSummonPanel`) when `DISCORD_GUILD_ID` is provided.
     - All startup branches log errors/warnings via `pino` without crashing the client if a feature is misconfigured.

## Interaction System
- **Discovery (`src/interactions/commandRegistry.ts`)**
  - Resolves the commands root dynamically (`dist/src/...` in production, `src/...` during dev).
  - Recursively loads modules named `command.ts|js`, coercing to the compiled `.js` when present.
  - Exposes `discoverSlash()` (JSON bodies for REST registration) and `loadSlashMap()` (runtime `Map<string, SlashCommandModule>`).
- **Router (`src/interactions/interactionHandler.ts`)**
  - Lazily warms the slash map once per runtime and caches it in-memory.
  - Routes chat input commands, autocomplete, and button/component events.
  - Contains the central button switch for dashboard tabs, soft reserve admin actions, Tier3 approvals, FlaskGamba flow, roles panel refresh, and summon updates.
  - Provides `safeReply`, `safeUpdate`, and modal parsers to guard against Discord lifecycle errors.
- **Components V2**
  - `types/Componentsv2.ts` defines the raw payload shapes used across the project.
  - `src/utils/v2.ts` exposes builder helpers (`container`, `section`, `text`, `button`, `baseV2`) for LLM-friendly construction.
  - `makeDashboardPanel()` composes a canonical admin dashboard layout (category buttons, separators, tab renderers).

## Feature Packages (selected)
- **Tier3 (`src/features/tier3`)**: Sheet-driven request processing, message review controls, and button listeners. Requires Google service account envs.
- **Summon (`src/features/summon`)**: Panel rendering, cache management, and tests for both the service and panel builder. Integrates with admin buttons in the router and has a standalone refresh script.
- **FlaskGamba (`src/features/games/flaskgamba`)**: Full mini-game lifecycle with sheet logging, slash command, and Components V2 scoreboard.
- **SoftRes (`src/features/softres`)**: Panel publishing and command shortcuts backed by sheet lookups.
- **Roles (`src/features/roles`)**: Class role panel generation triggered from the dashboard button.
- Each feature sticks to internal helpers and avoids cross-importing other domains unless coordinated via the router.

## Scripts & Tooling
- `npm run dev` → `tsx watch src/app.ts` for hot reload during development.
- `npm run build` → strict TypeScript compilation to `dist`.
- `npm run start` → runs the compiled bot (`node dist/src/app.js`).
- Command lifecycle: `npm run commands:register`, `commands:clear`, `commands:list`.
- Operational helpers:
  - `tsx scripts/refresh-summon-panel.ts` refreshes the summon dashboard without restarting the bot.
  - `tsx scripts/softres-sheets-check.ts` dumps configured raid ranges for diagnostics.
  - `tsx scripts/test-sheets.ts` verifies Google Sheets connectivity.

## Configuration & Environment
- **Required**: `DISCORD_TOKEN`, `DISCORD_CLIENT_ID`.
- **Common optional**:
  - `DISCORD_GUILD_ID`, `DASHBOARD_CHANNEL_ID`.
  - Tier3: `TIER3_CHANNEL_ID`, `TIER3_MSG_CELL`, Google service account vars (`GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_PRIVATE_KEY`, `SHEET_CONFIG_ID`).
  - FlaskGamba: `FLASKGAMBA_CHANNEL_ID`, `FLASKGAMBA_TZ`, `FLASK_LOG_SHEET`, `FLASK_RULES_TEXT`.
  - Summon: `SUMMON_PANEL_CHANNEL_ID`, `SUMMON_PANEL_MSG_RANGE`, `SUMMON_ROLE_ID`, `SUMMON_PANEL_ADMIN_ROLE_ID`, `SUMMON_PANEL_CHANNEL_RANGE`.
  - SoftRes: `SHEET_IDDQD_ID`, `SR_PANEL_CHANNEL_ID`, `EMBED_SEPERATOR_TRANSPARENT`, raid message id envs from `src/config/sheets.ts`.
  - Roles: `ROLES_TARGET_CHANNEL_ID`, `ROLES_SOCIAL_ALERT_CHANNEL_ID`.
- All environment access flows through `validateEnv()` or feature-specific config modules; missing optional envs disable that feature but keep the bot online.

## Testing & Quality
- Unit tests with Vitest (`npm test`) live alongside features (e.g., `src/interactions/tests/parseRawModalData.spec.ts`, `src/features/summon/tests.panel.spec.ts`).
- ESLint flat config (`eslint.config.js`) enforces TypeScript-heavy rules like `consistent-type-definitions` (interface-only) and `_` prefix for unused vars.
- Logging uses `pino`; prefer `logger` over `console`.

## Folder Guide
```
src/
  app.ts
  config/
    env.ts
    sheets.ts
  core/
    client.ts
    index.ts
    logger.ts
  interactions/
    commandRegistry.ts
    interactionHandler.ts
    middleware.ts
    commands/<command>/command.ts
    components/{buttons,selects,modals}/
    dashboard/{registry.ts,view.ts,categories/*}
    tests/*.spec.ts
  features/
    auto-react/
    emotes/
    games/flaskgamba/
    logging/
    reports/
    roles/
    softres/
    summon/
    tier3/
    yappers/
  utils/
    v2.ts
    sheets.ts
    guards.ts
    time.ts
types/
  Command.ts
  Componentsv2.ts
scripts/
  register-commands.ts
  clear-commands.ts
  list-commands.ts
  refresh-summon-panel.ts
  softres-sheets-check.ts
  test-sheets.ts
docs/
  ARCHITECTURE.md
  v2components.md
```

_Last updated: 2025-10-21_
