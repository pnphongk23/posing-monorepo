---
screen_id: SCR-005-01
screen_name: Jobs
related_feature: FEAT-005
compose: Native iOS `mobile/iosApp/iosApp/Features/Poses/` — Jobs screen chưa tồn tại (Next-plan prerequisite)
status: draft
template_version: 2
canonical: true
---

# SCR-005-01 — Jobs

> **Canonical screen template (v2)** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Main surface là danh sách Jobs; sub-surfaces `DLG` mô tả confirmation remove trong cùng file.
>
> **Evidence boundary:** Harness Features (`FEAT-005`, `FEAT-004`) và `docs/harness/specs/api-contract.md` / `data-contract.md` là contract hành vi và dữ liệu. Native iOS là implementation evidence. Prototype `docs/prototype/screens/jobs.html` và `docs/prototype/scripts/pose-jobs-demo.js` là visual/state exploration (**Observed**), không tự nâng thành production behavior.

<a id="scr-005-01-jobs"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | `SCR-005-01` |
| Screen name | Jobs |
| Related feature | FEAT-005 (primary, approved), FEAT-004 (async extraction contract, approved) |
| Compose / Voyager | Native iOS `mobile/iosApp/iosApp/Features/Poses/`; Jobs screen **chưa tồn tại** trong native code — **Next-plan prerequisite** |
| Stable anchor | `scr-005-01-jobs` |
| Template version | `2` |

## 2. Purpose

