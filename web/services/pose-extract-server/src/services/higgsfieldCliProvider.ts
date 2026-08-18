import { randomUUID } from "node:crypto";
import { spawn as nodeSpawn, type ChildProcess } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  ProviderAuthRequiredError,
  ProviderCliFailedError,
  ProviderError,
  ProviderTimeoutError
} from "./errors";
import { DEFAULT_EXTRACT_PROMPT } from "./extractPrompt";
import type { PoseExtractorProvider } from "./poseExtractorProvider";
import type { ExtractedImage } from "./types";

const DEFAULT_MODEL = "kling_omni_image";
const DEFAULT_RESOLUTION = "1k";
const DEFAULT_TIMEOUT_MS = 600_000;
const DEFAULT_WAIT_TIMEOUT = "9m";

export interface HiggsfieldCliProviderOptions {
  spawnImpl?: typeof nodeSpawn;
  fetchImpl?: typeof fetch;
  credentialsPath?: string;
  timeoutMs?: number;
  model?: string;
  tmpDir?: string;
}

interface CliSpawnResult {
  stdout: string;
  stderr: string;
  exitCode: number | null;
}

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAllowedMimeType(value: string): value is ExtractedImage["mimeType"] {
  return value === "image/png" || value === "image/jpeg" || value === "image/webp";
}

function mimeFromContentType(contentType: string | null): ExtractedImage["mimeType"] {
  const normalized = (contentType ?? "").split(";")[0]?.trim().toLowerCase();
  if (normalized && isAllowedMimeType(normalized)) {
    return normalized;
  }
  return "image/png";
}

export function extractResultUrlFromCliJson(payload: unknown): string | null {
  if (Array.isArray(payload)) {
    for (const item of payload) {
      const url = extractResultUrlFromCliJson(item);
      if (url) {
        return url;
      }
    }
    return null;
  }

  if (!isObject(payload)) {
    return null;
  }

  const candidates = [
    payload.result_url,
    payload.url,
    payload.resultUrl,
    payload.image_url,
    payload.imageUrl,
    payload.min_result_url
  ];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate.startsWith("http")) {
      return candidate;
    }
  }

  if (isObject(payload.result) && typeof payload.result.url === "string") {
    return payload.result.url;
  }

  if (isObject(payload.data) && typeof payload.data.url === "string") {
    return payload.data.url;
  }

  return null;
}

function isAuthFailure(stderr: string, stdout: string): boolean {
  const combined = `${stderr}\n${stdout}`.toLowerCase();
  return (
    combined.includes("not authenticated") ||
    combined.includes("auth required") ||
    combined.includes("unauthorized") ||
    combined.includes("credentials")
  );
}

async function runSpawn(
  spawnImpl: typeof nodeSpawn,
  command: string,
  args: string[],
  timeoutMs: number,
  env: NodeJS.ProcessEnv
): Promise<CliSpawnResult> {
  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let settled = false;

    const child: ChildProcess = spawnImpl(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env
    });

    if (!child.stdout || !child.stderr) {
      reject(new ProviderCliFailedError("Higgsfield CLI missing stdio pipes"));
      return;
    }

    const stdoutStream = child.stdout;
    const stderrStream = child.stderr;

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        child.kill("SIGTERM");
        reject(new ProviderTimeoutError(`Higgsfield CLI timed out after ${timeoutMs}ms`));
      }
    }, timeoutMs);

    stdoutStream.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    stderrStream.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(new ProviderCliFailedError(`Failed to spawn Higgsfield CLI: ${error.message}`));
    });

    child.on("close", (exitCode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ stdout, stderr, exitCode });
    });
  });
}

export class HiggsfieldCliProvider implements PoseExtractorProvider {
  readonly id = "higgsfield_cli" as const;

  private readonly spawnImpl: typeof nodeSpawn;
  private readonly fetchImpl: typeof fetch;
  private readonly credentialsPath: string;
  private readonly timeoutMs: number;
  private readonly model: string;
  private readonly tmpDir: string;

  constructor(options: HiggsfieldCliProviderOptions = {}) {
    this.spawnImpl = options.spawnImpl ?? nodeSpawn;
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.credentialsPath = options.credentialsPath ?? process.env.HIGGSFIELD_CREDENTIALS_PATH ?? path.join(os.homedir(), ".higgsfield", "credentials.json");
    this.timeoutMs = options.timeoutMs ?? Number(process.env.HIGGSFIELD_CLI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);
    this.model = options.model ?? DEFAULT_MODEL;
    this.tmpDir = options.tmpDir ?? path.join(os.tmpdir(), "extract-jobs");
  }

  async extractPoseImage(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage> {
    const jobDir = path.join(this.tmpDir, randomUUID());
    const extension = input.sourceMimeType === "image/png" ? "png" : "jpg";
    const sourcePath = path.join(jobDir, `source.${extension}`);

    try {
      await fs.mkdir(jobDir, { recursive: true });
      await fs.writeFile(sourcePath, Buffer.from(input.sourceImageBase64, "base64"));

      const args = [
        "generate",
        "create",
        this.model,
        "--prompt",
        DEFAULT_EXTRACT_PROMPT,
        "--image",
        sourcePath,
        "--resolution",
        DEFAULT_RESOLUTION,
        "--wait",
        "--wait-timeout",
        DEFAULT_WAIT_TIMEOUT,
        "--json"
      ];

      const env = {
        ...process.env,
        HIGGSFIELD_CREDENTIALS_PATH: this.credentialsPath
      };

      const { stdout, stderr, exitCode } = await runSpawn(this.spawnImpl, "higgsfield", args, this.timeoutMs, env);

      if (exitCode !== 0) {
        if (isAuthFailure(stderr, stdout)) {
          throw new ProviderAuthRequiredError(stderr.trim() || stdout.trim() || "Higgsfield authentication required");
        }
        throw new ProviderCliFailedError(stderr.trim() || stdout.trim() || `Higgsfield CLI exited with code ${exitCode}`);
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(stdout.trim());
      } catch {
        throw new ProviderCliFailedError("Malformed Higgsfield CLI JSON output");
      }

      const resultUrl = extractResultUrlFromCliJson(parsed);
      if (!resultUrl) {
        throw new ProviderCliFailedError("Higgsfield CLI JSON missing result URL");
      }

      let response: Response;
      try {
        response = await this.fetchImpl(resultUrl);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown fetch failure";
        throw new ProviderError(`Failed to fetch Higgsfield result: ${message}`);
      }

      if (!response.ok) {
        throw new ProviderError(`Higgsfield result fetch failed with status ${response.status}`);
      }

      const buffer = Buffer.from(await response.arrayBuffer());
      return {
        imageBase64: buffer.toString("base64"),
        mimeType: mimeFromContentType(response.headers.get("content-type"))
      };
    } finally {
      await fs.rm(jobDir, { recursive: true, force: true }).catch(() => undefined);
    }
  }
}
