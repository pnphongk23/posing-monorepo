/**
 * Regenerates the FULL, uncropped 390x844 (@2x = 780x1688 px) reference screenshots of the
 * HTML prototype for the 260913 parity gate.
 *
 * State list source of truth: docs/evidence/260913-parity-gate/dlb-state-map.md (DL-B Phase 1,
 * every parameter verified against the consuming JS). Do not add a shot here without a row in
 * that file.
 *
 * Rules (ios-ui-parity-verification skill):
 *  - Wide 1024x1000 viewport so `@media (max-width: 480px)` cannot collapse the fixed frame.
 *  - Element screenshot of `.nb-phone` at deviceScaleFactor 2 -> exactly 780x1688 px.
 *  - The prototype under docs/prototype/** is FROZEN: this script only navigates it (including
 *    driving post-tap states with Playwright clicks/keys); it never edits it.
 *
 * Post-tap states (NOT URL-reachable per the state map) are captured by replaying the tap:
 *   account-signed-out   <- click #account-sign-out on account.html        (scripts/account.js:17-27)
 *   sign-in-failure      <- click #google-sign-in on sign-in-prompt.html?state=fail (sign-in-prompt.js:13)
 *   camera-tools-dismissed <- Escape on camera-live.html?settings=open      (scripts/modal.js:33-42)
 *
 * Every SHOTS entry declares its own observables, asserted against the live page BEFORE the
 * screenshot is taken:
 *   expectText:   exact strings that must exist on the page (page.getByText(s, {exact:true}), count >= 1)
 *   expectVisible: css selectors with at least one VISIBLE match (never aborts early)
 *   expectAbsent:  css selectors with ZERO visible matches — absence is the most-missed defect class
 *     ('text=<exact string>' entries are matched as exact text instead of css)
 *   expectEmptyText: css selectors whose rendered innerText must be '' — for controls the page
 *     hides via a `hidden` attribute that CSS re-displays (nav-bar buttons, photo card), so
 *     visibility is a false signal and only the empty content proves the hidden state.
 * Every failure is collected (never abort at the first), printed as
 * `STATE ASSERT FAILED <ref>: <which assertion>` and the script exits non-zero at the end.
 * Expectations are derived from the prototype's own code; the fixing file:line for every row is
 * recorded in docs/evidence/260913-parity-gate/dlb-reference-manifest.md.
 *
 * Output: docs/prototype/screenshots/reference/<name>.png
 * Usage:  node scripts/prototype-reference-shots.mjs
 */
import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';
import { createHash } from 'crypto';
import { fileURLToPath } from 'url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outDir = path.join(root, 'docs/prototype/screenshots/reference');
fs.mkdirSync(outDir, { recursive: true });

