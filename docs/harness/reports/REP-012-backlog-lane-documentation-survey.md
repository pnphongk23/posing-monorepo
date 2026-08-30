---
schema_version: 1
type: report
id: REP-012
title: Backlog lane documentation survey
status: completed
delivered: 2026-08-30
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[product-delivery-roadmap]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans:
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241]]"
    - "[[260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan|260826-0003]]"
  reports:
    - "[[REP-006-feat-003-pose-library-slice-delivery|REP-006]]"
    - "[[REP-010-phase2-live-community-forensic-baseline|REP-010]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - README.md
    - design.md
    - TODO.md
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - docs/spec
    - docs/harness
    - docs/prototype
    - plans
---

# REP-012: Khảo sát tài liệu lane BACKLOG

## Mục tiêu khảo sát

Đọc và đối chiếu các nguồn tài liệu được chỉ định trong Task Contract frozen, ghi nhận bằng chứng hiện có, khoảng trống, và nguồn sự thật (source of truth) cho từng lớp. Không thay đổi runtime hay source code.

## Phạm vi đã khảo sát

| Khu vực | Files / sections chính | Vai trò |
| --- | --- | --- |
| Root | `README.md`, `design.md`, `TODO.md` | Router monorepo, hợp đồng visual prototype, TODO thực thi admin CRUD |
| `docs/spec/api/` | `README.md`, `openapi.yaml`, `conventions.md`, `modules/*.md`, `CHANGELOG.md` | HTTP contract product |
| `docs/spec/data/` | `README.md`, `domain-model.md`, `entities/*.md`, `erd/`, `enums.md`, `CHANGELOG.md` | Data contract product |
| `docs/harness/` | `index.md`, `specs/`, `features/`, `plans/`, `reports/`, `workflows/`, `templates/` | Hành vi product, roadmap business, delivery evidence |
| `docs/prototype/` | `README.md`, `styles/tokens.css`, `screens/*.html` | UI visual reference tĩnh |
| `plans/` (root) | `260505-*`, `260510-*` | Kế hoạch thực thi kỹ thuật (phase-XX convention) |

## Source of truth theo lớp

| Lớp | Source of truth | Không được dùng thay thế bởi |
| --- | --- | --- |
| Hành vi product | `docs/harness/features/FEAT-*.md` + specs harness | Code hiện tại, prototype flow |
| Roadmap business | `docs/harness/specs/product-delivery-roadmap.md` | Root `plans/` chưa approved |
| Data contract | `docs/spec/data/` | Schema SQL runtime trực tiếp |
| API contract | `docs/spec/api/openapi.yaml` + `modules/` | Handler Express ad-hoc |
| UI production | `docs/harness/specs/ui-ux-system.md` + Compose/web tokens | `docs/prototype/` |
| UI prototype visual | `docs/prototype/styles/tokens.css` + `design.md` | `ui-ux-system.md` (Compose/web khác palette) |
| Delivery sequencing | `docs/harness/plans/` (Harness) + `plans/` (root lane) | `TODO.md` ad-hoc |

## Bằng chứng theo nhóm Snap Pose (5 lane)

### 1. iOS camera pose reference

| Evidence | Nội dung |
| --- | --- |
| `product-delivery-roadmap.md` Phase 1–2 | North Star: chọn pose → Camera → chụp → xem ảnh |
| `docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md` | Plan Harness pending: **durable** selection, relaunch restore, clear lifecycle |
| `REP-006` (`E-TRY-EMIT`) | Try Pose prepare + emit `PreparedPoseReference` + chuyển `CameraTab` — **đã delivered slice** |
| `REP-006` (`E-2241-BOUNDARY`) | Ghi nhận tại thời điểm 2026-08-19 overlay guard `if (false)` — **stale so với code hiện tại** |
| `CameraScreen.kt` | Overlay render, opacity/toggle, pan/zoom khi có `PreparedPoseReference` session-scoped |
| `Navigation.kt` | Comment `E-2241-BOUNDARY` vẫn cite `if (false)` tại line 173 — line 173 hiện là `LaunchedEffect(permissionState)` |
| `docs/spec/data/entities/prepared-pose-reference.md` | Transient contract; `BR-PREPREF-002` cấm persist qua relaunch |
| `FEAT-008` + plan 2241 | Relaunch persistence thuộc durable `ActivePoseReference` (app-level), chưa ship |
| `README.md` § Current limitations | Câu “Use with Camera” / overlay — **có thể lệch** so với `E-TRY-EMIT`; authority relaunch là FEAT-008/2241 |

