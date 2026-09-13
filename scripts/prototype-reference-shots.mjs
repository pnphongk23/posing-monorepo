/**
 * Regenerates the FULL, uncropped 390x844 reference screenshots of the HTML prototype.
 *
 * The committed files in docs/prototype/screenshots/ are clipped (right edge missing), so they
 * are unusable as a parity reference. This script captures the whole `.nb-phone` frame instead.
 *
 * Output: docs/prototype/screenshots/reference/<name>.png
 * Usage:  node scripts/prototype-reference-shots.mjs
 */
import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'docs/prototype/screenshots/reference');
fs.mkdirSync(outDir, { recursive: true });

const SHOTS = [
  { name: 'camera-live', page: 'camera-live.html' },
  { name: 'pose-guide', page: 'pose-guide.html' },
  { name: 'search-blank', page: 'search.html' },
  { name: 'search-results', page: 'search.html?q=Warrior' },
  { name: 'poses-list', page: 'poses-list.html' },
];

const browser = await chromium.launch();
// Wide viewport so the `@media (max-width: 480px)` rule does not collapse the fixed 390x844
// device frame into a full-viewport one — we want the exact prototype frame.
const page = await browser.newPage({
  viewport: { width: 1024, height: 1000 },
  deviceScaleFactor: 2,
});

for (const shot of SHOTS) {
  const url = 'file://' + path.join(root, 'docs/prototype/screens', shot.page);
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(1200); // fonts + remote fixture imagery
  const phone = page.locator('.nb-phone').first();
  const target = (await phone.count()) ? phone : page.locator('body');
  const box = await target.boundingBox();
  await target.screenshot({ path: path.join(outDir, `${shot.name}.png`) });
  console.log(`${shot.name.padEnd(16)} ${Math.round(box.width)}x${Math.round(box.height)}  ${shot.page}`);
}

await browser.close();
console.log(`\nWrote ${SHOTS.length} reference shots to ${path.relative(root, outDir)}/`);
