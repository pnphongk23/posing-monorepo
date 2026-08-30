---
schema_version: 1
title: Product Delivery Roadmap
relationships:
  specs:
    - "[[product-feature-inventory]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans:
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
    - "[[260809-1806-camera-source-of-truth-convergence/plan|260809-1806]]"
    - "[[260809-2240-pose-reference-library-convergence/plan|260809-2240]]"
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-003-pose-reference-library-convergence-delivery|REP-003]]"
    - "[[REP-006-feat-003-pose-library-slice-delivery|REP-006]]"
    - "[[REP-007-feat-002-local-photo-gallery-delivery|REP-007]]"
    - "[[REP-010-phase2-live-community-forensic-baseline|REP-010]]"
    - "[[REP-011-firebase-observability-remote-config-delivery|REP-011]]"
    - "[[REP-012-backlog-lane-documentation-survey|REP-012]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths: []
type: spec
status: active
---

# Product Delivery Roadmap

**Revision:** Product Roadmap v1.0  
**Baseline:** `main` @ `ca33cc2585dd62f66999555cf60c93343189efca` (2026-08-30)  
**Published scope:** Snap Pose iOS 1.0 — phản ánh trạng thái code trên `main` tại
baseline. Không claim hành vi App Store Connect / production runtime nếu không có
evidence ASC hoặc báo cáo delivery tương ứng (xem
[REP-012](../reports/REP-012-backlog-lane-documentation-survey.md)).

## Scope

This is the business roadmap for AI Pose. It sequences the product around one
North Star outcome:

> A new user can choose a pose, see it in Camera, take a photo, and view the
> result.

The roadmap covers the user journey from the first successful photo through
Community discovery, Saved Poses, Albums, personal pose creation, and a
controlled publishing operation.

The roadmap is intentionally business-facing. Individual Features remain the
authority for detailed behavior; Plans determine implementation sequencing and
delivery evidence.

### Product sequence

```text
Choose pose → Use in Camera → Take photo → Keep photo
     ↓
Discover Community poses → Save pose → Organize in Album → Reuse pose
     ↓
Create personal pose → Publish safe, reusable poses
```

### v1.0 phase classification

Phân loại theo evidence trên baseline `main` @ `ca33cc2`. Các mô tả Phase 1–6
bên dưới giữ nguyên làm hợp đồng lịch sử; bảng này là trạng thái delivery thực
tế tại v1.0.

| Phase | v1.0 status | Evidence chính |
| --- | --- | --- |
| Phase 1 — First Pose Capture MVP | **shipped** | [REP-007](../reports/REP-007-feat-002-local-photo-gallery-delivery.md); `CameraScreen.kt` capture + overlay (`255-287`) |
| Phase 2 — Community Pose into Camera | **shipped** (residual partial) | [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md), [REP-006](../reports/REP-006-feat-003-pose-library-slice-delivery.md), [REP-005](../reports/REP-005-community-title-search-production-delivery.md); commit `e8ede24` |
| Phase 3 — Saved Poses | **future** | Không có auth/Save UX trên `main` |
| Phase 4 — Albums / Collections | **future** | Không có album UX trên `main` |
| Phase 5 — Personal Pose Creation | **partial** (deferred khỏi v1.0 UX) | Extract API + job pipeline có evidence server; tab My Poses đã gỡ (`0ca00b0`) |
| Phase 6 — Publish & Admin Operations | **partial** | Admin UI + `pose-extract-server` + R2 (`ffc9143`); operator loop chưa đủ depth catalogue |

**Residual partial trong shipped phases (không downgrade phase):**

- Session-scoped `PreparedPoseReference` → Camera overlay hoạt động; **chưa**
  durable relaunch restore theo plan `260809-2241` ([REP-012](../reports/REP-012-backlog-lane-documentation-survey.md) BL-GAP-01).
- Community catalogue depth / dual-layer source image — backlog post-v1.0.

