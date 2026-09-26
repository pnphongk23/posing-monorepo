---
schema_version: 1
title: Trích xuất ảnh Pose có thể tái sử dụng
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans:
    - "[[260816-2240-higgsfield-cli-parallel-extract-provider/plan|260816-2240]]"
  reports:
    - "[[REP-002-feature-gap-and-release-readiness-audit|REP-002]]"
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-009-configure-extraction-provider|FEAT-009]]"
  source_paths:
    - web/services/pose-extract-server/src/routes/extractPoseRoutes.ts
    - web/services/pose-extract-server/src/services/geminiService.ts
    - mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift
    - mobile/iosApp/iosApp/Features/Poses/PosesFeature.swift
type: feature
id: FEAT-004
status: approved
created: 2026-08-09
approved: 2026-08-17
approved_by: Product Authority
---

# FEAT-004: Extract Reusable Pose Images

## Introduction

Một ảnh nguồn được xác thực rồi gửi qua nhà cung cấp trích xuất để tạo ra một
skeleton (bộ khung xương) có thể tái sử dụng (đầu ra của quá trình trích xuất). Tài liệu này quy định hợp đồng yêu cầu/kết quả chung;
metadata/quyền sở hữu hướng dẫn thuộc [FEAT-005](./FEAT-005-manage-a-pose-guide.md),
bề mặt vận hành quản trị thuộc [FEAT-007](./FEAT-007-operate-pose-content-from-admin-web.md),
còn việc chọn engine trích xuất toàn cục thuộc
[FEAT-009](./FEAT-009-configure-extraction-provider.md) theo
[DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md).
Tính năng này mô tả **processing (quy trình xử lý)** bằng hai engine và luồng job bất đồng bộ; tài liệu
không quy định engine nào được chọn.

## Business Understanding

### Actors

| Vai trò | Loại | Mục tiêu | Trách nhiệm |
| --- | --- | --- | --- |
| Người dùng di động hoặc quản trị viên | Vai trò người dùng/nghiệp vụ | Tạo bộ khung xương cho tư thế có thể tái sử dụng | Gửi một ảnh nguồn đủ điều kiện |
| Nhà cung cấp AI | Hệ thống bên ngoài | Trả về bộ khung xương | Xử lý ảnh nguồn và báo kết quả |

### Preconditions

- Ứng dụng khách cung cấp một ảnh được hỗ trợ thông qua một luồng tiếp nhận.

### Trigger

Tác nhân gửi một ảnh nguồn để trích xuất (kèm metadata draft trong luồng tạo Pose di động).

### Main flow

1. **Actor:** Tác nhân gửi một ảnh (kèm `name`, `tags`, `description` tùy chọn trong luồng di động có xác thực Account). **System:** Dịch vụ xác thực payload multipart và áp dụng bộ giới hạn trích xuất.
2. **System:** Dịch vụ đưa một `ExtractionJob` vào hàng đợi (lưu `owner_account_id` và `pose_draft` trên job) và trả về `202 Accepted` cùng `jobId` và URL để thăm dò.
3. **System:** Tiến trình xử lý nền nhận quyền xử lý job và gọi engine được cấu hình toàn cục (`gemini_native` hoặc `higgsfield_cli`) thông qua `PoseExtractorProvider` theo [FEAT-009](./FEAT-009-configure-extraction-provider.md) / [DEC-001](../decisions/DEC-001-extraction-provider-selection-policy.md).
4. **Actor:** Tác nhân thăm dò hoặc liệt kê job từ máy chủ. Với ứng dụng khách di động, danh sách job được đọc qua `GET /api/me/extract-jobs?state=active|finished` và thăm dò qua `GET /api/extract-jobs/:id` (được kiểm tra theo quyền sở hữu tài khoản). **System:** Khi thành công, tiến trình xử lý tự động tạo `Pose` và ba media assets (`original`, `skeleton`, `thumbnail`) trong cùng transaction, gán `pose_id` cho job, và xóa dữ liệu base64 tạm thời; khi thất bại, trả về `error_code` độc lập với nhà cung cấp. Bốn trạng thái máy chủ (`queued`, `processing`, `succeeded`, `failed`) tương ứng với các trạng thái hàng trên UI di động: `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose`.
5. **Postcondition (creation timing):** Việc bắt đầu job **không** tạo `Pose` trước khi trích xuất thành công. Khi job `succeeded`, máy chủ tự động tạo `Pose` (`poseId` ổn định, `status: local`) và ba vai trò media (`original`, `skeleton`, `thumbnail`) một cách lũy đẳng theo `jobId`. Ứng dụng khách không cần gọi endpoint lưu riêng cho luồng này.

