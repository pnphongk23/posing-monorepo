import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { EXPIRING_SOON_SEC } from "./higgsfieldCredentialGuard";
import {
  evaluateProviderAuthHealth,
  getLastProviderAuthError,
  overallStatusFor,
  recordProviderAuthFailure,
  recordProviderAuthSuccess,
  resetProviderAuthState
} from "./providerAuthHealth";

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

afterEach(async () => {
  vi.restoreAllMocks();
  resetProviderAuthState();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("provider auth error store", () => {
  it("records the last auth failure with a timestamp and clears it on success", () => {
    expect(getLastProviderAuthError()).toBeNull();

    recordProviderAuthFailure({ code: "PROVIDER_AUTH_REQUIRED", nowMs: NOW_MS });
    const recorded = getLastProviderAuthError();

    expect(recorded?.code).toBe("PROVIDER_AUTH_REQUIRED");
    expect(recorded?.at).toBe(new Date(NOW_MS).toISOString());
    expect(JSON.stringify(recorded)).not.toContain("secret");

    recordProviderAuthSuccess();
    expect(getLastProviderAuthError()).toBeNull();
  });
});

describe("evaluateProviderAuthHealth", () => {
  it("reports not_configured when no credential path is configured and no default file exists", async () => {
    const health = await evaluateProviderAuthHealth({
      env: { HOME: "/nonexistent-home" },
      now: () => NOW_MS
    });

    expect(health).toEqual({ enabled: false, state: "not_configured", expiresInSec: null, lastAuthError: null });
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

  it("reports warn and logs once when the credential expires within a day", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 3600);
    const logger = { error: vi.fn() };

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger
    });

    expect(health.state).toBe("expiring_soon");
    expect(overallStatusFor(health)).toBe("warn");
    expect(logger.error).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(logger.error.mock.calls)).not.toContain("secret-refresh");

    await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger
    });
    expect(logger.error).toHaveBeenCalledTimes(1);
  });

  it("degrades on expired, missing and invalid credentials", async () => {
    const expiredPath = await makeCredentials(NOW_SEC - 60);
    const invalidPath = await makeCredentials("2099-01-01T00:00:00Z");
    const missingPath = path.join(os.tmpdir(), "hf-health-missing", "credentials.json");

    for (const credentialsPath of [expiredPath, invalidPath, missingPath]) {
      const health = await evaluateProviderAuthHealth({
        env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
        now: () => NOW_MS,
        logger: { error: vi.fn() }
      });
      expect(overallStatusFor(health)).toBe("degraded");
    }
  });

  it("degrades when the last CLI call failed auth even if the file still looks valid", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + EXPIRING_SOON_SEC + 600);
    recordProviderAuthFailure({ code: "PROVIDER_AUTH_REQUIRED", nowMs: NOW_MS });

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn() }
    });

    expect(health.state).toBe("ok");
    expect(health.lastAuthError).toEqual({ at: new Date(NOW_MS).toISOString(), code: "PROVIDER_AUTH_REQUIRED" });
    expect(overallStatusFor(health)).toBe("degraded");
  });

  it("degrades instead of throwing when the credential file cannot be read", async () => {
    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: "/root/definitely/not/readable/credentials.json" },
      now: () => NOW_MS,
      logger: { error: vi.fn() },
      readSnapshot: async () => {
        throw new Error("EACCES");
      }
    });

    expect(overallStatusFor(health)).toBe("degraded");
    expect(health.state).toBe("invalid");
  });

  it("dispatches one alert when the provider auth degrades", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
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

    expect(dispatchAlert).toHaveBeenCalledTimes(1);
    expect(dispatchAlert.mock.calls[0][0]).toMatchObject({ status: "degraded", state: "expired" });
  });
});
