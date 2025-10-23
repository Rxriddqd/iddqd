/**
 * Help command - Show available commands and features
 */

import { SlashCommandBuilder, EmbedBuilder } from 'discord.js';
import type { SlashCommandModule } from '../../../../types/Command.js';

const command: SlashCommandModule = {
  data: new SlashCommandBuilder()
    .setName('help')
    .setDescription('Show available commands and bot information'),

  async execute(interaction) {
    const embed = new EmbedBuilder()
      .setTitle('🤖 IDDQD Bot Help')
      .setDescription('A production-ready Discord bot with Components V2 support')
      .setColor(0x5865F2)
      .addFields(
        {
          name: '📝 Available Commands',
          value:
            '`/ping` - Check bot latency\n' +
            '`/help` - Show this help message',
        },
        {
          name: '⚙️ Features',
          value:
            '• Admin Dashboard with Components V2\n' +
            '• Rate limiting and RBAC\n' +
            '• Google Sheets integration\n' +
            '• Mini-games (FlaskGamba)\n' +
            '• Role and summon panels\n' +
            '• Raid signup management',
        },
        {
          name: '🔧 Admin Commands',
          value:
            '`!refresh-dashboard` - Refresh admin dashboard (Administrator only)',
        },
        {
          name: '📚 Configuration',
          value:
            'Configure the bot using environment variables in `.env` file.\n' +
            'See `.env.example` for all available options.',
        }
      )
      .setFooter({ text: 'IDDQD Bot | Components V2' })
      .setTimestamp();

    await interaction.reply({
      embeds: [embed],
      flags: 64, // EPHEMERAL
    });
  },
};

export default command;
