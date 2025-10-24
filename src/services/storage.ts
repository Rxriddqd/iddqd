/**
 * Storage service abstraction layer
 * 
 * Provides a unified interface for data storage operations:
 * - Redis for short-term/cache data (game state, sessions, temporary data)
 * - Persistent disk for long-term data (logs, backups, historical data)
 * - Falls back to disk if Redis is unavailable
 */

import { getRedis, setRedis, deleteRedis, existsRedis } from '../core/redis.js';
import { readDisk, writeDisk, existsDisk, deleteDisk, readJSON, writeJSON, appendDisk } from '../core/disk.js';
import { logger } from '../core/logger.js';

export interface StorageOptions {
  ttl?: number; // Time to live in seconds (for Redis)
  persistToDisk?: boolean; // Also save to disk as backup
}

/**
 * Store data with automatic fallback
 * Uses Redis for short-term data, with optional disk persistence
 */
export async function storeData(
  key: string,
  value: string,
  options: StorageOptions = {}
): Promise<boolean> {
  const { ttl, persistToDisk = false } = options;
  
  // Try Redis first
  const redisSuccess = await setRedis(key, value, ttl);
  
  // If persist to disk is enabled or Redis failed, write to disk
  if (persistToDisk || !redisSuccess) {
    const diskPath = `cache/${key}.txt`;
    const diskSuccess = await writeDisk(diskPath, value);
    
    if (!redisSuccess && !diskSuccess) {
      logger.error({ key }, 'Failed to store data in both Redis and disk');
      return false;
    }
    
    return true;
  }
  
  return redisSuccess;
}

/**
 * Retrieve data with automatic fallback
 * Tries Redis first, falls back to disk
 */
export async function retrieveData(key: string): Promise<string | null> {
  // Try Redis first
  const redisValue = await getRedis(key);
  if (redisValue !== null) {
    return redisValue;
  }
  
  // Fall back to disk
  const diskPath = `cache/${key}.txt`;
  const diskValue = await readDisk(diskPath);
  
  // If found on disk, restore to Redis for faster access next time
  if (diskValue !== null) {
    await setRedis(key, diskValue, 3600); // Cache for 1 hour
  }
  
  return diskValue;
}

/**
 * Delete data from both Redis and disk
 */
export async function removeData(key: string): Promise<boolean> {
  const redisSuccess = await deleteRedis(key);
  const diskPath = `cache/${key}.txt`;
  const diskSuccess = await deleteDisk(diskPath);
  
  return redisSuccess || diskSuccess;
}

/**
 * Check if data exists in Redis or disk
 */
export async function dataExists(key: string): Promise<boolean> {
  const redisExists = await existsRedis(key);
  if (redisExists) {
    return true;
  }
  
  const diskPath = `cache/${key}.txt`;
  return await existsDisk(diskPath);
}

/**
 * Store JSON object
 */
export async function storeJSON<T>(
  key: string,
  data: T,
  options: StorageOptions = {}
): Promise<boolean> {
  try {
    const jsonString = JSON.stringify(data);
    return await storeData(key, jsonString, options);
  } catch (error) {
    logger.error({ error, key }, 'Failed to store JSON data');
    return false;
  }
}

/**
 * Retrieve JSON object
 */
export async function retrieveJSON<T>(key: string): Promise<T | null> {
  try {
    const jsonString = await retrieveData(key);
    if (!jsonString) {
      return null;
    }
    return JSON.parse(jsonString) as T;
  } catch (error) {
    logger.error({ error, key }, 'Failed to retrieve JSON data');
    return null;
  }
}

/**
 * Store game state (short-term Redis storage with disk backup)
 */
export async function storeGameState<T>(
  gameId: string,
  state: T
): Promise<boolean> {
  const key = `game:${gameId}:state`;
  return await storeJSON(key, state, { ttl: 86400, persistToDisk: true }); // 24 hours TTL
}

/**
 * Retrieve game state
 */
export async function retrieveGameState<T>(gameId: string): Promise<T | null> {
  const key = `game:${gameId}:state`;
  return await retrieveJSON<T>(key);
}

/**
 * Store user session data (short-term Redis only)
 */
export async function storeUserSession<T>(
  userId: string,
  sessionData: T
): Promise<boolean> {
  const key = `session:${userId}`;
  return await storeJSON(key, sessionData, { ttl: 3600 }); // 1 hour TTL
}

/**
 * Retrieve user session data
 */
export async function retrieveUserSession<T>(userId: string): Promise<T | null> {
  const key = `session:${userId}`;
  return await retrieveJSON<T>(key);
}

/**
 * Log event to persistent disk (append-only)
 */
export async function logEvent(
  logType: string,
  event: Record<string, any>
): Promise<boolean> {
  const timestamp = new Date().toISOString();
  const logLine = JSON.stringify({ timestamp, ...event }) + '\n';
  const logPath = `logs/${logType}/${new Date().toISOString().split('T')[0]}.log`;
  
  return await appendDisk(logPath, logLine);
}

/**
 * Save backup to persistent disk (long-term storage)
 */
export async function saveBackup<T>(
  backupName: string,
  data: T
): Promise<boolean> {
  const timestamp = new Date().toISOString().replace(/:/g, '-');
  const backupPath = `backups/${backupName}/${timestamp}.json`;
  
  return await writeJSON(backupPath, data);
}

/**
 * Retrieve backup from persistent disk
 */
export async function retrieveBackup<T>(
  backupName: string,
  timestamp: string
): Promise<T | null> {
  const backupPath = `backups/${backupName}/${timestamp}.json`;
  return await readJSON<T>(backupPath);
}
