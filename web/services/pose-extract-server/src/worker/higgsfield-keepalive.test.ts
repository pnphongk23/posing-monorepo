import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  backupPathFor,
  withCredentialLock
} from "../services/higgsfieldCredentialGuard";
import {
  evaluateProviderAuthHealth,
  overallStatusFor
} from "../services/providerAuthHealth";
import {
  providerAuthStatePathFor,
  readProviderAuthState,
  recordProviderAuthFailure,
  recordProviderAuthSuccess
} from "../services/providerAuthStateFile";
import { logger } from "../utils/logger";
import {
  startHiggsfieldKeepalive,
  type HiggsfieldKeepaliveDeps,
  type KeepaliveTickResult
} from "./higgsfield-keepalive";
import { refreshCredentials } from "../services/higgsfieldSelfRefresh";

const NOW_MS = 1_800_000_000_000;
const NOW_SEC = Math.floor(NOW_MS / 1000);
const MINUTE = 60 * 1000;
const SELF_REFRESH_ENV = { HIGGSFIELD_SELF_REFRESH: "1" };

const tempDirs: string[] = [];

async function writeCredentials(credentialsPath: string, expiresAtSec: number): Promise<void> {
  await fs.writeFile(
    credentialsPath,
    JSON.stringify({
      access_token: "secret-access",
      refresh_token: "secret-refresh",
      expires_at: expiresAtSec
    }),
    { mode: 0o600 }
  );
}

async function makeCredentials(expiresAtSec: number | null): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-keepalive-"));
  tempDirs.push(dir);
  const credentialsPath = path.join(dir, "credentials.json");
  if (expiresAtSec !== null) {
    await writeCredentials(credentialsPath, expiresAtSec);
  }
  return credentialsPath;
}

/** A state file outside the credential directory, for tests that make that directory read-only. */
async function makeStatePath(): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-keepalive-state-"));
  tempDirs.push(dir);
  return path.join(dir, "provider-auth.json");
}

function makeHandle(options: {
  credentialsPath: string;
  env?: Record<string, string | undefined>;
  now?: () => number;
  deps?: Partial<HiggsfieldKeepaliveDeps>;
}) {
  const handle = startHiggsfieldKeepalive({
    credentialsPath: options.credentialsPath,
    env: options.env ?? {},
    now: options.now ?? (() => NOW_MS),
    ...options.deps
  });
  return { handle };
}

/** Give a queued tick the chance to reach the credential mutex. */
function flush(ms = 20): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

afterEach(async () => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  await Promise.all(
    tempDirs.splice(0).map(async (dir) => {
      // A test may leave its temp tree read-only to simulate an unwritable volume.
      await fs.chmod(dir, 0o700).catch(() => undefined);
      await fs.rm(dir, { recursive: true, force: true });
    })
  );
});

