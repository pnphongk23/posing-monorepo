# DL-B Phase 1 — verified prototype URL-state map (AC6 harness scope)

Read from `docs/prototype/**` at HEAD `3a4be1c`. Every parameter below was verified by
reading the consuming JS, not guessed. Source line cited per row.

Rule reminder: the prototype is the frozen reference. Nothing under `docs/prototype/screens/**`
or `docs/prototype/styles/**` may be edited to make a comparison pass.

## Global state parameter

`scripts/fixtures.js:287` — `getPrototypeState()` returns `params.get("state") || "ready"`.
So `?state=<loading|error|empty|offline|refresh-error|unavailable>` is honoured by every
screen that calls it. Valid values differ per screen; the per-screen rows below are the
authoritative list.

## Reference frame

`.nb-phone` renders 390x844 pt; existing references are 780x1688 px (deviceScaleFactor 2).
Keep the wide 1024x1000 viewport (otherwise `@media (max-width: 480px)` collapses the frame)
and the `.nb-phone` element screenshot. Both rules already exist in
`scripts/prototype-reference-shots.mjs`.

## camera-live.html

| State | URL | Source |
|---|---|---|
| default (no pose, tools closed) | `camera-live.html` | — |
| pose picker sheet open | `camera-live.html?guide-picker=open` | `scripts/guide-picker.js:231` |
| pose picker loading | `...?guide-picker=open&picker-state=loading` | `guide-picker.js:18,109` |
| pose picker error (+Try again) | `...?guide-picker=open&picker-state=error` | `guide-picker.js:118` |
| pose picker offline | `...?guide-picker=open&picker-state=offline` | `guide-picker.js:146` |
| pose picker query, populated | `...?guide-picker=open&picker-q=Dancing` | `guide-picker.js:17` |
| pose picker no-match | `...?guide-picker=open&picker-q=zzzz` | `guide-picker.js:130-140` |
| camera tools popup (Flash+Grid only) | `camera-live.html?settings=open` | `scripts/modal.js:45` |
| camera tools popup + pose-guide rows | `camera-live.html?settings=open&pose=dancing&source=community` | `modal.js:45` + `scripts/app.js:282-284,340` |
| pose reference overlay on preview | `camera-live.html?pose=dancing&source=community` | `app.js:282-284` |

Pose-guide rows (`data-pose-tools`: Pose guide / Opacity / Line color / Clear pose) are
`hidden` unless a pose resolves — `app.js:290-294,339-344`. The Flash/Grid-only popup and the
pose-guide popup are therefore two distinct references.

## poses-list.html

| State | URL | Source |
|---|---|---|
| default collection | `poses-list.html` | — |
| loading | `poses-list.html?state=loading` | `app.js:74,92` |
| error (+retry) | `poses-list.html?state=error` | `app.js:100` |
| refresh-error (warning tone) | `poses-list.html?state=refresh-error` | `app.js:115` |
| empty | `poses-list.html?state=empty` | `app.js:126` |
| deleted-notice (success tone) | `poses-list.html?notice=deleted` | `app.js:137` |

Dock: `poses-list.html` calls `initTabBar('poses')` (`scripts/tab-bar.js` at end of the page).

## search.html

| State | URL | Source |
|---|---|---|
| blank / discovery | `search.html` | `app.js:778` |
| results populated | `search.html?q=Warrior` | `app.js:707` |
| results filtered source | `search.html?q=Warrior&source=community` | `app.js:706-708` |
| loading | `search.html?q=Pose&state=loading` | `app.js:798` |
| error (+retry) | `search.html?state=error` | `app.js:810` |
| empty / no-match | `search.html?q=zzzz` | `app.js:828,848` |
| offline | `search.html?q=Pose&state=offline` | `app.js:829,867` |

## pose-detail.html

| State | URL | Source |
|---|---|---|
| default (dancing / community) | `pose-detail.html` | `app.js:148-149` |
| unavailable (error + Return to Poses) | `pose-detail.html?state=unavailable` | `app.js:150-151,167` |

## gallery.html

