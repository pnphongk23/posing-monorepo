---
schema_version: 1
type: feature
id: FEAT-013
title: Saved Poses & Albums (Account-backed)
status: proposed
created: 2026-08-31
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[ui-ux-system|UI/UX System]]"
  decisions: []
  plans:
    - "[[260831-0000-saved-poses-account-backed-v1/plan|Saved Poses account-backed v1]]"
  reports:
    - "[[REP-012-backlog-lane-documentation-survey|REP-012]]"
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - web/services/pose-extract-server/src/app.ts
    - web/services/pose-extract-server/src/routes/communityRoutes.ts
    - web/services/pose-extract-server/src/middleware/adminAuth.ts
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/schema.sql
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/remote/PoseApiService.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseRepository.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PosesScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
---

# FEAT-013: Saved Poses & Albums (Account-backed)

## Introduction

**Mục tiêu:** Đây là policy mới cho P2 Account-backed Saved Poses. Người dùng
đã đăng nhập lưu pose published, xem collection của mình và dùng lại trong flow
Try Pose. V1 chỉ triển khai Saved Poses; Albums là future/out-of-scope.
Feature đang proposed; approval của Product Authority còn pending. Đây không phải
claim rằng auth, Saved API hay Saved UI đã shipped.

**Phạm vi:** Google trên nền tảng Supabase cho auth và Account/session; Saved
collection qua SavedEntry; mobile Save/Unsave, Saved list và mở detail/Try Pose.
Guest chưa có signed-in Account thì bắt buộc sign-in và không được Try Pose.

**Ngoài phạm vi:** Albums CRUD/membership UI/API, social sharing, ownership/
publish, local-first sync/conflict, queued offline mutation, Android parity,
  camera relaunch thuộc FEAT-012. Không có work item triển khai Album trong v1.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Signed-in Account | User | Lưu và dùng lại pose published | Chọn Save/Unsave, mở Saved item, chọn Try Pose |
| Signed-out visitor/Guest | User | Hiểu và hoàn tất sign-in | Không được Save/Saved/Try Pose trước khi sign-in |
| Supabase Google auth | External identity provider | Xác thực danh tính và session | Trả auth result/session để backend map thành Account |
| Pose catalogue | Existing system | Cung cấp pose published | Chỉ cho Saved entry với pose còn published |

### User needs

- Người dùng cần collection Saved bền vững theo Account, không bị lẫn account khác.
- Người dùng cần biết khi pose đã bị xoá/ẩn và không được báo success giả khi mạng lỗi.
- Người dùng cần đọc stale Saved data khi offline, nhưng không được queue mutation.

### Preconditions

- Save/Unsave/Saved/Try Pose yêu cầu signed-in Account/session; Guest chỉ nhận
  sign-in requirement.
- Save target là pose published; pose missing/non-published không tạo SavedEntry.
- Runtime Google/Supabase integration path phải được xác minh trong implementation;
  contract provider đã frozen, nhưng evidence runtime hiện **Unresolved**.

### Trigger

Signed-in Account chọn Save/Unsave trên pose detail hoặc mở Saved list và chọn một
saved item để xem detail/Try Pose.

### Main flow

1. **Actor:** Account sign-in bằng Google trên Supabase. **System:** tạo/đọc
   Account/session và gửi session credential cho API.
2. **Actor:** Account chọn Save trên pose published. **System:** upsert một
   SavedEntry, trả 200, không duplicate.
3. **Actor:** Account mở Saved. **System:** trả paginated published projection,
   render loading/empty/error/retry đúng trạng thái.
4. **Actor:** Account mở item và chọn Try Pose. **System:** mở detail hiện hữu,
   chỉ sau sign-in mới chạy flow verify/handoff hiện có.

### Alternative flows

- **A1 — Signed-out action.** Source step: 2–4. Condition: chưa có Account/session. Behavior: yêu cầu sign-in; không tạo entry, không xác nhận Saved, Guest không được Try Pose. Resume at step: 1 after sign-in; ends with sign-in requirement otherwise.
- **A2 — Repeated Save.** Source step: 2. Condition: cặp accountId + poseId đã tồn tại. Behavior: trả success tương đương 200, giữ đúng một entry. Ends with: một entry duy nhất.
- **A3 — Idempotent Unsave.** Source step: 2. Condition: entry đã không tồn tại. Behavior: trả 204, không tạo hoặc xoá dữ liệu khác. Ends with: collection unchanged.
- **A4 — Offline read.** Source step: 3. Condition: network unavailable. Behavior: chỉ đọc stale data nếu có; không queue Save/Unsave; mutation failure không hiển thị success. Ends with: stale read or retryable failure.

### Exception flows

- **E1 — Missing/non-published pose.** Source step: 2. Failure: target không tồn tại hoặc không published. Handling: policy error/404 (hoặc contract error tương đương), không tạo entry. Prohibited: báo Saved success.
- **E2 — Unpublished/terminal-deleted pose.** Source step: 3–4. Failure: pose đã bị unpublish hoặc delete. Handling: list/API chỉ trả pose published usable; persistence vẫn giữ SavedEntry. Với stale detail, deep-link hoặc use attempt, UI báo đúng ý “đã xoá hoặc đã ẩn”. Prohibited: mở Try Pose hoặc xoá entry tự động; không invent tombstone list model.
- **E3 — 401/session invalid.** Source step: 1–4. Failure: API trả 401. Handling: không leak account collection, refresh/clear session theo auth flow, đưa user về sign-in requirement. Prohibited: trả collection của account khác.
- **E4 — Network/server error.** Source step: 2–3. Failure: request không thành công. Handling: error + retry; không hiển thị success giả. Prohibited: coi request thất bại là mutation thành công.

