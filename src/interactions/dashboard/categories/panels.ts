/**
 * Panels dashboard category
 */

import { text, separator } from '../../../utils/v2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderPanels(): V2TopLevel[] {
  return [
    text('# 📋 Panels'),
    text('Control role assignment panels and summon notifications.'),
    separator(),
    text('## Role Panels'),
    text('Manage class role assignment for guild members.'),
    text('Configure via `ROLES_TARGET_CHANNEL_ID`.'),
    separator(),
    text('## Summon Panel'),
    text('Manage summon notifications and channel assignments.'),
    text('Configure via `SUMMON_PANEL_CHANNEL_ID` and `SUMMON_ROLE_ID`.'),
    separator(),
    text('-# Use refresh commands to update panels after configuration changes'),
  ];
}
