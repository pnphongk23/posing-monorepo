import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  ADMIN_SECRET: z.string().min(1),
  COMMUNITY_UPLOAD_DIR: z.string().min(1).default("data/community"),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(10),
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
    NODE_ENV: overrides?.NODE_ENV ?? process.env.NODE_ENV,
    PORT: overrides?.PORT ?? process.env.PORT,
    DATABASE_URL: overrides?.DATABASE_URL ?? process.env.DATABASE_URL,
    ADMIN_SECRET: overrides?.ADMIN_SECRET ?? process.env.ADMIN_SECRET,
    COMMUNITY_UPLOAD_DIR: overrides?.COMMUNITY_UPLOAD_DIR ?? process.env.COMMUNITY_UPLOAD_DIR,
    RATE_LIMIT_WINDOW_MS: overrides?.RATE_LIMIT_WINDOW_MS ?? process.env.RATE_LIMIT_WINDOW_MS,
    RATE_LIMIT_MAX: overrides?.RATE_LIMIT_MAX ?? process.env.RATE_LIMIT_MAX,
    R2_ACCOUNT_ID: overrides?.R2_ACCOUNT_ID ?? process.env.R2_ACCOUNT_ID,
    R2_ACCESS_KEY_ID: overrides?.R2_ACCESS_KEY_ID ?? process.env.R2_ACCESS_KEY_ID,
    R2_SECRET_ACCESS_KEY: overrides?.R2_SECRET_ACCESS_KEY ?? process.env.R2_SECRET_ACCESS_KEY,
    R2_BUCKET: overrides?.R2_BUCKET ?? process.env.R2_BUCKET,
    R2_PUBLIC_URL: overrides?.R2_PUBLIC_URL ?? process.env.R2_PUBLIC_URL,
    BROWSER_APP_URL: overrides?.BROWSER_APP_URL ?? process.env.BROWSER_APP_URL,
    BROWSER_PROFILE_DIR: overrides?.BROWSER_PROFILE_DIR ?? process.env.BROWSER_PROFILE_DIR,
    BROWSER_HEADLESS: overrides?.BROWSER_HEADLESS ?? process.env.BROWSER_HEADLESS,
    BROWSER_EXECUTABLE_PATH: overrides?.BROWSER_EXECUTABLE_PATH ?? process.env.BROWSER_EXECUTABLE_PATH,
    BROWSER_CHROME_CHANNEL: overrides?.BROWSER_CHROME_CHANNEL ?? process.env.BROWSER_CHROME_CHANNEL
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
