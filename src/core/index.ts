/**
 * Core module exports
 * 
 * Re-exports commonly used core functionality for easier imports
 */

export { logger } from './logger.js';
export { buildClient } from './client.js';
export * from './redis.js';
export * from './disk.js';

import type { TextChannel } from 'discord.js';
import type { V2MessagePayload } from '../../types/Componentsv2.js';
import { logger } from './logger.js';

/**
 * Safely send a Components V2 message to a channel
 */
export async function safeSendV2(
  channel: TextChannel,
  payload: V2MessagePayload
): Promise<void> {
  try {
    await channel.send(payload as any);
  } catch (error) {
    logger.error({ error, channelId: channel.id }, 'Failed to send V2 message');
    throw error;
  }
}

/**
 * Safely edit a message with Components V2 payload
 */
export async function safeEditV2(
  channel: TextChannel,
  messageId: string,
  payload: V2MessagePayload
): Promise<void> {
  try {
    const message = await channel.messages.fetch(messageId);
    await message.edit(payload as any);
  } catch (error) {
    logger.error({ error, channelId: channel.id, messageId }, 'Failed to edit V2 message');
    throw error;
  }
}
