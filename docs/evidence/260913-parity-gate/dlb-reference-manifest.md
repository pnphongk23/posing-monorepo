# DL-B1 — reference manifest (260913 parity gate)

Companion to `dlb-state-map.md` (the authoritative state list). Produced by
`node scripts/prototype-reference-shots.mjs`; every PNG verified 780x1688 px via
`magick identify` (wide 1024x1000 viewport, `.nb-phone` element screenshot at
deviceScaleFactor 2; gallery-detail-v2 uses its own `.phone` frame element).

Every row carries four verification columns:

- **expected-visible** — the exact expected strings, quoted; `(none)` where the state carries no text.
- **expected-controls** — the control that must be PRESENT and the control that must be ABSENT.
- **source** — prototype file:line fixing those expectations.
- **confirmed-by** — exactly one of: `dom-asserted` (the capture-time assertion in
  `scripts/prototype-reference-shots.mjs` passed against the live page), `measured` (a numeric
  pixel probe run by `scripts/validate-reference-states.py`, percentage quoted), `opened`
  (the PNG was visually inspected), or `UNCONFIRMED` (inferred from the URL only).
  Tone rows validated at the stated magnitude get `measured`; rows whose DOM assertions ran get
  `dom-asserted` even when a tone probe also ran — the DOM assertion is the stronger evidence.

Apostrophes are the typographic U+2019 (’) exactly as in the prototype source.

## URL-reachable references

