---
schema_version: 1
type: spec
title: Technical Architecture
status: draft
relationships:
  specs:
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
    - "[[model-entity-catalogue]]"
    - "[[erd]]"
    - "[[api-catalogue]]"
  decisions:
    - "[[DEC-001-extraction-provider-selection-policy|DEC-001]]"
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
  source_paths:
    - package.json
    - mobile/iosApp/project.yml
    - mobile/iosApp/Podfile
    - web/admin-ui
    - web/services/pose-extract-server/src
    - web/services/pose-extract-server/scripts/remove_bg_lineart.py
---

# Technical Architecture

Tài liệu kỹ thuật của monorepo `ai-pose`: **công nghệ dùng, build, setup, và
những lưu ý khi làm việc**. Hợp đồng dữ liệu/API và domain model nằm tại
[[data-contract]] và [[api-contract]]; hành vi product theo các Feature trong
`docs/harness/features/`. File này chỉ mô tả cấu trúc kỹ thuật thực thi.

## Tech stack

| Lane | Công nghệ | Version | Ghi chú |
| --- | --- | --- | --- |
| Mobile UI | Kotlin Multiplatform + Compose Multiplatform | Kotlin 2.0.0, Compose 1.6.11, compose-compiler 1.5.10 | target `iosX64` / `iosArm64` / `iosSimulatorArm64`; **không có Android target** |
| Mobile UI | Voyager (navigation), Koin 4.0.0 (DI), Coil 3 (image), coroutines 1.8.0 | — | Koin **giữ 4.0.0** vì 4.1.x yêu cầu Kotlin 2.1+ (ABI klib) |
| Mobile data | SQLDelight 2.0.2, Ktor client 2.3.12, kotlinx-serialization, kotlinx-datetime | — | DB local: `mobile/shared/src/commonMain/sqldelight/` |
| iOS host | SwiftUI + XcodeGen / SwiftPM | Xcode 26.1, iOS 15.0+ | Active project dependencies: `RevenueCat 5.87.1`, `GRDB`, `Kingfisher`, Firebase (Core/Analytics/Crashlytics/Firestore); separate CocoaPods/KMP workspace remains in the repo |
| iOS env config | XcodeGen (`project.yml`) | — | 2 schemes (`Dev`/`Prod`) × 4 configs (`Debug/Release` × `Dev/Prod`) |
| Web/admin | Next.js + React + Tailwind | Next 16.2.3, React 19.2.4, Tailwind 4, TypeScript 6 | `web/admin-ui`; server-side API proxies tới Express |
| API service | Node + Express + TypeScript | Node ≥ 20, Express 5.2.1, TS 6 | `web/services/pose-extract-server`; validation bằng zod 4, log pino |
| DB server | Postgres (production) | `postgres` 3.4.9 driver | `DATABASE_URL`; dev stack dùng Postgres 16 container |
| Object storage | Cloudflare R2 (AWS SDK v3) | — | Cộng đồng poses/community objects |
| Extraction worker | Node/TypeScript + Gemini REST hoặc Higgsfield CLI | — | Worker claim job, tạo provider qua factory, xử lý ảnh kết quả bằng Python lineart remover |
| Deploy | Railway + Docker | — | `railway.toml`, Dockerfile per service |

Nguồn version: `gradle/libs.versions.toml`, `package.json` từng web workspace,
`mobile/iosApp/Podfile.lock`.

## Build từng lane

### Backend (pose-extract-server)

```sh
# từ repo root — npm scripts route tới đúng workspace
npm run backend:test      # vitest run
npm run backend:build     # tsc + copy schema
npm run backend:start     # node dist/index.js
npm run backend:dev       # tsx watch (host)

# worker xử lý extraction job — process riêng
npm --prefix web/services/pose-extract-server run worker        # dev
npm --prefix web/services/pose-extract-server run start:worker  # prod
```

### Extraction worker và provider factory

`worker-main.ts` chạy `worker-loop.ts`; mỗi lượt `processNextJob` claim một
`ExtractionJob`, đọc provider toàn cục từ `ProviderSettingsStore`, rồi gọi
`createPoseExtractorProvider`. Factory có hai nhánh:

- `gemini_native`: `GeminiNativeProvider` lấy API key từ `KeyPoolManager` và gọi
  Gemini REST qua `GeminiService`.
- `higgsfield_cli`: `HiggsfieldCliProvider` spawn lệnh `higgsfield generate create`,
  đọc JSON kết quả và tải ảnh từ result URL; credential nằm ở worker.

Theo [[DEC-001-extraction-provider-selection-policy|DEC-001]], Admin chọn một
provider toàn cục; mặc định là `higgsfield_cli`. Lựa chọn mới có hiệu lực từ job
được claim tiếp theo. Job đang chạy giữ provider đã chọn; Higgsfield thiếu hoặc
hết hạn credential làm job thất bại với mã lỗi tường minh, không tự đổi sang Gemini.

