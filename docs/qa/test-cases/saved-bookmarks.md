# Saved poses (FEAT-013, redesigned build 18)

Business behaviour of the Saved surface: what a user can keep, see, and lose. Saved is a **pushed
destination** (header with Back, no dock), reached from Settings → Library → Saved and from the Poses More
menu. It is account-scoped: the list belongs to the signed-in account and only to it.

Board source: `/tmp/ds-261030/export-c/06-board01..10.png`. Gap source: `/tmp/gap/05-06.md` §06. The board
slice landed in `1925f5c` + `6eab7c9` (undo, offline rows, board copy) — present in **1.1 (18)** but
**not** in the 1.1 (17) build `a03d03a`, where they were a regression-only pass.

Status legend: `automated:` = committed flow that passes, `draft:` = flow in
`docs/qa/redesign-drafts/saved-paywall/` (not yet run), `unit:` = XCTest only, `pending` = blocked on an id
or on data, `out of scope 1.1` = agreed out of this release.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SAV-001 | P0 | accounts on, signed out | 1. Launch. 2. Open the Poses More menu, tap Saved | The gate, not a fake list: `saved.signIn` with "Sign in to see saved poses" / "Your saved poses sync across your devices." and one **Sign in** action. No rows, no spinner, no error | automated: TC-SAV-001-saved-signed-out.yaml (runs on 17 and 18) |
| TC-SAV-002 | P1 | signed in, pose not yet saved | 1. Open any pose. 2. Tap Save (`poseDetail.saveButton`). 3. Settings → Library → Saved | The pose is listed (`poses.first-card` for the first row): "saved" and "listed" are the same fact | automated: TC-SAV-002-saved-list-loaded.yaml |
| TC-SAV-003 | P1 | signed in, at least one saved pose (the flow removes them all) | 1. Settings → Saved. 2. Unsave from the row. 3. Leave and re-enter Saved | Gone after the reload, with the empty state shown — a removal that survived a fresh load, not a local hide | automated: TC-SAV-003-unsave-removes.yaml |
| TC-SAV-004 | P1 | signed in, nothing saved | 1. Settings → Library → Saved | "No saved poses yet" / "Tap Save on any pose to keep it here." and one **Browse poses** (`saved.browseCommunity`) that returns to Poses. No error styling, no count text | automated: TC-SAV-004-empty-browse.yaml |
| TC-SAV-005 | P1 | signed in, one saved pose | 1. Tap the saved pose. 2. Tap "Try this pose" (`poseDetail.use`) | The detail opens (`poseDetail.title`) and its Try action opens the camera with that pose; the row is a link, so a tap outside the unsave control never removes anything | pending-e2e |
| TC-SAV-006 | P1 | signed in, saved poses, device offline | 1. Open Saved offline (evidence run: `-AIPoseSavedOfflineFixture 2`) | `saved.offlineBanner` "You're offline. Changes will sync when you're back online." above the rows; the first rows stay usable, rows the cache cannot serve are dimmed and labelled "Not saved offline". Neither the empty state nor the failure panel appears: offline is its own state | draft: redesign-drafts/saved-paywall/flows/TC-SAV-006-offline-banner-rows.yaml + unit: offline index / presentation rules (real network loss cannot be simulated per app) |
| TC-SAV-007 | P1 | A has saved poses, B has none | 1. As A, open Saved. 2. Sign out. 3. Sign in as B. 4. Open Saved | B sees B's list only, with no flash of A's data during the switch; signing out clears the list instead of leaving it readable | pending-e2e (needs `E2E_EMAIL` and `E2E_EMAIL_B`) |
| TC-SAV-008 | P1 | cold start, signed in | 1. Open Saved immediately | The skeleton (`saved.loading`) stands in for the list while the first page loads — never an empty state, never a spinner over a blank screen | unit: `SavedSurfaceStage.resolve` + `APCatalogPresentationRule.presentation` (loading precedes empty) |
| TC-SAV-009 | P1 | signed in, Saved load fails | 1. Open Saved with the account API unreachable (Debug `-AIPoseAPIBaseURL` relaunch) | `saved.retry`: "Couldn't load saved poses" + "We couldn't reach your account. Your saved poses are safe." and one **Try again** that retries in place. The empty state is never shown for a failure | draft: redesign-drafts/saved-paywall/flows/TC-SAV-009-load-error-retry.yaml |
| TC-SAV-010 | P1 | signed in, at least two saved poses | 1. Tap the first row's unsave. 2. Wait up to 15 s for the snackbar (the removal is server-confirmed before the row leaves the list). 3. Tap **Undo** | The snackbar says "Removed <pose name>" with **Undo** (bottom, above the safe area); tapping Undo puts that exact pose back **at its previous index** through the real bookmark service (`poses.first-card` reads the same title again). The flow logs the measured tap→snackbar latency as `SNACKBAR_LATENCY_MS`, so a slow server appears in the evidence instead of being read as a missing bar. Without the restore the destructive tap would be unrecoverable in a list whose entire purpose is keeping poses. The row leaves **only when the server confirms**, so a flow must wait longer than 4 s (the bar's own dismiss delay) before asserting the row is gone, and must not read the still-present row as "nothing happened": while the request is out the tile is the muted busy one (see TC-SAV-016) | automated: TC-SAV-010-unsave-undo.yaml |
| TC-SAV-011 | P1 | signed in, a saved pose with a long name | 1. Open Saved | Titles wrap to at most three lines without pushing the unsave control out of its 44 pt target and without overlapping the thumbnail | pending-e2e (needs long-name data) |
| TC-SAV-012 | P1 | accounts on | 1. Settings → Library → Saved (`settings.saved.row`). 2. Tap Back (`saved.back`) | Returns to Settings — not Poses, not out of the app: Saved is pushed from where it was opened | automated: TC-SAV-012-back-to-settings.yaml |
| TC-SAV-013 | P2 | signed in or out, dark + AX3 | 1. Open Saved at accessibility text size in dark mode | Rows, gate and state panels stay usable: titles wrap, the unsave control keeps at least its 44 pt target, the panel's action stays full-width | automated: TC-SAV-013-ax3-dark.yaml |
| TC-SAV-014 | P1 | signed in, device offline | 1. Open Saved offline (`-AIPoseSavedOfflineFixture 0`, so no row is cached) | No row offers **Remove from saved**, and the reason is stated on screen (banner + "Not saved offline"). Offering the destructive action offline would either fail silently or look successful while the server never heard it | draft: redesign-drafts/saved-paywall/flows/TC-SAV-014-no-unsave-offline.yaml |
| TC-SAV-015 | P1 | signed in, at least two saved poses | 1. Unsave a row. 2. Tap **Undo** while the restore cannot reach the server | The pose is **not** added back (no optimistic ghost row in the list) and the Undo action stays available so the user can retry; a failure never leaves the list claiming a pose is saved when it is not | unit: undo-failure path (no flow: there is no seam that makes only the re-save fail; the server must stay reachable for the list itself) |
| TC-SAV-016 | P2 | signed in, saved poses, account API slow or failing | 1. Tap a row's unsave (`saved.unsave.<poseID>`). 2. Watch the tile before the server answers. 3. Let the request fail, then repeat against a fast server | While the request is out the tile is **visibly taken**: muted `controlFill` instead of the accent fill, a small spinner in place of the bookmark-slash (the same glyph in the disabled colour with Reduce Motion on), `isEnabled=false`, accessibility value "In progress", and the accessible name unchanged. A second tap in that window is ignored — visibly so, not silently. On failure the tile returns to the accent resting tile and the existing failure bar (`saved.snackbar`, action **Dismiss**) states the reason; on success the row leaves and the Undo bar behaves as before | unit: tile state rule + pending/reverted transitions (`APSavedListTests`) — no flow: the request cannot be slowed from the outside without a seam |

