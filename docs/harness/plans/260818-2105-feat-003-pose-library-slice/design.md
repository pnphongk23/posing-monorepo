# Design: FEAT-003 Pose Library Slice (Search affordance retained)

Plan `260818-2105-feat-003-pose-library-slice` — authority for Cook after
Maintainer approval. Lead draft only; **changes_requested** (Maintainer
re-approval required after this revision).

Maintainer decision (2026-08-18): **Option A** — Create Pose (+) = Camera
**capture entry only** (`camera-live.html`). FEAT-004 extraction is **not**
claimed in this slice. Revision note (2026-08-18): Maintainer directs that the
poses-list **search icon stays visible and wired** to `SearchScreen`; search
*behavior* is owned by Plan `260818-2112`.

## Problem

FEAT-003 was approved 2026-08-18. Plan `260809-2240` delivered a broad library
convergence documented in REP-003. This scoped Plan closes **true deltas** only:

1. **Create Pose (+)** renders but `Navigation.kt:129` passes `onExtractPoseClick = {}`.
2. **Search affordance** is wired in product UI and is **retained** — search
   *behavior* is owned by Plan `260818-2112`; 2105 verifies the icon stays wired.
3. **Try Pose** prepares and emits `PreparedPoseReference`; overlay render and
   durable persistence remain Plan `260809-2241`.

## Goals (IN)

- My Poses / Community tabs on poses-list — **regression verify** (WI-03).
- pose-detail + Try Pose **prepare + emit** — **regression verify** (WI-04).
- Wire Create Pose (+) to **Camera capture entry** (Option A, WI-02).
- Retain the search toolbar icon wired to `SearchScreen` (WI-03 regression-verifies it stays wired).
- Document handoff seam to Plan `260809-2241` (overlay/persistence).

## Non-goals (OUT)

- FEAT-004 `extractPose` API wiring or async extraction orchestration.
- SearchScreen behavior, `CommunitySearchProvider`, server `?q=` (Plan 2112).
- Android delivery.
- FEAT-008 Save/bookmark.
- Camera overlay enablement or relaunch persistence (Plan 2241).
- Modifying completed Plan 2240 or REP-003 except named regression fixes.

## True deltas (Cook may change)

| Delta | WI | Notes |
| --- | --- | --- |
| Create Pose → `CameraTab` | WI-02 | Navigation only; prototype `camera-live.html` |
| Evidence / regression | WI-03, WI-04, WI-05 | 2240-delivered browse/detail unless regression fails |

All other library behavior is **read-only** from Plan 2240 / REP-003 unless a
named regression test fails.

## Recommended approach

### 1. Create Pose — Camera capture entry (WI-02, Option A)

Match prototype `poses-list.html:49` → `camera-live.html`:

```kotlin
onExtractPoseClick = { tabNavigator.current = CameraTab }
```

Do **not** call `PoseApiService.extractPose`, enqueue extraction jobs, or claim
FEAT-004 completion. Extraction remains a **future FEAT-004 slice** (Camera may
already expose capture independently).

### 2. Browse + search affordance verification (WI-03)

- **Regression:** coordinator paging, refresh, E1 recovery, card → detail.
- **Affordance:** verify `poses-search-button` (`PosesScreen.kt:179-193`) stays
  visible and `onSearchClick` push to `SearchScreen` (`Navigation.kt:130-136`)
  stays wired (post-2112 or already wired).
- **Positive acceptance:** poses-list shows the search affordance; navigating
  reaches `SearchScreen` (evidence ID `E-SEARCH-WIRED`).
- Do **not** delete `SearchScreen.kt` or `CommunitySearchProvider` — search
  *behavior* is read-only, owned by Plan `260818-2112`.

### 3. Detail + Try Pose prepare + emit (WI-04)

Regression verify existing `tryPose()` / `PreparedPoseReference` path. This Plan
**owns prepare + emit only**:

- Success: set `PoseServiceLocator.preparedReference`, switch to `CameraTab`.
- **Not in scope:** Camera reading/consuming reference, overlay, persistence.

Plan `260809-2241` WI-03 describes durable commit before tab switch — **stale**
vs current in-memory emit at `Navigation.kt:152-156`. 2241 must reconcile; 2105
does not implement durable store.

### 4. Plan ordering with 2112 (M3)

- **2112** cooks search behavior (SearchScreen, provider, server `q`)
  independently — no `blockedBy` on 2105.
- **2105** retains the search icon wired to `SearchScreen` and, after 2112
  delivers, verifies the affordance remains wired (WI-03). It does **not** hide
  or unwire search.

### 5. Evidence (WI-05)

Per-row evidence IDs in DEC-003 matrix; separate:

- Camera navigation (Create Pose)
- Extraction deferred (negative)
- Search affordance wired (positive)
- 2241 overlay deferred (boundary)

## Prototype mapping

| Prototype | Production | Plan |
| --- | --- | --- |
| `poses-list.html` tabs + grid (search icon retained in acceptance) | `PosesScreen.kt` | WI-03 |
| `poses-list.html` Create Pose → `camera-live.html` | `Navigation.kt` | WI-02 |
| `pose-detail.html` | `PoseDetailScreen.kt` | WI-04 |
| `camera-pose-overlay.html` | `CameraScreen.kt` | Plan 2241 (reference) |

**Not authoritative for this slice:** `search.html` (Plan 2112), async extract flow.

## Dependencies

| Dependency | Role |
| --- | --- |
| FEAT-003 (approved) | Governing feature |
| Plan 260809-2241 (pending) | Consume `preparedReference`, overlay, persistence |
| Plan 260818-2112 (pending) | Search behavior (SearchScreen/provider/server) — independent; 2105 retains icon |
| Plan 260809-2240 (completed, read-only) | Prior library delivery evidence |
| REP-003 (read-only) | Historical verification |

## Risks

- Claiming FEAT-004 extraction wired via Create Pose navigation.
- Hiding or unwiring the search icon, which must stay wired to `SearchScreen`.
- Claiming Try Pose complete when overlay remains behind `if (false)`.
