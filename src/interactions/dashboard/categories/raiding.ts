/**
 * Raiding dashboard category
 */

import { text, separator } from '../../../utils/v2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderRaiding(): V2TopLevel[] {
  return [
    text('# ⚔️ Raiding'),
    text('Manage raid signups, rosters, and soft reserves.'),
    separator(),
    text('## Raid Instances'),
    text('• **MC** - Molten Core'),
    text('• **BWL** - Blackwing Lair'),
    text('• **AQ40** - Temple of Ahn\'Qiraj'),
    text('• **NAXX** - Naxxramas'),
    separator(),
    text('## Actions'),
    text('• View current signups'),
    text('• Export roster to sheets'),
    text('• Manage soft reserves'),
    separator(),
    text('-# Configure via `SR_PANEL_CHANNEL_ID` and related environment variables'),
  ];
}
