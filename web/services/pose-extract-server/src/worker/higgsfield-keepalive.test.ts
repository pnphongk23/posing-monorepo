import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { EventEmitter } from "node:events";

import { HiggsfieldCliProvider } from "../services/higgsfieldCliProvider";
import { backupPathFor } from "../services/higgsfieldCredentialGuard";
import { providerAuthStatePathFor, readProviderAuthState } from "../services/providerAuthStateFile";
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
  tryCheckAccountStatus?: () => Promise<{ ok: boolean; authFailure: boolean } | null>;
  env?: Record<string, string | undefined>;
  now?: () => number;
}) {
  const tryCheckAccountStatus = options.tryCheckAccountStatus ?? vi.fn(async () => ({ ok: true, authFailure: false }));
  const handle = startHiggsfieldKeepalive({
    credentialsPath: options.credentialsPath,
    tryCheckAccountStatus,
    env: options.env ?? {},
    now: options.now ?? (() => NOW_MS)
  });
  return { handle, tryCheckAccountStatus };
}

afterEach(async () => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("higgsfield keepalive", () => {
  it("does not call the CLI while the token still has plenty of time", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC + 3600);
    const { handle, tryCheckAccountStatus } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(tryCheckAccountStatus).not.toHaveBeenCalled();
    handle.stop();
  });

  it("checks once when the token is expired and nothing else is running", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle, tryCheckAccountStatus } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("detected");
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);
    handle.stop();
  });

  it("stays quiet until the token has actually expired", async () => {
    // Ten minutes left is still a live token: the detector must not touch it before expires_at.
    const credentialsPath = await makeCredentials(NOW_SEC + 600);
    const { handle, tryCheckAccountStatus } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(tryCheckAccountStatus).not.toHaveBeenCalled();
    handle.stop();
  });

  it("never writes or restores the credential file", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const originalBytes = await fs.readFile(credentialsPath, "utf8");
    const provider = new HiggsfieldCliProvider({
      spawnImpl: vi.fn(() => {
        // The CLI deletes the file when a refresh fails; the detector must not put it back.
        fs.rm(credentialsPath).catch(() => undefined);
        const child = new EventEmitter() as EventEmitter & {
          stdout: EventEmitter;
          stderr: EventEmitter;
          kill: ReturnType<typeof vi.fn>;
        };
        child.stdout = new EventEmitter();
        child.stderr = new EventEmitter();
        child.kill = vi.fn();
        queueMicrotask(() => {
          child.stderr.emit("data", Buffer.from("Error: Session expired."));
          child.emit("close", 2);
        });
        return child;
      }) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/hf-keepalive-no-write",
      credentialsPath
    });

    const handle = startHiggsfieldKeepalive({
      credentialsPath,
      tryCheckAccountStatus: () => provider.tryCheckAccountStatus(),
      env: {},
      now: () => NOW_MS
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("auth_failed");

    // Backup is still taken before the call, but the credential itself is left exactly as the CLI
    // left it: no restore, no rewrite.
    await expect(fs.stat(backupPathFor(credentialsPath))).resolves.toBeTruthy();
    await expect(fs.stat(credentialsPath)).rejects.toThrow();
    await expect(fs.readFile(credentialsPath, "utf8")).rejects.toThrow();
    expect(originalBytes).toContain("secret-refresh");
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
    handle.stop();
  });

  it("skips the tick while a job holds the credential lock", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle, tryCheckAccountStatus } = makeHandle({
      credentialsPath,
      tryCheckAccountStatus: vi.fn(async () => null)
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("busy");
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);
    handle.stop();
  });

  it("does nothing when HIGGSFIELD_KEEPALIVE is off", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle, tryCheckAccountStatus } = makeHandle({
      credentialsPath,
      env: { HIGGSFIELD_KEEPALIVE: "0" }
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("disabled");
    expect(tryCheckAccountStatus).not.toHaveBeenCalled();
    handle.stop();
  });

  it("never spawns when the credential file is missing", async () => {
    const credentialsPath = await makeCredentials(null);
    const { handle, tryCheckAccountStatus } = makeHandle({ credentialsPath });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(tryCheckAccountStatus).not.toHaveBeenCalled();
    handle.stop();
  });

  it("backs off for an hour after an auth failure", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    let nowMs = NOW_MS;
    const { handle, tryCheckAccountStatus } = makeHandle({
      credentialsPath,
      tryCheckAccountStatus: vi.fn(async () => ({ ok: false, authFailure: true })),
      now: () => nowMs
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("auth_failed");
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);

    nowMs = NOW_MS + 15 * 60 * 1000;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("skipped");
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);

    nowMs = NOW_MS + 61 * 60 * 1000;
    expect(await handle.tick()).toBe<KeepaliveTickResult>("auth_failed");
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(2);
    handle.stop();
  });

  it("treats a network failure as a retryable failure, not an auth failure", async () => {
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const { handle } = makeHandle({
      credentialsPath,
      tryCheckAccountStatus: vi.fn(async () => ({ ok: false, authFailure: false }))
    });

    expect(await handle.tick()).toBe<KeepaliveTickResult>("failed");
    handle.stop();
  });

  it("runs on its own timer and stops cleanly", async () => {
    vi.useFakeTimers();
    const credentialsPath = await makeCredentials(NOW_SEC - 60);
    const tryCheckAccountStatus = vi.fn(async () => ({ ok: true, authFailure: false }));
    const handle = startHiggsfieldKeepalive({
      credentialsPath,
      tryCheckAccountStatus,
      env: {},
      now: () => NOW_MS,
      intervalMs: 1000,
      // Fake timers must not wait on real filesystem I/O.
      readSnapshot: async () => ({ state: "expired", expiresInSec: -60, expiresAtSec: NOW_SEC - 60, mtimeMs: 0 })
    });

    await vi.advanceTimersByTimeAsync(1000);
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);

    handle.stop();
    await vi.advanceTimersByTimeAsync(5000);
    expect(tryCheckAccountStatus).toHaveBeenCalledTimes(1);
  });
});
