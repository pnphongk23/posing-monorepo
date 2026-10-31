# Saved poses (FEAT-013, redesigned build 17)

Business behaviour of the Saved surface: what a user can keep, see, and lose. Saved is a **pushed
destination** (header with Back, no dock), reached from Settings → Library → Saved and from the Poses
More menu. It is account-scoped: the list belongs to the signed-in account and only to it.

Board source: `/tmp/ds-261030/export-c/06-board01..10.png` (9 artboards + evidence page).

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SAV-001 | P0 | accounts on, signed out | 1. Launch. 2. Open the Poses More menu, tap Saved | Saved opens but does not pretend to have data: `saved.signIn` panel "Sign in to see saved poses" (saved poses sync across devices) with one **Sign in** action. No rows, no loading spinner, no error | automated: TC-SAV-001-saved-signed-out.yaml |
| TC-SAV-002 | P1 | signed in, poses not yet saved | 1. Open any pose. 2. Tap Save (`poseDetail.saveButton`). 3. Open Saved | The pose is listed with the id it was saved by (`poses.first-card` for the first row), so "saved" and "listed" are the same fact | draft: redesign-drafts/saved-paywall/flows/TC-SAV-002-saved-list-loaded.yaml (needs E2E account) |
| TC-SAV-003 | P1 | signed in, one saved pose | 1. Open that pose. 2. Tap the saved toggle (`poseDetail.saveButton`, label "Remove from saved"). 3. Reopen Saved | The pose is gone from Saved after the list reloads; the empty state appears | draft (same file as 002, second half) / pending-e2e |
| TC-SAV-004 | P1 | signed in, nothing saved | 1. Open Saved | Empty state: "No saved poses yet", guidance to use Save on a pose, one **Browse poses** action (`saved.browseCommunity`) that returns to Poses. No error styling and no count text | draft: redesign-drafts/saved-paywall/flows/TC-SAV-004-empty-browse.yaml (needs an E2E account with an empty Saved) |
| TC-SAV-005 | P1 | signed in, one saved pose | 1. Open the saved pose from the list. 2. Tap "Try this pose" (`poseDetail.use`) | The pose detail opens (title `poseDetail.title`) and its Try action opens the camera with that pose; the row is a link, so a tap anywhere but the unsave control opens the pose | pending-e2e |
| TC-SAV-006 | P1 | signed in, poses saved, network off | 1. Open Saved with no connectivity. 2. Try to unsave a row | The last known list is still readable with an offline banner ("Changes will sync when you're back online"), and an unsave made offline is refused with per-row "Not saved offline" feedback — the UI never shows a row as removed when the server never heard about it | manual (no per-app network seam on the simulator) + unit: optimistic-unsave rollback |
| TC-SAV-007 | P1 | account A has saved poses; account B has none | 1. Signed in as A, open Saved. 2. Sign out. 3. Sign in as B. 4. Open Saved | B sees B's list only: no row of A's, no flash of A's data during the switch. Signing out clears the list rather than leaving it readable | pending-e2e (needs `E2E_EMAIL` and `E2E_EMAIL_B`) |
| TC-SAV-008 | P1 | cold start, signed in | 1. Open Saved immediately | A skeleton of row placeholders (`saved.loading`) stands in for the list while the first page loads — never an empty state, and never a spinner over a blank screen | unit: `SavedSurfaceStage.resolve` + `APCatalogPresentationRule.presentation` (loading precedes empty) |
| TC-SAV-009 | P1 | signed in, Saved load fails | 1. Open Saved with the account API unreachable | `saved.retry`: "Couldn't load saved poses" with the reassurance that saved poses are safe, and one **Try again** that retries the load in place | draft (needs `saved.retry.button`): redesign-drafts/saved-paywall/flows/TC-SAV-009-load-error-retry.yaml |
| TC-SAV-010 | P1 | signed in, list loaded | 1. Tap the unsave control on a row | The row disappears and a bottom snackbar says "Removed <pose name>" with **Undo**; Undo restores the row and the server state. Without Undo the action would be a data-loss trap in a list whose whole purpose is keeping poses | pending-ids + Feature: `saved.unsave.<poseID>`, `saved.snackbar`, `saved.snackbar.undo` |
| TC-SAV-011 | P1 | signed in, a saved pose with a long name | 1. Open Saved | Long titles wrap to at most three lines and keep the row's unsave control on screen at full 44 pt target; the thumbnail and the control never overlap the text | pending-e2e (needs long-name data; no layout assertion in Maestro beyond both ids visible) |
| TC-SAV-012 | P1 | signed in | 1. Settings → Library → Saved. 2. Tap Back (`saved.back`) | Returns to Settings, not to Poses: Saved is pushed from where it was opened | draft: redesign-drafts/saved-paywall/flows/TC-SAV-012-back-to-settings.yaml |
| TC-SAV-013 | P2 | signed in, dark appearance and AX3 text | 1. Open Saved at accessibility text size in dark mode | Rows, the sign-in gate and the empty state stay usable: title and unsave control still reachable, nothing clipped, the state panel's action stays a full-width target | draft: redesign-drafts/saved-paywall/flows/TC-SAV-013-ax3-dark.yaml |

## Assumptions

- The redesign keeps Saved reachable from **both** the Poses More menu (`poses.header.saved`) and Settings
  (`Open Saved poses` row); the boards show the Settings row and the More-menu row, so the flows use the
  More menu for now and the Settings route is covered by TC-SAV-012.
- "Offline" means the app has no connectivity; the case is **manual** because the simulator has no
  per-app network control (a device with Airplane Mode covers it), and the logic half is unit-tested by
  the optimistic-unsave rollback.
- TC-SAV-008's skeleton is a timing state, so it is pinned at the pure-decision level rather than raced
  in a flow.

## Requests to Feature (ids needed before the drafts can move into `maestro/flows`)

| Id | Why | Used by |
|---|---|---|
| `saved.unsave.<poseID>` | the row's unsave control is only labelled "Remove from saved" today, which is ambiguous with several rows | TC-SAV-010 |
| `saved.snackbar`, `saved.snackbar.undo` | the "Removed <name> / Undo" toast (F5 bottom position) has no id | TC-SAV-010 |
| `saved.offline` | the offline banner | TC-SAV-006 |
| `saved.retry.button` | `saved.retry` covers the error panel; the **Try again** button inside it needs its own id | TC-SAV-009 |
| `settings.saved.row` | the Settings → Library → Saved row is only labelled "Open Saved poses" (needed for TC-SAV-012 to enter from Settings) | TC-SAV-012 |
