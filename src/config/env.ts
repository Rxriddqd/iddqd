import { z } from 'zod';
import { config } from 'dotenv';

config();

/**
 * Environment variable schema for validation
 */
const envSchema = z.object({
  // Required Discord configuration
  DISCORD_TOKEN: z.string().min(1, 'DISCORD_TOKEN is required'),
  DISCORD_CLIENT_ID: z.string().min(1, 'DISCORD_CLIENT_ID is required'),
  
  // Optional Discord configuration
  DISCORD_GUILD_ID: z.string().optional(),
  DASHBOARD_CHANNEL_ID: z.string().optional(),
  
  // Optional database
  DATABASE_URL: z.string().optional(),
  
  // Redis configuration
  REDIS_HOST: z.string().default('localhost'),
  REDIS_PORT: z.string().default('6379'),
  REDIS_PASSWORD: z.string().optional(),
  REDIS_TLS: z.string().transform(val => val === 'true').default('false'),
  REDIS_ENABLED: z.string().transform(val => val === 'true').default('true'),
  
  // Persistent disk configuration
  PERSISTENT_DISK_PATH: z.string().default('/data'),
  
  // Optional Tier3 configuration
  TIER3_CHANNEL_ID: z.string().optional(),
  TIER3_MSG_CELL: z.string().optional(),
  
  // Optional FlaskGamba configuration
  FLASKGAMBA_CHANNEL_ID: z.string().optional(),
  FLASKGAMBA_TZ: z.string().optional(),
  FLASK_LOG_SHEET: z.string().optional(),
  FLASK_RULES_TEXT: z.string().optional(),
  
  // Optional Summon configuration
  SUMMON_PANEL_CHANNEL_ID: z.string().optional(),
  SUMMON_PANEL_MSG_RANGE: z.string().optional(),
  SUMMON_ROLE_ID: z.string().optional(),
  SUMMON_PANEL_ADMIN_ROLE_ID: z.string().optional(),
  SUMMON_PANEL_CHANNEL_RANGE: z.string().optional(),
  
  // Optional SoftRes configuration
  SR_PANEL_CHANNEL_ID: z.string().optional(),
  EMBED_SEPERATOR_TRANSPARENT: z.string().optional(),
  
  // Optional Roles configuration
  ROLES_TARGET_CHANNEL_ID: z.string().optional(),
  ROLES_SOCIAL_ALERT_CHANNEL_ID: z.string().optional(),
  
  // Optional Google Sheets configuration
  GOOGLE_SERVICE_ACCOUNT_EMAIL: z.string().optional(),
  GOOGLE_PRIVATE_KEY: z.string().optional(),
  SHEET_CONFIG_ID: z.string().optional(),
  SHEET_IDDQD_ID: z.string().optional(),
  
  // Optional Tournament configuration
  TOURNAMENT_CHANNEL_ID: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

/**
 * Validate and return environment variables
 */
export function validateEnv(): Env {
  const result = envSchema.safeParse(process.env);
  
  if (!result.success) {
    console.error('❌ Environment validation failed:');
    result.error.issues.forEach((issue) => {
      console.error(`  - ${issue.path.join('.')}: ${issue.message}`);
    });
    process.exit(1);
  }
  
  return result.data;
}

/**
 * Validated environment variables
 */
export const env = validateEnv();