### Current baseline (v1.0)

- **Shipped trên `main`:** chụp ảnh local, gallery (REP-007), duyệt Community,
  search, pose detail, Try Pose → `PreparedPoseReference` → Camera overlay
  (opacity, toggle, pan/zoom), Firebase observability + Remote Config
  (FEAT-010 / [REP-011](../reports/REP-011-firebase-observability-remote-config-delivery.md)),
  extract server async + admin operator slice.
- **Partial:** durable camera handoff qua relaunch (`ActivePoseReference`, plan
  `260809-2241`); personal extraction UX (My Poses tab removed); admin/community
  catalogue scale; một số gap pipeline [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
  còn relevant khi mở rộng publish.
- **Future (post-v1.0):** Saved Poses, Accounts, Albums, paywall/IAP
  (FEAT-011), Android parity.
- **Risk:** catalogue công khai phải an toàn trước khi scale discovery; monetization
  chưa approved cho product loop.

## Contract

### Roadmap principles

- The first successful photo has priority over breadth of features.
- Each phase must produce a usable customer outcome, not only an internal
  capability.
- A later phase may depend on the previous phase's user outcome, but must not
  make the first-use journey depend on login, AI processing, or Community
  availability unless explicitly stated.
- Guest use is allowed through personal capture. Account access is introduced
  when the user needs cross-session Saved Poses and Albums.
- A pose used for taking a photo does not automatically become owned,
  published, or saved by the user.

### Phase 1 — First Pose Capture MVP

**Objective:** Let a new user take the first photo with a pose quickly.

**In scope:**

- A small set of pose samples available in the app.
- Select one pose and open Camera with that pose visible.
- Show, hide, adjust opacity, and flip the pose guide.
- Take a photo and keep it in the personal gallery.
- View the newly captured photo.

**Result required:** The complete first-use loop works:
`open app → choose pose → open Camera → take photo → view photo`.

**Output for Phase 2:** A stable pose-guided capture experience and evidence that
users can complete the first photo without signing in.

**Explicitly out of scope:** AI extraction, login, Save, Albums, and publishing.

### Phase 2 — Community Pose into Camera

**Objective:** Let users discover a published pose and use it for a photo.

**In scope:**

- Browse published Community poses.
- Search and inspect pose details.
- Choose `Try Pose`.
- Open Camera with the selected Community pose.
- Capture and keep the resulting photo locally.

**Result required:** Every usable published pose can become an input to the
photo-taking journey.

**Output for Phase 3:** A reliable `discover → try → capture` journey and enough
usage evidence to identify which poses users want to keep.

**Explicitly out of scope:** Save/Unsave, Albums, and user publishing.

### Phase 3 — Saved Poses

**Objective:** Let users keep favorite Community poses for later use.

**In scope:**

- Save a published pose.
- Unsave a previously saved pose.
- View Saved Poses.
- Reuse a saved pose in Camera.
- Put a saved pose without a selected album into `Unassigned`.

**Business rules:**

- A pose can be saved only once per user.
- Save and Unsave are separate user actions.
- Saving a pose does not transfer ownership or publication rights.
- Removing a saved state does not remove photos already taken with that pose.

**Result required:** The user has a persistent personal list of poses that can
be reused.

**Output for Phase 4:** Saved Poses and the `Unassigned` destination are stable,
so organization can be added without changing the Save behavior.

**Explicitly out of scope:** User-created albums and user publishing.

### Phase 4 — Albums / Collections

**Objective:** Let users organize saved poses around real-life use cases.

**In scope:**

- Create, rename, and delete an album.
- Save a pose into a chosen album.
- Move a saved pose between albums.
- View saved poses in `Unassigned`.
- Reuse a pose from an album in Camera.

**Business rules:**

- When saving a pose, the user may choose one album.
- If no album is chosen, the pose goes to `Unassigned`.
- A saved pose belongs to at most one album in the first version.
- Deleting an album does not delete its poses; they return to `Unassigned`.
- Unsave is the action that removes a pose from the personal collection.

**Result required:** Users can organize saved poses into collections such as
“Outdoor”, “Travel”, or “Fashion” and reuse them.

**Output for Phase 5:** A complete `Save → Album → Try Pose` loop with stable
ownership and collection rules.

**Explicitly out of scope:** Shared albums, collaborative editing, and
many-albums-per-pose behavior.

### Phase 5 — Personal Pose Creation & AI Extraction

**Objective:** Let users create a reusable pose from their own source material.

**In scope:**

- Choose a source image.
- Request pose creation.
- See whether the request is processing, successful, or failed.
- Retry a failed request.
- View and reuse the resulting pose in Camera.
- Manage personal poses in `My Poses`.

**Result required:** Users can create and use personal poses without depending
on the public Community catalogue.

**Output for Phase 6:** Personal poses participate in the same camera journey as
the built-in and Community poses, with a clear path toward publication.

**Explicitly out of scope:** Public publishing, public discovery, and shared
creator workflows.

### Phase 6 — Publish & Admin Operations

**Objective:** Turn suitable poses into safe, reusable Community content.

**In scope:**

- Prepare a pose for publication.
- Publish and unpublish a pose.
- Control public visibility.
- Review and operate Community content.
- Monitor pose processing and recover failed operations.
- Select the approved extraction provider policy.

**Result required:** Community has a controlled supply of usable poses and can
remove content that should no longer be public.

**Product flywheel:**

`create pose → publish → discover → try → capture → save → reuse`.

**Explicitly out of scope:** Monetization, collaborative publishing, and social
feed behavior.

### Feature-to-phase ownership

| Phase | Primary Features |
| --- | --- |
| Phase 1 | [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]], [[FEAT-002-manage-a-local-photo-gallery\|FEAT-002]], first-use part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 2 | [[FEAT-003-browse-and-search-published-poses\|FEAT-003]], Camera handoff part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 3 | Saved Poses part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 4 | Album extension of [[FEAT-008-use-published-poses\|FEAT-008]] |
| Phase 5 | [[FEAT-004-extract-reusable-pose-images\|FEAT-004]], [[FEAT-005-manage-a-pose-guide\|FEAT-005]], part of [[FEAT-009-configure-extraction-provider\|FEAT-009]] |
| Phase 6 | [[FEAT-006-publish-a-pose\|FEAT-006]], [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]], remaining [[FEAT-009-configure-extraction-provider\|FEAT-009]] |

