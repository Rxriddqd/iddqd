/**
 * Type guard utilities
 */

import type { GuildMember, User } from 'discord.js';

/**
 * Check if a value is defined (not null or undefined)
 */
export function isDefined<T>(value: T | null | undefined): value is T {
  return value !== null && value !== undefined;
}

/**
 * Check if a value is a GuildMember
 */
export function isGuildMember(value: GuildMember | User | null): value is GuildMember {
  return value !== null && 'permissions' in value;
}

/**
 * Assert that a value is defined, throw if not
 */
export function assertDefined<T>(
  value: T | null | undefined,
  message = 'Value must be defined'
): asserts value is T {
  if (!isDefined(value)) {
    throw new Error(message);
  }
}
