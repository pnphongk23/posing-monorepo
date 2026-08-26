import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { EventEmitter } from "node:events";
import { describe, expect, it, vi } from "vitest";

import {
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderTimeoutError
} from "./errors";
import { DEFAULT_EXTRACT_PROMPT } from "./extractPrompt";
import { extractResultUrlFromCliJson, HiggsfieldCliProvider } from "./higgsfieldCliProvider";

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
