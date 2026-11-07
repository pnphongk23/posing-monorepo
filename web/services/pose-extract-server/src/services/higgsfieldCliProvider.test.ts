import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderTimeoutError
} from "./errors";
import { DEFAULT_EXTRACT_PROMPT } from "./extractPrompt";
import { extractResultUrlFromCliJson, HiggsfieldCliProvider } from "./higgsfieldCliProvider";
import { backupPathFor } from "./higgsfieldCredentialGuard";
import { providerAuthStatePathFor, readProviderAuthState } from "./providerAuthStateFile";
import { logger } from "../utils/logger";

// Every spawn records auth state next to the credential: keep it out of the real $HOME.
const sandboxDirs: string[] = [];
let previousCredentialsPath: string | undefined;
let sandboxCredentialsPath = "";

beforeEach(async () => {
  previousCredentialsPath = process.env.HIGGSFIELD_CREDENTIALS_PATH;
  const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "hf-provider-sandbox-"));
  sandboxDirs.push(dir);
  sandboxCredentialsPath = path.join(dir, "credentials.json");
  process.env.HIGGSFIELD_CREDENTIALS_PATH = sandboxCredentialsPath;
});

afterEach(async () => {
  if (previousCredentialsPath === undefined) {
    delete process.env.HIGGSFIELD_CREDENTIALS_PATH;
  } else {
    process.env.HIGGSFIELD_CREDENTIALS_PATH = previousCredentialsPath;
  }
  await Promise.all(sandboxDirs.splice(0).map((dir) => fs.promises.rm(dir, { recursive: true, force: true })));
});

describe("extractResultUrlFromCliJson", () => {
  it("reads top-level url fields", () => {
    expect(extractResultUrlFromCliJson({ url: "https://example.com/a.png" })).toBe("https://example.com/a.png");
    expect(extractResultUrlFromCliJson({ result_url: "https://example.com/b.png" })).toBe("https://example.com/b.png");
  });

  it("reads result_url from captured gpt_image_2 fixture", () => {
    const fixturePath = path.join(
      path.dirname(fileURLToPath(import.meta.url)),
      "../fixtures/higgsfield-gpt_image_2-success.json"
    );
    const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as unknown[];
    expect(extractResultUrlFromCliJson(fixture)).toBe("https://cdn.example.com/generated/anonymized-pose-cutout.png");
  });

  it("reads nested result url", () => {
    expect(extractResultUrlFromCliJson({ result: { url: "https://example.com/c.png" } })).toBe("https://example.com/c.png");
  });
});

function mockSpawn(stdout: string, stderr = "", exitCode = 0) {
  return vi.fn(() => {
    const child = new EventEmitter() as EventEmitter & {
      stdout: EventEmitter;
      stderr: EventEmitter;
      kill: ReturnType<typeof vi.fn>;
    };
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = vi.fn();

    queueMicrotask(() => {
      if (stdout) child.stdout.emit("data", Buffer.from(stdout));
      if (stderr) child.stderr.emit("data", Buffer.from(stderr));
      child.emit("close", exitCode);
    });

    return child;
  });
}

