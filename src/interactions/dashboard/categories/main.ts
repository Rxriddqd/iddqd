/**
 * Main dashboard category
 */

import { text, separator } from '../../../utils/v2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderMain(): V2TopLevel[] {
  return [
    text('# 🏠 Admin Dashboard'),
    text('Welcome to the IDDQD Bot admin dashboard. Use the buttons above to navigate between different sections.'),
    separator(),
    text('## Available Sections'),
    text('🎮 **Games** - Manage mini-games and leaderboards'),
    text('📊 **Sheets** - Export and sync Google Sheets data'),
    text('⚔️ **Raiding** - Manage raid signups and rosters'),
    text('📋 **Panels** - Control role and summon panels'),
    separator(),
    text('-# Dashboard is Administrator-only. Last refreshed: <t:' + Math.floor(Date.now() / 1000) + ':R>'),
  ];
}
