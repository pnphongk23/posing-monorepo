# APIs — Product HTTP Contract Summary

Tóm tắt contract HTTP cho các module product trong [`docs/harness/specs/api-contract.md`](../../specs/api-contract.md) — **không** duplicate source-of-truth; chỉ summary, evidence labels, và flat links tới spec/OpenAPI/features/screens.

| Canonical source | Link |
| --- | --- |
| API catalogue | [`docs/harness/specs/api-contract.md`](../../specs/api-contract.md) |
| OpenAPI paths/schemas | [`openapi.yaml`](../../specs/api/openapi.yaml) |
| Conventions (auth, pagination, proxy) | [`api-contract.md`](../../specs/api-contract.md) |
| Module semantics | [`community`](../../specs/api-contract.md#community) · [`extract-pose`](../../specs/api-contract.md#extract-pose) · [`guides`](../../specs/api-contract.md#pose-guides) · [`publish`](../../specs/api-contract.md#publish) · [`saved`](../../specs/api-contract.md#saved) · [`admin-community`](../../specs/api-contract.md#admin-community) |
| DTO projection | [`models.md`](./models.md) |

**20 stable Normative IDs** (thứ tự cố định): API-COMMUNITY-01/02 · API-EXTRACT-POSE-01/02 · API-GUIDES-01…08 · API-PUBLISH-01/02 · API-SAVED-01…03 · API-ADMIN-COMMUNITY-01…03.

**Compatibility aliases (chỉ 2):** API-003-01 → API-COMMUNITY-01 ([`#api-003-01`](#api-003-01)); API-003-02 → API-COMMUNITY-02 ([`#api-003-02`](#api-003-02)). Không API-003-03; không catalogue API-001…API-023 (state collision).

---

## 1. Evidence labeling

| Label | Nguồn | Cách dùng trong file này |
| --- | --- | --- |
| **Normative** | Harness Feature + `docs/spec` + OpenAPI | Contract hành vi/dữ liệu/API |
| **Observed** | Code / delivery evidence | Ghi nhận implementation; không thay SoT |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E | Xem [Unresolved](#unresolved) |

---

## 2. Normative operations (20 stable IDs)

### 2.1 Community — FEAT-003

Module: [`api-contract.md §Community`](../../specs/api-contract.md#community) · Feature: [FEAT-003](../../features/FEAT-003-browse-and-search-published-poses.md)

<a id="api-community-01"></a>

#### API-COMMUNITY-01 — `listCommunityPoses`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-COMMUNITY-01 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Không |
| **Path** | `/api/community/poses` |
| **operationId** | `listCommunityPoses` |

**Request (query):** `page` (default 1), `limit` (default 20, max 100), `difficulty`, `tag`, `q` (title search trên `name` — **Normative** contract; evidence **Unresolved**, xem [Unresolved](#unresolved)).

**Response:** `200` `{ data: CommunityPose[], pagination }` · `400` · `500`.

**Business rules:** BR-COMMUNITY-001, BR-COMMUNITY-005, BR-COMMUNITY-006.

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [Main 1](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#main-flow) | Initial catalogue load |
| [Main 2](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#main-flow) | Pagination / load-more / search (`q` — **Unresolved** E2E) |
| [A1](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) | `200`, `data: []` → empty state |
| [A2](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) | Refresh (`page=1`) |
| [E1](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#exception-flows) | Transport/5xx — giữ confirmed list |

<a id="api-003-01"></a>

**Compatibility alias — API-003-01:** Legacy Basic Design ID **API-003-01** alias tới [API-COMMUNITY-01](#api-community-01). Anchor ổn định: `#api-003-01`.

---

<a id="api-community-02"></a>

#### API-COMMUNITY-02 — `getCommunityPose`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-COMMUNITY-02 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Không |
| **Path** | `/api/community/poses/:id` |
| **operationId** | `getCommunityPose` |

**Request:** Path `id` — UUID (`poseId`).

**Response:** `200` `{ data: CommunityPose }` (`downloadCount` +1 khi thành công) · `404` (không leak `local`) · `500`.

**Business rules:** BR-COMMUNITY-002, BR-COMMUNITY-004, BR-COMMUNITY-007.

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [Main 3](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#main-flow) | Detail sau published card tap |
| [E2](../../../harness/features/FEAT-003-browse-and-search-published-poses.md#exception-flows) | `404`/lỗi → explain; **return to list**; cấm stale detail |

<a id="api-003-02"></a>

**Compatibility alias — API-003-02:** Legacy Basic Design ID **API-003-02** alias tới [API-COMMUNITY-02](#api-community-02). Anchor ổn định: `#api-003-02`.

---

### 2.2 Extract Pose — FEAT-004

Module: [`api-contract.md §Extract Pose`](../../specs/api-contract.md#extract-pose) · Feature: [FEAT-004](../../features/FEAT-004-extract-reusable-pose-images.md)

<a id="api-extract-pose-01"></a>

#### API-EXTRACT-POSE-01 — `extractPose`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-EXTRACT-POSE-01 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Account session (hoặc Bearer admin) |
| **Path** | `/api/extract-pose` |
| **operationId** | `extractPose` |

**Request:** `multipart/form-data`, field `image` (JPEG/PNG, max 10 MB), kèm `name`, `tags` (bắt buộc), `description` (tùy chọn) lưu vào `pose_draft`.

**Response:** `202` `ExtractionJobAccepted` (`jobId`, `status: queued`, `meta.pollUrl`) · pre-queue: `400 INVALID_IMAGE`, `413 IMAGE_TOO_LARGE`, `429 RATE_LIMITED`, `503 ALL_KEYS_EXHAUSTED`.

**Business rules:** BR-EXTRACT-001…007; Server worker tự động tạo `Pose` và ba `MediaAsset` khi job `succeeded`.

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [Main 1–2](../../features/FEAT-004-extract-reusable-pose-images.md#main-flow) | Validate + enqueue job (`202`; lưu `pose_draft`, tạo `Pose` tự động khi `succeeded`) |
| [A1](../../features/FEAT-004-extract-reusable-pose-images.md#alternative-flows) | Key rotation khi quota |
| [E1](../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows) | Invalid/oversized image |
| [E2](../../features/FEAT-004-extract-reusable-pose-images.md#exception-flows) | Provider unavailable |

---

<a id="api-extract-pose-02"></a>

#### API-EXTRACT-POSE-02 — `getExtractJob`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-EXTRACT-POSE-02 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Account session (owner-checked, 404 cho tài khoản khác) hoặc Bearer admin |
| **Path** | `/api/extract-jobs/:jobId` |
| **operationId** | `getExtractJob` |

**Response:** `200` job status (`queued` \| `processing` \| `succeeded` \| `failed`); `result` khi succeeded (kèm `poseId` đã được server tạo); `error` khi failed · `404` nếu job không tồn tại hoặc không thuộc quyền sở hữu.

**Business rules:** BR-EXTRACT-005; job `error_code` provider-neutral (module).

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [Main 4](../../features/FEAT-004-extract-reusable-pose-images.md#main-flow) | Per-job poll theo tài khoản |
| [FEAT-005 Main 4](../../features/FEAT-005-manage-a-pose-guide.md#main-flow) | Mobile Jobs screen ([SCR-005-01](./screens/mobile/scr-005-01-jobs.md)) và Add Pose ([SCR-004-01](./screens/mobile/scr-004-01-add-pose.md)) poll endpoint này |

---

#### Account Extraction Jobs — FEAT-004 / FEAT-005

| Operation | Method & Path | Auth | Mô tả | Label |
| --- | --- | --- | --- | --- |
| `listMyExtractJobs` | `GET /api/me/extract-jobs?state=active\|finished&cursor=` | Account session | Liệt kê danh sách jobs của tài khoản hiện tại | **Normative** |
| `retryExtractJob` | `POST /api/me/extract-jobs/:id/retry` | Account session | Thử lại job trích xuất bị `failed` | **Normative** |
| `hideExtractJob` | `DELETE /api/me/extract-jobs/:id` | Account session | Ẩn dòng job hoàn tất (`hidden_at`), không xoá `Pose` | **Normative** |

---

### 2.3 Guides — FEAT-005

Module: [`api-contract.md §Pose Guides`](../../specs/api-contract.md#pose-guides) · Feature: [FEAT-005](../../features/FEAT-005-manage-a-pose-guide.md)

<a id="api-guides-01"></a>

#### API-GUIDES-01 — `listGuides`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-01 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Account session hoặc Bearer admin |
| **Path** | `/api/guides` |
| **operationId** | `listGuides` |

**Request:** `page`, `limit`.

**Response:** `200` paginated `Pose` · `401`.

---

<a id="api-guides-02"></a>

#### API-GUIDES-02 — `createGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-02 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Account session (owner = session) hoặc Bearer admin (+ `ownerAccountId`) |
| **Path** | `/api/guides` |
| **operationId** | `createGuide` |

**Request:** JSON — `jobId` (succeeded), `name` (bắt buộc); optional `tags`, `description`, `difficulty`, `bodyParts`; admin Bearer bắt buộc `ownerAccountId`.

**Ghi chú luồng di động Add Pose:** Với luồng Add Pose di động (FEAT-005), máy chủ tự động tạo `Pose` và media assets khi job `succeeded` từ `pose_draft`. Client di động **không** cần gọi endpoint này để lưu pose sau trích xuất.

**Response:** `201` `{ data: { pose: Pose } }` · `400 BAD_REQUEST` · `401` · `404` · `409 JOB_ALREADY_CONSUMED` · `500`.

**Business rules:** BR-GUIDE-001, BR-GUIDE-002, BR-GUIDE-004.

---

<a id="api-guides-03"></a>

#### API-GUIDES-03 — `getGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-03 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id` |
| **operationId** | `getGuide` |

**Response:** `200` `{ data: Pose }` · `401` · `403` · `404`.

---

<a id="api-guides-04"></a>

#### API-GUIDES-04 — `updateGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-04 |
| **Label** | **Normative** |
| **Method** | `PATCH` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id` |
| **operationId** | `updateGuide` |

**Request:** Partial metadata (`name`, `description`, `tags`, `difficulty`, `bodyParts`).

**Response:** `200` `{ data: Pose }` · `401` · `403` · `404`.

---

<a id="api-guides-05"></a>

#### API-GUIDES-05 — `retryGuideJob`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-05 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id/retry` |
| **operationId** | `retryGuideJob` |

**Response:** `202` `ExtractionJobAccepted` · `401` · `403` · `404`.

**Feature-flow mapping:** [A1](../../../harness/features/FEAT-005-manage-a-pose-guide.md#alternative-flows), [A2](../../../harness/features/FEAT-005-manage-a-pose-guide.md#alternative-flows) (manual retry mobile).

---

<a id="api-guides-06"></a>

#### API-GUIDES-06 — `reExtractGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-06 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id/re-extract` |
| **operationId** | `reExtractGuide` |

**Response:** `202` `ExtractionJobAccepted` · `401` · `403` · `404`.

---

<a id="api-guides-07"></a>

#### API-GUIDES-07 — `revertGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-07 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id/revert` |
| **operationId** | `revertGuide` |

**Response:** `200` `{ data: Pose }` · `409 CONFLICT` (không có skeleton trước) · `401` · `403` · `404`.

---

<a id="api-guides-08"></a>

#### API-GUIDES-08 — `deleteGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-GUIDES-08 |
| **Label** | **Normative** |
| **Method** | `DELETE` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id` |
| **operationId** | `deleteGuide` |

**Response:** `204` · `401` · `403` · `404`.

**Business rules:** BR-GUIDE-005.

---

### 2.4 Publish — FEAT-006

Module: [`api-contract.md §Publish`](../../specs/api-contract.md#publish) · Feature: [FEAT-006](../../features/FEAT-006-publish-a-pose.md)

<a id="api-publish-01"></a>

#### API-PUBLISH-01 — `publishGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-PUBLISH-01 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Owner Account hoặc Bearer admin |
| **Path** | `/api/guides/:id/publish` |
| **operationId** | `publishGuide` |

**Request:** Path `id`; body rỗng.

**Response:** `200` `{ data: Pose }` (`status = published`) · `401` · `403` · `404` · `409 ASSET_NOT_READY`.

**Business rules:** BR-PUBLISH-001…003.

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [Main 1–2](../../features/FEAT-006-publish-a-pose.md#main-flow) | Visibility transition → public catalogue |
| [E1](../../features/FEAT-006-publish-a-pose.md#exception-flows) | Asset not ready |
| [E2](../../features/FEAT-006-publish-a-pose.md#exception-flows) | Owner/auth unknown |

**Ghi chú:** Admin PATCH `status` trên SCR-007-02 là **Observed** shortcut — **không** thay `publishGuide` (**Normative**). Xem [API-ADMIN-COMMUNITY-OBS-02](#api-admin-community-obs-02).

---

<a id="api-publish-02"></a>

#### API-PUBLISH-02 — `unpublishGuide`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-PUBLISH-02 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Owner hoặc Admin |
| **Path** | `/api/guides/:id/unpublish` |
| **operationId** | `unpublishGuide` |

**Response:** `200` `{ data: Pose }` (`status = local`) · `401` · `403` · `404`.

**Business rules:** BR-PUBLISH-004, BR-SAVED-004.

---

### 2.5 Saved — FEAT-008

Module: [`api-contract.md §Saved`](../../specs/api-contract.md#saved) · Feature: [FEAT-008](../../features/FEAT-008-use-published-poses.md)

<a id="api-saved-01"></a>

#### API-SAVED-01 — `listSavedPoses`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-SAVED-01 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Signed-in Account |
| **Path** | `/api/me/saved` |
| **operationId** | `listSavedPoses` |

**Request:** `page`, `limit`.

**Response:** `200` paginated **`CommunityPose` view** (published-only projection) · `401`.

**Ghi chú response shape:** List trả **CommunityPose** DTO — không phải `SavedEntry`.

---

<a id="api-saved-02"></a>

#### API-SAVED-02 — `savePose`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-SAVED-02 |
| **Label** | **Normative** |
| **Method** | `PUT` |
| **Auth** | Signed-in Account |
| **Path** | `/api/me/saved/:poseId` |
| **operationId** | `savePose` |

**Response:** `200` `{ data: SavedEntry }` · `401` · `404`.

**Ghi chú response shape:** PUT trả **`SavedEntry`** — khác list projection.

**Business rules:** BR-SAVED-001, BR-SAVED-002, BR-SAVED-005.

**Feature-flow mapping:** [A2](../../features/FEAT-008-use-published-poses.md#alternative-flows) (sign-in gate); [E2](../../features/FEAT-008-use-published-poses.md#exception-flows) (account state unavailable — **Unresolved** runtime).

---

<a id="api-saved-03"></a>

#### API-SAVED-03 — `unsavePose`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-SAVED-03 |
| **Label** | **Normative** |
| **Method** | `DELETE` |
| **Auth** | Signed-in Account |
| **Path** | `/api/me/saved/:poseId` |
| **operationId** | `unsavePose` |

**Response:** `204` (idempotent) · `401`.

---

### 2.6 Admin Community — FEAT-007

Module: [`api-contract.md §Admin Community`](../../specs/api-contract.md#admin-community) · Feature: [FEAT-007](../../features/FEAT-007-operate-pose-content-from-admin-web.md)

<a id="api-admin-community-01"></a>

#### API-ADMIN-COMMUNITY-01 — `listAdminCommunityPoses`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-01 |
| **Label** | **Normative** |
| **Method** | `GET` |
| **Auth** | Bearer admin |
| **Path** | `/api/admin/community/poses` |
| **operationId** | `listAdminCommunityPoses` |

**Request:** `page`, `limit` (default 50, max 100).

**Response:** `200` paginated canonical `Pose` (local + published) · `401` · `429` · `500`.

**Feature-flow mapping:** [Main 1](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md#main-flow), [A1](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md#alternative-flows) (refresh).

---

<a id="api-admin-community-02"></a>

#### API-ADMIN-COMMUNITY-02 — `createAdminCommunityUploadUrl`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-02 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Bearer admin |
| **Path** | `/api/admin/community/poses/upload-url` |
| **operationId** | `createAdminCommunityUploadUrl` |

**Request:** JSON MIME (`image/png`, `image/jpeg`, `image/webp`).

**Response:** `200` `{ data: { uploadUrl, fileKey } }` · `400` · `401` · `500`.

**Screen evidence:** **Normative** contract; [SCR-007-02](./screens/admin/scr-007-02-community.md) upload flow **không** dùng endpoint này (**Observed** multipart extract thay thế) — xem [Unresolved](#unresolved).

---

<a id="api-admin-community-03"></a>

#### API-ADMIN-COMMUNITY-03 — `createAdminCommunityPose`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-03 |
| **Label** | **Normative** |
| **Method** | `POST` |
| **Auth** | Bearer admin |
| **Path** | `/api/admin/community/poses` |
| **operationId** | `createAdminCommunityPose` |

**Request:** JSON — `jobId` (succeeded), `ownerAccountId` (bắt buộc), `name`, `bodyParts`, optional `tags`, `difficulty`, `description`.

**Response:** `201` `{ data: { pose: Pose } }` · `400` · `401` · `429` · `500`.

**Business rules:** BR-ADMCOM-003, BR-GUIDE-001, BR-ADMCOM-006, BR-ADMCOM-007.

**Feature-flow mapping:**

| Flow | Usage |
| --- | --- |
| [FEAT-005 Main 6–9](../../../harness/features/FEAT-005-manage-a-pose-guide.md#main-flow) | Admin intake sau extract `succeeded` |
| [FEAT-007 Main 2](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md#main-flow) | Proxy forward POST |
| [E2](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md#exception-flows) | Upstream rejection |

---

## 3. Feature → API mapping

| Feature | Module | Normative stable IDs | Dedicated screen | Ghi chú |
| --- | --- | --- | --- | --- |
| [FEAT-003](../../../harness/features/FEAT-003-browse-and-search-published-poses.md) | community | API-COMMUNITY-01, API-COMMUNITY-02 | SCR-003-01/02/03 | Aliases API-003-01/02 |
| [FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md) | extract-pose | API-EXTRACT-POSE-01, API-EXTRACT-POSE-02 | [SCR-004-01](./screens/mobile/scr-004-01-add-pose.md) | Add Pose extraction flow |
| [FEAT-005](../../../harness/features/FEAT-005-manage-a-pose-guide.md) | guides | API-GUIDES-01…08 | [SCR-004-01](./screens/mobile/scr-004-01-add-pose.md), [SCR-005-01](./screens/mobile/scr-005-01-jobs.md) | Add Pose metadata + dedicated Jobs tracking screen; shared SCR-003-03 delete UX |
| [FEAT-006](../../../harness/features/FEAT-006-publish-a-pose.md) | publish | API-PUBLISH-01, API-PUBLISH-02 | — | Admin status PATCH **Observed**, không owner screen |
| [FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md) | admin-community (+ proxy) | API-ADMIN-COMMUNITY-01…03; API-PROXY-01…06 | SCR-007-01/02/03 | Observed by-id + admin poll riêng |
| [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md) | saved | API-SAVED-01…03 | — | Try Pose: no HTTP |
| [FEAT-009](../../../harness/features/FEAT-009-configure-extraction-provider.md) | — | — (không module ID) | SCR-007-03 panel | **Observed** GET/PUT cross-ref only — **Unresolved** |

---

## 4. Screen → API matrix

| Screen | Endpoint(s) | Stable ID / label | Trigger |
| --- | --- | --- | --- |
| [SCR-003-01](./screens/scr-003-01-community-browse.md) | `GET /api/community/poses` | API-COMMUNITY-01 (**Normative**) | Initial, refresh, load-more |
| [SCR-003-02](./screens/scr-003-02-search.md) | `GET /api/community/poses?q=...` | API-COMMUNITY-01 (**Normative** contract; `q` evidence **Unresolved**) | Published title search |
| [SCR-003-03](./screens/scr-003-03-pose-detail.md) | `GET /api/community/poses/:id` | API-COMMUNITY-02 (**Normative**) | Detail sau published `poseId` |
| SCR-003-03 (FEAT-008) | `PUT/DELETE /api/me/saved/:poseId` | API-SAVED-02/03 (**Normative**; runtime **Unresolved**) | Save / Unsave |
| [SCR-004-01](./screens/mobile/scr-004-01-add-pose.md) | `POST /api/extract-pose` (image + metadata draft) → poll `GET /api/extract-jobs/:jobId` | API-EXTRACT-POSE-01 (**Normative**), API-EXTRACT-POSE-02 (**Normative**) | Submit ảnh và draft metadata, poll tiến độ; server tạo Pose tự động khi `succeeded`. UI trạng thái: `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose` |
| [SCR-005-01](./screens/mobile/scr-005-01-jobs.md) | `GET /api/me/extract-jobs` (list) → `GET /api/extract-jobs/:jobId` (poll) → `POST /api/me/extract-jobs/:id/retry` (retry) → `DELETE /api/me/extract-jobs/:id` (hide) | API-EXTRACT-POSE-02 (**Normative**), `listMyExtractJobs` (**Normative**), `retryExtractJob` (**Normative**), `hideExtractJob` (**Normative**) | Liệt kê, poll, retry và ẩn jobs của tài khoản; nhãn UI là `Queued`, `Processing`, `Failed → Retry`, `Ready → View pose` |
| [SCR-007-02](./screens/admin/scr-007-02-community.md) | `GET /api/admin/community/poses` | API-ADMIN-COMMUNITY-01 via [API-PROXY-02](#api-proxy-02) | List refresh |
| SCR-007-02 | `POST /api/admin/extract-pose` → poll → `POST /api/admin/community/poses` | API-PROXY-01 + [API-ADMIN-EXTRACT-JOBS-OBS-01](#api-admin-extract-jobs-obs-01) + API-ADMIN-COMMUNITY-03 | Upload flow |
| SCR-007-02 (edit overlay) | `PATCH /api/admin/community/poses/:id` | [API-ADMIN-COMMUNITY-OBS-02](#api-admin-community-obs-02) (**Observed**) | Save metadata + `status` |
| SCR-007-02 (edit overlay) | `DELETE /api/admin/community/poses/:id` | [API-ADMIN-COMMUNITY-OBS-03](#api-admin-community-obs-03) (**Observed**) | Delete pose |
| [SCR-007-03](./screens/admin/scr-007-03-keys.md) | `GET/PUT /api/admin/settings/extraction-provider` | FEAT-009 cross-ref (**Observed**; **Unresolved**) | Extract Engine panel |
| SCR-007-03 | Admin keys routes | API-PROXY-03…05 | Key CRUD (ngoài 20 Normative) |

Model response: [`models.md`](./models.md) — [`CommunityPose`](../../specs/data-contract.md#communitypose-deprecated-as-entity--public-dtoview), [`Pose`](../../specs/data-contract.md#pose), [`SavedEntry`](../../specs/data-contract.md#savedentry).

---

## 5. Admin proxy convention (API-PROXY-01 … API-PROXY-06)

Next.js Admin Web inject Bearer server-side; contract upstream nằm ở Express ([`api-contract.md` § Next.js proxy](../../specs/api-contract.md#nextjs-proxy-không-phải-contract-riêng)). Mỗi hàng: **transport** (Next path) → **upstream** (Express).

| Stable ID | Transport (Next.js) | Upstream (Express) | Ghi chú |
| --- | --- | --- | --- |
| <a id="api-proxy-01"></a>**API-PROXY-01** | `POST /api/admin/extract-pose` | `POST /api/extract-pose` | Maps tới [API-EXTRACT-POSE-01](#api-extract-pose-01) upstream |
| <a id="api-proxy-02"></a>**API-PROXY-02** | `GET`, `POST /api/admin/community/poses` | `/api/admin/community/poses` | GET → [API-ADMIN-COMMUNITY-01](#api-admin-community-01); POST → [API-ADMIN-COMMUNITY-03](#api-admin-community-03) |
| <a id="api-proxy-03"></a>**API-PROXY-03** | `GET`, `POST /api/admin/keys` | `/api/admin/keys` | Ngoài 20 Normative (`admin-keys` module) |
| <a id="api-proxy-04"></a>**API-PROXY-04** | `PATCH`, `DELETE /api/admin/keys/:id` | `/api/admin/keys/:id` | Ngoài 20 Normative |
| <a id="api-proxy-05"></a>**API-PROXY-05** | `POST /api/admin/keys/reset` | `/api/admin/keys/reset` | Ngoài 20 Normative |
| <a id="api-proxy-06"></a>**API-PROXY-06** | Job poll: `GET /api/admin/jobs/:jobId` | `GET /api/admin/jobs/:jobId` | Upstream `getAdminJob` — **ngoài** 20 Normative; module [`api-contract.md §Admin Jobs`](../../specs/api-contract.md#admin-jobs) |

**Không gộp:** `getAdminJob` (API-PROXY-06 upstream) ≠ [API-EXTRACT-POSE-02](#api-extract-pose-02) ≠ [API-ADMIN-EXTRACT-JOBS-OBS-01](#api-admin-extract-jobs-obs-01).

---

## 6. Poll endpoint distinctions

| # | Stable ID / route | Auth | Transport | Mục đích | Label |
| --- | --- | --- | --- | --- | --- |
| 1 | [API-EXTRACT-POSE-02](#api-extract-pose-02) `GET /api/extract-jobs/:jobId` | Account session (owner-checked, 404 cho tài khoản khác) hoặc Bearer admin | Express direct | Account/mobile per-job poll | **Normative** |
| 2 | `getAdminJob` `GET /api/admin/jobs/:jobId` | Bearer admin | Express upstream (API-PROXY-06) | Admin job poll canonical upstream | **Normative** (ngoài 20) |
| 3 | [API-ADMIN-EXTRACT-JOBS-OBS-01](#api-admin-extract-jobs-obs-01) `GET /api/admin/extract-jobs/:jobId` | Admin proxy session | Next.js forward → owner/admin poll | SCR-007-02 upload poll | **Observed** |

---

## 7. Observed operations (absent six modules / OpenAPI)

Các route sau có delivery evidence nhưng **không** nằm trong sáu module summary hay OpenAPI operation catalogue của slice này.

<a id="api-admin-community-obs-01"></a>

#### API-ADMIN-COMMUNITY-OBS-01 — `GET /api/admin/community/poses/:id`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-OBS-01 |
| **Label** | **Observed** |
| **Method** | `GET` |
| **Auth** | Bearer admin (proxy) |
| **Path** | `/api/admin/community/poses/:id` |

**Screen:** None (không map SCR item).

**Module/OpenAPI:** Absent.

---

<a id="api-admin-community-obs-02"></a>

#### API-ADMIN-COMMUNITY-OBS-02 — `PATCH /api/admin/community/poses/:id`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-OBS-02 |
| **Label** | **Observed** |
| **Method** | `PATCH` |
| **Auth** | Bearer admin (proxy) |
| **Path** | `/api/admin/community/poses/:id` |

**Request (Observed):** `name`, `tags`, `description`, `status` (`draft`/`published` UI).

**Screen:** [SCR-007-02](./screens/admin/scr-007-02-community.md) edit overlay (SCR-007-02-OVR-010).

**Ghi chú:** PATCH `status` là **Observed** admin shortcut — **không** thay [API-PUBLISH-01](#api-publish-01)/[API-PUBLISH-02](#api-publish-02) (**Normative**).

**Module/OpenAPI:** Absent.

---

<a id="api-admin-community-obs-03"></a>

#### API-ADMIN-COMMUNITY-OBS-03 — `DELETE /api/admin/community/poses/:id`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-COMMUNITY-OBS-03 |
| **Label** | **Observed** |
| **Method** | `DELETE` |
| **Auth** | Bearer admin (proxy) |
| **Path** | `/api/admin/community/poses/:id` |

**Screen:** [SCR-007-02](./screens/admin/scr-007-02-community.md) edit overlay (SCR-007-02-OVR-011).

**Module/OpenAPI:** Absent.

---

<a id="api-admin-extract-jobs-obs-01"></a>

#### API-ADMIN-EXTRACT-JOBS-OBS-01 — `GET /api/admin/extract-jobs/:jobId`

| Thuộc tính | Giá trị |
| --- | --- |
| **Stable ID** | API-ADMIN-EXTRACT-JOBS-OBS-01 |
| **Label** | **Observed** |
| **Method** | `GET` |
| **Auth** | Admin proxy (Next.js) |
| **Path** | `/api/admin/extract-jobs/:jobId` |

**Hành vi (Observed):** Next.js route forward tới [`GET /api/extract-jobs/:jobId`](#api-extract-pose-02) (owner/admin authenticated).

**Screen:** [SCR-007-02](./screens/admin/scr-007-02-community.md) upload poll (60×1s).

**Tách biệt:** **Không** merge với [API-EXTRACT-POSE-02](#api-extract-pose-02) (Express per-job poll) hay [API-PROXY-06](#api-proxy-06) / `getAdminJob` (admin jobs upstream).

---

#### FEAT-009 extraction-provider (cross-reference only)

| Route | Method | Label | Ghi chú |
| --- | --- | --- | --- |
| `/api/admin/settings/extraction-provider` | `GET` | **Observed** | [SCR-007-03](./screens/admin/scr-007-03-keys.md) Extract Engine panel |
| `/api/admin/settings/extraction-provider` | `PUT` | **Observed** | Body `{ provider }` |

**Không** có module ID trong sáu module summary; absent OpenAPI catalogue slice; semantics **Unresolved** vs [FEAT-009](../../features/FEAT-009-configure-extraction-provider.md) Current evidence.

---

## 8. Observed implementation evidence

| Topic | Evidence | Label |
| --- | --- | --- |
| `limit` khi `q` | `communityRoutes.ts` force `SEARCH_PAGE_LIMIT = 20` khi `q` present | **Observed** — **không** phải OpenAPI contract |
| Mobile search runtime | `PoseServiceLocator` → `LiveCommunitySearchRepository` | **Observed** |
| Mobile search test fallback | `MockCommunitySearchRepository` | **Observed** — test/fixture only |
| SCR-007-02 upload poll | Client poll `GET /api/admin/extract-jobs/:jobId` max 60×1s | **Observed** |
| SCR-007-02 upload `status` select | Form select không gửi POST body | **Observed** — **Unresolved** vs intake contract |
| Admin PATCH `status` | Edit overlay PATCH `status` field | **Observed** — không phải `publishGuide` |

---

## Unresolved

<a id="unresolved"></a>

| Chiều | Trạng thái |
| --- | --- |
| **`ckh validate` `scope.path.unsupported`** | `docs/harness/designs/basic-design/apis.md` không phải supported Harness document kind — ghi nhận khi chạy `ckh validate` |
| **`q` — Normative contract** | [`api-contract.md §Community`](../../specs/api-contract.md#community-public), OpenAPI `listCommunityPoses` — **declared** |
| **`q` — FEAT-003 Current evidence** | Feature file vẫn ghi mock-backed / *"no server title search query exists"* — **Unresolved** vs spec/server |
| **`q` — Mobile E2E** | Live vs mock repository — production title search **chưa proven** |
| **`limit` override** | Server `limit=20` khi `q` — **Observed**, không phải OpenAPI default/range |
| **Filter UI** | `difficulty` / `tag` **Normative** trên API; mobile filter UI **chưa proven** |
| **Production readiness** | Public asset readiness và production exposure **chưa proven** (FEAT-003) |
| **`upload-url` (API-ADMIN-COMMUNITY-02)** | **Normative** contract; [SCR-007-02](./screens/admin/scr-007-02-community.md) upload flow **không** dùng — multipart extract thay thế |
| **FEAT-007 async UI** | Feature **Not observed** vs code poll 60×1s trên SCR-007-02 |
| **FEAT-009 provider API** | **Observed** `GET/PUT /api/admin/settings/extraction-provider` vs feature evidence gap — semantics **Unresolved** |
| **FEAT-008 Saved runtime** | API-SAVED-01…03 **Normative**; account/session + Saved UI **chưa proven** E2E |
| **Observed admin by-id routes** | API-ADMIN-COMMUNITY-OBS-01/02/03 absent module/OpenAPI — contract promotion **Unresolved** |
| **Compatibility numbering** | Chỉ API-003-01/02 retained; API-001…API-023 catalogue **cấm** (state collision) |
