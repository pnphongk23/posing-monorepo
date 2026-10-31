# Saved poses (FEAT-013, redesigned build 17)

Business behaviour of the Saved surface: what a user can keep, see, and lose. Saved is a **pushed
destination** (header with Back, no dock), reached from Settings → Library → Saved and from the Poses
More menu. It is account-scoped: the list belongs to the signed-in account and only to it.

Board source: `/tmp/ds-261030/export-c/06-board01..10.png` (9 artboards + evidence page). Gap source:
`/tmp/gap/05-06.md` §06 — Saved is **PARTIAL**: unsave Undo **MISSING**, offline cached mode
**MISSING**, signed-out/empty/error copy differs, AX3 unsave tile is 44 pt vs the board's larger tile.
Only two Saved states exist as boarded today (populated, loading skeleton); the rest are the work below.

Status legend: `automated:` = committed flow that passes, `draft:` = flow in
`docs/qa/redesign-drafts/saved-paywall/` (not yet run), `unit:` = XCTest only, `pending` = blocked on an id
or on data, `out of scope 1.1` = agreed out of this release.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SAV-001 | P0 | accounts on, signed out | 1. Launch. 2. Open the Poses More menu, tap Saved | Saved opens but does not pretend to have data: `saved.signIn` panel (board copy: "Sign in to see saved poses", saved poses sync across devices) with one **Sign in** action. No rows, no loading spinner, no error. *(Copy changes from the current "Sign in to view your saved poses… tied to your account"; favourite glyph becomes the board's person glyph.)* | automated: TC-SAV-001-saved-signed-out.yaml — **re-baseline** on build 17 (copy) |
| TC-SAV-002 | P1 | signed in, poses not yet saved | 1. Open any pose. 2. Tap Save (`poseDetail.saveButton`). 3. Open Saved | The pose is listed with the id it was saved by (`poses.first-card` for the first row), so "saved" and "listed" are the same fact | draft: redesign-drafts/saved-paywall/flows/TC-SAV-002-saved-list-loaded.yaml (needs E2E account) |
| TC-SAV-003 | P1 | signed in, one saved pose | 1. Open that pose. 2. Tap the saved toggle (`poseDetail.saveButton`, label "Remove from saved"). 3. Reopen Saved | The pose is gone from Saved after the list reloads; the empty state appears | draft (same file as 002, second half) / pending-e2e |
| TC-SAV-004 | P1 | signed in, nothing saved | 1. Open Saved | Empty state: "No saved poses yet", board guidance "Tap Save on any pose to keep it here.", one **Browse poses** action (`saved.browseCommunity`) that returns to Poses. No error styling and no count text (F3). *(Action label changes from "Browse Community" to "Browse poses".)* | draft: redesign-drafts/saved-paywall/flows/TC-SAV-004-empty-browse.yaml — **re-baseline** (action label) |
| TC-SAV-005 | P1 | signed in, one saved pose | 1. Open the saved pose from the list. 2. Tap "Try this pose" (`poseDetail.use`) | The pose detail opens (title `poseDetail.title`) and its Try action opens the camera with that pose; the row is a link, so a tap anywhere but the unsave control opens the pose | pending-e2e |
| TC-SAV-006 | P1 | signed in, poses saved, network off | 1. Open Saved with no connectivity. 2. Try to unsave a row | Cached mode (MUST COVER in 1.1): the last known list stays readable under an offline banner ("You're offline. Changes will sync when you're back online."), rows that could not be confirmed are marked "Not saved offline", and the unsave control is disabled instead of appearing to work. The UI never shows a row as removed when the server never heard about it | draft pending ids (`saved.offline`, `saved.rowOffline.<poseID>`, `saved.unsave.<poseID>`) + unit: optimistic-unsave rollback; **no producer exists today** |
| TC-SAV-007 | P1 | account A has saved poses; account B has none | 1. Signed in as A, open Saved. 2. Sign out. 3. Sign in as B. 4. Open Saved | B sees B's list only: no row of A's, no flash of A's data during the switch. Signing out clears the list rather than leaving it readable | pending-e2e (needs `E2E_EMAIL` and `E2E_EMAIL_B`) |
| TC-SAV-008 | P1 | cold start, signed in | 1. Open Saved immediately | A skeleton of row placeholders (`saved.loading`) stands in for the list while the first page loads — never an empty state, and never a spinner over a blank screen | unit: `SavedSurfaceStage.resolve` + `APCatalogPresentationRule.presentation` (loading precedes empty) |
| TC-SAV-009 | P1 | signed in, Saved load fails | 1. Open Saved with the account API unreachable | `saved.retry`: "Couldn't load saved poses" with the reassurance that saved poses are safe, and one **Try again** that retries the load in place | draft (needs `saved.retry.button`): redesign-drafts/saved-paywall/flows/TC-SAV-009-load-error-retry.yaml |
| TC-SAV-010 | P1 | signed in, list loaded | 1. Tap the unsave control on a row | MUST COVER in 1.1 (undo is new): the row disappears and a bottom snackbar says "Removed <pose name>" with **Undo**; Undo restores the row **and** the server state, and the snackbar is the app's one recovery path for a destructive tap in a list whose purpose is keeping poses | pending ids + Feature (undo is MISSING today): `saved.unsave.<poseID>`, `saved.snackbar`, `saved.snackbar.undo` |
| TC-SAV-011 | P1 | signed in, a saved pose with a long name | 1. Open Saved | Long titles wrap to at most three lines and keep the row's unsave control on screen at full 44 pt target; the thumbnail and the control never overlap the text | pending-e2e (needs long-name data; no layout assertion in Maestro beyond both ids visible) |
| TC-SAV-012 | P1 | accounts on, signed in or out | 1. Settings → Library → Saved (`settings.saved.row`). 2. Tap Back (`saved.back`) | Returns to Settings, not to Poses, and not out of the app: Saved is pushed from where it was opened. Both ids exist since the Settings rebuild, so this is the boarded route for every Saved flow | draft: redesign-drafts/saved-paywall/flows/TC-SAV-012-back-to-settings.yaml (promote at the 1.1 (17) run) |
| TC-SAV-013 | P2 | signed in, dark appearance and AX3 text | 1. Open Saved at accessibility text size in dark mode | Rows, the sign-in gate and the empty state stay usable: the title wraps instead of clipping, the unsave control keeps at least its 44 pt target (the board draws a larger tile and glyph — the requirement is a real target with the glyph scaling with the text), and the state panel's action stays a full-width target | draft: redesign-drafts/saved-paywall/flows/TC-SAV-013-ax3-dark.yaml — **re-baseline** (unsave tile sizing) |

## Assumptions
- The redesign keeps Saved reachable from **both** the Poses More menu (`poses.header.saved`) and Settings
  (`Open Saved poses` row); the boards show the Settings row and the More-menu row, so the flows use the
  More menu for now and the Settings route is covered by TC-SAV-012.
- "Offline" means the app has no connectivity; the case is **manual** because the simulator has no
  per-app network control (a device with Airplane Mode covers it), and the logic half is unit-tested by
  the optimistic-unsave rollback.
- TC-SAV-008's skeleton is a timing state, so it is pinned at the pure-decision level rather than raced
  in a flow.

## Build 1.1 (17) = regression only

The build-17 app (`a03d03a`) does not contain the Saved undo/offline slices (`1925f5c`, `6eab7c9`) nor the
F4 states (`bf1db8c`), so the 17 run verifies **TC-SAV-001** as a regression and nothing else; the drafts
below are promoted with the **1.1 (18)** build.

## Promotable at the 1.1 (18) run

Verified against committed source at `a03d03a`: `saved.back`, `saved.signIn`, `saved.browseCommunity`,
`saved.retry`, `saved.loading`, `settings.saved.row`, `settings.back`, `poseDetail.saveButton`,
`poses.header.saved` all exist. So **TC-SAV-002, 003, 004, 009, 012, 013** have a flow whose ids are real and
are promoted with the run. Still blocked: **TC-SAV-006** (offline mode) and **TC-SAV-010** (Undo) — neither
has a producer yet, so their ids below are genuine requests, not reminders.

## Requests to Feature (ids needed before the drafts can move into `maestro/flows`)

| Id | Why | Used by |
|---|---|---|
| `saved.unsave.<poseID>` | the row's unsave control is only labelled "Remove from saved" today, which is ambiguous with several rows | TC-SAV-003, TC-SAV-010 |
| `saved.snackbar`, `saved.snackbar.undo` | the "Removed <name> / Undo" toast (F5 bottom position) has no id, and undo itself does not exist yet | TC-SAV-010 |
| `saved.offline` | the offline banner (no producer today) | TC-SAV-006 |
| `saved.rowOffline.<poseID>` | the per-row "Not saved offline" mark | TC-SAV-006 |
| `saved.retry.button` | `saved.retry` covers the error panel; the **Try again** button inside it needs its own id | TC-SAV-009 |

No Saved case is out of scope for 1.1.