| State | URL | Source |
|---|---|---|
| default (all photos) | `gallery.html` | `app.js:495-498` |
| filter with no photos | `gallery.html?filter=custom&date=2000-01-01` | `app.js:499,507,547` |
| ~~all-empty (+Open Camera CTA)~~ | ~~`gallery.html?state=empty`~~ — **NO COUNTERPART, not URL-reachable** | `renderGallery()` derives emptiness from `visibleCount === 0` (`app.js:543-552`) and never reads `getPrototypeState()`; with `filter=all` the fixture set is never empty (`app.js:476-477`). Verified: `gallery.html?state=empty` renders **byte-identical** to `gallery.html` (AE = 0). Emptying the fixtures would mean editing the frozen prototype. |

`filter` valid set = `{all,today,week,month,custom}` (`app.js:495`); `custom` without a valid
`?date=YYYY-MM-DD` degrades back to `all` (`app.js:499`).

## gallery-detail.html

| State | URL | Source |
|---|---|---|
| default | `gallery-detail.html?id=<GALLERY_FIXTURES id>` | `app.js:628` |
| unavailable (error + Return to gallery) | `gallery-detail.html?id=does-not-exist` | `app.js:641-652` |

## gallery-detail-v2.html

| State | URL | Source |
|---|---|---|
| ready | `gallery-detail-v2.html` | inline script line 296 |
| loading | `gallery-detail-v2.html?state=loading` | line 325 |
| missing photo (error, geometry preserved) | `gallery-detail-v2.html?state=missing` | line 334 |
| deleted (error) | `gallery-detail-v2.html?state=deleted` | line 340 |

## saved-list.html

| State | URL | Source |
|---|---|---|
| ready | `saved-list.html` | `scripts/saved-list.js:5` |
| loading | `saved-list.html?state=loading` | saved-list.js:41 |
| error (+Try again) | `saved-list.html?state=error` | saved-list.js:42 |
| offline, no cache | `saved-list.html?state=offline-no-cache` | saved-list.js:43 |
| empty (+Browse Community) | `saved-list.html?state=empty` | saved-list.js:44 |
| offline-stale (banner) | `saved-list.html?state=offline-stale` | saved-list.js:46 |
| refresh-error (warning tone) | `saved-list.html?state=refresh-error` | saved-list.js:47 |

## pose-detail-saved.html

| State | URL | Source |
|---|---|---|
| saved | `pose-detail-saved.html?id=dancing&source=saved&state=saved` | `scripts/pose-detail-saved.js:3-5` |
| unsaved | `pose-detail-saved.html?id=dancing&source=community&state=unsaved` | pose-detail-saved.js:3 |
| mutation error (error tone) | `pose-detail-saved.html?id=dancing&source=saved&state=error` | pose-detail-saved.js:42,49 |
| ~~sign-in gate (guest)~~ | ~~`...&auth=guest`~~ — **NO COUNTERPART** | `auth=guest` is only read inside `toggle.onclick` (`pose-detail-saved.js:42`), so it has no load-time visual (verified byte-identical, AE = 0). `prompt()` at `:36` **navigates** to `sign-in-prompt.html?intent=save`, an unchanged out-of-slice surface. |

## NOT URL-reachable (must be driven by a tap; no reference-by-URL exists)

| State | How it is reached | Source |
|---|---|---|
| account signed-out success state | tap `#account-sign-out` on `account.html` | `scripts/account.js:17-27` |
| sign-in-prompt failure (error tone) | open `sign-in-prompt.html?state=fail`, then tap `#google-sign-in` | `scripts/sign-in-prompt.js:13` |
| camera tools popup dismissed / focus back on More | tap outside or Escape | `modal.js:33-42` |

`sign-in-prompt.html?state=fail` alone renders no error — the error state is only produced by
the click handler, so the reference must be a post-tap capture.

## pose-guide.html

Now a compatibility redirect: meta-refresh + `location.replace('camera-live.html?guide-picker=open')`
(`screens/pose-guide.html`). It is NOT an independent reference. The existing
`reference/pose-guide.png` must be deleted and replaced by the camera pose-picker state.
