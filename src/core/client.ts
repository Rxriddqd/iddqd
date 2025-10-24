import { Client, Events, GatewayIntentBits, Partials } from 'discord.js';
import { logger } from './logger.js';
import { env } from '../config/env.js';
import { onInteraction } from '../interactions/interactionHandler.js';

/**
 * Build and configure the Discord client
 */
export function buildClient(): Client {
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.GuildMembers,
      GatewayIntentBits.MessageContent,
    ],
    partials: [
      Partials.Message,
      Partials.Channel,
      Partials.User,
      Partials.GuildMember,
    ],
  });

  // Register interaction handler
  client.on(Events.InteractionCreate, onInteraction);

  // Register message handler for text commands
  client.on(Events.MessageCreate, async (message) => {
    if (message.author.bot) return;
    
    // Handle !refresh-dashboard command
    if (message.content === '!refresh-dashboard') {
      const member = message.member;
      if (!member) return;
      
      // Check if user is admin
      if (!member.permissions.has('Administrator')) {
        await message.reply('❌ You need Administrator permissions to use this command.');
        return;
      }
      
      // Import dashboard refresh logic
      try {
        const { refreshDashboard } = await import('../interactions/dashboard/view.js');
        await refreshDashboard(message.client, message.channelId);
        await message.reply('✅ Dashboard refreshed successfully!');
      } catch (error) {
        logger.error({ error }, 'Failed to refresh dashboard');
        await message.reply('❌ Failed to refresh dashboard. Check logs for details.');
      }
    }
  });

  // Ready event - first time only
  let readyFired = false;
  client.once(Events.ClientReady, async (c) => {
    if (readyFired) return;
    readyFired = true;
    
    logger.info(`✅ Logged in as ${c.user.tag}`);

    // Initialize Redis if URL is configured
    if (env.REDIS_URL || env.REDIS_HOST) {
      try {
        const { initRedis } = await import('../config/redis.js');
        await initRedis();
        logger.info('✅ Redis initialized');
      } catch (error) {
        logger.warn({ error }, 'Redis initialization failed - tournament feature will be unavailable');
      }
    }

    // Initialize dashboard if configured
    if (env.DASHBOARD_CHANNEL_ID) {
      try {
        const { refreshDashboard } = await import('../interactions/dashboard/view.js');
        await refreshDashboard(c, env.DASHBOARD_CHANNEL_ID);
        logger.info('✅ Dashboard initialized');
      } catch (error) {
        logger.error({ error }, 'Failed to initialize dashboard');
      }
    }

    // Initialize other features based on environment configuration
    if (env.SUMMON_PANEL_CHANNEL_ID) {
      logger.info('ℹ️  Summon panel configuration detected');
    }
    
    if (env.TIER3_CHANNEL_ID) {
      logger.info('ℹ️  Tier3 configuration detected');
    }
    
    if (env.FLASKGAMBA_CHANNEL_ID) {
      logger.info('ℹ️  FlaskGamba configuration detected');
    }
    
    if (env.TOURNAMENT_CHANNEL_ID) {
      logger.info('ℹ️  Tournament configuration detected');
    }

    logger.info('🚀 Bot is ready!');
  });

  return client;
}