**Đã quan sát (2026-09-25):** Server jobs là server-authoritative theo tài khoản người dùng (`plans/260925-server-authoritative-jobs/plan.md`). Tuyến `POST /api/extract-pose` nhận ảnh kèm metadata draft theo tài khoản, trả `202`; máy chủ tự tạo Pose khi thành công; màn hình Jobs đọc trực tiếp danh sách từ máy chủ.

### Alternative flows

- **A1 — Hạn mức nhà cung cấp.** Source step: 2. Condition: key được chọn đã hết hạn mức. Behavior: chuyển sang key đang hoạt động khác nếu có. Resume at step: 2.
- **A2 — Thử lại trích xuất thất bại.** Source step: 4. Condition: job ở trạng thái `failed`. Behavior: gọi `POST /api/me/extract-jobs/:id/retry` để đưa job vào hàng đợi xử lý lại. Resume at step: 2.

### Exception flows

- **E1 — Ảnh không hợp lệ/quá lớn.** Source step: 1. Failure: xác thực từ chối ảnh tải lên. Handling: trả về định dạng bao lỗi đã được tài liệu hóa. Prohibited: gọi nhà cung cấp.
- **E2 — Nhà cung cấp không khả dụng.** Source step: 2. Failure: không nhận được kết quả thành công từ nhà cung cấp. Handling: trả về trạng thái `failed`/có thể thử lại qua API retry. Prohibited: khẳng định có ảnh dùng được.

### Postconditions

- **Thành công:** Trả về kết quả trích xuất; `Pose` (`poseId` ổn định) và ba vai trò media được máy chủ tạo tự động **sau khi** job ở trạng thái `succeeded` theo `jobId`.
- **Thất bại:** Không khẳng định có kết quả sử dụng được; cho phép thử lại qua `POST /api/me/extract-jobs/:id/retry`.

### Current evidence

- **Đã quan sát (2026-09-25):** Kế hoạch Server-authoritative Jobs ([`plans/260925-server-authoritative-jobs/plan.md`](../../../plans/260925-server-authoritative-jobs/plan.md)) quy định máy chủ sở hữu hoàn toàn trạng thái job theo tài khoản (`owner_account_id`, `pose_draft`, `pose_id`, `hidden_at`). [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts) enqueue `ExtractionJob` và trả `202`. [`extractJobsRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractJobsRoutes.ts) phục vụ poll và list theo tài khoản.
- **Ranh giới:** Add Pose trên di động chỉ nhận ảnh qua Photo Library theo FEAT-005/FEAT-002; không mở CameraScreen/FEAT-001.
- **Ranh giới thiết kế và điều kiện tiên quyết:**
  - **Không có API hủy:** Theo thiết kế (by design), không có API hủy job trích xuất phía máy chủ; giao diện người dùng không bao giờ cung cấp nút hoặc nhãn "Cancel".
  - **Định dạng lỗi:** Chuẩn hóa các mã lỗi trung lập với nhà cung cấp (`PROVIDER_QUOTA_EXCEEDED`, `PROVIDER_CREDENTIALS_EXHAUSTED`, `PROVIDER_ERROR`, `PROVIDER_AUTH_REQUIRED`, `PROVIDER_TIMEOUT`, `PROVIDER_CLI_FAILED`, `LINEART_BG_REMOVAL_FAILED`).
  - **Dọn dẹp kết quả (Retention):** Khi job thành công và tạo Pose xong, máy chủ xóa `result_image_base64` và `source_image_base64` để giải phóng bộ nhớ.

### Traceability

| Mối quan tâm | Tham chiếu chuẩn | Bằng chứng |
| --- | --- | --- |
| Thực thể | [`ExtractionJob`](../specs/data-contract.md#extractionjob), [`ApiKeyCredential`](../specs/data-contract.md#apikeycredential), [`ProviderRequestLog`](../specs/data-contract.md#providerrequestlog) | [`schema.sql`](../../../web/services/pose-extract-server/src/db/schema.sql), [`KeyStore`](../../../web/services/pose-extract-server/src/services/keyStore.ts) |
| ERD | [Đồ thị vật lý phía máy chủ](../specs/data-contract.md#server) | [`ExtractionJobStore`](../../../web/services/pose-extract-server/src/db/extractionJobStore.ts) |
| API | [Trích xuất trực tiếp](../specs/api-contract.md#extract-pose), [tuyến cũ trong quy ước](../specs/api-contract.md#conventions) | [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts), [`extractJobsRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractJobsRoutes.ts) |
| Ứng dụng khách hỗ trợ | Native iOS start/poll/list và proxy quản trị | [`PoseAPIService.swift`](../../../mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift), [`poseExtractExtractPoseProxy.js`](../../../web/admin-ui/src/lib/poseExtractExtractPoseProxy.js) |

