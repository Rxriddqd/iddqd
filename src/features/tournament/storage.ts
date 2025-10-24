/**
 * Tournament data storage service using Redis
 */

import { getRedisClient } from '../../core/redis.js';
import type Redis from 'ioredis';
import { logger } from '../../core/logger.js';
import type {
  TournamentConfig,
  UserRoll,
  RoundData,
  TournamentStats,
} from '../../../types/Tournament.js';

const TOURNAMENT_PREFIX = 'tournament:';
const TOURNAMENT_ROLLS_PREFIX = 'tournament:rolls:';
const TOURNAMENT_ROUND_PREFIX = 'tournament:round:';
const TOURNAMENT_STATS_PREFIX = 'tournament:stats:';

/**
 * Get Redis client or throw error if not available
 */
function requireRedisClient(): Redis {
  const client = getRedisClient();
  if (!client) {
    throw new Error('Redis client not available');
  }
  return client;
}

/**
 * Save tournament configuration
 */
export async function saveTournamentConfig(config: TournamentConfig): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_PREFIX}${config.id}`;
  
  try {
    await client.set(key, JSON.stringify(config));
    logger.info({ tournamentId: config.id }, 'Tournament config saved');
  } catch (error) {
    logger.error({ error, tournamentId: config.id }, 'Failed to save tournament config');
    throw error;
  }
}

/**
 * Get tournament configuration
 */
export async function getTournamentConfig(tournamentId: string): Promise<TournamentConfig | null> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_PREFIX}${tournamentId}`;
  
  try {
    const data = await client.get(key);
    if (!data) return null;
    
    return JSON.parse(data) as TournamentConfig;
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to get tournament config');
    return null;
  }
}

/**
 * Delete tournament configuration
 */
export async function deleteTournamentConfig(tournamentId: string): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_PREFIX}${tournamentId}`;
  
  try {
    await client.del(key);
    logger.info({ tournamentId }, 'Tournament config deleted');
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to delete tournament config');
    throw error;
  }
}

/**
 * Save user roll
 */
export async function saveUserRoll(
  tournamentId: string,
  userId: string,
  roll: UserRoll
): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROLLS_PREFIX}${tournamentId}`;
  
  try {
    await client.hset(key, userId, JSON.stringify(roll));
    logger.info({ tournamentId, userId, roll: roll.roll }, 'User roll saved');
  } catch (error) {
    logger.error({ error, tournamentId, userId }, 'Failed to save user roll');
    throw error;
  }
}

/**
 * Get user roll
 */
export async function getUserRoll(
  tournamentId: string,
  userId: string
): Promise<UserRoll | null> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROLLS_PREFIX}${tournamentId}`;
  
  try {
    const data = await client.hget(key, userId);
    if (!data) return null;
    
    return JSON.parse(data) as UserRoll;
  } catch (error) {
    logger.error({ error, tournamentId, userId }, 'Failed to get user roll');
    return null;
  }
}

/**
 * Get all user rolls for a tournament
 */
export async function getAllUserRolls(tournamentId: string): Promise<UserRoll[]> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROLLS_PREFIX}${tournamentId}`;
  
  try {
    const data = await client.hgetall(key);
    const rolls: UserRoll[] = [];
    
    for (const value of Object.values(data)) {
      rolls.push(JSON.parse(value) as UserRoll);
    }
    
    return rolls;
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to get all user rolls');
    return [];
  }
}

/**
 * Delete all user rolls for a tournament
 */
export async function deleteAllUserRolls(tournamentId: string): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROLLS_PREFIX}${tournamentId}`;
  
  try {
    await client.del(key);
    logger.info({ tournamentId }, 'All user rolls deleted');
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to delete user rolls');
    throw error;
  }
}

/**
 * Save round data
 */
export async function saveRoundData(
  tournamentId: string,
  roundNumber: number,
  round: RoundData
): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROUND_PREFIX}${tournamentId}:${roundNumber}`;
  
  try {
    await client.set(key, JSON.stringify(round));
    logger.info({ tournamentId, roundNumber }, 'Round data saved');
  } catch (error) {
    logger.error({ error, tournamentId, roundNumber }, 'Failed to save round data');
    throw error;
  }
}

/**
 * Get round data
 */
export async function getRoundData(
  tournamentId: string,
  roundNumber: number
): Promise<RoundData | null> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_ROUND_PREFIX}${tournamentId}:${roundNumber}`;
  
  try {
    const data = await client.get(key);
    if (!data) return null;
    
    return JSON.parse(data) as RoundData;
  } catch (error) {
    logger.error({ error, tournamentId, roundNumber }, 'Failed to get round data');
    return null;
  }
}

/**
 * Get all round data for a tournament
 */
export async function getAllRoundData(tournamentId: string): Promise<RoundData[]> {
  const client = requireRedisClient();
  const pattern = `${TOURNAMENT_ROUND_PREFIX}${tournamentId}:*`;
  
  try {
    const keys = await client.keys(pattern);
    const rounds: RoundData[] = [];
    
    for (const key of keys) {
      const data = await client.get(key);
      if (data) {
        rounds.push(JSON.parse(data) as RoundData);
      }
    }
    
    return rounds.sort((a, b) => a.roundNumber - b.roundNumber);
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to get all round data');
    return [];
  }
}

/**
 * Calculate and save tournament statistics
 */
export async function saveTournamentStats(
  tournamentId: string,
  stats: TournamentStats
): Promise<void> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_STATS_PREFIX}${tournamentId}`;
  
  try {
    await client.set(key, JSON.stringify(stats));
    logger.info({ tournamentId }, 'Tournament stats saved');
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to save tournament stats');
    throw error;
  }
}

/**
 * Get tournament statistics
 */
export async function getTournamentStats(tournamentId: string): Promise<TournamentStats | null> {
  const client = requireRedisClient();
  const key = `${TOURNAMENT_STATS_PREFIX}${tournamentId}`;
  
  try {
    const data = await client.get(key);
    if (!data) return null;
    
    return JSON.parse(data) as TournamentStats;
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to get tournament stats');
    return null;
  }
}

/**
 * List all active tournaments
 */
export async function listActiveTournaments(): Promise<TournamentConfig[]> {
  const client = requireRedisClient();
  const pattern = `${TOURNAMENT_PREFIX}*`;
  
  try {
    const keys = await client.keys(pattern);
    const tournaments: TournamentConfig[] = [];
    
    for (const key of keys) {
      const data = await client.get(key);
      if (data) {
        tournaments.push(JSON.parse(data) as TournamentConfig);
      }
    }
    
    return tournaments;
  } catch (error) {
    logger.error({ error }, 'Failed to list active tournaments');
    return [];
  }
}
