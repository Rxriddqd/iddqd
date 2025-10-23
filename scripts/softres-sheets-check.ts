/**
 * Check soft reserve sheets configuration
 */

import 'dotenv/config';
import { env } from '../src/config/env.js';
import { RAID_SHEETS, getAllRaidRanges } from '../src/config/sheets.js';
import { logger } from '../src/core/logger.js';

function checkSoftResSheets() {
  logger.info('📊 Soft Reserve Sheets Configuration');
  logger.info('═'.repeat(50));
  
  logger.info(`\nSheet ID: ${env.SHEET_IDDQD_ID || 'Not configured'}`);
  logger.info(`Panel Channel: ${env.SR_PANEL_CHANNEL_ID || 'Not configured'}`);
  
  logger.info('\n📋 Configured Raid Sheets:');
  Object.entries(RAID_SHEETS).forEach(([key, config]) => {
    const msgId = process.env[config.msgIdEnv];
    logger.info(`\n  ${key} - ${config.name}`);
    logger.info(`    Range: ${config.range}`);
    logger.info(`    Message ID Env: ${config.msgIdEnv}`);
    logger.info(`    Message ID: ${msgId || 'Not set'}`);
  });
  
  const allRanges = getAllRaidRanges();
  logger.info(`\n📝 Total ranges configured: ${allRanges.length}`);
  
  logger.info('\n═'.repeat(50));
}

checkSoftResSheets();
