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
    headless: env.BROWSER_HEADLESS === "true",
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH,
    prompt: process.env.BROWSER_PROMPT ?? DEFAULT_EXTRACT_PROMPT,
    timeoutMs: Number(process.env.BROWSER_TIMEOUT_MS ?? "45000"),
    useMockFlow: process.env.WORKER_MOCK_BROWSER === "true",
    debugDir: process.env.WORKER_DEBUG_DIR
  });

  try {
    const result = await client.checkAuthReady();
    if (!result.ready) {
      console.error(JSON.stringify({ ok: false, reason: result.reason ?? "UNKNOWN" }));
      process.exit(1);
    }
    console.log(JSON.stringify({ ok: true }));
  } finally {
    await client.close();
  }
}

run().catch((error) => {
  console.error(JSON.stringify({ ok: false, reason: error instanceof Error ? error.message : "UNKNOWN" }));
  process.exit(1);
});
