---
schema_version: 1
title: Quản lý hướng dẫn Pose
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions: []
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
  source_paths:
    - web/services/pose-extract-server/src/db/communityStore.ts
    - web/services/pose-extract-server/src/db/extractionJobStore.ts
    - web/services/pose-extract-server/src/worker/job-processor.ts
    - web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts
    - web/services/pose-extract-server/src/routes/jobStatusRoutes.ts
    - web/services/pose-extract-server/src/routes/adminRoutes.ts
    - mobile/iosApp/iosApp/Features/Poses/PosesFeature.swift
    - mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift
    - mobile/iosApp/iosApp/Core/Database/AppDatabase.swift
    - mobile/iosApp/iosApp/Core/Database/DatabaseRecords.swift
    - mobile/iosApp/iosApp/Features/Support/AccountSessionModel.swift
type: feature
id: FEAT-005
status: approved
created: 2026-08-09
approved: 2026-09-24
approved_by: Product Authority
---

# FEAT-005: Manage a Pose Guide

## Introduction

Chủ sở hữu Pose quản lý metadata của tư thế và vòng đời của một tư thế đã được trích
xuất. Đây là chủ thể nghiệp vụ sở hữu trạng thái tư thế, nhưng phải sử dụng lại
hợp đồng trích xuất của [FEAT-004](./FEAT-004-extract-reusable-pose-images.md) và
ranh giới xuất bản của [FEAT-006](./FEAT-006-publish-a-pose.md). Phần triển khai
hiện tại mới hiện thực hóa một phần `aggregate` (cụm dữ liệu nghiệp vụ) này.

## Business Understanding

### Actors

| Vai trò | Loại | Mục tiêu | Trách nhiệm |
| --- | --- | --- | --- |
| Chủ sở hữu Pose | Vai trò nghiệp vụ | Duy trì vòng đời của một tư thế có thể tái sử dụng | Rà soát metadata và kết quả trích xuất |
| Người dùng di động | Người dùng | Tạo Pose cá nhân từ ảnh nguồn | Chọn ảnh nguồn, nhập metadata chuẩn, gửi yêu cầu, theo dõi job từ máy chủ và thử lại khi lỗi |
| Quản trị viên/người vận hành/người xử lý nền | Vai trò nghiệp vụ/quy trình bên ngoài | Xử lý công việc cộng đồng đang `queued` | Gửi, xử lý và kiểm tra job |

### Preconditions

- Yêu cầu tạo hướng dẫn có metadata ảnh nguồn đủ điều kiện và có luồng trích xuất.
- Người dùng di động có thể chọn ảnh nguồn từ Photo Library qua FEAT-002 và có các trường Pose chuẩn.

### Trigger

Người dùng di động gửi, kiểm tra hoặc thử lại một lượt trích xuất cá nhân; chủ sở hữu hoặc người vận hành gửi, kiểm tra, thử lại hoặc quản lý một hướng dẫn.

### Main flow

**Luồng cá nhân trên di động (chuẩn):**

1. **Actor:** Người dùng di động mở màn hình Add Pose chuyên biệt. **System:** Màn hình cung cấp một CTA để chọn ảnh từ Photo Library qua FEAT-002; không mở luồng camera.
2. **Actor:** Người dùng di động chọn ảnh trong Photo Library và nhập các trường Pose chuẩn — `name` và `tags` (bắt buộc); `description` là tùy chọn. **System:** Màn hình Add Pose xác thực các trường bắt buộc và ảnh nguồn.
3. **Actor:** Người dùng di động gửi yêu cầu. **System:** Thiết bị gửi ảnh multipart kèm draft metadata (`name`, `tags`, `description`) tới `POST /api/extract-pose` (yêu cầu xác thực tài khoản). Máy chủ lưu `owner_account_id` và `pose_draft` trên `ExtractionJob`, trả về `202 Accepted` cùng `jobId` và `pollUrl`.
4. **Actor:** Người dùng mở màn hình Jobs chuyên biệt (`SCR-005-01`). **System:** Màn hình đọc danh sách job của tài khoản từ máy chủ qua `GET /api/me/extract-jobs?state=active|finished` và thăm dò `GET /api/extract-jobs/:id`. Hàng hiển thị trạng thái trung thực: `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose`. Header màn hình Poses hiển thị nút `Jobs` kèm badge đếm số active jobs (`queued`, `processing`).
5. **System:** Khi tiến trình trích xuất phía máy chủ `succeeded`, worker tự động tạo `Pose` (`poseId` ổn định, `status=local`) và ba vai trò media (`original`, `skeleton`, `thumbnail`) trong một transaction lũy đẳng theo `jobId`, gán `pose_id` cho job, rồi dọn dẹp ảnh base64 tạm thời. Ứng dụng khách không cần gọi endpoint lưu riêng. Màn hình Jobs hiển thị `Ready` kèm nút `View pose` dẫn tới Pose Detail (`SCR-003-03`).

