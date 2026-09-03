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
  decisions: []
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
    - settings.gradle.kts
    - gradle/libs.versions.toml
    - mobile/composeApp
    - mobile/shared
    - web/admin-ui
    - web/services/pose-extract-server/src
---

# Technical Architecture

Tài liệu kỹ thuật của monorepo `ai-pose`: **công nghệ dùng, build, setup, và
những lưu ý khi làm việc**. Hợp đồng dữ liệu/API và domain model nằm tại
[`docs/spec/`](../../spec/README.md); hành vi product theo Feature tại
[`docs/harness/features/`](../features/). File này chỉ mô tả cấu trúc kỹ thuật
thực thi.

## Tech stack

| Lane | Công nghệ | Version | Ghi chú |
| --- | --- | --- | --- |
| Mobile UI | Kotlin Multiplatform + Compose Multiplatform | Kotlin 2.0.0, Compose 1.6.11, compose-compiler 1.5.10 | target `iosX64` / `iosArm64` / `iosSimulatorArm64`; **không có Android target** |
| Mobile UI | Voyager (navigation), Koin 4.0.0 (DI), Coil 3 (image), coroutines 1.8.0 | — | Koin **giữ 4.0.0** vì 4.1.x yêu cầu Kotlin 2.1+ (ABI klib) |
| Mobile data | SQLDelight 2.0.2, Ktor client 2.3.12, kotlinx-serialization, kotlinx-datetime | — | DB local: `mobile/shared/src/commonMain/sqldelight/` |
| iOS host | SwiftUI host + CocoaPods | Xcode 26.1, CocoaPods 1.16.2, iOS 15.0+ | Pods: `MijickCamera ~> 3.0.0`, `RevenueCat ~> 5.87`, Firebase (Core/Analytics/Crashlytics/RemoteConfig) |
| iOS env config | XcodeGen (`project.yml`) | — | 2 schemes (`Dev`/`Prod`) × 4 configs (`Debug/Release` × `Dev/Prod`) |
| Web/admin | Next.js + React + Tailwind | Next 16.2.3, React 19.2.4, Tailwind 4, TypeScript 6 | `web/admin-ui`; server-side API proxies tới Express |
| API service | Node + Express + TypeScript | Node ≥ 20, Express 5.2.1, TS 6 | `web/services/pose-extract-server`; validation bằng zod 4, log pino |
| DB server | Postgres (production) | `postgres` 3.4.9 driver | `DATABASE_URL`; dev stack dùng Postgres 16 container |
| Object storage | Cloudflare R2 (AWS SDK v3) | — | Cộng đồng poses/community objects |
| Extraction worker | Playwright 1.59 | — | Worker xử lý job qua browser session (Gemini app) |
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

# worker (Playwright) — riêng
npm --prefix web/services/pose-extract-server run worker        # dev
npm --prefix web/services/pose-extract-server run start:worker  # prod
npm --prefix web/services/pose-extract-server run worker:preflight  # kiểm tra auth profile
```

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
`DATABASE_URL`, `ADMIN_SECRET`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_PUBLIC_URL`.

Có default/safe: `PORT` (3000), `SUPABASE_URL`/`SUPABASE_JWT_KEY_ID`,
`RATE_LIMIT_WINDOW_MS`/`RATE_LIMIT_MAX` (60s/10 req), `BROWSER_HEADLESS` (true).

Worker: `BROWSER_PROFILE_DIR` (browser profile đã login Gemini),
`HIGGSFIELD_CREDENTIALS_PATH` + `HIGGSFIELD_CLI_TIMEOUT_MS` (nếu dùng Higgsfield).

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
8. **Worker cần browser profile đã login** — không phải config-only; production
   activation chưa được chứng minh chỉ bằng repo config.
9. **Skeleton từ khóa chuẩn hóa** — theo
   [`pose-domain-glossary.md`](pose-domain-glossary.md), thuật ngữ extraction
   result là `skeleton`, không dùng `render`/`result image`/`extract`.
10. **Thủ tục khởi động (DB, R2, secret) không đổi** — bất kỳ thay đổi schema
    fetch/khởi tạo runtime phải coi là thay đổi hành vi (xem Feature workflow).

## Boundary & storage

- Mobile: photo bytes trong app-private storage; metadata SQLDelight
  (`mobile/shared/src/commonMain/sqldelight/`).
- Server: Postgres qua `DATABASE_URL` (production/Supabase); key, community, job
  state không còn SQLite.
- R2: community objects; credential + admin secret chỉ ở server.
- Playwright worker: profile browser riêng, tách biệt khỏi API path trực tiếp.

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