### v1.0 delivery evidence — five groups

Tóm tắt theo [REP-012](../reports/REP-012-backlog-lane-documentation-survey.md),
đối chiếu lại `main` @ `ca33cc2` trước khi edit roadmap này.

#### 1. iOS camera pose reference

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| `PreparedPoseReference` transport | **shipped** | `mobile/shared/.../PreparedPoseReference.kt`; `PoseServiceLocator.preparedReference` |
| Try Pose → Camera handoff | **shipped** | `Navigation.kt` `createTryPoseCameraHandoffAction` (`285-291`); [REP-006](../reports/REP-006-feat-003-pose-library-slice-delivery.md) `E-TRY-EMIT` |
| Overlay render (PNG/skeleton) | **shipped** | `CameraScreen.kt:255-287` `AsyncImage` khi `hasOverlay` |
| Opacity / toggle / pan-zoom | **shipped** | More menu + `Slider` + `detectTransformGestures` (`CameraScreen.kt`) |
| Durable relaunch restore | **future** | `BR-PREPREF-002`; plan `260809-2241` — `ActivePoseReference` chưa ship |
| `if (false)` overlay guard | **obsolete** | Không còn trên `main`; comment `E-2241-BOUNDARY` trong `Navigation.kt` stale |

`PreparedPoseReference` **vẫn là** runtime transport hiện hữu; không thay bằng
contract khác trong v1.0.

