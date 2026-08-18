> **⚠️ Tài liệu lịch sử.** Contract chính thức đã chuyển sang [`docs/spec/api/`](spec/api/README.md).
> Xem [`docs/spec/api/openapi.yaml`](spec/api/openapi.yaml) cho schemas đầy đủ và [`docs/spec/api/conventions.md`](spec/api/conventions.md) cho quy ước.
> [`docs/spec/api/modules/community.md`](spec/api/modules/community.md) — public community routes.
> [`docs/spec/api/modules/admin-community.md`](spec/api/modules/admin-community.md) — admin community routes.
> File này được giữ nguyên như tài liệu lịch sử hỗ trợ; không chỉnh sửa thêm.

# Community Poses API

> **Current contract (2026-08-09):** Public read endpoints and admin listing are current. The admin UI submits `multipart/form-data` to `POST /api/admin/community/poses`, which enqueues an extraction job and returns `202`. The `/upload-url` helper still exists, but there is currently no metadata-only `fileKey` POST path that completes that presigned flow.

**Production base URL:** `https://pose-extract-server-production.up.railway.app`  
**Local dev base URL:** `http://localhost:3001`

> `imagePath` is always a **full URL** (e.g. `https://pub-fa04b9ec834d4ae9b1e7fc9a8ab0eea7.r2.dev/community/abc.png`).  
> Use it directly as `<img src={pose.imagePath} />` — no prefix needed.

---

## Data Types

```ts
interface CommunityPose {
  id: string;               // UUID
  name: string;
  imagePath: string;        // Full URL — use directly as <img src>
  thumbnailPath: string | null;
  tags: string[];
  difficulty: "beginner" | "intermediate" | "advanced" | null;
  description: string | null;
  bodyParts: string[];
  status: "draft" | "published";
  uploadedAt: string;       // ISO 8601, e.g. "2026-04-21T10:00:00.000Z"
  downloadCount: number;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
}
```

---

## Public Endpoints (no auth required)

### GET /api/community/poses — List published poses

**Query params**

| Param        | Type                                                   | Default | Description           |
|--------------|--------------------------------------------------------|---------|-----------------------|
| `page`       | number                                                 | `1`     | Page number           |
| `limit`      | number (max 100)                                       | `20`    | Items per page        |
| `difficulty` | `"beginner"` \| `"intermediate"` \| `"advanced"`       | —       | Filter by difficulty  |
| `tag`        | string                                                 | —       | Filter by tag (exact) |

**Response `200`**

```json
{
  "data": [CommunityPose],
  "pagination": { "page": 1, "limit": 20, "total": 42 }
}
```

**Examples**

```ts
const BASE_URL = "https://pose-extract-server-production.up.railway.app";

// First page
const res = await fetch(`${BASE_URL}/api/community/poses`);
const { data, pagination } = await res.json();

// Filter by difficulty
const res = await fetch(`${BASE_URL}/api/community/poses?difficulty=beginner`);

// Filter by tag + paginate
const res = await fetch(`${BASE_URL}/api/community/poses?tag=yoga&page=2&limit=10`);
```

---

### GET /api/community/poses/:id — Get pose by ID

Returns a single published pose. Also increments `downloadCount`.

**Response `200`**

```json
{ "data": CommunityPose }
```

**Response `404`**

```json
{ "error": { "code": "NOT_FOUND", "message": "Pose not found" } }
```

**Example**

```ts
const res = await fetch(`${BASE_URL}/api/community/poses/${id}`);
if (!res.ok) {
  const { error } = await res.json();
  console.error(error.message); // "Pose not found"
  return;
}
const { data: pose } = await res.json();
// pose.imagePath is a full URL — use directly
<img src={pose.imagePath} alt={pose.name} />
```

---

## Admin Endpoints

All admin endpoints require:

```
Authorization: Bearer <ADMIN_SECRET>
```

Returns `401 Unauthorized` if the header is missing or wrong.

---

### POST /api/admin/community/poses/upload-url — Get presigned upload URL

Request a presigned PUT URL to upload an image directly to R2.

**Allowed MIME types:** `image/png`, `image/jpeg`, `image/webp`

**Request body**

```json
{
  "fileName": "warrior-pose.png",
  "mimeType": "image/png"
}
```

**Response `200`**

```json
{
  "data": {
    "uploadUrl": "https://...",
    "fileKey": "community/<uuid>.png"
  }
}
```

**Response `400`** — invalid mimeType

```json
{
  "error": {
    "code": "BAD_REQUEST",
    "message": "mimeType \"image/bmp\" is not allowed. Allowed types: image/png, image/jpeg, image/webp"
  }
}
```

---

### PUT \<uploadUrl\> — Upload file directly to R2

