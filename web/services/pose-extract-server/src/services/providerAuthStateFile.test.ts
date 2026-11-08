import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  EMPTY_PROVIDER_AUTH_STATE,
  dispatchProviderAuthAlertOnce,
  providerAuthStatePathFor,
  readProviderAuthState,
  recordProviderAuthFailure,
  recordProviderAuthSuccess,
  writeProviderAuthState
} from "./providerAuthStateFile";

const NOW_MS = 1_800_000_000_000;

const tempDirs: string[] = [];

async function makeCredentialsDir(): Promise<{ dir: string; credentialsPath: string; statePath: string }> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-state-"));
  tempDirs.push(dir);
  const credentialsPath = path.join(dir, "credentials.json");
  await fs.writeFile(
    credentialsPath,
    JSON.stringify({
      access_token: "secret-access",
      refresh_token: "secret-refresh",
      expires_at: Math.floor(NOW_MS / 1000) + 3600
    }),
    { mode: 0o600 }
  );
  return { dir, credentialsPath, statePath: providerAuthStatePathFor(credentialsPath) };
}

afterEach(async () => {
  vi.restoreAllMocks();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("providerAuthStatePathFor", () => {
  it("keeps the state file next to the credential, under state/", async () => {
    const { credentialsPath, statePath } = await makeCredentialsDir();

    expect(statePath).toBe(path.join(path.dirname(credentialsPath), "state", "provider-auth.json"));
  });
});

describe("readProviderAuthState", () => {
  it("returns an empty record when the file is missing or unreadable", async () => {
    const { statePath } = await makeCredentialsDir();
    expect(await readProviderAuthState(statePath)).toEqual(EMPTY_PROVIDER_AUTH_STATE);

    await fs.mkdir(path.dirname(statePath), { recursive: true });
    await fs.writeFile(statePath, "not-json", { mode: 0o600 });
    expect(await readProviderAuthState(statePath)).toEqual(EMPTY_PROVIDER_AUTH_STATE);
  });
});

describe("recordProviderAuthFailure / recordProviderAuthSuccess", () => {
  it("writes an atomic 0600 record with no token material", async () => {
    const { statePath } = await makeCredentialsDir();

    await recordProviderAuthFailure({ statePath, code: "PROVIDER_AUTH_REQUIRED", nowMs: NOW_MS });

    const raw = await fs.readFile(statePath, "utf8");
    expect(JSON.parse(raw)).toEqual({
      lastAuthErrorAt: new Date(NOW_MS).toISOString(),
      lastAuthErrorCode: "PROVIDER_AUTH_REQUIRED",
      lastAuthErrorReason: "cli_auth_failure",
      lastSuccessAt: null,
      lastAlertAt: null,
      lastAlertKey: null
    });
    expect(raw).not.toContain("secret-access");
    expect(raw).not.toContain("secret-refresh");
    expect((await fs.stat(statePath)).mode & 0o777).toBe(0o600);
    const leftovers = (await fs.readdir(path.dirname(statePath))).filter((name) => name.includes(".tmp."));
    expect(leftovers).toEqual([]);
  });

  it("keeps the error history and stamps the success time", async () => {
    const { statePath } = await makeCredentialsDir();
    await recordProviderAuthFailure({ statePath, nowMs: NOW_MS });

    const afterSuccess = await recordProviderAuthSuccess({ statePath, nowMs: NOW_MS + 60_000 });

    expect(afterSuccess.lastAuthErrorAt).toBe(new Date(NOW_MS).toISOString());
    expect(afterSuccess.lastSuccessAt).toBe(new Date(NOW_MS + 60_000).toISOString());
    expect(await readProviderAuthState(statePath)).toEqual(afterSuccess);
  });

  it("survives a concurrent write by another process", async () => {
    const { statePath } = await makeCredentialsDir();

    await Promise.all([
      recordProviderAuthFailure({ statePath, nowMs: NOW_MS }),
      recordProviderAuthSuccess({ statePath, nowMs: NOW_MS + 1000 })
    ]);

    const record = await readProviderAuthState(statePath);
    expect([record.lastAuthErrorAt, record.lastSuccessAt]).toContain(new Date(NOW_MS).toISOString());
    expect(record).toMatchObject({ lastAuthErrorCode: "PROVIDER_AUTH_REQUIRED" });
  });
});

describe("writeProviderAuthState", () => {
  it("creates the state directory with restrictive permissions", async () => {
    const { statePath } = await makeCredentialsDir();

    await writeProviderAuthState(statePath, { ...EMPTY_PROVIDER_AUTH_STATE, lastSuccessAt: new Date(NOW_MS).toISOString() });

    expect((await fs.stat(path.dirname(statePath))).mode & 0o777).toBe(0o700);
  });
});

describe("dispatchProviderAuthAlertOnce", () => {
  const payload = {
    event: "provider_auth" as const,
    status: "degraded" as const,
    state: "auth_error",
    expiresInSec: null
  };

  it("does nothing when no webhook is configured", async () => {
    const { statePath } = await makeCredentialsDir();
    const fetchImpl = vi.fn();

    const sent = await dispatchProviderAuthAlertOnce({
      statePath,
      payload,
      nowMs: NOW_MS,
      env: {},
      fetchImpl: fetchImpl as unknown as typeof fetch
    });

    expect(sent).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect((await readProviderAuthState(statePath)).lastAlertAt).toBeNull();
  });

  it("debounces through the state file so another process cannot re-send it", async () => {
    const { statePath } = await makeCredentialsDir();
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    const deps = {
      statePath,
      payload,
      env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
      fetchImpl: fetchImpl as unknown as typeof fetch
    };

    expect(await dispatchProviderAuthAlertOnce({ ...deps, nowMs: NOW_MS })).toBe(true);
    // A second process reads the same file and must stay quiet.
    expect(await dispatchProviderAuthAlertOnce({ ...deps, nowMs: NOW_MS + 60_000 })).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);

    const record = await readProviderAuthState(statePath);
    expect(record.lastAlertKey).toBe("degraded:auth_error");
    expect(record.lastAlertAt).toBe(new Date(NOW_MS).toISOString());
  });

  it("sends again once the debounce window has passed", async () => {
    const { statePath } = await makeCredentialsDir();
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    const deps = {
      statePath,
      payload,
      env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
      fetchImpl: fetchImpl as unknown as typeof fetch
    };

    await dispatchProviderAuthAlertOnce({ ...deps, nowMs: NOW_MS });
    await dispatchProviderAuthAlertOnce({ ...deps, nowMs: NOW_MS + 7 * 60 * 60 * 1000 });

    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it("does not record an alert when the webhook fails", async () => {
    const { statePath } = await makeCredentialsDir();
    const fetchImpl = vi.fn().mockRejectedValue(new Error("network down"));

    const sent = await dispatchProviderAuthAlertOnce({
      statePath,
      payload,
      nowMs: NOW_MS,
      env: { ALERT_WEBHOOK_URL: "https://hooks.example.com/abc" },
      fetchImpl: fetchImpl as unknown as typeof fetch
    });

    expect(sent).toBe(false);
    expect((await readProviderAuthState(statePath)).lastAlertAt).toBeNull();
  });
});
