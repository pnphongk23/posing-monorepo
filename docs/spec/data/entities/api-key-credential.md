# ApiKeyCredential

## Description

Provider API key dùng cho extraction ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)). Admin quản lý trên Admin Web ([FEAT-007](../../../harness/features/FEAT-007-operate-pose-content-from-admin-web.md)). Secret không bao giờ trả về client.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | TEXT (UUID) | PK | Server-generated UUID |
| `name` | TEXT | ✓ | Label |
| `apiKey` | TEXT | ✓ | Secret; omit mọi response |
| `status` | TEXT | ✓ (default `active`) | Enum `ApiKeyStatus` |
| `requestsToday` | INTEGER | ✓ (default `0`) | Đếm trong ngày |
| `createdAt` | DATETIME | ✓ | Thời điểm tạo |
| `lastUsedAt` | DATETIME | — | Lần dùng cuối |

## Relationships

- Một `ApiKeyCredential` 1 — 0..* [`ProviderRequestLog`](provider-request-log.md) (`keyId`, ON DELETE SET NULL)

## Business Rules

| ID | Rule |
|---|---|
| BR-KEY-001 | Secret `apiKey` không xuất hiện trên bất kỳ API response nào. |
| BR-KEY-002 | Key `exhausted` được reset định kỳ về `active` và `requestsToday = 0`. |
| BR-KEY-003 | Extraction chọn key `active`; hết quota thì đánh `exhausted` và xoay key còn lại. |
| BR-KEY-004 | Hết key `active` thì extraction thất bại có thể phục hồi (không tuyên bố usable image). |
