/**
 * Persistent disk utilities tests
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { writeDisk, readDisk, existsDisk, deleteDisk, writeJSON, readJSON, appendDisk, getDiskPath } from '../disk.js';
import { promises as fs } from 'fs';
import path from 'path';
import { tmpdir } from 'os';

const TEST_DIR = path.join(tmpdir(), 'iddqd-disk-tests');

describe('Persistent Disk', () => {
  beforeAll(async () => {
    // Use /tmp for tests instead of actual persistent disk path
    process.env.PERSISTENT_DISK_PATH = TEST_DIR;
    // Create test directory
    await fs.mkdir(TEST_DIR, { recursive: true });
  });

  afterAll(async () => {
    // Clean up test directory
    try {
      await fs.rm(TEST_DIR, { recursive: true, force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  it('should get correct disk path', () => {
    const relativePath = 'test/file.txt';
    const fullPath = getDiskPath(relativePath);
    expect(fullPath).toBe(path.join(TEST_DIR, relativePath));
  });

  it('should write and read a file', async () => {
    const relativePath = 'test/write-read.txt';
    const content = 'Hello, World!';
    
    const writeResult = await writeDisk(relativePath, content);
    expect(writeResult).toBe(true);
    
    const readResult = await readDisk(relativePath);
    expect(readResult).toBe(content);
    
    // Cleanup
    await deleteDisk(relativePath);
  });

  it('should check if file exists', async () => {
    const relativePath = 'test/exists.txt';
    const content = 'exists test';
    
    const existsBefore = await existsDisk(relativePath);
    expect(existsBefore).toBe(false);
    
    await writeDisk(relativePath, content);
    
    const existsAfter = await existsDisk(relativePath);
    expect(existsAfter).toBe(true);
    
    // Cleanup
    await deleteDisk(relativePath);
  });

  it('should delete a file', async () => {
    const relativePath = 'test/delete.txt';
    const content = 'delete test';
    
    await writeDisk(relativePath, content);
    
    const deleteResult = await deleteDisk(relativePath);
    expect(deleteResult).toBe(true);
    
    const exists = await existsDisk(relativePath);
    expect(exists).toBe(false);
  });

  it('should write and read JSON', async () => {
    const relativePath = 'test/json-test.json';
    const data = { name: 'test', value: 123, nested: { key: 'value' } };
    
    const writeResult = await writeJSON(relativePath, data);
    expect(writeResult).toBe(true);
    
    const readResult = await readJSON(relativePath);
    expect(readResult).toEqual(data);
    
    // Cleanup
    await deleteDisk(relativePath);
  });

  it('should append to a file', async () => {
    const relativePath = 'test/append.txt';
    
    const append1 = await appendDisk(relativePath, 'Line 1\n');
    expect(append1).toBe(true);
    
    const append2 = await appendDisk(relativePath, 'Line 2\n');
    expect(append2).toBe(true);
    
    const content = await readDisk(relativePath);
    expect(content).toBe('Line 1\nLine 2\n');
    
    // Cleanup
    await deleteDisk(relativePath);
  });

  it('should return null for non-existent file', async () => {
    const relativePath = 'test/non-existent.txt';
    const content = await readDisk(relativePath);
    expect(content).toBeNull();
  });

  it('should create nested directories automatically', async () => {
    const relativePath = 'test/deep/nested/path/file.txt';
    const content = 'nested file';
    
    const writeResult = await writeDisk(relativePath, content);
    expect(writeResult).toBe(true);
    
    const readResult = await readDisk(relativePath);
    expect(readResult).toBe(content);
    
    // Cleanup
    await deleteDisk(relativePath);
  });
});
