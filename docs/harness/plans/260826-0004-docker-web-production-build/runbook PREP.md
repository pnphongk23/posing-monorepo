# Web production Docker build PREP

Ngày: 2026-08-26  
Scope: `web/services/pose-extract-server` (backend) và `web/admin-ui` (frontend).  
Không thuộc scope: `sub2api/`. Không deploy, không push image/registry, không chạy container production trong task này.

## Kết quả xác minh lần này

| Service | Kết quả | Thời gian/log |
|---|---|---|
| `pose-extract-server` | **PASS** — image `ai-pose-pose-extract-server:latest` | ~2 phút; [backend-build-1.log](backend-build-1.log) |
| `admin-ui` | **PASS** — image `ai-pose-admin-ui:latest` | ~33 giây; [frontend-build-1.log](frontend-build-1.log) |

Kết quả đạt được sau khi khôi phục Docker Desktop (quit + relaunch; Engine trước đó wedged không trả lời socket, đúng như ghi nhận lần thử đầu trong `backend-build.log`/`frontend-build.log` — các log đó giữ làm lịch sử). Build thật chạy lần lượt từng service với `Dockerfile` hiện tại (đã chỉnh thứ tự Playwright), kết quả đều PASS.

- Backend: `tsc` + `copy-schema.mjs` pass (kể cả `src/services/higgsfieldCliProvider.ts` đang modified bởi lane khác vẫn compile sạch); Higgsfield CLI `@higgsfield/cli@1.1.23` cài + `--version` pass; Playwright `install-deps` + Chromium 147 (playwright v1217, arm64) + headless shell tải về `/root/.cache/ms-playwright` pass; `pip3` cài pillow/numpy pass.
- Frontend: `npm ci` (node:22-alpine), `next build` 16.2.3 (Turbopack) `✓ Compiled successfully in 1706ms`, copy `.next/standalone` + `.next/static` + `public`, runner `server.js` pass.
- `docker compose config --quiet` pass với `ADMIN_SECRET=prep-placeholder`; khi không export biến này Compose chỉ cảnh báo blank (exit 0). Placeholder chỉ dùng để kiểm tra cấu hình, không phải production secret.

## Audit build

- Backend build context là repo root (`.`), Dockerfile là `web/services/pose-extract-server/Dockerfile`.
- Frontend build context là `web/admin-ui`, Dockerfile là `Dockerfile`.
- Cả hai có `package-lock.json` và dùng `npm ci`.
- Backend dùng Node `20-bookworm-slim`, TypeScript build ở stage `build`, runtime chạy Node API và worker cùng container.
- Frontend dùng Node `22-alpine`, Next `output: "standalone"` khớp với việc copy `.next/standalone`, `.next/static`, `public` và chạy `server.js`.
- Backend runtime cài Python/Pillow/NumPy, CA certificates, Higgsfield CLI `@higgsfield/cli@1.1.23`, Playwright Chromium và OS dependencies cần cho browser extraction.
- Đã sửa thứ tự Playwright: `npm ci --omit=dev` trước, sau đó gọi `./node_modules/.bin/playwright ...`; browser/CLI không còn bị `npx` tải tạm ngoài package đã lock.
- Các Dockerfile không bake `.env` vào image; backend `.dockerignore` loại `.env`/`.env.*`, frontend context cũng không chứa backend secrets.

## Lệnh build chuẩn (đã xác minh chạy được)

Chạy từ repo root. Cấp `ADMIN_SECRET` qua shell/project env để frontend nhận đúng secret; không ghi secret vào file tracked hoặc image build args. Yêu cầu Docker Engine healthy (kiểm tra qua `curl --max-time 5 --unix-socket "$HOME/.docker/run/docker.sock" http://localhost/_ping` trả `OK`).

```bash
export ADMIN_SECRET='<same value as backend ADMIN_SECRET>'
docker compose build --progress=plain pose-extract-server
docker compose build --progress=plain admin-ui
docker compose build --progress=plain pose-extract-server admin-ui
docker compose config --quiet
```

Lệnh cuối trong ba lệnh build là smoke check compose-level đầy đủ; chạy riêng từng service giúp cô lập lỗi. Có thể thêm `--pull` trong lần chuẩn bị release khi muốn lấy base image mới:

