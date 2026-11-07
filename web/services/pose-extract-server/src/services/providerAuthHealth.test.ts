import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { EXPIRING_SOON_SEC } from "./higgsfieldCredentialGuard";
import {
  evaluateProviderAuthHealth,
  overallStatusFor,
  resetProviderAuthHealthMemory
} from "./providerAuthHealth";
import { providerAuthStatePathFor, recordProviderAuthFailure, recordProviderAuthSuccess } from "./providerAuthStateFile";

const NOW_MS = 1_800_000_000_000;
const NOW_SEC = Math.floor(NOW_MS / 1000);

const tempDirs: string[] = [];

async function makeCredentials(expiresAtSec: number | string | null): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-health-"));
  tempDirs.push(dir);
  const credentialsPath = path.join(dir, "credentials.json");
  const payload =
    expiresAtSec === null
      ? { access_token: "secret-access" }
      : { access_token: "secret-access", refresh_token: "secret-refresh", expires_at: expiresAtSec };
  await fs.writeFile(credentialsPath, JSON.stringify(payload), { mode: 0o600 });
  return credentialsPath;
}

beforeEach(() => {
  resetProviderAuthHealthMemory();
});

afterEach(async () => {
  vi.restoreAllMocks();
  resetProviderAuthHealthMemory();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("evaluateProviderAuthHealth", () => {
  it("reports not_configured when no credential path is configured and no default file exists", async () => {
    const health = await evaluateProviderAuthHealth({
      env: { HOME: "/nonexistent-home" },
      now: () => NOW_MS
    });

    expect(health).toEqual({
      enabled: false,
      state: "not_configured",
      expiresInSec: null,
      lastAuthError: null,
      lastSuccessAt: null
    });
    expect(overallStatusFor(health)).toBe("ok");
  });

  it("reports ok when the credential lives longer than a day", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + EXPIRING_SOON_SEC + 600);

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS
    });

    expect(health).toMatchObject({ enabled: true, state: "ok", expiresInSec: EXPIRING_SOON_SEC + 600 });
    expect(overallStatusFor(health)).toBe("ok");
    expect(JSON.stringify(health)).not.toContain("secret-access");
  });

  it("reads the auth state another process (the worker) wrote to the shared file", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + EXPIRING_SOON_SEC + 600);
    // The worker records the failure; this process only reads the file.
    await recordProviderAuthFailure({
      statePath: providerAuthStatePathFor(credentialsPath),
      code: "PROVIDER_AUTH_REQUIRED",
      nowMs: NOW_MS
    });

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() }
    });

    expect(health.state).toBe("ok");
    expect(health.lastAuthError).toEqual({
      at: new Date(NOW_MS).toISOString(),
      code: "PROVIDER_AUTH_REQUIRED",
      reason: "cli_auth_failure"
    });
    expect(overallStatusFor(health)).toBe("degraded");
  });

  it("stops degrading once a later CLI call succeeded", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + EXPIRING_SOON_SEC + 600);
    const statePath = providerAuthStatePathFor(credentialsPath);
    await recordProviderAuthFailure({ statePath, nowMs: NOW_MS });
    await recordProviderAuthSuccess({ statePath, nowMs: NOW_MS + 60_000 });

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS + 120_000
    });

    expect(health.lastAuthError).toBeNull();
    expect(health.lastSuccessAt).toBe(new Date(NOW_MS + 60_000).toISOString());
    expect(overallStatusFor(health)).toBe("ok");
  });

  it("logs the transition once per change instead of on every probe", async () => {
    const credentialsPath = await makeCredentials("2099-01-01T00:00:00Z");
    const logger = { error: vi.fn() };

    await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger,
      dispatchAlert: vi.fn(async () => true)
    });
    await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger,
      dispatchAlert: vi.fn(async () => true)
    });

    expect(logger.error).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(logger.error.mock.calls)).not.toContain("secret-refresh");
  });

  it("degrades on missing and invalid credentials", async () => {
    const invalidPath = await makeCredentials("2099-01-01T00:00:00Z");
    const missingPath = path.join(os.tmpdir(), "hf-health-missing", "credentials.json");

    for (const credentialsPath of [invalidPath, missingPath]) {
      resetProviderAuthHealthMemory();
      const health = await evaluateProviderAuthHealth({
        env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
        now: () => NOW_MS,
        logger: { error: vi.fn() },
        dispatchAlert: vi.fn(async () => true)
      });
      expect(overallStatusFor(health)).toBe("degraded");
    }
  });

  it("stays ok while a 24h access token is expiring: the CLI refreshes on its next call", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 600);

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      dispatchAlert: vi.fn(async () => true)
    });

    expect(health.state).toBe("expiring_soon");
    expect(overallStatusFor(health)).toBe("ok");
  });

  it("stays ok for a recently expired token, because no job has had a chance to refresh it", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 3 * 3600);

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      dispatchAlert: vi.fn(async () => true)
    });

    expect(health.state).toBe("expired");
    expect(overallStatusFor(health)).toBe("ok");
  });

  it("warns without alerting once the token has been expired for more than 48 hours", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 49 * 3600);
    const dispatchAlert = vi.fn(async () => true);
    const logger = { error: vi.fn(), warn: vi.fn() };

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger,
      dispatchAlert
    });

    expect(health.state).toBe("expired");
    expect(overallStatusFor(health)).toBe("warn");
    expect(dispatchAlert).not.toHaveBeenCalled();
  });

  it("degrades instead of throwing when the credential file cannot be read", async () => {
    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: "/root/definitely/not/readable/credentials.json" },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      dispatchAlert: vi.fn(async () => true),
      readSnapshot: async () => {
        throw new Error("EACCES");
      }
    });

    expect(overallStatusFor(health)).toBe("degraded");
    expect(health.state).toBe("invalid");
  });

  it("dispatches one alert when the provider auth degrades", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 49 * 3600);
    const dispatchAlert = vi.fn(async () => true);

    await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      dispatchAlert
    });
    await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      dispatchAlert
    });

    expect(dispatchAlert).not.toHaveBeenCalled();
  });
});
