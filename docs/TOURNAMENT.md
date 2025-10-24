# Tournament Game Mode

The Tournament game mode is a competitive elimination game where players roll numbers across multiple rounds. Players compete to get the highest rolls, with bottom performers eliminated each round until a winner emerges.

## Features

- **🎲 Random Roll System**: Players roll numbers within a specified range (e.g., 1-100)
- **🔄 Limited Rolls**: Each player gets a limited number of rolls per round (keeps their best roll)
- **⏰ Time-Limited Rounds**: Rounds have deadlines that can be set by administrators
- **🏅 Elimination Rounds**: Bottom performers are eliminated after each round
- **📊 Real-time Leaderboard**: Live leaderboard showing top performers
- **📈 Statistics Tracking**: Comprehensive statistics including average rolls, highest rolls, and player counts
- **🏆 Winner Determination**: Tournament continues through elimination rounds until a winner is crowned

## Architecture

### Data Storage

The tournament system uses **Redis** for fast, in-memory data storage with the following structure:

```
tournament:{tournamentId}          - Tournament configuration
tournament:rolls:{tournamentId}    - User rolls (hash: userId -> roll data)
tournament:round:{tournamentId}:{roundNumber} - Round data and history
tournament:stats:{tournamentId}    - Tournament statistics
```

### Components

1. **Storage Layer** (`src/features/tournament/storage.ts`)
   - Redis client integration
   - CRUD operations for tournaments, rolls, rounds, and statistics
   - Key-based data organization

2. **Game Logic** (`src/features/tournament/game.ts`)
   - Tournament creation and management
   - Roll processing and validation
   - Round ending and elimination logic
   - Statistics calculation
   - Leaderboard generation

3. **UI Components** (`src/features/tournament/ui.ts`)
   - V2 Components for tournament display
   - Admin setup interfaces
   - Tournament list rendering
   - User statistics display

4. **Handlers** (`src/features/tournament/handlers.ts`)
   - Button interaction handling
   - Modal form processing
   - Admin commands
   - User actions (roll, view stats, refresh)

## Setup

### Prerequisites

1. **Redis Server**: Install and run Redis locally or use a hosted Redis service

```bash
# Install Redis (Ubuntu/Debian)
sudo apt-get install redis-server

# Start Redis
redis-server

# Or use Docker
docker run -d -p 6379:6379 redis:latest
```

2. **Environment Configuration**: Add Redis configuration to your `.env` file

```env
# Redis Configuration
REDIS_URL=redis://localhost:6379
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your_password_here  # Optional

# Tournament Configuration
TOURNAMENT_CHANNEL_ID=your_tournament_channel_id
```

### Installation

1. Install dependencies (already included in package.json):
```bash
npm install
```

2. Build the project:
```bash
npm run build
```

3. Start the bot:
```bash
npm start
```

## Usage

### For Administrators

#### Create a Tournament

1. Access the admin dashboard in your configured dashboard channel
2. Navigate to the **🎮 Games** category
3. Click **🏆 Tournament Setup**
4. Click **➕ Create Tournament**
5. Fill in the modal form:
   - **Tournament Name**: A descriptive name for your tournament
   - **Maximum Roll Number**: The upper limit for rolls (e.g., 100 for rolls 1-100)
   - **Roll Limit per Player**: How many times each player can roll (they keep their best roll)
   - **Deadline (hours)**: How long until the round ends

#### Manage Tournaments

- **View Active Tournaments**: Click **📋 Active Tournaments** to see all running tournaments
- **End a Round**: Click **End Round** on a tournament to eliminate bottom performers and start the next round
- **View Tournament**: Click **View** to see the current tournament state with leaderboard

### For Players

#### Participate in a Tournament

1. When a tournament message appears in a channel, you'll see:
   - Tournament information (name, roll range, deadline)
   - Current statistics (participants, average roll, etc.)
   - Top 10 leaderboard
   - Action buttons

2. **🎲 Roll**: Click to make a roll
   - You'll be notified of your roll result
   - Only your best roll counts
   - You can roll up to the roll limit

3. **📊 My Stats**: View your personal tournament statistics
   - Your best roll
   - Current rank
   - Rolls remaining
   - Last roll timestamp

4. **🔄 Refresh**: Update the tournament display with latest data

## Game Flow

### Round 1: Initial Rolling

1. Administrator creates a tournament
2. Players join by making their first roll
3. Each player can roll multiple times (up to roll limit)
4. Only the best roll is kept for each player
5. Leaderboard updates in real-time

### Round End: Elimination

1. Administrator clicks "End Round"
2. Bottom 50% of players are eliminated
3. Eliminated players are notified
4. Remaining players advance to next round
5. Roll counts reset for next round

### Subsequent Rounds

1. Surviving players can roll again
2. Process repeats until only one player remains
3. Winner is announced

### Tournament Complete

1. Final winner is displayed
2. Tournament status changes to COMPLETED
3. Historical data is preserved in Redis

## Data Models

### TournamentConfig
```typescript
{
  id: string;                    // Unique tournament ID
  name: string;                  // Tournament name
  maxRoll: number;               // Maximum roll value (e.g., 100)
  rollLimit: number;             // Rolls per player per round
  deadline: number;              // Unix timestamp
  currentRound: number;          // Current round number
  status: TournamentStatus;      // ACTIVE, COMPLETED, etc.
  channelId: string;             // Discord channel ID
  createdAt: number;             // Creation timestamp
  updatedAt: number;             // Last update timestamp
}
```

### UserRoll
```typescript
{
  userId: string;                // Discord user ID
  username: string;              // Display name
  roll: number;                  // Best roll value
  timestamp: number;             // Last roll timestamp
  rollsUsed: number;             // Total rolls made
}
```

