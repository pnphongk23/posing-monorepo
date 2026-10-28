import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  ADMIN_SECRET: z.string().min(1),
  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string().min(1).optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(),
  SUPABASE_JWT_KEY_ID: z.string().min(1),
  BACKEND_PUBLIC_URL: z.string().url().optional(),
  COMMUNITY_UPLOAD_DIR: z.string().min(1).default("data/community"),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(10),
  AUTH_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().optional(),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().optional(),
  AUTH_RATE_LIMIT_IP_MAX: z.coerce.number().int().positive().optional(),
  R2_ACCOUNT_ID: z.string().min(1),
  R2_ACCESS_KEY_ID: z.string().min(1),
  R2_SECRET_ACCESS_KEY: z.string().min(1),
  R2_BUCKET: z.string().min(1),
  R2_PUBLIC_URL: z.string().url(),
  BROWSER_APP_URL: z.string().url().default("https://gemini.google.com/app"),
  BROWSER_PROFILE_DIR: z.string().min(1).default("data/browser-profile"),
  BROWSER_HEADLESS: z.enum(["true", "false"]).default("true"),
  BROWSER_EXECUTABLE_PATH: z.string().optional(),
  BROWSER_CHROME_CHANNEL: z.string().optional()
});

export type AppEnv = z.infer<typeof envSchema>;

let cachedEnv: AppEnv | null = null;

export function getEnv(overrides?: Record<string, string | undefined>): AppEnv {
  if (!overrides && cachedEnv) {
    return cachedEnv;
  }

  const parsed = envSchema.safeParse({
    ...process.env,
    ...(overrides ?? {})
  });

  if (!parsed.success) {
    const errors = parsed.error.issues.map((item) => `${item.path.join(".")}: ${item.message}`);
    throw new Error(`Invalid environment variables:\n${errors.join("\n")}`);
  }

  if (!overrides) {
    cachedEnv = parsed.data;
  }

  return parsed.data;
}

export function resetEnvCache(): void {
  cachedEnv = null;
}

const authRateLimitSchema = z.object({
  AUTH_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().optional(),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().positive().optional(),
  AUTH_RATE_LIMIT_IP_MAX: z.coerce.number().int().positive().optional()
});
export function authRateLimitFromEnv(source: Record<string, string | undefined> = process.env): { windowMs?: number; maxPerEmail?: number; maxPerIp?: number } {
  const parsed = authRateLimitSchema.safeParse(source);
  if (!parsed.success) {
    const errors = parsed.error.issues.map((item) => `${item.path.join(".")}: ${item.message}`);
    throw new Error(`Invalid environment variables:\n${errors.join("\n")}`);
  }
  return {
    windowMs: parsed.data.AUTH_RATE_LIMIT_WINDOW_MS,
    maxPerEmail: parsed.data.AUTH_RATE_LIMIT_MAX,
    maxPerIp: parsed.data.AUTH_RATE_LIMIT_IP_MAX
  };
}

/** A short webhook token is a guessable webhook token, so the schema refuses it at boot. */
export const REVENUECAT_WEBHOOK_AUTH_MIN_LENGTH = 32;

const revenueCatSchema = z.object({
  REVENUECAT_WEBHOOK_AUTH: z.string().min(REVENUECAT_WEBHOOK_AUTH_MIN_LENGTH).optional(),
  REVENUECAT_SECRET_API_KEY: z.string().min(1).optional(),
  REVENUECAT_ENTITLEMENT_ID: z.string().min(1).optional()
});

export interface RevenueCatConfig {
  webhookAuth?: string;
  secretApiKey?: string;
  entitlementId?: string;
}

/**
 * Feature-scoped env: absent keys leave the entitlement surface mounted as a 503 stub and
 * leave the webhook unmounted, so an unprovisioned deploy fails closed instead of booting
 * with a half-configured subscription integration.
 */
export function revenueCatFromEnv(source: Record<string, string | undefined> = process.env): RevenueCatConfig {
  const parsed = revenueCatSchema.safeParse(source);
  if (!parsed.success) {
    const errors = parsed.error.issues.map((item) => `${item.path.join(".")}: ${item.message}`);
    throw new Error(`Invalid environment variables:\n${errors.join("\n")}`);
  }
  return {
    webhookAuth: parsed.data.REVENUECAT_WEBHOOK_AUTH,
    secretApiKey: parsed.data.REVENUECAT_SECRET_API_KEY,
    entitlementId: parsed.data.REVENUECAT_ENTITLEMENT_ID
  };
}
