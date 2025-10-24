/**
 * Games dashboard category
 */

import { text, separator, button, actionRow } from '../../../utils/v2.js';
import { ButtonStyle } from '../../../../types/Componentsv2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderGames(): V2TopLevel[] {
  return [
    text('# 🎮 Games'),
    text('Manage mini-games and view leaderboards.'),
    separator(),
    text('## 🏆 Tournament Mode'),
    text('Competitive elimination game where players roll numbers across multiple rounds.'),
    text('Players compete to get the highest rolls, with bottom performers eliminated each round.'),
    text('Configure via `TOURNAMENT_CHANNEL_ID` in environment variables.'),
    actionRow([
      button('🏆 Tournament Setup', 'tournament:setup', ButtonStyle.PRIMARY),
      button('📋 Active Tournaments', 'tournament:list', ButtonStyle.SECONDARY),
    ]),
    separator(),
    text('## FlaskGamba'),
    text('Mini-game where players guess the outcome of flask usage.'),
    text('Configure via `FLASKGAMBA_CHANNEL_ID` in environment variables.'),
    separator(),
    text('-# Additional games can be configured via environment variables'),
  ];
}
