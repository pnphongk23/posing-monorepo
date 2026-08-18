# ProviderRequestLog

## Description

Log một lần gọi provider trong extraction ([FEAT-004](../../../harness/features/FEAT-004-extract-reusable-pose-images.md)). Dùng cho chẩn đoán và giám sát usage.

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | INTEGER | PK | Sequential log ID |
| `keyId` | TEXT | — | [`ApiKeyCredential`](api-key-credential.md); NULL nếu key đã xóa |
| `timestamp` | DATETIME | ✓ | Thời điểm ghi |
| `processingTimeMs` | INTEGER | — | Thời gian xử lý |
| `success` | INTEGER | ✓ | `1` thành công, `0` thất bại |
| `errorCode` | TEXT | — | Khi thất bại |

## Relationships

- Nhiều log → một `ApiKeyCredential` (nullable, ON DELETE SET NULL)

## Business Rules

| ID | Rule |
|---|---|
| BR-LOG-001 | Mọi attempt extraction (thành công hoặc thất bại) đều ghi một log. |
| BR-LOG-002 | `keyId` NULL khi không gắn được key hoặc key đã xóa. |
