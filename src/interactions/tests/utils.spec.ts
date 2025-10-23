/**
 * Tests for utility functions
 */

import { describe, it, expect } from 'vitest';
import { isDefined, isGuildMember } from '../../utils/guards.js';
import { formatDuration, formatRelativeTime } from '../../utils/time.js';
import { hexToRgb } from '../../utils/v2.js';

describe('Guards', () => {
  it('should check if value is defined', () => {
    expect(isDefined('hello')).toBe(true);
    expect(isDefined(0)).toBe(true);
    expect(isDefined(false)).toBe(true);
    expect(isDefined(null)).toBe(false);
    expect(isDefined(undefined)).toBe(false);
  });

  it('should check if value is a GuildMember', () => {
    const guildMember = { permissions: {} };
    const user = { id: '123' };
    
    expect(isGuildMember(guildMember as any)).toBe(true);
    expect(isGuildMember(user as any)).toBe(false);
    expect(isGuildMember(null)).toBe(false);
  });
});

describe('Time utilities', () => {
  it('should format duration correctly', () => {
    expect(formatDuration(1000)).toBe('1s');
    expect(formatDuration(60000)).toBe('1m 0s');
    expect(formatDuration(3600000)).toBe('1h 0m');
    expect(formatDuration(86400000)).toBe('1d 0h');
  });

  it('should format relative time', () => {
    const now = Date.now();
    const secondsAgo = now - 5000;
    const minutesAgo = now - 120000;
    
    expect(formatRelativeTime(secondsAgo)).toContain('second');
    expect(formatRelativeTime(minutesAgo)).toContain('minute');
  });
});

describe('V2 utilities', () => {
  it('should convert hex to RGB', () => {
    expect(hexToRgb('#FF0000')).toBe(0xFF0000);
    expect(hexToRgb('#00FF00')).toBe(0x00FF00);
    expect(hexToRgb('#0000FF')).toBe(0x0000FF);
    expect(hexToRgb('FFFFFF')).toBe(0xFFFFFF);
  });
});
