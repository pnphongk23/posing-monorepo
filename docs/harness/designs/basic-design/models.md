# Models — Basic Design summary

<a id="models-top"></a>

Tài liệu này tóm tắt **8 entity/domain projection** + **1 auxiliary navigation DTO** cho Basic Design slice. Không thay thế [`docs/spec/data`](../../../spec/data/README.md) — chỉ summary + link source-of-truth.

| Canonical source | Link |
| --- | --- |
| Domain overview | [`domain-model.md`](../../../spec/data/domain-model.md) |
| Entity semantics | [`entities/`](../../../spec/data/entities/) |
| Shared enums | [`enums.md`](../../../spec/data/enums.md) |
| ERD | [`erd/`](../../../spec/data/erd/) |
| HTTP contract (slice) | [`apis.md`](./apis.md) |
| Screens | [`screens/README.md`](./screens/README.md) |

**Evidence labeling:** **Normative** = Harness Feature + `docs/spec`; **Observed** = code/delivery evidence; **Unresolved** = conflict hoặc chưa chứng minh E2E — không sửa SoT tại đây.

---

## 1. Tổng quan

<a id="models-overview"></a>

Basic Design `models.md` map **presentation/data projection** → canonical entity SoT. Phân loại storage vs DTO:

| ID | Tên | Layer | Storage vs DTO | Owning features (summary) |
| --- | --- | --- | --- | --- |
| `MODEL-PHOTO-01` | Photo | Mobile local | **Persisted** (SQLDelight local) | [FEAT-001](../../features/FEAT-001-capture-a-photo-on-mobile.md), [FEAT-002](../../features/FEAT-002-manage-a-local-photo-gallery.md) |
| `MODEL-POSE-01` | Pose | Mobile local + Server | **Persisted** (canonical entity) | [FEAT-005](../../features/FEAT-005-manage-a-pose-guide.md), [FEAT-006](../../features/FEAT-006-publish-a-pose.md) |
| `MODEL-MEDIA-ASSET-01` | MediaAsset | Server | **Persisted** | [FEAT-005](../../features/FEAT-005-manage-a-pose-guide.md), [FEAT-006](../../features/FEAT-006-publish-a-pose.md) |
| `MODEL-EXTRACTION-JOB-01` | ExtractionJob | Server | **Persisted** | [FEAT-004](../../features/FEAT-004-extract-reusable-pose-images.md) |
| `MODEL-ACCOUNT-01` | Account | Server | **Persisted** | [FEAT-006](../../features/FEAT-006-publish-a-pose.md), [FEAT-008](../../features/FEAT-008-use-published-poses.md), [FEAT-014](../../features/FEAT-014-manage-account-and-session.md) |
| `MODEL-SAVED-ENTRY-01` | SavedEntry | Server | **Persisted** | [FEAT-008](../../features/FEAT-008-use-published-poses.md) |
| `MODEL-PREPARED-POSE-REFERENCE-01` | PreparedPoseReference | Mobile conceptual | **In-memory transport** (không persist relaunch) | [FEAT-008](../../features/FEAT-008-use-published-poses.md) |
| `MODEL-COMMUNITY-POSE-01` | CommunityPose | Public API DTO | **View/DTO** trên `Pose` (`status = published`); không storage riêng | [FEAT-003](../../features/FEAT-003-browse-and-search-published-poses.md), [FEAT-006](../../features/FEAT-006-publish-a-pose.md) |
| `MODEL-POSE-PREVIEW` | PosePreview | Navigation | **Observed transport** — không entity, không persisted | Cross-slice FEAT-003 navigation |

**Không mở rộng trong slice này:** `ApiKeyCredential`, `ProviderRequestLog`, deprecated aliases (`PoseGuide`, `PersonalPose`, `PoseReferenceKey`).

**Creation timing (cross-entity):** `Pose` chỉ được tạo **sau khi** `ExtractionJob` `succeeded`; trong lúc extraction chỉ có `jobId` làm correlation key — xem [`domain-model.md`](../../../spec/data/domain-model.md).

---

## 2. Enum register

<a id="models-enum-register"></a>

Năm nhóm enum product dùng chung. Chi tiết giá trị và BR: [`enums.md`](../../../spec/data/enums.md).

