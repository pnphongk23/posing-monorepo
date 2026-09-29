# FEAT-004/005 Design Closure — Shared Contract

Status: completed · Owner: General Lead (agent 447c822b) · Date: 2026-09-24

## Outcome
FEAT-004 and FEAT-005 have no open TBD; Basic Design (Add Pose + new Jobs screen) and the
prototype are consistent, minimal, and ready for the next implementation plan. No native
code, no Cook plan in this mission.

## Product Authority decisions (fixed, do not reopen)
1. FEAT-005 approved 2026-09-24 with revised scope: Photo Library only; name + tags required;
   description optional; Jobs stored locally on device.
2. Sign-out / account switch policy **B**: on sign-out the device deletes all Jobs (intents,
   attempts) and copied source photos for that account. Running server jobs cannot be
   recovered later (no list API). Other accounts' jobs are never shown.

## Shared UX contract (both streams must match this exactly)
- **Entry**: Poses screen header gets a `Jobs` button next to `Add pose`, with a small count
  badge of active jobs (sending / queued / processing / saving). Hidden badge at 0. Jobs is
  not a bottom tab.
- **Add Pose after submit (202)**: processing surface shows source photo + skeleton overlay
  and honest status copy. Actions: `View jobs` (primary) and `Done` (closes surface). Leaving
  never cancels the server job. No `Cancel` label anywhere (no cancel API).
- **Jobs screen (SCR-005-01)**: nav title `Jobs`, standard Back. Two sections: `In progress`
  then `Finished`, newest first inside each. Row = source thumbnail, pose name, status label,
  one trailing action when applicable.
- **Row states → label → action**
  - submitting → `Sending…` → none
  - submission_unconfirmed → `Couldn't confirm` + short help → `Check again` (never auto-resubmit)
  - queued → `Queued` → none
  - processing → `Processing` → none
  - extraction failed → `Failed` + human error → `Retry` (new attempt, same localIntentId)
  - succeeded, save pending → `Saving…` → none
  - save_failed / save_unconfirmed → `Not saved` → `Retry save` (same jobId, no re-extraction)
  - saved (poseId set) → `Ready` → `View pose`
- **Remove**: swipe-to-remove only on Finished rows (Failed, Not saved, Ready) with a confirm
  sheet; removing a Ready row never deletes the Pose.
- **Empty**: "No jobs yet" + `Add pose` CTA. **Offline**: inline banner "You're offline —
  statuses update when you're back online."; retry actions disabled while offline.
- **Sign-out**: if active jobs exist, the sign-out confirm warns "N poses are still processing.
  Signing out removes them from this device." (copy owned by Basic Design; prototype optional).
- No auto-retry, no fake percentages, respect reduced motion, 44pt targets, Dynamic Type.

## Items that stay open but must be recorded as plan prerequisites (not TBD)
- `POST /api/guides` not mounted in Express → backend work item for next plan.
- No server cancel API → by design; UI never offers cancel.
- Server result retention (base64 in extractionJobStore, no TTL) → backend work item.

## Streams
- Docs Lead: FEAT-004/005, specs, Basic Design (scr-004-01, new scr-005-01-jobs), indexes.
- Prototype Lead: docs/prototype screens/scripts for Poses entry, Add Pose, Jobs.

## Result (2026-09-24)
- Docs: FEAT-004/005 approved, no blockers; scr-004-01 §7 closed; new scr-005-01-jobs.md.
- Prototype: poses-list Jobs badge, add-pose processing (View jobs / Done), jobs.html + scripts/jobs.js; screenshots in `screens/`.

## Next-plan prerequisites
Prerequisites 1–3 are superseded by `plans/260925-server-authoritative-jobs/`.
1. Mount `POST /api/guides` (idempotent on `jobId`: 201 / 200 replay / 409).
2. Server result retention/TTL for `extractionJobStore`.
3. Native device-local JobRecord store (account partition, policy B wipe on sign-out) + Add Pose and Jobs SwiftUI screens.
4. Native `View pose` routes directly to Pose Detail (prototype goes via Poses first).
5. Prototype polish (non-blocking): keyboard-accessible Remove, `touchcancel`, drop unused `.add-pose-cancel[hidden]`, clipped "SAMPLE PHOTO" label and dashed outline on processing title, trim Jobs header copy.