### RoundData
```typescript
{
  roundNumber: number;           // Round identifier
  startTime: number;             // Round start timestamp
  endTime?: number;              // Round end timestamp
  participants: string[];        // User IDs in this round
  eliminated: string[];          // User IDs eliminated
  cutoffRoll?: number;           // Minimum roll to survive
}
```

## Configuration Options

### Tournament Parameters

- **Max Roll**: 10-10000 (recommended: 100 for standard play)
- **Roll Limit**: 1-10 rolls per player (recommended: 3)
- **Deadline**: 1-168 hours (recommended: 24 hours)
- **Elimination Rate**: 50% per round (hardcoded, can be customized in code)

### Redis Configuration

- **Connection Pooling**: Automatic reconnection with exponential backoff
- **Error Handling**: Graceful degradation if Redis is unavailable
- **Data Persistence**: Configure Redis persistence (RDB/AOF) for tournament data retention

## Troubleshooting

### Redis Connection Issues

If you see `Redis client error` in logs:

1. Verify Redis is running:
```bash
redis-cli ping
# Should return: PONG
```

2. Check Redis connection settings in `.env`
3. Ensure firewall allows Redis port (default: 6379)
4. Check Redis authentication if password is set

### Tournament Not Appearing

1. Verify `TOURNAMENT_CHANNEL_ID` is set correctly
2. Check bot has permissions to send messages in the channel
3. Ensure Redis is connected (check logs)
4. Try creating a tournament from the dashboard

### Rolls Not Saving

1. Check Redis logs for errors
2. Verify Redis has sufficient memory
3. Check for Redis key expiration policies
4. Review bot logs for storage errors

## Advanced Customization

### Changing Elimination Rate

Edit `src/features/tournament/game.ts`:

```typescript
// Default is 50% elimination
export async function endRound(
  tournamentId: string,
  eliminationPercentage: number = 50  // Change this value
): Promise<...>
```

### Custom Roll Algorithms

Modify the roll generation in `processUserRoll`:

```typescript
// Default: uniform random
const rollValue = Math.floor(Math.random() * config.maxRoll) + 1;

// Example: Weighted towards higher values
const rollValue = Math.floor(Math.pow(Math.random(), 0.5) * config.maxRoll) + 1;
```

### Adding Tournament Commands

Create a new slash command in `src/interactions/commands/tournament/command.ts`:

```typescript
import { SlashCommandBuilder } from 'discord.js';
import type { SlashCommandModule } from '../../../../types/Command.js';

const command: SlashCommandModule = {
  data: new SlashCommandBuilder()
    .setName('tournament')
    .setDescription('Tournament commands'),
  
  async execute(interaction) {
    // Your logic here
  },
};

export default command;
```

## Performance Considerations

### Redis Memory Usage

- Each tournament: ~1KB
- Each user roll: ~200 bytes
- Each round: ~500 bytes
- Example: 100-player tournament ≈ 21KB

### Scalability

- Redis can handle thousands of concurrent tournaments
- Consider Redis Cluster for multi-server deployments
- Use Redis TTL for automatic cleanup of completed tournaments

### Rate Limiting

- Default: 5 requests per 10 seconds per user
- Tournament rolls respect global rate limits
- Consider per-tournament rate limits for fairness

## API Reference

### Storage Functions

- `saveTournamentConfig(config)`: Save tournament configuration
- `getTournamentConfig(id)`: Retrieve tournament
- `saveUserRoll(tournamentId, userId, roll)`: Save user roll
- `getUserRoll(tournamentId, userId)`: Get user's roll
- `getAllUserRolls(tournamentId)`: Get all rolls
- `saveRoundData(tournamentId, roundNumber, round)`: Save round data
- `getRoundData(tournamentId, roundNumber)`: Get round data

### Game Functions

- `createTournament(...)`: Create new tournament
- `processUserRoll(...)`: Process a user's roll
- `endRound(tournamentId, eliminationRate)`: End round and eliminate players
- `calculateStats(tournamentId)`: Calculate tournament statistics
- `getLeaderboard(tournamentId, limit)`: Get top players
- `cancelTournament(tournamentId)`: Cancel tournament

## Testing

Run tournament tests:
```bash
npm test src/features/tournament/tournament.spec.ts
```

The test suite covers:
- Tournament configuration validation
- Roll generation and tracking
- Leaderboard sorting
- Elimination calculations
- Statistics computation

## Security Considerations

1. **Admin-Only Actions**: Tournament creation and round ending are admin-only
2. **Rate Limiting**: Prevents roll spam
3. **Input Validation**: All form inputs are validated
4. **Redis Security**: Use password authentication and firewall rules
5. **Data Isolation**: Tournament data is scoped by tournament ID

## Future Enhancements

Potential features to add:

1. **Scheduled Tournaments**: Automatic round endings based on deadlines
2. **Prize System**: Integration with economy/points system
3. **Tournament Templates**: Pre-configured tournament types
4. **Spectator Mode**: View-only access for non-participants
5. **Team Tournaments**: Multi-player team competitions
6. **Historical Statistics**: Long-term player performance tracking
7. **Custom Roll Distributions**: Different probability curves
8. **Tournament Brackets**: Single/double elimination formats
9. **Live Notifications**: DM players when rounds end
10. **Tournament Series**: Linked tournaments with overall rankings

## Support

For issues or questions:
- Check logs: `~/.iddqd/logs/` or console output
- Review Redis logs: `/var/log/redis/`
- GitHub Issues: [Create an issue](https://github.com/Rxriddqd/iddqd/issues)

## License

MIT License - Same as the main iddqd project
