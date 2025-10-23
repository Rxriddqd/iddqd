/**
 * Register slash commands with Discord API
 */

import 'dotenv/config';
import { REST, Routes } from 'discord.js';
import { env } from '../src/config/env.js';
import { discoverSlash } from '../src/interactions/commandRegistry.js';
import { logger } from '../src/core/logger.js';

async function registerCommands() {
  try {
    logger.info('Starting command registration...');
    
    const commands = await discoverSlash();
    const rest = new REST().setToken(env.DISCORD_TOKEN);
    
    if (env.DISCORD_GUILD_ID) {
      // Register guild commands (instant)
      logger.info(`Registering ${commands.length} guild commands...`);
      await rest.put(
        Routes.applicationGuildCommands(env.DISCORD_CLIENT_ID, env.DISCORD_GUILD_ID),
        { body: commands }
      );
      logger.info('✅ Guild commands registered successfully');
    } else {
      // Register global commands (takes up to 1 hour to propagate)
      logger.info(`Registering ${commands.length} global commands...`);
      await rest.put(
        Routes.applicationCommands(env.DISCORD_CLIENT_ID),
        { body: commands }
      );
      logger.info('✅ Global commands registered successfully (may take up to 1 hour to propagate)');
    }
  } catch (error) {
    logger.error({ error }, 'Failed to register commands');
    process.exit(1);
  }
}

registerCommands();
