# pose-extract-server

Express + TypeScript service để nhận ảnh người dùng, gọi Gemini và trả về ảnh pose.

## Prerequisites

- Node.js >= 20
- A PostgreSQL database (hosted — e.g. Supabase — or local)
- A Cloudflare R2 bucket for community pose images (required in production; the
  service validates R2 env vars on boot)

## Environment variables

Tạo file `.env` từ `.env.example`:

```bash
cp .env.example .env
```

Required variables (service fails to boot without these):

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (e.g. Supabase pooler URL) |
| `ADMIN_SECRET` | Bearer token for `/api/admin/*` endpoints |
| `R2_ACCOUNT_ID` | Cloudflare R2 account ID |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 access key ID |
| `R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret access key |
| `R2_BUCKET` | Cloudflare R2 bucket name (e.g. `pose-dev`) |
| `R2_PUBLIC_URL` | Public base URL for the R2 bucket (e.g. `https://pub-xxx.r2.dev`) |

Optional variables (defaults apply when unset):

| Variable | Default | Notes |
| --- | --- | --- |
| `NODE_ENV` | `development` | `production` disables local community file serving |
| `PORT` | `3000` | HTTP listen port |
| `RATE_LIMIT_WINDOW_MS` | `60000` | Extract endpoint rate-limit window |
| `RATE_LIMIT_MAX` | `10` | Max requests per window |
| `COMMUNITY_UPLOAD_DIR` | `data/community` | Local dev only — not used in production (R2 is used instead) |
| `BROWSER_APP_URL` | `https://gemini.google.com/app` | Target app for browser automation |
| `BROWSER_PROFILE_DIR` | `data/browser-profile` | Chrome profile for the worker |
| `BROWSER_HEADLESS` | `true` | Run the worker browser headless |

## Setup (fresh start)

1. Create `.env` (see above) with your `DATABASE_URL`, `ADMIN_SECRET`, and R2 vars.
2. Install dependencies:

   ```bash
   npm install
   ```

3. Apply the schema. The server applies `src/db/schema.sql` automatically on
   boot (`applySchema`), so simply starting the server is enough:

   ```bash
   npm run dev
   ```

   Alternatively, apply the schema manually before first boot:

   ```bash
   psql "$DATABASE_URL" -f src/db/schema.sql
   ```

4. Verify the health endpoint:

   ```bash
   curl http://localhost:3000/api/health
   ```

> **Note:** There is no SQLite. The service uses PostgreSQL exclusively via
> `DATABASE_URL`. Do not set `DATABASE_PATH`.

## Local dev vs production

- **Local dev:** community pose images are written to `COMMUNITY_UPLOAD_DIR`
  (`data/community` by default) and served via Express static middleware.
- **Production:** `COMMUNITY_UPLOAD_DIR` is ignored. Community images are
  uploaded to Cloudflare R2 (admin flow: presigned PUT URL → upload → save
  metadata) and served from `R2_PUBLIC_URL`. The `/community` static path is not
  mounted in production.

## Run local

```bash
npm install
npm run dev
```

Health check:

```bash
curl http://localhost:3000/api/health
```

## Admin setup API key

1. Tạo API key đầu tiên:

```bash
curl -X POST http://localhost:3000/api/admin/keys \
  -H "Authorization: Bearer $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "key1",
    "apiKey": "AIza..."
  }'
```

2. Kiểm tra danh sách key:

```bash
curl http://localhost:3000/api/admin/keys \
  -H "Authorization: Bearer $ADMIN_SECRET"
```

## Extract pose endpoint

Request:

```bash
curl -X POST http://localhost:3000/api/extract-pose \
  -F "image=@/absolute/path/to/photo.jpg"
```

Success response:

```json
{
  "success": true,
  "data": {
    "imageBase64": "iVBORw0KGgo...",
    "mimeType": "image/png",
    "processingTimeMs": 4523
  },
  "meta": {
    "keyUsed": "key2",
    "quotaRemaining": "~80%"
  }
}
```

Error matrix:

- `400 INVALID_IMAGE`: thiếu file `image` hoặc mime type không hợp lệ
- `413 IMAGE_TOO_LARGE`: file > 10MB
- `429 RATE_LIMITED`: vượt hạn mức endpoint
- `503 ALL_KEYS_EXHAUSTED`: tất cả key bị exhausted vì quota/rate-limit từ provider
- `500 GEMINI_ERROR`: lỗi provider không thuộc quota

## Verification checklist

- `npm test`
- `npm run lint`
- `npm run build`
- Tạo ít nhất 2 key qua admin API
- Gọi `POST /api/extract-pose` với ảnh JPEG/PNG hợp lệ
- Kiểm tra failover: mô phỏng key1 quota exhausted, request vẫn success bằng key2
- Kiểm tra `request_logs` có cả bản ghi fail (quota) và success
