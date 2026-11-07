import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, describe, expect, it } from "vitest";

const execFileAsync = promisify(execFile);

const scriptPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "scripts",
  "higgsfield-auth-probe.sh"
);

const NODE_DIR = path.dirname(process.execPath);
const tempDirs: string[] = [];

interface ProbeResult {
  code: number;
  stdout: string;
  stderr: string;
  invocations: string[];
}

async function makeWorkspace(expiresInSec: number | null, rawContents?: string): Promise<{
  root: string;
  credentialsPath: string;
  logPath: string;
  binDir: string;
  homeDir: string;
}> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "hf-probe-"));
  tempDirs.push(root);
  const binDir = path.join(root, "bin");
  const homeDir = path.join(root, "home");
  const credentialsPath = path.join(root, "credentials", "credentials.json");
  const logPath = path.join(root, "invocations.log");
  await fs.mkdir(binDir, { recursive: true });
  await fs.mkdir(homeDir, { recursive: true });
  await fs.mkdir(path.dirname(credentialsPath), { recursive: true });

  const stub = `#!/usr/bin/env bash
set -u
printf '%s\\n' "$*" >> "${logPath}"
if [ "\${STUB_DELETE_CREDENTIALS:-0}" = "1" ]; then rm -f "\${HIGGSFIELD_CREDENTIALS_PATH}"; fi
if [ "\${1:-}" = "account" ] && [ "\${2:-}" = "status" ]; then exit "\${STUB_ACCOUNT_EXIT:-0}"; fi
exit 0
`;
  const stubPath = path.join(binDir, "higgsfield");
  await fs.writeFile(stubPath, stub, { mode: 0o755 });

  if (rawContents !== undefined) {
    await fs.writeFile(credentialsPath, rawContents, { mode: 0o600 });
  } else if (expiresInSec !== null) {
    await fs.writeFile(
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
  }

  return { root, credentialsPath, logPath, binDir, homeDir };
}

async function runProbe(
  workspace: { credentialsPath: string; binDir: string; homeDir: string; logPath: string },
  extraEnv: Record<string, string> = {},
  options: { withCli?: boolean } = {}
): Promise<ProbeResult> {
  const withCli = options.withCli ?? true;
  const searchPath = withCli ? `${workspace.binDir}:${NODE_DIR}:/usr/bin:/bin` : `${NODE_DIR}:/usr/bin:/bin`;
  try {
    const { stdout, stderr } = await execFileAsync("bash", [scriptPath], {
      env: {
        PATH: searchPath,
        HOME: workspace.homeDir,
        HIGGSFIELD_CREDENTIALS_PATH: workspace.credentialsPath,
        ...extraEnv
      }
    });
    return { code: 0, stdout, stderr, invocations: await readInvocations(workspace.logPath) };
  } catch (error) {
    const failure = error as { code?: number; stdout?: string; stderr?: string };
    return {
      code: failure.code ?? -1,
      stdout: failure.stdout ?? "",
      stderr: failure.stderr ?? "",
      invocations: await readInvocations(workspace.logPath)
    };
  }
}

async function readInvocations(logPath: string): Promise<string[]> {
  try {
    const raw = await fs.readFile(logPath, "utf8");
    return raw.split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

describe("scripts/higgsfield-auth-probe.sh", () => {
  it("exits 0 on a healthy credential, validates against the API and leaves a 0600 backup", async () => {
    const workspace = await makeWorkspace(3 * 24 * 60 * 60);

    const result = await runProbe(workspace);

    expect(result.code).toBe(0);
    expect(result.invocations).toEqual(["account status"]);
    expect(result.stdout).not.toContain("secret-access");
    expect(result.stderr).not.toContain("secret-refresh");
    const backupPath = path.join(path.dirname(workspace.credentialsPath), "backup", "credentials.latest.json");
    expect((await fs.stat(backupPath)).mode & 0o777).toBe(0o600);
  });

  it("exits 3 when the credential expires within 24 hours", async () => {
    const workspace = await makeWorkspace(3600);

    const result = await runProbe(workspace);

    expect(result.code).toBe(3);
    expect(result.stderr).toContain("expires in");
  });

  it("exits 2 without touching the CLI when the token is already expired", async () => {
    const workspace = await makeWorkspace(-120);

    const result = await runProbe(workspace);

    expect(result.code).toBe(2);
    expect(result.invocations).toEqual([]);
    // The probe must never hand an expired credential to the CLI: a failed refresh deletes it.
    await expect(fs.stat(workspace.credentialsPath)).resolves.toBeTruthy();
  });

  it("exits 2 when the credential file is missing", async () => {
    const workspace = await makeWorkspace(null);

    const result = await runProbe(workspace);

    expect(result.code).toBe(2);
    expect(result.invocations).toEqual([]);
    expect(result.stderr).toContain("missing");
  });

  it("exits 2 when the credential file is not a usable credential", async () => {
    const workspace = await makeWorkspace(null, "not-json");

    const result = await runProbe(workspace);

    expect(result.code).toBe(2);
    expect(result.invocations).toEqual([]);
  });

  it("exits 2 when the API rejects the token and restores the credential the CLI deleted", async () => {
    const workspace = await makeWorkspace(3 * 24 * 60 * 60);

    const result = await runProbe(workspace, { STUB_ACCOUNT_EXIT: "2", STUB_DELETE_CREDENTIALS: "1" });

    expect(result.code).toBe(2);
    expect(result.invocations).toEqual(["account status"]);
    const restored = JSON.parse(await fs.readFile(workspace.credentialsPath, "utf8")) as { refresh_token: string };
    expect(restored.refresh_token).toBe("secret-refresh");
    expect((await fs.stat(workspace.credentialsPath)).mode & 0o777).toBe(0o600);
    expect(result.stderr).toContain("restored");
  });

  it("exits 1 when the CLI is not installed", async () => {
    const workspace = await makeWorkspace(3 * 24 * 60 * 60);

    const result = await runProbe(workspace, {}, { withCli: false });

    expect(result.code).toBe(1);
    expect(result.stderr).toContain("not found on PATH");
  });
});
