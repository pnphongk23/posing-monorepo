---
screen_id: SCR-004-01
screen_name: Add Pose
related_feature: FEAT-004
compose: Native iOS `mobile/iosApp/iosApp/Features/Poses/` — Add Pose screen chưa tồn tại (Next-plan prerequisite)
status: draft
template_version: 2
canonical: true
---

# SCR-004-01 — Add Pose

> **Canonical screen template (v2)** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Main surface là form Add Pose; processing surface là sub-surface `DTL` trong cùng file.
>
> **Evidence boundary:** Harness Features (`FEAT-004`, `FEAT-005`) và `docs/harness/specs/api-contract.md` / `data-contract.md` là contract hành vi và dữ liệu. Native iOS là implementation evidence. Prototype `docs/prototype/screens/add-pose.html` là visual/state exploration (**Observed**), không tự nâng thành production behavior.

<a id="scr-004-01-add-pose"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | `SCR-004-01` |
| Screen name | Add Pose |
| Related feature | FEAT-004 (primary, approved), FEAT-005 (primary, approved 2026-09-24); FEAT-002 (Photo Library intake, approved) |
| Compose / Voyager | Native iOS `mobile/iosApp/iosApp/Features/Poses/`; Poses hiện do `PosesFeature.swift` sở hữu; màn hình Add Pose **chưa tồn tại** — **Next-plan prerequisite** |
| Stable anchor | `scr-004-01-add-pose` |
| Template version | `2` |

## 2. Purpose

