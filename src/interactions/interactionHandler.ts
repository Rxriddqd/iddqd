/**
 * Central interaction handler and router
 */

import type {
  Interaction,
  ChatInputCommandInteraction,
  AutocompleteInteraction,
  ButtonInteraction,
} from 'discord.js';
import { loadSlashMap } from './commandRegistry.js';
import { logger } from '../core/logger.js';
import { rateLimiter } from '../utils/rate-limit.js';
import { isAdmin } from './middleware.js';
import type { SlashCommandModule } from '../../types/Command.js';

// Lazy-load command map
let commandMap: Map<string, SlashCommandModule> | null = null;

/**
 * Warm up the command map
 */
async function warmCommandMap() {
  if (!commandMap) {
    commandMap = await loadSlashMap();
  }
  return commandMap;
}

/**
 * Check rate limit for user interaction
 */
function checkRateLimit(interaction: Interaction): boolean {
  if (!interaction.user) return false;
  
  const action = 'customId' in interaction && interaction.customId 
    ? interaction.customId 
    : 'command' in interaction && interaction.command?.name
    ? interaction.command.name
    : 'default';
  
  if (rateLimiter.isRateLimited(interaction.user.id, action)) {
    const resetTime = Math.ceil(rateLimiter.getResetTime(interaction.user.id, action) / 1000);
    
    if (interaction.isRepliable()) {
      interaction.reply({
        content: `⏱️ You're being rate limited. Please wait ${resetTime} seconds.`,
        flags: 64, // EPHEMERAL
      }).catch(() => {});
    }
    
    return false;
  }
  
  return true;
}

/**
 * Handle chat input commands
 */
async function handleChatInput(interaction: ChatInputCommandInteraction) {
  const commands = await warmCommandMap();
  const command = commands.get(interaction.commandName);
  
  if (!command) {
    logger.warn({ commandName: interaction.commandName }, 'Unknown command');
    await interaction.reply({
      content: '❌ Command not found.',
      flags: 64, // EPHEMERAL
    });
    return;
  }
  
  try {
    await command.execute(interaction);
  } catch (error) {
    logger.error({ error, commandName: interaction.commandName }, 'Command execution failed');
    
    const errorMessage = '❌ An error occurred while executing this command.';
    
    if (interaction.replied || interaction.deferred) {
      await interaction.followUp({ content: errorMessage, flags: 64 });
    } else {
      await interaction.reply({ content: errorMessage, flags: 64 });
    }
  }
}

/**
 * Handle autocomplete interactions
 */
async function handleAutocomplete(interaction: AutocompleteInteraction) {
  const commands = await warmCommandMap();
  const command = commands.get(interaction.commandName);
  
  if (!command || !command.autocomplete) {
    return;
  }
  
  try {
    await command.autocomplete(interaction);
  } catch (error) {
    logger.error({ error, commandName: interaction.commandName }, 'Autocomplete failed');
  }
}

/**
 * Handle button interactions
 */
async function handleButton(interaction: ButtonInteraction) {
  const { customId } = interaction;
  
  // Dashboard category switching
  if (customId.startsWith('dash:')) {
    const category = customId.split(':')[1];
    
    if (!isAdmin(interaction.member)) {
      await interaction.reply({
        content: '❌ You need Administrator permissions to use the dashboard.',
        flags: 64,
      });
      return;
    }
    
    try {
      const { renderCategory } = await import('./dashboard/view.js');
      const payload = await renderCategory(category);
      await interaction.update(payload as any);
    } catch (error) {
      logger.error({ error, category }, 'Failed to render dashboard category');
      await interaction.reply({
        content: '❌ Failed to load dashboard category.',
        flags: 64,
      });
    }
    return;
  }
  
  // Dashboard refresh
  if (customId === 'dash:refresh') {
    if (!isAdmin(interaction.member)) {
      await interaction.reply({
        content: '❌ You need Administrator permissions to refresh the dashboard.',
        flags: 64,
      });
      return;
    }
    
    try {
      const { renderCategory } = await import('./dashboard/view.js');
      const payload = await renderCategory('main');
      await interaction.update(payload as any);
      await interaction.followUp({
        content: '✅ Dashboard refreshed!',
        flags: 64,
      });
    } catch (error) {
      logger.error({ error }, 'Failed to refresh dashboard');
    }
    return;
  }
  
  logger.warn({ customId }, 'Unhandled button interaction');
}

/**
 * Main interaction handler
 */
export async function onInteraction(interaction: Interaction) {
  // Check rate limit
  if (!checkRateLimit(interaction)) {
    return;
  }
  
  try {
    if (interaction.isChatInputCommand()) {
      await handleChatInput(interaction);
    } else if (interaction.isAutocomplete()) {
      await handleAutocomplete(interaction);
    } else if (interaction.isButton()) {
      await handleButton(interaction);
    }
  } catch (error) {
    logger.error({ error }, 'Interaction handler error');
  }
}

/**
 * Safe reply helper
 */
export async function safeReply(
  interaction: ChatInputCommandInteraction | ButtonInteraction,
  content: string,
  ephemeral = true
) {
  try {
    if (interaction.replied || interaction.deferred) {
      await interaction.followUp({ content, flags: ephemeral ? 64 : 0 });
    } else {
      await interaction.reply({ content, flags: ephemeral ? 64 : 0 });
    }
  } catch (error) {
    logger.error({ error }, 'Failed to send reply');
  }
}
