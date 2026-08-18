# Module: Admin Keys

Quản lý Gemini API keys. Tất cả routes yêu cầu `Authorization: Bearer <ADMIN_SECRET>`.

## GET /api/admin/keys

Lấy danh sách tất cả API keys (secret omitted).

**Authentication / Permission:** Bearer admin.

**Request:** Không có params. Xem operationId `listAdminKeys` trong [openapi.yaml](../openapi.yaml).

**Response:** `200` `{ data: ApiKeyPublic[] }`. Field `apiKey` bị loại bỏ. Xem `listAdminKeys`.

**Errors:** `401 UNAUTHORIZED`, `429 RATE_LIMITED`, `500`.

---

## POST /api/admin/keys

Tạo API key mới.

**Authentication / Permission:** Bearer admin.

**Request:** JSON body. Xem operationId `createAdminKey` trong [openapi.yaml](../openapi.yaml).

**Response:** `201` `{ data: ApiKeyPublic }`. Secret bị loại bỏ.

**Errors:** `400 BAD_REQUEST`, `401`, `429`, `500`.

---

## PATCH /api/admin/keys/:id

Cập nhật status của key.

**Authentication / Permission:** Bearer admin.

**Request:** JSON `{ status }`. Xem operationId `updateAdminKey`.

**Response:** `200` `{ data: ApiKeyPublic }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-KEY-005 | Status phải là `active`, `disabled`, hoặc `exhausted`. |

**Errors:** `400 BAD_REQUEST`, `401`, `404 NOT_FOUND`, `429`, `500`.

---

## DELETE /api/admin/keys/:id

Xóa API key.

**Authentication / Permission:** Bearer admin.

**Request:** Không có body. Xem operationId `deleteAdminKey`.

**Response:** `204` empty.

**Errors:** `401`, `404 NOT_FOUND`, `429`, `500`.

---

## POST /api/admin/keys/reset

Reset `requests_today = 0` cho tất cả keys; keys `exhausted` trở về `active`.

**Authentication / Permission:** Bearer admin.

**Request:** Không có body. Xem operationId `resetAdminKeys`.

**Response:** `200` `{ data: { updated: number } }`.

**Business Rules:**

| ID | Rule |
|---|---|
| BR-KEY-002 | Keys `exhausted` được set về `active`; keys `disabled` không thay đổi. |

**Errors:** `401`, `429`, `500`.
