import 'dotenv/config';
import { buildClient } from './core/client.js';
import { logger } from './core/logger.js';
import { env } from './config/env.js';
import { getRedisClient, isRedisAvailable } from './core/redis.js';

/**
 * Main application entry point
 */
async function main() {
  logger.info('🤖 Starting Discord bot...');
  
  // Initialize Redis connection if enabled
  if (env.REDIS_ENABLED) {
    const redisClient = getRedisClient();
    if (redisClient) {
      const available = await isRedisAvailable();
      if (available) {
        logger.info('✅ Redis connected and ready');
      } else {
        logger.warn('⚠️ Redis client created but not responding to ping');
      }
    } else {
      logger.warn('⚠️ Redis is enabled but failed to initialize');
    }
  } else {
    logger.info('ℹ️ Redis is disabled');
  }
  
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

/**
 * Cleanup function for graceful shutdown
 */
async function cleanup() {
  logger.info('🛑 Shutting down...');
  const { disconnectRedis } = await import('./core/redis.js');
  await disconnectRedis();
  process.exit(0);
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

// Handle graceful shutdown
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

// Start the bot
main().catch((error) => {
  logger.error({ error }, 'Fatal error during startup');
  process.exit(1);
});
