/**
 * Middleware utilities for interaction handling
 */

import type { GuildMember, ChatInputCommandInteraction, ButtonInteraction } from 'discord.js';
import type { APIInteractionGuildMember } from 'discord-api-types/v10';

/**
 * Check if a member is an administrator
 */
export function isAdmin(
  member: GuildMember | APIInteractionGuildMember | null
): boolean {
  if (!member) return false;
  
  // Handle API member (from interactions)
  if ('permissions' in member && typeof member.permissions === 'string') {
    const permissions = BigInt(member.permissions);
    const ADMINISTRATOR = BigInt(0x8);
    return (permissions & ADMINISTRATOR) === ADMINISTRATOR;
  }
  
  // Handle GuildMember
  if ('permissions' in member && typeof member.permissions !== 'string') {
    return member.permissions.has('Administrator');
  }
  
  return false;
}

/**
 * Check if a member has a specific role
 */
export function hasRole(
  member: GuildMember | APIInteractionGuildMember | null,
  roleId: string
): boolean {
  if (!member) return false;
  
  // Handle both API member and GuildMember
  const roles = 'roles' in member 
    ? (Array.isArray(member.roles) ? member.roles : member.roles.cache.map(r => r.id))
    : [];
    
  return roles.includes(roleId);
}

/**
 * Require administrator permissions, reply with error if not authorized
 */
export async function requireAdmin(
  interaction: ChatInputCommandInteraction | ButtonInteraction
): Promise<boolean> {
  if (!interaction.member || !isAdmin(interaction.member)) {
    await interaction.reply({
      content: '❌ You need Administrator permissions to use this command.',
      flags: 64, // EPHEMERAL
    });
    return false;
  }
  
  return true;
}