```bash
docker compose build --pull --progress=plain pose-extract-server admin-ui
```

## Runtime configuration cần chuẩn bị

### Backend bắt buộc theo schema

Chỉ tên biến, không ghi giá trị:

- `DATABASE_URL`
- `ADMIN_SECRET`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_PUBLIC_URL`

### Backend runtime/feature variables

Compose đặt sẵn `NODE_ENV=production`, `PORT=3000`, `BROWSER_PROFILE_DIR=/app/data/browser-profile`, `HIGGSFIELD_CREDENTIALS_PATH=/app/higgsfield/credentials.json`, `HOME=/app/higgsfield`, và `HIGGSFIELD_CLI_TIMEOUT_MS`.

Các biến tùy chọn/feature được code hỗ trợ gồm: `APP_VERSION`, `COMMUNITY_UPLOAD_DIR`, `RATE_LIMIT_WINDOW_MS`, `RATE_LIMIT_MAX`, `BROWSER_APP_URL`, `BROWSER_HEADLESS`, `BROWSER_EXECUTABLE_PATH`, `BROWSER_CHROME_CHANNEL`, `PLAYWRIGHT_CHROME_CHANNEL`, `PLAYWRIGHT_CHROMIUM_PATH`, `BROWSER_PROMPT`, `BROWSER_TIMEOUT_MS`, `WORKER_DEBUG_DIR`, `WORKER_MOCK_BROWSER`, `WORKER_POLL_INTERVAL_MS`, `WORKER_STALE_LOCK_SECONDS`, `HIGGSFIELD_CLI_MODEL`, `LINEART_BG_REMOVAL_ENABLED`, `LINEART_BG_REMOVAL_STRENGTH`, `LINEART_BG_REMOVAL_THRESHOLD`, `LINEART_BG_REMOVAL_SOFTNESS`, `LINEART_BG_REMOVAL_TIMEOUT_MS`, `LINEART_BG_SCRIPT_PATH`, `PYTHON_BIN`, và `REPLICATE_API_TOKEN` nếu route tương ứng được dùng.

Higgsfield CLI còn cần credentials thực tế tại `/app/higgsfield/credentials.json` (được giữ ngoài image qua volume). Không commit hoặc đưa nội dung credential vào runbook.

### Frontend

- `POSE_EXTRACT_SERVER_URL` — Compose hiện đặt `http://pose-extract-server:3000` trên network nội bộ.
- `POSE_EXTRACT_ADMIN_SECRET` — Compose lấy từ `${ADMIN_SECRET}` của shell/project environment. `env_file` của backend không tự truyền biến sang frontend; phải cấp cùng giá trị `ADMIN_SECRET` khi render/run Compose.
- `NODE_ENV=production`.
- `PORT` mặc định trong image là `3000`.

## Ports, names, health và volumes

| Service | Container name | Container port | Host mapping |
|---|---|---:|---:|
| Backend | `pose-extract-server` | `3000` | `3000:3000` |
| Frontend | `pose-admin-ui` | `3000` | `3001:3000` |

Production Compose hiện không định nghĩa labels. Service discovery dùng tên `pose-extract-server` trên Compose network.

- Backend health endpoint đã có: `GET /api/health`, response thành công có `status: "ok"`.
- Production Compose hiện chưa có `healthcheck:` cho backend hoặc frontend; `depends_on` của frontend hiện chỉ biểu thị start order, không chờ backend healthy.
- Frontend chưa có healthcheck stanza riêng trong compose. Runtime smoke test sau này cần kiểm tra URL frontend và `/api/health` backend trong môi trường đã được cấp secrets.
- `./.docker-persist/data:/app/data` giữ browser profile tại `/app/data/browser-profile`.
- `./.docker-persist/higgsfield:/app/higgsfield` giữ Higgsfield credentials/profile; không bake credentials vào image.
- Production image không có volume database. Database là Postgres bên ngoài qua `DATABASE_URL`; không tạo hoặc dùng SQLite volume.

## Chuẩn bị tag image cho giai đoạn sau