## Requirements

- **FR-001:** Tuyến trích xuất chuẩn trả về `202 Accepted` cùng `jobId`; chỉ tạo `Pose` và media assets tự động sau khi job `succeeded`, không tạo lúc bắt đầu job.
- **FR-002:** Các tuyến trích xuất trực tiếp và tuyến cũ tiếp tục được gắn nhãn riêng cho đến khi một Decision chọn một hướng.
- **FR-003:** Tuyến trích xuất chuẩn đưa `ExtractionJob` vào hàng đợi (kèm `owner_account_id` và `pose_draft`) và trả về `202`; tiến trình xử lý nền xử lý job thông qua `PoseExtractorProvider` bằng engine được cấu hình toàn cục theo FEAT-009/DEC-001.
- **FR-004:** Các engine được hỗ trợ: `gemini_native` (REST + nhóm key) và `higgsfield_cli` (CLI khởi chạy riêng cho mỗi job, model `gpt_image_2`).
- **BR-001:** Không được báo kết quả từ nhà cung cấp là dùng được nếu kết quả `failed` hoặc chưa được xác minh.
- **FR-005:** Ứng dụng khách di động liệt kê danh sách job của tài khoản qua `GET /api/me/extract-jobs` và thăm dò `GET /api/extract-jobs/:id` (owner-checked). Khi job `failed`, hỗ trợ thử lại qua `POST /api/me/extract-jobs/:id/retry`.
- **BR-002:** Tài liệu này không sở hữu việc chọn engine; việc xử lý (processing) sử dụng cấu hình toàn cục từ FEAT-009.
- **BR-003:** Trích xuất trên di động không sở hữu luồng nghiệp vụ CameraScreen ([FEAT-001](./FEAT-001-capture-a-photo-on-mobile.md)); chỉ sử dụng lại các điểm vào nguồn ảnh.

## Acceptance

- [ ] Trích xuất trực tiếp hợp lệ trả về `202 Accepted` + `jobId`; máy chủ tự động tạo `Pose` khi `succeeded`.
- [ ] Yêu cầu không hợp lệ/quá lớn trả về lỗi đã được tài liệu hóa.
- [ ] Hết hạn mức và lỗi nhà cung cấp vẫn có thể khôi phục hoặc được nêu rõ; job `failed` có thể thử lại qua endpoint retry.
- [ ] Ứng dụng di động liệt kê và thăm dò job theo tài khoản xác thực qua API máy chủ.

## Relationships

- Tham chiếu chung: [ExtractionJob](../specs/data-contract.md#extractionjob), [ERD máy chủ](../specs/data-contract.md#server), [API trích xuất](../specs/api-contract.md#extract-pose).
- Tính năng liên quan: [FEAT-005](./FEAT-005-manage-a-pose-guide.md), [FEAT-007](./FEAT-007-operate-pose-content-from-admin-web.md), [FEAT-009](./FEAT-009-configure-extraction-provider.md) (chọn engine toàn cục; tính năng này dùng engine đã cấu hình cho processing (quá trình xử lý)).
- Chính sách: [DEC-001 Chính sách chọn nhà cung cấp trích xuất](../decisions/DEC-001-extraction-provider-selection-policy.md)
### Supporting evidence

- [`extractPoseRoutes.ts`](../../../web/services/pose-extract-server/src/routes/extractPoseRoutes.ts)
- [`geminiService.ts`](../../../web/services/pose-extract-server/src/services/geminiService.ts)
- [`extractPose.test.ts`](../../../web/services/pose-extract-server/src/extractPose.test.ts)
- [`PoseAPIService.swift`](../../../mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift)
- [`REP-002`](../reports/REP-002-feature-gap-and-release-readiness-audit.md)
- [`plans/260925-server-authoritative-jobs/plan.md`](../../../plans/260925-server-authoritative-jobs/plan.md)
