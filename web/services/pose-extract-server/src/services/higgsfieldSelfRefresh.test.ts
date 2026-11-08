import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import { isHiggsfieldSelfRefreshEnabled, refreshCredentials } from "./higgsfieldSelfRefresh";

const NOW_MS = 1_800_000_000_000;
const AUTH_URL = "https://clerk.higgsfield.ai/oauth/token";
const CLIENT_ID = "sRGCQJvvJkPrrtRj";

const tempDirs: string[] = [];
const originalEnv = {
  selfRefresh: process.env.HIGGSFIELD_SELF_REFRESH,
  credentialsPath: process.env.HIGGSFIELD_CREDENTIALS_PATH
};

async function makeCredentials(overrides: Record<string, unknown> = {}) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-self-refresh-"));
  tempDirs.push(dir);
  const credentialsPath = path.join(dir, "credentials.json");
  const credentials = {
    access_token: "old-access-token-secret",
    refresh_token: "old-refresh-token-secret",
    token_type: "Bearer",
    expires_at: Math.floor(NOW_MS / 1000) - 1,
    auth_version: 2,
    workspace_id: "workspace-test",
    ...overrides
  };
  await fs.writeFile(credentialsPath, JSON.stringify(credentials), { mode: 0o600 });
  return { credentialsPath, credentials, dir };
}

