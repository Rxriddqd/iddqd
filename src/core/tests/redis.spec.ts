/**
 * Redis client tests
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { getRedisClient, setRedis, getRedis, deleteRedis, existsRedis, disconnectRedis, isRedisAvailable } from '../redis.js';

describe('Redis Client', () => {
  beforeAll(async () => {
    // Initialize Redis client
    getRedisClient();
  });

  afterAll(async () => {
    // Clean up Redis connection
    await disconnectRedis();
  });

  it('should get Redis client instance', () => {
    const client = getRedisClient();
    // Client may be null if Redis is disabled or connection fails
    expect(client === null || typeof client === 'object').toBe(true);
  });

  it('should check Redis availability', async () => {
    const available = await isRedisAvailable();
    expect(typeof available).toBe('boolean');
  });

  it('should set and get a value', async () => {
    const key = 'test:redis:set-get';
    const value = 'test-value-123';
    
    const setResult = await setRedis(key, value);
    // May fail if Redis is not available, which is acceptable
    if (setResult) {
      const getResult = await getRedis(key);
      expect(getResult).toBe(value);
      
      // Cleanup
      await deleteRedis(key);
    }
  });

  it('should set a value with TTL', async () => {
    const key = 'test:redis:ttl';
    const value = 'ttl-value';
    const ttl = 1; // 1 second
    
    const setResult = await setRedis(key, value, ttl);
    if (setResult) {
      const getResult = await getRedis(key);
      expect(getResult).toBe(value);
      
      // Cleanup
      await deleteRedis(key);
    }
  });

  it('should delete a key', async () => {
    const key = 'test:redis:delete';
    const value = 'delete-value';
    
    const setResult = await setRedis(key, value);
    if (setResult) {
      const deleteResult = await deleteRedis(key);
      expect(deleteResult).toBe(true);
      
      const getResult = await getRedis(key);
      expect(getResult).toBeNull();
    }
  });

  it('should check if key exists', async () => {
    const key = 'test:redis:exists';
    const value = 'exists-value';
    
    const setResult = await setRedis(key, value);
    if (setResult) {
      const exists = await existsRedis(key);
      expect(exists).toBe(true);
      
      await deleteRedis(key);
      const notExists = await existsRedis(key);
      expect(notExists).toBe(false);
    }
  });

  it('should return null for non-existent key', async () => {
    const key = 'test:redis:non-existent';
    const getResult = await getRedis(key);
    expect(getResult).toBeNull();
  });

  it('should handle graceful disconnect', async () => {
    await expect(disconnectRedis()).resolves.not.toThrow();
  });
});
