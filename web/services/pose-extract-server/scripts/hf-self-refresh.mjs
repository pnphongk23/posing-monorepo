import { randomBytes } from "node:crypto";
import { open, readFile, rename, rm } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TOKEN_ENDPOINT = "https://clerk.higgsfield.ai/oauth/token";
const CLIENT_ID = "sRGCQJvvJkPrrtRj";

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validateCredentials(value) {
  if (!isRecord(value) || typeof value.access_token !== "string" || !value.access_token ||
      typeof value.refresh_token !== "string" || !value.refresh_token ||
      typeof value.expires_at !== "number" || !Number.isFinite(value.expires_at)) {
    return false;
  }
  return true;
}

async function writeAtomic(outputPath, contents) {
  const directory = path.dirname(outputPath);
  const tempPath = path.join(directory, `.${path.basename(outputPath)}.${process.pid}.${randomBytes(8).toString("hex")}.tmp`);
  let handle;
  try {
    handle = await open(tempPath, "wx", 0o600);
    await handle.chmod(0o600);
    await handle.writeFile(contents, "utf8");
    await handle.sync();
    await handle.close();
    handle = undefined;
    await rename(tempPath, outputPath);
  } catch {
    if (handle) await handle.close().catch(() => undefined);
    await rm(tempPath, { force: true }).catch(() => undefined);
    throw new Error("write_error");
  }
}

/** Refresh credentials from inputPath and atomically write the rotated set to outputPath. */
export async function runRefresh({
  inputPath,
  outputPath,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  tokenEndpoint = TOKEN_ENDPOINT
}) {
  if (path.resolve(inputPath) === path.resolve(outputPath)) {
    return { ok: false, reason: "invalid_paths" };
  }
  let credentials;
  try {
    credentials = JSON.parse(await readFile(inputPath, "utf8"));
  } catch {
    return { ok: false, reason: "read_error" };
  }
  if (!validateCredentials(credentials)) return { ok: false, reason: "invalid_credentials" };

  const form = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: credentials.refresh_token,
    client_id: CLIENT_ID
  });
  let response;
  try {
    response = await fetchImpl(tokenEndpoint, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form.toString()
    });
  } catch {
    return { ok: false, reason: "network_error" };
  }
  if (response.status !== 200) {
    if (response.status === 400) {
      try {
        const body = await response.json();
        if (isRecord(body) && body.error === "invalid_grant") return { ok: false, reason: "invalid_grant" };
      } catch {
        // Ignore response parsing errors; never return or print the response body.
      }
    }
    return { ok: false, reason: "http_error" };
  }

  let tokenResponse;
  try {
    tokenResponse = await response.json();
  } catch {
    return { ok: false, reason: "invalid_response" };
  }
  if (!isRecord(tokenResponse) || typeof tokenResponse.access_token !== "string" ||
      !tokenResponse.access_token || typeof tokenResponse.expires_in !== "number" ||
      !Number.isFinite(tokenResponse.expires_in) || tokenResponse.expires_in <= 0) {
    return { ok: false, reason: "invalid_response" };
  }

  const expiresAt = Math.floor(now() / 1000) + tokenResponse.expires_in;
  const updated = {
    ...credentials,
    access_token: tokenResponse.access_token,
    refresh_token: typeof tokenResponse.refresh_token === "string" && tokenResponse.refresh_token
      ? tokenResponse.refresh_token
      : credentials.refresh_token,
    expires_in: tokenResponse.expires_in,
    expires_at: expiresAt
  };

  try {
    await writeAtomic(outputPath, `${JSON.stringify(updated, null, 2)}\n`);
  } catch {
    return { ok: false, reason: "write_error" };
  }
  return { ok: true, expiresAt };
}

async function main() {
  const [inputPath, outputPath] = process.argv.slice(2);
  if (!inputPath || !outputPath) {
    process.stdout.write("FAIL invalid_arguments\n");
    process.exitCode = 2;
    return;
  }
  const result = await runRefresh({ inputPath, outputPath });
  if (result.ok) {
    process.stdout.write(`OK expires_at=${new Date(result.expiresAt * 1000).toISOString()}\n`);
    return;
  }
  process.stdout.write(`FAIL ${result.reason}\n`);
  process.exitCode = 1;
}

if (process.argv[1] === "-" || import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch(() => {
    process.stdout.write("FAIL internal_error\n");
    process.exitCode = 1;
  });
}