describe("HiggsfieldCliProvider", () => {
  it("spawns CLI with seedream_v5_lite (no resolution, Seedream quality) and fetches result URL", async () => {
    const spawnImpl = mockSpawn(JSON.stringify({ url: "https://cdn.example.com/out.png" }));
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: { get: () => "image/png" },
      arrayBuffer: async () => Uint8Array.from([1, 2, 3]).buffer
    });

    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: fetchImpl as typeof fetch,
      tmpDir: "/tmp/higgsfield-test",
      credentialsPath: "/tmp/creds.json",
      timeoutMs: 5_000
    });

    const result = await provider.extractPoseImage({
      sourceImageBase64: Buffer.from("source").toString("base64"),
      sourceMimeType: "image/png"
    });

    expect(spawnImpl).toHaveBeenCalled();
    const [, args] = spawnImpl.mock.calls[0] as [string, string[]];
    expect(args).toContain("seedream_v5_lite");
    expect(args).toContain("--prompt");
    expect(args).toContain(DEFAULT_EXTRACT_PROMPT);
    expect(args).toContain("--quality");
    expect(args).toContain("high");
    expect(args).not.toContain("--resolution");
    expect(args).toContain("--wait");
    expect(args).toContain("--wait-timeout");
    expect(args).toContain("9m");
    expect(args).toContain("--json");
    expect(fetchImpl).toHaveBeenCalledWith("https://cdn.example.com/out.png");
    expect(result.mimeType).toBe("image/png");
    expect(result.imageBase64).toBe(Buffer.from([1, 2, 3]).toString("base64"));
  });

  it("keeps GPT-style quality medium for globally-set GPT model", async () => {
    const spawnImpl = mockSpawn(JSON.stringify({ url: "https://cdn.example.com/out.png" }));
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true, status: 200, headers: { get: () => "image/png" }, arrayBuffer: async () => Uint8Array.from([1]).buffer
    });
    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: fetchImpl as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-gpt",
      model: "openai_hazel"
    });
    await provider.extractPoseImage({ sourceImageBase64: Buffer.from("s").toString("base64"), sourceMimeType: "image/png" });
    const [, args] = spawnImpl.mock.calls[0] as [string, string[]];
    expect(args).toContain("--quality");
    expect(args).toContain("medium");
    expect(args).not.toContain("--aspect-ratio");
  });

  it("adds --aspect-ratio matching the source image for seedream_v5_lite", async () => {
    const spawnImpl = mockSpawn(JSON.stringify({ url: "https://cdn.example.com/out.png" }));
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true, status: 200, headers: { get: () => "image/png" }, arrayBuffer: async () => Uint8Array.from([1]).buffer
    });
    // Minimal valid PNG shell: signature + width=9, height=12 → 3:4.
    const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const png = Buffer.alloc(24);
    sig.copy(png, 0);
    png.writeUInt32BE(9, 16);
    png.writeUInt32BE(12, 20);
    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never, fetchImpl: fetchImpl as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-ar", model: "seedream_v5_lite"
    });
    await provider.extractPoseImage({ sourceImageBase64: png.toString("base64"), sourceMimeType: "image/png" });
    const [, args] = spawnImpl.mock.calls[0] as [string, string[]];
    expect(args).toContain("--aspect-ratio");
    expect(args[args.indexOf("--aspect-ratio") + 1]).toBe("3:4");
    expect(args).toContain("--quality");
    expect(args[args.indexOf("--quality") + 1]).toBe("high");
  });

  it("maps auth failures to PROVIDER_AUTH_REQUIRED", async () => {
    const spawnImpl = mockSpawn("", "not authenticated", 1);
    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-auth"
    });

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderAuthRequiredError);
  });

  it("maps malformed JSON to PROVIDER_CLI_FAILED", async () => {
    const spawnImpl = mockSpawn("not-json");
    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-json"
    });

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderCliFailedError);
  });

  it("times out long-running CLI", async () => {
    const spawnImpl = vi.fn(() => {
      const child = new EventEmitter() as EventEmitter & {
        stdout: EventEmitter;
        stderr: EventEmitter;
        kill: ReturnType<typeof vi.fn>;
      };
      child.stdout = new EventEmitter();
      child.stderr = new EventEmitter();
      child.kill = vi.fn();
      return child;
    });

    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-timeout",
      timeoutMs: 20
    });

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderTimeoutError);
  });
});

