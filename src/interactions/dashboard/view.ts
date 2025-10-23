/**
 * Dashboard view and rendering
 */

import type { Client, TextChannel } from 'discord.js';
import { baseV2, button, actionRow, separator } from '../../utils/v2.js';
import { ButtonStyle } from '../../../types/Componentsv2.js';
import type { V2MessagePayload } from '../../../types/Componentsv2.js';
import { DASHBOARD_CATEGORIES } from './registry.js';
import { renderMain } from './categories/main.js';
import { renderGames } from './categories/games.js';
import { renderSheets } from './categories/sheets.js';
import { renderRaiding } from './categories/raiding.js';
import { renderPanels } from './categories/panels.js';
import { logger } from '../../core/logger.js';

/**
 * Render a specific dashboard category
 */
export async function renderCategory(categoryId: string): Promise<V2MessagePayload> {
  const payload = baseV2();
  
  // Category navigation buttons
  const navButtons = DASHBOARD_CATEGORIES.map(cat =>
    button(
      cat.emoji ? `${cat.emoji} ${cat.label}` : cat.label,
      `dash:${cat.id}`,
      cat.id === categoryId ? ButtonStyle.PRIMARY : ButtonStyle.SECONDARY
    )
  );
  
  // Split into two rows (3 buttons each)
  payload.components = [
    actionRow(navButtons.slice(0, 3)),
    actionRow([
      ...navButtons.slice(3),
      button('🔄 Refresh', 'dash:refresh', ButtonStyle.SUCCESS),
    ]),
    separator(),
  ];
  
  // Add category-specific content
  let categoryContent;
  switch (categoryId) {
    case 'main':
      categoryContent = renderMain();
      break;
    case 'games':
      categoryContent = renderGames();
      break;
    case 'sheets':
      categoryContent = renderSheets();
      break;
    case 'raiding':
      categoryContent = renderRaiding();
      break;
    case 'panels':
      categoryContent = renderPanels();
      break;
    default:
      categoryContent = renderMain();
  }
  
  payload.components.push(...categoryContent);
  
  return payload;
}

/**
 * Refresh the dashboard in a specific channel
 */
export async function refreshDashboard(
  client: Client,
  channelId: string
): Promise<void> {
  try {
    const channel = await client.channels.fetch(channelId);
    
    if (!channel || !channel.isTextBased()) {
      logger.warn({ channelId }, 'Dashboard channel not found or not text-based');
      return;
    }
    
    const textChannel = channel as TextChannel;
    
    // Fetch recent messages to find existing dashboard
    const messages = await textChannel.messages.fetch({ limit: 10 });
    const dashboardMessage = messages.find(msg =>
      msg.author.id === client.user?.id &&
      msg.components.length > 0
    );
    
    const payload = await renderCategory('main');
    
    if (dashboardMessage) {
      // Update existing dashboard
      await dashboardMessage.edit(payload as any);
      logger.info({ channelId, messageId: dashboardMessage.id }, 'Dashboard updated');
    } else {
      // Send new dashboard
      await textChannel.send(payload as any);
      logger.info({ channelId }, 'Dashboard created');
    }
  } catch (error) {
    logger.error({ error, channelId }, 'Failed to refresh dashboard');
    throw error;
  }
}