Hiện chưa tạo/push tag nào. Khi bước registry được PO cho phép, dùng immutable tag theo full Git SHA, ví dụ `pose-extract-server:<git-sha>` và `admin-ui:<git-sha>`, có thể thêm release alias sau khi đã kiểm tra digest. Registry, repository names, credentials và policy retention vẫn cần quyết định riêng.

## Thay đổi và SHA

- `web/services/pose-extract-server/Dockerfile`: trước các dòng 25-34 gọi `npx playwright install-deps/install` trước `npm ci`; sau các dòng 25-31 cài bằng binary Playwright local (`./node_modules/.bin/playwright`) sau `npm ci --omit=dev`. Blob SHA trước: `1cc4c6f51121ad83b519be7ebc8aa69bcb5d12c8`; sau: `a33de3923edd6986236aa0aaa6e124c5151de743`. Thay đổi có từ lần chuẩn bị trước, **được xác minh bằng build PASS** trong lần này.
- `web/admin-ui/Dockerfile`: không đổi (SHA trùng HEAD). Blob SHA: `b9ab188c80ca7234a3d4ad22992b5900bda5d306`.
- `docker-compose.yml`: không đổi (SHA trùng HEAD). Blob SHA: `4912052a3346d268f306c71b0b4bf12ea98f1627`.
- `web/services/pose-extract-server/Dockerfile.dev`: không đổi. `web/admin-ui/Dockerfile.dev`: không đổi.
- Log build PASS (`backend-build-1.log`, `frontend-build-1.log`) không chứa production secret values. Các log block cũ (`backend-build.log`, `frontend-build.log`) giữ làm lịch sử.

## Quan sát cần PO biết

- `.env` hiện tại của backend (env_file trong production compose) còn mang `DATABASE_PATH` (SQLite legacy); compose comment + `.env.example` + code (client `postgres`) đều dùng `DATABASE_URL`. Khi chuẩn bị production phải cấp `DATABASE_URL` và bỏ/không dùng `DATABASE_PATH` — đây là việc runtime của phase deploy, không nằm ở build.
- `web/admin-ui/.env.local` đang được git track (chứa `REPLICATE_API_TOKEN`, `POSE_EXTRACT_SERVER_URL`, `POSE_EXTRACT_ADMIN_SECRET`); `.dockerignore` của admin-ui chưa loại `.env*` (backend đã loại). Image runner cuối không chứa file này (chỉ copy standalone/static/public), nhưng layer builder có dính file — nên thêm `.env*` vào admin-ui `.dockerignore` trước khi đẩy production.
- Container dev `pose-admin-ui-dev` đang `Restarting (127)` — lỗi thuộc dev stack, ngoài scope lane này; cần lane vận hành dev kiểm tra.
- Docker Engine local wedged 2 lần (một lần trước khi lane này chạy, một lần ngay sau khi cả 2 build PASS) — cùng failure mode: daemon im lặng trên socket sau hoạt động build. Môi trường local không ổn định; khi đẩy production nên build/CI trên runner riêng thay vì máy local này.
- Image size/digest chưa capture được vì daemon wedged lại ngay sau build; cần lấy lại `docker images`/`docker inspect` khi Engine healthy.

## Giới hạn và việc còn lại trước production thật

- Build PASS đã xác minh trên máy này với Docker Engine được khôi phục; nhưng daemon local không ổn định nên khuyến nghị re-verify image metadata (size/digest) khi Engine healthy.
- Chưa chạy container, chưa test runtime/health, chưa test Playwright/Higgsfield browser profile, chưa test kết nối Postgres/R2.
- Chưa cấu hình production secrets thật; cần PO cấp tên/giá trị qua secret manager cho `DATABASE_URL`, `ADMIN_SECRET`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_PUBLIC_URL`; và credentials file cho Higgsfield CLI. `REPLICATE_API_TOKEN` chỉ cần nếu feature đó được bật.
- Cần quyết định healthcheck/container orchestration, persistent volume implementation, registry/tag policy, domain/TLS, resource limits, restart policy và secret injection cho môi trường production.
- Cần chạy lại build đầy đủ, kiểm tra image metadata/digest, rồi mới lập kế hoạch deploy riêng. Không thực hiện các bước đó trong PREP này.
