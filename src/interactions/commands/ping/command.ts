/**
 * Ping command - Check bot responsiveness
 */

import { SlashCommandBuilder } from 'discord.js';
import type { SlashCommandModule } from '../../../../types/Command.js';

const command: SlashCommandModule = {
  data: new SlashCommandBuilder()
    .setName('ping')
    .setDescription('Check bot responsiveness and latency'),

  async execute(interaction) {
    const sent = await interaction.reply({
      content: '🏓 Pinging...',
      fetchReply: true,
    });

    const latency = sent.createdTimestamp - interaction.createdTimestamp;
    const apiLatency = Math.round(interaction.client.ws.ping);

    await interaction.editReply(
      `🏓 Pong!\n` +
      `**Roundtrip Latency:** ${latency}ms\n` +
      `**WebSocket Latency:** ${apiLatency}ms`
    );
  },
};

export default command;
