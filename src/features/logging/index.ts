/**
 * Message logging feature
 * 
 * Example feature module for logging messages
 */

import type { Message } from 'discord.js';
import { logger } from '../../core/logger.js';

/**
 * Log a message event
 */
export function logMessage(message: Message): void {
  if (message.author.bot) return;
  
  logger.info({
    userId: message.author.id,
    username: message.author.username,
    channelId: message.channelId,
    guildId: message.guildId,
    content: message.content.substring(0, 100), // Truncate for privacy
  }, 'Message received');
}

/**
 * Log a message deletion
 */
export function logMessageDelete(message: Message): void {
  logger.info({
    messageId: message.id,
    userId: message.author?.id,
    channelId: message.channelId,
    guildId: message.guildId,
  }, 'Message deleted');
}

/**
 * Log a message edit
 */
export function logMessageEdit(oldMessage: Message, newMessage: Message): void {
  if (newMessage.author?.bot) return;
  
  logger.info({
    messageId: newMessage.id,
    userId: newMessage.author?.id,
    channelId: newMessage.channelId,
    oldContent: oldMessage.content?.substring(0, 100),
    newContent: newMessage.content.substring(0, 100),
  }, 'Message edited');
}
