/**
 * Game State Manager
 * 
 * Example implementation showing how to use the storage service
 * for managing game state with Redis and persistent disk.
 * 
 * This can be used as a template for implementing game features.
 */

import {
  storeGameState,
  retrieveGameState,
  logEvent,
  saveBackup,
} from './storage.js';
import { logger } from '../core/logger.js';

export interface GameState {
  gameId: string;
  type: string;
  status: 'pending' | 'active' | 'completed' | 'cancelled';
  players: string[];
  startedAt?: string;
  endedAt?: string;
  data: Record<string, any>;
}

export interface GameScore {
  userId: string;
  score: number;
  timestamp: string;
}

/**
 * Create a new game session
 */
export async function createGame(
  gameId: string,
  type: string,
  initialData: Record<string, any> = {}
): Promise<boolean> {
  const state: GameState = {
    gameId,
    type,
    status: 'pending',
    players: [],
    data: initialData,
  };

  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'create',
      gameId,
      type,
    });
    logger.info({ gameId, type }, 'Game created');
  } else {
    logger.error({ gameId, type }, 'Failed to create game');
  }

  return success;
}

/**
 * Get current game state
 */
export async function getGame(gameId: string): Promise<GameState | null> {
  return await retrieveGameState<GameState>(gameId);
}

/**
 * Start a game (mark as active)
 */
export async function startGame(gameId: string): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  state.status = 'active';
  state.startedAt = new Date().toISOString();

  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'start',
      gameId,
      type: state.type,
    });
    logger.info({ gameId }, 'Game started');
  }

  return success;
}

/**
 * Add player to game
 */
export async function addPlayer(
  gameId: string,
  userId: string
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  if (state.players.includes(userId)) {
    logger.warn({ gameId, userId }, 'Player already in game');
    return true; // Not an error, player is already added
  }

  state.players.push(userId);
  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'player_join',
      gameId,
      userId,
      playerCount: state.players.length,
    });
    logger.info({ gameId, userId }, 'Player added to game');
  }

  return success;
}

/**
 * Remove player from game
 */
export async function removePlayer(
  gameId: string,
  userId: string
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  const index = state.players.indexOf(userId);
  if (index === -1) {
    logger.warn({ gameId, userId }, 'Player not in game');
    return true; // Not an error
  }

  state.players.splice(index, 1);
  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'player_leave',
      gameId,
      userId,
      playerCount: state.players.length,
    });
    logger.info({ gameId, userId }, 'Player removed from game');
  }

  return success;
}

/**
 * Update game data
 */
export async function updateGameData(
  gameId: string,
  data: Record<string, any>
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  state.data = { ...state.data, ...data };
  const success = await storeGameState(gameId, state);
  
  if (success) {
    logger.debug({ gameId }, 'Game data updated');
  }

  return success;
}

/**
 * Complete a game
 */
export async function completeGame(
  gameId: string,
  finalData?: Record<string, any>
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  state.status = 'completed';
  state.endedAt = new Date().toISOString();
  
  if (finalData) {
    state.data = { ...state.data, ...finalData };
  }

  const success = await storeGameState(gameId, state);
  
  if (success) {
    // Log completion
    await logEvent('game', {
      action: 'complete',
      gameId,
      type: state.type,
      playerCount: state.players.length,
      duration: state.startedAt 
        ? new Date(state.endedAt!).getTime() - new Date(state.startedAt).getTime()
        : 0,
    });
    
    // Create backup of completed game
    await saveBackup(`game-${state.type}`, state);
    
    logger.info({ gameId }, 'Game completed');
  }

  return success;
}

/**
 * Cancel a game
 */
export async function cancelGame(
  gameId: string,
  reason?: string
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  state.status = 'cancelled';
  state.endedAt = new Date().toISOString();
  
  if (reason) {
    state.data.cancelReason = reason;
  }

  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'cancel',
      gameId,
      type: state.type,
      reason,
    });
    logger.info({ gameId, reason }, 'Game cancelled');
  }

  return success;
}

/**
 * Record a score for a player in a game
 */
export async function recordScore(
  gameId: string,
  userId: string,
  score: number
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state) {
    logger.error({ gameId }, 'Game not found');
    return false;
  }

  if (!state.data.scores) {
    state.data.scores = [];
  }

  const scoreEntry: GameScore = {
    userId,
    score,
    timestamp: new Date().toISOString(),
  };

  state.data.scores.push(scoreEntry);
  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('game', {
      action: 'score',
      gameId,
      userId,
      score,
    });
    logger.info({ gameId, userId, score }, 'Score recorded');
  }

  return success;
}

/**
 * Get leaderboard for a game type
 * 
 * Note: This is a simplified example. In production, you might want to
 * maintain a separate leaderboard data structure for better performance.
 */
export async function getLeaderboard(
  gameType: string,
  limit: number = 10
): Promise<Array<{ userId: string; totalScore: number; games: number }>> {
  // This is a placeholder implementation
  // In a real app, you'd maintain a separate leaderboard structure
  logger.info({ gameType, limit }, 'Fetching leaderboard');
  
  // For now, return empty array
  // Implement actual leaderboard logic based on your needs
  return [];
}

/**
 * Example: FlaskGamba-specific game logic
 */
export async function createFlaskGambaRound(
  channelId: string,
  question: string,
  options: string[]
): Promise<string | null> {
  const gameId = `flaskgamba-${Date.now()}`;
  
  const success = await createGame(gameId, 'flaskgamba', {
    channelId,
    question,
    options,
    bets: [],
  });

  return success ? gameId : null;
}

/**
 * Example: Place a bet in FlaskGamba
 */
export async function placeBet(
  gameId: string,
  userId: string,
  choice: string,
  amount: number
): Promise<boolean> {
  const state = await getGame(gameId);
  if (!state || state.type !== 'flaskgamba') {
    logger.error({ gameId }, 'Invalid game for betting');
    return false;
  }

  if (!state.data.bets) {
    state.data.bets = [];
  }

  // Check if user already bet
  const existingBet = state.data.bets.find((bet: any) => bet.userId === userId);
  if (existingBet) {
    logger.warn({ gameId, userId }, 'User already placed a bet');
    return false;
  }

  state.data.bets.push({
    userId,
    choice,
    amount,
    timestamp: new Date().toISOString(),
  });

  const success = await storeGameState(gameId, state);
  
  if (success) {
    await logEvent('flaskgamba', {
      action: 'bet',
      gameId,
      userId,
      choice,
      amount,
    });
  }

  return success;
}
