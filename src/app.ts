import 'dotenv/config';
import { buildClient } from './core/client.js';
import { logger } from './core/logger.js';
import { env } from './config/env.js';

/**
 * Main application entry point
 */
async function main() {
  logger.info('🤖 Starting Discord bot...');
  
  // Build and configure client
  const client = buildClient();
  
  try {
    // Login to Discord
    await client.login(env.DISCORD_TOKEN);
  } catch (error) {
    logger.error({ error }, 'Failed to login to Discord');
    process.exit(1);
  }
}

// Handle unhandled rejections
process.on('unhandledRejection', (error) => {
  logger.error({ error }, 'Unhandled promise rejection');
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error({ error }, 'Uncaught exception');
  process.exit(1);
});

// Start the bot
main().catch((error) => {
  logger.error({ error }, 'Fatal error during startup');
  process.exit(1);
});
