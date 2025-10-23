/**
 * List all registered slash commands
 */

import 'dotenv/config';
import { REST, Routes } from 'discord.js';
import { env } from '../src/config/env.js';
import { logger } from '../src/core/logger.js';

async function listCommands() {
  try {
    logger.info('Fetching registered commands...');
    
    const rest = new REST().setToken(env.DISCORD_TOKEN);
    
    let commands: any[];
    
    if (env.DISCORD_GUILD_ID) {
      // List guild commands
      commands = await rest.get(
        Routes.applicationGuildCommands(env.DISCORD_CLIENT_ID, env.DISCORD_GUILD_ID)
      ) as any[];
      logger.info(`📝 Guild Commands (${commands.length}):`);
    } else {
      // List global commands
      commands = await rest.get(
        Routes.applicationCommands(env.DISCORD_CLIENT_ID)
      ) as any[];
      logger.info(`📝 Global Commands (${commands.length}):`);
    }
    
    if (commands.length === 0) {
      logger.info('No commands registered.');
    } else {
      commands.forEach(cmd => {
        logger.info(`  • /${cmd.name} - ${cmd.description}`);
      });
    }
  } catch (error) {
    logger.error({ error }, 'Failed to list commands');
    process.exit(1);
  }
}

listCommands();
