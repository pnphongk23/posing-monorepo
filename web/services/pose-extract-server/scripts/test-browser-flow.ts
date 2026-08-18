/**
 * Manual E2E test for Gemini browser extraction flow.
 *
 * Uses Playwright's launchPersistentContext pointing DIRECTLY at your real
 * Chrome profile. Chrome encrypts cookies via macOS Keychain so cloning
 * does not work.
 *
 * MUST close Chrome before running.
 *
 * Usage:
 *   npx tsx scripts/test-browser-flow.ts /path/to/image.png
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

import { chromium, type Page } from "playwright";

import { DEFAULT_EXTRACT_PROMPT } from "../src/services/extractPrompt";

const CHROME_PROFILE = path.join(
  process.env.HOME ?? "/Users/phamnhuphong",
  "Library/Application Support/Google/Chrome/Default"
);
const APP_URL = process.env.BROWSER_APP_URL ?? "https://gemini.google.com/app";
const PROMPT = process.env.BROWSER_PROMPT ?? DEFAULT_EXTRACT_PROMPT;
const TIMEOUT_MS = Number(process.env.BROWSER_TIMEOUT_MS ?? "90000");

async function findFirstVisible(page: Page, selectors: string[]) {
  for (const sel of selectors) {
    const loc = page.locator(sel).first();
    if (await loc.count()) return loc;
  }
  return null;
}

async function waitForAnySelector(page: Page, selectors: string[], timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = await findFirstVisible(page, selectors);
    if (found) return found;
    await page.waitForTimeout(500);
  }
  return null;
}

async function main(): Promise<void> {
  const inputImageArg = process.argv.find((a, i) => i >= 2 && !a.startsWith("--"));
  if (!inputImageArg || !fs.existsSync(inputImageArg)) {
    console.error("❌ Provide a valid image path.");
    process.exit(1);
  }

  const buf = fs.readFileSync(inputImageArg);
  const sourceBase64 = buf.toString("base64");
  console.log(`📷 Input: ${inputImageArg} (${(buf.length / 1024).toFixed(1)} KB)\n`);

  // Ensure Chrome is closed
  try {
    const ps = execSync("pgrep -f 'Google Chrome'", { stdio: "pipe" }).toString().trim();
    if (ps) {
      console.error("❌ Chrome is running. Close it first.");
      process.exit(1);
    }
  } catch { /* good */ }

  console.log("🚀 Launching Chrome with real profile...");
  const context = await chromium.launchPersistentContext(CHROME_PROFILE, {
    channel: "chrome",
    headless: false,
    viewport: { width: 1440, height: 900 },
    args: ["--disable-blink-features=AutomationControlled"],
  });

  const page = await context.newPage();
  page.setDefaultTimeout(TIMEOUT_MS);
  const debugDir = path.resolve(__dirname, "../data/debug");
  fs.mkdirSync(debugDir, { recursive: true });

  try {
    // Navigate
    console.log("🌐 Navigating to Gemini...");
    await page.goto(APP_URL, { waitUntil: "domcontentloaded" });

    const promptBox = await waitForAnySelector(page, [
      "div[aria-label*='Enter a prompt'][role='textbox']",
      "div.ql-editor.textarea[role='textbox']",
      "[role='textbox'][contenteditable='true']",
      "textarea",
    ], 30000);

    if (!promptBox) {
      console.error("❌ Prompt box not found.");
      await page.screenshot({ path: path.join(debugDir, "no-prompt.png"), fullPage: true });
      process.exit(1);
    }
    console.log("✅ Gemini authenticated\n");

    // Upload image
    console.log("📤 Uploading...");
    const uploadPath = path.join(debugDir, `input-${Date.now()}.png`);
    fs.writeFileSync(uploadPath, Buffer.from(sourceBase64, "base64"));

    let uploaded = false;

    // Try direct file input first
    const fileInput = await findFirstVisible(page, [
      "input[type='file'][accept*='image']",
      "input[type='file']",
    ]);
    if (fileInput) {
      await fileInput.setInputFiles(uploadPath);
      uploaded = true;
      console.log("   ✅ Via direct file input\n");
    }

    if (!uploaded) {
      // Two-step: click "+" menu → "Upload files"
      const menuBtn = await findFirstVisible(page, [
        "button[aria-label*='Open upload file menu']",
        "button[aria-label*='upload file']",
        "button[aria-label*='Add files']",
        "button[aria-label*='Upload']",
      ]);
      if (!menuBtn) {
        // Dump buttons for debugging
        const buttons = await page.locator("button").all();
        console.log("   Available buttons:");
        for (const b of buttons.slice(0, 25)) {
          const label = await b.getAttribute("aria-label");
          const text = await b.textContent();
          if (label || text?.trim()) {
            console.log(`     aria-label="${label ?? ""}" text="${(text ?? "").trim().substring(0, 50)}"`);
          }
        }
        console.error("   ❌ Upload menu button not found.");
        await page.screenshot({ path: path.join(debugDir, "no-upload.png"), fullPage: true });
        fs.rmSync(uploadPath, { force: true });
        process.exit(1);
      }

      console.log("   Clicking upload menu (+)...");
      await menuBtn.click();
      await page.waitForTimeout(800);

      const uploadOption = await waitForAnySelector(page, [
        "button[aria-label*='Upload files']",
        "button:has-text('Upload files')",
        "button:has-text('Upload file')",
        "[role='menuitem']:has-text('Upload')",
      ], 5000);

      if (uploadOption) {
        console.log("   Clicking 'Upload files'...");
        const chooserP = page.waitForEvent("filechooser", { timeout: 15000 });
        await uploadOption.click();
        const chooser = await chooserP;
        await chooser.setFiles(uploadPath);
        uploaded = true;
        console.log("   ✅ Uploaded via menu\n");
      } else {
        // Fallback: hidden file input may have appeared
        const hiddenInput = await waitForAnySelector(page, ["input[type='file']"], 3000);
        if (hiddenInput) {
          await hiddenInput.setInputFiles(uploadPath);
          uploaded = true;
          console.log("   ✅ Uploaded via hidden input\n");
        } else {
          await page.screenshot({ path: path.join(debugDir, "upload-menu-open.png"), fullPage: true });
          console.error("   ❌ Upload option not found in menu.");
          fs.rmSync(uploadPath, { force: true });
          process.exit(1);
        }
      }
    }

    // Wait for image to attach visually
    await page.waitForTimeout(2000);

    // Fill prompt
    console.log("📝 Filling prompt...");
    const rPromptBox = await waitForAnySelector(page, [
      "div[aria-label*='Enter a prompt'][role='textbox']",
      "[role='textbox'][contenteditable='true']",
      "textarea",
    ], 5000);
    if (rPromptBox) {
      await rPromptBox.click();
      await rPromptBox.fill(PROMPT);
    }
    console.log(`   "${PROMPT.substring(0, 50)}..."`);

    // Submit
    const submitBtn = await findFirstVisible(page, [
      "button[aria-label='Send message']",
      "button[aria-label*='Send']",
      "button.send-button",
      "button[aria-label*='send']",
    ]);
    if (!submitBtn) {
      console.error("   ❌ Submit button not found.");
      await page.screenshot({ path: path.join(debugDir, "no-submit.png"), fullPage: true });
      fs.rmSync(uploadPath, { force: true });
      process.exit(1);
    }

    const IMAGE_SEL = ".response-container img, [data-test-id] img, .message-content img, canvas + img, img[src*='googleusercontent']";
    const beforeCount = await page.locator(IMAGE_SEL).count();
    console.log(`   Images before: ${beforeCount}`);

    await submitBtn.click();
    console.log("   ✅ Submitted!\n");

    // Wait for new image
    console.log("⏳ Waiting for image generation (up to 90s)...");
    const t0 = Date.now();

    await page.waitForFunction(
      (args: { selector: string; prevCount: number }) => {
        const doc = (globalThis as Record<string, unknown>)["document"] as {
          querySelectorAll(s: string): ArrayLike<unknown>;
        };
        return doc.querySelectorAll(args.selector).length > args.prevCount;
      },
      { selector: IMAGE_SEL, prevCount: beforeCount },
      { timeout: 90000 }
    );

    const imgLoc = page.locator(IMAGE_SEL).last();
    await imgLoc.waitFor({ state: "visible", timeout: 10000 });
    console.log(`   ✅ New image after ${((Date.now() - t0) / 1000).toFixed(1)}s\n`);

    // Extract
    console.log("💾 Extracting...");
    const src = await imgLoc.getAttribute("src");
    if (!src) { console.error("❌ Empty src"); process.exit(1); }

    let outputBase64: string;
    let mimeType: string;
    if (src.startsWith("data:image/")) {
      const [hdr, b64] = src.split(",");
      outputBase64 = b64 ?? "";
      mimeType = hdr.includes("jpeg") ? "image/jpeg" : hdr.includes("webp") ? "image/webp" : "image/png";
    } else {
      const resp = await context.request.get(src);
      const buffer = await resp.body();
      outputBase64 = buffer.toString("base64");
      mimeType = "image/png";
    }

    const ext = mimeType.includes("jpeg") ? ".jpg" : mimeType.includes("webp") ? ".webp" : ".png";
    const outPath = path.join(debugDir, `output-${Date.now()}${ext}`);
    fs.writeFileSync(outPath, Buffer.from(outputBase64, "base64"));

    console.log(`\n✅ DONE — ${mimeType}`);
    console.log(`   💾 ${outPath}`);
    fs.rmSync(uploadPath, { force: true });
  } catch (err) {
    console.error(`\n❌ ${err instanceof Error ? err.message : String(err)}`);
    await page.screenshot({ path: path.join(debugDir, `fail-${Date.now()}.png`), fullPage: true });
  }

  await context.close();
}

main().catch((e) => { console.error("Fatal:", e); process.exit(1); });
