import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import { runRefresh } from "../../scripts/hf-self-refresh.mjs";

const tempDirs: string[] = [];
const servers: http.Server[] = [];

async function makeDir() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "hf-one-off-"));
  tempDirs.push(dir);
  return dir;
}

afterEach(async () => {
  vi.restoreAllMocks();
  await Promise.all(servers.splice(0).map((server) => new Promise<void>((resolve) => server.close(() => resolve()))));
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

function useShortTimeoutSignal() {
  return vi.spyOn(AbortSignal, "timeout").mockImplementation((() => {
    const controller = new AbortController();
    setTimeout(() => controller.abort(new DOMException("Timed out", "TimeoutError")), 20);
    return controller.signal;
  }) as typeof AbortSignal.timeout);
}

describe("one-off self-refresh script", () => {
  it("uses a local mock token endpoint and writes only the output credentials file with mode 0600", async () => {
    const requests: Array<{ method: string | undefined; contentType: string | undefined; body: string }> = [];
    const server = http.createServer((request, response) => {
      const chunks: Buffer[] = [];
      request.on("data", (chunk: Buffer) => chunks.push(chunk));
      request.on("end", () => {
        requests.push({
          method: request.method,
          contentType: request.headers["content-type"],
          body: Buffer.concat(chunks).toString("utf8")
        });
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify({
          access_token: "mock-access-token-secret",
          refresh_token: "mock-refresh-token-secret",
          token_type: "NewType",
          scope: "new-scope",
          expires_in: 600
        }));
      });
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("mock server failed to bind");

    const dir = await makeDir();
    const inputPath = path.join(dir, "in.json");
    const outputPath = path.join(dir, "out.json");
    const input = {
      access_token: "old-access-token-secret",
      refresh_token: "old-refresh-token-secret",
      token_type: "OldType",
      scope: "old-scope",
      expires_at: 1,
      auth_version: 1,
      workspace_id: "workspace-test"
    };
    await fs.writeFile(inputPath, JSON.stringify(input), { mode: 0o600 });
    const before = await fs.readFile(inputPath);
    const now = 1_800_000_000_000;

    const result = await runRefresh({
      inputPath,
      outputPath,
      tokenEndpoint: `http://127.0.0.1:${address.port}/oauth/token`,
      now: () => now
    });

    expect(result).toEqual({ ok: true, expiresAt: Math.floor(now / 1000) + 600 });
    expect(requests).toHaveLength(1);
    expect(requests[0]?.method).toBe("POST");
    expect(requests[0]?.contentType).toContain("application/x-www-form-urlencoded");
    expect(Object.fromEntries(new URLSearchParams(requests[0]?.body))).toEqual({
      grant_type: "refresh_token",
      refresh_token: "old-refresh-token-secret",
      client_id: "sRGCQJvvJkPrrtRj"
    });
    expect(await fs.readFile(inputPath)).toEqual(before);
    expect(JSON.parse(await fs.readFile(outputPath, "utf8"))).toMatchObject({
      ...input,
      access_token: "mock-access-token-secret",
      refresh_token: "mock-refresh-token-secret",
      token_type: "OldType",
      scope: "old-scope",
      expires_at: Math.floor(now / 1000) + 600
    });
    expect((await fs.stat(outputPath)).mode & 0o777).toBe(0o600);
  });

  it("does not print token material in the returned failure reason", async () => {
    const dir = await makeDir();
    const inputPath = path.join(dir, "in.json");
    const outputPath = path.join(dir, "out.json");
    await fs.writeFile(inputPath, JSON.stringify({
      access_token: "access-token-secret",
      refresh_token: "refresh-token-secret",
      expires_at: 1
    }));

    const result = await runRefresh({
      inputPath,
      outputPath,
      tokenEndpoint: "http://127.0.0.1:1/oauth/token"
    });

    expect(result).toEqual({ ok: false, reason: "network_error" });
    expect(JSON.stringify(result)).not.toContain("refresh-token-secret");
    await expect(fs.access(outputPath)).rejects.toMatchObject({ code: "ENOENT" });
  });

  it("refuses to use the same path for input and output", async () => {
    const dir = await makeDir();
    const credentialsPath = path.join(dir, "credentials.json");
    const input = JSON.stringify({ access_token: "mock-access", refresh_token: "mock-refresh", expires_at: 1 });
    await fs.writeFile(credentialsPath, input, { mode: 0o600 });
    const fetchImpl = async () => {
      throw new Error("must not make a request");
    };

    const result = await runRefresh({
      inputPath: credentialsPath,
      outputPath: credentialsPath,
      fetchImpl
    });

    expect(result).toEqual({ ok: false, reason: "invalid_paths" });
    expect(await fs.readFile(credentialsPath, "utf8")).toBe(input);
  });

  it("returns FAIL timeout for a hanging request without creating output", async () => {
    const timeoutSpy = useShortTimeoutSignal();
    const dir = await makeDir();
    const inputPath = path.join(dir, "in.json");
    const outputPath = path.join(dir, "out.json");
    await fs.writeFile(inputPath, JSON.stringify({ access_token: "a", refresh_token: "r", expires_at: 1 }));
    const fetchImpl = vi.fn((_url: string, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal?.reason), { once: true });
    }));

    const result = await Promise.race([
      runRefresh({ inputPath, outputPath, fetchImpl }),
      new Promise<"hung">((resolve) => setTimeout(() => resolve("hung"), 500))
    ]);

    expect(result).toEqual({ ok: false, reason: "timeout" });
    expect(timeoutSpy).toHaveBeenCalledWith(20_000);
    expect(await fs.readdir(dir)).toEqual(["in.json"]);
  });

  it("applies the same timeout while reading the token response body", async () => {
    useShortTimeoutSignal();
    const dir = await makeDir();
    const inputPath = path.join(dir, "in.json");
    const outputPath = path.join(dir, "out.json");
    await fs.writeFile(inputPath, JSON.stringify({ access_token: "a", refresh_token: "r", expires_at: 1 }));
    const hangingBody = new ReadableStream({ start() {} });
    const fetchImpl = async () => new Response(hangingBody, { status: 200 });

    const result = await Promise.race([
      runRefresh({ inputPath, outputPath, fetchImpl }),
      new Promise<"hung">((resolve) => setTimeout(() => resolve("hung"), 500))
    ]);

    expect(result).toEqual({ ok: false, reason: "timeout" });
    expect(await fs.readdir(dir)).toEqual(["in.json"]);
  });
});