Cho phép người dùng di động bắt đầu từ `Poses`, chọn ảnh từ Photo Library, nhập metadata chuẩn (`name` và `tags` bắt buộc, `description` tùy chọn), gửi yêu cầu trích xuất bất đồng bộ kèm draft metadata tới máy chủ, theo dõi kết quả hoặc điều hướng sang màn hình Jobs ([SCR-005-01](./scr-005-01-jobs.md)), và máy chủ tự động tạo `Pose` cá nhân sau khi job trích xuất thành công. Quy trình trích xuất thuộc FEAT-004; metadata, owner và quản lý `Pose` thuộc FEAT-005. Màn hình chỉ dùng lại Photo Library intake thuộc FEAT-002; không mở luồng camera. **Normative:** [FEAT-004 Main flow](../../../../features/FEAT-004-extract-reusable-pose-images.md#main-flow), [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow).

## 3. Scope and ownership

- **Trong scope:** entry Add Pose từ `Poses`; CTA chọn hoặc đổi ảnh qua Photo Library và preview ảnh nguồn; thu thập `name`, `tags`, `description`; kiểm tra phía client; gửi request `POST /api/extract-pose` (kèm ảnh và draft metadata) và poll `ExtractionJob`; hiển thị processing surface chuyên biệt; cung cấp nút `View jobs` để chuyển sang [SCR-005-01 Jobs](./scr-005-01-jobs.md) và nút `Done` để quay về `Poses`; hiển thị trạng thái `Queued`, `Processing`, `Failed → Retry`, và `Ready → View pose`.
- **Ownership:** FEAT-004 quy định enqueue, polling và kết quả extraction; FEAT-005 quy định metadata, owner và vòng đời `Pose`; FEAT-002 sở hữu Photo Library intake. Màn hình này chỉ nhận lại ảnh và không mở camera. **Normative:** [FEAT-004 §Requirements](../../../../features/FEAT-004-extract-reusable-pose-images.md#requirements), [FEAT-005 §Requirements](../../../../features/FEAT-005-manage-a-pose-guide.md#requirements).
- **Ngoài scope:** chọn provider (FEAT-009/[DEC-001](../../../../decisions/DEC-001-extraction-provider-selection-policy.md)); publish (FEAT-006); server-side cancel API (không có cancel operation; UI không có nút cancel server).
- **Entry:** mở Add Pose từ nút `Add pose` trên header `Poses` ([SCR-003-01](../scr-003-01-community-browse.md)); header có nút `Jobs` kèm badge số active jobs (`queued`, `processing`). **Normative / Observed:** [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow), [prototype poses-list.html](../../../../../prototype/screens/poses-list.html).

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Ghi chú |
| --- | --- | --- | --- |
| FEAT-004 | approved | **Normative** async extract contract; **Observed** prototype form/processing | Provider selection thuộc FEAT-009/DEC-001 |
| FEAT-005 | approved (revised 2026-09-25) | **Normative** canonical fields + server-authoritative jobs; **Observed** prototype | Photo Library là nguồn ảnh duy nhất; bỏ `bodyParts`/`difficulty`; Jobs server-authoritative theo tài khoản |
| FEAT-002 | approved | **Observed** prototype Photo Library CTA | Photo Library intake do SCR-002-01 sở hữu |

## 4. Data contract and evidence

**Input và validation — Normative:** ảnh nguồn chỉ được chọn từ Photo Library qua FEAT-002; `name` và `tags` bắt buộc; `description` tùy chọn; `bodyParts`/`difficulty` **không còn được thu thập** (quyết định sản phẩm 2026-09-24). `ownerAccountId` bắt buộc trên `Pose` và lấy từ session đăng nhập khi gửi `POST /api/extract-pose`. Xác thực trường bắt buộc và ảnh trước khi submit. **Normative:** [FEAT-005 Main flow / FR-003](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow), [Data Contract §Pose](../../../../specs/data-contract.md#pose).

**API/data — Normative:** `POST /api/extract-pose` nhận `multipart/form-data` gồm `image` (JPEG/PNG, tối đa 10 MB) kèm `name`, `tags` và `description` tùy chọn (lưu vào `pose_draft` trên máy chủ), trả `202 Accepted` + `jobId` + `status: queued` + `pollUrl`. Client poll `GET /api/extract-jobs/:jobId` (owner-checked). Khi job `succeeded`, máy chủ tự động tạo `Pose` (`status=local`) và ba `MediaAsset` (`original`, `skeleton`, `thumbnail`) trong một transaction lũy đẳng theo `jobId`. Client không gọi endpoint lưu riêng. **Normative:** [API Contract §Extract Pose](../../../../specs/api-contract.md#extract-pose), [Data Contract §Pose](../../../../specs/data-contract.md#pose), [§MediaAsset](../../../../specs/data-contract.md#mediaasset), [`plans/260925-server-authoritative-jobs/plan.md`](../../../../plans/260925-server-authoritative-jobs/plan.md).

**Entity map — Normative:** `ExtractionJob` được tạo khi enqueue; `Pose` được tạo tự động khi `succeeded` cùng đúng ba `MediaAsset`. Enum liên quan: `ExtractionJobStatus` (`queued`, `processing`, `succeeded`, `failed`), `PoseStatus` (`local`, `published`), `MediaAssetRole` (`original`, `skeleton`, `thumbnail`), `MediaAssetReadiness` (`pending`, `ready`, `failed`). **Normative:** [Data Contract §Enums](../../../../specs/data-contract.md#enums), [../models.md](../../models.md).

**Evidence labels:**

| Label | Ý nghĩa |
| --- | --- |
| **Normative** | Contract hành vi/dữ liệu/API từ harness feature + `docs/harness/specs` — không suy từ code |
| **Observed** | Ghi nhận implementation/prototype hiện tại; không thay source of truth |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E |
| **Non-evidence** | Placeholder template hoặc sub-surface mẫu chưa có evidence — **không** dùng làm acceptance |

## 5. Screen items (main surface)

<a id="scr-004-01-add-pose-main"></a>

**Hierarchy:** screen container → standard app-bar (square Back + title `Add pose` + right button `Jobs`) → Photo Library CTA → metadata form → submit action. Processing thay thế toàn bộ form (§8).

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SCR-004-01-HDR-001 | Back về `Poses` | Standard square icon button | Req | Dùng `nb-nav-bar` + `nb-btn--square`, quay về [SCR-003-01 Poses](../scr-003-01-community-browse.md) — **Normative / Observed** ([prototype add-pose.html](../../../../../prototype/screens/add-pose.html)) |
| 2 | SCR-004-01-HDR-002 | Tiêu đề `Add pose` | Text | Req | Tiêu đề màn hình; khớp prototype `add-pose.html` — **Normative / Observed** |
| 3 | SCR-004-01-HDR-003 | Nút mở `Jobs` | Text button / link | Opt | Nút `Jobs` ở góc phải header điều hướng sang [SCR-005-01 Jobs](./scr-005-01-jobs.md) — **Normative / Observed** ([prototype add-pose.html](../../../../../prototype/screens/add-pose.html)) |
| 4 | SCR-004-01-IMG-001 | `Start with a photo` / `Change photo` — Photo Library | Primary Photo Library CTA | Req | Toàn vùng CTA mở Photo Library qua FEAT-002; khi đã chọn ảnh, CTA cho phép đổi ảnh từ cùng thư viện — **Normative / Observed** ([FEAT-005 FR-003](../../../../features/FEAT-005-manage-a-pose-guide.md#requirements)) |
| 5 | SCR-004-01-IMG-002 | Preview ảnh nguồn | Image preview | Req | Cho người dùng xác nhận ảnh đã chọn — **Observed** ([prototype](../../../../../prototype/screens/add-pose.html)) |
| 6 | SCR-004-01-MET-001 | `name` | Text field | Req | Không rỗng sau trim, độ dài tối đa 60 ký tự — **Normative** ([Data Contract §Pose](../../../../specs/data-contract.md#pose)) |
| 7 | SCR-004-01-MET-002 | `tags` | Text / tag input | Req | Ít nhất một tag; prototype nhập phân tách bằng dấu phẩy là **Observed**, không phải chuẩn serialization — **Normative / Observed** |
| 8 | SCR-004-01-MET-003 | `description` | Text area | Opt | Gửi nếu có giá trị; không chặn submit nếu trống — **Normative** |
| 9 | SCR-004-01-ACT-001 | Tạo Pose (submit) | Primary button | Req | Validate client trước; gửi ảnh và metadata draft bằng `POST /api/extract-pose`; nhận `202 Accepted` và chuyển sang processing surface (§8) — **Normative** ([FEAT-004 Main flow](../../../../features/FEAT-004-extract-reusable-pose-images.md#main-flow)) |
| 10 | SCR-004-01-FBK-001 | Lỗi validation theo trường | Inline error | Req | Gắn lỗi với trường tương ứng; focus trường lỗi đầu tiên; không gọi API — **Normative / Observed** |
| 11 | SCR-004-01-ST-001 | Trạng thái initial/empty | Form rỗng | Req | Form trống chờ chọn ảnh từ Photo Library và metadata; submit chạy validation — **Observed** |
| 12 | SCR-004-01-ST-002 | Trạng thái image selected | Preview + form | Req | Hiện preview và CTA đổi ảnh bằng Photo Library; người dùng bổ sung trường bắt buộc — **Observed** |
| 13 | SCR-004-01-ST-003 | Trạng thái offline | Status + Retry | Req | Giữ metadata và cho retry khi có kết nối lại — **Normative / Observed** |

## 6. Screen flow and feature links

**Main flow — Normative:**
1. Người dùng mở `Add pose` từ [SCR-003-01 Poses](../scr-003-01-community-browse.md).
2. Chọn ảnh từ Photo Library (FEAT-002) qua CTA `Start with a photo`.
3. Nhập `name` và `tags` (bắt buộc); `description` (tùy chọn).
4. Client validation thành công → gửi `POST /api/extract-pose` multipart gồm `image` và draft metadata.
5. Nhận `202 Accepted` + `jobId` + `pollUrl` → chuyển sang processing surface (§8).
6. Người dùng có thể chờ trên processing surface hoặc bấm `View jobs` để sang [SCR-005-01 Jobs](./scr-005-01-jobs.md) hoặc bấm `Done` để quay về `Poses`. Việc rời khỏi màn hình **không bao giờ** huỷ job trích xuất trên server.
7. Client poll `GET /api/extract-jobs/:jobId` tới terminal status:
   - Khi `succeeded`: máy chủ tự động tạo `Pose` (`status=local`) và ba `MediaAsset` (`original`, `skeleton`, `thumbnail`), gán `pose_id` cho job.
   - Trạng thái trên màn hình chuyển thành `Ready` và hiển thị xác nhận thành công cùng nút `View pose` hoặc `Done`.

**Alternative và exception flows:**

- **A1 — Quota rotation:** Key hết quota được server đánh dấu `exhausted` và xoay sang key `active` nếu có; nếu không còn key, API trả `503 ALL_KEYS_EXHAUSTED` hoặc job fail với `PROVIDER_CREDENTIALS_EXHAUSTED`. **Normative:** [FEAT-004 Alternative flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#alternative-flows), [API Contract BR-EXTRACT-001/002](../../../../specs/api-contract.md#extract-pose).
- **A2 — Manual retry trích xuất:** Khi job `failed`, processing surface hiển thị thông điệp lỗi và nút `Retry`. Người dùng bấm `Retry` để gọi `POST /api/me/extract-jobs/:id/retry`; không tự động retry. **Normative:** [FEAT-005 Alternative flows](../../../../features/FEAT-005-manage-a-pose-guide.md#alternative-flows).
- **A3 — Điều hướng sang Jobs screen:** Tại bất kỳ thời điểm nào sau khi submit, người dùng có thể bấm `View jobs` để chuyển sang [SCR-005-01](./scr-005-01-jobs.md) để theo dõi tiến độ tổng thể.
- **E1 — Invalid / oversized image:** Chặn gọi provider; API trả `INVALID_IMAGE` (`400`) hoặc `IMAGE_TOO_LARGE` (`413`), không enqueue job. **Normative:** [FEAT-004 Exception flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows).
- **E2 — Provider unavailable:** Job `failed` thì hiển thị lỗi provider-neutral qua copy dễ hiểu và nút `Retry`. **Normative:** [FEAT-004 Exception flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows), [FEAT-005 E3](../../../../features/FEAT-005-manage-a-pose-guide.md#exception-flows).
- **No Cancel Label:** Không có server-side cancel API. Giao diện người dùng **không bao giờ** cung cấp nút có nhãn `Cancel` để tránh gây hiểu lầm rằng job server đã dừng. Người dùng có thể rời surface bằng `View jobs` hoặc `Done`.

| Trạng thái | Hành vi / chuyển tiếp | Đối chiếu evidence |
| --- | --- | --- |
| Initial / empty | Form trống; submit chạy validation. | **Observed** — [SCR-004-01-ST-001](#scr-004-01-add-pose-main); **Normative** [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow) |
| Image selected | Hiện preview; bổ sung trường bắt buộc. | **Observed** — SCR-004-01-ST-002, SCR-004-01-IMG-002 |
| Validation error | Field error; không gọi extraction khi thiếu ảnh/`name`/`tags`. | **Observed / Normative** — SCR-004-01-FBK-001 |
| Queued / Processing | Enqueue rồi poll; status estimated/indeterminate, không fake percentage. Nút `View jobs` và `Done`. | **Observed** — [§8 DTL](#scr-004-01-add-pose-dtl-processing); **Normative** [UI UX System](../../../../specs/ui-ux-system.md#interaction-patterns) |
| Ready (Succeeded) | Máy chủ tự động tạo `Pose`; hiển thị `Ready` cùng nút `View pose` và `Done`. | **Normative** — [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow) |
| Failed / Retry | Hiển thị nhãn `Failed`, chi tiết lỗi và CTA `Retry` (`POST /api/me/extract-jobs/:id/retry`); chỉ retry khi người dùng bấm. | **Normative** — [FEAT-005 A2/E3](../../../../features/FEAT-005-manage-a-pose-guide.md#alternative-flows) |
| Offline | Giữ form và retry khi kết nối lại; disable retry trong khi offline. | **Observed / Normative** — SCR-004-01-ST-003 |

**Feature flow links:**

- Main flow: [[FEAT-004-extract-reusable-pose-images#main-flow|FEAT-004 Main flow]] · [FEAT-004 Main flow](../../../../features/FEAT-004-extract-reusable-pose-images.md#main-flow); [[FEAT-005-manage-a-pose-guide#main-flow|FEAT-005 Main flow]] · [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow)
- Alternative A1 quota rotation: [[FEAT-004-extract-reusable-pose-images#alternative-flows|FEAT-004 Alternative flows]] · [FEAT-004 Alternative flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#alternative-flows)
- Alternative A2 manual retry: [[FEAT-005-manage-a-pose-guide#alternative-flows|FEAT-005 Alternative flows]] · [FEAT-005 Alternative flows](../../../../features/FEAT-005-manage-a-pose-guide.md#alternative-flows)
- Exception E1/E2: [[FEAT-004-extract-reusable-pose-images#exception-flows|FEAT-004 Exception flows]] · [FEAT-004 Exception flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows); [[FEAT-005-manage-a-pose-guide#exception-flows|FEAT-005 Exception flows]] · [FEAT-005 Exception flows](../../../../features/FEAT-005-manage-a-pose-guide.md#exception-flows)

**Cross-feature handoff links:**

- Photo Library intake: [[FEAT-002-manage-a-local-photo-gallery#main-flow|FEAT-002 Main flow]] · [FEAT-002 Main flow](../../../../features/FEAT-002-manage-a-local-photo-gallery.md#main-flow) — owner [SCR-002-01 Gallery](./scr-002-01-gallery.md).
- Jobs tracking: [SCR-005-01 Jobs](./scr-005-01-jobs.md) — owner FEAT-005 FR-005.

## 7. Traceability and unresolved items

| Item | API / owner | Model / evidence |
| --- | --- | --- |
| SCR-004-01-HDR-001 | Không có API; owner: FEAT-005 | Navigation bar; quay về [SCR-003-01 Poses](../scr-003-01-community-browse.md) |
| SCR-004-01-HDR-002 / HDR-003 | Không có API; owner: FEAT-005 | Tiêu đề và nút mở [SCR-005-01 Jobs](./scr-005-01-jobs.md) |
| SCR-004-01-IMG-001 / IMG-002 | Không có API (intake trước submit); Photo Library owner FEAT-002 | Ảnh nguồn; chưa có media entity tới lúc tạo `Pose` |
| SCR-004-01-MET-001 … MET-003 | `POST /api/extract-pose` (draft metadata) | `ExtractionJob.poseDraft`; `Pose` khi job succeeded |
| SCR-004-01-ACT-001 | `POST /api/extract-pose` (`extractPose`) → `GET /api/extract-jobs/:jobId` (poll) | `ExtractionJob` → `Pose` + ba `MediaAsset` — **Normative** |
| SCR-004-01-FBK-001 / ST-001 … ST-003 | Không gọi API khi validation lỗi | Client validation **Normative**; field feedback/offline **Observed** |
| SCR-004-01-DTL-001 … DTL-003 | `GET /api/extract-jobs/:jobId` (poll); navigation `View jobs` / `Done` | `ExtractionJob`; skeletal overlay — **Normative / Observed** |
| SCR-004-01-DTL-004 … DTL-006 | Máy chủ tự tạo Pose khi success; `POST /api/me/extract-jobs/:id/retry` khi manual retry | `Pose`, `MediaAsset`, `ExtractionJob` — **Normative** |

HTTP contract: [../apis.md](../../apis.md) — xem API-EXTRACT-POSE-01/02. Model: [../models.md](../../models.md). Tổng flow: [./README.md](../README.md#overall-screen-flow).

**Status of items (Closed / Next-plan prerequisites):**

1. **Màn hình Add Pose chưa tồn tại trong delivery app:** **Closed** ở mức Basic Design specification; việc hiện thực hóa mã Swift (`Features/Poses/AddPoseScreen.swift`) được ghi nhận là **Next-plan prerequisite**.
2. **Entry affordance trên `Poses`:** **Closed** — Hợp đồng dùng chung đã chốt: Header Poses có nút `Jobs` kèm active count badge bên cạnh nút `Add pose`; prototype `poses-list.html` và `add-pose.html` cung cấp bằng chứng **Observed**.
3. **Server-authoritative jobs:** **Closed** — FEAT-005 và `plans/260925-server-authoritative-jobs/plan.md` phê duyệt mô hình jobs thuộc về server theo tài khoản; không lưu trữ bảng jobs cục bộ trên thiết bị, không cảnh báo hay xóa jobs khi đăng xuất.
4. **Persistence `ownerAccountId`:** **Closed** — Session-derived ở thời điểm gửi request theo contract.
5. **Liên kết job-to-pose bền vững:** **Closed** — Máy chủ tự động tạo `Pose` và gán `pose_id` cho `ExtractionJob` trong cùng transaction khi job `succeeded`.
6. **Cancel server-side:** **Closed** — Theo thiết kế, backend không có API cancel; UI không bao giờ hiển thị nhãn `Cancel` và cho phép người dùng rời màn hình mà không huỷ job server.
7. **Bỏ client-side save endpoint:** **Closed** — Luồng Add Pose không gọi `POST /api/guides`; máy chủ tự tạo Pose từ draft metadata khi trích xuất thành công.
8. **Màn hình Jobs chuyên biệt (FEAT-005 FR-005):** **Closed** — Đã được định nghĩa đầy đủ trong tài liệu thiết kế riêng [SCR-005-01](./scr-005-01-jobs.md).
9. **KMP `source_paths` discrepancy:** **Closed** — Ghi nhận là bối cảnh lịch sử của harness; đường dẫn Swift iOS thực tế đã được xác định.
10. **FEAT-005 scope revision:** **Closed** — Product Authority đã chính thức phê duyệt FEAT-005 (nguồn ảnh duy nhất là Photo Library; `name` + `tags` bắt buộc, `description` tùy chọn; jobs server-authoritative).

## 8. Full-screen detail — Processing surface

<a id="scr-004-01-add-pose-dtl-processing"></a>

Surface này thay thế form trong lúc trích xuất pose. Prototype ẩn form và hiển thị processing surface với ảnh nguồn phủ skeletal overlay động. Màn hình processing chuyên biệt, trạng thái trung thực, và nút điều hướng rõ ràng là **Normative**. Không có nhãn Cancel trên giao diện. **Normative / Observed:** [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow), [UI UX System §Interaction patterns](../../../../specs/ui-ux-system.md#interaction-patterns), [prototype add-pose.html](../../../../../prototype/screens/add-pose.html).

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SCR-004-01-DTL-001 | Ảnh nguồn và skeletal overlay | Image / animated overlay | Req | Processing surface chuyên biệt thay thế form; ảnh nguồn cùng skeletal overlay minh hoạ tiến độ, tôn trọng prefers-reduced-motion — **Normative / Observed** ([UI UX System](../../../../specs/ui-ux-system.md#interaction-patterns)) |
| 2 | SCR-004-01-DTL-002 | Processing status | Live status / progress copy | Req | Hiển thị trạng thái máy chủ: `Queued` hoặc `Processing`. Không giả phần trăm nhân tạo — **Normative / Observed** |
| 3 | SCR-004-01-DTL-003 | `View jobs` & `Done` navigation | Primary action / Done button | Req | Nút `View jobs` chuyển sang [SCR-005-01 Jobs](./scr-005-01-jobs.md); nút `Done` hoặc back đóng surface về `Poses`; rời đi không huỷ job server; tuyệt đối không dùng nhãn `Cancel` — **Normative / Observed** |
| 4 | SCR-004-01-DTL-004 | Trạng thái thành công | Status / confirmation | Req | Chỉ hiện sau khi máy chủ trích xuất `succeeded` và tạo `Pose` thành công; hiển thị `Ready` kèm nút `View pose` hoặc `Done` — **Normative** |
| 5 | SCR-004-01-DTL-005 | Trạng thái thất bại và error copy | Error status | Req | Khi job `failed`, hiển thị nhãn `Failed` kèm copy lỗi thân thiện provider-neutral — **Normative** |
| 6 | SCR-004-01-DTL-006 | Thao tác `Retry` / Quay về `Poses` | Action buttons | Req | `Retry` gọi `POST /api/me/extract-jobs/:id/retry`; không auto-retry. Sau success, nút `Done` quay về `Poses` [SCR-003-01](../scr-003-01-community-browse.md) — **Normative / Observed** |

## 9. Rationale

| Quyết định | Lý do |
| --- | --- |
| Add Pose là screen file riêng `SCR-004-01` | FEAT-004/005 sở hữu flow riêng (intake → extract → create Pose); tách biệt khỏi browse catalogue của SCR-003-01 |
| Processing là sub-surface `DTL` trong cùng file | Processing thay thế trực tiếp form của Add Pose; gom lại giữ traceability Item ID ↔ main surface theo TEMPLATE v2 |
| Server-authoritative extraction jobs | Máy chủ sở hữu job state per account và tự tạo Pose khi thành công; loại bỏ phức tạp của việc lưu trữ jobs cục bộ trên thiết bị và client save endpoint |
| Không sử dụng nhãn `Cancel` | Backend không có cancel API; UI trung thực không tạo thao tác Cancel gây hiểu lầm mà cung cấp `View jobs` và `Done` |
| Bổ sung nút `View jobs` và liên kết sang `SCR-005-01` | Cho phép người dùng rời khỏi màn hình Add Pose để thực hiện tác vụ khác mà vẫn theo dõi được tiến trình bất đồng bộ |
| Metadata Add Pose rút gọn còn `name` + `tags` + `description` | Quyết định sản phẩm 2026-09-24: bỏ `difficulty` và `bodyParts` khỏi form tạo pose của mobile client |
| Toàn bộ mục trong §7 được giải quyết hoặc chuyển thành prerequisite | Đảm bảo tính sẵn sàng thiết kế và ranh giới rõ ràng cho kế hoạch triển khai tiếp theo (Next-plan) |