Cho phép người dùng theo dõi tiến độ các tác vụ trích xuất pose và tạo Pose bất đồng bộ từ máy chủ cho tài khoản hiện tại. Màn hình đọc trực tiếp danh sách jobs từ máy chủ (`GET /api/me/extract-jobs`), cung cấp giao diện hiển thị trạng thái trung thực, cho phép tiếp tục sử dụng ứng dụng mà không cần chờ ở màn hình Add Pose, hỗ trợ thử lại các tác vụ lỗi, điều hướng đến Pose sau khi đã sẵn sàng (`Ready`), và ẩn các tác vụ đã hoàn tất. **Normative:** [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow), [FEAT-004 Main flow](../../../../features/FEAT-004-extract-reusable-pose-images.md#main-flow).

## 3. Scope and ownership

- **Trong scope:**
  - Entry từ `Poses` ([SCR-003-01](../scr-003-01-community-browse.md)): nút `Jobs` trên header bên cạnh `Add pose` kèm count badge số job active (`queued`, `processing`); ẩn badge khi count = 0.
  - Entry từ `Add Pose` ([SCR-004-01](./scr-004-01-add-pose.md)): nút `Jobs` trên header và nút `View jobs` trên processing sub-surface.
  - Hai tab: `Processing` (các job `queued`, `processing`) và `Finish` (các job `Ready` hoặc `Failed`), sắp xếp mới nhất trước. Tab `Finish` có popup filter `All results` / `Success` (`Ready`) / `Fail` (`Failed`).
  - Hiển thị từng dòng (row): thumbnail ảnh nguồn, tên pose, description nếu có, một trong bốn status label `Queued`, `Processing`, `Ready`, `Failed`, và nút hành động trailing khi áp dụng. Không hiển thị tên file ảnh thay cho description; chỉ `Failed` có thông điệp lỗi chi tiết.
  - Không hiển thị badge tổng hợp số lượng job trên màn hình Jobs.
  - Ma trận trạng thái → nhãn hiển thị → action:
    - `queued` → `Queued` → không có action.
    - `processing` → `Processing` → không có action.
    - `failed` → `Failed` + thông điệp lỗi → `Retry` (gọi `POST /api/me/extract-jobs/:id/retry`).
    - `succeeded` (`pose_id` đã được server tạo) → `Ready` → `View pose` (điều hướng sang [SCR-003-03 Pose Detail](../scr-003-03-pose-detail.md) đọc pose cá nhân qua `GET /api/guides/:id` hoặc `PoseRepository`).
  - Swipe-to-remove: hỗ trợ trên các dòng đã kết thúc (`Failed` hoặc `Ready`), kích hoạt confirmation sheet và gọi `DELETE /api/me/extract-jobs/:id` (đặt `hidden_at` trên server). Việc ẩn dòng `Ready` không bao giờ xoá bản ghi `Pose` đã tạo.
  - Trạng thái Empty: hiển thị tiêu đề "No jobs yet", nội dung hướng dẫn và nút CTA `Add pose` mở [SCR-004-01](./scr-004-01-add-pose.md).
  - Trạng thái Offline: banner inline "You're offline — statuses update when you're back online."; danh sách trống khi offline; các hành động retry bị vô hiệu hoá khi offline.
  - Đăng xuất: Jobs thuộc về tài khoản trên server. Đăng xuất không xoá bất kỳ dữ liệu nào trên máy chủ và không hiển thị cảnh báo jobs. Đăng nhập lại trên bất kỳ thiết bị nào đều thấy cùng danh sách jobs.
- **Ownership:** FEAT-005 sở hữu vòng đời pose guide, metadata và quản trị Jobs theo tài khoản; FEAT-004 sở hữu trích xuất bất đồng bộ và polling backend.
- **Ngoài scope:**
  - Không có API cancel trên server; UI không bao giờ cung cấp nút Cancel server job.
  - Không chia sẻ hoặc hiển thị job giữa các tài khoản khác nhau.
  - Không tự động retry khi gặp lỗi mạng hoặc lỗi trích xuất.
  - Không có bộ nhớ đệm offline (offline cache) cho danh sách jobs.

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Ghi chú |
| --- | --- | --- | --- |
| FEAT-005 | approved (revised 2026-09-25) | **Normative** Server-authoritative Jobs lifecycle theo `plans/260925-server-authoritative-jobs/plan.md`; **Observed** prototype | Jobs screen là màn hình chuyên biệt (FR-005) |
| FEAT-004 | approved | **Normative** async extract polling & error contract; **Observed** prototype | Server endpoints `GET /api/me/extract-jobs`, `GET /api/extract-jobs/:id` |

## 4. Data contract and evidence

**Server-authoritative Job model — Normative:** Trạng thái job hoàn toàn do máy chủ quản trị theo `Account` (`ownerAccountId`):
- `id`: UUID của `ExtractionJob`.
- `ownerAccountId`: UUID của `Account` sở hữu.
- `poseDraft`: JSONB lưu metadata (`name`, `tags`, `description`).
- `poseId`: UUID của `Pose` được máy chủ tự động tạo khi trích xuất thành công (`succeeded`).
- `status`: enum gồm `queued`, `processing`, `succeeded`, `failed`.
- `hiddenAt`: timestamp khi người dùng ẩn dòng job khỏi danh sách.
- `errorCode`, `errorMessage`: mã lỗi và copy thân thiện khi thất bại.
- `createdAt`, `updatedAt`: mốc thời gian sắp xếp.

**API contract liên quan — Normative:**
1. Danh sách Jobs: `GET /api/me/extract-jobs?state=active|finished&cursor=` (`listMyExtractJobs`) trả về danh sách jobs của tài khoản hiện tại.
2. Thăm dò từng Job: `GET /api/extract-jobs/:id` ([API-EXTRACT-POSE-02](../../apis.md#api-extract-pose-02), `getExtractJob`) trả về trạng thái job (`queued`, `processing`, `succeeded`, `failed`) có kiểm tra quyền sở hữu.
3. Thử lại Job: `POST /api/me/extract-jobs/:id/retry` (`retryExtractJob`) đưa job `failed` vào hàng đợi xử lý lại.
4. Ẩn dòng Job: `DELETE /api/me/extract-jobs/:id` (`hideExtractJob`) đánh dấu `hidden_at` trên máy chủ, không xoá `Pose`.

**Evidence labels:**

| Label | Ý nghĩa |
| --- | --- |
| **Normative** | Contract hành vi/dữ liệu/API từ harness feature + `docs/harness/specs` — không suy từ code |
| **Observed** | Ghi nhận implementation/prototype hiện tại; không thay source of truth |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E |

## 5. Screen items (main surface)

<a id="scr-005-01-jobs-main"></a>

**Hierarchy:** Screen container → standard app-bar (square Back + title `Jobs`) → offline banner (khi offline) → intro → tab `Processing` / tab `Finish` → vùng danh sách có đệm trên để tách khỏi tab bar → popup filter dạng select gọn, đặt cạnh nhãn `Filter` khi mở Finish → danh sách job → Empty state view (khi không có job nào). Không có badge tổng hợp.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-005-01-HDR-001 | Back về `Poses` | Square icon button | Req | Dùng `nb-nav-bar` + `nb-btn--square`, quay về [SCR-003-01 Poses](../scr-003-01-community-browse.md) hoặc màn hình gọi trước đó — **Normative / Observed** ([prototype jobs.html](../../../../../prototype/screens/jobs.html)) |
| 2 | SCR-005-01-HDR-002 | Tiêu đề `Jobs` | Text | Req | Tiêu đề màn hình chuẩn; khớp prototype `jobs.html` — **Normative / Observed** |
| 3 | SCR-005-01-BNR-001 | Inline Offline Banner | Banner / Status notice | Opt | Hiển thị khi mất kết nối mạng: "You're offline — statuses update when you're back online."; danh sách trống và disable retry — **Normative** |
| 4 | SCR-005-01-TAB-001 | Hai tab Jobs | Tab list | Req | `Processing` hiển thị job `Queued` và `Processing`; `Finish` hiển thị job `Ready` và `Failed`. Mặc định mở `Processing`; không có badge tổng hợp — **Normative / Observed** |
| 5 | SCR-005-01-FILTER-001 | Filter kết quả | Popup menu / Select | Req | Chỉ hiện trong tab `Finish`; select gọn đặt cạnh nhãn `Filter`; chọn `All results`, `Success` (`Ready`) hoặc `Fail` (`Failed`) — **Normative / Observed** |
| 6 | SCR-005-01-ROW-001 | Thumbnail ảnh nguồn | Image thumbnail | Req | Hiển thị ảnh nguồn thu nhỏ của pose để người dùng dễ nhận diện — **Normative / Observed** |
| 7 | SCR-005-01-ROW-002 | Tên Pose & thông tin phụ | Text / Subtext | Req | Tên pose (`name`) và `description` tùy chọn từ draft metadata; ẩn subtext khi description rỗng. Không hiện tên file ảnh. Chỉ `Failed` mới có thông điệp lỗi — **Normative / Observed** |
| 8 | SCR-005-01-ROW-003 | Badge trạng thái | Status badge | Req | Hiển thị các nhãn: `Queued`, `Processing`, `Failed`, `Ready` — **Normative / Observed** |
| 9 | SCR-005-01-ROW-004 | Nút hành động theo dòng | Trailing button | Opt | `Retry` (`Failed`), `View pose` (`Ready`). Target tối thiểu 44pt — **Normative / Observed** |
| 10 | SCR-005-01-ROW-005 | Thao tác Swipe-to-remove | Swipe gesture action | Opt | Hỗ trợ trên dòng `Failed` và `Ready`; kích hoạt sheet xác nhận [SCR-005-01-DLG-001](#scr-005-01-jobs-dlg-remove) và gọi `DELETE /api/me/extract-jobs/:id` — **Normative** |
| 11 | SCR-005-01-ST-001 | Trạng thái Empty | Empty state view | Req | Hiển thị khi danh sách trống: "No jobs yet" + nút CTA `Add pose` mở [SCR-004-01](./scr-004-01-add-pose.md) — **Normative / Observed** ([prototype jobs.html](../../../../../prototype/screens/jobs.html)) |

## 6. Screen flow and feature links

**Main flow — Normative:**
1. Người dùng mở `Jobs` từ header `Poses` ([SCR-003-01](../scr-003-01-community-browse.md)) hoặc từ `Add Pose` ([SCR-004-01](./scr-004-01-add-pose.md)).
2. Client tải danh sách Jobs từ máy chủ qua `GET /api/me/extract-jobs` (`listMyExtractJobs`); tab `Processing` hiển thị job đang xử lý (`Queued`, `Processing`), tab `Finish` gộp `Ready` và `Failed`. Filter `Success` / `Fail` áp dụng trên tab `Finish`.
3. Với các job đang active, client thăm dò `GET /api/extract-jobs/:id` (`getExtractJob`) trong khi màn hình Jobs đang mở.
4. Khi trích xuất thành công (`succeeded`), máy chủ tự động tạo `Pose` và ba media assets, gán `pose_id` cho job. UI hiển thị `Ready` và nút `View pose` trong tab `Finish`/filter `Success`.
5. Người dùng bấm `View pose` để chuyển sang màn hình [SCR-003-03 Pose Detail](../scr-003-03-pose-detail.md) hiển thị pose vừa tạo (đọc pose cá nhân qua `GET /api/guides/:id` hoặc `PoseRepository`).

**Alternative & Exception flows — Normative:**
- **A1 — Manual Retry trích xuất thất bại:** Khi job có nhãn `Failed`, người dùng bấm `Retry`. Client gọi `POST /api/me/extract-jobs/:id/retry` (`retryExtractJob`); máy chủ đưa job vào lại hàng đợi, chuyển trạng thái về `Queued`/`Processing` trong tab `Processing`.
- **A2 — Swipe-to-remove (Ẩn dòng hoàn tất):** Người dùng vuốt dòng `Failed` hoặc `Ready` trong tab `Finish`, rồi chọn Remove. Sheet xác nhận hiển thị; khi xác nhận, client gọi `DELETE /api/me/extract-jobs/:id` (`hideExtractJob`) để máy chủ đánh dấu `hidden_at`. Pose đã tạo trong thư viện không bị ảnh hưởng.
- **E1 — Mất kết nối mạng (Offline):** Banner offline hiển thị, danh sách jobs trống, các tác vụ poll tạm dừng và tự phục hồi khi có mạng trở lại; các nút Retry bị disable trong thời gian offline.

| Trạng thái máy chủ | Tab / filter | Nhãn hiển thị | Chi tiết trạng thái | Action / hành vi |
| --- | --- | --- | --- | --- |
| `queued` | `Processing` | `Queued` | Ẩn; description tùy chọn vẫn có thể hiển thị | Đang chờ xử lý trong hàng đợi — **Normative** |
| `processing` | `Processing` | `Processing` | Ẩn; description tùy chọn vẫn có thể hiển thị | Tiến trình AI đang xử lý trích xuất — **Normative** |
| `failed` | `Finish` / `Fail` | `Failed` | Hiện thông điệp lỗi | `Retry`; gọi `POST /api/me/extract-jobs/:id/retry` (`retryExtractJob`) — **Normative** |
| `succeeded` (`pose_id` set) | `Finish` / `Success` | `Ready` | Ẩn | `View pose`; mở [SCR-003-03](../scr-003-03-pose-detail.md) qua `GET /api/guides/:id` hoặc `PoseRepository` — **Normative** |

**Feature flow links:**
- FEAT-005 Main flow: [[FEAT-005-manage-a-pose-guide#main-flow|FEAT-005 Main flow]] · [FEAT-005 Main flow](../../../../features/FEAT-005-manage-a-pose-guide.md#main-flow)
- FEAT-005 Alternative flows: [[FEAT-005-manage-a-pose-guide#alternative-flows|FEAT-005 Alternative flows]] · [FEAT-005 Alternative flows](../../../../features/FEAT-005-manage-a-pose-guide.md#alternative-flows)
- FEAT-004 Main flow: [[FEAT-004-extract-reusable-pose-images#main-flow|FEAT-004 Main flow]] · [FEAT-004 Main flow](../../../../features/FEAT-004-extract-reusable-pose-images.md#main-flow)
- FEAT-004 Exception flows: [[FEAT-004-extract-reusable-pose-images#exception-flows|FEAT-004 Exception flows]] · [FEAT-004 Exception flows](../../../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows)

## 7. Traceability and unresolved items

| Item | API / owner | Model / evidence |
| --- | --- | --- |
| SCR-005-01-HDR-001 / HDR-002 | Không có API; owner: FEAT-005 | Navigation bar; quay về [SCR-003-01](../scr-003-01-community-browse.md) |
| SCR-005-01-BNR-001 | Không có API | Trạng thái kết nối mạng client — **Normative** |
| SCR-005-01-TAB-001 / FILTER-001 | `GET /api/me/extract-jobs` (`listMyExtractJobs`); owner: FEAT-005 | Hai tab và filter `Success`/`Fail` — **Normative** |
| SCR-005-01-ROW-001 … ROW-003 | `GET /api/me/extract-jobs` (`listMyExtractJobs`) + `GET /api/extract-jobs/:id` (`getExtractJob`) | `ExtractionJob` — **Normative** |
| SCR-005-01-ROW-004 (Retry) | `POST /api/me/extract-jobs/:id/retry` (`retryExtractJob`) | Đưa job vào hàng đợi xử lý lại — **Normative** |
| SCR-005-01-ROW-004 (View pose) | `GET /api/guides/:id` (`getGuide`) / `PoseRepository` | Mở `Pose` (local/private) trên [SCR-003-03](../scr-003-03-pose-detail.md) — **Normative** |
| SCR-005-01-ROW-005 | `DELETE /api/me/extract-jobs/:id` (`hideExtractJob`) | Đánh dấu `hidden_at` trên server — **Normative** |
| SCR-005-01-ST-001 | Không có API | Empty state; CTA mở [SCR-004-01](./scr-004-01-add-pose.md) — **Observed** |
| SCR-005-01-DLG-001 | `DELETE /api/me/extract-jobs/:id` (`hideExtractJob`) | Sheet xác nhận ẩn dòng hoàn tất — **Normative** |

HTTP contract: [../apis.md](../../apis.md) — xem API-EXTRACT-POSE-01/02 và `listMyExtractJobs`, `retryExtractJob`, `hideExtractJob`. Model: [../models.md](../../models.md). Tổng flow: [./README.md](../README.md#overall-screen-flow).

**Unresolved / Agreed next-plan prerequisites:**
1. **Native iOS screen implementation:** File `mobile/iosApp/iosApp/Features/Poses/JobsScreen.swift` (hoặc tương đương) được ghi nhận là **Next-plan prerequisite**.
2. **Server result retention:** Khi job thành công và tạo Pose xong, máy chủ xóa dữ liệu base64 trong store.

## 8. Dialogs and Sheets

### Dialog — Remove Confirmation Sheet

<a id="scr-005-01-jobs-dlg-remove"></a>

Sheet hiển thị khi người dùng swipe-to-remove một dòng `Failed` hoặc `Ready` trong tab `Finish`.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SCR-005-01-DLG-001 | Remove confirmation sheet | Modal confirmation sheet | Req | Hiển thị tiêu đề "Remove job?", giải thích việc ẩn dòng job khỏi danh sách; nếu job đã `Ready`, ghi rõ không xoá Pose đã tạo trong thư viện. Nút Confirm Remove (gọi `DELETE /api/me/extract-jobs/:id`) và Cancel — **Normative** |

## 9. Rationale

| Quyết định | Lý do |
| --- | --- |
| Jobs là screen file riêng `SCR-005-01` | FEAT-005 FR-005 định nghĩa Jobs là một product surface chuyên biệt, có vòng đời và tương tác riêng biệt với Add Pose form |
| Máy chủ quản lý Jobs theo tài khoản (Server-authoritative) | Jobs thuộc về tài khoản người dùng, đồng bộ trên mọi thiết bị khi đăng nhập; đăng xuất không làm mất dữ liệu; loại bỏ hoàn toàn các lỗi mất đồng bộ cục bộ |
| Bốn trạng thái hiển thị chuẩn xác (`Queued`, `Processing`, `Failed`, `Ready`) | Phản ánh chính xác tiến trình xử lý máy chủ; `Ready` có nút xem Pose, `Failed` có nút thử lại |
| Chia thành hai tab `Processing` và `Finish`, lọc kết quả trong Finish | Giúp người dùng tách các job đang xử lý khỏi job đã sẵn sàng hoặc lỗi; filter Success/Fail chỉ tác động lên tab Finish |
| Không cung cấp nút Cancel server-side | Server không có API huỷ tác vụ đang chạy; UI trung thực không tạo nút Cancel giả tạo gây hiểu lầm |
| Swipe-to-remove gọi `DELETE` ẩn dòng trên máy chủ | Cho phép dọn dẹp danh sách gọn gàng mà không bao giờ xoá `Pose` đã tạo trong thư viện |