#### 2. Community poses

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Public catalogue API | **shipped** | `docs/spec/api/modules/community.md`; `PoseApiService.kt` `ignoreUnknownKeys` |
| Browse / search / detail | **shipped** | [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md), [REP-005](../reports/REP-005-community-title-search-production-delivery.md) |
| Try Pose từ Community | **shipped** | `PoseDetailScreen` + handoff action |
| My Poses tab | **removed in v1.0** | Commit `0ca00b0` — Poses screen Community-only |
| Dual-layer source image | **future** | Plan `260510-1726` pending |
| Catalogue scale (taxonomy depth) | **partial** | Operator pipeline có; volume targets chưa đạt |

#### 3. Paywall / purchase

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| FEAT-010 Firebase / Remote Config | **shipped** (iOS) | [REP-011](../reports/REP-011-firebase-observability-remote-config-delivery.md) |
| FEAT-011 RevenueCat / IAP | **future** | Plan `260826-0003` pending; **không** có paywall code trong `mobile/` |
| Product loop dependency | **out of v1.0** | Phase 1–2 MVP không yêu cầu monetization |

Không claim subscription/production IAP behavior.

#### 4. Admin UI

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Community list / create | **shipped** | `web/admin-ui/src/app/admin/community/page.js` |
| Read / edit / delete proxy | **shipped** | `api/admin/community/poses/[id]/route.js` GET/PATCH/DELETE |
| Backend PATCH/DELETE | **shipped** | `adminCommunityRoutes.ts`; `communityStore.updatePose` / `deletePose` |
| Extraction provider settings | **shipped** | `api/admin/settings/extraction-provider/` |
| Full operator loop at scale | **partial** | Content pipeline + review depth — backlog post-v1.0 |

`TODO.md` root checklist CRUD **stale** so với code trên `main`; evidence ưu tiên
routes/store hiện có.

#### 5. Extract server

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Async `POST /api/extract-pose` | **shipped** | `docs/spec/api/modules/extract-pose.md`; `web/services/pose-extract-server/` |
| Worker + provider factory | **shipped** | Higgsfield + parallel provider plan `260816-2240` |
| Community media R2 | **shipped** | Commit `ffc9143` |
| Job↔pose linkage / atomic publish | **partial** | [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md) GAP-001–007 — một phần đã cải thiện; vẫn relevant khi scale publish |
| Production deploy | **evidence only** | Railway runbook/skills trên `main`; không claim live traffic SLA |

### Brainstorm lanes

**Frozen:** 2026-08-30  
**Reconciled:** 2026-08-30 (Product Roadmap v1.0)

Frozen brainstorm cho delivery sequencing **post-v1.0**. Phần Wave/Milestone dưới
đây được giữ làm evidence lịch sử; mục **v1.0 status** phản ánh `main` @ `ca33cc2`
và loại claim stale (overlay `if (false)`, “first ship chưa xảy ra”).

#### Wave 0 — Foundation (start now, parallel)

**v1.0 status:** **partial shipped** — extract server, admin create/publish slice,
R2 media; taxonomy pilot và operating loop depth còn backlog.

Starts immediately as background work and runs in parallel with every other
wave and workstream in this brainstorm. Feeds Phase 6 operations and the
content supply needed for Phase 2 Community readiness.

- Content pipeline with AI-generated source imagery.
- Flat taxonomy v1 (10 groups): cafe, beach, hills, mountains, resort, pool,
  sunset, urban street, garden, home/studio; hierarchy deferred to a later wave.
- Consistent quality spec across persona, framing, lighting, and background.
- Pilot: first 100 poses across cafe and beach.
- Operating loop: intake → extract → review → publish.

| Bridge | Mapping |
| --- | --- |
| Phases | Phase 6 (publish/admin operations); supports Phase 2 catalogue depth |
| Features | [[FEAT-004-extract-reusable-pose-images\|FEAT-004]], [[FEAT-006-publish-a-pose\|FEAT-006]], [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]], [[FEAT-009-configure-extraction-provider\|FEAT-009]] |

