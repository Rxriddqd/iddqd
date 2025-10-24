/**
 * Redis client configuration and connection pooling
 * 
 * Provides a singleton Redis client with connection pooling,
 * error handling, and reconnection logic for production use.
 */

import Redis from 'ioredis';
import { logger } from './logger.js';

let redisClient: Redis | null = null;

/**
 * Get or create Redis client instance
 */
export function getRedisClient(): Redis | null {
  // Get env variables at runtime, not at import time
  const redisEnabled = process.env.REDIS_ENABLED !== 'false';
  
  // Return null if Redis is disabled
  if (!redisEnabled) {
    logger.info('Redis is disabled via REDIS_ENABLED environment variable');
    return null;
  }

  // Return existing client if already initialized
  if (redisClient) {
    return redisClient;
  }

  try {
    const host = process.env.REDIS_HOST || 'localhost';
    const port = parseInt(process.env.REDIS_PORT || '6379', 10);
    const password = process.env.REDIS_PASSWORD;
    const tls = process.env.REDIS_TLS === 'true';
    
    // Configure Redis client with connection pooling
    redisClient = new Redis({
      host,
      port,
      password,
      retryStrategy: (times) => {
        // Exponential backoff: 50ms, 100ms, 200ms, up to 3 seconds
        const delay = Math.min(times * 50, 3000);
        logger.warn({ times, delay }, 'Redis connection retry');
        return delay;
      },
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      // Enable TLS if configured (required for some Render Redis instances)
      ...(tls && {
        tls: {
          rejectUnauthorized: false, // Some Render instances use self-signed certs
        },
      }),
    });

    // Connection event handlers
    redisClient.on('connect', () => {
      logger.info('Redis client connected');
    });

    redisClient.on('ready', () => {
      logger.info('Redis client ready');
    });

    redisClient.on('error', (error) => {
      logger.error({ error }, 'Redis client error');
    });

    redisClient.on('close', () => {
      logger.warn('Redis connection closed');
    });

    redisClient.on('reconnecting', () => {
      logger.info('Redis client reconnecting');
    });

    return redisClient;
  } catch (error) {
    logger.error({ error }, 'Failed to initialize Redis client');
    return null;
  }
}

/**
 * Disconnect Redis client gracefully
 */
export async function disconnectRedis(): Promise<void> {
  if (redisClient) {
    try {
      await redisClient.quit();
      redisClient = null;
      logger.info('Redis client disconnected');
    } catch (error) {
      logger.error({ error }, 'Error disconnecting Redis client');
    }
  }
}

/**
 * Check if Redis is available and connected
 */
export async function isRedisAvailable(): Promise<boolean> {
  const client = getRedisClient();
  if (!client) {
    return false;
  }

  try {
    await client.ping();
    return true;
  } catch (error) {
    logger.error({ error }, 'Redis ping failed');
    return false;
  }
}

/**
 * Redis helper: Set value with optional TTL
 */
export async function setRedis(
  key: string,
  value: string,
  ttlSeconds?: number
): Promise<boolean> {
  const client = getRedisClient();
  if (!client) {
    return false;
  }

  try {
    if (ttlSeconds) {
      await client.setex(key, ttlSeconds, value);
    } else {
      await client.set(key, value);
    }
    return true;
  } catch (error) {
    logger.error({ error, key }, 'Failed to set Redis key');
    return false;
  }
}

/**
 * Redis helper: Get value
 */
export async function getRedis(key: string): Promise<string | null> {
  const client = getRedisClient();
  if (!client) {
    return null;
  }

  try {
    return await client.get(key);
  } catch (error) {
    logger.error({ error, key }, 'Failed to get Redis key');
    return null;
  }
}

/**
 * Redis helper: Delete key
 */
export async function deleteRedis(key: string): Promise<boolean> {
  const client = getRedisClient();
  if (!client) {
    return false;
  }

  try {
    await client.del(key);
    return true;
  } catch (error) {
    logger.error({ error, key }, 'Failed to delete Redis key');
    return false;
  }
}

/**
 * Redis helper: Check if key exists
 */
export async function existsRedis(key: string): Promise<boolean> {
  const client = getRedisClient();
  if (!client) {
    return false;
  }

  try {
    const result = await client.exists(key);
    return result === 1;
  } catch (error) {
    logger.error({ error, key }, 'Failed to check Redis key existence');
    return false;
  }
}
