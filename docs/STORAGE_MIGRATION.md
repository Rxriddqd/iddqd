# Storage Migration Guide

This document explains the storage architecture changes and how to migrate from Google Sheets to Redis + Persistent Disk.

## Overview

The bot has been updated to use a modern multi-tier storage approach:

### Previous Architecture
- **Google Sheets** - Primary data storage for everything

### New Architecture
1. **Redis** - Short-term, high-performance cache
   - Game state during active sessions
   - User session data  
   - Frequently accessed data
   - TTL-based expiration

2. **Persistent Disk** - Long-term, reliable storage
   - Event logs with daily rotation
   - Automated backups
   - Historical data
   - Fallback when Redis is unavailable

3. **Google Sheets** - Optional export only
   - Data export for reporting
   - Not required for primary storage
   - Can be completely disabled

## Benefits

### Performance
- **10-100x faster** - Redis in-memory operations vs. API calls
- **Lower latency** - No network roundtrips to Google
- **Better scalability** - Local caching reduces external dependencies

### Reliability
- **Offline capable** - Works without internet for Sheets
- **Automatic fallback** - Disk storage if Redis fails
- **No API limits** - No Google API quota issues
- **Faster recovery** - Local data for quick restarts

### Cost
- **Free Redis tier** - 25MB available on Render
- **Lower API usage** - Reduced Google API costs
- **Better resource usage** - Less CPU time on API calls

## Storage Service API

The new storage service provides a unified interface:

```typescript
// Import storage functions
import {
  storeData,
  retrieveData,
  storeJSON,
  retrieveJSON,
  storeGameState,
  retrieveGameState,
  logEvent,
  saveBackup,
} from './services/storage.js';

// Store simple data (uses Redis with TTL)
await storeData('user:123:status', 'active', { ttl: 3600 });

// Retrieve data (tries Redis first, falls back to disk)
const status = await retrieveData('user:123:status');

// Store JSON objects
await storeJSON('config', { theme: 'dark', lang: 'en' });

// Store game state (Redis with disk backup)
await storeGameState('game-123', {
  players: ['user1', 'user2'],
  status: 'active',
});

// Log events to persistent disk
await logEvent('game', {
  action: 'start',
  gameId: 'game-123',
  timestamp: Date.now(),
});

// Create backups
await saveBackup('daily', gameData);
```

## Migration Steps

### For Game Features

**Before (Google Sheets):**
```typescript
import { writeSheetRange, readSheetRange } from '../utils/sheets.js';

// Store game state
await writeSheetRange(
  env.SHEET_IDDQD_ID,
  'Games!A2:D2',
  [[gameId, player1, player2, 'active']]
);

// Read game state
const rows = await readSheetRange(
  env.SHEET_IDDQD_ID,
  'Games!A2:D100'
);
```

**After (Storage Service):**
```typescript
import { storeGameState, retrieveGameState } from '../services/storage.js';

// Store game state
await storeGameState(gameId, {
  player1,
  player2,
  status: 'active',
});

// Read game state
const state = await retrieveGameState(gameId);
```

### For Logging

**Before:**
```typescript
// Append to sheet
await appendSheetRange(
  env.SHEET_IDDQD_ID,
  'Logs!A:D',
  [[timestamp, action, user, details]]
);
```

**After:**
```typescript
// Append to daily log file
await logEvent('game', {
  timestamp,
  action,
  user,
  details,
});
```

### For Caching

**Before:**
```typescript
// Re-fetch from Sheets every time
const data = await readSheetRange(spreadsheetId, range);
```

**After:**
```typescript
// Cache in Redis with TTL
await storeData('cache:config', JSON.stringify(config), { 
  ttl: 3600, // 1 hour
  persistToDisk: true // Also save to disk
});

// Fast retrieval
const cached = await retrieveData('cache:config');
```

## Example: Migrating FlaskGamba

### Original Implementation (Sheets)
```typescript
async function createFlaskGame(question: string) {
  const gameId = generateId();
  
  // Write to sheet
  await appendSheetRange(
    env.SHEET_IDDQD_ID,
    'FlaskGamba!A:E',
    [[gameId, question, 'active', '', '']]
  );
  
  return gameId;
}

async function placeBet(gameId: string, userId: string, choice: string) {
  // Read all rows to find game
  const rows = await readSheetRange(
    env.SHEET_IDDQD_ID,
    'FlaskGamba!A:E'
  );
  
  const rowIndex = rows.findIndex(row => row[0] === gameId);
  
  // Update row
  await writeSheetRange(
    env.SHEET_IDDQD_ID,
    `FlaskGamba!D${rowIndex + 1}:E${rowIndex + 1}`,
    [[userId, choice]]
  );
}
```

