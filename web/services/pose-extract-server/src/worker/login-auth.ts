import "dotenv/config";

import { getEnv } from "../config/env";
import { DEFAULT_EXTRACT_PROMPT } from "../services/extractPrompt";
import { GeminiBrowserClient } from "./gemini-browser-client";

async function run(): Promise<void> {
  const env = getEnv();
  const profileDir = process.env.BROWSER_PROFILE_DIR ?? env.BROWSER_PROFILE_DIR;
  const client = new GeminiBrowserClient({
    appUrl: env.BROWSER_APP_URL,
    profileDir,
    chromeChannel: process.env.PLAYWRIGHT_CHROME_CHANNEL,
    headless: false,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH,
    prompt: process.env.BROWSER_PROMPT ?? DEFAULT_EXTRACT_PROMPT,
    timeoutMs: Number(process.env.BROWSER_TIMEOUT_MS ?? "45000"),
    useMockFlow: false,
    debugDir: process.env.WORKER_DEBUG_DIR
  });

  const first = await client.checkAuthReady();
  if (first.ready) {
    console.log("Already logged in. You can close now.");
    await client.close();
    return;
  }

  console.log("Browser is open for login. Complete Google/Gemini login, then press Enter here...");
  await new Promise<void>((resolve) => {
    process.stdin.resume();
    process.stdin.once("data", () => resolve());
  });

  const second = await client.checkAuthReady();
  if (!second.ready) {
    console.error(JSON.stringify({ ok: false, reason: second.reason ?? "UNKNOWN" }));
    await client.close();
    process.exit(1);
  }

  console.log(JSON.stringify({ ok: true }));
  await client.close();
}

run().catch((error) => {
  console.error(JSON.stringify({ ok: false, reason: error instanceof Error ? error.message : "UNKNOWN" }));
  process.exit(1);
});
