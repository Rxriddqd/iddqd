/**
 * Command registry for dynamic command discovery and loading
 */

import { fileURLToPath, pathToFileURL } from 'url';
import { dirname, join } from 'path';
import { readdir } from 'fs/promises';
import type { SlashCommandModule } from '../../types/Command.js';
import { logger } from '../core/logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Get the commands directory path
 */
function getCommandsRoot(): string {
  // In production (dist/), look for compiled .js files
  // In development, look for .ts files
  const isDist = __dirname.includes('/dist/');
  return join(__dirname, isDist ? './commands' : './commands');
}

/**
 * Recursively discover command files
 */
async function discoverCommandFiles(dir: string): Promise<string[]> {
  const files: string[] = [];
  
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    
    for (const entry of entries) {
      const fullPath = join(dir, entry.name);
      
      if (entry.isDirectory()) {
        const subFiles = await discoverCommandFiles(fullPath);
        files.push(...subFiles);
      } else if (entry.name === 'command.ts' || entry.name === 'command.js') {
        files.push(fullPath);
      }
    }
  } catch (error) {
    logger.warn({ error, dir }, 'Failed to read commands directory');
  }
  
  return files;
}

/**
 * Discover all slash command data for registration
 */
export async function discoverSlash(): Promise<any[]> {
  const commandsRoot = getCommandsRoot();
  const commandFiles = await discoverCommandFiles(commandsRoot);
  const commands: any[] = [];
  
  for (const file of commandFiles) {
    try {
      // Use file URL to support absolute Windows paths under ESM/tsx
      const module = await import(pathToFileURL(file).href);
      const command = module.default as SlashCommandModule;
      
      if (command.data) {
        commands.push(command.data.toJSON());
      }
    } catch (error) {
      logger.error({ error, file }, 'Failed to load command module');
    }
  }
  
  logger.info(`Discovered ${commands.length} slash commands`);
  return commands;
}

/**
 * Load all slash command modules into a map
 */
export async function loadSlashMap(): Promise<Map<string, SlashCommandModule>> {
  const commandsRoot = getCommandsRoot();
  const commandFiles = await discoverCommandFiles(commandsRoot);
  const commandMap = new Map<string, SlashCommandModule>();
  
  for (const file of commandFiles) {
    try {
      // Use file URL to support absolute Windows paths under ESM/tsx
      const module = await import(pathToFileURL(file).href);
      const command = module.default as SlashCommandModule;
      
      if (command.data && 'name' in command.data) {
        commandMap.set(command.data.name, command);
      }
    } catch (error) {
      logger.error({ error, file }, 'Failed to load command module');
    }
  }
  
  logger.info(`Loaded ${commandMap.size} slash command handlers`);
  return commandMap;
}
