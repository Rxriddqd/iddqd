/**
 * Test Google Sheets connectivity
 */

import 'dotenv/config';
import { env } from '../src/config/env.js';
import { logger } from '../src/core/logger.js';

async function testSheets() {
  logger.info('🧪 Testing Google Sheets connectivity...');
  
  if (!env.GOOGLE_SERVICE_ACCOUNT_EMAIL || !env.GOOGLE_PRIVATE_KEY) {
    logger.error('❌ Google Sheets credentials not configured');
    logger.info('Please set GOOGLE_SERVICE_ACCOUNT_EMAIL and GOOGLE_PRIVATE_KEY in .env');
    process.exit(1);
  }
  
  if (!env.SHEET_CONFIG_ID && !env.SHEET_IDDQD_ID) {
    logger.error('❌ No sheet IDs configured');
    logger.info('Please set SHEET_CONFIG_ID or SHEET_IDDQD_ID in .env');
    process.exit(1);
  }
  
  try {
    const { readSheetRange } = await import('../src/utils/sheets.js');
    
    const testSheetId = env.SHEET_CONFIG_ID || env.SHEET_IDDQD_ID;
    logger.info(`Testing with sheet ID: ${testSheetId}`);
    
    // Try to read a small range
    const data = await readSheetRange(testSheetId!, 'A1:A1');
    
    logger.info('✅ Successfully connected to Google Sheets');
    logger.info(`Read ${data.length} row(s)`);
    
    process.exit(0);
  } catch (error) {
    logger.error({ error }, '❌ Failed to connect to Google Sheets');
    process.exit(1);
  }
}

testSheets();