Sau provider, `LineartBackgroundRemover` spawn
`scripts/remove_bg_lineart.py` bằng `PYTHON_BIN` (mặc định `python3`) để tạo
ảnh PNG đã gỡ nền. Có thể tắt bước này bằng `LINEART_BG_REMOVAL_ENABLED=false`;
mọi lỗi spawn, timeout hoặc script thoát lỗi ghi `LINEART_BG_REMOVAL_FAILED`
vào job.

Khi extraction thành công (`succeeded`), worker thực hiện một database transaction duy nhất:
1. Tạo bản ghi `Pose` canonical (`status = 'local'`) với `pose_id` UUID ổn định, `owner_account_id` từ job, và metadata từ `pose_draft` (`name`, `tags`, `description`).
2. Tạo 3 bản ghi `MediaAsset` (`original`, `skeleton`, `thumbnail`) gắn với `pose_id`.
3. Gán `pose_id` vào `extraction_jobs`, cập nhật `status = 'succeeded'`.
4. Giải phóng `result_image_base64` và `source_image_base64` (retention policy).
Quy trình này đảm bảo tính lũy đẳng (idempotent) theo `jobId`. Client không gọi endpoint lưu riêng.

### Admin UI (web/admin-ui)

```sh
npm run lint      # eslint
npm run build     # next build
npm run dev       # next dev
```

### Mobile (KMP + iOS)

```sh
./gradlew :composeApp:compileKotlinIosSimulatorArm64
./gradlew :shared:iosSimulatorArm64Test
```

> ⚠️ `:shared:iosSimulatorArm64Test` hiện **không compile**: `PoseApiServiceTest.kt`
> import `kotlinx.coroutines.test.runTest` mà chưa có dependency tương ứng trong
> `commonTest` của `:shared` (chỉ có ở `iosSimulatorArm64Test`). Biết trước để
> không nhầm là lỗi do thay đổi của mình.

iOS app là host SwiftUI chạy scheme `Dev`/`Prod` sinh từ `project.yml` bằng
XcodeGen. Thay đổi native (Info.plist, pods, configs) phải sửa `project.yml`
rồi regenerate, không sửa tay `.xcodeproj`.

## Setup

### Backend env — `web/services/pose-extract-server/.env`

Bắt buộc (zod validate lúc boot, thiếu là crash):
`DATABASE_URL`, `ADMIN_SECRET`, `SUPABASE_URL`, `SUPABASE_JWT_KEY_ID`,
`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_PUBLIC_URL`.

Có default/safe: `PORT` (3000), `RATE_LIMIT_WINDOW_MS`/`RATE_LIMIT_MAX`
(60s/10 req).

Worker: `HIGGSFIELD_CREDENTIALS_PATH` + `HIGGSFIELD_CLI_TIMEOUT_MS` khi dùng
Higgsfield; `PYTHON_BIN`, `LINEART_BG_SCRIPT_PATH`,
`LINEART_BG_REMOVAL_ENABLED`, `LINEART_BG_REMOVAL_STRENGTH`,
`LINEART_BG_REMOVAL_THRESHOLD`, `LINEART_BG_REMOVAL_SOFTNESS` và
`LINEART_BG_REMOVAL_TIMEOUT_MS` điều khiển bước gỡ nền. Các biến worker này
đọc trực tiếp từ `process.env`, không thuộc zod schema lúc API boot.

> Nguồn sự thật cho config: `web/services/pose-extract-server/src/config/env.ts`.
> Không commit secret thật; `.env.example` chỉ chứa giá trị mẫu.

### Admin UI env — `web/admin-ui/.env.local`

```env
POSE_EXTRACT_SERVER_URL=http://localhost:3001
POSE_EXTRACT_ADMIN_SECRET=change-me
```

Proxies ở `web/admin-ui/src/app/api/admin/` inject secret này trước khi forward
tới Express; client components không bao giờ nhận secret.

### Docker

```sh
npm run docker:dev        # dev stack: Postgres 16 + backend + admin-ui, hot reload
npm run docker:dev:logs
npm run docker:dev:down
docker compose up --build # production-like

# Ports: admin-ui http://localhost:3001/admin · backend http://localhost:3000/api/health · postgres :5433
```

Dev stack mount bind source + dùng volume riêng cho `node_modules` (tránh ghi đè
container). Admin secret đọc từ `web/services/pose-extract-server/.env` qua
`scripts/docker-dev.sh`. Deploy Railway: `railway.toml` (Dockerfile
pose-extract-server, mounts `/app/data` + `/app/higgsfield`).

### iOS Firebase + RevenueCat

- Firebase: plist thật đặt tại `mobile/iosApp/iosApp/GoogleService-Info.plist`
  (git-ignored; chỉ có `.example` trong repo). Cùng plist dùng cho cả `Dev`/`Prod`.
- iOS first paint reads the last successfully fetched `config/app` payload from
  UserDefaults synchronously; compile-time defaults apply only before the first
  successful fetch. A failed/offline fetch preserves the current payload, and a
  successful fetched payload replaces the cache.
