/**
 * Sheets dashboard category
 */

import { text, separator } from '../../../utils/v2.js';
import type { V2TopLevel } from '../../../../types/Componentsv2.js';

export function renderSheets(): V2TopLevel[] {
  return [
    text('# 📊 Sheets'),
    text('Export and manage Google Sheets integrations.'),
    separator(),
    text('## Available Actions'),
    text('• Export raid signup data'),
    text('• Sync soft reserve lists'),
    text('• Update tier3 request status'),
    text('• Export summon panel data'),
    separator(),
    text('-# Configure Google Sheets via `GOOGLE_SERVICE_ACCOUNT_EMAIL` and `GOOGLE_PRIVATE_KEY`'),
  ];
}
