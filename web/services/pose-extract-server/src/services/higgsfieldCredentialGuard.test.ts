import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  EXPIRING_SOON_SEC,
  backupCredential,
  backupPathFor,
  defaultCredentialsPath,
  readCredentialSnapshot,
  restoreCredential,
  withCredentialLock
} from "./higgsfieldCredentialGuard";

const NOW_MS = 1_800_000_000_000;
const NOW_SEC = Math.floor(NOW_MS / 1000);

const tempDirs: string[] = [];

async function makeTempDir(): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-guard-"));
  tempDirs.push(dir);
  return dir;
}

async function writeCredential(
  credentialsPath: string,
  expiresAtSec: number | null,
  extra: Record<string, unknown> = {}
): Promise<void> {
  await fs.mkdir(path.dirname(credentialsPath), { recursive: true });
  const payload =
    expiresAtSec === null
      ? { access_token: "super-secret-token", refresh_token: "super-secret-refresh" }
      : {
          access_token: "super-secret-token",
          refresh_token: "super-secret-refresh",
          token_type: "Bearer",
          expires_in: 3600,
          expires_at: expiresAtSec,
          scope: "openid",
          auth_version: 2,
          ...extra
        };
  await fs.writeFile(credentialsPath, JSON.stringify(payload), { mode: 0o600 });
}

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("readCredentialSnapshot", () => {
  it("reports ok with the remaining seconds when the token lives longer than a day", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + EXPIRING_SOON_SEC + 3600);

    const snapshot = await readCredentialSnapshot(credentialsPath, NOW_MS);

    expect(snapshot.state).toBe("ok");
    expect(snapshot.expiresInSec).toBe(EXPIRING_SOON_SEC + 3600);
  });

  it("reports expiring_soon below the 24h window", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 60);

    const snapshot = await readCredentialSnapshot(credentialsPath, NOW_MS);

    expect(snapshot.state).toBe("expiring_soon");
    expect(snapshot.expiresInSec).toBe(60);
  });

  it("reports expired with a negative remaining time", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC - 120);

    const snapshot = await readCredentialSnapshot(credentialsPath, NOW_MS);

    expect(snapshot.state).toBe("expired");
    expect(snapshot.expiresInSec).toBe(-120);
  });

  it("reports missing when the file does not exist", async () => {
    const dir = await makeTempDir();

    const snapshot = await readCredentialSnapshot(path.join(dir, "credentials.json"), NOW_MS);

    expect(snapshot.state).toBe("missing");
    expect(snapshot.expiresInSec).toBeNull();
  });

  it("reports invalid for unparseable JSON", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await fs.writeFile(credentialsPath, "not-json", { mode: 0o600 });

    const snapshot = await readCredentialSnapshot(credentialsPath, NOW_MS);

    expect(snapshot.state).toBe("invalid");
    expect(snapshot.expiresInSec).toBeNull();
  });

  it("reports invalid when expires_at is missing or not an epoch number", async () => {
    const dir = await makeTempDir();
    const withoutExpiry = path.join(dir, "no-expiry.json");
    const stringExpiry = path.join(dir, "string-expiry.json");
    await writeCredential(withoutExpiry, null);
    await fs.writeFile(
      stringExpiry,
      JSON.stringify({ access_token: "t", expires_at: "2099-01-01T00:00:00Z" }),
      { mode: 0o600 }
    );

    expect((await readCredentialSnapshot(withoutExpiry, NOW_MS)).state).toBe("invalid");
    expect((await readCredentialSnapshot(stringExpiry, NOW_MS)).state).toBe("invalid");
  });

  it("never returns token material", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 3600);

    const snapshot = await readCredentialSnapshot(credentialsPath, NOW_MS);

    expect(JSON.stringify(snapshot)).not.toContain("super-secret");
  });
});