Upload the file **directly to R2** using the presigned URL — do NOT go through the server.

```
PUT <uploadUrl>
Content-Type: <mimeType>
Body: <binary file data>
```

- URL expires in **60 seconds**
- `Content-Type` must match the `mimeType` used to request the URL
- On success: R2 returns `200` with empty body

**Example (browser)**

```ts
const fileInput = document.querySelector<HTMLInputElement>('input[type="file"]')!;
const file = fileInput.files![0];

// Step 1: Get presigned URL
const urlRes = await fetch(`${BASE_URL}/api/admin/community/poses/upload-url`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${ADMIN_SECRET}`,
  },
  body: JSON.stringify({ fileName: file.name, mimeType: file.type }),
});
const { data: { uploadUrl, fileKey } } = await urlRes.json();

// Step 2: Upload directly to R2
const uploadRes = await fetch(uploadUrl, {
  method: "PUT",
  headers: { "Content-Type": file.type },
  body: file,
});
if (!uploadRes.ok) throw new Error("R2 upload failed");

// Step 3: Save metadata (see below)
```

---

### POST /api/admin/community/poses — Submit pose and enqueue extraction

Send one `multipart/form-data` request. The Next.js admin proxy uses this contract.

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `image` | PNG/JPEG/WEBP file | yes | Maximum 10 MB |
| `name` | string | yes | Non-empty |
| `bodyParts` | JSON string array or comma-separated string | yes | Must contain at least one item |
| `tags` | JSON string array or comma-separated string | no | Defaults to empty |
| `difficulty` | beginner/intermediate/advanced | no | Defaults to null |
| `description` | string | no | Defaults to null |
| `status` | draft/published | no | Defaults to draft |

**Response `202`**

```json
{
  "data": {
    "pose": { "id": "...", "name": "Warrior Pose", "status": "draft" },
    "jobId": "...",
    "status": "queued"
  }
}
```

The `imagePath` is derived from the configured R2 public URL and generated community key. Extraction completes asynchronously through the worker; poll the protected job-status endpoint used by the admin integration when job progress is needed.

**Response `400`** uses `BAD_REQUEST` for invalid metadata or `INVALID_IMAGE` for a missing, unsupported, or oversized image. **Response `500`** uses `QUEUE_WRITE_FAILED` when enqueue cannot be completed.

---

### GET /api/admin/community/poses — List all poses (admin)

Returns both draft and published poses sorted by newest first.

**Query params:** `page` (default 1), `limit` (default 50, max 100)

**Response `200`**

```json
{
  "data": [CommunityPose],
  "pagination": { "page": 1, "limit": 50, "total": 10 }
}
```

---

## Current Multipart Upload Flow (TypeScript helper)

```ts
const BASE_URL = "https://pose-extract-server-production.up.railway.app";

async function uploadPose(
  file: File,
  meta: {
    name: string;
    tags?: string[];
    difficulty?: "beginner" | "intermediate" | "advanced" | null;
    description?: string;
    bodyParts: string[];
    status?: "draft" | "published";
  },
  adminSecret: string
): Promise<CommunityPose> {
  const form = new FormData();
  form.append("image", file);
  form.append("name", meta.name);
  form.append("tags", JSON.stringify(meta.tags ?? []));
  form.append("difficulty", meta.difficulty ?? "");
  form.append("description", meta.description ?? "");
  form.append("bodyParts", JSON.stringify(meta.bodyParts ?? []));
  form.append("status", meta.status ?? "draft");

  const response = await fetch(`${BASE_URL}/api/admin/community/poses`, {
    method: "POST",
    headers: { Authorization: `Bearer ${adminSecret}` },
    body: form,
  });
  if (!response.ok) throw new Error(`community upload failed: ${response.status}`);
  const { data } = await response.json();
  return data.pose;
}
```

---

## Error Format

All errors follow this shape:

```json
{
  "error": {
    "code": "NOT_FOUND" | "BAD_REQUEST" | "INVALID_IMAGE" | "UNAUTHORIZED" | "QUEUE_WRITE_FAILED" | "INTERNAL_SERVER_ERROR",
    "message": "Human-readable message"
  }
}
```

| Code | HTTP | When |
|------|------|------|
| `UNAUTHORIZED` | 401 | Missing or wrong `Authorization` header on admin endpoints |
| `BAD_REQUEST` | 400 | Missing required field, invalid mimeType, schema validation failure |
| `INVALID_IMAGE` | 400 | Missing, unsupported, or oversized multipart image |
| `NOT_FOUND` | 404 | Pose not found or not published |
| `QUEUE_WRITE_FAILED` | 500 | Community extraction job could not be enqueued |
| `INTERNAL_SERVER_ERROR` | 500 | Unexpected server error |
