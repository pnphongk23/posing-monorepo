---
schema_version: 1
type: decision
id: DEC-003
title: FEAT-003 Scoped Parity Matrix (Search affordance retained)
status: approved
created: 2026-08-18
approved: 2026-08-18
approved_by: Repository Maintainer
relationships:
  specs:
    - "[[ui-ux-system]]"
    - "[[product-feature-inventory]]"
  decisions:
    - "[[260809-2240-pose-reference-library-convergence/DEC-002-pose-reference-library-parity-matrix|DEC-002]]"
  plans:
    - "[[260818-2105-feat-003-pose-library-slice/plan|260818-2105]]"
    - "[[260818-2112-community-title-search-production/plan|260818-2112]]"
  reports:
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - docs/prototype/screens/poses-list.html
    - docs/prototype/screens/pose-detail.html
    - docs/prototype/screens/camera-pose-overlay.html
    - docs/prototype/screens/camera-live.html
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
---

# FEAT-003 Scoped Parity Matrix (Search affordance retained)

Scope boundary for Plan `260818-2105-feat-003-pose-library-slice`. Rows marked
**Excluded** are intentionally out of Plan acceptance. Historical DEC-002 and
REP-003 remain read-only; this matrix documents parity for **new** work under
FEAT-003 approval (2026-08-18). DEC-003 is **approved** (2026-08-18, Repository
Maintainer); WI-01 records the matrix. Revision note (2026-08-18): Maintainer
directs that the poses-list search icon remains visible and wired to
`SearchScreen`; search *behavior* is owned by Plan 260818-2112.

## Parity matrix

| Requirement / Scenario | Prototype | Production target | Status for this Plan |
| --- | --- | --- | --- |
| **FR-001** Public list/detail DTOs | `poses-list.html` community grid | `PoseApiService.kt` + `communityRoutes.ts` | **Aligned** — regression WI-03/WI-05 |
| **Browse: My Poses tab** | `poses-list.html:39-40` | `PosesScreen.kt:161-172`, `234-281` | **Aligned** — regression WI-03 |
| **Browse: Community tab** | `poses-list.html:40-41` | `PosesScreen.kt:167-172`, `284-462` | **Aligned** — regression WI-03 |
| **Create Pose (+)** | `poses-list.html:49` → `camera-live.html` | `PosesScreen.kt:195-208` + `Navigation.kt:129` | **Gap** — Camera capture entry only (Option A); WI-02 |
| **Community pagination + dedupe** | N/A (static) | `PosesLibraryCoordinator.kt:43+` | **Aligned** — regression WI-03 |
| **Refresh + E1 retry** | N/A | `PosesScreen.kt:298-320`, `329-355` | **Aligned** — regression WI-03 |
| **Detail metadata (nullable)** | `pose-detail.html:66-69` | `PoseDetailScreen.kt:400-420` | **Aligned** — regression WI-04 |
| **Try Pose CTA** | `pose-detail.html:72-76` | `PoseDetailScreen.kt:432-439` | **Partial** — prepare OK; overlay deferred; regression WI-04 |
| **Try Pose prepare + emit** | `camera-pose-overlay.html:34-46` (reference) | `Navigation.kt:152-156` → `preparedReference` | **Boundary** — emit only WI-04; Plan 2241 consumes |
| **Local delete (personal only)** | `pose-detail.html:77-79` | `PoseDetailScreen.kt:217-231` | **Aligned** — regression WI-04 |
| **Empty My → Create Pose** | prototype empty tip | `PosesScreen.kt:245-263` | **Gap** — same Camera entry as WI-02 |
| **Search toolbar wired** | `poses-list.html:44-47` (prototype has link) | `PosesScreen.kt:179-193`, `Navigation.kt:130-136` | **Aligned** — verify WI-03 (`E-SEARCH-WIRED`); icon retained+wired |
| **FR-002 server title search `q`** | `search.html` | `SearchScreen.kt`, `CommunitySearchProvider.kt` | **Excluded** — Plan 2112; code read-only here |
| **FEAT-004 `extractPose` orchestration** | N/A (not poses-list entry) | `PoseApiService.extractPose` | **Excluded** — Option A; `E-EXTRACT-DEFER`; not wired by Create Pose WI-02 |
| **FEAT-008 Save / bookmark** | prototype social metadata only | not in `PoseDetailScreen.kt` | **Excluded** — deferred |
| **Android parity** | N/A | iOS-only `shared` targets | **Excluded** — deferred |
| **E2 detail missing/unpublished** | `pose-detail.html:44-48` | `PoseDetailScreen.kt:263-281`, `137-140` | **Aligned** — regression WI-04 |
| **BR-001 no server deletion** | N/A | `PoseDetailViewModel.delete()` community guard | **Aligned** — regression WI-04 |

## Material scope decisions

1. **Option A — Create Pose (+):** Opens `CameraTab` for **capture entry** per
   prototype `camera-live.html`. Does **not** wire or claim FEAT-004
   `extractPose` / async extraction orchestration in this slice.
2. **Search affordance retained:** Keep the poses-list search icon visible and
   wired to `SearchScreen`. Plan `260818-2112` owns `SearchScreen` /
   `CommunitySearchProvider` / server `?q=` search *behavior* (read-only here);
   Plan `260818-2105` verifies the affordance stays wired (WI-03) and does not
   hide or unwire it. Maintainer intent (2026-08-18): the icon stays when 2112
   completes.
3. **Try Pose seam:** Plan `260818-2105` owns **prepare + emit**
   `PreparedPoseReference` only. Plan `260809-2241` owns durable store, Camera
   consume, and overlay render (`CameraScreen.kt:173`). Plan 2241 WI-03 text
   describing durable commit before tab switch is **stale** relative to current
   `Navigation.kt:152-156` in-memory emit — 2241 must reconcile on execution.
4. **Read-only history:** Plan 2240, REP-003, and DEC-002 are evidence only;
   do not rewrite their completion claims.

## Verification labels

- **Aligned** — existing behavior meets acceptance; regression in WI-03/04/05.
- **Gap** — must close in this Plan before approval.
- **Partial** — user-visible step works up to a documented boundary.
- **Boundary** — owned by linked Plan 2241; cite handoff contract only.
- **Excluded** — must not block Plan approval.

## Evidence IDs (WI-05 cross-reference)

| ID | Row / concern | Owner |
| --- | --- | --- |
| `E-CAM-ENTRY` | Create Pose (+) → `CameraTab` capture entry | WI-02 |
| `E-SEARCH-WIRED` | Search toolbar visible + navigates to `SearchScreen` | WI-03 |
| `E-EXTRACT-DEFER` | No acceptance step calls `extractPose` | — (negative) |
| `E-TRY-EMIT` | Try Pose prepare + emit `preparedReference` | WI-04 |
| `E-2241-BOUNDARY` | Overlay/persistence deferred to Plan 2241 | Plan 2241 |
