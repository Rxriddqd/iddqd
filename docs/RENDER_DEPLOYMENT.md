# Render Deployment Guide

This guide explains how to deploy the IDDQD Discord bot on Render with Redis and Persistent Disk support.

## Prerequisites

1. A [Render](https://render.com) account
2. Discord Bot Token and Client ID
3. GitHub repository connected to Render

## Services Required

### 1. Redis Instance

The bot uses Redis for short-term data storage (game state, sessions, cache).

**Setup Steps:**
1. In Render Dashboard, click "New +" → "Redis"
2. Choose a name (e.g., `iddqd-redis`)
3. Select a region (same as your web service for lower latency)
4. Choose a plan:
   - **Free tier**: 25MB storage, suitable for testing
   - **Starter**: 256MB storage, recommended for production
5. Click "Create Redis"
6. After creation, note the **Internal Redis URL** (starts with `redis://`)

### 2. Web Service with Persistent Disk

The bot needs a web service (running as a background worker) with persistent disk for long-term storage.

**Setup Steps:**
1. In Render Dashboard, click "New +" → "Web Service"
2. Connect your GitHub repository
3. Configure the service:
   - **Name**: `iddqd-bot`
   - **Region**: Same as Redis
   - **Branch**: `main` (or your preferred branch)
   - **Runtime**: `Node`
   - **Build Command**: `npm install && npm run build`
   - **Start Command**: `npm start`
   - **Plan**: Choose based on your needs (Starter or higher)

4. **Add Persistent Disk:**
   - In the service settings, scroll to "Disks"
   - Click "Add Disk"
   - **Name**: `iddqd-data`
   - **Mount Path**: `/data`
   - **Size**: 1GB minimum (adjust based on your needs)
   - Click "Save"

## Environment Variables Configuration

In your Render Web Service settings, add the following environment variables:

### Required Discord Configuration
```env
DISCORD_TOKEN=your_bot_token_here
DISCORD_CLIENT_ID=your_client_id_here
```

### Redis Configuration
```env
# Use the Internal Redis URL from your Render Redis instance
REDIS_HOST=your-redis-internal-hostname
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password
REDIS_TLS=false
REDIS_ENABLED=true
```

**Note**: You can get these values from your Redis instance's "Info" tab:
- The Internal Redis URL format is: `redis://red-xxx:password@hostname:6379`
- Extract the hostname, port, and password from this URL

### Persistent Disk Configuration
```env
PERSISTENT_DISK_PATH=/data
```

### Optional Discord Configuration
```env
DISCORD_GUILD_ID=your_guild_id_here
DASHBOARD_CHANNEL_ID=channel_id_for_admin_dashboard
```

### Optional Feature Configuration
Add any optional feature configurations you need:
```env
# FlaskGamba
FLASKGAMBA_CHANNEL_ID=channel_id_here
FLASKGAMBA_TZ=America/New_York

# Summon Panel
SUMMON_PANEL_CHANNEL_ID=channel_id_here
SUMMON_ROLE_ID=role_id_here

# Google Sheets (Optional - for export only)
GOOGLE_SERVICE_ACCOUNT_EMAIL=your_service_account_email
GOOGLE_PRIVATE_KEY=your_private_key
SHEET_CONFIG_ID=your_sheet_id
SHEET_IDDQD_ID=your_sheet_id
```

## Deployment Process

1. **Deploy the Service:**
   - After configuring environment variables, Render will automatically build and deploy
   - Monitor the deployment logs for any errors
   - Look for the message: `✅ Redis connected and ready`

2. **Verify Redis Connection:**
   - Check the logs for successful Redis connection
   - If Redis fails, verify the connection details and TLS settings

3. **Verify Persistent Disk:**
   - The disk will be automatically mounted at `/data`
   - The bot will create subdirectories as needed:
     - `/data/cache/` - Cache data with disk persistence
     - `/data/logs/` - Event logs
     - `/data/backups/` - Data backups

4. **Register Discord Commands:**
   - SSH into your Render service or use the Shell tab
   - Run: `npm run commands:register`
   - This will register slash commands with Discord

## Data Storage Architecture

### Redis (Short-term)
- **Purpose**: Fast access for frequently used data
- **TTL**: Configurable per data type (e.g., 1 hour for sessions, 24 hours for game state)
- **Use Cases**:
  - Game state during active gameplay
  - User session data
  - Cache for frequently accessed data

### Persistent Disk (Long-term)
- **Purpose**: Permanent storage that survives service restarts
- **Use Cases**:
  - Event logs
  - Data backups
  - Historical data
  - Fallback when Redis is unavailable

### Fallback Strategy
The bot automatically falls back to disk storage if Redis is unavailable, ensuring reliability.

## Monitoring and Logs

### View Logs
- Go to your Web Service in Render
- Click "Logs" tab
- Look for:
  - `✅ Redis connected and ready` - Redis is working
  - `⚠️ Redis is disabled` - Redis is disabled or failed to connect
  - Log entries for data operations

### Health Checks
The bot logs:
- Redis connection status on startup
- Failed Redis operations (with automatic disk fallback)
- Disk I/O operations at debug level

## Troubleshooting

### Redis Connection Issues

**Problem**: Bot can't connect to Redis
```
⚠️ Redis is enabled but failed to initialize
```

**Solutions:**
1. Verify Redis is running in Render dashboard
2. Check `REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD` are correct
3. Ensure Web Service and Redis are in the same region
4. Try setting `REDIS_TLS=true` if using external connection

### Persistent Disk Issues

**Problem**: Can't write to disk
```
Failed to write to disk
```

**Solutions:**
1. Verify disk is mounted at `/data`
2. Check disk is not full (upgrade size if needed)
3. Ensure service has write permissions

### Memory Issues

**Problem**: Service runs out of memory

**Solutions:**
1. Upgrade to a larger Render plan
2. Reduce Redis TTL to expire data faster
3. Monitor cache size in logs

## Scaling Considerations

### Horizontal Scaling
- The bot is designed to run as a single instance
- Redis provides shared state if you need multiple processes
- Persistent disk is mounted per instance

### Vertical Scaling
- Increase service memory/CPU in Render plan
- Upgrade Redis instance for more storage
- Increase persistent disk size as needed

## Security Best Practices

1. **Secrets Management:**
   - Never commit `.env` files to git
   - Use Render's environment variables
   - Rotate credentials regularly

2. **Redis Security:**
   - Always use password authentication
   - Use TLS for production
   - Use internal URLs when possible

3. **Disk Security:**
   - Sensitive data is stored on encrypted disks
   - Regular backups are recommended
   - Monitor disk usage

## Backup and Recovery

### Automatic Backups
The bot automatically:
- Backs up game state to disk every 24 hours
- Logs events to dated log files
- Persists important data to disk

### Manual Backups
You can create manual backups using the storage service:
```typescript
import { saveBackup } from './services/storage.js';
await saveBackup('manual', yourData);
```

### Recovery
Data can be recovered from:
1. Redis (if within TTL)
2. Persistent disk cache
3. Backup files in `/data/backups/`

## Cost Optimization

### Free Tier Setup
- **Redis**: Free tier (25MB)
- **Web Service**: Starter ($7/month)
- **Persistent Disk**: 1GB included
- **Total**: ~$7/month for small bot

### Production Setup
- **Redis**: Starter (256MB) - $10/month
- **Web Service**: Standard ($25/month)
- **Persistent Disk**: 5GB - Included
- **Total**: ~$35/month for production bot

## Migration from Google Sheets

If you're migrating from Google Sheets-based storage:

1. **Data Export:**
   - Use the existing Sheets integration to export current data
   - Save exported data using the storage service
   - Verify data integrity

2. **Update Code:**
   - Replace Sheets API calls with storage service calls
   - Update game logic to use Redis/disk storage
   - Keep Sheets integration for optional export

3. **Testing:**
   - Test all game functionality with new storage
   - Verify data persistence across restarts
   - Monitor for issues in production

## Support

For issues specific to:
- **Render Platform**: [Render Support](https://render.com/support)
- **IDDQD Bot**: [GitHub Issues](https://github.com/Rxriddqd/iddqd/issues)
- **Discord.js**: [Discord.js Guide](https://discordjs.guide/)

## Additional Resources

- [Render Documentation](https://render.com/docs)
- [Redis Documentation](https://redis.io/docs/)
- [Discord.js Documentation](https://discord.js.org/)
- [IDDQD Architecture](./ARCHITECTURE.md)

---

**Last Updated**: 2025-10-24