## Held for dev19 (the unsave fix)

`BUG-SAVED-18-01` (unsave tile unreachable) is fixed in `0cb55d1`; **TC-SAV-010** and the flows that depend
on unsaving — **TC-SAV-003**, **TC-SAV-004** (its setup empties the list), **TC-SAV-014** — are held until the
dev19 app is installed, then re-run. The fix also changed what the row ids mean: `poses.first-card` /
`poses.card.<id>` now sit on the open-pose link (thumbnail + copy), not on the whole row, so the trailing
unsave tile is addressed by `saved.unsave.<poseID>` (or, by text, `"Remove from saved"`) and never by a
row coordinate. The removal bar and its Undo action carry `saved.snackbar` / `saved.snackbar.undo`, so a
flow no longer has to race the four-second auto-dismiss with a text match alone.

## Accepted cosmetic deltas (do not raise as bugs)

Agreed with the Feature lane for this slice — the flows must not assert against these:

- the offline banner carries an "Offline" word row plus a wifi glyph (board draws the text only);
- the signed-out gate's button uses the secondary fill (board draws the primary);
- the failed-load **Try again** has no retry glyph and prints no status code.

## Assumptions

- Saved is reachable from **both** Settings (`settings.saved.row`) and the Poses More menu
  (`poses.header.saved`). The drafts use the Settings route (the boarded one, and the one with ids); the
  More-menu route stays covered by TC-SAV-001.
- Offline evidence uses the DEBUG-only `-AIPoseSavedOfflineFixture <n>` seam in
  `docs/qa/redesign-drafts/saved-paywall/subflows/saved-launch-offline.yaml` (first n rows cached). The
  real network-loss behaviour is unit/XCTest-mapped, because the simulator cannot cut the network for one
  app — it is compiled out of Release, so these cases run on a Debug build only.
- The snackbar and its Undo action now carry ids — `saved.snackbar` on the bar, `saved.snackbar.undo` on
  the reversible action **only** (a failure bar's action is a Dismiss and has no Undo id), and the row's
  unsave control is `saved.unsave.<poseID>`. The flows may still read the code-owned text ("Removed …",
  "Undo"); the ids are what makes "the bar never appeared" a finding instead of a guess about which of
  several "Remove from saved" labels was tapped.

## Build gate

This runs on **1.1 (18)**, where `1925f5c`/`6eab7c9` are ancestors and `saved.offlineBanner` exists. (On
1.1 (17) the slice's ids were absent, so only TC-SAV-001 ran there — see the drafts README for that run.)

## Requests to Feature (ids still worth adding)

| Id | Why | Used by |
|---|---|---|
| `saved.retry.button` | `saved.retry` covers the panel; the **Try again** button inside it would be nicer to address by id than by text | TC-SAV-009 |

Already delivered or superseded, kept for the record: `saved.offlineBanner` (delivered), `settings.saved.row`
and `settings.back` (delivered with the Settings rebuild), `saved.unsave.<poseID>`, `saved.snackbar` and
`saved.snackbar.undo` (delivered: the bar id, the Undo action id and the per-pose unsave id).
`saved.offline` / `saved.rowOffline.<poseID>` are superseded — the banner id plus code-owned text cover
them.