describe("HiggsfieldCliProvider credential guard", () => {
  const tempDirs: string[] = [];

  async function makeCredentials(expiresInSec: number): Promise<string> {
    const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "hf-provider-"));
    tempDirs.push(dir);
    const credentialsPath = path.join(dir, "credentials.json");
    await fs.promises.writeFile(
      credentialsPath,
      JSON.stringify({
        access_token: "secret-access",
        refresh_token: "secret-refresh",
        token_type: "Bearer",
        expires_in: expiresInSec,
        expires_at: Math.floor(Date.now() / 1000) + expiresInSec,
        scope: "openid",
        auth_version: 2
      }),
      { mode: 0o600 }
    );
    return credentialsPath;
  }

  function okFetch() {
    return vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: { get: () => "image/png" },
      arrayBuffer: async () => Uint8Array.from([1]).buffer
    });
  }

  afterEach(async () => {
    vi.restoreAllMocks();
    await Promise.all(tempDirs.splice(0).map((dir) => fs.promises.rm(dir, { recursive: true, force: true })));
  });

  it("backs the credential up before spawning and restores it when the CLI deletes it", async () => {
    const credentialsPath = await makeCredentials(7200);
    const warn = vi.spyOn(logger, "warn");
    const spawnImpl = vi.fn(() => {
      fs.rmSync(credentialsPath);
      const child = new EventEmitter() as EventEmitter & {
        stdout: EventEmitter;
        stderr: EventEmitter;
        kill: ReturnType<typeof vi.fn>;
      };
      child.stdout = new EventEmitter();
      child.stderr = new EventEmitter();
      child.kill = vi.fn();
      queueMicrotask(() => {
        child.stderr.emit("data", Buffer.from("Error: Session expired.\nHint: Run: hf auth login"));
        child.emit("close", 2);
      });
      return child;
    });

    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-guard",
      credentialsPath
    });

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderAuthRequiredError);

    const restored = JSON.parse(fs.readFileSync(credentialsPath, "utf8")) as { refresh_token: string };
    expect(restored.refresh_token).toBe("secret-refresh");
    expect(fs.statSync(credentialsPath).mode & 0o777).toBe(0o600);
    const backupPath = backupPathFor(credentialsPath);
    expect(fs.existsSync(backupPath)).toBe(true);
    expect(fs.statSync(backupPath).mode & 0o777).toBe(0o600);
    expect(warn).toHaveBeenCalled();
    expect(JSON.stringify(warn.mock.calls)).not.toContain("secret-refresh");
    const authState = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(authState.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
    expect(authState.lastAuthErrorAt).not.toBeNull();
    expect(JSON.stringify(authState)).not.toContain("secret-refresh");
  });

  it("keeps the existing backup when a later credential file is older", async () => {
    const credentialsPath = await makeCredentials(7200);
    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn(JSON.stringify({ url: "https://cdn.example.com/out.png" })) as never,
      fetchImpl: okFetch() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-guard-older",
      credentialsPath
    });
    await provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" });
    const firstBackup = fs.readFileSync(backupPathFor(credentialsPath), "utf8");

    await fs.promises.writeFile(
      credentialsPath,
      JSON.stringify({ access_token: "a", refresh_token: "b", expires_at: Math.floor(Date.now() / 1000) + 60 }),
      { mode: 0o600 }
    );
    await provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" });

    expect(fs.readFileSync(backupPathFor(credentialsPath), "utf8")).toBe(firstBackup);
  });

  it.each([
    ["Session expired."],
    ["Error: Stored credentials use an older auth flow."],
    ["Error: Invalid credentials file."]
  ])("maps %s to PROVIDER_AUTH_REQUIRED", async (stderr) => {
    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn("", stderr, 2) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-auth-strings"
    });

    await expect(
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderAuthRequiredError);
  });

  it("never puts CLI output in the thrown error, only in the redacted log", async () => {
    const marker = "LEAK-CANARY-1234 https://user:secret@cdn.example.com/upload";
    const errorLog = vi.spyOn(logger, "error");

    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn("", `Error: Session expired. ${marker}`, 2) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-leak"
    });

    const error = await provider
      .extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
      .catch((thrown: unknown) => thrown as Error);

    expect(error).toBeInstanceOf(ProviderAuthRequiredError);
    expect(error.message).toBe("Higgsfield authentication required");
    expect(error.message).not.toContain("LEAK-CANARY");
    expect(JSON.stringify(error)).not.toContain("LEAK-CANARY");

    const logged = JSON.stringify(errorLog.mock.calls);
    expect(logged).toContain("LEAK-CANARY");
    // Connection-string style credentials are redacted before they reach the log.
    expect(logged).not.toContain("user:secret@");
  });

  it("keeps CLI output out of a non-auth CLI failure too", async () => {
    const marker = "LEAK-CANARY-5678 https://user:secret@cdn.example.com/upload";
    const errorLog = vi.spyOn(logger, "error");

    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn("", `Error: upload failed ${marker}`, 1) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-leak-cli"
    });

    const error = await provider
      .extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
      .catch((thrown: unknown) => thrown as Error);

    expect(error).toBeInstanceOf(ProviderCliFailedError);
    expect(error.message).toBe("Higgsfield CLI failed");
    expect(JSON.stringify(error)).not.toContain("LEAK-CANARY");
    const logged = JSON.stringify(errorLog.mock.calls);
    expect(logged).toContain("LEAK-CANARY");
    expect(logged).not.toContain("user:secret@");
  });

  it("clears the recorded auth error after a successful call", async () => {
    const failingProvider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn("", "Error: Session expired.", 2) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-auth-clear"
    });
    await expect(
      failingProvider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ).rejects.toBeInstanceOf(ProviderAuthRequiredError);
    const statePath = providerAuthStatePathFor(sandboxCredentialsPath);
    expect((await readProviderAuthState(statePath)).lastAuthErrorAt).not.toBeNull();

    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn(JSON.stringify({ url: "https://cdn.example.com/out.png" })) as never,
      fetchImpl: okFetch() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-auth-clear"
    });
    await provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" });

    const state = await readProviderAuthState(statePath);
    expect(state.lastSuccessAt).not.toBeNull();
    expect(Date.parse(state.lastSuccessAt!)).toBeGreaterThan(Date.parse(state.lastAuthErrorAt!));
  });

  it("checks account status through the guard: backup first, state on success", async () => {
    const credentialsPath = await makeCredentials(7200);
    const spawnImpl = mockSpawn("");

    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-account",
      credentialsPath
    });

    await expect(provider.tryCheckAccountStatus()).resolves.toEqual({ ok: true, authFailure: false });

    const [, args] = spawnImpl.mock.calls[0] as [string, string[]];
    expect(args).toEqual(["account", "status"]);
    expect(fs.existsSync(backupPathFor(credentialsPath))).toBe(true);
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastSuccessAt).not.toBeNull();
  });

  it("reports an auth failure from account status and records it for the API", async () => {
    const credentialsPath = await makeCredentials(7200);
    const provider = new HiggsfieldCliProvider({
      spawnImpl: mockSpawn("", "Error: Session expired.", 2) as never,
      fetchImpl: vi.fn() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-account-fail",
      credentialsPath
    });

    await expect(provider.tryCheckAccountStatus()).resolves.toEqual({ ok: false, authFailure: true });
    const state = await readProviderAuthState(providerAuthStatePathFor(credentialsPath));
    expect(state.lastAuthErrorCode).toBe("PROVIDER_AUTH_REQUIRED");
  });

  it("runs concurrent extractions one at a time", async () => {
    const events: string[] = [];
    const spawnImpl = vi.fn((_cmd: string, args: string[]) => {
      const label = args.includes("--prompt") ? (events.length === 0 ? "first" : "second") : "unknown";
      events.push(`${label}:start`);
      const child = new EventEmitter() as EventEmitter & {
        stdout: EventEmitter;
        stderr: EventEmitter;
        kill: ReturnType<typeof vi.fn>;
      };
      child.stdout = new EventEmitter();
      child.stderr = new EventEmitter();
      child.kill = vi.fn();
      setTimeout(() => {
        events.push(`${label}:end`);
        child.stdout.emit("data", Buffer.from(JSON.stringify({ url: "https://cdn.example.com/out.png" })));
        child.emit("close", 0);
      }, 20);
      return child;
    });

    const provider = new HiggsfieldCliProvider({
      spawnImpl: spawnImpl as never,
      fetchImpl: okFetch() as typeof fetch,
      tmpDir: "/tmp/higgsfield-test-mutex"
    });

    await Promise.all([
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" }),
      provider.extractPoseImage({ sourceImageBase64: "c291cmNl", sourceMimeType: "image/png" })
    ]);

    expect(events).toEqual(["first:start", "first:end", "second:start", "second:end"]);
  });
});