function response(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

/** Restore directory permissions so cleanup can always delete the temp tree. */
async function makeWritable(dir: string): Promise<void> {
  await fs.chmod(dir, 0o700).catch(() => undefined);
}

afterEach(async () => {
  process.env.HIGGSFIELD_SELF_REFRESH = originalEnv.selfRefresh;
  process.env.HIGGSFIELD_CREDENTIALS_PATH = originalEnv.credentialsPath;
  await Promise.all(
    tempDirs.splice(0).map(async (dir) => {
      await makeWritable(dir);
      await fs.rm(dir, { recursive: true, force: true });
    })
  );
  vi.restoreAllMocks();
});

describe("refreshCredentials", () => {
  it("posts the public-client refresh grant as form-urlencoded without a client secret", async () => {
    const { credentialsPath } = await makeCredentials();
    const fetchImpl = vi.fn(async () => response(200, {
      access_token: "new-access-token-secret",
      refresh_token: "new-refresh-token-secret",
      token_type: "Bearer",
      expires_in: 3600,
      scope: "email profile offline_access"
    }));

    await refreshCredentials({ credentialsPath, fetchImpl, now: () => NOW_MS });

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(AUTH_URL);
    expect(init.method).toBe("POST");
    expect(new Headers(init.headers).get("content-type")).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(String(init.body));
    expect(Object.fromEntries(form.entries())).toEqual({
      grant_type: "refresh_token",
      refresh_token: "old-refresh-token-secret",
      client_id: CLIENT_ID
    });
    expect(String(init.body)).not.toContain("client_secret");
  });

  it("writes a rotated token set atomically in CLI-compatible shape and preserves other fields", async () => {
    const { credentialsPath, credentials } = await makeCredentials();
    const fetchImpl = vi.fn(async () => response(200, {
      access_token: "new-access-token-secret",
      refresh_token: "new-refresh-token-secret",
      token_type: "Bearer",
      expires_in: 3600,
      scope: "email profile offline_access"
    }));

    const result = await refreshCredentials({ credentialsPath, fetchImpl, now: () => NOW_MS });
    const written = JSON.parse(await fs.readFile(credentialsPath, "utf8"));
    const stat = await fs.stat(credentialsPath);

    expect(result).toEqual({ ok: true, expiresAt: Math.floor(NOW_MS / 1000) + 3600, refreshed: true });
    expect(written).toMatchObject({
      ...credentials,
      access_token: "new-access-token-secret",
      refresh_token: "new-refresh-token-secret",
      token_type: "Bearer",
      expires_in: 3600,
      expires_at: Math.floor(NOW_MS / 1000) + 3600,
      scope: "email profile offline_access"
    });
    expect(stat.mode & 0o777).toBe(0o600);
  });

  it("keeps the old refresh token when Clerk omits a rotated one", async () => {
    const { credentialsPath } = await makeCredentials();
    const fetchImpl = vi.fn(async () => response(200, {
      access_token: "new-access-token-secret",
      token_type: "Bearer",
      expires_in: 1800
    }));

    const result = await refreshCredentials({ credentialsPath, fetchImpl, now: () => NOW_MS });
    const written = JSON.parse(await fs.readFile(credentialsPath, "utf8"));

    expect(result.ok).toBe(true);
    expect(written.refresh_token).toBe("old-refresh-token-secret");
  });

  it("preserves the old file on invalid_grant without exposing token data", async () => {
    const { credentialsPath } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => response(400, { error: "invalid_grant" }));

    const result = await refreshCredentials({ credentialsPath, fetchImpl, now: () => NOW_MS });

    expect(result).toEqual({ ok: false, reason: "invalid_grant" });
    expect(await fs.readFile(credentialsPath)).toEqual(before);
    expect(JSON.stringify(result)).not.toContain("old-refresh-token-secret");
  });

  it("preserves the old file on network errors without exposing token data", async () => {
    const { credentialsPath } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => { throw new Error("network failed"); });

    const result = await refreshCredentials({ credentialsPath, fetchImpl, now: () => NOW_MS });

    expect(result).toEqual({ ok: false, reason: "network_error" });
    expect(await fs.readFile(credentialsPath)).toEqual(before);
    expect(JSON.stringify(result)).not.toContain("old-refresh-token-secret");
  });

  it("gives up on a token request that never answers and reports network_error", async () => {
    const { credentialsPath } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    // Neither resolves nor honours the abort signal: the timeout race must still settle.
    const fetchImpl = vi.fn(() => new Promise<Response>(() => undefined));

    const result = await refreshCredentials({
      credentialsPath,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      now: () => NOW_MS,
      timeoutMs: 20
    });

    expect(result).toEqual({ ok: false, reason: "network_error" });
    expect(await fs.readFile(credentialsPath)).toEqual(before);
  });

  it("passes an abort signal so a hung socket is cancelled rather than left open", async () => {
    const { credentialsPath } = await makeCredentials();
    const calls: RequestInit[] = [];
    // Asserting inside the fetch would be swallowed by the network-error catch, so capture instead.
    const fetchImpl = vi.fn(async (_url: string, init: RequestInit) => {
      calls.push(init);
      throw new Error("aborted");
    });

    const result = await refreshCredentials({
      credentialsPath,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      now: () => NOW_MS,
      timeoutMs: 5000
    });

    expect(result).toEqual({ ok: false, reason: "network_error" });
    expect(calls).toHaveLength(1);
    expect(calls[0]?.signal).toBeInstanceOf(AbortSignal);
    expect(calls[0]?.signal?.aborted).toBe(false);
  });

  it("does not contact Clerk when the credential directory cannot be written", async () => {
    const { credentialsPath, dir } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => response(200, { access_token: "new", expires_in: 3600 }));
    await fs.chmod(dir, 0o500);
    try {
      const result = await refreshCredentials({
        credentialsPath,
        fetchImpl: fetchImpl as unknown as typeof fetch,
        now: () => NOW_MS
      });

      expect(result).toEqual({ ok: false, reason: "write_error" });
      // No rotation was risked: the request never left the process.
      expect(fetchImpl).not.toHaveBeenCalled();
      expect(await fs.readFile(credentialsPath)).toEqual(before);
    } finally {
      await makeWritable(dir);
    }
  });

  it("retries the local write when the volume recovers and never re-posts the rotated token", async () => {
    const { credentialsPath, dir } = await makeCredentials();
    const fetchImpl = vi.fn(async () => {
      // The token is rotated from here on: make the write fail once, then recover.
      await fs.chmod(dir, 0o500);
      setTimeout(() => {
        void fs.chmod(dir, 0o700).catch(() => undefined);
      }, 30);
      return response(200, {
        access_token: "new-access-token-secret",
        refresh_token: "new-refresh-token-secret",
        expires_in: 3600
      });
    });

    try {
      const result = await refreshCredentials({
        credentialsPath,
        fetchImpl: fetchImpl as unknown as typeof fetch,
        now: () => NOW_MS,
        writeRetryDelayMs: 150
      });

      expect(result).toEqual({ ok: true, expiresAt: Math.floor(NOW_MS / 1000) + 3600, refreshed: true });
      // Exactly one POST: the retry re-writes from memory, it never goes back to Clerk.
      expect(fetchImpl).toHaveBeenCalledTimes(1);
      const written = JSON.parse(await fs.readFile(credentialsPath, "utf8"));
      expect(written.refresh_token).toBe("new-refresh-token-secret");
      expect(written.expires_at).toBe(Math.floor(NOW_MS / 1000) + 3600);
      expect((await fs.stat(credentialsPath)).mode & 0o777).toBe(0o600);
    } finally {
      await makeWritable(dir);
    }
  });

  it("reports write_error_after_rotation when the rotated token cannot be stored", async () => {
    const { credentialsPath, dir } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => {
      // Rotate, then make every local write attempt fail for the rest of the call.
      await fs.chmod(dir, 0o500);
      return response(200, {
        access_token: "new-access-token-secret",
        refresh_token: "new-refresh-token-secret",
        expires_in: 3600
      });
    });

    try {
      const result = await refreshCredentials({
        credentialsPath,
        fetchImpl: fetchImpl as unknown as typeof fetch,
        now: () => NOW_MS,
        writeRetryDelayMs: 5
      });

      expect(result).toEqual({ ok: false, reason: "write_error_after_rotation" });
      // One POST only: re-posting would burn the already rotated refresh token.
      expect(fetchImpl).toHaveBeenCalledTimes(1);
      expect(await fs.readFile(credentialsPath)).toEqual(before);
      // No probe/temp leftovers from the failed attempts.
      expect((await fs.readdir(dir)).sort()).toEqual(["credentials.json"]);
    } finally {
      await makeWritable(dir);
    }
  });

  it("treats an unreadable 200 body as invalid_response without re-posting", async () => {
    const { credentialsPath } = await makeCredentials();
    const before = await fs.readFile(credentialsPath);
    const fetchImpl = vi.fn(async () => new Response("not-json", { status: 200 }));

    const result = await refreshCredentials({
      credentialsPath,
      fetchImpl: fetchImpl as unknown as typeof fetch,
      now: () => NOW_MS
    });

    expect(result).toEqual({ ok: false, reason: "invalid_response" });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    expect(await fs.readFile(credentialsPath)).toEqual(before);
  });
});

describe("isHiggsfieldSelfRefreshEnabled", () => {
  it("is off by default and off for every value other than 1/true", () => {
    expect(isHiggsfieldSelfRefreshEnabled({})).toBe(false);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "" })).toBe(false);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "0" })).toBe(false);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "false" })).toBe(false);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "yes" })).toBe(false);
  });

  it("accepts 1/true in any casing, ignoring surrounding whitespace", () => {
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "1" })).toBe(true);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "true" })).toBe(true);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: "TRUE" })).toBe(true);
    expect(isHiggsfieldSelfRefreshEnabled({ HIGGSFIELD_SELF_REFRESH: " True " })).toBe(true);
  });
});
