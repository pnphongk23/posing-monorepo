# Tài liệu API

Nguồn sự thật duy nhất cho API contract của `pose-extract-server` (Express service).

## Cấu trúc

| Tệp/Thư mục | Nội dung |
|---|---|
| [`openapi.yaml`](openapi.yaml) | OpenAPI 3.1 — contract đầy đủ: paths, schemas, status codes |
| [`conventions.md`](conventions.md) | Quy ước URL, auth, pagination, errors, datetime |
| [`modules/`](modules/) | API docs nhóm theo domain: health, extract-pose, community, admin-keys, admin-community, jobs |
| [`CHANGELOG.md`](CHANGELOG.md) | Lịch sử thay đổi tài liệu API |

## Routes overview

| Module | Path prefix | Auth | File |
|---|---|---|---|
| Health | `GET /api/health` | None | [`modules/health.md`](modules/health.md) |
| Extract Pose | `POST /api/extract-pose` | None (rate limited) | [`modules/extract-pose.md`](modules/extract-pose.md) |
| Community (public) | `GET /api/community/poses[/:id]` | None | [`modules/community.md`](modules/community.md) |
| Admin Keys | `/api/admin/keys[/:id]` | Bearer admin | [`modules/admin-keys.md`](modules/admin-keys.md) |
| Admin Community | `/api/admin/community/poses[/upload-url]` | Bearer admin | [`modules/admin-community.md`](modules/admin-community.md) |
| Admin Jobs | `GET /api/admin/jobs/:jobId` | Bearer admin | [`modules/admin-jobs.md`](modules/admin-jobs.md) |

Tất cả schemas request/response: xem `openapi.yaml`.
