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

Roadmap business cho AI Pose / Snap Pose. North Star:

> Người dùng mới chọn pose, thấy pose trong Camera, chụp ảnh, và xem kết quả.

Hành vi chi tiết thuộc Feature documents; thứ tự delivery thuộc Harness Plans.
Roadmap này chỉ mô tả **v1.0 đã ship** và **backlog post-v1.0** còn cần làm.

### Hành trình sản phẩm (định hướng)

```text
[v1.0 shipped]  Chọn pose → Camera → Chụp → Gallery
                Community browse/search/detail → Try Pose → Camera

[post-v1.0]     Save pose → Album → Tái sử dụng
                Tạo pose cá nhân → Publish an toàn
                IAP / paywall (FEAT-011, khi được approve)
```

## v1.0 baseline

Evidence: `main` @ `ca33cc2`, scout độc lập + [REP-012](../reports/REP-012-backlog-lane-documentation-survey.md).
Shipped được ghi nhận **iOS-scoped**; physical-device và Android không claim đủ
evidence trong v1.0.

### Đã ship trên `main`

| Nhóm | Nội dung | Evidence |
| --- | --- | --- |
| Capture & gallery | Chụp, persistence local, gallery search/delete/export | [REP-007](../reports/REP-007-feat-002-local-photo-gallery-delivery.md); `CameraScreen.kt`, `PhotoRepository` |
| Camera pose reference | `PreparedPoseReference` session transport; Try Pose verify + handoff; overlay opacity/toggle/pan-zoom/tint | `PreparedPoseReference.kt:7-29`, `PoseServiceLocator.kt:12-21`, `PoseDetailScreen.kt:317-351`, `Navigation.kt:285-291`, `CameraScreen.kt:248-287` |
| Community | Browse, search, detail, Try Pose từ catalogue | [REP-003](../reports/REP-003-pose-reference-library-convergence-delivery.md), [REP-005](../reports/REP-005-community-title-search-production-delivery.md), [REP-006](../reports/REP-006-feat-003-pose-library-slice-delivery.md); commit `e8ede24` |
| Extract server | Async job, polling, provider factory | `web/services/pose-extract-server/`; plan `260816-2240` |
| Admin & ops | Community list/create/edit/delete, R2 media, provider settings | `web/admin-ui/`; `adminCommunityRoutes.ts`; commit `ffc9143` |
| Observability / config | FEAT-010 Firebase + Remote Config (iOS) | [REP-011](../reports/REP-011-firebase-observability-remote-config-delivery.md) |

`PreparedPoseReference` **vẫn là** runtime transport hiện hữu cho Try Pose → Camera.

### Partial còn lại sau v1.0 (không downgrade shipped)

- **Durable camera handoff:** overlay session-scoped hoạt động; relaunch restore,
  clear lifecycle, managed cache chưa đủ theo plan `260809-2241`
  ([REP-012](../reports/REP-012-backlog-lane-documentation-survey.md) BL-GAP-01).
- **Community catalogue:** operator loop có; taxonomy depth / volume targets chưa
  đạt; dual-layer source image (plan `260510-1726`) chưa land.
- **Personal extraction UX:** server/job path có evidence; tab My Poses đã gỡ
  (`0ca00b0`) — UX mobile chưa restore.
