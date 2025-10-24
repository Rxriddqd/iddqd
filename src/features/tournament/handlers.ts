/**
 * Tournament button and modal interaction handlers
 */

import type { ButtonInteraction, ModalSubmitInteraction } from 'discord.js';
import { ModalBuilder, TextInputBuilder, TextInputStyle, ActionRowBuilder } from 'discord.js';
import { logger } from '../../core/logger.js';
import { isAdmin } from '../../interactions/middleware.js';
import {
  createTournament,
  getTournament,
  processUserRoll,
  calculateStats,
  getLeaderboard,
  endRound,
} from './game.js';
import {
  renderTournamentMessage,
  renderTournamentSetup,
  renderTournamentList,
  renderUserStats,
} from './ui.js';
import { listActiveTournaments, getUserRoll } from './storage.js';

/**
 * Handle tournament button interactions
 */
export async function handleTournamentButton(interaction: ButtonInteraction): Promise<void> {
  const { customId } = interaction;
  const parts = customId.split(':');
  const action = parts[1];
  
  try {
    switch (action) {
      case 'setup':
        await handleSetup(interaction);
        break;
      case 'list':
      case 'listrefresh':
        await handleList(interaction);
        break;
      case 'create':
        await handleCreateModal(interaction);
        break;
      case 'roll':
        await handleRoll(interaction, parts[2]);
        break;
      case 'stats':
        await handleStats(interaction, parts[2]);
        break;
      case 'refresh':
        await handleRefresh(interaction, parts[2]);
        break;
      case 'view':
        await handleView(interaction, parts[2]);
        break;
      case 'endround':
        await handleEndRound(interaction, parts[2]);
        break;
      default:
        logger.warn({ customId }, 'Unknown tournament action');
        await interaction.reply({
          content: '❌ Unknown action.',
          flags: 64,
        });
    }
  } catch (error) {
    logger.error({ error, customId }, 'Tournament handler error');
    throw error;
  }
}

/**
 * Handle setup button
 */
async function handleSetup(interaction: ButtonInteraction): Promise<void> {
  if (!isAdmin(interaction.member)) {
    await interaction.reply({
      content: '❌ Only administrators can access tournament setup.',
      flags: 64,
    });
    return;
  }
  
  const payload = renderTournamentSetup();
  await interaction.reply({ ...payload, flags: 64 } as any);
}

/**
 * Handle list tournaments
 */
async function handleList(interaction: ButtonInteraction): Promise<void> {
  const tournaments = await listActiveTournaments();
  const payload = renderTournamentList(tournaments);
  
  if (interaction.customId === 'tournament:listrefresh') {
    await interaction.update(payload as any);
  } else {
    await interaction.reply({ ...payload, flags: 64 } as any);
  }
}

/**
 * Handle create tournament modal
 */
async function handleCreateModal(interaction: ButtonInteraction): Promise<void> {
  if (!isAdmin(interaction.member)) {
    await interaction.reply({
      content: '❌ Only administrators can create tournaments.',
      flags: 64,
    });
    return;
  }
  
  const modal = new ModalBuilder()
    .setCustomId('tournament:create:modal')
    .setTitle('Create Tournament');
  
  const nameInput = new TextInputBuilder()
    .setCustomId('name')
    .setLabel('Tournament Name')
    .setStyle(TextInputStyle.Short)
    .setRequired(true)
    .setMaxLength(100)
    .setPlaceholder('e.g., Weekly Roll Championship');
  
  const maxRollInput = new TextInputBuilder()
    .setCustomId('maxRoll')
    .setLabel('Maximum Roll Number')
    .setStyle(TextInputStyle.Short)
    .setRequired(true)
    .setPlaceholder('e.g., 100')
    .setValue('100');
  
  const rollLimitInput = new TextInputBuilder()
    .setCustomId('rollLimit')
    .setLabel('Roll Limit per Player')
    .setStyle(TextInputStyle.Short)
    .setRequired(true)
    .setPlaceholder('e.g., 3')
    .setValue('3');
  
  const deadlineInput = new TextInputBuilder()
    .setCustomId('deadline')
    .setLabel('Deadline (hours from now)')
    .setStyle(TextInputStyle.Short)
    .setRequired(true)
    .setPlaceholder('e.g., 24')
    .setValue('24');
  
  modal.addComponents(
    new ActionRowBuilder<TextInputBuilder>().addComponents(nameInput),
    new ActionRowBuilder<TextInputBuilder>().addComponents(maxRollInput),
    new ActionRowBuilder<TextInputBuilder>().addComponents(rollLimitInput),
    new ActionRowBuilder<TextInputBuilder>().addComponents(deadlineInput)
  );
  
  await interaction.showModal(modal);
}

/**
 * Handle user roll
 */
async function handleRoll(interaction: ButtonInteraction, tournamentId: string): Promise<void> {
  const result = await processUserRoll(
    tournamentId,
    interaction.user.id,
    interaction.user.username
  );
  
  if (!result.success) {
    await interaction.reply({
      content: `❌ ${result.message}`,
      flags: 64,
    });
    return;
  }
  
  await interaction.reply({
    content: `🎲 ${result.message}`,
    flags: 64,
  });
  
  // Refresh the tournament message
  try {
    const config = await getTournament(tournamentId);
    if (config) {
      const stats = await calculateStats(tournamentId);
      const leaderboard = await getLeaderboard(tournamentId);
      const payload = renderTournamentMessage(config, leaderboard, stats);
      await interaction.message.edit(payload as any);
    }
  } catch (error) {
    logger.error({ error, tournamentId }, 'Failed to refresh tournament message after roll');
  }
}

