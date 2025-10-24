/**
 * Tournament game logic and mechanics
 */

import { logger } from '../../core/logger.js';

/**
 * Default elimination percentage for tournament rounds
 */
const DEFAULT_ELIMINATION_PERCENTAGE = 50;
import {
  TournamentStatus,
  type TournamentConfig,
  type UserRoll,
  type RoundData,
  type TournamentStats,
} from '../../../types/Tournament.js';
import {
  saveTournamentConfig,
  getTournamentConfig,
  saveUserRoll,
  getUserRoll,
  getAllUserRolls,
  saveRoundData,
  getRoundData,
  saveTournamentStats,
  deleteAllUserRolls,
} from './storage.js';

/**
 * Create a new tournament
 */
export async function createTournament(
  name: string,
  maxRoll: number,
  rollLimit: number,
  deadlineHours: number,
  channelId: string
): Promise<TournamentConfig> {
  const now = Date.now();
  const deadline = now + deadlineHours * 60 * 60 * 1000;
  
  const config: TournamentConfig = {
    id: `tournament-${now}`,
    name,
    maxRoll,
    rollLimit,
    deadline,
    currentRound: 1,
    status: TournamentStatus.ACTIVE,
    channelId,
    createdAt: now,
    updatedAt: now,
  };
  
  await saveTournamentConfig(config);
  
  // Initialize round 1
  const round: RoundData = {
    roundNumber: 1,
    startTime: now,
    participants: [],
    eliminated: [],
  };
  await saveRoundData(config.id, 1, round);
  
  logger.info({ tournamentId: config.id, name }, 'Tournament created');
  return config;
}

/**
 * Get tournament by ID
 */
export async function getTournament(tournamentId: string): Promise<TournamentConfig | null> {
  return getTournamentConfig(tournamentId);
}

/**
 * Process user roll
 */
export async function processUserRoll(
  tournamentId: string,
  userId: string,
  username: string
): Promise<{ success: boolean; roll?: UserRoll; message: string }> {
  const config = await getTournamentConfig(tournamentId);
  
  if (!config) {
    return { success: false, message: 'Tournament not found' };
  }
  
  if (config.status !== TournamentStatus.ACTIVE) {
    return { success: false, message: 'Tournament is not active' };
  }
  
  const now = Date.now();
  if (now > config.deadline) {
    return { success: false, message: 'Tournament deadline has passed' };
  }
  
  // Check existing roll
  const existingRoll = await getUserRoll(tournamentId, userId);
  
  if (existingRoll && existingRoll.rollsUsed >= config.rollLimit) {
    return {
      success: false,
      message: `You have used all ${config.rollLimit} rolls`,
    };
  }
  
  // Generate roll
  const rollValue = Math.floor(Math.random() * config.maxRoll) + 1;
  const rollsUsed = existingRoll ? existingRoll.rollsUsed + 1 : 1;
  
  // Only save if it's better than existing roll or first roll
  if (!existingRoll || rollValue > existingRoll.roll) {
    const roll: UserRoll = {
      userId,
      username,
      roll: rollValue,
      timestamp: now,
      rollsUsed,
    };
    
    await saveUserRoll(tournamentId, userId, roll);
    
    return {
      success: true,
      roll,
      message: `Rolled ${rollValue}! (${rollsUsed}/${config.rollLimit} rolls used)`,
    };
  } else {
    // Update rolls used even if roll wasn't better
    const updatedRoll = { ...existingRoll, rollsUsed };
    await saveUserRoll(tournamentId, userId, updatedRoll);
    
    return {
      success: true,
      roll: existingRoll,
      message: `Rolled ${rollValue}, but your previous roll of ${existingRoll.roll} was better. (${rollsUsed}/${config.rollLimit} rolls used)`,
    };
  }
}

/**
 * End current round and eliminate bottom performers
 */
