---
title: FEAT-013 Saved list screen
status: draft
---

# Saved list screen

## Purpose and entry behavior

The screen represents the current Account’s saved published poses. It is a
pushed stack screen from the Poses header bookmark, like existing Search/Detail
navigation. `MainDock` is intentionally hidden while Saved is on top. A guest
does not see a fake empty collection and does not trigger `GET /api/me/saved`:
tapping the bookmark opens the shared [sign-in prompt](./pose-detail-auth.md#sign-in-gating)
before route/API access. On success it pushes this screen; cancellation or failed
auth remains on Poses. Community browse remains available to the guest, so
“browse” and “Saved” are deliberately different gates.

## Layout

Reuse the existing Poses screen geometry from `PosesScreen` and the prototype
`poses-list.html`:

- safe-area-aware vertical content with 16dp horizontal inset and normal content
  bottom padding; do not apply `MainDockContentInset` or any floating-dock inset;
- header row with `Saved`, a back-to-Poses affordance, and a refresh affordance;
  no search or Albums affordance in v1;
- small count/status line below the header only when a server total is known;
- two-column `LazyVerticalStaggeredGrid`, 8dp gap, normal content padding with no
  `MainDock` inset; preserve existing matched-image transition key `pose:<poseId>`;
- each card is a surface with dark contour, 4dp hard shadow, thumbnail/skeleton
  fallback, title and a pink bookmark status badge; entire card opens detail;
- show a compact stale banner above content when rendering cached data offline:
  `Offline · showing saved poses from last confirmed read.`

## State matrix

| State | Layout/content | Primary action | Navigation/data rule |
| --- | --- | --- | --- |
| Guest pre-entry gate | Not a Saved-list state: shared `SignInPrompt` appears from the Poses-header bookmark. | `Continue with Google` | No Saved route or API request before auth; cancellation/failure remains on Poses. |
| Initial loading | Header remains; 2–4 neutral card skeletons or centered progress. | None | `aria/live` equivalent; do not report empty. |
| Empty | Centered bookmark/pose illustration, `No saved poses yet`, `Save poses from Community to find them here.` | `Browse Community` | Go to Community; no Albums CTA. |
| Content | Count (if known) + two-column cards. | Tap card | Push existing Pose detail with `source=community`/saved origin metadata. |
| Load-more loading | Existing cards stay; full-width compact spinner at end. | None | Append only after confirmed `page n+1`; preserve scroll position. |
| Load-more error | Existing cards stay; inline error at end. | `Retry` | Retry the same next page; never replace content with an empty state. |
| Initial error/no cache | Error panel, `Unable to load saved poses`, concise server/network copy. | `Retry` | Retry list; 401 routes to sign-in requirement. |
| Refresh error/content | Existing cards stay + warning/error banner: `Couldn’t refresh. Showing your saved poses.` | `Retry` | Keep confirmed previous list; do not claim fresh data. |
| Offline with cache | Existing cards stay + yellow `Offline · showing saved poses from last confirmed read.` | `Retry`/refresh when available | Read only; Save/Unsave disabled and no mutation queue. |
| Offline without cache | Offline empty/error panel, not “No saved poses”. | `Try again` | No mutation; retry when network returns. |
| Session expired (401) | Remove account-specific list from active state; sign-in requirement. | `Continue with Google` | Refresh/clear session; never render prior account data as current. |

## Pagination

Use the authority contract from [Saved API](../../../spec/api/modules/saved.md)
and [API conventions](../../../spec/api/conventions.md):
`GET /api/me/saved?page=<n>&limit=<n>`, returning
`pagination.page`, `pagination.limit`, and `pagination.total`. Use page 1 and
the API convention default `limit=20` unless the implementation has an approved
different limit within the contract maximum of 100. Start at page 1,
append only a confirmed page `n+1`, and stop when the loaded item count reaches
`pagination.total` when total is known. Do not invent a cursor or `hasMore` field.
The end sentinel is a 1dp/structural item as in current `CommunityContent`; while
loading show a full-width indicator, and on failure show a full-width Retry.
Prevent duplicate requests for the same page. Pull-to-refresh requests page 1
and replaces the list only after success; a refresh failure retains the last
confirmed page set and existing refresh-error banner behavior.

## Card interaction and accessibility

- Card has one primary activation (open detail), semantic role button, and a
  label such as `Saved pose, Dancing`.
- Bookmark is not a separate nested tap target on the list in v1; Unsave happens
  from detail so accidental collection mutation is avoided.
- Thumbnail failure becomes the neutral existing image placeholder, not a red
  diagnostic card. A missing image does not imply the pose is unavailable if the
  usable projection is otherwise valid.
- Progress and retry messages are announced; retry controls are 44dp minimum and
  icon-only refresh has an explicit content description.

## Navigation outcomes

1. The Poses-header bookmark pushes this Saved screen; `MainDock` remains hidden
   while the Saved stack screen is on top.
2. Signed-in card tap pushes existing `PoseDetailScreen` with the same preview
   contract used by Community.
3. Saved’s Back-to-Poses affordance pops the Saved screen to Poses. Detail Back
   pops detail and returns to the same Saved list ViewModel/grid state; do not
   reload automatically merely because detail was popped.
4. If an item becomes unavailable between list and detail, detail owns the
   unavailable message and returns to Saved; the list may refresh explicitly.
5. After a successful Unsave in detail, pop back with the list entry removed or
   marked absent only after HTTP 204; never optimistically claim success on a
   failed request.

## Copy contract

Keep current prototype’s direct, uppercase-label tone for controls, but use
sentence case for explanatory copy. Required semantic copy for a removed pose is
defined in the detail doc and must not be softened to “not found”.
