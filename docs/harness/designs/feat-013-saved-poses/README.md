---
title: FEAT-013 Saved Poses account-backed v1 UI/UX
status: draft
feature: FEAT-013
scope: Account-backed Saved Poses only
---

# FEAT-013 — Saved Poses account-backed v1

## Design outcome

V1 adds a signed-in **Saved** collection for published poses. Community browsing
remains discoverable to guests; the Saved collection and all Save/Unsave/Try Pose
actions are account-gated. Albums have no UI, model, route, or interaction in
this slice.

Screen details live in:

- [Saved list](./saved-list.md)
- [Pose detail, auth, removal and offline](./pose-detail-auth.md)

## Authority and inheritance

Behavior follows [FEAT-013](../../features/FEAT-013-saved-poses-albums-account-backed.md)
and the pending [v1 plan](../../plans/260831-0000-saved-poses-account-backed-v1/plan.md).
Visual language inherits the [prototype](../../../prototype/README.md),
[UI/UX System](../../specs/ui-ux-system.md), and the two design reference summaries:
[exploration](../../../design-reference/design_exploration_summary.md) and
[final summary](../../../design-reference/final_design_summary.txt).

The prototype is visual/navigation reference only. Its sessionStorage deletion,
fixture states, and direct camera redirect are not production behavior.

## Product boundaries

| Area | V1 decision |
| --- | --- |
| Identity | Supabase Auth; Google is the only enabled provider; valid session maps to one Account. |
| Saved API | `GET /api/me/saved`, `PUT /api/me/saved/:poseId`, `DELETE /api/me/saved/:poseId`. |
| Save | Published pose only; idempotent upsert, confirmed only after HTTP 200. |
| Unsave | Idempotent delete, confirmed only after HTTP 204; never deletes the pose. |
| Removed pose | Keep SavedEntry server-side; filter unusable pose from list; stale detail/use says exactly **“đã xoá hoặc đã ẩn”** and blocks Try Pose. |
| Session failure | 401 must clear/refresh session and never expose another account’s collection. |
| Offline | Cached Saved list is read-only stale content. Disable mutation; never queue it or show success. |
| Albums | Future many-to-many boundary only; no Albums UI. |

Auth clarification: Supabase Auth has Google as the only enabled provider for v1;
email/password, magic link, anonymous, Apple, GitHub and every other Supabase
provider are disabled/out of scope. See the Feature’s proposed missing constraints,
marked `proposed — needs Product Authority approval`; they are not frozen decisions.
Runtime Google/Supabase integration remains `Unresolved` until WI-02 evidence.

## Global shell and navigation

Keep the existing Compose `MainDock` unchanged: Poses, Gallery, and the
standalone pink Camera action. Do not add a Saved or Account/profile tab. In the
existing Poses header action group, add a 44dp bookmark action with accessible
label **Open Saved poses**. Signed-in activation pushes a dedicated Saved stack
screen, like the existing Search/Detail pushes from `PosesListScreen`; guest
activation invokes the shared `SignInPrompt` before any route or API request.
Because `MainDock` is composed inside `PosesListScreen` and is absent from pushed
Search/Detail screens, it is intentionally hidden while Saved is on top. Saved
has its own `Saved` header with a back-to-Poses affordance, normal safe-area
content and bottom padding, and the same hard-border/hard-shadow shell language.

Recommended route model:

```text
Community browse (guest or signed-in)
  ├─ Pose detail
  │   ├─ Save / Unsave (signed-in only)
  │   └─ Try Pose (signed-in only)
  └─ Poses header bookmark: Open Saved poses
      ├─ guest → SignInPrompt → cancelled/failed stays on Poses
      └─ signed-in → push Saved stack screen (MainDock hidden)
          └─ Saved list → existing Pose detail → Try Pose
```

## Shared component contract

- `PoseCard`: reuse the existing thumbnail/skeleton fallback, rounded surface,
  dark outline, 4dp hard shadow, two-column staggered layout, title below, and
  ellipsis behavior. Saved cards add a small pink filled bookmark indicator;
  this indicator is status, not an independent mutation target.
- `StateMessage`: use the existing explicit state pattern—prototype
  `nb-state-message` and the current Compose inline state treatment—for loading,
  empty, error, retry and refresh-error states. This is a design pattern, not a
  claim that a named shared Compose component already exists. Do not leave a
  blank list.
- `PrimaryButton` / `SecondaryButton`: use shared Compose components and
  `NeoBrutalismContainer`; icon-only controls expose content descriptions and
  critical actions receive stable test tags.
- `SignInPrompt`: modal/sheet with the same cream surface, 2dp dark border and
  hard shadow. Primary action is “Continue with Google”; secondary action is
  “Not now”. Keep the interrupted intent in memory for this navigation session.

## Assumptions

1. “Saved” is a new collection entry point; existing Community remains the browse
   surface. There is no source-backed My Poses tab in the current Compose
   navigation baseline.
2. A Saved list item is a `CommunityPose`-style published projection, not a new
   tombstone model. The SavedEntry is persistence/API truth, not a visible deleted
   card.
3. The sign-in SDK, token storage and exact callback are intentionally not named
   here; WI-02 must confirm repository evidence before implementation.
4. Offline stale data means previously confirmed list data may render with a
   visible stale/offline label. Freshness timestamp is optional; a misleading
   “synced” claim is not allowed.

## Unresolved questions

- Does the platform auth callback return to the interrupted detail/list route or
  only resume the action? This doc specifies the intent outcome, while WI-02
  owns callback mechanics.
- Which locale is authoritative for new copy? The required removal meaning is
  preserved in Vietnamese; localization keys should be supplied in both current
  app locales during implementation.

## Token additions for this feature

Use existing theme tokens first. If a token is absent, add semantic aliases in
the theme/token layer rather than literals in a screen. These additions are
design requirements only; `tokens.css` is not changed by this task.

| Proposed token | Value | Use |
| --- | --- | --- |
| `savedIndicator` | existing primary pink (`#E7A1B0` Compose / `#E89CAE` prototype) | Saved bookmark/status |
| `offlineNotice` | existing warning yellow (`#F4C542` / `#FED766`) | stale read-only banner |
| `errorSurface` | existing semantic Compose error treatment (`AiPoseColors.Error` with the current alpha pattern); prototype `nb-state-message--error` alias | list/action error surface; no new screen literal |
| `errorText` | existing semantic `AiPoseColors.Error` / current theme error token | retryable errors; no new Compose literal |
| `disabledContent` | `#737373` or current `AiPoseColors.Subtext` | disabled mutation affordances |
| `staleLabel` | existing warning text token | “Offline · showing saved poses from last confirmed read.” |

Do not copy prototype `#FBF6EF`, `#000000`, or pastel values into Compose
literally. The documented divergence is intentional: Compose uses its existing
`AiPoseColors`/theme values; the web prototype keeps `tokens.css` values.
