/**
 * Tests for rate limiter
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { RateLimiter } from '../../utils/rate-limit.js';

describe('RateLimiter', () => {
  let limiter: RateLimiter;

  beforeEach(() => {
    limiter = new RateLimiter(3, 1000); // 3 requests per second for tests
  });

  afterEach(() => {
    limiter.destroy();
  });

  it('should allow requests within limit', () => {
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
  });

  it('should block requests exceeding limit', () => {
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(true);
    expect(limiter.isRateLimited('user1')).toBe(true);
  });

  it('should track different users separately', () => {
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(true);

    expect(limiter.isRateLimited('user2')).toBe(false);
    expect(limiter.isRateLimited('user2')).toBe(false);
  });

  it('should track different actions separately', () => {
    expect(limiter.isRateLimited('user1', 'action1')).toBe(false);
    expect(limiter.isRateLimited('user1', 'action1')).toBe(false);
    expect(limiter.isRateLimited('user1', 'action1')).toBe(false);
    expect(limiter.isRateLimited('user1', 'action1')).toBe(true);

    expect(limiter.isRateLimited('user1', 'action2')).toBe(false);
  });

  it('should get remaining requests', () => {
    expect(limiter.getRemaining('user1')).toBe(3);
    limiter.isRateLimited('user1');
    expect(limiter.getRemaining('user1')).toBe(2);
    limiter.isRateLimited('user1');
    expect(limiter.getRemaining('user1')).toBe(1);
  });

  it('should reset rate limit', () => {
    limiter.isRateLimited('user1');
    limiter.isRateLimited('user1');
    limiter.isRateLimited('user1');
    expect(limiter.isRateLimited('user1')).toBe(true);

    limiter.reset('user1');
    expect(limiter.isRateLimited('user1')).toBe(false);
  });

  it('should reset after time window', async () => {
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(false);
    expect(limiter.isRateLimited('user1')).toBe(true);

    await new Promise(resolve => setTimeout(resolve, 1100));
    expect(limiter.isRateLimited('user1')).toBe(false);
  });
});