export async function endRound(
  tournamentId: string,
  eliminationPercentage: number = DEFAULT_ELIMINATION_PERCENTAGE
): Promise<{ success: boolean; message: string; eliminated?: string[] }> {
  const config = await getTournamentConfig(tournamentId);
  
  if (!config) {
    return { success: false, message: 'Tournament not found' };
  }
  
  if (config.status !== TournamentStatus.ACTIVE) {
    return { success: false, message: 'Tournament is not active' };
  }
  
  const allRolls = await getAllUserRolls(tournamentId);
  
  if (allRolls.length === 0) {
    return { success: false, message: 'No participants in this round' };
  }
  
  // Sort by roll value descending
  const sortedRolls = allRolls.sort((a, b) => b.roll - a.roll);
  
  // Calculate cutoff
  const eliminateCount = Math.floor(sortedRolls.length * (eliminationPercentage / 100));
  const cutoffIndex = Math.max(0, sortedRolls.length - eliminateCount - 1);
  const cutoffRoll = sortedRolls[cutoffIndex]?.roll || 0;
  
  // Determine eliminated users
  const eliminated = sortedRolls
    .slice(sortedRolls.length - eliminateCount)
    .map(r => r.userId);
  
  // Save round data
  const roundData: RoundData = {
    roundNumber: config.currentRound,
    startTime: (await getRoundData(tournamentId, config.currentRound))?.startTime || Date.now(),
    endTime: Date.now(),
    participants: sortedRolls.map(r => r.userId),
    eliminated,
    cutoffRoll,
  };
  await saveRoundData(tournamentId, config.currentRound, roundData);
  
  // Clear rolls for next round
  await deleteAllUserRolls(tournamentId);
  
  // Check if tournament is complete
  const remainingPlayers = sortedRolls.length - eliminateCount;
  if (remainingPlayers <= 1) {
    config.status = TournamentStatus.COMPLETED;
    config.updatedAt = Date.now();
    await saveTournamentConfig(config);
    
    return {
      success: true,
      message: `Tournament complete! Winner: ${sortedRolls[0].username}`,
      eliminated,
    };
  }
  
  // Start next round
  config.currentRound += 1;
  config.updatedAt = Date.now();
  await saveTournamentConfig(config);
  
  // Initialize next round
  const nextRound: RoundData = {
    roundNumber: config.currentRound,
    startTime: Date.now(),
    participants: sortedRolls.slice(0, remainingPlayers).map(r => r.userId),
    eliminated: [],
  };
  await saveRoundData(tournamentId, config.currentRound, nextRound);
  
  return {
    success: true,
    message: `Round ${config.currentRound - 1} ended. ${eliminateCount} players eliminated. Starting round ${config.currentRound}!`,
    eliminated,
  };
}

/**
 * Calculate tournament statistics
 */
export async function calculateStats(tournamentId: string): Promise<TournamentStats | null> {
  const allRolls = await getAllUserRolls(tournamentId);
  
  if (allRolls.length === 0) {
    return null;
  }
  
  const totalRolls = allRolls.reduce((sum, roll) => sum + roll.rollsUsed, 0);
  const averageRoll = allRolls.reduce((sum, roll) => sum + roll.roll, 0) / allRolls.length;
  
  const sortedRolls = allRolls.sort((a, b) => b.roll - a.roll);
  const highestRoll = sortedRolls[0];
  const lowestRoll = sortedRolls[sortedRolls.length - 1];
  
  const stats: TournamentStats = {
    totalParticipants: allRolls.length,
    activeParticipants: allRolls.length,
    eliminatedParticipants: 0,
    totalRolls,
    averageRoll: Math.round(averageRoll * 100) / 100,
    highestRoll,
    lowestRoll,
  };
  
  await saveTournamentStats(tournamentId, stats);
  return stats;
}

/**
 * Get leaderboard
 */
export async function getLeaderboard(tournamentId: string, limit: number = 10): Promise<UserRoll[]> {
  const allRolls = await getAllUserRolls(tournamentId);
  return allRolls.sort((a, b) => b.roll - a.roll).slice(0, limit);
}

/**
 * Cancel tournament
 */
export async function cancelTournament(tournamentId: string): Promise<boolean> {
  const config = await getTournamentConfig(tournamentId);
  
  if (!config) {
    return false;
  }
  
  config.status = TournamentStatus.CANCELLED;
  config.updatedAt = Date.now();
  await saveTournamentConfig(config);
  
  logger.info({ tournamentId }, 'Tournament cancelled');
  return true;
}
