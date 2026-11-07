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
import {
  backupCredential,
  backupPathFor,
  defaultCredentialsPath,
  restoreCredential,
  readCredentialSnapshot,
  withCredentialLock
} from "./higgsfieldCredentialGuard";
import type { PoseExtractorProvider } from "./poseExtractorProvider";
import {
  dispatchProviderAuthAlertOnce,
  providerAuthStatePathFor,
  recordProviderAuthFailure,
  recordProviderAuthSuccess
} from "./providerAuthStateFile";
import type { ExtractedImage } from "./types";
import { logger } from "../utils/logger";
import { sanitizeErrorMessage } from "../utils/sanitizeError";

/** Default generation model → Seedream 5.0 Lite (no `--resolution`, quality `basic`|`high`). */
const DEFAULT_MODEL = "seedream_v5_lite";
const DEFAULT_RESOLUTION = "1k";
const DEFAULT_GPT_IMAGE_QUALITY = "medium";
/** Model-specific quality value used when `--resolution` is omitted. */
const DEFAULT_SEEDREAM_QUALITY = "high";
/** Models that reject `--resolution` on the Higgsfield CLI. */
const MODELS_WITHOUT_RESOLUTION = new Set(["openai_hazel", "text2image_gpt", "seedream_v4_5", "seedream_v5_lite"]);
/** GPT-style models that expect `--quality medium` (vs Seedream's basic|high). */
const GPT_STYLE_QUALITY = new Set(["openai_hazel", "text2image_gpt"]);
/** Allowed `--aspect-ratio` values per Seedream model (from `higgsfield model get`). */
const ASPECT_RATIOS: Record<string, string[]> = {
  seedream_v4_5: ["1:1", "4:3", "16:9", "3:2", "21:9", "3:4", "9:16", "2:3"],
  seedream_v5_lite: ["1:1", "4:3", "3:4", "16:9", "9:16", "21:9"]
};
const ASPECT_VALUES: Record<string, number> = {
  "1:1": 1, "4:3": 4 / 3, "16:9": 16 / 9, "3:2": 1.5, "21:9": 21 / 9,
  "3:4": 3 / 4, "9:16": 9 / 16, "2:3": 2 / 3
};
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

