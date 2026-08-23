import { randomUUID } from "node:crypto";
import { spawn as nodeSpawn, type ChildProcess } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { AppError } from "./errors";
import type { ExtractedImage } from "./types";

const DEFAULT_STRENGTH = 1.0;
const DEFAULT_THRESHOLD = 245;
const DEFAULT_SOFTNESS = 24;
const DEFAULT_TIMEOUT_MS = 30_000;

export interface LineartBackgroundRemoverOptions {
  spawnImpl?: typeof nodeSpawn;
  pythonBin?: string;
  scriptPath?: string;
  enabled?: boolean;
  strength?: number;
  threshold?: number;
  softness?: number;
  timeoutMs?: number;
  tmpDir?: string;
}

interface SpawnResult {
  stdout: string;
  stderr: string;
  exitCode: number | null;
}

function resolveDefaultScriptPath(): string {
  return path.resolve(__dirname, "../../scripts/remove_bg_lineart.py");
}

function extensionForMimeType(mimeType: string): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    case "image/jpeg":
      return "jpg";
    default:
      return "png";
  }
}

async function runPython(
  spawnImpl: typeof nodeSpawn,
  command: string,
  args: string[],
  timeoutMs: number
): Promise<SpawnResult> {
  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let settled = false;

    const child: ChildProcess = spawnImpl(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });

    if (!child.stdout || !child.stderr) {
      reject(new AppError("Python process missing stdio pipes", 500, "LINEART_BG_REMOVAL_FAILED"));
      return;
    }

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        child.kill("SIGTERM");
        reject(new AppError(`Line-art background removal timed out after ${timeoutMs}ms`, 500, "LINEART_BG_REMOVAL_FAILED"));
      }
    }, timeoutMs);

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(new AppError(`Failed to spawn Python: ${error.message}`, 500, "LINEART_BG_REMOVAL_FAILED"));
    });

    child.on("close", (exitCode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ stdout, stderr, exitCode });
    });
  });
}

export function isLineartBackgroundRemovalEnabled(): boolean {
  const raw = process.env.LINEART_BG_REMOVAL_ENABLED;
  if (raw === undefined) {
    return true;
  }
  return raw !== "0" && raw.toLowerCase() !== "false";
}

export function createLineartBackgroundRemover(options: LineartBackgroundRemoverOptions = {}) {
  const spawnImpl = options.spawnImpl ?? nodeSpawn;
  const pythonBin = options.pythonBin ?? process.env.PYTHON_BIN ?? "python3";
  const scriptPath = options.scriptPath ?? process.env.LINEART_BG_SCRIPT_PATH ?? resolveDefaultScriptPath();
  const enabled = options.enabled ?? isLineartBackgroundRemovalEnabled();
  const strength = options.strength ?? Number(process.env.LINEART_BG_REMOVAL_STRENGTH ?? DEFAULT_STRENGTH);
  const threshold = options.threshold ?? Number(process.env.LINEART_BG_REMOVAL_THRESHOLD ?? DEFAULT_THRESHOLD);
  const softness = options.softness ?? Number(process.env.LINEART_BG_REMOVAL_SOFTNESS ?? DEFAULT_SOFTNESS);
  const timeoutMs = options.timeoutMs ?? Number(process.env.LINEART_BG_REMOVAL_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);
  const tmpDir = options.tmpDir ?? path.join(os.tmpdir(), "lineart-bg-removal");

  return {
    enabled,

    async removeBackground(input: ExtractedImage): Promise<ExtractedImage> {
      if (!enabled) {
        return input;
      }

      const jobDir = path.join(tmpDir, randomUUID());
      const inputPath = path.join(jobDir, `input.${extensionForMimeType(input.mimeType)}`);
      const outputPath = path.join(jobDir, "output.png");

      try {
        await fs.mkdir(jobDir, { recursive: true });
        await fs.writeFile(inputPath, Buffer.from(input.imageBase64, "base64"));

        const args = [
          scriptPath,
          inputPath,
          "-o",
          outputPath,
          "--threshold",
          String(threshold),
          "--softness",
          String(softness),
          "--strength",
          String(strength),
          "--preserve-color"
        ];

        const { stdout, stderr, exitCode } = await runPython(spawnImpl, pythonBin, args, timeoutMs);
        if (exitCode !== 0) {
          const detail = stderr.trim() || stdout.trim() || `Python exited with code ${exitCode}`;
          throw new AppError(detail, 500, "LINEART_BG_REMOVAL_FAILED");
        }

        const outputBuffer = await fs.readFile(outputPath);
        return {
          imageBase64: outputBuffer.toString("base64"),
          mimeType: "image/png"
        };
      } finally {
        await fs.rm(jobDir, { recursive: true, force: true }).catch(() => undefined);
      }
    }
  };
}