**Gap còn lại (residual, không claim ship):** partial session handoff đã có evidence runtime; **chưa** có durable persistence qua relaunch, canonical promotion `PreparedPoseReference` → `ActivePoseReference`, managed cache lifecycle, clear/replace authority thống nhất theo plan 2241. Đây là P0 backlog lane — **future cook handoff**, không phải approval ship.

#### Parity matrix — camera handoff (tối thiểu)

| Khía cạnh | Prototype | Harness 2241 | Current code (evidence) | Residual gap |
| --- | --- | --- | --- | --- |
| Try Pose → Camera | Mock notice only (`docs/prototype/README.md` §10) | Prepare + navigate sau verify | `createTryPoseCameraHandoffAction` → `PoseServiceLocator.preparedReference` + `CameraTab` (`REP-006` `E-TRY-EMIT`) | Chỉ session-scoped; chưa promote sang durable store |
| Overlay render | `camera-pose-overlay.html` | Transparent PNG, default 50% opacity | `CameraScreen.kt:255-287` `AsyncImage` khi `hasOverlay` | Đọc từ transient reference, không restore sau relaunch |
| Opacity / toggle | Static demo | Toggle + opacity controls | More menu Show/Hide + `Slider` 0.1–1.0 (`CameraScreen.kt:858-881`) | Giữ behavior hiện hữu; gắn durable reference |
| Pan / zoom overlay | Không interactive | Không cấm gesture | `detectTransformGestures` pan + scale 0.4–2.5 (`CameraScreen.kt:274-280`) | **Không thuộc scope loại bỏ** |
| Relaunch persist | N/A | Survive termination | `BR-PREPREF-002`: không persist | **Gap P0 chính** — `ActivePoseReference` + managed cache |
| Clear lifecycle | N/A | Clear until replaced | Close về PosesTab **không** xóa reference (`CameraScreen.kt:290-291`) | Explicit clear + cache cleanup theo 2241 |

### 2. Community poses

| Evidence | Nội dung |
| --- | --- |
| `docs/spec/api/modules/community.md` | Public catalogue `GET /api/community/poses` |
| `docs/spec/data/entities/community-pose.md` | Published-only DTO |
| `REP-005`, `REP-010` | Title search production + Phase 2 forensic baseline |
| `plans/260510-1726-dual-layer-pose-source-image/` | Pending: `source_image_path` dual-layer |
| `TODO.md` | Admin Community CRUD chưa hoàn thành |

**Gap:** Dual-layer source image chưa land; admin PATCH/DELETE CRUD còn checklist mở; một số gap REP-002 (JSON/error envelope) có thể vẫn relevant tùy branch runtime.

### 3. Paywall / purchase

| Evidence | Nội dung |
| --- | --- |
| `docs/harness/plans/260826-0003-integrate-revenuecat-paid-access-and-iap-for-feat-011/plan.md` | Plan pending, FEAT-011 proposed |
| `product-delivery-roadmap.md` | Paid access không nằm Phase 1–2 MVP loop |
| Harness index | `next_feature_sequence: 12` — FEAT-011 chưa trong inventory chính thức |

**Gap:** Product Authority chưa approve FEAT-011; prototype Premium header “Unresolved” trong plan RevenueCat.

### 4. Admin UI

| Evidence | Nội dung |
| --- | --- |
| `docs/harness/features/FEAT-007-operate-pose-content-from-admin-web.md` | Boundary admin |
| `docs/spec/api/modules/admin-*.md` | Admin routes qua proxy Next.js |
| `TODO.md` | CRUD community poses: store, routes, proxy, page |
| `plans/260505-0840-admin-community-multipart-sync-extract/` | Multipart sync extract |

**Gap:** Read/edit/delete UX và proxy `[id]` chưa done theo TODO; phụ thuộc extract server job pipeline.

### 5. Extract server