/** Read image pixel dimensions (PNG/JPEG) without external deps. WebP → null. */
async function readImageDimensions(
  filePath: string,
  mimeType: string
): Promise<{ width: number; height: number } | null> {
  const handle = await fs.open(filePath, "r");
  try {
    if (mimeType === "image/png") {
      const sig = Buffer.alloc(8);
      await handle.read(sig, 0, 8, 0);
      if (!sig.equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return null;
      const b = Buffer.alloc(8);
      await handle.read(b, 0, 8, 16);
      return { width: b.readUInt32BE(0), height: b.readUInt32BE(4) };
    }
    if (mimeType === "image/jpeg") {
      const head = Buffer.alloc(2);
      await handle.read(head, 0, 2, 0);
      if (head[0] !== 0xff || head[1] !== 0xd8) return null;
      const buf = Buffer.alloc(65536);
      const n = (await handle.read(buf, 0, buf.length, 0)).bytesRead;
      let off = 2;
      while (off + 9 < n) {
        if (buf[off] !== 0xff) { off++; continue; }
        const marker = buf[off + 1];
        const isSof = (marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) || (marker >= 0xcd && marker <= 0xcf);
        if (isSof) return { height: (buf[off + 5] << 8) | buf[off + 6], width: (buf[off + 7] << 8) | buf[off + 8] };
        if (marker === 0xda || marker === 0xd9) return null;
        const len = (buf[off + 2] << 8) | buf[off + 3];
        off += 2 + len;
      }
      return null;
    }
    return null;
  } finally {
    await handle.close();
  }
}

/** Map source pixel ratio to the nearest allowed `--aspect-ratio` for the model. */
function pickAspectRatio(model: string, dims: { width: number; height: number } | null): string | null {
  const allowed = ASPECT_RATIOS[model];
  if (!allowed || !dims || dims.width <= 0 || dims.height <= 0) return null;
  const target = dims.width / dims.height;
  let best = allowed[0];
  let bestErr = Infinity;
  for (const a of allowed) {
    const err = Math.abs(Math.log2(ASPECT_VALUES[a]) - Math.log2(target));
    if (err < bestErr) { bestErr = err; best = a; }
  }
  return best;
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

/**
 * The CLI reports every credential problem as a plain sentence on stderr; all of them mean "a human
 * must re-authenticate", so they must map to PROVIDER_AUTH_REQUIRED instead of a generic CLI failure.
 */
function isAuthFailure(stderr: string, stdout: string): boolean {
  const combined = `${stderr}\n${stdout}`.toLowerCase();
  return (
    combined.includes("not authenticated") ||
    combined.includes("auth required") ||
    combined.includes("unauthorized") ||
    combined.includes("credentials") ||
    combined.includes("session expired") ||
    combined.includes("older auth flow")
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
  private readonly authStatePath: string;

  constructor(options: HiggsfieldCliProviderOptions = {}) {
    this.spawnImpl = options.spawnImpl ?? nodeSpawn;
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.credentialsPath = options.credentialsPath ?? defaultCredentialsPath(process.env);
    this.timeoutMs = options.timeoutMs ?? Number(process.env.HIGGSFIELD_CLI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);
    this.model = options.model ?? process.env.HIGGSFIELD_CLI_MODEL ?? DEFAULT_MODEL;
    this.tmpDir = options.tmpDir ?? path.join(os.tmpdir(), "extract-jobs");
    // Shared with the API process: the worker records auth failures here so /api/health sees them.
    this.authStatePath = providerAuthStatePathFor(this.credentialsPath);
  }

  /**
   * Every CLI spawn is serialised: the CLI rotates its refresh token on write, so two concurrent
   * commands can invalidate each other's token and make the CLI delete the credential file.
   */
  async extractPoseImage(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage> {
    return withCredentialLock(() => this.extractPoseImageLocked(input));
  }

  private async extractPoseImageLocked(input: {
    sourceImageBase64: string;
    sourceMimeType: string;
  }): Promise<ExtractedImage> {
    const jobDir = path.join(this.tmpDir, randomUUID());
    const extension = input.sourceMimeType === "image/png" ? "png" : "jpg";
    const sourcePath = path.join(jobDir, `source.${extension}`);

    try {
      await fs.mkdir(jobDir, { recursive: true });
      await fs.writeFile(sourcePath, Buffer.from(input.sourceImageBase64, "base64"));

      const dims = await readImageDimensions(sourcePath, input.sourceMimeType);
      const modelArgs = MODELS_WITHOUT_RESOLUTION.has(this.model)
        ? ["--quality", GPT_STYLE_QUALITY.has(this.model) ? DEFAULT_GPT_IMAGE_QUALITY : DEFAULT_SEEDREAM_QUALITY]
        : ["--resolution", DEFAULT_RESOLUTION];
      const aspect = pickAspectRatio(this.model, dims);
      if (aspect) modelArgs.push("--aspect-ratio", aspect);
      const args = [
        "generate",
        "create",
        this.model,
        "--prompt",
        DEFAULT_EXTRACT_PROMPT,
        "--image",
        sourcePath,
        ...modelArgs,
        "--wait",
        "--wait-timeout",
        DEFAULT_WAIT_TIMEOUT,
        "--json"
      ];

      const env = {
        ...process.env,
        HIGGSFIELD_CREDENTIALS_PATH: this.credentialsPath
      };

      // The CLI deletes the credential file when a refresh fails, and the refresh token it holds
      // is the only copy, so keep an atomic 0600 backup before every spawn.
      const backup = await backupCredential({ credentialsPath: this.credentialsPath });

      const { stdout, stderr, exitCode } = await runSpawn(this.spawnImpl, "higgsfield", args, this.timeoutMs, env);

      if (exitCode !== 0) {
        const afterFailure = await readCredentialSnapshot(this.credentialsPath);
        const restored =
          afterFailure.state === "missing" ? await restoreCredential({ credentialsPath: this.credentialsPath }) : false;
        if (restored) {
          logger.warn(
            { backupPath: backup.backupPath, credentialsPath: this.credentialsPath },
            "higgsfield CLI removed the credential file; restored the last backup"
          );
        }

        if (restored || isAuthFailure(stderr, stdout)) {
          // The CLI output never reaches the API response: only the log, redacted and truncated.
          logger.error(
            {
              credentialsPath: this.credentialsPath,
              restoredFromBackup: restored,
              cliOutput: sanitizeErrorMessage(stderr.trim() || stdout.trim())
            },
            "higgsfield CLI reported an authentication failure"
          );
          await recordProviderAuthFailure({ statePath: this.authStatePath, code: "PROVIDER_AUTH_REQUIRED" });
          await dispatchProviderAuthAlertOnce({
            statePath: this.authStatePath,
            payload: { event: "provider_auth", status: "degraded", state: "auth_error", expiresInSec: null }
          });
          throw new ProviderAuthRequiredError("Higgsfield authentication required");
        }
        // Same rule as the auth path: the CLI output goes to the redacted log, the caller gets a
        // fixed message that is safe to store on the job and return through the API.
        logger.error(
          {
            credentialsPath: this.credentialsPath,
            exitCode,
            cliOutput: sanitizeErrorMessage(stderr.trim() || stdout.trim())
          },
          "higgsfield CLI failed"
        );
        throw new ProviderCliFailedError("Higgsfield CLI failed");
      }

      await recordProviderAuthSuccess({ statePath: this.authStatePath });

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
