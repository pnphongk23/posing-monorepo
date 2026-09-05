import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { getEnv, resetEnvCache } from "./env";

const originalEnv = {
  NODE_ENV: process.env.NODE_ENV,
  PORT: process.env.PORT,
  DATABASE_URL: process.env.DATABASE_URL,
  ADMIN_SECRET: process.env.ADMIN_SECRET,
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_JWT_KEY_ID: process.env.SUPABASE_JWT_KEY_ID,
  RATE_LIMIT_WINDOW_MS: process.env.RATE_LIMIT_WINDOW_MS,
  RATE_LIMIT_MAX: process.env.RATE_LIMIT_MAX,
  R2_ACCOUNT_ID: process.env.R2_ACCOUNT_ID,
  R2_ACCESS_KEY_ID: process.env.R2_ACCESS_KEY_ID,
  R2_SECRET_ACCESS_KEY: process.env.R2_SECRET_ACCESS_KEY,
  R2_BUCKET: process.env.R2_BUCKET,
  R2_PUBLIC_URL: process.env.R2_PUBLIC_URL
};

beforeEach(() => {
  resetEnvCache();
});

afterEach(() => {
  if (originalEnv.NODE_ENV === undefined) {
    delete process.env.NODE_ENV;
  } else {
    process.env.NODE_ENV = originalEnv.NODE_ENV;
  }

  if (originalEnv.PORT === undefined) {
    delete process.env.PORT;
  } else {
    process.env.PORT = originalEnv.PORT;
  }

  if (originalEnv.DATABASE_URL === undefined) {
    delete process.env.DATABASE_URL;
  } else {
    process.env.DATABASE_URL = originalEnv.DATABASE_URL;
  }

  if (originalEnv.ADMIN_SECRET === undefined) {
    delete process.env.ADMIN_SECRET;
  } else {
    process.env.ADMIN_SECRET = originalEnv.ADMIN_SECRET;
  }

  for (const key of ["SUPABASE_URL", "SUPABASE_JWT_KEY_ID"] as const) {
    if (originalEnv[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = originalEnv[key];
    }
  }

  if (originalEnv.RATE_LIMIT_WINDOW_MS === undefined) {
    delete process.env.RATE_LIMIT_WINDOW_MS;
  } else {
    process.env.RATE_LIMIT_WINDOW_MS = originalEnv.RATE_LIMIT_WINDOW_MS;
  }

  if (originalEnv.RATE_LIMIT_MAX === undefined) {
    delete process.env.RATE_LIMIT_MAX;
  } else {
    process.env.RATE_LIMIT_MAX = originalEnv.RATE_LIMIT_MAX;
  }

  const r2Keys = [
    "R2_ACCOUNT_ID",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_BUCKET",
    "R2_PUBLIC_URL"
  ] as const;
  for (const key of r2Keys) {
    if (originalEnv[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = originalEnv[key];
    }
  }
});

const DATABASE_URL = "postgres://user:pass@localhost:5432/pose";
const SUPABASE_URL = "https://project-ref.supabase.co";
const SUPABASE_JWT_KEY_ID = "test-key-id";

describe("getEnv", () => {
  it("uses schema defaults when NODE_ENV and PORT are missing", () => {
    delete process.env.NODE_ENV;
    delete process.env.PORT;
    process.env.DATABASE_URL = DATABASE_URL;
    process.env.ADMIN_SECRET = "secret-value";
    process.env.SUPABASE_URL = SUPABASE_URL;
    process.env.SUPABASE_JWT_KEY_ID = SUPABASE_JWT_KEY_ID;
    process.env.R2_ACCOUNT_ID = "account-id";
    process.env.R2_ACCESS_KEY_ID = "access-key-id";
    process.env.R2_SECRET_ACCESS_KEY = "secret-access-key";
    process.env.R2_BUCKET = "pose-bucket";
    process.env.R2_PUBLIC_URL = "https://cdn.example.com";

    const env = getEnv();

    expect(env.NODE_ENV).toBe("development");
    expect(env.PORT).toBe(3000);
    expect(env.DATABASE_URL).toBe(DATABASE_URL);
    expect(env.ADMIN_SECRET).toBe("secret-value");
    expect(env.RATE_LIMIT_WINDOW_MS).toBe(60_000);
    expect(env.RATE_LIMIT_MAX).toBe(10);
    expect(env.R2_ACCOUNT_ID).toBe("account-id");
    expect(env.R2_ACCESS_KEY_ID).toBe("access-key-id");
    expect(env.R2_SECRET_ACCESS_KEY).toBe("secret-access-key");
    expect(env.R2_BUCKET).toBe("pose-bucket");
    expect(env.R2_PUBLIC_URL).toBe("https://cdn.example.com");
  });

  it("reads NODE_ENV and PORT from current process env", () => {
    process.env.NODE_ENV = "production";
    process.env.PORT = "4567";
    process.env.DATABASE_URL = "postgres://prod:secret@db.prod:5432/pose";
    process.env.ADMIN_SECRET = "prod-secret";
    process.env.SUPABASE_URL = SUPABASE_URL;
    process.env.SUPABASE_JWT_KEY_ID = SUPABASE_JWT_KEY_ID;
    process.env.RATE_LIMIT_WINDOW_MS = "120000";
    process.env.RATE_LIMIT_MAX = "25";
    process.env.R2_ACCOUNT_ID = "prod-account-id";
    process.env.R2_ACCESS_KEY_ID = "prod-access-key-id";
    process.env.R2_SECRET_ACCESS_KEY = "prod-secret-access-key";
    process.env.R2_BUCKET = "prod-pose-bucket";
    process.env.R2_PUBLIC_URL = "https://cdn.prod.example.com";

    const env = getEnv();

    expect(env.NODE_ENV).toBe("production");
    expect(env.PORT).toBe(4567);
    expect(env.DATABASE_URL).toBe("postgres://prod:secret@db.prod:5432/pose");
    expect(env.ADMIN_SECRET).toBe("prod-secret");
    expect(env.RATE_LIMIT_WINDOW_MS).toBe(120000);
    expect(env.RATE_LIMIT_MAX).toBe(25);
    expect(env.R2_ACCOUNT_ID).toBe("prod-account-id");
    expect(env.R2_ACCESS_KEY_ID).toBe("prod-access-key-id");
    expect(env.R2_SECRET_ACCESS_KEY).toBe("prod-secret-access-key");
    expect(env.R2_BUCKET).toBe("prod-pose-bucket");
    expect(env.R2_PUBLIC_URL).toBe("https://cdn.prod.example.com");
  });

  it("throws on invalid environment variables", () => {
    expect(() =>
      getEnv({
        ADMIN_SECRET: "",
        SUPABASE_URL,
        SUPABASE_JWT_KEY_ID,
        DATABASE_URL: "",
        R2_ACCOUNT_ID: "",
        R2_ACCESS_KEY_ID: "",
        R2_SECRET_ACCESS_KEY: "",
        R2_BUCKET: "",
        R2_PUBLIC_URL: "not-a-url"
      })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when DATABASE_URL is missing", () => {
    expect(() =>
      getEnv({
        DATABASE_URL: undefined,
        ADMIN_SECRET: "secret",
        SUPABASE_URL,
        SUPABASE_JWT_KEY_ID,
        R2_ACCOUNT_ID: "account-id",
        R2_ACCESS_KEY_ID: "access-key-id",
        R2_SECRET_ACCESS_KEY: "secret-access-key",
        R2_BUCKET: "pose-bucket",
        R2_PUBLIC_URL: "https://cdn.example.com"
      })
    ).toThrowError(/Invalid environment variables/);
  });

  it("parses COMMUNITY_UPLOAD_DIR", () => {
    resetEnvCache();
    const env = getEnv({
      DATABASE_URL,
      ADMIN_SECRET: "secret",
      SUPABASE_URL,
      SUPABASE_JWT_KEY_ID,
      COMMUNITY_UPLOAD_DIR: "/tmp/community",
      R2_ACCOUNT_ID: "account-id",
      R2_ACCESS_KEY_ID: "access-key-id",
      R2_SECRET_ACCESS_KEY: "secret-access-key",
      R2_BUCKET: "pose-bucket",
      R2_PUBLIC_URL: "https://cdn.example.com"
    });

    expect(env.COMMUNITY_UPLOAD_DIR).toBe("/tmp/community");
    resetEnvCache();
  });

  it("defaults COMMUNITY_UPLOAD_DIR to data/community", () => {
    resetEnvCache();
    const env = getEnv({
      DATABASE_URL,
      ADMIN_SECRET: "secret",
      SUPABASE_URL,
      SUPABASE_JWT_KEY_ID,
      R2_ACCOUNT_ID: "account-id",
      R2_ACCESS_KEY_ID: "access-key-id",
      R2_SECRET_ACCESS_KEY: "secret-access-key",
      R2_BUCKET: "pose-bucket",
      R2_PUBLIC_URL: "https://cdn.example.com"
    });

    expect(env.COMMUNITY_UPLOAD_DIR).toBe("data/community");
    resetEnvCache();
  });

  const r2BaseOverrides = {
    DATABASE_URL,
    ADMIN_SECRET: "secret",
    SUPABASE_URL,
    SUPABASE_JWT_KEY_ID,
    R2_ACCOUNT_ID: "account-id",
    R2_ACCESS_KEY_ID: "access-key-id",
    R2_SECRET_ACCESS_KEY: "secret-access-key",
    R2_BUCKET: "pose-bucket",
    R2_PUBLIC_URL: "https://cdn.example.com"
  };

  it("parses all R2 env vars correctly", () => {
    resetEnvCache();
    const env = getEnv(r2BaseOverrides);

    expect(env.R2_ACCOUNT_ID).toBe("account-id");
    expect(env.R2_ACCESS_KEY_ID).toBe("access-key-id");
    expect(env.R2_SECRET_ACCESS_KEY).toBe("secret-access-key");
    expect(env.R2_BUCKET).toBe("pose-bucket");
    expect(env.R2_PUBLIC_URL).toBe("https://cdn.example.com");
    resetEnvCache();
  });

  it("throws when R2_ACCOUNT_ID is missing", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_ACCOUNT_ID: undefined })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when R2_ACCESS_KEY_ID is missing", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_ACCESS_KEY_ID: undefined })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when R2_SECRET_ACCESS_KEY is missing", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_SECRET_ACCESS_KEY: undefined })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when R2_BUCKET is missing", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_BUCKET: undefined })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when R2_PUBLIC_URL is missing", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_PUBLIC_URL: undefined })
    ).toThrowError(/Invalid environment variables/);
  });

  it("throws when R2_PUBLIC_URL is not a valid URL", () => {
    expect(() =>
      getEnv({ ...r2BaseOverrides, R2_PUBLIC_URL: "not-a-valid-url" })
    ).toThrowError(/Invalid environment variables/);
  });
});
