/**
 * Tournament UI components and rendering
 */

import { baseV2, text, button, actionRow, separator, container } from '../../utils/v2.js';
import { ButtonStyle, type V2MessagePayload } from '../../../types/Componentsv2.js';
import type { TournamentConfig, UserRoll, TournamentStats } from '../../../types/Tournament.js';
import { TournamentStatus } from '../../../types/Tournament.js';

/**
 * Render tournament main message
 */
export function renderTournamentMessage(
  config: TournamentConfig,
  leaderboard: UserRoll[],
  stats: TournamentStats | null
): V2MessagePayload {
  const payload = baseV2();
  
  if (!payload.components) {
    payload.components = [];
  }
  
  // Tournament header
  payload.components.push(
    text(`# 🏆 ${config.name}`),
    text(`**Round ${config.currentRound}** • Status: ${getStatusEmoji(config.status)} ${config.status.toUpperCase()}`)
  );
  
  payload.components.push(separator());
  
  // Tournament info
  payload.components.push(
    text('## Tournament Info'),
    text(`🎲 Roll Range: 1-${config.maxRoll}`),
    text(`🔄 Roll Limit: ${config.rollLimit} per player`),
    text(`⏰ Deadline: <t:${Math.floor(config.deadline / 1000)}:R>`),
  );
  
  payload.components.push(separator());
  
  // Statistics
  if (stats) {
    payload.components.push(
      text('## Current Statistics'),
      text(`👥 Active Players: **${stats.activeParticipants}**`),
      text(`🎲 Total Rolls: **${stats.totalRolls}**`),
      text(`📊 Average Roll: **${stats.averageRoll}**`),
    );
    
    if (stats.highestRoll) {
      payload.components.push(
        text(`🔥 Highest Roll: **${stats.highestRoll.roll}** by ${stats.highestRoll.username}`)
      );
    }
    
    payload.components.push(separator());
  }
  
  // Leaderboard
  if (leaderboard.length > 0) {
    payload.components.push(text('## 🏅 Top 10 Leaderboard'));
    
    const leaderboardText = leaderboard
      .slice(0, 10)
      .map((roll, index) => {
        const medal = index === 0 ? '🥇' : index === 1 ? '🥈' : index === 2 ? '🥉' : `${index + 1}.`;
        return `${medal} **${roll.username}** - ${roll.roll} (${roll.rollsUsed}/${config.rollLimit} rolls)`;
      })
      .join('\n');
    
    payload.components.push(text(leaderboardText));
    payload.components.push(separator());
  }
  
  // Action buttons
  if (config.status === TournamentStatus.ACTIVE) {
    payload.components.push(
      actionRow([
        button('🎲 Roll', `tournament:roll:${config.id}`, ButtonStyle.PRIMARY),
        button('📊 My Stats', `tournament:stats:${config.id}`, ButtonStyle.SECONDARY),
        button('🔄 Refresh', `tournament:refresh:${config.id}`, ButtonStyle.SUCCESS),
      ])
    );
  } else if (config.status === TournamentStatus.COMPLETED) {
    payload.components.push(
      text('## 🎉 Tournament Complete!'),
      text(`Congratulations to the winner!`)
    );
  }
  
  return payload;
}

/**
 * Render user stats message
 */
export function renderUserStats(
  config: TournamentConfig,
  userRoll: UserRoll | null,
  rank: number
): string {
  if (!userRoll) {
    return `❌ You haven't rolled yet in **${config.name}**!\n\nRoll Range: 1-${config.maxRoll}\nRolls Remaining: ${config.rollLimit}`;
  }
  
  const rollsRemaining = config.rollLimit - userRoll.rollsUsed;
  
  return `## 📊 Your Tournament Stats\n\n` +
    `**Tournament:** ${config.name}\n` +
    `**Your Best Roll:** ${userRoll.roll}\n` +
    `**Current Rank:** #${rank}\n` +
    `**Rolls Used:** ${userRoll.rollsUsed}/${config.rollLimit}\n` +
    `**Rolls Remaining:** ${rollsRemaining}\n` +
    `**Last Roll:** <t:${Math.floor(userRoll.timestamp / 1000)}:R>`;
}

/**
 * Render tournament setup message for admins
 */
export function renderTournamentSetup(): V2MessagePayload {
  const payload = baseV2();
  
  if (!payload.components) {
    payload.components = [];
  }
  
  payload.components.push(
    text('# 🏆 Tournament Setup'),
    text('Use the button below to create a new tournament.'),
    separator(),
    text('## Tournament Features:'),
    text('• 🎲 Users can roll numbers within a specified range'),
    text('• 🔄 Limited number of rolls per player (keeps best roll)'),
    text('• ⏰ Time-limited rounds with deadlines'),
    text('• 🏅 Elimination rounds - bottom performers are removed'),
    text('• 📊 Real-time leaderboard and statistics'),
    text('• 🏆 Winner determined after multiple elimination rounds'),
    separator(),
    actionRow([
      button('➕ Create Tournament', 'tournament:create', ButtonStyle.SUCCESS),
      button('📋 List Tournaments', 'tournament:list', ButtonStyle.SECONDARY),
    ])
  );
  
  return payload;
}

/**
 * Render tournament list
 */
export function renderTournamentList(tournaments: TournamentConfig[]): V2MessagePayload {
  const payload = baseV2();
  
  if (!payload.components) {
    payload.components = [];
  }
  
  payload.components.push(
    text('# 📋 Active Tournaments'),
    separator()
  );
  
  if (tournaments.length === 0) {
    payload.components.push(
      text('No active tournaments found.'),
      text('Create a new tournament to get started!')
    );
  } else {
    for (const tournament of tournaments) {
      const statusEmoji = getStatusEmoji(tournament.status);
      const containerContent = [
        text(`## ${tournament.name}`),
        text(`${statusEmoji} **Status:** ${tournament.status.toUpperCase()}`),
        text(`🎲 Roll Range: 1-${tournament.maxRoll}`),
        text(`🔄 Roll Limit: ${tournament.rollLimit}`),
        text(`📅 Round: ${tournament.currentRound}`),
        text(`⏰ Deadline: <t:${Math.floor(tournament.deadline / 1000)}:R>`),
        separator(false, 1),
        actionRow([
          button('View', `tournament:view:${tournament.id}`, ButtonStyle.PRIMARY),
          button('End Round', `tournament:endround:${tournament.id}`, ButtonStyle.DANGER),
        ]),
      ];
      
      payload.components.push(container(containerContent, 0x5865F2));
      payload.components.push(separator(false, 1));
    }
  }
  
  payload.components.push(
    actionRow([
      button('➕ Create New', 'tournament:create', ButtonStyle.SUCCESS),
      button('🔄 Refresh', 'tournament:listrefresh', ButtonStyle.SECONDARY),
    ])
  );
  
  return payload;
}

/**
 * Get status emoji
 */
function getStatusEmoji(status: TournamentStatus): string {
  switch (status) {
    case TournamentStatus.SETUP:
      return '⚙️';
    case TournamentStatus.ACTIVE:
      return '🟢';
    case TournamentStatus.ROUND_ENDING:
      return '🟡';
    case TournamentStatus.COMPLETED:
      return '✅';
    case TournamentStatus.CANCELLED:
      return '❌';
    default:
      return '❔';
  }
}
