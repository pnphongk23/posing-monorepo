---
schema_version: 1
title: Backlog Lane Documentation Survey
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
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
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
    - docs/spec
    - docs/harness
    - docs/prototype
    - plans
type: report
id: REP-012
status: completed
delivered: 2026-08-30
lane: backlog
persona: "Lính · Bàng Đức"
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
| `README.md` § Current limitations | “Use with Camera” chưa chuyển pose overlay |
| `product-delivery-roadmap.md` Phase 1–2 | North Star: chọn pose → Camera → chụp → xem ảnh |
| `docs/harness/plans/260809-2241-selected-pose-camera-handoff/plan.md` | Plan Harness pending: persist selection, overlay 50%, relaunch |
| `REP-006` | Try Pose prepare+emit đã có; overlay deferred sang 2241 |
| `docs/spec/data/entities/prepared-pose-reference.md` | Hợp đồng transient Try Pose handoff |
| `docs/prototype/screens/camera-pose-overlay.html` | Visual reference overlay |

**Gap:** End-to-end handoff Camera overlay chưa delivered; overlay rendering bị tắt trong code (REP-002/2241 mô tả `if (false)`).

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
| BL-GAP-01 | Camera pose overlay handoff chưa end-to-end | P0 product | iOS camera |
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
4. Community catalogue đã có slice delivery (REP-006); blocker còn lại là Camera consumption.

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
