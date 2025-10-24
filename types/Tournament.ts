/**
 * Tournament game mode types and interfaces
 */

/**
 * Tournament configuration
 */
export interface TournamentConfig {
  /** Unique tournament ID */
  id: string;
  /** Tournament name */
  name: string;
  /** Maximum roll number (e.g., 100 for 1-100) */
  maxRoll: number;
  /** Maximum number of rolls per user */
  rollLimit: number;
  /** Deadline timestamp (Unix timestamp in milliseconds) */
  deadline: number;
  /** Current round number */
  currentRound: number;
  /** Tournament status */
  status: TournamentStatus;
  /** Message ID for the tournament embed */
  messageId?: string;
  /** Channel ID where tournament is active */
  channelId: string;
  /** Created timestamp */
  createdAt: number;
  /** Updated timestamp */
  updatedAt: number;
}

/**
 * Tournament status enum
 */
export enum TournamentStatus {
  SETUP = 'setup',
  ACTIVE = 'active',
  ROUND_ENDING = 'round_ending',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
}

/**
 * User roll data
 */
export interface UserRoll {
  /** User ID */
  userId: string;
  /** Username for display */
  username: string;
  /** Roll value */
  roll: number;
  /** Timestamp of roll */
  timestamp: number;
  /** Number of rolls used */
  rollsUsed: number;
}

/**
 * Round data
 */
export interface RoundData {
  /** Round number */
  roundNumber: number;
  /** Start timestamp */
  startTime: number;
  /** End timestamp */
  endTime?: number;
  /** Users participating in this round */
  participants: string[];
  /** Users eliminated in this round */
  eliminated: string[];
  /** Minimum roll to survive */
  cutoffRoll?: number;
}

/**
 * Tournament statistics
 */
export interface TournamentStats {
  /** Total participants */
  totalParticipants: number;
  /** Active participants */
  activeParticipants: number;
  /** Eliminated participants */
  eliminatedParticipants: number;
  /** Total rolls made */
  totalRolls: number;
  /** Average roll value */
  averageRoll: number;
  /** Highest roll */
  highestRoll?: UserRoll;
  /** Lowest roll */
  lowestRoll?: UserRoll;
}
