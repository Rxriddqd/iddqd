/**
 * Refresh summon panel manually
 */

import 'dotenv/config';
import { Client, GatewayIntentBits } from 'discord.js';
import { env } from '../src/config/env.js';
import { logger } from '../src/core/logger.js';

async function refreshSummonPanel() {
  if (!env.SUMMON_PANEL_CHANNEL_ID) {
    logger.error('SUMMON_PANEL_CHANNEL_ID not configured');
    process.exit(1);
  }
  
  const client = new Client({
    intents: [GatewayIntentBits.Guilds],
  });
  
  try {
    logger.info('Logging in...');
    await client.login(env.DISCORD_TOKEN);
    
    logger.info('Fetching summon panel channel...');
    const channel = await client.channels.fetch(env.SUMMON_PANEL_CHANNEL_ID);
    
    if (!channel?.isTextBased()) {
      throw new Error('Summon panel channel not found or not text-based');
    }
    
    logger.info('✅ Summon panel would be refreshed here');
    logger.info('ℹ️  Summon panel feature implementation pending');
    
    await client.destroy();
    process.exit(0);
  } catch (error) {
    logger.error({ error }, 'Failed to refresh summon panel');
    await client.destroy();
    process.exit(1);
  }
}

refreshSummonPanel();
