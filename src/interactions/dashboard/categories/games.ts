/**
 * Games dashboard category
 */

import { text, separator } from '../../../utils/v2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderGames(): V2TopLevel[] {
  return [
    text('# 🎮 Games'),
    text('Manage mini-games and view leaderboards.'),
    separator(),
    text('## FlaskGamba'),
    text('Mini-game where players guess the outcome of flask usage.'),
    text('Configure via `FLASKGAMBA_CHANNEL_ID` in environment variables.'),
    separator(),
    text('-# No active games configured'),
  ];
}