**Luồng quản trị/vận hành (cộng đồng):**

6. **Actor:** Người vận hành gửi metadata cộng đồng và một ảnh. **System:** Ảnh được gửi qua FEAT-004: dịch vụ đưa `ExtractionJob` vào hàng đợi và trả về `202` + `jobId` — chưa có `Pose` nào được tạo.
7. **System:** Tiến trình xử lý nền nhận và xử lý job. **System:** Job chuyển sang `queued`, `processing`, `succeeded` hoặc `failed`.
8. **Actor:** Người vận hành kiểm tra `status`. **System:** Dịch vụ trả về kết quả job mới nhất đã được xác nhận.
9. **System (creation timing):** Khi job ở trạng thái `succeeded`, dịch vụ tạo `Pose` (`poseId` ổn định, `status=local`) với metadata đã gửi và hiện thực hóa ba vai trò media (`original`, `skeleton`, `thumbnail`) (`201`), nhất quán với luồng di động; DTO/view công khai là `CommunityPose` với `status=published`.

### Alternative flows

- **A1 — Lỗi có thể thử lại (máy chủ).** Source step: 7. Condition: vẫn còn lượt thử. Behavior: đưa job trở lại hàng đợi. Resume at step: 7.
- **A2 — Thử trích xuất lại thủ công (di động).** Source step: 4. Condition: job ở trạng thái `failed` và người dùng chọn Retry. Behavior: client gọi `POST /api/me/extract-jobs/:id/retry` để máy chủ đưa job vào hàng đợi xử lý lại; job chuyển về `Queued`/`Processing`. Resume at step: 4.
- **A3 — Ẩn dòng job đã hoàn tất.** Source step: 4. Condition: job ở trạng thái `failed` hoặc `ready` và người dùng chọn xoá/ẩn dòng. Behavior: client gọi `DELETE /api/me/extract-jobs/:id`; máy chủ đánh dấu `hidden_at` và không trả về trong danh sách, tuyệt đối không xoá `Pose` đã tạo.

### Exception flows

- **E1 — Lỗi hàng đợi/metadata.** Source step: 3 hoặc 6. Failure: một thao tác ghi thất bại. Handling: trả về lỗi đã được tài liệu hóa và giữ lại bằng chứng để đối soát. Prohibited: khẳng định hướng dẫn đã sẵn sàng hoặc có `Pose` trước khi job ở trạng thái `succeeded`.
- **E2 — Tiến trình xử lý nền gặp lỗi.** Source step: 7. Failure: processing của nhà cung cấp thất bại. Handling: ghi nhận lỗi vào job. Prohibited: khẳng định đã sẵn sàng công khai.
- **E3 — Trích xuất thất bại (di động).** Source step: 4. Failure: job phía máy chủ chuyển sang `failed`. Handling: màn hình Jobs hiển thị chi tiết lỗi và thao tác `Retry` thủ công. Prohibited: âm thầm tự động thử lại hoặc khẳng định đã có Pose.

### Postconditions

- **Thành công:** `Pose` cá nhân (`status=local`) được máy chủ tạo tự động **sau khi** job trích xuất báo `succeeded`, kèm metadata draft đã gửi và **hiện thực hóa ba vai trò media: `original`, `skeleton`, `thumbnail`**; `pose_id` được liên kết với job. Trong luồng quản trị, Pose cũng được tạo theo cách tương tự sau `succeeded`.
- **Thất bại:** Job `failed` được lưu trên máy chủ theo tài khoản, hiển thị trên màn hình Jobs và có thao tác `Retry` thủ công.