### New Implementation (Storage Service)
```typescript
import { 
  createFlaskGambaRound, 
  placeBet 
} from '../services/gameStateManager.js';

async function createFlaskGame(question: string) {
  const gameId = await createFlaskGambaRound(
    channelId,
    question,
    ['Yes', 'No']
  );
  
  return gameId;
}

// Bets are automatically handled by game state manager
// Uses Redis for active game, automatically backs up to disk
```

## Data Location

### Development
```
./data/
├── cache/              # Cached data from Redis
├── logs/               # Event logs
│   ├── game/          # Game logs
│   ├── flaskgamba/    # FlaskGamba logs
│   └── system/        # System logs
└── backups/           # Automated backups
    ├── game-flaskgamba/
    └── game-test/
```

### Production (Render)
```
/data/                 # Mounted persistent disk
├── cache/
├── logs/
└── backups/
```

## Optional: Keep Sheets for Export

You can keep Google Sheets integration for data export:

```typescript
import { getSheets, writeSheetRange } from '../utils/sheets.js';
import { retrieveGameState } from '../services/storage.js';

async function exportGameToSheets(gameId: string) {
  // Get from Redis/disk
  const game = await retrieveGameState(gameId);
  
  if (game && env.GOOGLE_SERVICE_ACCOUNT_EMAIL) {
    // Export to Sheets for reporting
    await writeSheetRange(
      env.SHEET_IDDQD_ID,
      'Export!A2:D2',
      [[game.gameId, game.type, game.status, game.endedAt]]
    );
  }
}
```

## Performance Comparison

### Google Sheets
- Read: 200-1000ms per API call
- Write: 300-1500ms per API call
- Rate limited: ~100 requests/100 seconds
- Requires internet connection

### Redis + Disk
- Redis read: <1ms
- Redis write: <1ms
- Disk read: 5-20ms
- Disk write: 10-50ms
- No rate limits
- Works offline

## Rollback Plan

If you need to rollback to Google Sheets:

1. Keep the Sheets integration code (it's still present)
2. Set `REDIS_ENABLED=false` in environment
3. Update code to use Sheets functions directly
4. The storage service will automatically fall back to disk

## Testing

All storage operations have comprehensive tests:

```bash
# Run all tests
npm test

# Test Redis integration
npm test src/core/tests/redis.spec.ts

# Test disk operations
npm test src/core/tests/disk.spec.ts

# Test storage service
npm test src/services/tests/storage.spec.ts

# Test game state manager
npm test src/services/tests/gameStateManager.spec.ts
```

## Monitoring

Monitor storage health in logs:

```
# Redis connected successfully
✅ Redis connected and ready

# Redis unavailable (falling back to disk)
⚠️ Redis is enabled but failed to initialize

# Storage operation logs
DEBUG: Data written to disk path=/data/cache/game:123:state.txt
INFO: Score recorded gameId=game-123 userId=user1 score=100
```

## Troubleshooting

### Redis Connection Issues
**Symptom**: `⚠️ Redis is enabled but failed to initialize`

**Solution**: 
1. Verify Redis is running: Check Render dashboard
2. Check credentials: Ensure REDIS_HOST, REDIS_PORT, REDIS_PASSWORD are correct
3. Check TLS: Try setting REDIS_TLS=true if using external connection
4. Fallback works: Bot continues using disk storage

### Disk Write Issues
**Symptom**: `Failed to write to disk`

**Solution**:
1. Check disk space: `df -h /data`
2. Check permissions: Ensure write access to /data
3. Check path: Verify PERSISTENT_DISK_PATH is correct

### Data Not Persisting
**Symptom**: Data lost after restart

**Solution**:
1. Use `persistToDisk: true` option for important data
2. Verify persistent disk is mounted at /data
3. Check that Redis TTL is appropriate for data type
4. Use `saveBackup()` for critical data

## Best Practices

1. **Use appropriate storage**:
   - Redis: Session data, active game state (TTL < 24h)
   - Disk: Logs, backups, historical data (permanent)
   - Sheets: Optional export for reporting

2. **Set appropriate TTLs**:
   - User sessions: 1 hour
   - Game state: 24 hours
   - Cache: 5-60 minutes

3. **Enable disk backup**:
   ```typescript
   await storeData(key, value, { 
     ttl: 3600,
     persistToDisk: true // Backup to disk
   });
   ```

4. **Log important events**:
   ```typescript
   await logEvent('game', {
     action: 'complete',
     gameId,
     winner,
   });
   ```

5. **Create backups**:
   ```typescript
   await saveBackup('game-completed', gameState);
   ```

## Resources

- [Storage Service Source](../src/services/storage.ts)
- [Game State Manager Source](../src/services/gameStateManager.ts)
- [Redis Documentation](https://redis.io/docs/)
- [Render Deployment Guide](./RENDER_DEPLOYMENT.md)

---

**Last Updated**: 2025-10-24
