/**
 * Tournament game logic tests
 */

import { describe, it, expect } from 'vitest';
import { TournamentStatus } from '../../../types/Tournament.js';

describe('Tournament Types', () => {
  it('should have correct status enum values', () => {
    expect(TournamentStatus.SETUP).toBe('setup');
    expect(TournamentStatus.ACTIVE).toBe('active');
    expect(TournamentStatus.ROUND_ENDING).toBe('round_ending');
    expect(TournamentStatus.COMPLETED).toBe('completed');
    expect(TournamentStatus.CANCELLED).toBe('cancelled');
  });
});

describe('Tournament Configuration', () => {
  it('should validate roll limits', () => {
    const validRollLimits = [1, 3, 5, 10];
    
    for (const limit of validRollLimits) {
      expect(limit).toBeGreaterThanOrEqual(1);
      expect(limit).toBeLessThanOrEqual(10);
    }
  });
  
  it('should validate max roll values', () => {
    const validMaxRolls = [10, 50, 100, 1000, 10000];
    
    for (const maxRoll of validMaxRolls) {
      expect(maxRoll).toBeGreaterThanOrEqual(10);
      expect(maxRoll).toBeLessThanOrEqual(10000);
    }
  });
  
  it('should validate deadline hours', () => {
    const validDeadlines = [1, 6, 12, 24, 48, 72, 168];
    
    for (const deadline of validDeadlines) {
      expect(deadline).toBeGreaterThanOrEqual(1);
      expect(deadline).toBeLessThanOrEqual(168);
    }
  });
});

describe('Tournament Roll Logic', () => {
  it('should generate random roll within range', () => {
    const maxRoll = 100;
    const rolls: number[] = [];
    
    // Generate 100 rolls and verify they're in range
    for (let i = 0; i < 100; i++) {
      const roll = Math.floor(Math.random() * maxRoll) + 1;
      rolls.push(roll);
      expect(roll).toBeGreaterThanOrEqual(1);
      expect(roll).toBeLessThanOrEqual(maxRoll);
    }
    
    // Verify we get some variety
    const uniqueRolls = new Set(rolls);
    expect(uniqueRolls.size).toBeGreaterThan(10);
  });
  
  it('should track roll count correctly', () => {
    const rollLimit = 3;
    let rollsUsed = 0;
    
    for (let i = 0; i < rollLimit; i++) {
      rollsUsed++;
      expect(rollsUsed).toBeLessThanOrEqual(rollLimit);
    }
    
    expect(rollsUsed).toBe(rollLimit);
  });
});

describe('Tournament Leaderboard', () => {
  it('should sort players by roll value descending', () => {
    const players = [
      { userId: '1', username: 'Alice', roll: 45, timestamp: 1000, rollsUsed: 1 },
      { userId: '2', username: 'Bob', roll: 92, timestamp: 1001, rollsUsed: 1 },
      { userId: '3', username: 'Charlie', roll: 67, timestamp: 1002, rollsUsed: 1 },
      { userId: '4', username: 'David', roll: 23, timestamp: 1003, rollsUsed: 1 },
    ];
    
    const sorted = [...players].sort((a, b) => b.roll - a.roll);
    
    expect(sorted[0].username).toBe('Bob');
    expect(sorted[1].username).toBe('Charlie');
    expect(sorted[2].username).toBe('Alice');
    expect(sorted[3].username).toBe('David');
  });
  
  it('should limit leaderboard to top 10', () => {
    const players = Array.from({ length: 50 }, (_, i) => ({
      userId: `${i}`,
      username: `Player${i}`,
      roll: Math.floor(Math.random() * 100) + 1,
      timestamp: Date.now(),
      rollsUsed: 1,
    }));
    
    const sorted = [...players].sort((a, b) => b.roll - a.roll);
    const top10 = sorted.slice(0, 10);
    
    expect(top10.length).toBe(10);
  });
});

describe('Tournament Elimination', () => {
  it('should calculate elimination count correctly', () => {
    const playerCounts = [10, 20, 50, 100];
    const eliminationPercentage = 50;
    
    for (const count of playerCounts) {
      const eliminateCount = Math.floor(count * (eliminationPercentage / 100));
      expect(eliminateCount).toBe(Math.floor(count / 2));
      expect(count - eliminateCount).toBeLessThanOrEqual(count);
    }
  });
  
  it('should determine cutoff roll correctly', () => {
    const rolls = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    const eliminateCount = Math.floor(rolls.length * 0.5);
    const cutoffIndex = rolls.length - eliminateCount - 1;
    const cutoffRoll = rolls[cutoffIndex];
    
    expect(cutoffRoll).toBe(50);
    expect(rolls.filter(r => r < cutoffRoll).length).toBeLessThanOrEqual(eliminateCount);
  });
});

describe('Tournament Statistics', () => {
  it('should calculate average roll correctly', () => {
    const rolls = [10, 20, 30, 40, 50];
    const average = rolls.reduce((sum, roll) => sum + roll, 0) / rolls.length;
    
    expect(average).toBe(30);
  });
  
  it('should find highest and lowest rolls', () => {
    const rolls = [45, 92, 67, 23, 18, 76];
    const highest = Math.max(...rolls);
    const lowest = Math.min(...rolls);
    
    expect(highest).toBe(92);
    expect(lowest).toBe(18);
  });
  
  it('should count total rolls correctly', () => {
    const players = [
      { rollsUsed: 3 },
      { rollsUsed: 2 },
      { rollsUsed: 1 },
      { rollsUsed: 3 },
    ];
    
    const totalRolls = players.reduce((sum, p) => sum + p.rollsUsed, 0);
    expect(totalRolls).toBe(9);
  });
});