### Current evidence

- **Đã quan sát (2026-09-25):** Quyết định Server-authoritative Jobs ([`plans/260925-server-authoritative-jobs/plan.md`](../../../plans/260925-server-authoritative-jobs/plan.md)) phê duyệt: máy chủ sở hữu hoàn toàn trạng thái extraction jobs theo tài khoản (`owner_account_id`, `pose_draft`, `pose_id`, `hidden_at`). Không sử dụng bảng lưu trữ Jobs cục bộ trên thiết bị và không có cảnh báo/xoá dữ liệu khi đăng xuất. Đăng xuất không xoá gì; đăng nhập lại trên bất kỳ thiết bị nào đều thấy cùng danh sách jobs.
- **APIs máy chủ:**
  - `POST /api/extract-pose`: nhận ảnh và draft metadata theo tài khoản, trả `202 Accepted` + `jobId`.
  - `GET /api/me/extract-jobs?state=active|finished&cursor=`: liệt kê jobs của tài khoản.
  - `GET /api/extract-jobs/:id`: kiểm tra trạng thái job theo tài khoản sở hữu.
  - `POST /api/me/extract-jobs/:id/retry`: thử lại job bị `failed`.
  - `DELETE /api/me/extract-jobs/:id`: ẩn dòng job (`hidden_at`), không xoá `Pose`.
- **UI di động:** Màn hình Add Pose chuyên biệt ([SCR-004-01](../designs/basic-design/screens/mobile/scr-004-01-add-pose.md)) và màn hình Jobs chuyên biệt ([SCR-005-01](../designs/basic-design/screens/mobile/scr-005-01-jobs.md)). Các hàng job chỉ mang bốn trạng thái: `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose`.
- **Chính sách đăng xuất:** Server quản lý jobs theo tài khoản. Đăng xuất không xoá jobs, không cảnh báo; đăng nhập lại tải lại đầy đủ jobs từ server.

### Traceability