#### Wave 1 — First ship

**v1.0 status:** **shipped** trên `main` @ `ca33cc2` — không còn là “first ship
pending”.

- Pose origin display: show the real reference image (not skeleton only) in home
  list, detail, and Camera. — **shipped** (`e8ede24`, `PoseDetailScreen`, overlay)
- Category shelf with filter and search. — **partial** (search shipped; category
  shelf taxonomy depth post-v1.0)
- Guidance text plus basic Camera overlay. — **shipped** (`CameraScreen.kt:255-287`)

| Bridge | Mapping |
| --- | --- |
| Phases | Phase 1 (first pose-guided capture); Phase 2 (discover → try → capture) |
| Features | [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]], [[FEAT-003-browse-and-search-published-poses\|FEAT-003]], [[FEAT-008-use-published-poses\|FEAT-008]] |
| New boundaries (document only) | Origin display, Guidance, Category browsing |

#### Milestone 2 — Pro Camera

**v1.0 status:** **partial shipped** — overlay đã active; durable handoff + pro
controls depth còn backlog.

Mobile-only cleanup and professional Camera controls. Overlay khớp
`PreparedPoseReference` contract; zoom, flash, exposure/brightness, grid, timer,
và full guidance overlay.

Đã ship trong v1.0 (không còn claim stale):

- Overlay rendering per Camera handoff contract — **shipped** (`CameraScreen.kt:255-287`).
- Pose line color White/Black — **shipped** (`60eb2ad`).

Post-v1.0 backlog (giữ intent gốc, bỏ stale guard):

- Durable `ActivePoseReference` + relaunch restore (plan `260809-2241`).
- Pro controls depth (exposure/timer polish) nếu chưa đủ parity prototype.

Color filters and presets v1: **chưa chốt / deferred — quyết định khi tới
phase**.

| Bridge | Mapping |
| --- | --- |
| Phases | Completes Phase 1 overlay experience; stabilizes Phase 2 Try Pose handoff |
| Features | [[FEAT-001-capture-a-photo-on-mobile\|FEAT-001]], Camera handoff part of [[FEAT-008-use-published-poses\|FEAT-008]] |
| New boundaries (document only) | Camera controls |

#### Milestone 3 — Account-based Saved Poses and Albums

**v1.0 status:** **future** — không nằm trong Snap Pose 1.0.

Sequence: Account infrastructure (auth, server, security) → Saved Poses →
Albums. Route is account-based, not local-first.

- Auth method (suggested: Sign in with Apple): **chưa chốt / deferred — quyết
  định khi tới phase**.
- Guidance language (assumed: Vietnamese): **chưa chốt / deferred — quyết định
  khi tới phase**.

| Bridge | Mapping |
| --- | --- |
| Phases | Phase 3 (Saved Poses); Phase 4 (Albums / Collections) |
| Features | [[FEAT-008-use-published-poses\|FEAT-008]] |
| New boundaries (document only) | Album; Account infra is a prerequisite slice, not a separate monetization lane |

Backend and web are in scope only to serve Account and Saved/Album behavior.

#### Wave 4 — Scale

**v1.0 status:** **future** — phụ thuộc Wave 0 depth + stable publish loop.

- Fill remaining taxonomy categories by priority.
- Hot categories: at least 100 poses each.
- Other groups: 20–50 poses each.

| Bridge | Mapping |
| --- | --- |
| Phases | Strengthens Phase 2 catalogue depth; sustains Phase 6 Community supply |
| Features | [[FEAT-003-browse-and-search-published-poses\|FEAT-003]], [[FEAT-006-publish-a-pose\|FEAT-006]], [[FEAT-007-operate-pose-content-from-admin-web\|FEAT-007]] |

#### Post-v1.0 sequencing (canonical)

Thứ tự ưu tiên sau baseline v1.0, theo dependency thực tế trên `main`:

