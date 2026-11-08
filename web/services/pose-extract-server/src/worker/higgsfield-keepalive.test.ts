import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  evaluateProviderAuthHealth,
  overallStatusFor
} from "../services/providerAuthHealth";
import {
  providerAuthStatePathFor,
  readProviderAuthState,
  recordProviderAuthSuccess
} from "../services/providerAuthStateFile";
import { startHiggsfieldKeepalive, type KeepaliveTickResult } from "./higgsfield-keepalive";

const NOW_MS = 1_800_000_000_000;
const NOW_SEC = Math.floor(NOW_MS / 1000);

const tempDirs: string[] = [];

async function makeCredentials(expiresAtSec: number | null): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-keepalive-"));
  tempDirs.push(dir);
  const credentialsPath = path.join(dir, "credentials.json");
  if (expiresAtSec !== null) {
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
  return credentialsPath;
}

function makeHandle(options: {
  credentialsPath: string;
  env?: Record<string, string | undefined>;
  now?: () => number;
}) {
  const handle = startHiggsfieldKeepalive({
    credentialsPath: options.credentialsPath,
    env: options.env ?? {},
    now: options.now ?? (() => NOW_MS)
  });
  return { handle };
}

afterEach(async () => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
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
