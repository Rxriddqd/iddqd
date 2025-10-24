/**
 * Redis client configuration and connection management
 */

import { createClient, type RedisClientType } from 'redis';
import { logger } from '../core/logger.js';
import { env } from './env.js';

let redisClient: RedisClientType | null = null;

/**
 * Get Redis connection URL from environment
 */
function getRedisUrl(): string {
  if (env.REDIS_URL) {
    return env.REDIS_URL;
  }
  
  const host = env.REDIS_HOST || 'localhost';
  const port = env.REDIS_PORT || '6379';
  const password = env.REDIS_PASSWORD;
  
  if (password) {
    return `redis://:${password}@${host}:${port}`;
  }
  
  return `redis://${host}:${port}`;
}

/**
 * Initialize Redis client connection
 */
export async function initRedis(): Promise<RedisClientType> {
  if (redisClient) {
    return redisClient;
  }
  
  const redisUrl = getRedisUrl();
  
  redisClient = createClient({
    url: redisUrl,
    socket: {
      reconnectStrategy: (retries) => {
        if (retries > 10) {
          logger.error('Redis reconnection failed after 10 attempts');
          return new Error('Redis reconnection limit reached');
        }
        // Exponential backoff: 100ms, 200ms, 400ms, etc.
        return Math.min(retries * 100, 3000);
      },
    },
  });
  
  redisClient.on('error', (err) => {
    logger.error({ error: err }, 'Redis client error');
  });
  
  redisClient.on('connect', () => {
    logger.info('Redis client connected');
  });
  
  redisClient.on('reconnecting', () => {
    logger.info('Redis client reconnecting');
  });
  
  redisClient.on('ready', () => {
    logger.info('Redis client ready');
  });
  
  try {
    await redisClient.connect();
    logger.info('✅ Redis initialized successfully');
    return redisClient;
  } catch (error) {
    logger.error({ error }, 'Failed to connect to Redis');
    throw error;
  }
}

/**
 * Get the Redis client instance
 */
export function getRedisClient(): RedisClientType {
  if (!redisClient) {
    throw new Error('Redis client not initialized. Call initRedis() first.');
  }
  return redisClient;
}

/**
 * Check if Redis is available
 */
export function isRedisAvailable(): boolean {
  return redisClient !== null && redisClient.isOpen;
}

/**
 * Close Redis connection
 */
export async function closeRedis(): Promise<void> {
  if (redisClient) {
    await redisClient.quit();
    redisClient = null;
    logger.info('Redis connection closed');
  }
}