describe("defaultCredentialsPath", () => {
  it("prefers HIGGSFIELD_CREDENTIALS_PATH", () => {
    expect(defaultCredentialsPath({ HIGGSFIELD_CREDENTIALS_PATH: "/app/higgsfield/credentials.json" })).toBe(
      "/app/higgsfield/credentials.json"
    );
  });

  it("falls back to $HOME/.config/higgsfield/credentials.json", () => {
    const resolved = defaultCredentialsPath({ HOME: "/home/tester" });

    expect(resolved).toBe(path.join("/home/tester", ".config", "higgsfield", "credentials.json"));
  });
});

describe("backupCredential", () => {
  it("writes an atomic 0600 copy next to the credential file", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 7200);

    const result = await backupCredential({ credentialsPath, nowMs: NOW_MS });

    expect(result.written).toBe(true);
    const backupPath = backupPathFor(credentialsPath);
    expect((await fs.stat(backupPath)).mode & 0o777).toBe(0o600);
    expect(JSON.parse(await fs.readFile(backupPath, "utf8")).expires_at).toBe(NOW_SEC + 7200);
    const leftovers = (await fs.readdir(path.dirname(backupPath))).filter((name) => name.includes(".tmp."));
    expect(leftovers).toEqual([]);
  });

  it("does not overwrite the backup with an invalid or older credential", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 7200);
    await backupCredential({ credentialsPath, nowMs: NOW_MS });

    // Older expiry: keep the existing backup.
    await writeCredential(credentialsPath, NOW_SEC + 60);
    expect((await backupCredential({ credentialsPath, nowMs: NOW_MS })).written).toBe(false);

    // Unparseable: keep the existing backup.
    await fs.writeFile(credentialsPath, "not-json", { mode: 0o600 });
    expect((await backupCredential({ credentialsPath, nowMs: NOW_MS })).written).toBe(false);

    expect(JSON.parse(await fs.readFile(backupPathFor(credentialsPath), "utf8")).expires_at).toBe(NOW_SEC + 7200);
  });

  it("overwrites the backup when the credential is newer", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 7200);
    await backupCredential({ credentialsPath, nowMs: NOW_MS });

    await writeCredential(credentialsPath, NOW_SEC + 86400);
    expect((await backupCredential({ credentialsPath, nowMs: NOW_MS })).written).toBe(true);
    expect(JSON.parse(await fs.readFile(backupPathFor(credentialsPath), "utf8")).expires_at).toBe(NOW_SEC + 86400);
  });
});

describe("restoreCredential", () => {
  it("restores the backup with 0600 when the CLI deleted the credential", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 7200);
    await backupCredential({ credentialsPath, nowMs: NOW_MS });

    await fs.rm(credentialsPath);

    expect(await restoreCredential({ credentialsPath })).toBe(true);
    expect((await fs.stat(credentialsPath)).mode & 0o777).toBe(0o600);
    expect(JSON.parse(await fs.readFile(credentialsPath, "utf8")).refresh_token).toBe("super-secret-refresh");
  });

  it("does nothing when the credential still exists or no backup was taken", async () => {
    const dir = await makeTempDir();
    const credentialsPath = path.join(dir, "credentials.json");
    await writeCredential(credentialsPath, NOW_SEC + 7200);

    expect(await restoreCredential({ credentialsPath })).toBe(false);

    await fs.rm(credentialsPath);
    expect(await restoreCredential({ credentialsPath })).toBe(false);
  });
});

describe("withCredentialLock", () => {
  it("serialises concurrent callers", async () => {
    const events: string[] = [];
    const task = (name: string, delayMs: number) => async () => {
      events.push(`${name}:start`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      events.push(`${name}:end`);
      return name;
    };

    const [first, second] = await Promise.all([
      withCredentialLock(task("first", 30)),
      withCredentialLock(task("second", 5))
    ]);

    expect(first).toBe("first");
    expect(second).toBe("second");
    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
  });

  it("keeps running after a rejected task", async () => {
    await expect(withCredentialLock(async () => Promise.reject(new Error("boom")))).rejects.toThrow("boom");
    await expect(withCredentialLock(async () => "next")).resolves.toBe("next");
  });
});
