/**
 * Tests for cache utility
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Cache } from '../../utils/cache.js';

describe('Cache', () => {
  let cache: Cache<string>;

  beforeEach(() => {
    cache = new Cache(1000); // 1 second TTL for tests
  });

  afterEach(() => {
    cache.destroy();
  });

  it('should store and retrieve values', () => {
    cache.set('key1', 'value1');
    expect(cache.get('key1')).toBe('value1');
  });

  it('should return undefined for missing keys', () => {
    expect(cache.get('nonexistent')).toBeUndefined();
  });

  it('should delete values', () => {
    cache.set('key1', 'value1');
    expect(cache.delete('key1')).toBe(true);
    expect(cache.get('key1')).toBeUndefined();
  });

  it('should clear all values', () => {
    cache.set('key1', 'value1');
    cache.set('key2', 'value2');
    cache.clear();
    expect(cache.get('key1')).toBeUndefined();
    expect(cache.get('key2')).toBeUndefined();
  });

  it('should expire values after TTL', async () => {
    cache.set('key1', 'value1', 100); // 100ms TTL
    expect(cache.get('key1')).toBe('value1');
    
    await new Promise(resolve => setTimeout(resolve, 150));
    expect(cache.get('key1')).toBeUndefined();
  });

  it('should compute and cache values', async () => {
    let callCount = 0;
    const computeFn = async () => {
      callCount++;
      return 'computed';
    };

    const value1 = await cache.getOrCompute('key1', computeFn);
    expect(value1).toBe('computed');
    expect(callCount).toBe(1);

    const value2 = await cache.getOrCompute('key1', computeFn);
    expect(value2).toBe('computed');
    expect(callCount).toBe(1); // Should not call again
  });
});
