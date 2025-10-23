/**
 * Rate limiting utility
 * 
 * Provides in-memory rate limiting for user interactions
 */

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

export class RateLimiter {
  private limits = new Map<string, RateLimitEntry>();
  private cleanupInterval: NodeJS.Timeout;

  constructor(
    private maxRequests = 5,
    private windowMs = 10000 // 10 seconds
  ) {
    // Cleanup expired entries every minute
    this.cleanupInterval = setInterval(() => this.cleanup(), 60000);
  }

  /**
   * Check if a user has exceeded the rate limit
   */
  isRateLimited(userId: string, action = 'default'): boolean {
    const key = `${userId}:${action}`;
    const now = Date.now();
    const entry = this.limits.get(key);

    if (!entry || now > entry.resetAt) {
      // Reset or create new entry
      this.limits.set(key, {
        count: 1,
        resetAt: now + this.windowMs,
      });
      return false;
    }

    if (entry.count >= this.maxRequests) {
      return true;
    }

    entry.count++;
    return false;
  }

  /**
   * Get remaining requests for a user
   */
  getRemaining(userId: string, action = 'default'): number {
    const key = `${userId}:${action}`;
    const now = Date.now();
    const entry = this.limits.get(key);

    if (!entry || now > entry.resetAt) {
      return this.maxRequests;
    }

    return Math.max(0, this.maxRequests - entry.count);
  }

  /**
   * Get time until reset in milliseconds
   */
  getResetTime(userId: string, action = 'default'): number {
    const key = `${userId}:${action}`;
    const now = Date.now();
    const entry = this.limits.get(key);

    if (!entry || now > entry.resetAt) {
      return 0;
    }

    return entry.resetAt - now;
  }

  /**
   * Reset rate limit for a user
   */
  reset(userId: string, action = 'default'): void {
    const key = `${userId}:${action}`;
    this.limits.delete(key);
  }

  /**
   * Cleanup expired entries
   */
  private cleanup(): void {
    const now = Date.now();
    for (const [key, entry] of this.limits.entries()) {
      if (now > entry.resetAt) {
        this.limits.delete(key);
      }
    }
  }

  /**
   * Destroy the rate limiter and cleanup interval
   */
  destroy(): void {
    clearInterval(this.cleanupInterval);
    this.limits.clear();
  }
}

/**
 * Global rate limiter instance
 */
export const rateLimiter = new RateLimiter();
