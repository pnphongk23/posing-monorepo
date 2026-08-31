---
title: FEAT-013 Pose detail, Save, auth and unavailable states
status: draft
---

# Pose detail, Save/Unsave, auth and unavailable states

## Detail layout

Keep the existing `PoseDetailScreen` scaffold and prototype `pose-detail.html`:

- top safe-area navigation bar with 44dp back target, centered/primary pose title;
- stable hero wrapper that uses the navigation preview while loading and keeps the
  same `pose:<poseId>` transition identity when enriched;
- cream/background surface, white pose card, dark 2dp outline and hard shadow;
- source badge (`Community`/`Saved`) and available metadata as compact tags;
- bottom action area with primary `Try Pose` and secondary Save control;
- no delete control for a published Saved pose. Personal-pose deletion remains
  the existing FEAT-003/008 boundary and is not repurposed as Unsave.

The Save control is a 44–48dp outlined/filled bookmark button with accessible
label `Save pose` or `Remove pose from Saved`. Filled pink means confirmed saved;
outline/white means confirmed not saved. During mutation show a compact progress
indicator and disable the control, but retain the last confirmed visual state.

## Detail state matrix

| State | UI | Action behavior |
| --- | --- | --- |
| Loading with preview | Existing stable hero + `Loading details…`. | Save/Try disabled until usable detail and session gate can be evaluated. |
| Load error | Existing detail error treatment: `Failed to load detail`, returned error copy, and a `Retry` button. | Stay on detail; retry the existing load flow. Do not replace this with an unavailable or empty state. |
| Loaded, not saved | Detail + white/outlined `Save`. | Signed-in → PUT; guest → sign-in prompt. |
| Loaded, saved | Detail + pink filled `Saved`/bookmark. | Signed-in → DELETE; guest session loss → sign-in prompt. |
| Save/Unsave pending | Preserve confirmed state; spinner/“Saving…” or “Removing…”. | Ignore duplicate taps; await server response. |
| Mutation success | Apply new confirmed state and short live confirmation: `Saved` or `Removed from Saved`. | No navigation required. |
| Mutation failure/offline | Preserve prior confirmed state; inline retryable error. | No success copy, no queue; retry only when user taps. |
| Missing/non-published | Unavailable panel; no Save/Try. | Show the required removal message; return to origin. |
| 401 | Clear account-specific action state. | Refresh/clear session and open sign-in requirement; do not leak collection. |

## Save/Unsave flow

```text
Tap Save/Unsave
  ├─ no valid Account session → SignInPrompt(intent = Save or Unsave)
  ├─ offline → keep state + offline mutation error; no request/queue
  └─ valid session → pending → API response
       ├─ 200 Save / 204 Unsave → update confirmed state
       ├─ 401 → refresh/clear → sign-in requirement
       ├─ 404 missing/non-published → unavailable; never show Saved success
       └─ network/server error → inline Retry; keep confirmed state
```

Repeated Save remains one entry by API idempotency. Repeated Unsave remains a
no-op by API idempotency. The screen must not infer success from a local tap.

## Try Pose gating and existing handoff

Guest Try Pose opens SignInPrompt and does not call `tryPose`, prepare a skeleton,
or switch to Camera. After successful sign-in, resume the interrupted Try intent:
reload/confirm the published detail, call the existing verification/preparation
flow, and only then emit `PreparedPoseReference` to the existing camera handoff.
If auth is cancelled, remain on detail with no side effect.

For signed-in users, preserve current behavior: `Preparing` overlay, verify the
skeleton/image, recoverable action error on failure, then use the existing
navigation handoff. Saved does not create a second camera or overlay flow.

## Sign-in gating

Use one shared modal/sheet `SignInPrompt` from all three entry points. Its single
primary CTA is always **`Continue with Google`**; secondary action is `Not now`.

The prompt is used from:

| Trigger | Prompt message | On success |
| --- | --- | --- |
| Guest taps Save | `Sign in to save poses to your account.` | Return to detail and execute the original Save intent once. |
| Guest taps Saved | `Sign in to view your saved poses.` | Navigate to Saved and load the signed-in collection. |
| Guest taps Try Pose | `Sign in to try this pose.` | Return to detail, revalidate, then run existing Try Pose handoff. |

Auth failure shows a retryable error in the prompt; cancellation does not change
Save state or navigation and, for the Saved entry point, remains on Poses without
route/API access. The interrupted intent is single-use and
must be cleared after success, cancellation, or terminal failure to avoid replay
on a later screen.

## Unpublish/delete retention behavior

When a pose is unpublished or terminally deleted:

- server persistence retains `SavedEntry(accountId, poseId)`;
- `GET /api/me/saved` excludes it from the usable published projection;
- a stale detail, deep link, or Try Pose attempt resolves to an unavailable
  state, never a successful detail or camera handoff;
- show this exact meaning in user-facing copy: **“Pose này đã xoá hoặc đã ẩn.”**
  Supporting copy may say the pose is no longer available; do not use a generic
  “not found” message as the only explanation;
- offer `Back to Saved` when origin is Saved, otherwise `Back to Community`;
- do not automatically DELETE the SavedEntry and do not invent a tombstone card;
- if an already-open detail receives the removal response while Save/Unsave is
  pending, stop the mutation UI, show unavailable, and never report success.

This differs from the prototype’s personal `markPoseDeleted` sessionStorage flow:
that flow is not an account-backed removal model.

## Offline and stale reads

On offline entry, render the last confirmed account-scoped Saved projection with
the yellow stale banner `Offline · showing saved poses from last confirmed read.` Keep
card navigation read-only only when the cached
detail assets are available; otherwise show the unavailable/retry state. Save,
Unsave and Try Pose are disabled or gate to a clear “Reconnect to change Saved
poses / try a pose” action—never queue, retry invisibly, or display a success
toast. When connectivity returns, refresh is explicit or follows the existing
screen refresh convention; reconcile only confirmed server data.

## Accessibility and motion

Use the existing semantic/test-tag conventions from Compose and prototype:

- descriptive labels for bookmark, back, Try Pose and retry;
- announce mutation pending/success/failure through a live status;
- preserve 44dp minimum targets and visible dashed focus treatment;
- use the existing slide-up/press translation and hard-shadow collapse; honor
  reduced motion by removing non-essential transitions;
- modal focus starts on Continue with Google, Escape/back dismisses safely, and
  focus returns to the triggering action.

## Implementation handoff notes

Reuse `PoseDetailViewModel`’s preview-first loading, `DetailActionState` recovery,
`prepareReference`, and `createTryPoseCameraHandoffAction`. Extend the state model
for confirmed Saved status, Save/Unsave pending/error, account gate, stale mode,
and unavailable-removed copy; do not replace the existing detail architecture.

Albums are explicitly deferred: future Album membership may reference the same
pose, but this screen has no Album selector, “add to album” action, album tab, or
album-specific empty state.