| Enum | Entity liên quan | Giá trị (summary) | SoT |
| --- | --- | --- | --- |
| `PoseStatus` | `Pose`, `CommunityPose` (projection) | `local` \| `published`; legacy `draft` → `local` | [`enums.md#posestatus`](../../../spec/data/enums.md#posestatus) |
| `PoseDifficulty` | `Pose`, `CommunityPose` | `beginner` \| `intermediate` \| `advanced` \| _(null)_ | [`enums.md#posedifficulty`](../../../spec/data/enums.md#posedifficulty) |
| `MediaAssetRole` | `MediaAsset` | `original` \| `skeleton` \| `thumbnail` — đúng ba role/pose | [`enums.md#mediaassetrole`](../../../spec/data/enums.md#mediaassetrole) |
| `MediaAssetReadiness` | `MediaAsset` | `pending` \| `ready` \| `failed` | [`enums.md#mediaassetreadiness`](../../../spec/data/enums.md#mediaassetreadiness) |
| `ExtractionJobStatus` | `ExtractionJob` | `queued` \| `processing` \| `succeeded` \| `failed` | [`enums.md#extractionjobstatus`](../../../spec/data/enums.md#extractionjobstatus) |

**Adjacent proxy note:** `ApiKeyStatus` (`active` \| `disabled` \| `exhausted`) thuộc vận hành provider ([`enums.md#apikeystatus`](../../../spec/data/enums.md#apikeystatus)) — gắn [`ApiKeyCredential`](../../../spec/data/entities/api-key-credential.md) / FEAT-004 ops, **không** catalogue trong slice entity chính. Screen proxy: [SCR-007-03 Keys](./screens/admin/scr-007-03-keys.md#scr-007-03-admin-keys-main).

---

## 3. ERD relation summary

<a id="models-erd-summary"></a>

Tóm tắt quan hệ product — diagram đầy đủ tại SoT ERD (không duplicate Mermaid tại đây).

| ERD | Phạm vi | Link |
| --- | --- | --- |
| Conceptual overlay | Try Pose, `PreparedPoseReference`, ranh giới mobile/server | [`erd/conceptual.md`](../../../spec/data/erd/conceptual.md) |
| Server | `Account`, `Pose`, `MediaAsset`, `ExtractionJob`, `SavedEntry` | [`erd/server.md`](../../../spec/data/erd/server.md) |
| Mobile local | `Photo`, `Pose` (local) | [`erd/mobile.md`](../../../spec/data/erd/mobile.md) |

**Quan hệ cốt lõi (summary):**

```text
Account 1──* Pose (ownerAccountId REQUIRED)
Pose 1──|3 MediaAsset (original | skeleton | thumbnail — materialize tại tạo pose)
Pose 1──* ExtractionJob (jobId trước pose; poseId back-fill sau succeeded)
Account 1──* SavedEntry ──* Pose (published only)
Photo ──o Pose (optional poseId, mobile local)
CommunityPose = view Pose WHERE status = published (DTO, không entity riêng)
PreparedPoseReference ──o Pose + MediaAsset(skeleton ready) [in-memory]
```

`CommunityPose` catalogue **không** xuất hiện như node storage trong ERD server — chỉ projection/DTO.

---

## 4. Photo (`MODEL-PHOTO-01`)

<a id="model-photo-01"></a>

### 4.1 Overview — DTO vs storage

**Persisted** trên mobile local (SQLDelight). Không có HTTP API. Không sync bắt buộc lên server. `Photo.poseId` optional — chỉ set khi [`Pose`](../../../spec/data/entities/pose.md) đã tồn tại (post-extraction).

### 4.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `id` | Local PK |
| `imagePath` | Đường dẫn file ảnh đọc được |
| `poseId` | Optional FK → `Pose.poseId` (UUID) |
| `poseName` | Snapshot tên pose lúc chụp |
| `createdAt` | ISO 8601 |
| `isFavorite` | Boolean favorite flag |

SoT: [`photo.md`](../../../spec/data/entities/photo.md)

### 4.3 Relations

| Relation | Mô tả |
| --- | --- |
| `Photo.poseId` → `Pose.poseId` | Optional; ON DELETE SET NULL |
| Server | Không FK bắt buộc |

ERD: [`erd/mobile.md`](../../../spec/data/erd/mobile.md)

### 4.4 Enums

Không dùng shared enum product — `isFavorite` là integer flag local.

### 4.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-PHOTO-001 | Một capture → một `Photo` + một file |
| BR-PHOTO-002 | Capture cần camera permission |
| BR-PHOTO-003 | Xóa hoàn tất khi metadata + file đều gỡ |
| BR-PHOTO-004 | Favorite/delete/export success sau khi xác nhận |
| BR-PHOTO-005 | File không đọc được → placeholder, không crash |
| BR-PHOTO-006 | Xóa `Pose` không xóa `Photo`; `poseName` là snapshot |

### 4.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `Photo` (capture) | None (local) | [SCR-001-01 Camera](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) |
| `Photo` (gallery) | None (local SQLDelight) | [SCR-002-01 Gallery](./screens/mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) |

### 4.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Entity fields + BR tại SoT |
| **Observed** | `PhotoRepository`, `CameraCoordinator` trên mobile |

---

## 5. Pose (`MODEL-POSE-01`)

<a id="model-pose-01"></a>

### 5.1 Overview — DTO vs storage

**Persisted canonical entity** — mobile local (`status = local`) và server (local + published). Catalogue công khai **không** tạo entity thứ hai; publish chỉ đổi `status`. API trả `PoseResponse` với URL camelCase (`originalUrl`, `skeletonUrl`, `thumbnailUrl`) thay cho media IDs — projection từ [`MediaAsset`](../../../spec/data/entities/media-asset.md).

`ownerAccountId` **bắt buộc** trên mọi `Pose`. `poseId` UUID ổn định từ tạo (post-extraction) → `published`.

### 5.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `poseId` | PK; gán một lần post-extraction |
| `ownerAccountId` | FK → `Account.id` (required) |
| `name`, `description`, `tags`, `difficulty`, `bodyParts` | Metadata catalogue |
| `status` | `PoseStatus`: `local` \| `published` |
| `originalMediaId`, `skeletonMediaId`, `thumbnailMediaId` | FK → ba `MediaAsset` (non-nullable tại tạo) |
| `currentJobId` | FK → `ExtractionJob` hiện hành |
| `createdAt`, `updatedAt` | Timestamps |

SoT: [`pose.md`](../../../spec/data/entities/pose.md)

### 5.3 Relations

| Relation | Mô tả |
| --- | --- |
| `Pose.ownerAccountId` → `Account` | Owner bắt buộc |
| `Pose` 1—3 `MediaAsset` | Roles `original`, `skeleton`, `thumbnail` |
| `Pose` 1—* `ExtractionJob` | Lịch sử; `currentJobId` trỏ job hiện tại |
| `Pose` 1—* `SavedEntry` | Khi `published` |
| `Photo.poseId` → `Pose` | Optional mobile link |
| Public catalogue | View/DTO `CommunityPose` khi `published` |

ERD: [`erd/server.md`](../../../spec/data/erd/server.md), [`erd/mobile.md`](../../../spec/data/erd/mobile.md)

### 5.4 Enums

| Enum | Field | Link |
| --- | --- | --- |
| `PoseStatus` | `status` | [`enums.md#posestatus`](../../../spec/data/enums.md#posestatus) |
| `PoseDifficulty` | `difficulty` | [`enums.md#posedifficulty`](../../../spec/data/enums.md#posedifficulty) |

### 5.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-POSE-001 | Submit enqueue job — không tạo `Pose` cho tới `succeeded` |
| BR-POSE-002 | Publish cần skeleton `ready` |
| BR-POSE-003 | Retry/re-extract cùng `poseId` |
| BR-POSE-004 | `poseId` stable `local` → `published` |
| BR-POSE-005 | Xóa terminal gỡ catalogue + SavedEntry presentation |
| BR-POSE-006 | Chỉ owner hoặc Admin sửa/xóa |
| BR-POSE-007 | Catalogue = view `published` only |
| BR-POSE-008 | `ownerAccountId` bắt buộc; Admin phải chỉ định owner |
| BR-POSE-009 | Ba `MediaAsset` materialize tại tạo pose |

### 5.6 Traceability — model → API → screen

| Model | API (summary) | Screen |
| --- | --- | --- |
| `Pose` (admin CRUD) | [API-ADMIN-COMMUNITY-01…03](./apis.md#api-admin-community-01) via [API-PROXY-02](./apis.md#api-proxy-02); edit/delete [API-ADMIN-COMMUNITY-OBS-02/03](./apis.md#api-admin-community-obs-02) (**Observed**) | [SCR-007-02 Community](./screens/admin/scr-007-02-community.md#scr-007-02-admin-community-poses) |
| `Pose` (local) | None (mobile local) | Local paths trong FEAT-005 — **out-of-slice** |
| `Pose` → `CommunityPose` projection | [API-COMMUNITY-01](./apis.md#api-community-01), [API-COMMUNITY-02](./apis.md#api-community-02) (public DTO leg; alias API-003-01/02) | [SCR-003-01/02/03](./screens/scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) |

### 5.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Entity + enums + BR tại SoT |
| **Observed** | Admin upload/list/edit trên SCR-007-02; mobile local repository |

---

## 6. MediaAsset (`MODEL-MEDIA-ASSET-01`)

<a id="model-media-asset-01"></a>

### 6.1 Overview — DTO vs storage

**Persisted** server-side payload gắn `Pose`. Mỗi pose có đúng **ba** asset (roles materialize tại tạo pose). Public/API DTO expose locator qua URL fields (`skeletonUrl`, `thumbnailUrl`, `originalUrl`) — không duplicate asset row trên client catalogue.

### 6.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `mediaId` | PK |
| `poseId` | FK → `Pose` |
| `role` | `MediaAssetRole` |
| `locator` | URI đọc được |
| `mimeType` | `image/png` \| `jpeg` \| `webp` |
| `readiness` | `MediaAssetReadiness` |
| `createdAt`, `updatedAt` | Timestamps |

SoT: [`media-asset.md`](../../../spec/data/entities/media-asset.md)

### 6.3 Relations

| Relation | Mô tả |
| --- | --- |
| `Pose` → `MediaAsset` | 1—1 mỗi role (`original`, `skeleton`, `thumbnail`) |
| `ExtractionJob` `succeeded` | Cập nhật/tạo skeleton `ready` |
| `PreparedPoseReference.mediaId` | Tham chiếu skeleton `ready` (in-memory) |
| `CommunityPose` URLs | Project từ skeleton/thumbnail `ready` |

ERD: [`erd/server.md`](../../../spec/data/erd/server.md)

### 6.4 Enums

| Enum | Field | Link |
| --- | --- | --- |
| `MediaAssetRole` | `role` | [`enums.md#mediaassetrole`](../../../spec/data/enums.md#mediaassetrole) |
| `MediaAssetReadiness` | `readiness` | [`enums.md#mediaassetreadiness`](../../../spec/data/enums.md#mediaassetreadiness) |

### 6.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-ASSET-001 | Một `original` hiện hành/pose |
| BR-ASSET-002 | Publish cần skeleton `ready` + locator đọc được |
| BR-ASSET-003 | `pending`/`failed` không catalogue/Try Pose |
| BR-ASSET-004 | Public locator trỏ asset `ready`, không payload job tạm |
| BR-ASSET-005 | Ba asset materialize tại tạo pose |

### 6.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `MediaAsset` (embedded) | `PoseResponse` / `CommunityPose` URL fields — **Normative** summary/traceability trong Basic Design: [API-COMMUNITY-01](./apis.md#api-community-01), [API-COMMUNITY-02](./apis.md#api-community-02) | SCR-003-03 hero (`skeletonUrl`/`thumbnailUrl`); SCR-007-02 card image |
| Skeleton verify (Try Pose) | Download skeleton — FEAT-008 **out-of-slice** | [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) → [SCR-001-01](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) |

### 6.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Role/readiness semantics tại SoT |
| **Observed** | URL projection trên community/admin responses |

---

## 7. ExtractionJob (`MODEL-EXTRACTION-JOB-01`)

<a id="model-extraction-job-01"></a>

### 7.1 Overview — DTO vs storage

**Persisted** server job. `id` = **`jobId`** — correlation key khi **chưa có** `Pose`. Submit trả `202` + `jobId`; `Pose` tạo **sau** `succeeded`. `poseId` nullable tới lúc back-fill.

### 7.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `id` | PK = `jobId` (UUID) |
| `poseId` | FK → `Pose`; NULL tới succeeded |
| `status` | `ExtractionJobStatus` |
| `sourceMediaId`, `skeletonMediaId` | FK `MediaAsset` khi có |
| `errorCode`, `errorMessage` | Khi `failed` |
| `attempts`, `maxAttempts` | Retry control |
| `createdAt`, `updatedAt` | Timestamps |

SoT: [`extraction-job.md`](../../../spec/data/entities/extraction-job.md)

### 7.3 Relations

| Relation | Mô tả |
| --- | --- |
| `ExtractionJob` → `Pose` | Nhiều job một pose; `poseId` late-bound |
| Job `succeeded` | Tạo `Pose` + materialize ba `MediaAsset` |
| Provider ops | `ApiKeyCredential` / `ProviderRequestLog` — **out-of-slice** entity |

ERD: [`erd/server.md`](../../../spec/data/erd/server.md)

### 7.4 Enums

| Enum | Field | Link |
| --- | --- | --- |
| `ExtractionJobStatus` | `status` | [`enums.md#extractionjobstatus`](../../../spec/data/enums.md#extractionjobstatus) |

### 7.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-JOB-001 | Trạng thái: `queued` → `processing` → `succeeded` \| `failed` |
| BR-JOB-002 | Retry trong `maxAttempts`; hết → `failed` |
| BR-JOB-003 | `succeeded` cần skeleton `ready` trước publish |
| BR-JOB-004 | GET: `result`/`error` theo status |
| BR-JOB-005 | Không usable image khi provider fail |
| BR-JOB-006 | Không `Pose` persisted trước `succeeded` |

### 7.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `ExtractionJob` (admin upload) | [API-PROXY-01](./apis.md#api-proxy-01) + [API-ADMIN-EXTRACT-JOBS-OBS-01](./apis.md#api-admin-extract-jobs-obs-01) (**Observed** poll) | [SCR-007-02 Upload](./screens/admin/scr-007-02-community.md#scr-007-02-admin-community-poses) |
| Extract engine setting | Provider API — FEAT-009 **Unresolved** | [SCR-007-03 Keys](./screens/admin/scr-007-03-keys.md#scr-007-03-admin-keys-main) |

### 7.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Job lifecycle + BR tại SoT |
| **Observed** | Admin extract→poll→create pose trên SCR-007-02 |

---

## 8. Account (`MODEL-ACCOUNT-01`)

<a id="model-account-01"></a>

### 8.1 Overview — DTO vs storage

**Persisted** server identity cho signed-in user. Session/credential fields **ngoài** entity catalogue — xem [FEAT-014](../../features/FEAT-014-manage-account-and-session.md). Admin operator **không** là `Account` (Bearer admin); mọi `Pose` vẫn có `ownerAccountId` trỏ `Account`.

### 8.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `id` | PK (UUID) |
| `displayName` | Tên hiển thị |
| `createdAt` | Timestamp |

SoT: [`account.md`](../../../spec/data/entities/account.md)

### 8.3 Relations

| Relation | Mô tả |
| --- | --- |
| `Account` 1—* `Pose` | Owner |
| `Account` 1—* `SavedEntry` | Saved collection |

ERD: [`erd/server.md`](../../../spec/data/erd/server.md)

### 8.4 Enums

Không enum riêng trên entity `Account`.

### 8.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-ACCOUNT-001 | Chỉ signed-in account Save/Unsave và sở hữu pose |
| BR-ACCOUNT-002 | Use published pose không cấp ownership |
| BR-ACCOUNT-003 | Publish/unpublish cần owner hoặc Admin |
| BR-ACCOUNT-004 | Visitor → sign-in prompt; không confirm Saved khi chưa account |
| BR-ACCOUNT-005 | `ownerAccountId` bắt buộc mọi `Pose`; Admin chỉ định owner explicit |

### 8.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `Account` / session | Auth endpoints — FEAT-014 **out-of-slice** | Không dedicated screen trong Basic Design inventory |
| Owner on admin create | `ownerAccountId` trên admin pose create | [SCR-007-02](./screens/admin/scr-007-02-community.md#scr-007-02-admin-community-poses) |
| Save gate | Save/Unsave — FEAT-008 **Unresolved** account API | [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) cross-ref |

### 8.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Entity fields + BR tại SoT |
| **Observed** | Admin upload yêu cầu `ownerAccountId` — **Observed** SCR-007-02 |

---

## 9. SavedEntry (`MODEL-SAVED-ENTRY-01`)

<a id="model-saved-entry-01"></a>

### 9.1 Overview — DTO vs storage

**Persisted** server collection row — liên kết signed-in `Account` với `Pose` **published**. Không tạo entity pose riêng; không cấp ownership.

### 9.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `id` | PK (UUID) |
| `accountId` | FK → `Account` |
| `poseId` | FK → `Pose` (published) |
| `savedAt` | Timestamp |

SoT: [`saved-entry.md`](../../../spec/data/entities/saved-entry.md)

### 9.3 Relations

| Relation | Mô tả |
| --- | --- |
| `SavedEntry` → `Account` | N:1 |
| `SavedEntry` → `Pose` | N:1; unique (`accountId`, `poseId`) |

ERD: [`erd/server.md`](../../../spec/data/erd/server.md), [`erd/conceptual.md`](../../../spec/data/erd/conceptual.md)

### 9.4 Enums

Không enum riêng.

### 9.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-SAVED-001 | Chỉ lưu pose `published` |
| BR-SAVED-002 | Unique account+pose; idempotent re-save |
| BR-SAVED-003 | Unsave chỉ xóa entry |
| BR-SAVED-004 | Unpublish/xóa pose → không present như còn hiệu lực |
| BR-SAVED-005 | Use/Save không cấp edit/publish/delete |

### 9.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `SavedEntry` | [API-SAVED-01…03](./apis.md#api-saved-01) (**Normative**); FEAT-008/013 runtime **Unresolved** | [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) Save action — cross-ref |

### 9.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Entity + BR tại SoT |
| **Unresolved** | Account-backed Save API/UI evidence chưa proven trong slice |

---

## 10. PreparedPoseReference (`MODEL-PREPARED-POSE-REFERENCE-01`)

<a id="model-prepared-pose-reference-01"></a>

### 10.1 Overview — DTO vs storage

**In-memory transport contract** trên mobile sau Try Pose prepare thành công. **Không persist qua relaunch** — khác [`PreparedPoseReference`](../../../spec/data/entities/prepared-pose-reference.md) SoT và FEAT-012 snapshot (`PersistedPoseIdentity` là concern riêng).

### 10.2 Field summary

| Field | Vai trò (summary) |
| --- | --- |
| `poseId` | UUID canonical `Pose` |
| `mediaId` | UUID skeleton `MediaAsset` |
| `name` | Display name |
| `skeletonLocator` | Local/data URI sau verify — **never remote URL** |

SoT: [`prepared-pose-reference.md`](../../../spec/data/entities/prepared-pose-reference.md)

### 10.3 Relations

| Relation | Mô tả |
| --- | --- |
| `poseId` → `Pose` | Identity |
| `mediaId` → `MediaAsset` | Role `skeleton`, `readiness = ready` |

ERD: [`erd/conceptual.md`](../../../spec/data/erd/conceptual.md)

### 10.4 Enums

Không enum riêng — readiness của skeleton theo `MediaAssetReadiness`.

### 10.5 Business rules (reference)

| ID | Tóm tắt |
| --- | --- |
| BR-PREPREF-001 | `skeletonLocator` chỉ local/data URI |
| BR-PREPREF-002 | Không persist relaunch |
| BR-PREPREF-003 | Verify pass trước emit; fail → ở detail |
| BR-PREPREF-004 | Try Pose không cấp ownership/publish |

### 10.6 Traceability — model → API → screen

| Model | API | Screen |
| --- | --- | --- |
| `PreparedPoseReference` | Skeleton download/verify — FEAT-008 **out-of-slice** | [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) Try Pose → [SCR-001-01](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) overlay |

### 10.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | Transport contract tại SoT |
| **Observed** | `activeReference` / overlay trên Camera — **Observed** |
| **Unresolved** | FEAT-012 durable restore vs SoT BR-PREPREF-002 — xem §13 |

---

## 11. CommunityPose (`MODEL-COMMUNITY-POSE-01`)

<a id="model-community-pose-01"></a>

### 11.1 Overview — DTO vs storage

**Public DTO / filtered view** đọc trên canonical [`Pose`](../../../spec/data/entities/pose.md) với `status = published`. **Không** entity/bảng lưu trữ riêng. Catalogue [FEAT-003](../../features/FEAT-003-browse-and-search-published-poses.md) chỉ đọc projection này. Không lộ `ownerAccountId`, `originalUrl`, hay job metadata.

### 11.2 Field summary

| Field | Vai trò (summary) | Screen / API usage |
| --- | --- | --- |
| `poseId` | PK; card key, detail path | SCR-003-01-GRD-002, SCR-003-03 |
| `name` | Card title; title search `q` | SCR-003-03-META-001 |
| `skeletonUrl`, `thumbnailUrl` | Hero/card images | SCR-003-03-HRO-001 |
| `tags`, `bodyParts` | Metadata arrays | SCR-003-03-META-004 |
| `difficulty`, `description` | Optional metadata | SCR-003-03-META-002–003 |
| `status` | Luôn `published` trên public API | — |
| `uploadedAt` | Catalogue ordering | List sort |
| `downloadCount` | +1 mỗi detail GET thành công | Side-effect; không bắt buộc hiển thị |

SoT: [`community-pose.md`](../../../spec/data/entities/community-pose.md)

**Observed JSON aliases (mobile DTO only):** `poseId`←`id`, `skeletonUrl`←`imagePath`, `thumbnailUrl`←`thumbnailPath` — **Observed** deserialize; không đổi canonical spec field.

### 11.3 Relations

| Relation | Mô tả |
| --- | --- |
| `Pose` (canonical) | Cùng `poseId`; view khi `published` |
| `MediaAsset` | URLs project từ role `skeleton`/`thumbnail` `ready` |
| `PosePreview` | Navigation hop only — không persisted |
| `SavedEntry` | Có thể tham chiếu `poseId` — [API-SAVED-01…03](./apis.md#api-saved-01) (**Normative**, in-scope); FEAT-008/013 delivery/runtime **Unresolved** |

Publication visibility: [FEAT-006](../../features/FEAT-006-publish-a-pose.md).

### 11.4 Enums

| Enum | Usage | Link |
| --- | --- | --- |
| `PoseStatus` | DTO luôn `published`; API không lộ `local` | [`enums.md#posestatus`](../../../spec/data/enums.md#posestatus) |
| `PoseDifficulty` | Filter `difficulty` (API) | [`enums.md#posedifficulty`](../../../spec/data/enums.md#posedifficulty) |

### 11.5 Business rules (reference)

| ID | Source / context | Tóm tắt |
| --- | --- | --- |
| BR-COMMUNITY-001 | [data entity] | Public list/detail chỉ `published` |
| BR-COMMUNITY-002 | [data entity] | `downloadCount` +1 mỗi detail GET |
| BR-COMMUNITY-004 | [data entity] | Skeleton `ready` bắt buộc cho published |
| BR-COMMUNITY-005 | [data entity] | Title search chỉ published |
| BR-COMMUNITY-006 | [data entity] | List không trùng `poseId` active |
| BR-COMMUNITY-007 | [data entity] | DTO view-only; không storage riêng |
| BR-COMMUNITY-008 | [data entity] | `status` luôn `published` trên DTO |

> **Namespace collision (record only — không sửa SoT):** `BR-COMMUNITY-007` [API module] = unpublished → `404`; `BR-COMMUNITY-007` [data entity] = view-only/no storage — **cùng ID, khác layer**. API mapping: [API-COMMUNITY-02](./apis.md#api-community-02) (alias API-003-02).

Chi tiết: [`community-pose.md`](../../../spec/data/entities/community-pose.md).

### 11.6 Traceability — model → API → screen

| Model field | API | Screen item |
| --- | --- | --- |
| `poseId`, `name`, `thumbnailUrl`, `skeletonUrl` | [API-COMMUNITY-01](./apis.md#api-community-01), [API-COMMUNITY-02](./apis.md#api-community-02) | SCR-003-01-GRD-002, SCR-003-02-RES-003, SCR-003-03-HRO-001, SCR-003-03-META-001 |
| `difficulty`, `description`, `tags`, `bodyParts` | [API-COMMUNITY-02](./apis.md#api-community-02) Detail | SCR-003-03-META-002–004 |
| `downloadCount` | Detail GET side-effect | Không bắt buộc hiển thị slice evidence |
| Pagination envelope | [API-COMMUNITY-01](./apis.md#api-community-01) List | SCR-003-01-GRD-003, SCR-003-01-GRD-004 |

HTTP contract: [apis.md](./apis.md). UI surfaces: [screens/README.md](./screens/README.md).

### 11.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Normative** | DTO fields + public API contract |
| **Observed** | Mobile list/search/detail repositories |
| **Unresolved** | Title search `q` E2E; filter UI — xem §13 |

---

## 12. PosePreview (`MODEL-POSE-PREVIEW`) — Observed auxiliary

<a id="model-pose-preview"></a>

### 12.1 Overview — DTO vs storage

`PosePreview` (và helper `communityPosePreview`) là **navigation DTO / transport projection** giữa card tap và detail screen — **không** canonical entity, **không** persisted, **không** thay `CommunityPose` / API / data source-of-truth.

### 12.2 Field summary

| Field (summary) | Vai trò | Label |
| --- | --- | --- |
| `poseId` | Stable key cho navigation + API detail | **Observed** |
| `imageModel` / thumbnail locator | Hero preview-first trước enrich | **Observed** |
| `name` (nếu có) | Header placeholder | **Observed** |

Không invent schema đầy đủ. SoT comparison: [`CommunityPose`](../../../spec/data/entities/community-pose.md) (canonical public DTO).

### 12.3 Relations

| Relation | Mô tả |
| --- | --- |
| `PosePreview` → detail enrich | `GET /api/community/poses/:id` → `CommunityPose` |
| `Pose` / `MediaAsset` | Không FK — transport only |

### 12.4 Enums

Không áp dụng.

### 12.5 Business rules

Không BR riêng — tuân public detail contract khi enrich.

### 12.6 Traceability — model → API → screen

| Flow | Screen |
| --- | --- |
| List card tap | SCR-003-01-GRD-002 emit `PosePreview` → SCR-003-03-HRO-001 |
| Search result tap | SCR-003-02-RES-003 → SCR-003-03 |
| Enrich | [API-COMMUNITY-02](./apis.md#api-community-02) → `CommunityPose` |

Chi tiết UI: [screens/README.md](./screens/README.md), [SCR-003-03](./screens/scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen).

### 12.7 Evidence

| Label | Ghi chú |
| --- | --- |
| **Observed** | `PoseDetailVoyagerScreen` nhận `PosePreview` |
| **Normative** | Detail contract sau enrich = `CommunityPose` |

---

## 13. Unresolved / open tensions

<a id="models-unresolved"></a>

| ID | Chủ đề | Label | Ghi chú |
| --- | --- | --- | --- |
| U-MODEL-001 | `BR-COMMUNITY-007` namespace | **Unresolved** | API layer (404 unpublished) vs data entity (view-only) — cùng BR ID; record tại §11.5 |
| U-MODEL-002 | FEAT-003 title search `q` | **Unresolved** | Spec **Normative** vs FEAT-003 mock-backed evidence — [apis.md#unresolved](./apis.md#unresolved) |
| U-MODEL-003 | FEAT-003 lifecycle | **Unresolved** | Harness inventory Proposed vs feature `approved` |
| U-MODEL-004 | FEAT-012 durable restore | **Unresolved** | Feature doc **Unresolved** vs **Observed** `CameraSnapshotRepository` — [SCR-001-01 §7](./screens/mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) |
| U-MODEL-005 | FEAT-009 Extract Engine | **Unresolved** | **Observed** provider panel/API vs FEAT-009 evidence gap — [SCR-007-03](./screens/admin/scr-007-03-keys.md#scr-007-03-admin-keys-main) |
| U-MODEL-006 | FEAT-008 Save/account API | **Unresolved** | Save/Unsave + `Account` session chưa proven trong Basic Design slice |
| U-MODEL-007 | `PreparedPoseReference` vs FEAT-012 snapshot | **Unresolved** | SoT BR-PREPREF-002 no relaunch persist vs FEAT-012 settings/pose identity snapshot |
| U-MODEL-008 | `ckh validate` scope | **Unresolved** | `models.md` design summary ngoài supported `ckh validate --kind` artifact kinds — expected unsupported |

Không sửa `docs/spec/**` hay Harness Feature files tại đây — chỉ ghi nhận tension.