describe("higgsfield keepalive", () => {
  it("does nothing while the token still has time", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 3600);
    const { handle } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorAt).toBeNull();
    handle.stop();
  });

  it("never spawns the CLI once the token expired: it only records the state", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const originalBytes = await fs.readFile(credentialsPath, "utf8");
    const { handle } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("expired");

    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
    expect(state.lastAuthErrorReason).toBe("expired");
    expect(state.lastAuthErrorAt).not.toBeNull();
    // Byte-for-byte untouched: no write, no restore, no rewrite.
    expect(await fs.readFile(credentialsPath, "utf8")).toBe(originalBytes);
    handle.stop();
  });

  it("does not invoke the higgsfield binary at all", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const stubDir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-keepalive-bin-"));
    tempDirs.push(stubDir);
    const spawnLog = path.join(stubDir, "spawn.log");
    await fs.writeFile(
      path.join(stubDir, "higgsfield"),
      `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "${spawnLog}"\nexit 0\n`,
      { mode: 0o755 }
    );
    const previousPath = process.env.PATH;
    process.env.PATH = `${stubDir}:${previousPath ?? ""}`;

    const { handle } = makeHandle({ credentialsPath });
    try {
      expect(await handle.tick()).toBe<KeepaliveTickResult>("expired");
      await expect(fs.stat(spawnLog)).rejects.toThrow();
    } finally {
      process.env.PATH = previousPath;
      handle.stop();
    }
  });

  it("lets a later successful job clear the expired state", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle } = makeHandle({ credentialsPath });
    await handle.tick();

    const degraded = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn(), warn: vi.fn() },
      dispatchAlert: vi.fn(async () => true)
    });
    expect(overallStatusFor(degraded)).toBe("degraded");

    await recordProviderAuthSuccess({ statePath: providerAuthStatePathFor(credentialsPath), nowMs: NOW_MS + 60_000 });
    const healthy = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS + 120_000,
      logger: { error: vi.fn(), warn: vi.fn() },
      dispatchAlert: vi.fn(async () => true)
    });
    expect(healthy.lastAuthError).toBeNull();
    expect(overallStatusFor(healthy)).toBe("ok");
    handle.stop();
  });

  it("stays quiet until the token has actually expired", async () => {
    // Ten minutes left is still a live token: the detector must not touch it before expires_at.
    const credentialsPath = await makeCredentials(NOW_SEC + 600);
    const { handle } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorAt).toBeNull();
    handle.stop();
  });

  it("does nothing when HIGGSFIELD_KEEPALIVE is off", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle } = makeHandle({
      credentialsPath,
      env: { HIGGSFIELD_KEEPALIVE: "0" }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("disabled");
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorAt).toBeNull();
    handle.stop();
  });

  it("does nothing when the credential file is missing", async () => {
    const credentialsPath = await makeCredentials(null);
    const { handle } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    await expect(fs.stat(providerAuthStatePathFor(credentialsPath))).rejects.toThrow();
    handle.stop();
  });

  it("backs off for an hour after recording the expiry", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    let nowMs = NOW_MS;
    const { handle } = makeHandle({ credentialsPath, now: () => nowMs });
    const statePath = providerAuthStatePathFor(credentialsPath);

    expect(await handle.tick()).toBe<KeepaliveTickResult>("expired");
    const firstState = await readProviderAuthState(statePath);

    nowMs = NOW_MS + 15 * 60 * 1000;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect((await readProviderAuthState(statePath)).lastAuthErrorAt).toBe(firstState.lastAuthErrorAt);

    nowMs = NOW_MS + 61 * 60 * 1000;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("expired");
    handle.stop();
  });

  it("runs on its own timer and stops cleanly", async () => {
    vi.useFakeTimers();
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const recorded: number[] = [];
    const handle = startHiggsfieldKeepalive({
      credentialsPath,
      env: {},
      now: () => NOW_MS,
      intervalMs: 1000,
      // Fake timers must not wait on real filesystem I/O.
      readSnapshot: async () => ({ state: "expired", expiresInSec: -60, expiresAtSec: NOW_SEC - 60, mtimeMs: 0 }),
      recordExpiry: async () => {
        recorded.push(Date.now());
      }
    });

    await vi.advanceTimersByTimeAsync(1000);
    expect(recorded).toHaveLength(1);

    handle.stop();
    await vi.advanceTimersByTimeAsync(5000);
    expect(recorded).toHaveLength(1);
  });
});

