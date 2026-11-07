import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import { maybeSelfRefresh, refreshCredentials } from "./higgsfieldSelfRefresh";

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
  return { credentialsPath, credentials };
}

function response(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}

afterEach(async () => {
  process.env.HIGGSFIELD_SELF_REFRESH = originalEnv.selfRefresh;
  process.env.HIGGSFIELD_CREDENTIALS_PATH = originalEnv.credentialsPath;
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
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
});

describe("maybeSelfRefresh", () => {
  it("is disabled unless HIGGSFIELD_SELF_REFRESH is explicitly enabled", async () => {
    const { credentialsPath } = await makeCredentials();
    process.env.HIGGSFIELD_SELF_REFRESH = "false";
    process.env.HIGGSFIELD_CREDENTIALS_PATH = credentialsPath;
    const fetchImpl = vi.fn();

    const result = await maybeSelfRefresh({ fetchImpl, now: () => NOW_MS });

    expect(result).toEqual({ ok: false, reason: "disabled" });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