### Postconditions

- **Success:** Đúng account có một Saved collection; Save trả 200, Unsave trả
  204; Saved list chỉ trình bày pose published còn usable.
- **Failure:** Không có SavedEntry mới ngoài điều kiện hợp lệ; không leak data,
  không claim success; entry cũ vẫn tồn tại khi pose bị unpublish/delete.

## Requirements

- **FR-001:** Hệ thống shall dùng Google trên Supabase cho auth và signed-in
  Account/session; mọi Save, Saved list và Try Pose đều yêu cầu session hợp lệ.
- **FR-002:** Signed-out Save/Saved/Try Pose shall yêu cầu sign-in; Guest shall
  không được Try Pose.
- **FR-003:** Save published pose shall tạo/upsert đúng một SavedEntry theo
  (accountId, poseId) và trả 200; repeated Save không duplicate.
- **FR-004:** Unsave shall trả 204, idempotent khi entry không tồn tại, và không
  xoá pose.
- **FR-005:** Missing, unpublished hoặc non-published pose shall không tạo entry và
  trả policy error/404 theo Saved API contract.
- **FR-006:** Unpublish/terminal delete shall giữ SavedEntry persistence-side;
  list/API chỉ trả pose published usable, còn stale detail/deep-link/use attempt
  báo đúng ý “đã xoá hoặc đã ẩn” và không cho Try Pose.
- **FR-007:** 401 shall không leak account collection; client shall refresh/clear
  session và chuyển về sign-in requirement.
- **FR-008:** Network error shall không hiển thị success giả; Saved list shall có
  loading, empty, error, retry và pagination; chỉ đọc stale data offline và không
  queue Save/Unsave.
- **FR-009:** Saved item shall mở detail hiện hữu; Try Pose chỉ chạy sau sign-in
  và reuse flow verify/handoff hiện có.
- **FR-010:** Albums many-to-many (một pose có thể thuộc nhiều Album) là future
  boundary; Album CRUD/membership không thuộc acceptance hay implementation v1.

### Non-goals

Albums CRUD/membership UI/API; social sharing; ownership/publish; local-first
sync/conflict; queued offline mutation; Android parity; camera relaunch và FEAT-012.

## Acceptance

- [ ] Google/Supabase sign-in tạo hoặc khôi phục Account/session; runtime evidence
  được ghi trong Plan trước approval.
- [ ] Signed-out Save, Saved và Try Pose đều yêu cầu sign-in; Guest không Try Pose.
- [ ] Signed-in Save published trả 200, repeated Save không duplicate.
- [ ] Unsave trả 204 và idempotent.
- [ ] Missing/unpublished/non-published pose không tạo entry và trả policy error/404.
- [ ] Unpublish/terminal delete giữ SavedEntry persistence-side; list/API lọc
  pose usable/published; stale detail/deep-link/use attempt bị chặn và báo “đã
  xoá hoặc đã ẩn”.
- [ ] 401 không leak collection và client refresh/clear session.
- [ ] Network error không có success giả; mutation có retryable error.
- [ ] Saved list chỉ dùng được với signed-in Account và có loading/empty/error/retry/
  pagination; offline chỉ đọc stale, không queue mutation.
- [ ] Saved item mở detail hiện hữu; Try Pose chỉ sau sign-in.
- [ ] Không có Album work item; many-to-many Albums được ghi rõ là future boundary.

**Scenario: signed-in Save**
Given a valid signed-in Account và published pose
When Account chọn Save
Then API trả 200 và collection có đúng một SavedEntry.

**Scenario: removed published pose**
Given SavedEntry tồn tại và pose bị unpublish/delete
When Account mở stale detail/deep-link hoặc chọn Try Pose
Then list/API không trả pose usable, entry không bị xoá tự động, UI báo “đã xoá hoặc đã ẩn”.

**Scenario: invalid session**
Given client có collection account A nhưng session invalid
When API trả 401
Then collection không bị leak, session được refresh/clear và user phải sign-in.

**Scenario: offline mutation**
Given Saved list stale và network unavailable
When Account chọn Save/Unsave
Then không queue mutation và không hiển thị success giả.

## Relationships

- Roadmap: [Product Delivery Roadmap](../specs/product-delivery-roadmap.md), P2 Saved Poses & Albums.
- Existing feature boundaries: [FEAT-003](FEAT-003-browse-and-search-published-poses.md), [FEAT-006](FEAT-006-publish-a-pose.md), [FEAT-008](FEAT-008-use-published-poses.md).
- FEAT-008 is the predecessor/boundary for published-pose use and existing Try Pose flow; this policy does not change its frozen Guest gate.
- Contracts: [Account](../../spec/data/entities/account.md), [SavedEntry](../../spec/data/entities/saved-entry.md), [Saved API](../../spec/api/modules/saved.md), [API Conventions](../../spec/api/conventions.md).
- Current flow reuse: CommunityPose, PoseDetailScreen, PoseApiService, PoseRepository, existing pagination and error conventions.
- Albums boundary: many-to-many is reserved for a future Feature/Plan; this Feature v1 has no Album implementation work.
