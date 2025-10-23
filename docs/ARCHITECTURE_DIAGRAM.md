# System Architecture Diagram

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Discord API                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Discord.js Client                             │
│                  (src/core/client.ts)                            │
│  • Gateway Intents: Guilds, Messages, Members, MessageContent   │
│  • Partials: Message, Channel, User, GuildMember                │
└────────────┬────────────────────┬──────────────────────────────┘
             │                    │
             │ InteractionCreate  │ MessageCreate
             ▼                    ▼
┌────────────────────────┐  ┌──────────────────────────┐
│  Interaction Handler   │  │  Message Handler         │
│ (interactionHandler.ts)│  │  (!refresh-dashboard)    │
└────────┬───────────────┘  └──────────────────────────┘
         │
         ├─ Rate Limiter (checkRateLimit) ────────────────┐
         │                                                 │
         ▼                                                 ▼
┌────────────────────┐                          ┌──────────────────┐
│  Slash Commands    │                          │  Components      │
│  (Dynamic Load)    │                          │  (Buttons/Menus) │
└────────┬───────────┘                          └────────┬─────────┘
         │                                               │
         ▼                                               │
┌────────────────────────────────────────────────────────┘
│
├─ Role-Based Access Control (isAdmin, hasRole)
│
├─ Dashboard Categories (Main, Games, Sheets, Raiding, Panels)
│
├─ Feature Modules:
│  ├─ Tier3 (src/features/tier3)
│  ├─ Summon (src/features/summon)
│  ├─ SoftRes (src/features/softres)
│  ├─ FlaskGamba (src/features/games/flaskgamba)
│  ├─ Roles (src/features/roles)
│  └─ Logging (src/features/logging)
│
└─ Utilities:
   ├─ Cache (TTL-based in-memory cache)
   ├─ Rate Limiter (per-user request tracking)
   ├─ Components V2 Helpers (v2.ts)
   └─ Sheets Integration (Google Sheets API)
```

## Request Flow with Security Layers

```
User Action (Button/Command)
    │
    ▼
┌───────────────────────┐
│  Discord API          │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Rate Limiter         │ ◄── 5 req/10s default
│  • Check user ID      │
│  • Check action ID    │
└───────────┬───────────┘
            │
            ├─ Rate Limited? ──► Send error message
            │
            ▼ (Allowed)
┌───────────────────────┐
│  RBAC Middleware      │
│  • Check permissions  │
│  • Validate roles     │
└───────────┬───────────┘
            │
            ├─ No Permission? ──► Send error message
            │
            ▼ (Authorized)
┌───────────────────────┐
│  Action Handler       │
│  • Execute command    │
│  • Update dashboard   │
│  • Modify game state  │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Cache Check          │
│  • Hit? Return cached │
│  • Miss? Compute      │
└───────────┬───────────┘
            │
            ▼
┌───────────────────────┐
│  Response to User     │
└───────────────────────┘
```

## Dashboard Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Admin Dashboard                        │
│                  (Components V2 Embed)                    │
├──────────────────────────────────────────────────────────┤
│  [Refresh Button]                           Admin Only    │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │  Main   │  │  Games  │  │ Sheets  │  │ Raiding │    │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │
│  ┌─────────┐                                             │
│  │ Panels  │  ◄── Category Buttons                       │
│  └─────────┘                                             │
│                                                           │
├──────────────────────────────────────────────────────────┤
│                    Category Content                       │
│  • Main: Welcome & navigation                            │
│  • Games: FlaskGamba controls                            │
│  • Sheets: Export actions                                │
│  • Raiding: Signup management                            │
│  • Panels: Panel & raid message controls                 │
└──────────────────────────────────────────────────────────┘
```

## CI/CD Pipeline

```
┌──────────────┐
│  Git Push/PR │
└──────┬───────┘
       │
       ├─────────────────┬──────────────────┬─────────────┐
       ▼                 ▼                  ▼             ▼
┌─────────────┐  ┌──────────────┐  ┌─────────────┐  ┌──────────────┐
│    Lint     │  │    Build     │  │    Test     │  │  Type Check  │
│  (ESLint)   │  │ (TypeScript) │  │  (Vitest)   │  │  (tsc)       │
└─────┬───────┘  └──────┬───────┘  └─────┬───────┘  └──────┬───────┘
      │                 │                │                  │
      └─────────────────┴────────────────┴──────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  Quality Gate   │
                        │  All Pass? ✓    │
                        └────────┬────────┘
                                 │
                    ┌────────────┴──────────────┐
                    ▼                           ▼
            ┌──────────────┐          ┌─────────────────┐
            │   Deploy     │          │  CodeQL Scan    │
            │ (main only)  │          │  (Daily + PRs)  │
            └──────────────┘          └─────────────────┘
```

## Data Flow: Command Execution

```
1. User Input
   └─► /command or Button Click

2. Client Event
   └─► Events.InteractionCreate

3. Rate Limiter
   └─► Check user:action quota
       ├─► Limited? → Error Response
       └─► Allowed? → Continue

4. Command Registry
   └─► Lookup command handler
       ├─► Not found? → Error
       └─► Found? → Continue

5. Middleware
   └─► Check permissions (RBAC)
       ├─► No Permission? → Error
       └─► Authorized? → Continue

6. Command Handler
   └─► Execute business logic
       ├─► Check Cache
       │   ├─► Hit? → Use cached
       │   └─► Miss? → Compute & cache
       └─► Process request

7. Response
   └─► Send to Discord API
       ├─► safeSendV2() or
       └─► safeEditV2()
```

## Module Dependencies

```
┌─────────────────────────────────────────────────────┐
│                   Application Layer                  │
│  src/app.ts (Entry Point)                           │
└─────────────────┬───────────────────────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
┌─────────────────┐  ┌──────────────────┐
│  Core Layer     │  │  Config Layer    │
│  • client.ts    │  │  • env.ts        │
│  • logger.ts    │  │  • sheets.ts     │
│  • index.ts     │  │                  │
└────────┬────────┘  └──────────────────┘
         │
         ├─────────────────┬─────────────────┐
         ▼                 ▼                 ▼
┌─────────────────┐  ┌──────────────┐  ┌─────────────┐
│ Interactions    │  │  Features    │  │  Utils      │
│ • commands/     │  │  • tier3/    │  │  • cache    │
│ • dashboard/    │  │  • summon/   │  │  • rate-    │
│ • middleware    │  │  • softres/  │  │    limit    │
│ • handler       │  │  • games/    │  │  • v2       │
└─────────────────┘  └──────────────┘  └─────────────┘
```

## Legend

```
┌────────┐
│  Box   │  = Component/Module
└────────┘

─────────► = Data/Control Flow

◄────────  = Return/Response

┌────────┐
│  ✓✓✓   │  = Multiple instances/parallel processes
└────────┘

├── = Branch/Fork in flow
```

## Key Principles

1. **Separation of Concerns**: Each module has a single responsibility
2. **Dependency Injection**: Features don't directly depend on each other
3. **Event-Driven**: React to Discord events, don't poll
4. **Type Safety**: TypeScript strict mode, no `any` types
5. **Security First**: Rate limiting, RBAC, input validation
6. **Performance**: Caching, lazy loading, efficient data structures
7. **Testability**: Unit tests for all business logic
8. **Observability**: Structured logging with pino
