/**
 * Game State Manager tests
 */

import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import {
  createGame,
  getGame,
  startGame,
  addPlayer,
  removePlayer,
  updateGameData,
  completeGame,
  cancelGame,
  recordScore,
  createFlaskGambaRound,
  placeBet,
} from '../gameStateManager.js';
import { removeData } from '../storage.js';
import { promises as fs } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const TEST_DIR = join(tmpdir(), 'iddqd-game-tests');

describe('Game State Manager', () => {
  beforeAll(async () => {
    process.env.PERSISTENT_DISK_PATH = TEST_DIR;
    process.env.REDIS_ENABLED = 'false';
    await fs.mkdir(TEST_DIR, { recursive: true });
  });

  afterAll(async () => {
    try {
      await fs.rm(TEST_DIR, { recursive: true, force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  describe('Basic Game Operations', () => {
    const gameId = 'test-game-basic';

    beforeEach(async () => {
      // Clean up before each test
      await removeData(`game:${gameId}:state`);
    });

    it('should create a new game', async () => {
      const success = await createGame(gameId, 'test', { difficulty: 'easy' });
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game).toBeDefined();
      expect(game?.gameId).toBe(gameId);
      expect(game?.type).toBe('test');
      expect(game?.status).toBe('pending');
      expect(game?.data.difficulty).toBe('easy');
    });

    it('should start a game', async () => {
      await createGame(gameId, 'test');
      
      const success = await startGame(gameId);
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game?.status).toBe('active');
      expect(game?.startedAt).toBeDefined();
    });

    it('should add players to game', async () => {
      await createGame(gameId, 'test');
      
      const success1 = await addPlayer(gameId, 'user1');
      expect(success1).toBe(true);

      const success2 = await addPlayer(gameId, 'user2');
      expect(success2).toBe(true);

      const game = await getGame(gameId);
      expect(game?.players).toHaveLength(2);
      expect(game?.players).toContain('user1');
      expect(game?.players).toContain('user2');
    });

    it('should not add duplicate players', async () => {
      await createGame(gameId, 'test');
      
      await addPlayer(gameId, 'user1');
      await addPlayer(gameId, 'user1'); // Duplicate

      const game = await getGame(gameId);
      expect(game?.players).toHaveLength(1);
    });

    it('should remove players from game', async () => {
      await createGame(gameId, 'test');
      await addPlayer(gameId, 'user1');
      await addPlayer(gameId, 'user2');
      
      const success = await removePlayer(gameId, 'user1');
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game?.players).toHaveLength(1);
      expect(game?.players).not.toContain('user1');
      expect(game?.players).toContain('user2');
    });

    it('should update game data', async () => {
      await createGame(gameId, 'test', { score: 0 });
      
      const success = await updateGameData(gameId, { 
        score: 100,
        level: 2,
      });
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game?.data.score).toBe(100);
      expect(game?.data.level).toBe(2);
    });

    it('should complete a game', async () => {
      await createGame(gameId, 'test');
      await startGame(gameId);
      
      const success = await completeGame(gameId, { winner: 'user1' });
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game?.status).toBe('completed');
      expect(game?.endedAt).toBeDefined();
      expect(game?.data.winner).toBe('user1');
    });

    it('should cancel a game', async () => {
      await createGame(gameId, 'test');
      
      const success = await cancelGame(gameId, 'Not enough players');
      expect(success).toBe(true);

      const game = await getGame(gameId);
      expect(game?.status).toBe('cancelled');
      expect(game?.endedAt).toBeDefined();
      expect(game?.data.cancelReason).toBe('Not enough players');
    });
  });

  describe('Score Recording', () => {
    const gameId = 'test-game-scores';

    beforeEach(async () => {
      await removeData(`game:${gameId}:state`);
      await createGame(gameId, 'test');
    });

    it('should record player scores', async () => {
      const success1 = await recordScore(gameId, 'user1', 100);
      expect(success1).toBe(true);

      const success2 = await recordScore(gameId, 'user2', 150);
      expect(success2).toBe(true);

      const game = await getGame(gameId);
      expect(game?.data.scores).toHaveLength(2);
      expect(game?.data.scores[0].userId).toBe('user1');
      expect(game?.data.scores[0].score).toBe(100);
      expect(game?.data.scores[1].userId).toBe('user2');
      expect(game?.data.scores[1].score).toBe(150);
    });

    it('should allow multiple scores from same user', async () => {
      await recordScore(gameId, 'user1', 50);
      await recordScore(gameId, 'user1', 75);

      const game = await getGame(gameId);
      expect(game?.data.scores).toHaveLength(2);
    });
  });

  describe('FlaskGamba Specific', () => {
    it('should create a FlaskGamba round', async () => {
      const gameId = await createFlaskGambaRound(
        'channel123',
        'Will it flask?',
        ['Yes', 'No']
      );

      expect(gameId).toBeDefined();
      expect(gameId).toMatch(/^flaskgamba-/);

      if (gameId) {
        const game = await getGame(gameId);
        expect(game?.type).toBe('flaskgamba');
        expect(game?.data.question).toBe('Will it flask?');
        expect(game?.data.options).toEqual(['Yes', 'No']);
      }
    });

    it('should place bets in FlaskGamba', async () => {
      const gameId = await createFlaskGambaRound(
        'channel123',
        'Will it flask?',
        ['Yes', 'No']
      );

      if (gameId) {
        const success = await placeBet(gameId, 'user1', 'Yes', 10);
        expect(success).toBe(true);

        const game = await getGame(gameId);
        expect(game?.data.bets).toHaveLength(1);
        expect(game?.data.bets[0].userId).toBe('user1');
        expect(game?.data.bets[0].choice).toBe('Yes');
        expect(game?.data.bets[0].amount).toBe(10);
      }
    });

    it('should prevent duplicate bets', async () => {
      const gameId = await createFlaskGambaRound(
        'channel123',
        'Will it flask?',
        ['Yes', 'No']
      );

      if (gameId) {
        await placeBet(gameId, 'user1', 'Yes', 10);
        const success = await placeBet(gameId, 'user1', 'No', 5); // Duplicate

        expect(success).toBe(false);

        const game = await getGame(gameId);
        expect(game?.data.bets).toHaveLength(1);
      }
    });
  });

  describe('Error Handling', () => {
    it('should handle non-existent game', async () => {
      const game = await getGame('non-existent');
      expect(game).toBeNull();
    });

    it('should fail to start non-existent game', async () => {
      const success = await startGame('non-existent');
      expect(success).toBe(false);
    });

    it('should fail to add player to non-existent game', async () => {
      const success = await addPlayer('non-existent', 'user1');
      expect(success).toBe(false);
    });

    it('should fail to record score for non-existent game', async () => {
      const success = await recordScore('non-existent', 'user1', 100);
      expect(success).toBe(false);
    });
  });
});
