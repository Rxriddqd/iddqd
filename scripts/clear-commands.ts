/**
 * Clear all registered slash commands
 */

import 'dotenv/config';
import { REST, Routes } from 'discord.js';
import { env } from '../src/config/env.js';
import { logger } from '../src/core/logger.js';

async function clearCommands() {
  try {
    logger.info('Starting command clear...');
    
    const rest = new REST().setToken(env.DISCORD_TOKEN);
    
    if (env.DISCORD_GUILD_ID) {
      // Clear guild commands
      logger.info('Clearing guild commands...');
      await rest.put(
        Routes.applicationGuildCommands(env.DISCORD_CLIENT_ID, env.DISCORD_GUILD_ID),
        { body: [] }
      );
      logger.info('✅ Guild commands cleared successfully');
    } else {
      // Clear global commands
      logger.info('Clearing global commands...');
      await rest.put(
        Routes.applicationCommands(env.DISCORD_CLIENT_ID),
        { body: [] }
      );
      logger.info('✅ Global commands cleared successfully');
    }
  } catch (error) {
    logger.error({ error }, 'Failed to clear commands');
    process.exit(1);
  }
}

clearCommands();