| Evidence | Nội dung |
| --- | --- |
| `docs/spec/api/modules/extract-pose.md` | `POST /api/extract-pose` async job |
| `docs/spec/data/entities/extraction-job.md` | Job lifecycle |
| `REP-002` GAP-001–007 | Worker↔R2 linkage, atomic enqueue, concurrency |
| `docs/harness/plans/260816-2240-higgsfield-cli-parallel-extract-provider/` | Provider factory parallel |
| `web/services/pose-extract-server/plans/` | Provider strategy plans (ngoài scope docs lane) |

**Gap:** Một số pipeline gaps REP-002 vẫn là release blocker khi bật community publishing; provider ops đã có plan riêng.

## Lệch tài liệu design (design drift)

| File | Lệch | Canonical |
| --- | --- | --- |
| `docs/prototype/README.md` § Design System | Ghi `3px` border, `4px 4px 0` shadow | `tokens.css`: `--nb-border-width-thick: 2px`, `--nb-shadow-offset: 3px` |
| `design.md` | Khớp `tokens.css` | Đúng — không cần sửa token values |
| `ui-ux-system.md` vs `design.md` | Background pink khác (`#FAF8F3` vs `#FBF6EF`) | Cố ý: production Compose/web vs prototype |

Deliverable 2 chuẩn hoá `docs/prototype/README.md` theo `tokens.css` và `design.md`. Không thêm claim runtime mới.

## Gaps tổng hợp (ưu tiên backlog)

| ID | Gap | Severity | Nhóm |
| --- | --- | --- | --- |
| BL-GAP-01 | Durable camera handoff: relaunch restore, `ActivePoseReference`, clear/cache lifecycle (partial session overlay đã có) | P0 product | iOS camera |
| BL-GAP-02 | Prototype README lệch token geometry | P2 docs | design |
| BL-GAP-03 | Admin community CRUD incomplete | P1 ops | admin UI |
| BL-GAP-04 | Dual-layer source image pending | P1 UX | community |
| BL-GAP-05 | Extract worker↔R2 gaps (REP-002) | P0 khi publish | extract server |
| BL-GAP-06 | RevenueCat / paywall chưa approved | P2 monetization | paywall |

## Khuyến nghị ưu tiên lane BACKLOG

**Chọn trước:** iOS camera pose reference (Try Pose → Camera overlay durable handoff).

**Rationale:**

1. Khớp North Star Phase 1–2 trong `product-delivery-roadmap.md`.
2. Harness plan `260809-2241` đã có authority và work items — backlog lane bổ sung plan phase-XX executable tại `plans/` root.
3. Không phụ thuộc login, paywall, hay admin CRUD mới.
4. Community catalogue đã có slice delivery (REP-006); blocker còn lại là **durable** Camera consumption (relaunch), không phải render overlay session-scoped.

## Liên kết deliverable tiếp theo

| Deliverable | File |
| --- | --- |
| Design alignment | `docs/prototype/README.md`, cross-ref trong `design.md` |
| Roadmap 5 nhóm | `plans/260830-1327-snap-pose-roadmap/roadmap.md` |
| Plan chi tiết P0 | `plans/260830-1327-ios-camera-pose-reference/plan.md` + `phase-*.md` |

## Verification (docs-only)

- Khảo sát chỉ đọc markdown/yaml trong phạm vi Task Contract.
- Không sửa source, tests, configs, assets, CI.
- Báo cáo này là input cho design diff và roadmap/plan commits tiếp theo.

### `ckh validate` (targeted)

| Target | Kết quả |
| --- | --- |
| `ckh validate docs/harness/reports/REP-012-backlog-lane-documentation-survey.md --workspace .` | **Pass** sau remediation (frontmatter khớp REP-006/REP-011; bỏ `lane`/`persona`) |
| `ckh validate docs/harness/reports/REP-006-feat-003-pose-library-slice-delivery.md --workspace .` | Pass (mẫu frontmatter hợp lệ) |
| `ckh validate --all --workspace .` | **Fail baseline repo** — không do REP-012: `DEC-008` unapproved trên plan 260826-0003 WI; `runbook PREP.md` / `PLAN.md` / `CHECKLIST.md` thiếu frontmatter delimiter |

Lane executor: chỉ sửa artifact backlog; baseline failures ghi nhận, không mở rộng scope.
