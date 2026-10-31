# BUG-SAVED-18-01 (high) — the Saved row's unsave tile does nothing, so Saved can only grow

**Build:** 1.1 (18), Debug-Dev, `/tmp/ai-pose-lane2-app-1.1/dev18/posing.app` (`a03d03a` + integration,
HEAD `da7c019`), lane-2 `CF871F97`.
**Screen:** Saved list (Settings → Library → Saved), signed in with the E2E account.
**Flows that hit it:** `TC-SAV-010-unsave-undo` (assertion "Removed …"), and through it `TC-SAV-003`,
`TC-SAV-014`, and `TC-SAV-004`'s empty-state setup.

## Steps

1. Sign in, open Settings → Library → Saved so the list shows at least one saved pose.
2. Tap the bookmark-slash tile at the trailing edge of a row.
3. Wait (20 s) and look at the list.

## Expected

The row is removed after the server confirms, and the bottom snackbar offers **Undo** ("Removed <pose>"),
per `06-board04` and `APSavedUndoRule`/`APSavedStateCopy.removedMessage`.

## Actual

Nothing happens at all: the row stays, no snackbar appears, and the app does not navigate either — the tap
is swallowed rather than forwarded to the button. Reproduced three ways:

| Attempt | Result |
|---|---|
| `tapOn: "Remove from saved"` (the button's own accessibility label) | row unchanged, no snackbar |
| `tapOn: { id: "bookmark.slash" }` (the id the hierarchy exposes) | row unchanged, no snackbar |
| `tapOn: { point: "87%,19%" }` (raw coordinate on the tile, no selector involved) | row unchanged, no snackbar |

The third rules out a Maestro targeting artefact.

## Likely cause (for the Feature lane, not fixed here)

`APSavedList.row(for:index:)` wraps `APSavedPoseRow` — whose trailing `unsaveButton` is a `Button` — in a
`NavigationLink`, so the link owns the whole row's hit area and the nested button never receives the tap.
The tile still renders in its enabled style (accent fill), so the user sees an affordance that cannot act.
Note the data path is fine: unsaving from the pose detail (`poseDetail.saveButton`) works, which is why
TC-SAV-002 passes.

## Impact

- A saved pose cannot be removed from the Saved list at all; the collection can only grow.
- **Undo has no reachable producer** from this surface, so the shipped Undo feature cannot be exercised by a
  user or by TC-SAV-010.
- Offline "no unsave offered" (TC-SAV-014) is unverifiable in the positive direction until the control works.

## Evidence

- `BUG-SAVED-18-01-unsave-noop-id-tap.png` — final screen after the tap (row still saved, list intact).
- `BUG-SAVED-18-01-coordinate-tap-hierarchy.json` — Maestro's hierarchy for the raw coordinate attempt:
  the row and its "Remove from saved" element are present, `poses.first-card` still there after 20 s.