const SHOTS = [
  // --- camera-live.html (state map section "camera-live.html") ---
  {
    name: 'camera-live', page: 'camera-live.html',
    expectAbsent: ['#camera-tools-menu', '[data-pose-tools]', '.nb-pose-picker-panel'],
  },
  {
    name: 'camera-picker-open', page: 'camera-live.html?guide-picker=open',
    expectText: ['Choose a pose'],
    expectVisible: ['.nb-pose-picker-panel', '.nb-grid-pose-item', '#pose-picker-close'],
    expectAbsent: ['#pose-picker-search-clear'],
  },
  {
    name: 'camera-picker-loading', page: 'camera-live.html?guide-picker=open&picker-state=loading',
    expectText: ['Loading poses', 'Getting your pose library ready.'],
    expectVisible: ['.nb-pose-picker-panel', '#pose-picker-state'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'camera-picker-error', page: 'camera-live.html?guide-picker=open&picker-state=error',
    expectText: ['Couldn’t load poses', 'Check your connection and try again.', 'Try again'],
    expectVisible: ['.nb-pose-picker-panel', '#pose-picker-state'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'camera-picker-offline', page: 'camera-live.html?guide-picker=open&picker-state=offline',
    expectText: ['You’re offline', 'Showing your last available poses.'],
    expectVisible: ['.nb-pose-picker-panel', '.nb-grid-pose-item'],
  },
  {
    name: 'camera-picker-query', page: 'camera-live.html?guide-picker=open&picker-q=Dancing',
    expectText: ['Choose a pose', 'Dancing'],
    expectVisible: ['.nb-pose-picker-panel', '#pose-picker-search-clear', '.nb-grid-pose-item'],
  },
  {
    name: 'camera-picker-no-match', page: 'camera-live.html?guide-picker=open&picker-q=zzzz',
    expectText: ['No poses match “zzzz”', 'Try a different pose name.'],
    expectVisible: ['.nb-pose-picker-panel', '#pose-picker-state'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'camera-tools', page: 'camera-live.html?settings=open',
    expectText: ['Flash', 'Grid'],
    expectVisible: ['#camera-tools-menu.is-open'],
    expectAbsent: ['[data-pose-tools]'],
  },
  {
    name: 'camera-tools-pose', page: 'camera-live.html?settings=open&pose=dancing&source=community',
    expectText: ['Pose guide', 'Opacity', 'Clear pose'],
    expectVisible: ['#camera-tools-menu.is-open', '[data-pose-tools]', '#clear-pose-row'],
  },
  {
    name: 'camera-pose-overlay', page: 'camera-live.html?pose=dancing&source=community',
    expectText: ['Dancing selected'],
    expectVisible: ['#camera-pose-reference'],
  },
  // Post-tap: popup dismissed, focus returns to the More button (modal.js:33-42).
  {
    name: 'camera-tools-dismissed', page: 'camera-live.html?settings=open', press: 'Escape',
    expectAbsent: ['#camera-tools-menu'],
  },

  // --- poses-list.html ---
  {
    name: 'poses-list', page: 'poses-list.html',
    expectVisible: ['.nb-grid-pose-item'],
    expectAbsent: ['#poses-state-message'],
  },
  {
    name: 'poses-list-loading', page: 'poses-list.html?state=loading',
    expectText: ['Loading poses', 'Getting the pose library ready.'],
    expectVisible: ['#poses-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'poses-list-error', page: 'poses-list.html?state=error',
    expectText: ['Couldn’t load poses', 'Check your connection and try again.', 'Retry'],
    expectVisible: ['#poses-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'poses-list-refresh-error', page: 'poses-list.html?state=refresh-error',
    expectText: ['Couldn’t refresh', 'Your current list is still here. Try again when you’re ready.', 'Retry'],
    expectVisible: ['#poses-state-message', '.nb-grid-pose-item'],
  },
  {
    name: 'poses-list-empty', page: 'poses-list.html?state=empty',
    expectText: ['No poses yet', 'New poses will appear here when they’re available.'],
    expectVisible: ['#poses-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'poses-list-deleted', page: 'poses-list.html?notice=deleted',
    expectText: ['Pose removed', 'The pose is no longer in this collection.'],
    expectVisible: ['#poses-state-message', '.nb-grid-pose-item'],
  },

  // --- search.html ---
  {
    name: 'search-blank', page: 'search.html',
    expectText: ['Recent searches'],
    expectVisible: ['#search-recent-chips'],
    expectAbsent: ['#search-state-message', '#search-results-panel'],
  },
  {
    name: 'search-results', page: 'search.html?q=Warrior',
    expectText: ['YOUR MATCHES', 'Results for “Warrior”'],
    expectVisible: ['#search-results-panel', '.nb-grid-pose-item'],
  },
  // FINDING (headline, assertion-proved): `q=Warrior&source=community` matches ZERO poses —
  // Warrior is a my-poses fixture (fixtures.js:174, category "my-poses" at :202), so the
  // source filter `pose.category === 'community'` (app.js:716-721) excludes it and the page
  // rendered the NO-MATCH surface, not community results. The old search-results-community.png
  // was therefore a distinct-but-wrong reference. A genuinely community query is used instead.
  {
    name: 'search-results-community', page: 'search.html?q=Dancing&source=community',
    expectText: ['YOUR MATCHES', 'Results for “Dancing”'],
    expectVisible: ['#search-results-panel', '.nb-grid-pose-item'],
  },
  {
    name: 'search-loading', page: 'search.html?q=Pose&state=loading',
    expectText: ['Searching', 'Looking through your library and the community.'],
    expectVisible: ['#search-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'search-error', page: 'search.html?state=error',
    expectText: ['Search is paused', 'We could not load results right now. Your query is still here.', 'Try again'],
    expectVisible: ['#search-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'search-no-match', page: 'search.html?q=zzzz',
    expectText: ['No poses match “zzzz”', 'Try a different pose name.'],
    expectVisible: ['#search-state-message'],
    expectAbsent: ['.nb-grid-pose-item'],
  },
  {
    name: 'search-offline', page: 'search.html?q=Pose&state=offline',
    expectText: ['You’re offline', 'Showing your last available poses. Community results may be out of date.'],
    expectVisible: ['#search-state-message', '.nb-grid-pose-item'],
  },

  // --- pose-detail.html ---
  {
    name: 'pose-detail', page: 'pose-detail.html',
    expectText: ['Dancing'],
    expectVisible: ['#detail-content', '#detail-try-pose-btn'],
  },
  {
    name: 'pose-detail-unavailable', page: 'pose-detail.html?state=unavailable',
    expectText: ['Pose unavailable', 'This pose could not be confirmed as published. Return to Poses and try again.', 'Return to Poses'],
    expectVisible: ['#detail-unavailable-state'],
    expectAbsent: ['#detail-content'],
  },

  // --- gallery.html ---
  {
    name: 'gallery', page: 'gallery.html',
    expectVisible: ['.nb-gallery-item'],
  },
  {
    name: 'gallery-filter-today', page: 'gallery.html?filter=today',
    expectVisible: ['.nb-gallery-item', '.nb-gallery-filter.is-active[data-gallery-filter="today"]'],
  },
  // Filter-empty: `filter=custom` + a valid far-past `date` matches no fixture
  // (app.js:507 `item.dateKey === galleryDate`), so `visibleCount === 0` renders the
  // 'No photos in this filter' branch with NO action (app.js:547-551 passes null).
  // NOTE: `?state=empty` is a NO-OP — renderGallery() (app.js:543-552) derives emptiness
  // from visibleCount and never reads getPrototypeState(); with filter=all the fixtures
  // always have photos, so the all-empty gallery is NOT URL-reachable -> NO COUNTERPART
  // (see dlb-reference-manifest.md).
  {
    name: 'gallery-filter-empty', page: 'gallery.html?filter=custom&date=2000-01-01',
    expectText: ['No photos in this filter', 'Try another filter.'],
    expectVisible: ['.nb-gallery-empty-state'],
    expectAbsent: ['.nb-gallery-item', 'text=Open Camera'],
  },

  // --- gallery-detail.html (gal-1 = first GALLERY_FIXTURES id, fixtures.js:310) ---
  {
    name: 'gallery-detail', page: 'gallery-detail.html?id=gal-1',
    expectText: ['Pose Match 1'],
    expectVisible: ['#gallery-detail-content'],
  },
  {
    name: 'gallery-detail-unavailable', page: 'gallery-detail.html?id=does-not-exist',
    expectText: ['Photo unavailable', 'This photo can’t be opened. Return to Gallery to see your current photos.', 'Return to gallery'],
    expectVisible: ['#gallery-unavailable-state', '#gallery-detail-photo'],
    // app.js:641 hides #gallery-detail-content (which carries the empty photo card) and
    // #gallery-detail-actions, but their CSS display:flex (card.css:71, nav-bar) re-displays
    // the empty shells — so only the EMPTY TEXT of the action buttons proves the hidden state.
    expectEmptyText: ['#gallery-detail-actions .nb-btn'],
  },

  // --- gallery-detail-v2.html (frame element is `.phone`, not `.nb-phone`) ---
  {
    name: 'gallery-detail-v2', page: 'gallery-detail-v2.html', selector: '.phone',
    expectVisible: ['#photo'],
  },
  // The loading state resolves itself 700ms after load (line 329) and shows the
  // 'Photo ready' toast for 2600ms (line 316-317) — the capture lands inside that window.
  {
    name: 'gallery-detail-v2-loading', page: 'gallery-detail-v2.html?state=loading', selector: '.phone',
    expectText: ['Photo ready'],
    expectVisible: ['#photo', '#toast.is-visible'],
  },
  {
    name: 'gallery-detail-v2-missing', page: 'gallery-detail-v2.html?state=missing', selector: '.phone',
    expectText: ['Photo unavailable', 'This local file is missing, but the gallery record is still safe to recover.'],
    expectVisible: ['.photo-frame.is-missing', '#empty-photo'],
    expectAbsent: ['#photo'],
  },
  {
    name: 'gallery-detail-v2-deleted', page: 'gallery-detail-v2.html?state=deleted', selector: '.phone',
    expectText: ['Photo deleted', 'The local record has been removed. Return to Gallery to continue.'],
    expectVisible: ['.photo-frame.is-deleted', '#empty-photo'],
    expectAbsent: ['#photo'],
  },

  // --- saved-list.html ---
  {
    name: 'saved-list', page: 'saved-list.html',
    expectVisible: ['.nb-saved-card'],
    expectAbsent: ['#saved-state'],
  },
  {
    name: 'saved-list-loading', page: 'saved-list.html?state=loading',
    expectText: ['Loading saved poses', 'Getting your saved collection ready.'],
    expectVisible: ['#saved-state'],
    expectAbsent: ['.nb-saved-card'],
  },
  {
    name: 'saved-list-error', page: 'saved-list.html?state=error',
    expectText: ['Couldn’t load saved poses', 'Check your connection and try again.', 'Try again'],
    expectVisible: ['#saved-state'],
    expectAbsent: ['.nb-saved-card'],
  },
  {
    name: 'saved-list-offline-no-cache', page: 'saved-list.html?state=offline-no-cache',
    expectText: ['Saved poses aren’t available offline', 'Reconnect to load your saved collection.', 'Try again'],
    expectVisible: ['#saved-state'],
    expectAbsent: ['.nb-saved-card'],
  },
  {
    name: 'saved-list-empty', page: 'saved-list.html?state=empty',
    expectText: ['No saved poses yet', 'Save poses from Community to find them here.', 'Browse Community'],
    expectVisible: ['#saved-state'],
    expectAbsent: ['.nb-saved-card'],
  },
  {
    name: 'saved-list-offline-stale', page: 'saved-list.html?state=offline-stale',
    expectText: ['Offline · showing saved poses from last confirmed read.'],
    expectVisible: ['#saved-offline-banner', '.nb-saved-card'],
  },
  {
    name: 'saved-list-refresh-error', page: 'saved-list.html?state=refresh-error',
    expectText: ['Couldn’t refresh', 'Showing your saved poses. Try again when you’re ready.', 'Retry'],
    expectVisible: ['#saved-state', '.nb-saved-card'],
  },

  // --- pose-detail-saved.html ---
  {
    name: 'pose-detail-saved', page: 'pose-detail-saved.html?id=dancing&source=saved&state=saved',
    expectText: ['Dancing', 'Saved'],
    expectVisible: ['#saved-detail-content', '#saved-toggle.is-confirmed'],
  },
  {
    name: 'pose-detail-saved-unsaved', page: 'pose-detail-saved.html?id=dancing&source=community&state=unsaved',
    expectText: ['Dancing', 'Save'],
    expectVisible: ['#saved-detail-content'],
    expectAbsent: ['#saved-toggle.is-confirmed'],
  },
  {
    name: 'pose-detail-saved-error', page: 'pose-detail-saved.html?id=dancing&source=saved&state=error',
    expectText: ['Couldn’t update Saved', 'Your confirmed state is unchanged.', 'Try again', 'Saved'],
    expectVisible: ['#saved-detail-state', '#saved-toggle.is-confirmed'],
  },
  // NOTE: `?auth=guest` is NOT captured: pose-detail-saved.js:42 branches on auth only inside
  // toggle.onclick, and the gate action (pose-detail-saved.js:36) NAVIGATES to
  // sign-in-prompt.html — an out-of-slice surface. No distinct visual at load -> NO COUNTERPART.

  // --- NOT URL-reachable: post-tap captures on the frozen prototype ---
  {
    name: 'account-signed-out', page: 'account.html', tap: '#account-sign-out',
    expectText: ['Signed out', 'Sign in again to access your Saved poses.', 'No active session'],
    expectVisible: ['#account-status'],
    expectAbsent: ['#account-sign-out'],
  },
  {
    name: 'sign-in-failure', page: 'sign-in-prompt.html?state=fail', tap: '#google-sign-in',
    expectText: ['Sign-in failed', 'Try again to continue.', 'Try again'],
    expectVisible: ['#sign-in-error'],
  },
];

/** Number of VISIBLE matches for a css selector, or for an exact text when the entry
 *  is written as `text=<exact string>` (used where the observable is a text control,
 *  e.g. the all-empty-only `Open Camera` action). */
async function visibleCount(page, selector) {
  const loc = selector.startsWith('text=')
    ? page.getByText(selector.slice(5), { exact: true })
    : page.locator(selector);
  const total = await loc.count();
  let visible = 0;
  for (let i = 0; i < total; i += 1) {
    if (await loc.nth(i).isVisible()) visible += 1;
  }
  return visible;
}

/** Assert one shot's declared observables against the live page. Collects EVERY failure
 *  for the shot (never aborts at the first) and returns the failure list. */
async function assertState(page, shot) {
  const failures = [];
  for (const text of shot.expectText ?? []) {
    if ((await page.getByText(text, { exact: true }).count()) < 1) {
      failures.push(`expectText missing: "${text}"`);
    }
  }
  for (const selector of shot.expectVisible ?? []) {
    if ((await visibleCount(page, selector)) < 1) {
      failures.push(`expectVisible not visible: "${selector}"`);
    }
  }
  for (const selector of shot.expectAbsent ?? []) {
    if ((await visibleCount(page, selector)) > 0) {
      failures.push(`expectAbsent still visible: "${selector}"`);
    }
  }
  for (const selector of shot.expectEmptyText ?? []) {
    const loc = page.locator(selector);
    const total = await loc.count();
    if (total < 1) {
      failures.push(`expectEmptyText no match: "${selector}"`);
      continue;
    }
    for (let i = 0; i < total; i += 1) {
      const text = (await loc.nth(i).innerText()).trim();
      if (text !== '') {
        failures.push(`expectEmptyText not empty: "${selector}" -> "${text.slice(0, 40)}"`);
      }
    }
  }
  return failures;
}

const browser = await chromium.launch();
// Wide viewport so the `@media (max-width: 480px)` rule does not collapse the fixed 390x844
// device frame into a full-viewport one — we want the exact prototype frame.
const page = await browser.newPage({
  viewport: { width: 1024, height: 1000 },
  deviceScaleFactor: 2,
});

let written = 0;
const assertionFailures = [];
for (const shot of SHOTS) {
  const url = 'file://' + path.join(root, 'docs/prototype/screens', shot.page);
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(1200); // fonts + remote fixture imagery

  if (shot.tap) {
    await page.click(shot.tap);
    await page.waitForTimeout(800); // empty-state render / focus ring
  }
  if (shot.press) {
    await page.keyboard.press(shot.press);
    await page.waitForTimeout(800);
  }

  // Capture-time state assertions: prove the page is in the requested state BEFORE the
  // screenshot. Failures never abort the shot — they are collected and reported at the end.
  const stateFailures = await assertState(page, shot);
  if (stateFailures.length) {
    for (const failure of stateFailures) {
      console.error(`STATE ASSERT FAILED ${shot.name}: ${failure}`);
      assertionFailures.push(`${shot.name}: ${failure}`);
    }
  }

  const phone = page.locator(shot.selector ?? '.nb-phone').first();
  const target = (await phone.count()) ? phone : page.locator('body');
  const box = await target.boundingBox();
  await target.screenshot({ path: path.join(outDir, `${shot.name}.png`) });
  written += 1;
  const driven = shot.tap ? ` tap:${shot.tap}` : shot.press ? ` key:${shot.press}` : '';
  console.log(`${shot.name.padEnd(28)} ${Math.round(box.width)}x${Math.round(box.height)}  ${shot.page}${driven}`);
}

await browser.close();

// Distinctness guard: no two reference PNGs may be byte-identical. A duplicate means the
// state's driver was a no-op (e.g. a `?state=` the page ignores) — the shot documents a
// state that does not exist instead of the one requested. This class of defect shipped once
// (gallery-empty / pose-detail-saved-guest were byte-identical to their base states), so the
// check lives here, not in reviewer judgement. Exit 1 with the offending pair names.
const hashes = new Map();
const duplicates = [];
for (const file of fs.readdirSync(outDir).filter((f) => f.endsWith('.png')).sort()) {
  const digest = createHash('md5').update(fs.readFileSync(path.join(outDir, file))).digest('hex');
  if (hashes.has(digest)) duplicates.push(`${hashes.get(digest)} == ${file}`);
  else hashes.set(digest, file);
}
if (duplicates.length) {
  console.error(`DUPLICATE reference PNGs (byte-identical):\n  ${duplicates.join('\n  ')}`);
  process.exit(1);
}
console.log(`Distinctness guard: ${hashes.size} unique PNGs, no duplicates.`);

if (assertionFailures.length) {
  console.error(`\n${assertionFailures.length} STATE ASSERT FAILURE(S) across ${new Set(assertionFailures.map((f) => f.split(':')[0])).size} reference(s).`);
  process.exit(1);
}
console.log('State assertions: all green.');
console.log(`\nWrote ${written} reference shots to ${path.relative(root, outDir)}/`);