```text
P0  Durable camera handoff (260809-2241) — ActivePoseReference, relaunch, clear lifecycle
P1  Community catalogue scale (Wave 0 + Wave 4) — taxonomy pilot, R2 content depth
P1  Dual-layer source image (260510-1726) — origin display fidelity
P2  Account → Saved Poses → Albums (Phase 3–4)
P2  Personal extraction UX restore (Phase 5) — sau khi My Poses strategy chốt
P3  Monetization FEAT-011 — sau Product Authority approve
Out Android parity; opportunistic backend/web cleanup ngoài Account/pipeline
```

**Out of scope post-v1.0 (ghi nhận, không mở ngầm):** paywall trong MVP loop;
Android; social feed; collaborative publishing.

#### Constraints and non-goals

- Clean-code scope is **mobile only**. Do not run opportunistic backend or web
  cleanup unless the change serves Account or the content pipeline.
- Backend and web changes are allowed only when they serve Account, Saved
  Poses, Albums, or the content pipeline.
- Monetization/IAP lane (FEAT-011) is out of scope for this brainstorm. FEAT-010
  (Firebase observability + Remote Config) is shipped iOS infrastructure, not
  monetization.
- Android parity is out of scope; no decision to open Android work here.
- Open and deferred items in this section are recorded, not resolved.

#### Deferred items (preserved)

| Item | Status |
| --- | --- |
| Taxonomy hierarchy beyond flat v1 | deferred — hierarchy để sau |
| Color filters / presets v1 | chưa chốt / deferred — quyết định khi tới phase |
| Auth method (Sign in with Apple suggested) | chưa chốt / deferred — quyết định khi tới phase |
| Guidance language (Vietnamese assumed) | chưa chốt / deferred — quyết định khi tới phase |
| Monetization / IAP (FEAT-011) | out of scope — không quyết định mở |
| Android parity | out of scope — không quyết định mở |

## Verification

The roadmap is considered on track only when each phase has both the stated
business outcome and the output needed by the next phase.

### Phase gates

| Gate | Evidence of completion | v1.0 |
| --- | --- | --- |
| Phase 1 | A new user can complete the first pose-guided photo flow and view the result. | **met** (session-scoped overlay) |
| Phase 2 | A published Community pose can be found, tried in Camera, and used for a photo. | **met** |
| Phase 3 | A user can Save, view, reuse, and Unsave a pose; unsorted poses appear in Unassigned. | **not met** |
| Phase 4 | A user can create and manage albums, assign saved poses, and recover poses to Unassigned when an album is deleted. | **not met** |
| Phase 5 | A user can create a personal pose, understand its processing outcome, retry failure, and use the result in Camera. | **partial** (server path; My Poses UX removed) |
| Phase 6 | An operator can control publication visibility and the public catalogue contains only usable, permitted poses. | **partial** |

### Success signals

- **First-use success:** percentage of new users who complete one pose-guided
  photo in their first session.
- **Capture value:** percentage of selected poses that lead to a captured photo.
- **Reuse value:** percentage of users who return to use a saved pose.
- **Collection value:** percentage of saved poses assigned to an intentional
  album rather than remaining in `Unassigned`.
- **Community value:** percentage of published poses that are successfully
  discovered and tried.
- **Creation value:** percentage of personal pose requests that produce a pose
  usable in Camera.

### Source of truth and review

- Business boundaries are maintained by the linked Feature documents.
- Delivery ordering is maintained by Harness Plans.
- **v1.0 baseline evidence:** [REP-012](../reports/REP-012-backlog-lane-documentation-survey.md)
  (five-group survey); delivery reports REP-003, REP-006, REP-007, REP-011 trên
  `main` @ `ca33cc2`.
- Residual gaps are grounded in [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
  and [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md).
- This roadmap should be reviewed when a Feature boundary, publication policy,
  Saved/Album rule, or v1.x publish baseline changes.