/**
 * Handle user stats
 */
async function handleStats(interaction: ButtonInteraction, tournamentId: string): Promise<void> {
  const config = await getTournament(tournamentId);
  if (!config) {
    await interaction.reply({
      content: '❌ Tournament not found.',
      flags: 64,
    });
    return;
  }
  
  const userRoll = await getUserRoll(tournamentId, interaction.user.id);
  const leaderboard = await getLeaderboard(tournamentId, 100);
  const rank = leaderboard.findIndex(r => r.userId === interaction.user.id) + 1;
  
  const statsMessage = renderUserStats(config, userRoll, rank || leaderboard.length + 1);
  
  await interaction.reply({
    content: statsMessage,
    flags: 64,
  });
}

/**
 * Handle refresh tournament
 */
async function handleRefresh(interaction: ButtonInteraction, tournamentId: string): Promise<void> {
  const config = await getTournament(tournamentId);
  if (!config) {
    await interaction.reply({
      content: '❌ Tournament not found.',
      flags: 64,
    });
    return;
  }
  
  const stats = await calculateStats(tournamentId);
  const leaderboard = await getLeaderboard(tournamentId);
  const payload = renderTournamentMessage(config, leaderboard, stats);
  
  await interaction.update(payload as any);
}

/**
 * Handle view tournament
 */
async function handleView(interaction: ButtonInteraction, tournamentId: string): Promise<void> {
  const config = await getTournament(tournamentId);
  if (!config) {
    await interaction.reply({
      content: '❌ Tournament not found.',
      flags: 64,
    });
    return;
  }
  
  const stats = await calculateStats(tournamentId);
  const leaderboard = await getLeaderboard(tournamentId);
  const payload = renderTournamentMessage(config, leaderboard, stats);
  
  await interaction.reply({ ...payload, flags: 64 } as any);
}

/**
 * Handle end round
 */
async function handleEndRound(interaction: ButtonInteraction, tournamentId: string): Promise<void> {
  if (!isAdmin(interaction.member)) {
    await interaction.reply({
      content: '❌ Only administrators can end tournament rounds.',
      flags: 64,
    });
    return;
  }
  
  await interaction.deferReply({ flags: 64 });
  
  // Use default elimination percentage (50%)
  const result = await endRound(tournamentId);
  
  if (!result.success) {
    await interaction.editReply({
      content: `❌ ${result.message}`,
    });
    return;
  }
  
  await interaction.editReply({
    content: `✅ ${result.message}\n\nEliminated players: ${result.eliminated?.length || 0}`,
  });
}

/**
 * Handle tournament creation modal submit
 */
export async function handleTournamentModalSubmit(interaction: ModalSubmitInteraction): Promise<void> {
  const name = interaction.fields.getTextInputValue('name');
  const maxRoll = parseInt(interaction.fields.getTextInputValue('maxRoll'), 10);
  const rollLimit = parseInt(interaction.fields.getTextInputValue('rollLimit'), 10);
  const deadlineHours = parseInt(interaction.fields.getTextInputValue('deadline'), 10);
  
  // Validate inputs
  if (isNaN(maxRoll) || maxRoll < 10 || maxRoll > 10000) {
    await interaction.reply({
      content: '❌ Maximum roll must be between 10 and 10000.',
      flags: 64,
    });
    return;
  }
  
  if (isNaN(rollLimit) || rollLimit < 1 || rollLimit > 10) {
    await interaction.reply({
      content: '❌ Roll limit must be between 1 and 10.',
      flags: 64,
    });
    return;
  }
  
  if (isNaN(deadlineHours) || deadlineHours < 1 || deadlineHours > 168) {
    await interaction.reply({
      content: '❌ Deadline must be between 1 and 168 hours.',
      flags: 64,
    });
    return;
  }
  
  await interaction.deferReply({ flags: 64 });
  
  try {
    const channelId = interaction.channelId;
    if (!channelId) {
      await interaction.editReply({
        content: '❌ Could not determine channel ID.',
      });
      return;
    }
    
    const config = await createTournament(
      name,
      maxRoll,
      rollLimit,
      deadlineHours,
      channelId
    );
    
    const stats = await calculateStats(config.id);
    const leaderboard = await getLeaderboard(config.id);
    const payload = renderTournamentMessage(config, leaderboard, stats);
    
    // Send tournament message to channel
    if (interaction.channel && 'send' in interaction.channel) {
      await interaction.channel.send(payload as any);
    }
    
    await interaction.editReply({
      content: `✅ Tournament **${name}** created successfully!\n\nTournament ID: \`${config.id}\``,
    });
    
    logger.info({ tournamentId: config.id, name }, 'Tournament created via modal');
  } catch (error) {
    logger.error({ error }, 'Failed to create tournament');
    await interaction.editReply({
      content: '❌ Failed to create tournament. Please try again.',
    });
  }
}