- **Publish pipeline:** một số gap [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
  vẫn relevant khi scale publish.

### Chưa ship (post-v1.0)

- Saved Poses, Accounts, Albums ([[FEAT-008-use-published-poses|FEAT-008]] scope
  chưa deliver).
- FEAT-011 monetization / IAP / paywall — **không** có RevenueCat/purchase code
  trong `mobile/`.
- Android parity.

**Rủi ro:** scale Community discovery trước khi catalogue an toàn; FEAT-011 chưa
approved cho product loop.

## v1.0 delivery evidence — five groups

#### 1. iOS camera pose reference

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| `PreparedPoseReference` transport | **shipped** | `PreparedPoseReference.kt:7-29`; `PoseServiceLocator.kt:12-21` |
| Try Pose verify + handoff | **shipped** | `PoseDetailScreen.kt:317-351`; `createTryPoseCameraHandoffAction` (`Navigation.kt:285-291`); [REP-006](../reports/REP-006-feat-003-pose-library-slice-delivery.md) `E-TRY-EMIT` |
| Overlay render | **shipped** | `CameraScreen.kt:248-287` |
| Opacity / toggle / pan-zoom / tint | **shipped** | More menu, `Slider`, `poseLineColor`, `detectTransformGestures` |
| Durable relaunch restore | **post-v1.0 gap** | `BR-PREPREF-002`; plan `260809-2241` |

#### 2. Community poses

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Public catalogue API | **shipped** | `docs/spec/api/modules/community.md`; `PoseApiService.kt` |
| Browse / search / detail | **shipped** | REP-003, REP-005 |
| Try Pose từ Community | **shipped** | `PoseDetailScreen` + handoff |
| Poses screen Community-only | **shipped** | My Poses tab removed (`0ca00b0`) |
| Dual-layer source image | **post-v1.0** | Plan `260510-1726` |
| Catalogue scale | **partial** | Pipeline có; volume chưa đạt |

#### 3. Paywall / purchase

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| FEAT-010 observability / Remote Config | **shipped** (iOS) | [REP-011](../reports/REP-011-firebase-observability-remote-config-delivery.md) |
| FEAT-011 IAP / paywall | **post-v1.0** | Plan `260826-0003` pending; không có paywall code trong `mobile/` |

Không claim subscription/production IAP behavior.

#### 4. Admin UI

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Community CRUD + proxy | **shipped** | `admin/community/page.js`; `poses/[id]/route.js` |
| Backend PATCH/DELETE | **shipped** | `adminCommunityRoutes.ts`; `communityStore` |
| Provider settings | **shipped** | `api/admin/settings/extraction-provider/` |
| Operator loop at scale | **partial** | Content depth — post-v1.0 |

#### 5. Extract server

| Khía cạnh | v1.0 status | Evidence |
| --- | --- | --- |
| Async extract + worker | **shipped** | `pose-extract-server/` |
| Provider factory | **shipped** | Plan `260816-2240` |
| Community media R2 | **shipped** | Commit `ffc9143` |
| Job↔pose atomic publish | **partial** | REP-002 GAP-001–007 khi scale |

## Post-v1.0 backlog

Thứ tự ưu tiên theo dependency trên `main` @ `ca33cc2`. Chỉ liệt kê việc **còn
cần**; không biến capability đã ship thành pending.

### P0 — Durable camera handoff

**Mục tiêu:** selection survive relaunch; clear/replace lifecycle thống nhất.

- Plan authority: `260809-2241`.
- Giữ `PreparedPoseReference` làm transport hiện hữu; mở rộng durable selection
  theo plan — **không** định nghĩa runtime contract mới trong roadmap này.
- Features: [[FEAT-001-capture-a-photo-on-mobile|FEAT-001]], camera handoff
  [[FEAT-008-use-published-poses|FEAT-008]].

### P1 — Community catalogue scale

**Mục tiêu:** đủ depth và chất lượng cho discovery ổn định.

- Taxonomy pilot (flat v1: cafe, beach, hills, mountains, resort, pool, sunset,
  urban street, garden, home/studio).
- Operating loop: intake → extract → review → publish.
- Volume targets: hot categories ≥100 poses; nhóm khác 20–50.
- Dual-layer source image (plan `260510-1726`).
- Features: [[FEAT-003-browse-and-search-published-poses|FEAT-003]],
  [[FEAT-006-publish-a-pose|FEAT-006]], [[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]],
  [[FEAT-004-extract-reusable-pose-images|FEAT-004]], [[FEAT-009-configure-extraction-provider|FEAT-009]].

### P2 — Saved Poses & Albums

**Mục tiêu:** account-based Save → Album → Try Pose reuse.

- Thứ tự: Account infrastructure → Saved Poses → Albums (không local-first).
- Auth method (Sign in with Apple gợi ý): **chưa chốt**.
- Feature: [[FEAT-008-use-published-poses|FEAT-008]].
- Backend/web chỉ khi phục vụ Account hoặc Saved/Album.

### P2 — Personal extraction UX

**Mục tiêu:** restore luồng tạo pose cá nhân trên mobile sau khi strategy My
Poses được chốt.

- Server/job path đã có; UX mobile là gap chính.
- Features: [[FEAT-004-extract-reusable-pose-images|FEAT-004]],
  [[FEAT-005-manage-a-pose-guide|FEAT-005]].

### P3 — Monetization (FEAT-011)

**Mục tiêu:** paid access / IAP sau Product Authority approve.

- Plan `260826-0003`; **không** nằm trong core loop v1.0.
- FEAT-010 (observability/config) đã ship — **không** thuộc monetization.

### Out of scope (ghi nhận)

| Item | Status |
| --- | --- |
| Android parity | out of scope — chưa mở quyết định |
| Social feed / collaborative publishing | out of scope |
| Color filters / presets v1 | chưa chốt |
| Auth method / guidance language | chưa chốt khi tới Saved Poses |
| FEAT-011 IAP | chờ approve — không mở ngầm |

## Nguyên tắc

- Core loop (chọn pose → Camera → chụp → xem) ưu tiên hơn breadth.
- Guest capture không yêu cầu login; Account khi cần Saved/Album cross-session.
- Chọn pose để chụp **không** tự động Save, publish, hay transfer ownership.
- Clean-code opportunistic: **mobile only**, trừ khi phục vụ Account hoặc content
  pipeline.

## Verification

### Success signals

- **First-use success:** % người dùng mới hoàn thành một pose-guided photo trong
  session đầu.
- **Capture value:** % pose được chọn dẫn tới ảnh chụp.
- **Reuse value:** % người dùng quay lại dùng saved pose (post-v1.0).
- **Collection value:** % saved pose nằm trong album có chủ đích (post-v1.0).
- **Community value:** % published pose được discover và try.
- **Creation value:** % personal pose request tạo pose dùng được trong Camera.

### Source of truth and review

- Business boundaries: linked Feature documents.
- Delivery sequencing: Harness Plans (ví dụ `260809-2241`, `260826-0003`).
- v1.0 evidence: [REP-012](../reports/REP-012-backlog-lane-documentation-survey.md);
  REP-003, REP-006, REP-007, REP-011 trên `main` @ `ca33cc2`.
- Residual gaps: [REP-002](../reports/REP-002-feature-gap-and-release-readiness-audit.md).
- Review lại roadmap khi Feature boundary, publication policy, Saved/Album rule,
  hoặc v1.x publish baseline thay đổi.