| Reference | Exact URL | expected-visible | expected-controls | source | confirmed-by |
|---|---|---|---|---|---|
| camera-live | `camera-live.html` | (none) | PRESENT: shutter bar, More + Choose pose chrome; ABSENT: `#camera-tools-menu`, `[data-pose-tools]`, picker panel | screens/camera-live.html:64,78; app.js:290-294,345 | dom-asserted |
| camera-picker-open | `camera-live.html?guide-picker=open` | 'Choose a pose' | PRESENT: `.nb-pose-picker-panel`, pose cards (`.nb-grid-pose-item`), Close; ABSENT: `#pose-picker-search-clear` (no query yet) | screens/camera-live.html:163-181; guide-picker.js:231,109 | dom-asserted |
| camera-picker-loading | `camera-live.html?guide-picker=open&picker-state=loading` | 'Loading poses', 'Getting your pose library ready.' | PRESENT: `.nb-pose-picker-panel`, `#pose-picker-state` (white loading surface); ABSENT: `.nb-grid-pose-item` | guide-picker.js:109-115 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| camera-picker-error | `camera-live.html?guide-picker=open&picker-state=error` | 'Couldn’t load poses', 'Check your connection and try again.', 'Try again' | PRESENT: `#pose-picker-state` error surface; ABSENT: `.nb-grid-pose-item` | guide-picker.js:118-128 | dom-asserted, measured (#FFF4F5 = 11.96%) |
| camera-picker-offline | `camera-live.html?guide-picker=open&picker-state=offline` | 'You’re offline', 'Showing your last available poses.' | PRESENT: `#pose-picker-state` offline surface + cards (stale content shown); ABSENT: — | guide-picker.js:146-149 | dom-asserted, measured (#FED766 = 7.94%) |
| camera-picker-query | `camera-live.html?guide-picker=open&picker-q=Dancing` | 'Choose a pose', 'Dancing' (label on the matching card) | PRESENT: `.nb-pose-picker-panel`, `#pose-picker-search-clear` (query present), cards; ABSENT: state surface | guide-picker.js:17,54-56 | dom-asserted |
| camera-picker-no-match | `camera-live.html?guide-picker=open&picker-q=zzzz` | 'No poses match “zzzz”', 'Try a different pose name.' | PRESENT: `#pose-picker-state` empty surface; ABSENT: `.nb-grid-pose-item` | guide-picker.js:130-140 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| camera-tools | `camera-live.html?settings=open` | 'Flash', 'Grid' | PRESENT: `#camera-tools-menu.is-open` with Flash+Grid rows; ABSENT: visible `[data-pose-tools]` (no pose selected) | screens/camera-live.html:78-93,102-103; app.js:290-294,339-344; modal.js:45 | dom-asserted |
| camera-tools-pose | `camera-live.html?settings=open&pose=dancing&source=community` | 'Pose guide', 'Opacity', 'Clear pose' | PRESENT: `#camera-tools-menu.is-open`, visible `[data-pose-tools]` rows, `#clear-pose-row` | screens/camera-live.html:102-130; app.js:338-344; modal.js:45 | dom-asserted |
| camera-pose-overlay | `camera-live.html?pose=dancing&source=community` | 'Dancing selected' (success camera status) | PRESENT: visible `#camera-pose-reference` overlay; ABSENT: tools popup | app.js:282-284,352-355 | dom-asserted |
| poses-list | `poses-list.html` | (none — populated grid) | PRESENT: `.nb-grid-pose-item` cards, dock; ABSENT: `#poses-state-message` | app.js:80-86,141; screens/poses-list.html:62 | dom-asserted |
| poses-list-loading | `poses-list.html?state=loading` | 'Loading poses', 'Getting the pose library ready.' | PRESENT: `#poses-state-message` loading surface; ABSENT: `.nb-grid-pose-item` | app.js:92-97 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| poses-list-error | `poses-list.html?state=error` | 'Couldn’t load poses', 'Check your connection and try again.', 'Retry' | PRESENT: `#poses-state-message` error surface; ABSENT: `.nb-grid-pose-item` | app.js:100-112 | dom-asserted, measured (#FFF4F5 = 12.68%) |
| poses-list-refresh-error | `poses-list.html?state=refresh-error` | 'Couldn’t refresh', 'Your current list is still here. Try again when you’re ready.', 'Retry' | PRESENT: `#poses-state-message` WARNING surface + cards retained; ABSENT: — | app.js:114-125 | dom-asserted, measured (#FED766 = 15.14%) |
| poses-list-empty | `poses-list.html?state=empty` | 'No poses yet', 'New poses will appear here when they’re available.' | PRESENT: `#poses-state-message` empty surface; ABSENT: `.nb-grid-pose-item` | app.js:126-131 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| poses-list-deleted | `poses-list.html?notice=deleted` | 'Pose removed', 'The pose is no longer in this collection.' | PRESENT: `#poses-state-message` SUCCESS surface + cards retained | app.js:135-139 | dom-asserted, measured (#B5E2B9 = 8.10%) |
| search-blank | `search.html` | 'Recent searches' | PRESENT: `#search-recent-chips` (3 chips); ABSENT: `#search-state-message`, `#search-results-panel` | screens/search.html:60-73; app.js:781-788 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| search-results | `search.html?q=Warrior` | 'YOUR MATCHES', 'Results for “Warrior”' | PRESENT: `#search-results-panel`, `.nb-grid-pose-item` cards | app.js:792-795,851-854 | dom-asserted |
| search-results-community | `search.html?q=Dancing&source=community` | 'YOUR MATCHES', 'Results for “Dancing”' | PRESENT: `#search-results-panel`, cards | app.js:714-722,792-795 | dom-asserted — **URL CORRECTED, see corrections below** |
| search-loading | `search.html?q=Pose&state=loading` | 'Searching', 'Looking through your library and the community.' | PRESENT: `#search-state-message`; ABSENT: `.nb-grid-pose-item` | app.js:798-807 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| search-error | `search.html?state=error` | 'Search is paused', 'We could not load results right now. Your query is still here.', 'Try again' | PRESENT: `#search-state-message` error surface; ABSENT: `.nb-grid-pose-item` | app.js:810-822 | dom-asserted, measured (#FFF4F5 = 14.53%) |
| search-no-match | `search.html?q=zzzz` | 'No poses match “zzzz”', 'Try a different pose name.' | PRESENT: `#search-state-message` empty surface; ABSENT: `.nb-grid-pose-item` | app.js:828,843-849 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| search-offline | `search.html?q=Pose&state=offline` | 'You’re offline', 'Showing your last available poses. Community results may be out of date.' | PRESENT: `#search-state-message` offline surface + stale cards retained | app.js:829,866-868 | dom-asserted, measured (#FED766 = 10.99%) |
| pose-detail | `pose-detail.html` | 'Dancing' (pose title) | PRESENT: `#detail-content`, `#detail-try-pose-btn` | app.js:148-149,191-204 | dom-asserted |
| pose-detail-unavailable | `pose-detail.html?state=unavailable` | 'Pose unavailable', 'This pose could not be confirmed as published. Return to Poses and try again.', 'Return to Poses' | PRESENT: `#detail-unavailable-state` error surface; ABSENT: `#detail-content` | app.js:150-151,167-174 | dom-asserted, measured (#FFF4F5 = 13.70%) |
| gallery | `gallery.html` | (none — populated grid) | PRESENT: `.nb-gallery-item` photos, 5 filter chips | app.js:543-582 | dom-asserted |
| gallery-filter-today | `gallery.html?filter=today` | (none — populated grid) | PRESENT: `.nb-gallery-item`, `.nb-gallery-filter.is-active[data-gallery-filter="today"]`; ABSENT: state surface | app.js:495-505,523 | dom-asserted |
| gallery-filter-empty | `gallery.html?filter=custom&date=2000-01-01` | 'No photos in this filter', 'Try another filter.' | PRESENT: `.nb-gallery-empty-state`; ABSENT: `.nb-gallery-item`, 'Open Camera' action (all-empty only) | app.js:543-551 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| gallery-detail | `gallery-detail.html?id=gal-1` | 'Pose Match 1' | PRESENT: `#gallery-detail-content` (photo + actions) | app.js:630-638; fixtures.js:310-314 | dom-asserted |
| gallery-detail-unavailable | `gallery-detail.html?id=does-not-exist` | 'Photo unavailable', 'This photo can’t be opened. Return to Gallery to see your current photos.', 'Return to gallery' | PRESENT: `#gallery-unavailable-state`, empty `#gallery-detail-photo` placeholder; EMPTY: nav action buttons (`#gallery-detail-actions .nb-btn` render no label — CSS re-displays the hidden shells) | app.js:641-652 | dom-asserted, measured (#FFF4F5 = 13.64%) |
| gallery-detail-v2 | `gallery-detail-v2.html` | (none) | PRESENT: `#photo` media block | screens/gallery-detail-v2.html:250,296 | dom-asserted |
| gallery-detail-v2-loading | `gallery-detail-v2.html?state=loading` | 'Photo ready' (toast; state self-resolves after 700ms) | PRESENT: `#photo`, `#toast.is-visible` | screens/gallery-detail-v2.html:325-332 | dom-asserted |
| gallery-detail-v2-missing | `gallery-detail-v2.html?state=missing` | 'Photo unavailable', 'This local file is missing, but the gallery record is still safe to recover.' | PRESENT: `.photo-frame.is-missing`, `#empty-photo`; ABSENT: `#photo` | screens/gallery-detail-v2.html:334-339 | dom-asserted, measured (#FFF4F5 = 0.00% — F2: uses #EEE9E1, 48.0%) |
| gallery-detail-v2-deleted | `gallery-detail-v2.html?state=deleted` | 'Photo deleted', 'The local record has been removed. Return to Gallery to continue.' | PRESENT: `.photo-frame.is-deleted`, `#empty-photo`; ABSENT: `#photo` | screens/gallery-detail-v2.html:340-345 | dom-asserted, measured (#FFF4F5 = 0.00% — F2) |
| saved-list | `saved-list.html` | (none — populated grid) | PRESENT: `.nb-saved-card` cards; ABSENT: `#saved-state` | saved-list.js:5,45 | dom-asserted |
| saved-list-loading | `saved-list.html?state=loading` | 'Loading saved poses', 'Getting your saved collection ready.' | PRESENT: `#saved-state`; ABSENT: `.nb-saved-card` | saved-list.js:41 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| saved-list-error | `saved-list.html?state=error` | 'Couldn’t load saved poses', 'Check your connection and try again.', 'Try again' | PRESENT: `#saved-state` error surface; ABSENT: `.nb-saved-card` | saved-list.js:42 | dom-asserted, measured (#FFF4F5 = 12.18%) |
| saved-list-offline-no-cache | `saved-list.html?state=offline-no-cache` | 'Saved poses aren’t available offline', 'Reconnect to load your saved collection.', 'Try again' | PRESENT: `#saved-state` offline surface; ABSENT: `.nb-saved-card` | saved-list.js:43 | dom-asserted, measured (#FED766 = 11.99%) |
| saved-list-empty | `saved-list.html?state=empty` | 'No saved poses yet', 'Save poses from Community to find them here.', 'Browse Community' | PRESENT: `#saved-state` empty surface; ABSENT: `.nb-saved-card` | saved-list.js:44 | dom-asserted, measured (#FFF4F5 = 0.00%) |
| saved-list-offline-stale | `saved-list.html?state=offline-stale` | 'Offline · showing saved poses from last confirmed read.' | PRESENT: `#saved-offline-banner` (yellow), `.nb-saved-card` stale cards | saved-list.js:46; screens/saved-list.html:14 | dom-asserted, measured (#FED766 = 5.88%) |
| saved-list-refresh-error | `saved-list.html?state=refresh-error` | 'Couldn’t refresh', 'Showing your saved poses. Try again when you’re ready.', 'Retry' | PRESENT: `#saved-state` WARNING surface + cards retained | saved-list.js:47 | dom-asserted, measured (#FED766 = 14.94%) |
| pose-detail-saved | `pose-detail-saved.html?id=dancing&source=saved&state=saved` | 'Dancing', 'Saved' (toggle label) | PRESENT: `#saved-detail-content`, `#saved-toggle.is-confirmed` | pose-detail-saved.js:3-5,40 | dom-asserted |
| pose-detail-saved-unsaved | `pose-detail-saved.html?id=dancing&source=community&state=unsaved` | 'Dancing', 'Save' (toggle label) | PRESENT: `#saved-detail-content`; ABSENT: `#saved-toggle.is-confirmed` (toggle unconfirmed) | pose-detail-saved.js:3,39-40 | dom-asserted |
| pose-detail-saved-error | `pose-detail-saved.html?id=dancing&source=saved&state=error` | 'Couldn’t update Saved', 'Your confirmed state is unchanged.', 'Try again', 'Saved' | PRESENT: `#saved-detail-state` error surface, `#saved-toggle.is-confirmed` | pose-detail-saved.js:42,49-58 | dom-asserted, measured (#FFF4F5 = 12.24%) |

## Post-tap references (NOT URL-reachable; driven on the frozen prototype via Playwright)

| Reference | Drive | expected-visible | expected-controls | source | confirmed-by |
|---|---|---|---|---|---|
| account-signed-out | click `#account-sign-out` on `account.html` | 'Signed out', 'Sign in again to access your Saved poses.', 'No active session' | PRESENT: `#account-status` success surface; ABSENT: `#account-sign-out` (hidden after tap) | scripts/account.js:17-27 | dom-asserted, measured (#B5E2B9 = 8.12%) |
| sign-in-failure | click `#google-sign-in` on `sign-in-prompt.html?state=fail` | 'Sign-in failed', 'Try again to continue.', 'Try again' | PRESENT: `#sign-in-error` error surface inside the still-open modal | scripts/sign-in-prompt.js:13 | dom-asserted, measured (#FFF4F5 = 9.67%) |
| camera-tools-dismissed | Escape on `camera-live.html?settings=open` | (none) | ABSENT: `#camera-tools-menu` (popup closed, focus back on More) | scripts/modal.js:33-42 | dom-asserted |

## Corrections made by the state-assertion pass

1. **`search-results-community.png` was a wrong-state reference (replaced).** The old URL
   `?q=Warrior&source=community` matches ZERO poses — `Warrior` is a `my-poses` fixture
   (`scripts/fixtures.js:174`, category `"my-poses"` at `:202`), so the community filter
   (`app.js:716-721`) excluded it and the page rendered the NO-MATCH surface
   ('No poses match “Warrior”') instead of community results. The capture-time assertion
   `expectVisible '.nb-grid-pose-item'` failed and proved it. The reference now uses
   `?q=Dancing&source=community` (a genuine community fixture, `fixtures.js:30-36`), asserted
   green. The old PNG was hash-distinct, so the distinctness guard alone could not catch this —
   exactly the distinct-but-wrong failure mode the checklist warns about.
2. **Two references were STALE against the frozen prototype at HEAD `3a4be1c`:**
   `camera-live.png` and `poses-list.png` were committed at prototype revision `5b98a3b` and
   differed from a fresh capture of the unchanged URLs (camera-live 0.99% AE in the header and
   chip band; poses-list 43.43% AE — the grid content changed with the prototype). Both were
   regenerated from the same URLs; assertions now pass against HEAD. No URL changed for these two.
3. **`gallery-detail-unavailable`: the hidden-state proof is EMPTY TEXT, not visibility.**
   `app.js:641-652` sets `hidden` on `#gallery-detail-content` and `#gallery-detail-actions`,
   but their own CSS `display: flex` (`styles/components/card.css:71`, nav-bar rules) re-displays
   the empty shells — an `expectAbsent '#gallery-detail-actions'` assertion CANNOT hold against
   the frozen prototype. The honest observable is that the action buttons render no label
   (`expectEmptyText '#gallery-detail-actions .nb-btn'`) and the empty bordered photo placeholder
   stays visible. A native app must therefore prove unavailability by ABSENT CONTENT, not absent
   chrome — worth checking in Phase 2.

## Deletions / replacements

- `reference/pose-guide.png` DELETED — `pose-guide.html` is now a redirect to
  `camera-live.html?guide-picker=open`; `camera-picker-open.png` is the replacement reference.
- Distinctness guard: `scripts/prototype-reference-shots.mjs` md5-hashes every output PNG
  and exits 1 naming any byte-identical pair. Now complemented by per-state DOM assertions
  (collect-all, exit non-zero) — the distinct-but-wrong class above is what the guard misses.

## NO COUNTERPART (state exists in the contract, no URL-reachable prototype visual)

| State | Why | Evidence |
|---|---|---|
| gallery all-empty (`?state=empty`) | `renderGallery()` derives emptiness from `visibleCount === 0` and never reads `getPrototypeState()`; with `filter=all` the fixture gallery always has photos, and emptying fixtures would edit the frozen prototype. DELETED `gallery-empty.png` (was byte-identical to `gallery.png`, AE=0). | docs/prototype/scripts/app.js:543-552; CTA branch only when `filter === 'all'`, app.js:549-551 |
| pose-detail-saved guest gate (`?auth=guest`) | `auth=guest` is only read inside `toggle.onclick`; at load the page renders identically to the saved state. The gate action is a NAVIGATION to `sign-in-prompt.html` (out-of-slice surface; report 3.8 scopes only the sign-in FAILURE state). DELETED `pose-detail-saved-guest.png` (was byte-identical to `pose-detail-saved.png`, AE=0). | docs/prototype/scripts/pose-detail-saved.js:36,42 |

## Tone magnitudes (scripts/validate-reference-states.py, exact-hex frame fraction)

Present-threshold 3% of frame; absent-ceiling 2% (the shared `#FED766` accent-yellow noise
band is ≤1%, checklist item 2). All 29 tone assertions green; per-row numbers are quoted in
the tables above (`measured`). gallery-detail-v2 missing/deleted assert the ABSENCE of the
component error tone (0.00%) per finding F2 — the page renders its own `#EEE9E1` surface.
