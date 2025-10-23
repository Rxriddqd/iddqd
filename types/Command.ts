import type {
  AutocompleteInteraction,
  ChatInputCommandInteraction,
  SlashCommandBuilder,
  SlashCommandOptionsOnlyBuilder,
  SlashCommandSubcommandsOnlyBuilder,
} from 'discord.js';

/**
 * Base structure for a slash command module
 */
export interface SlashCommandModule {
  /**
   * Command data for registration with Discord API
   */
  data:
    | SlashCommandBuilder
    | SlashCommandOptionsOnlyBuilder
    | SlashCommandSubcommandsOnlyBuilder
    | Omit<SlashCommandBuilder, 'addSubcommand' | 'addSubcommandGroup'>;

  /**
   * Execute function called when the command is invoked
   */
  execute: (interaction: ChatInputCommandInteraction) => Promise<void>;

  /**
   * Optional autocomplete handler for command options
   */
  autocomplete?: (interaction: AutocompleteInteraction) => Promise<void>;
}