| Mối quan tâm | Tham chiếu chuẩn | Bằng chứng |
| --- | --- | --- |
| Thực thể | [`Pose`](../specs/data-contract.md#pose), [`CommunityPose`](../specs/data-contract.md#communitypose) (view/DTO `published` đã xuất bản), [`ExtractionJob`](../specs/data-contract.md#extractionjob), [`MediaAsset`](../specs/data-contract.md#mediaasset), [`Account`](../specs/data-contract.md#account), [`ApiKeyCredential`](../specs/data-contract.md#apikeycredential) | [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts), [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql) |
| ERD | [Đồ thị vật lý phía máy chủ](../specs/data-contract.md#server), [Lớp phủ khái niệm](../specs/data-contract.md#conceptual-overlay) | [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts) |
| API | [Hướng dẫn](../specs/api-contract.md#pose-guides), [Trích xuất](../specs/api-contract.md#extract-pose), [key quản trị](../specs/api-contract.md#admin-keys), [cộng đồng](../specs/api-contract.md#admin-community), [job quản trị](../specs/api-contract.md#admin-jobs) | [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts), [`extractJobsRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractJobsRoutes.ts) |
| Luồng cá nhân trên di động | Màn hình Add Pose chuyên biệt ([SCR-004-01](../designs/basic-design/screens/mobile/scr-004-01-add-pose.md)), màn hình Jobs chuyên biệt ([SCR-005-01](../designs/basic-design/screens/mobile/scr-005-01-jobs.md)) | [`PoseAPIService.swift`](../../../mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift), [`PosesFeature.swift`](../../../mobile/iosApp/iosApp/Features/Poses/PosesFeature.swift) |

## Requirements

- **FR-001:** Yêu cầu gửi bằng `202 Accepted` được tiếp nhận ở trạng thái `queued`, không đồng nghĩa với việc đã sẵn sàng.
- **FR-002:** Trạng thái job phía máy chủ gồm `queued`, `processing`, `succeeded`, `failed`.
- **FR-003:** Người dùng di động tạo Pose cá nhân qua màn hình Add Pose, nơi thu thập các trường chuẩn — `name` và `tags` (bắt buộc); `description` (tùy chọn) — đồng thời chọn ảnh nguồn chỉ từ Photo Library qua [FEAT-002](./FEAT-002-manage-a-local-photo-gallery.md). Màn hình này không cung cấp camera entry. Payload gửi trực tiếp qua `POST /api/extract-pose` kèm metadata draft.
- **FR-004:** Máy chủ quản lý toàn bộ vòng đời extraction job theo tài khoản xác thực. Người dùng theo dõi qua danh sách `GET /api/me/extract-jobs` và thăm dò `GET /api/extract-jobs/:id`. Khi job `succeeded`, máy chủ tự động tạo `Pose` và media assets; không cần bước client save riêng.
- **FR-005:** Màn hình Jobs chuyên biệt `SCR-005-01` hiển thị jobs thuộc tài khoản theo hai tab `Processing` (`queued`, `processing`) và `Finish` (`failed`, `ready`), sắp xếp mới nhất trước. Tab `Finish` có filter `All results` / `Success` (`Ready`) / `Fail` (`Failed`). Thao tác: `Retry` qua `POST /api/me/extract-jobs/:id/retry` cho job `failed`, `View pose` dẫn tới Pose Detail cho job `ready`. Vuốt để ẩn dòng gọi `DELETE /api/me/extract-jobs/:id` (đánh dấu `hidden_at`, không xoá Pose).
- **BR-001:** Không công khai hướng dẫn cho đến khi chứng minh được mối liên hệ bền vững giữa asset và trạng thái sẵn sàng; không lưu `Pose` trước khi job trích xuất ở trạng thái `succeeded`.
- **BR-002:** Add Pose trên di động chỉ nhận ảnh qua Photo Library (FEAT-002); không mở hoặc sở hữu luồng nghiệp vụ CameraScreen (FEAT-001).
- **BR-003:** Khi job `succeeded`, máy chủ tạo `Pose` và ba `MediaAsset` (`original`, `skeleton`, `thumbnail`) tự động và lũy đẳng theo `jobId`.

## Acceptance

- [ ] Gửi ảnh và metadata draft qua `POST /api/extract-pose` nhận `202 Accepted` + `jobId`; máy chủ tự tạo `Pose` sau extraction `succeeded`.
- [ ] Trạng thái job phân biệt `queued`, `processing`, `succeeded` và `failed`.
- [ ] Chủ sở hữu, tài nguyên media và liên kết giữa job với tư thế tuân theo [`Pose`](../specs/data-contract.md#pose).
- [ ] Add Pose chỉ cung cấp một CTA mở Photo Library làm điểm chọn ảnh; không cung cấp camera entry.
- [ ] Jobs đọc từ server theo tài khoản xác thực; hai tab `Processing`/`Finish` hoạt động, filter `All results`/`Success`/`Fail` chỉ hiện trong `Finish`; các hàng dùng đúng các trạng thái `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose`.
- [ ] Retry gọi endpoint retry máy chủ; xoá/ẩn dòng đánh dấu `hidden_at` trên máy chủ và không xoá `Pose`.
- [ ] Đăng xuất không xoá dữ liệu jobs trên server và không hiển thị cảnh báo jobs.

## Relationships

- Tham chiếu chung: [CommunityPose](../specs/data-contract.md#communitypose) (view/DTO `published` đã xuất bản), [ERD khái niệm](../specs/data-contract.md#conceptual-overlay), [API quản trị](../specs/api-contract.md).
- Tính năng liên quan: [FEAT-004](./FEAT-004-extract-reusable-pose-images.md), [FEAT-006](./FEAT-006-publish-a-pose.md).
- Add Pose trên di động sử dụng Photo Library intake từ [FEAT-002](./FEAT-002-manage-a-local-photo-gallery.md); không mở luồng camera của FEAT-001.

### Supporting evidence

- [`communityStore.ts`](../../../web/services/pose-extract-server/src/db/communityStore.ts)
- [`extractionJobStore.ts`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts)
- [`job-processor.ts`](../../../web/services/pose-extract-server/src/worker/job-processor.ts)
- [`adminCommunityRoutes.ts`](../../../web/services/pose-extract-server/src/routes/adminCommunityRoutes.ts)
- [`REP-004`](../reports/REP-004-backend-feature-and-model-entity-scout.md)
- [`plans/260925-server-authoritative-jobs/plan.md`](../../../plans/260925-server-authoritative-jobs/plan.md)
