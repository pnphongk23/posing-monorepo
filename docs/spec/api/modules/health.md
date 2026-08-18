# Module: Health

## GET /api/health

Kiểm tra trạng thái server. Không có business logic.

**Authentication / Permission:** Không yêu cầu.

**Request:** Không có query params, body, hoặc auth.

**Response:** Xem operationId `getHealth` trong [openapi.yaml](../openapi.yaml).

```json
{ "status": "ok", "uptime": 123.4, "version": "1.0.0" }
```

**Business Rules:** Không có.

**Errors:** Generic server middleware áp dụng (`500 INTERNAL_SERVER_ERROR`).
