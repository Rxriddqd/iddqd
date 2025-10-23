/**
 * Google Sheets configuration for raid data
 * 
 * This module defines the cell ranges for various raid-related sheets
 * used throughout the application.
 */

export interface RaidSheetConfig {
  name: string;
  msgIdEnv: string;
  range: string;
}

/**
 * Configuration for all raid sheets
 */
export const RAID_SHEETS: Record<string, RaidSheetConfig> = {
  MC: {
    name: 'Molten Core',
    msgIdEnv: 'MC_RAID_MSG_ID',
    range: 'MC!A2:I100',
  },
  BWL: {
    name: "Blackwing Lair",
    msgIdEnv: 'BWL_RAID_MSG_ID',
    range: 'BWL!A2:I100',
  },
  AQ40: {
    name: 'Temple of Ahn\'Qiraj',
    msgIdEnv: 'AQ40_RAID_MSG_ID',
    range: 'AQ40!A2:I100',
  },
  NAXX: {
    name: 'Naxxramas',
    msgIdEnv: 'NAXX_RAID_MSG_ID',
    range: 'Naxx!A2:I100',
  },
} as const;

/**
 * Get all configured raid sheet ranges
 */
export function getAllRaidRanges(): string[] {
  return Object.values(RAID_SHEETS).map(sheet => sheet.range);
}

/**
 * Get raid sheet config by key
 */
export function getRaidSheet(key: string): RaidSheetConfig | undefined {
  return RAID_SHEETS[key];
}
