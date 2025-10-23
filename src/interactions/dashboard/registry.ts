/**
 * Dashboard category registry
 */

export interface DashboardCategory {
  id: string;
  label: string;
  emoji?: string;
}

/**
 * Available dashboard categories
 */
export const DASHBOARD_CATEGORIES: DashboardCategory[] = [
  { id: 'main', label: 'Main', emoji: '🏠' },
  { id: 'games', label: 'Games', emoji: '🎮' },
  { id: 'sheets', label: 'Sheets', emoji: '📊' },
  { id: 'raiding', label: 'Raiding', emoji: '⚔️' },
  { id: 'panels', label: 'Panels', emoji: '📋' },
];

/**
 * Get category by ID
 */
export function getCategory(id: string): DashboardCategory | undefined {
  return DASHBOARD_CATEGORIES.find(cat => cat.id === id);
}
