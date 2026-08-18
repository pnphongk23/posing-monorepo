import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { createLineartBackgroundRemover } from "./lineartBackgroundRemover";

const tempDirs: string[] = [];

afterEach(() => {
  for (const tempDir of tempDirs.splice(0)) {
    fs.rm(tempDir, { recursive: true, force: true }).catch(() => undefined);
  }
});

describe("createLineartBackgroundRemover", () => {
  it("returns input unchanged when disabled", async () => {
    const remover = createLineartBackgroundRemover({ enabled: false });
    const input = { imageBase64: "cG9zZQ==", mimeType: "image/png" as const };

    await expect(remover.removeBackground(input)).resolves.toEqual(input);
  });

  it("runs python script and returns processed PNG", async () => {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "lineart-bg-test-"));
    tempDirs.push(tmpDir);

    const scriptPath = path.join(tmpDir, "remove_bg_lineart.py");

    await fs.writeFile(
      scriptPath,
      `#!/usr/bin/env python3
import sys
from pathlib import Path
out = Path(sys.argv[sys.argv.index("-o") + 1])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(b"processed-png")
print(f"OK: {sys.argv[1]} -> {out}")
`
    );

    const remover = createLineartBackgroundRemover({
      enabled: true,
      scriptPath,
      pythonBin: "python3",
      tmpDir: path.join(tmpDir, "jobs")
    });

    const result = await remover.removeBackground({
      imageBase64: Buffer.from("source-image").toString("base64"),
      mimeType: "image/png"
    });

    expect(result.mimeType).toBe("image/png");
    expect(Buffer.from(result.imageBase64, "base64").toString()).toBe("processed-png");
  });

  it("throws when python exits non-zero", async () => {
    const spawnImpl = vi.fn(() => {
      const child = {
        stdout: { on: vi.fn() },
        stderr: { on: vi.fn((event: string, cb: (chunk: Buffer) => void) => {
          if (event === "data") {
            queueMicrotask(() => cb(Buffer.from("python failed")));
          }
        }) },
        kill: vi.fn(),
        on: vi.fn((event: string, cb: (value?: unknown) => void) => {
          if (event === "close") {
            queueMicrotask(() => cb(1));
          }
        })
      };
      return child as never;
    });

    const remover = createLineartBackgroundRemover({
      enabled: true,
      spawnImpl,
      scriptPath: "/tmp/remove_bg_lineart.py"
    });

    await expect(
      remover.removeBackground({ imageBase64: "c291cmNl", mimeType: "image/png" })
    ).rejects.toMatchObject({ code: "LINEART_BG_REMOVAL_FAILED" });
  });
});