- Hide the Poses Jobs entry and reject every `.jobs` route while
  `extractPoseEnabled` is false.
- RevenueCat: key public SDK theo từng scheme từ `Config/*-*.xcconfig`
  (`REVENUECAT_PUBLIC_SDK_KEY`); giá trị thật không commit.
- Chi tiết: [`mobile/iosApp/FIREBASE_SETUP.md`](../../../mobile/iosApp/FIREBASE_SETUP.md),
  [`mobile/iosApp/REVENUECAT_SETUP.md`](../../../mobile/iosApp/REVENUECAT_SETUP.md).

## Những lưu ý khi làm việc

1. **Koin phải là 4.0.0** — 4.1.x cần Kotlin 2.1+ (ABI klib); đang dùng Kotlin 2.0.0.
2. **Không `pod()` cinterop cho Firebase từ Kotlin** — Kotlin 2.0.0 không parse
   được Xcode 26.1 SDK modulemap; Firebase chỉ bridge qua Swift
   (`AppDelegate.swift`). Kotlin chỉ giữ contract/test seam
   (`EndpointPolicy`, `AppStartupConfig`).
3. **XcodeGen là nguồn sự thật cho iOS project** — tạo file mới (Assets, plist,
   source) phải vào `project.yml`, regenerate, kiểm tra `Podfile.lock` không đổi
   vô cớ. Có 4 config `Debug/Release` × `Dev/Prod` ánh xạ native build type.
4. **Gradle build config luôn chỉ `ios*` targets** — không có Android; mọi
   claim "Android parity" là gap chưa giải quyết.
5. **Bắt buộc linker flag `-lsqlite3`** — thêm qua Kotlin/Native (`linkerOpts`)
   và Podfile `post_install` (`OTHER_LDFLAGS`); không bỏ.
6. **Swift 6 strict concurrency bị tắt** (`SWIFT_STRICT_CONCURRENCY = minimal`)
   trong Podfile `post_install` — đừng "sửa" ngược lại.
7. **Framework ComposeApp là static (`isStatic = true`)** cho cả 3 targets.
8. **Worker cần credential của provider được chọn** — Gemini dùng key pool;
   Higgsfield dùng CLI credentials. Thiếu credential Higgsfield làm job fail rõ mã
   lỗi theo DEC-001.
9. **Skeleton từ khóa chuẩn hóa** — theo
   [[pose-domain-glossary]], thuật ngữ extraction
   result là `skeleton`, không dùng `render`/`result image`/`extract`.
10. **Thủ tục khởi động (DB, R2, secret) không đổi** — bất kỳ thay đổi schema
    fetch/khởi tạo runtime phải coi là thay đổi hành vi (xem Feature workflow).

## Boundary & storage

- Mobile: photo bytes trong app-private storage; `Pose` local cache trong SQLDelight
  (`mobile/shared/src/commonMain/sqldelight/`). Không lưu trữ extraction jobs trên thiết bị (server-authoritative).
- Server: Postgres qua `DATABASE_URL` (production/Supabase); `extraction_jobs` lưu `owner_account_id`, `pose_draft` (jsonb), `pose_id`, `hidden_at` và index `(owner_account_id, created_at)`.
- R2: community objects; credential + admin secret chỉ ở server.
- Extraction worker: process riêng, dùng provider factory và Python lineart
  remover; tạo Pose và MediaAssets tự động khi thành công; job state lưu trong Postgres.
- Identity & Jobs: Jobs thuộc về Account trên server; đăng xuất không xóa job; đăng nhập lại hiển thị đầy đủ jobs trên bất kỳ thiết bị nào.
- Extraction API auth (D5): `POST /api/extract-pose` and the legacy single-job read accept either
  an Account session or the admin Bearer secret. With an Account session, the server derives the
  owner from the verified session and ignores client-supplied ownership; with admin Bearer, an
  explicit owner is required. User job routes (`/api/me/extract-jobs/**`) and guide reads require
  an Account session and enforce owner scope. The admin secret stays server-side; an invalid admin
  Bearer may fall through to Account authentication but never grants anonymous access.
- Successful extraction materializes canonical R2 media at UUID-based public URLs. Job list
  `thumbnailUrl` is the materialized thumbnail locator. Once a job has a `poseId`, both transient
  image payload columns (`source_image_base64`, `result_image_base64`) are cleared; the durable
  original/skeleton/thumbnail live in `MediaAsset` instead.

## Verification

Từ repo root:

```sh
npm run backend:test
npm run backend:build
npm run build
./gradlew :composeApp:compileKotlinIosSimulatorArm64 :shared:iosSimulatorArm64Test
ckh validate --all --workspace .
ckh index check --workspace .
```

Build fail là bằng chứng health hiện tại — ghi lại, không lấy `error.log` cũ
thay cho lần chạy mới.
