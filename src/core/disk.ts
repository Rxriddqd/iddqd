/**
 * Persistent disk utilities for long-term data storage
 * 
 * Provides helpers for reading and writing to the persistent disk
 * mounted at the configured path (e.g., /data on Render)
 */

import { promises as fs } from 'fs';
import path from 'path';
import { logger } from './logger.js';

/**
 * Ensure directory exists, create if it doesn't
 */
async function ensureDir(dirPath: string): Promise<boolean> {
  try {
    await fs.mkdir(dirPath, { recursive: true });
    return true;
  } catch (error) {
    logger.error({ error, dirPath }, 'Failed to create directory');
    return false;
  }
}

/**
 * Get full path on persistent disk
 */
export function getDiskPath(relativePath: string): string {
  const diskPath = process.env.PERSISTENT_DISK_PATH || '/data';
  return path.join(diskPath, relativePath);
}

/**
 * Write data to persistent disk
 */
export async function writeDisk(
  relativePath: string,
  data: string
): Promise<boolean> {
  try {
    const fullPath = getDiskPath(relativePath);
    const dirPath = path.dirname(fullPath);
    
    // Ensure directory exists
    await ensureDir(dirPath);
    
    // Write file
    await fs.writeFile(fullPath, data, 'utf-8');
    logger.debug({ path: fullPath }, 'Data written to disk');
    return true;
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to write to disk');
    return false;
  }
}

/**
 * Read data from persistent disk
 */
export async function readDisk(
  relativePath: string
): Promise<string | null> {
  try {
    const fullPath = getDiskPath(relativePath);
    const data = await fs.readFile(fullPath, 'utf-8');
    logger.debug({ path: fullPath }, 'Data read from disk');
    return data;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      logger.debug({ relativePath }, 'File not found on disk');
    } else {
      logger.error({ error, relativePath }, 'Failed to read from disk');
    }
    return null;
  }
}

/**
 * Check if file exists on disk
 */
export async function existsDisk(relativePath: string): Promise<boolean> {
  try {
    const fullPath = getDiskPath(relativePath);
    await fs.access(fullPath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Delete file from disk
 */
export async function deleteDisk(relativePath: string): Promise<boolean> {
  try {
    const fullPath = getDiskPath(relativePath);
    await fs.unlink(fullPath);
    logger.debug({ path: fullPath }, 'File deleted from disk');
    return true;
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to delete from disk');
    return false;
  }
}

/**
 * List files in directory on disk
 */
export async function listDisk(
  relativePath: string = ''
): Promise<string[] | null> {
  try {
    const fullPath = getDiskPath(relativePath);
    const files = await fs.readdir(fullPath);
    return files;
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to list disk directory');
    return null;
  }
}

/**
 * Write JSON data to persistent disk
 */
export async function writeJSON<T>(
  relativePath: string,
  data: T
): Promise<boolean> {
  try {
    const jsonString = JSON.stringify(data, null, 2);
    return await writeDisk(relativePath, jsonString);
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to write JSON to disk');
    return false;
  }
}

/**
 * Read JSON data from persistent disk
 */
export async function readJSON<T>(
  relativePath: string
): Promise<T | null> {
  try {
    const data = await readDisk(relativePath);
    if (!data) {
      return null;
    }
    return JSON.parse(data) as T;
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to read JSON from disk');
    return null;
  }
}

/**
 * Append data to file on disk (for logs)
 */
export async function appendDisk(
  relativePath: string,
  data: string
): Promise<boolean> {
  try {
    const fullPath = getDiskPath(relativePath);
    const dirPath = path.dirname(fullPath);
    
    // Ensure directory exists
    await ensureDir(dirPath);
    
    // Append to file
    await fs.appendFile(fullPath, data, 'utf-8');
    logger.debug({ path: fullPath }, 'Data appended to disk');
    return true;
  } catch (error) {
    logger.error({ error, relativePath }, 'Failed to append to disk');
    return false;
  }
}