describe("higgsfield keepalive self-refresh", () => {
  it("never refreshes while HIGGSFIELD_SELF_REFRESH is off, even with ten minutes left", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 10 * 60);
    const originalBytes = await fs.readFile(credentialsPath, "utf8");
    const refresh = vi.fn(async () => ({ ok: true as const, expiresAt: NOW_SEC + 3600, refreshed: true as const }));
    const recordExpiry = vi.fn(async () => undefined);
    const { handle } = makeHandle({ credentialsPath, env: {}, deps: { refresh, recordExpiry } });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(refresh).not.toHaveBeenCalled();
    expect(recordExpiry).not.toHaveBeenCalled();
    expect(await fs.readFile(credentialsPath, "utf8")).toBe(originalBytes);
    handle.stop();
  });

  it("does not refresh a token that still has more than an hour left", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 2 * 3600);
    const refresh = vi.fn(async () => ({ ok: true as const, expiresAt: NOW_SEC + 7200, refreshed: true as const }));
    const { handle } = makeHandle({ credentialsPath, env: SELF_REFRESH_ENV, deps: { refresh } });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(refresh).not.toHaveBeenCalled();
    handle.stop();
  });

  it("refreshes inside the last hour, backs the file up and records the success", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const fetchImpl = vi.fn(async () => jsonResponse(200, {
      access_token: "new-access-token-secret",
      refresh_token: "new-refresh-token-secret",
      token_type: "Bearer",
      expires_in: 3600
    }));
    vi.stubGlobal("fetch", fetchImpl);

    const { handle } = makeHandle({ credentialsPath, env: SELF_REFRESH_ENV });
    expect(await handle.tick()).toBe<KeepaliveTickResult>("refreshed");

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const credentials = JSON.parse(await fs.readFile(credentialsPath, "utf8"));
    expect(credentials.expires_at).toBe(NOW_SEC + 3600);
    expect(credentials.access_token).toBe("new-access-token-secret");
    expect((await fs.stat(credentialsPath)).mode & 0o777).toBe(0o600);

    // The backup is the refreshed file, so a later destructive CLI refresh is recoverable.
    const backupBytes = await fs.readFile(backupPathFor(credentialsPath));
    expect(backupBytes).toEqual(await fs.readFile(credentialsPath));
    expect((await fs.stat(backupPathFor(credentialsPath))).mode & 0o777).toBe(0o600);

    const state = await readProviderAuthState(statePath);
    expect(state.lastSuccessAt).not.toBeNull();
    expect(state.lastAuthErrorAt).toBeNull();
    handle.stop();
  });

  it("waits for the credential lock and never refreshes concurrently with it", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const events: string[] = [];
    let releaseLock: (() => void) | null = null;
    const held = withCredentialLock(async () => {
      events.push("lock-start");
      await new Promise<void>((resolve) => {
        releaseLock = resolve;
      });
      events.push("lock-end");
    });
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: {
        refresh: async () => {
          events.push("refresh");
          await writeCredentials(credentialsPath, NOW_SEC + 3600);
          return { ok: true, expiresAt: NOW_SEC + 3600, refreshed: true };
        }
      }
    });

    const tickPromise = handle.tick();
    await flush();
    // Still queued behind the held lock: no refresh may have started.
    expect(events).toEqual(["lock-start"]);
    expect(JSON.parse(await fs.readFile(credentialsPath, "utf8")).expires_at).toBe(NOW_SEC + 30 * 60);

    releaseLock?.();
    await held;
    expect(await tickPromise).toBe<KeepaliveTickResult>("refreshed");
    expect(events).toEqual(["lock-start", "lock-end", "refresh"]);
    handle.stop();
  });

  it("re-reads the credential inside the lock and skips a job that already rotated it", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const refresh = vi.fn(async () => ({ ok: true as const, expiresAt: NOW_SEC + 7200, refreshed: true as const }));
    let releaseLock: (() => void) | null = null;
    const held = withCredentialLock(async () => {
      await new Promise<void>((resolve) => {
        releaseLock = resolve;
      });
      // A CLI job rotated the credential while the tick waited for the lock.
      await writeCredentials(credentialsPath, NOW_SEC + 7200);
    });
    const { handle } = makeHandle({ credentialsPath, env: SELF_REFRESH_ENV, deps: { refresh } });

    const tickPromise = handle.tick();
    await flush();
    releaseLock?.();
    await held;

    expect(await tickPromise).toBe<KeepaliveTickResult>("skipped");
    expect(refresh).not.toHaveBeenCalled();
    expect(JSON.parse(await fs.readFile(credentialsPath, "utf8")).expires_at).toBe(NOW_SEC + 7200);
    handle.stop();
  });

  it("tries to refresh an already expired token when self-refresh is on", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 5 * 60);
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: {
        refresh: async () => {
          await writeCredentials(credentialsPath, NOW_SEC + 3600);
          return { ok: true, expiresAt: NOW_SEC + 3600, refreshed: true };
        }
      }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refreshed");
    expect(JSON.parse(await fs.readFile(credentialsPath, "utf8")).expires_at).toBe(NOW_SEC + 3600);
    handle.stop();
  });

  it("leaves the credential byte-for-byte intact and alerts once when the refresh is rejected", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const before = await fs.readFile(credentialsPath);
    const alertFetch = vi.fn(async () => jsonResponse(200, { ok: true }));
    vi.stubGlobal("fetch", alertFetch);
    let nowMs = NOW_MS;
    const refresh = vi.fn(async () => ({ ok: false as const, reason: "invalid_grant" }));
    const { handle } = makeHandle({
      credentialsPath,
      env: { ...SELF_REFRESH_ENV, ALERT_WEBHOOK_URL: "https://alerts.test/hook" },
      now: () => nowMs,
      deps: { refresh }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect(await fs.readFile(credentialsPath)).toEqual(before);

    const state = await readProviderAuthState(statePath);
    expect(state.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
    expect(state.lastAuthErrorReason).toBe("refresh_invalid_grant");
    // Permanent failures debounce under their own key so a transient alert cannot hide them.
    expect(state.lastAlertKey).toBe("degraded:refresh_failed_permanent");

    expect(alertFetch).toHaveBeenCalledTimes(1);
    const [url, init] = alertFetch.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://alerts.test/hook");
    const body = JSON.parse(String(init.body));
    expect(body).toMatchObject({ event: "provider_auth", status: "degraded", state: "refresh_failed_permanent" });
    expect(body.expiresInSec).toBe(30 * 60);
    expect(String(init.body)).not.toContain("secret-refresh");

    // A dead refresh token is not retried on the next tick: one hour of backoff.
    nowMs = NOW_MS + 15 * MINUTE;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(alertFetch).toHaveBeenCalledTimes(1);

    nowMs = NOW_MS + 61 * MINUTE;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect(refresh).toHaveBeenCalledTimes(2);
    // The alert stays debounced even though the retry failed again.
    expect(alertFetch).toHaveBeenCalledTimes(1);
    handle.stop();
  });

  it("retries a transient failure on the next tick without extra backoff", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const before = await fs.readFile(credentialsPath);
    let nowMs = NOW_MS;
    const refresh = vi.fn(async () => ({ ok: false as const, reason: "write_error" }));
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      now: () => nowMs,
      deps: { refresh }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect(await fs.readFile(credentialsPath)).toEqual(before);
    const state = await readProviderAuthState(statePath);
    expect(state.lastAuthErrorReason).toBe("refresh_write_error");

    nowMs = NOW_MS + 15 * MINUTE;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect(refresh).toHaveBeenCalledTimes(2);
    handle.stop();
  });

  it("lets a permanent alert through even after a transient alert was just sent", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 55 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const alertFetch = vi.fn(async () => jsonResponse(200, { ok: true }));
    vi.stubGlobal("fetch", alertFetch);
    let nowMs = NOW_MS;
    const refresh = vi.fn(async () => ({ ok: false as const, reason: "network_error" }));
    const { handle } = makeHandle({
      credentialsPath,
      env: { ...SELF_REFRESH_ENV, ALERT_WEBHOOK_URL: "https://alerts.test/hook" },
      now: () => nowMs,
      deps: { refresh }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect((await readProviderAuthState(statePath)).lastAlertKey).toBe("degraded:refresh_failed");

    // The refresh token turns out to be dead while the transient alert is still debounced: the
    // operator must still be told, because this one needs a re-login.
    refresh.mockResolvedValue({ ok: false, reason: "invalid_grant" });
    nowMs = NOW_MS + 15 * MINUTE;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");

    expect(alertFetch).toHaveBeenCalledTimes(2);
    const states = alertFetch.mock.calls.map(([, init]) => JSON.parse(String((init as RequestInit).body)).state);
    expect(states).toEqual(["refresh_failed", "refresh_failed_permanent"]);
    expect((await readProviderAuthState(statePath)).lastAlertKey).toBe("degraded:refresh_failed_permanent");
    handle.stop();
  });

  it("keeps a refresh successful when only the backup fails", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const warn = vi.spyOn(logger, "warn");
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: {
        refresh: async () => {
          await writeCredentials(credentialsPath, NOW_SEC + 3600);
          return { ok: true, expiresAt: NOW_SEC + 3600, refreshed: true };
        },
        backup: async () => {
          throw new Error("volume full");
        }
      }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refreshed");
    // Not a failure: no degraded state, no alert, and the refreshed file stays.
    const state = await readProviderAuthState(statePath);
    expect(state.lastAuthErrorAt).toBeNull();
    expect(state.lastSuccessAt).not.toBeNull();
    expect(warn).toHaveBeenCalledWith(
      { message: "volume full" },
      "higgsfield credential was refreshed but could not be backed up"
    );
    expect(JSON.parse(await fs.readFile(credentialsPath, "utf8")).expires_at).toBe(NOW_SEC + 3600);
    handle.stop();
  });

  it("clears a credential error on success but never an unrelated job auth failure", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const statePath = providerAuthStatePathFor(credentialsPath);
    const refresh = async () => {
      await writeCredentials(credentialsPath, NOW_SEC + 3600);
      return { ok: true as const, expiresAt: NOW_SEC + 3600, refreshed: true as const };
    };

    // 1. A job-side CLI auth failure is not ours to clear.
    await recordProviderAuthFailure({ statePath, reason: "cli_auth_failure", nowMs: NOW_MS - 60_000 });
    const jobFailure = makeHandle({ credentialsPath, env: SELF_REFRESH_ENV, deps: { refresh } });
    expect(await jobFailure.handle.tick()).toBe<KeepaliveTickResult>("refreshed");
    const afterRefresh = await readProviderAuthState(statePath);
    expect(afterRefresh.lastAuthErrorReason).toBe("cli_auth_failure");
    expect(afterRefresh.lastSuccessAt).toBeNull();
    jobFailure.handle.stop();

    // 2. Our own refresh/expiry error (and "expired") is cleared.
    await recordProviderAuthFailure({ statePath, reason: "refresh_network_error", nowMs: NOW_MS });
    const gitRefreshed = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      now: () => NOW_MS + MINUTE,
      deps: { refresh }
    });
    expect(await gitRefreshed.handle.tick()).toBe<KeepaliveTickResult>("refreshed");
    const cleared = await readProviderAuthState(statePath);
    expect(cleared.lastAuthErrorAt).toBeNull();
    expect(cleared.lastAuthErrorReason).toBeNull();
    expect(cleared.lastSuccessAt).toBe(new Date(NOW_MS + MINUTE).toISOString());
    gitRefreshed.handle.stop();
  });

  it("does not lose the rotated token when the real writer cannot store it", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const dir = path.dirname(credentialsPath);
    const statePath = await makeStatePath();
    const before = await fs.readFile(credentialsPath);
    // Clerk answers 200 and rotates the token; every local write then fails.
    const fetchImpl = vi.fn(async () => {
      await fs.chmod(dir, 0o500);
      return jsonResponse(200, {
        access_token: "new-access-token-secret",
        refresh_token: "new-refresh-token-secret",
        expires_in: 3600
      });
    });
    vi.stubGlobal("fetch", fetchImpl);
    let nowMs = NOW_MS;
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      now: () => nowMs,
      deps: {
        statePath,
        refresh: (innerPath: string) =>
          refreshCredentials({ credentialsPath: innerPath, now: () => NOW_MS, writeRetryDelayMs: 5 })
      }
    });

    try {
      expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
      expect(await fs.readFile(credentialsPath)).toEqual(before);
      const state = await readProviderAuthState(statePath);
      expect(state.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
      expect(state.lastAuthErrorReason).toBe("refresh_write_error_after_rotation");
      expect(fetchImpl).toHaveBeenCalledTimes(1);
    } finally {
      await fs.chmod(dir, 0o700).catch(() => undefined);
    }

    // Permanent: the next tick does not POST the stale refresh token again.
    nowMs = NOW_MS + 15 * MINUTE;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    handle.stop();
  });

  it("does not contact the provider when the credential directory is not writable", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const dir = path.dirname(credentialsPath);
    const statePath = await makeStatePath();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => jsonResponse(200, { access_token: "new", expires_in: 3600 }));
    vi.stubGlobal("fetch", fetchImpl);
    await fs.chmod(dir, 0o500);

    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: {
        statePath,
        refresh: (innerPath: string) => refreshCredentials({ credentialsPath: innerPath, now: () => NOW_MS })
      }
    });

    try {
      expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
      const state = await readProviderAuthState(statePath);
      expect(state.lastAuthErrorReason).toBe("refresh_write_error");
      // Pre-flight probe only: nothing was sent, so nothing could be rotated.
      expect(fetchImpl).not.toHaveBeenCalled();
      expect(await fs.readFile(credentialsPath)).toEqual(before);
    } finally {
      await fs.chmod(dir, 0o700).catch(() => undefined);
    }
    handle.stop();
  });

  it("reports a timed-out token request as a network failure and keeps the credential", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 30 * 60);
    const before = await fs.readFile(credentialsPath);
    // A socket that never answers: the request must give up and report a transient network error.
    vi.stubGlobal("fetch", () => new Promise<Response>(() => undefined));

    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: {
        refresh: (innerPath: string) => refreshCredentials({ credentialsPath: innerPath, now: () => NOW_MS, timeoutMs: 20 })
      }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");
    expect(await fs.readFile(credentialsPath)).toEqual(before);
    expect((await readProviderAuthState(providerAuthStatePathFor(credentialsPath))).lastAuthErrorReason)
      .toBe("refresh_network_error");
    handle.stop();
  });

  it("stays degraded for the health endpoint after a refresh failure", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 5 * 60);
    const { handle } = makeHandle({
      credentialsPath,
      env: SELF_REFRESH_ENV,
      deps: { refresh: async () => ({ ok: false, reason: "invalid_credentials" }) }
    });
    expect(await handle.tick()).toBe<KeepaliveTickResult>("refresh_failed");

    const health = await evaluateProviderAuthHealth({
      env: { HIGGSFIELD_CREDENTIALS_PATH: credentialsPath },
      now: () => NOW_MS,
      logger: { error: vi.fn(), warn: vi.fn() },
      dispatchAlert: vi.fn(async () => true)
    });
    expect(health.lastAuthError?.reason).toBe("refresh_invalid_credentials");
    expect(overallStatusFor(health)).toBe("degraded");
    handle.stop();
  });
});
