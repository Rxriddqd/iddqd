/**
 * Storage service tests
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import {
  storeData,
  retrieveData,
  removeData,
  dataExists,
  storeJSON,
  retrieveJSON,
  storeGameState,
  retrieveGameState,
  storeUserSession,
  retrieveUserSession,
  logEvent,
  saveBackup,
} from '../storage.js';
import { promises as fs } from 'fs';

const TEST_DIR = '/tmp/iddqd-storage-tests';

describe('Storage Service', () => {
  beforeAll(async () => {
    // Use /tmp for tests
    process.env.PERSISTENT_DISK_PATH = TEST_DIR;
    process.env.REDIS_ENABLED = 'false'; // Disable Redis for consistent tests
    await fs.mkdir(TEST_DIR, { recursive: true });
  });

  afterAll(async () => {
    // Clean up test directory
    try {
      await fs.rm(TEST_DIR, { recursive: true, force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  describe('Basic Operations', () => {
    it('should store and retrieve data', async () => {
      const key = 'test-key';
      const value = 'test-value';
      
      const storeResult = await storeData(key, value);
      expect(storeResult).toBe(true);
      
      const retrieveResult = await retrieveData(key);
      expect(retrieveResult).toBe(value);
      
      // Cleanup
      await removeData(key);
    });

    it('should check if data exists', async () => {
      const key = 'exists-key';
      const value = 'exists-value';
      
      const existsBefore = await dataExists(key);
      expect(existsBefore).toBe(false);
      
      await storeData(key, value);
      
      const existsAfter = await dataExists(key);
      expect(existsAfter).toBe(true);
      
      // Cleanup
      await removeData(key);
    });

    it('should remove data', async () => {
      const key = 'remove-key';
      const value = 'remove-value';
      
      await storeData(key, value);
      
      const removeResult = await removeData(key);
      expect(removeResult).toBe(true);
      
      const exists = await dataExists(key);
      expect(exists).toBe(false);
    });
  });

  describe('JSON Operations', () => {
    it('should store and retrieve JSON', async () => {
      const key = 'json-key';
      const data = { name: 'test', count: 42, items: [1, 2, 3] };
      
      const storeResult = await storeJSON(key, data);
      expect(storeResult).toBe(true);
      
      const retrieveResult = await retrieveJSON(key);
      expect(retrieveResult).toEqual(data);
      
      // Cleanup
      await removeData(key);
    });

    it('should return null for non-existent JSON', async () => {
      const key = 'non-existent-json';
      const result = await retrieveJSON(key);
      expect(result).toBeNull();
    });
  });

  describe('Game State Operations', () => {
    it('should store and retrieve game state', async () => {
      const gameId = 'game-123';
      const state = {
        players: ['player1', 'player2'],
        score: { player1: 100, player2: 150 },
        status: 'active',
      };
      
      const storeResult = await storeGameState(gameId, state);
      expect(storeResult).toBe(true);
      
      const retrieveResult = await retrieveGameState(gameId);
      expect(retrieveResult).toEqual(state);
      
      // Cleanup
      await removeData(`game:${gameId}:state`);
    });
  });

  describe('User Session Operations', () => {
    it('should store and retrieve user session', async () => {
      const userId = 'user-456';
      const sessionData = {
        currentGame: 'game-123',
        lastAction: 'roll-dice',
        timestamp: Date.now(),
      };
      
      const storeResult = await storeUserSession(userId, sessionData);
      expect(storeResult).toBe(true);
      
      const retrieveResult = await retrieveUserSession(userId);
      expect(retrieveResult).toEqual(sessionData);
      
      // Cleanup
      await removeData(`session:${userId}`);
    });
  });

  describe('Log Operations', () => {
    it('should log events to disk', async () => {
      const logType = 'test-events';
      const event = {
        action: 'test-action',
        user: 'test-user',
        details: 'test details',
      };
      
      const logResult = await logEvent(logType, event);
      expect(logResult).toBe(true);
    });
  });

  describe('Backup Operations', () => {
    it('should save backup to disk', async () => {
      const backupName = 'test-backup';
      const data = {
        timestamp: new Date().toISOString(),
        data: { key: 'value', count: 10 },
      };
      
      const saveResult = await saveBackup(backupName, data);
      expect(saveResult).toBe(true);
    });
  });

  describe('Storage Options', () => {
    it('should store with persist to disk option', async () => {
      const key = 'persist-key';
      const value = 'persist-value';
      
      const storeResult = await storeData(key, value, { persistToDisk: true });
      expect(storeResult).toBe(true);
      
      const retrieveResult = await retrieveData(key);
      expect(retrieveResult).toBe(value);
      
      // Cleanup
      await removeData(key);
    });
  });
});
