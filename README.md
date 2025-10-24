# IDDQD Discord Bot

A production-ready Discord bot built with **Discord.js v14**, **TypeScript strict mode**, and **Components V2** support.

## 🌟 Features

- **🎨 Components V2** - Modern Discord UI with the latest message components
- **⚡ TypeScript** - Strict mode for maximum type safety
- **🔐 Security** - Rate limiting, RBAC, and environment validation
- **📊 Admin Dashboard** - Interactive dashboard with category navigation
- **🎮 Mini-Games** - FlaskGamba and other interactive games
- **📋 Role & Summon Panels** - Dynamic role assignment and notifications
- **💾 Redis Integration** - Fast short-term data storage with automatic fallback
- **📁 Persistent Disk** - Long-term storage for logs, backups, and historical data
- **📊 Google Sheets Integration** - Optional data export to Google Sheets
- **🧪 Testing** - Vitest for unit and integration tests
- **🔄 CI/CD** - Automated testing, linting, and deployment
- **📝 Comprehensive Logging** - Structured logging with Pino
- **☁️ Render Ready** - Optimized for deployment on Render with Redis and disk support

## 📋 Prerequisites

- **Node.js** 22.x or higher
- **npm** or **yarn**
- **Discord Bot Token** (from [Discord Developer Portal](https://discord.com/developers/applications))
- **Discord Client ID**
- **Redis** (optional but recommended, for short-term data storage)
- **Google Service Account** (optional, for Sheets data export)

## 🚀 Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/Rxriddqd/iddqd.git
cd iddqd
```

### 2. Install dependencies

```bash
npm install
```

### 3. Configure environment variables

Copy `.env.example` to `.env` and fill in your configuration:

```bash
cp .env.example .env
```

**Required variables:**
```env
DISCORD_TOKEN=your_bot_token_here
DISCORD_CLIENT_ID=your_client_id_here
```

**Optional variables:**
```env
DISCORD_GUILD_ID=your_guild_id_here
DASHBOARD_CHANNEL_ID=channel_id_for_admin_dashboard

# Redis configuration (recommended for production)
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password
REDIS_ENABLED=true

# Persistent disk path (for long-term storage)
PERSISTENT_DISK_PATH=/data

# ... see .env.example for all options
```

### 4. Register slash commands

```bash
npm run commands:register
```

### 5. Start the bot

**Development mode** (with hot reload):
```bash
npm run dev
```

**Production mode:**
```bash
npm run build
npm start
```

## 📖 Project Structure

```
iddqd/
├── .github/
│   └── workflows/          # CI/CD workflows
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md
│   ├── v2components.md
│   ├── IMPLEMENTATION_SUMMARY.md
│   └── ARCHITECTURE_DIAGRAM.md
├── scripts/                # Operational scripts
│   ├── register-commands.ts
│   ├── clear-commands.ts
│   ├── list-commands.ts
│   ├── refresh-summon-panel.ts
│   ├── softres-sheets-check.ts
│   └── test-sheets.ts
├── src/
│   ├── app.ts             # Entry point
│   ├── config/            # Configuration
│   │   ├── env.ts         # Environment validation
│   │   └── sheets.ts      # Sheets configuration
│   ├── core/              # Core infrastructure
│   │   ├── client.ts      # Discord client setup
│   │   ├── logger.ts      # Logging configuration
│   │   └── index.ts       # Core exports
│   ├── interactions/      # Interaction handling
│   │   ├── commandRegistry.ts
│   │   ├── interactionHandler.ts
│   │   ├── middleware.ts
│   │   ├── commands/      # Slash commands
│   │   │   ├── ping/
│   │   │   └── help/
│   │   └── dashboard/     # Admin dashboard
│   │       ├── registry.ts
│   │       ├── view.ts
│   │       └── categories/
│   │           ├── main.ts
│   │           ├── games.ts
│   │           ├── sheets.ts
│   │           ├── raiding.ts
│   │           └── panels.ts
│   ├── features/          # Feature modules
│   │   └── logging/       # Example feature
│   └── utils/             # Utility functions
│       ├── v2.ts          # Components V2 helpers
│       ├── cache.ts       # Caching
│       ├── rate-limit.ts  # Rate limiting
│       ├── guards.ts      # Type guards
│       ├── time.ts        # Time utilities
│       └── sheets.ts      # Google Sheets helpers
├── types/                 # TypeScript types
│   ├── Command.ts
│   └── Componentsv2.ts
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── eslint.config.js
└── .env.example
```

## 🎮 Commands

### Slash Commands

- `/ping` - Check bot latency and responsiveness
- `/help` - Show available commands and bot information

### Text Commands (Admin Only)

- `!refresh-dashboard` - Refresh the admin dashboard

## 🎨 Admin Dashboard

The bot features an interactive admin dashboard with Components V2:

### Categories

- **🏠 Main** - Dashboard overview and navigation
- **🎮 Games** - Manage mini-games and leaderboards
- **📊 Sheets** - Export and sync Google Sheets data
- **⚔️ Raiding** - Manage raid signups and rosters
- **📋 Panels** - Control role and summon panels

### Features

- Category navigation with interactive buttons
- Administrator-only access with RBAC
- Real-time updates with refresh button
- Components V2 for modern UI

## 🧪 Testing

Run tests:
```bash
npm test
```

Run tests in watch mode:
```bash
npm run test:watch
```

## 🔍 Linting

Run ESLint:
```bash
npm run lint
```

Fix linting issues automatically:
```bash
npm run lint:fix
```

## 🏗️ Building

Build for production:
```bash
npm run build
```

The compiled JavaScript will be in the `dist/` directory.

## 📜 Available Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start bot in development mode with hot reload |
| `npm run build` | Build for production |
| `npm start` | Start bot in production mode |
| `npm test` | Run tests |
| `npm run test:watch` | Run tests in watch mode |
| `npm run lint` | Run ESLint |
| `npm run lint:fix` | Fix linting issues |
| `npm run commands:register` | Register slash commands |
| `npm run commands:clear` | Clear all slash commands |
| `npm run commands:list` | List registered commands |
| `npm run refresh-summon` | Refresh summon panel |
| `npm run check-sheets` | Check sheets configuration |
| `npm run test-sheets` | Test Google Sheets connectivity |

## 🔐 Security Features

### Rate Limiting

- Default: 5 requests per 10 seconds per user
- Configurable per action
- Automatic cleanup of expired entries
- User-friendly error messages

### Role-Based Access Control (RBAC)

- Administrator-only dashboard access
- Middleware functions: `isAdmin()`, `hasRole()`, `requireAdmin()`
- Support for both GuildMember and APIInteractionGuildMember

### Environment Validation

- Zod schema validation for all environment variables
- Clear error messages for missing required variables
- Type-safe environment access

## ⚡ Performance Features

### Caching

- In-memory cache with TTL support
- Default TTL: 5 minutes
- Automatic cleanup of expired entries
- `getOrCompute()` helper for lazy loading

### Lazy Loading

- Commands loaded on-demand
- Feature modules initialized only when needed
- Efficient memory usage

## 📚 Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Project architecture and design decisions
- **[v2components.md](docs/v2components.md)** - Components V2 reference guide
- **[IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)** - Implementation details and changes
- **[ARCHITECTURE_DIAGRAM.md](docs/ARCHITECTURE_DIAGRAM.md)** - System architecture diagrams
- **[RENDER_DEPLOYMENT.md](docs/RENDER_DEPLOYMENT.md)** - Complete guide for deploying to Render with Redis and Persistent Disk
- **[STORAGE_MIGRATION.md](docs/STORAGE_MIGRATION.md)** - Guide for migrating from Google Sheets to Redis/Disk storage

## 🔄 CI/CD

The project includes three GitHub Actions workflows:

1. **CI** (`ci.yml`) - Automated testing, linting, type checking, and building
2. **Deploy** (`deploy.yml`) - Production deployment template
3. **CodeQL** (`codeql.yml`) - Security scanning (daily + on PRs)

## 🎯 Feature Configuration

### Dashboard

```env
DASHBOARD_CHANNEL_ID=channel_id_here
```

### FlaskGamba

```env
FLASKGAMBA_CHANNEL_ID=channel_id_here
FLASKGAMBA_TZ=America/New_York
FLASK_LOG_SHEET=Sheet1
FLASK_RULES_TEXT=Game rules here
```

### Summon Panel

```env
SUMMON_PANEL_CHANNEL_ID=channel_id_here
SUMMON_PANEL_MSG_RANGE=Sheet1!A1:B10
SUMMON_ROLE_ID=role_id_here
SUMMON_PANEL_ADMIN_ROLE_ID=admin_role_id_here
SUMMON_PANEL_CHANNEL_RANGE=Sheet1!C1:D10
```

### Google Sheets

```env
GOOGLE_SERVICE_ACCOUNT_EMAIL=your_service_account_email
GOOGLE_PRIVATE_KEY=your_private_key
SHEET_CONFIG_ID=your_config_sheet_id
SHEET_IDDQD_ID=your_main_sheet_id
```

## 🛠️ Development Guidelines

### Adding a New Command

1. Create a new directory: `src/interactions/commands/your-command/`
2. Create `command.ts` with the SlashCommandModule structure:

```typescript
import { SlashCommandBuilder } from 'discord.js';
import type { SlashCommandModule } from '../../../../types/Command.js';

const command: SlashCommandModule = {
  data: new SlashCommandBuilder()
    .setName('your-command')
    .setDescription('Your command description'),

  async execute(interaction) {
    await interaction.reply('Your response');
  },
};

export default command;
```

3. Re-register commands: `npm run commands:register`

### Adding a New Feature

1. Create a directory: `src/features/your-feature/`
2. Add your feature logic with proper exports
3. Import and integrate in `src/core/client.ts` or interaction handlers
4. Add configuration in `src/config/env.ts` if needed
5. Update documentation

### Adding a Dashboard Category

1. Create a new category file: `src/interactions/dashboard/categories/your-category.ts`
2. Export a `render` function that returns `V2TopLevel[]`
3. Add the category to `DASHBOARD_CATEGORIES` in `registry.ts`
4. Add the category case in `view.ts`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'Add your feature'`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

- Built with [Discord.js](https://discord.js.org/)
- Components V2 documentation from Discord
- Inspired by best practices from the Discord.js community

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/Rxriddqd/iddqd/issues)
- **Discord**: Join our server for support and updates

## 🎉 Additional Suggestions

Here are some additional features and improvements you might want to consider:

### Data Storage

The bot now uses a multi-tier storage approach:

1. **Redis** (Short-term storage)
   - Game state during active sessions
   - User session data
   - Frequently accessed cache data
   - Automatic TTL and expiration

2. **Persistent Disk** (Long-term storage)
   - Event logs with daily rotation
   - Automated backups
   - Historical data
   - Fallback when Redis is unavailable

3. **Google Sheets** (Optional export only)
   - Data export and reporting
   - No longer required for primary storage
   - Configure only if you need sheet integration

See [RENDER_DEPLOYMENT.md](docs/RENDER_DEPLOYMENT.md) for deployment instructions.

### Suggested Features

1. **Enhanced Database Integration**
   - Add PostgreSQL for relational data
   - Integrate with existing Redis/disk storage
   - Example: Prisma ORM integration

2. **Advanced Commands**
   - `/stats` - Show server statistics
   - `/leaderboard` - Display game leaderboards
   - `/profile` - User profile management
   - `/settings` - Bot settings configuration

3. **Event Listeners**
   - Welcome messages for new members
   - Moderation logs (kicks, bans, timeouts)
   - Auto-role assignment
   - Anti-spam protection

4. **Webhooks**
   - Integrate with external services (GitHub, Twitch, YouTube)
   - Post updates to Discord channels
   - Custom notification systems

5. **Scheduled Tasks**
   - Daily reminders
   - Weekly raid resets
   - Automatic data cleanup
   - Backup schedules

6. **Voice Features**
   - Music playback
   - Voice state tracking
   - Temporary voice channels

7. **Moderation Tools**
   - `/warn`, `/kick`, `/ban`, `/timeout`
   - Case management system
   - Appeal system

8. **Economy System**
   - Virtual currency
   - Shop system
   - Daily rewards
   - Gambling games

9. **Level System**
   - XP and levels for activity
   - Role rewards for levels
   - Leaderboards

10. **Custom Embeds**
    - Embed builder command
    - Announcement templates
    - Rich message formatting

### Infrastructure Improvements

1. **Docker Support**
   - Add `Dockerfile` and `docker-compose.yml`
   - Containerize the bot for easy deployment

2. **Database Migrations**
   - Schema versioning
   - Migration scripts

3. **Monitoring**
   - Prometheus metrics
   - Health check endpoints
   - Uptime monitoring

4. **Error Tracking**
   - Sentry integration
   - Error reporting dashboard

5. **Analytics**
   - Command usage statistics
   - User engagement metrics
   - Performance monitoring

### Documentation Improvements

1. **API Documentation**
   - Generate API docs with TypeDoc
   - Interactive examples

2. **User Guide**
   - Command usage examples
   - Feature walkthroughs
   - Troubleshooting guide

3. **Developer Guide**
   - Architecture deep dive
   - Plugin system documentation
   - Best practices

Let me know if you'd like me to implement any of these suggestions!

---

**Made with ❤️ by the IDDQD team**
