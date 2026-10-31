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
    - mobile/iosApp/iosApp
    - mobile/iosApp/iosAppTests
    - web/admin-ui
    - web/services/pose-extract-server/src
    - web/services/pose-extract-server/scripts/remove_bg_lineart.py
    - scripts/ios-verify.sh
    - scripts/git-hooks/pre-commit
    - .swiftlint.yml
    - .swiftformat
---

# Technical Architecture

Tài liệu kỹ thuật của monorepo `ai-pose`: **công nghệ dùng, build, setup, và
những lưu ý khi làm việc**. Hợp đồng dữ liệu/API và domain model nằm tại
[[data-contract]] và [[api-contract]]; hành vi product theo các Feature trong
`docs/harness/features/`. File này chỉ mô tả cấu trúc kỹ thuật thực thi.

## Tech stack

| Lane | Công nghệ | Version | Ghi chú |
| --- | --- | --- | --- |
| Mobile UI | SwiftUI (native iOS) | Swift 6.0, iOS 15.0+ | `mobile/iosApp`; **không có Android target** |
| Mobile state/DI/networking | MVVM (`*Feature` view model), hand-wired service locator, URLSession | — | `mobile/iosApp/iosApp/Core/Network/ServiceLocator.swift` |
| Mobile data | GRDB 7.6.0 (SQLite) | — | DB local + schema parity guard: `mobile/iosApp/iosApp/Core/Database/` |
| iOS host | SwiftUI + XcodeGen / SwiftPM | Xcode 26.1, iOS 15.0+ | Active project dependencies: `RevenueCat 5.87.1`, `GRDB 7.6.0`, `Kingfisher 8.12.0`, Firebase 12.10.0 (Core/Analytics/Crashlytics/Firestore) |
| iOS env config | XcodeGen (`project.yml`) | — | 2 schemes (`Dev`/`Prod`) × 4 configs (`Debug/Release` × `Dev/Prod`) |
| Web/admin | Next.js + React + Tailwind | Next 16.2.3, React 19.2.4, Tailwind 4, TypeScript 6 | `web/admin-ui`; server-side API proxies tới Express |
| API service | Node + Express + TypeScript | Node ≥ 20, Express 5.2.1, TS 6 | `web/services/pose-extract-server`; validation bằng zod 4, log pino |
| DB server | Postgres (production) | `postgres` 3.4.9 driver | `DATABASE_URL`; dev stack dùng Postgres 16 container |
| Object storage | Cloudflare R2 (AWS SDK v3) | — | Cộng đồng poses/community objects |
| Extraction worker | Node/TypeScript + Gemini REST hoặc Higgsfield CLI | — | Worker claim job, tạo provider qua factory, xử lý ảnh kết quả bằng Python lineart remover |
| Deploy | Railway + Docker | — | `railway.toml`, Dockerfile per service |

Nguồn version: `mobile/iosApp/project.yml` (SwiftPM `exactVersion` pins) cùng
`mobile/iosApp/iosApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
`package.json` từng web workspace.

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

### Mobile (native iOS)

```sh
(cd mobile/iosApp && xcodegen generate)   # khi project.yml/source/dependency đổi
xcodebuild test -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev \
  -destination 'platform=iOS Simulator,name=<available iPhone>'
xcodebuild build -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev \
  -destination 'generic/platform=iOS Simulator'
```

> Gradle/Kotlin build (`./gradlew …`) đã retired 2026-09-13 cùng migration
> KMP → native; đừng khôi phục lại `gradlew`, `gradle.properties` hay lane
> `mobile/composeApp`.

## iOS app architecture and conventions

Cách giữ cho `mobile/iosApp` sửa được về lâu dài: ít luật, rẻ để chạy, không refactor lớn.
**Quyết định đã chốt**: giữ SwiftUI + MVVM, và thêm *unidirectional state* **bên trong từng
model**. Không TCA, không Redux, không viết lại app. Các mục dưới đây là chuẩn để review và để
worker tự kiểm — không mở lại quyết định này trong một packet feature.

### Layers

```text
View (SwiftUI)  →  Model (State + Action)  →  Service / Port  →  Store (GRDB, UserDefaults, HTTP)
```

- **View** chỉ render `model.state` và gọi `model.send(_:)`. Không business rule, không I/O,
  không `Task` tự sửa state. View là hàm của state.
- **Model**: một `@MainActor final class …: ObservableObject` cho mỗi feature, sở hữu đúng
  một nested `struct State: Equatable` và một nested `enum Action`. Biến duy nhất là
  `@Published private(set) var state`. Chỉ có **một cửa vào mutate**: `func send(_ action: Action)`.
- **Pure transition**: toàn bộ logic nằm ở `static func transition(_ state: State, _ action: Action) -> (State, [Effect])`
  — thuần, không `await`, không đọc singleton, không chạm UI. `send(_:)` chỉ gọi `transition`
  rồi chạy các `Effect` (gọi service) và đưa state mới vào. Nhờ vậy test được **không cần UI,
  không cần simulator**.
- **Service / Port**: side effect đi qua protocol (port) do model nhận từ ngoài, ví dụ
  `PurchaseGateway`, `TokenStoring`, `PoseService`. Model không tự `URLSession`/`StoreKit`/GRDB.
- **Store**: GRDB (`Core/Database/`), `UserDefaults`, network. Dumb — không chứa quyết định
  sản phẩm.

Luồng chuẩn: user tap → `send(.tappedSave)` → `transition` trả state mới + `.persist(...)` →
model chạy effect → `send(.saveSucceeded)` / `send(.saveFailed(reason))`.

### One concern per file

Mỗi file một việc, **mục tiêu ~400 dòng** (SwiftLint warning ở 400, không bao giờ là error):

| File | Chứa | Không chứa |
| --- | --- | --- |
| `<Feature>Screen.swift` / `<Feature>View.swift` | SwiftUI view, layout, accessibility id | state machine, network |
| `<Feature>Model.swift` | `State`, `Action`, `send`, `transition` | view code, URLSession |
| `<Feature>Rules.swift` / `…Catalog.swift` / `…Formatting.swift` | helper thuần, test bằng input→output | state, I/O |
| `<Feature>Service.swift` / `…Adapter.swift` | port + implementation thật | SwiftUI |

Ngoại lệ legacy đang tồn tại (đo 2026-10-29, dòng): `Features/Camera/CameraFeature.swift`
2169 · `Features/Poses/PosesFeature.swift` 1912 · `Poses/PoseServiceAdapter.swift` 913 ·
`Support/SupportScreens.swift` 868 · `RevenueCatAdapter.swift` 861 · `Gallery/GalleryFeature.swift`
768 · `Support/SignIn.swift` 658 · `Jobs/AddPoseScreen.swift` 485. **Không refactor chỉ vì file to.**
Tách **cơ hội**: khi một feature thật sự sửa vào file đó thì tách phần đang sửa ra trước, và
mỗi lần tách là **một commit behavior-preserving riêng** (test params/assert không đổi, xanh
*trước* và *sau*; commit này không kèm thay đổi hành vi).

### Naming

- Model mới: `<Feature>Model` (`PaywallModel`, `AccountSessionModel`) — một số tên cũ là
  `…Feature`/`…ViewModel`; giữ nguyên cho tới lần tách, đổi tên làm trong commit riêng.
- View/screen: `<Feature>Screen` (nếu là một màn) hoặc `<Feature>View` (một phần của màn).
- Port: đặt theo *khả năng*, không theo công nghệ (`PurchaseGateway`, `TokenStoring`).
  Implementation thật: `<Provider><Port>` hoặc `<Provider>Adapter` (`RevenueCatAdapter`).
- Action thì mệnh lệnh quá khứ/ý định rõ ràng, kèm payload: `.tappedSave`, `.appeared`,
  `.searchChanged(String)`, `.loadSucceeded([Pose])`, `.loadFailed(String)`. Không `.setX`.
- State field là danh từ mô tả dữ liệu view cần (`isLoading`, `query`, `results`, `banner`).
- Test: soi gương đường dẫn source → `iosAppTests/Features/<Feature>ModelTests.swift`.

### Session-scoped state

Mọi model giữ dữ liệu **của một account** phải là `SessionScoped`: subscribe
`SessionBoundary` generation, bỏ mọi kết quả trả về từ generation cũ, và xóa state khi sign-out.
Cơ chế `SessionScoped` một đầu mối được thiết kế ở **P2** (chưa có trong packet này); cho tới
lúc đó luật vẫn hiệu lực và được test thủ công theo từng model — xem
`Core/Network/SessionBoundary.swift`, `Core/Network/SessionScopeCoordinator.swift` và
`iosAppTests/Services/SessionScopeCoordinatorTests.swift`. Không model nào được tự phát minh
cách reset riêng.

### Test conventions

- Test **state transition, không UI**: tạo model với fake port, `send(...)`, assert `state`.
  Không snapshot, không `XCUIApplication`, không simulator cho logic.
- **Failing test trước** cho mọi thay đổi hành vi và mọi bug fix: đỏ → code → xanh.
- **Mutation proof** cho logic an toàn (session/account scope, xóa dữ liệu, persistence, tiền):
  cố tình làm sai điều kiện (hoặc đảo một guard) rồi xác nhận test đỏ, sau đó revert. Một test
  không đỏ được khi logic sai thì không phải bằng chứng — ghi lại việc này trong report.
- Test độc lập, không phụ thuộc thứ tự; mỗi test tự dựng state và tự dọn (temp dir, in-memory DB).

### Accessibility identifier convention

`<screen>.<element>` — screen là camelCase của feature, element là camelCase của hành vi:
`poseDetail.saveButton`, `camera.choosePose`, `saved.signIn`, `poses.add-pose`, `search.field`.
Identifier là **hợp đồng với Maestro** (`mobile/iosApp/maestro/flows/*.yaml`): không dùng lại một
id cho hai element, không đổi tên id mà không sửa flow trong cùng commit. Element lặp lại trong
list dùng suffix khoá của row: `<screen>.row.<id>`.

### Cheap gates (SwiftLint, SwiftFormat, pre-commit)

- Cài bằng brew, **không** thêm gì vào app target / build phase / SwiftPM graph:
  `brew install swiftlint swiftformat`.
- [`swiftlint.yml`](../../../.swiftlint.yml) (repo root) bật warning cho `file_length` (400), `function_body_length`,
  `type_body_length`, `line_length`… không rule nào là error trên cây hiện tại. Các vi phạm cũ
  được đóng băng trong `.swiftlint.baseline.json` (**93 vi phạm / 34 file**, đo 2026-10-29) nên
  `swiftlint lint --quiet` im lặng và exit 0; vi phạm **mới** in ra và fail. Re-baseline là hành
  động được review, không phải cách dập lỗi mới.
- [`.swiftformat`](../../../.swiftformat) là **allow-list** đúng những rule cây hiện tại đã thoả; dùng `--lint` thôi,
  không bao giờ format lại code cũ trong commit feature. Danh sách rule nợ nằm ở comment cuối file.
- [`scripts/git-hooks/pre-commit`](../../../scripts/git-hooks/pre-commit) (cài thủ công, xem dưới) chỉ chạy swiftformat `--lint` +
  `swiftlint` trên **file .swift đã stage**, không bao giờ gọi `xcodebuild`.
- Chạy gate:

```sh
swiftlint lint --quiet                                  # từ repo root (baseline resolve theo cwd)
swiftformat --lint mobile/iosApp/iosApp mobile/iosApp/iosAppTests

# cài hook pre-commit (không tự động)
ln -sf ../../scripts/git-hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

### VERIFY RULE (bắt buộc)

> Worker **phải** chạy [`scripts/ios-verify.sh`](../../../scripts/ios-verify.sh) và thấy **xanh trước khi commit** bất kỳ thay đổi
> code iOS nào. Xanh = exit 0 **và** dòng summary `failures=0` với `executed > 0`.
>
> Commit bằng pathspec tường minh — `git commit -m "..." -- <path>…` — **không bao giờ** `git commit`
trần: nhiều lane cùng làm trên một working tree, và index dùng chung sẽ nuốt file đã stage của lane khác.

Script lo hết phần dễ sai: chặn khi `/` còn dưới 1.5 GB, chặn khi đã có `xcodebuild` khác chạy
(một build tại một thời điểm, toàn máy), dùng simulator test chung
`7CC9393C-88FC-4AE6-88D3-AC68A2E266B7` (override `IOS_VERIFY_SIM`), `-derivedDataPath /tmp/dd-shared`
(override `IOS_VERIFY_DD` khi cần hai lane build song song; mặc định không đổi),
`build-for-testing` rồi `test-without-building` với scheme `Dev`, bọc `perl alarm` 1400s, in một
dòng `executed/failures`. Chỉ nhận thêm `-only-testing:`/`-skip-testing:`. Selector là bundle-relative
và **không** kèm thư mục nguồn: `iosAppTests/AppConfigTests` (đúng), không phải
`iosAppTests/Services/AppConfigTests` (chọn 0 test). Script fail non-zero khi chọn/chạy 0 test —
xanh với 0 test là false pass. Muốn kiểm môi trường không build: `scripts/ios-verify.sh --check-env`.

Bước cuối của **mọi** lần chạy (xanh hay đỏ, trap `EXIT`): script xoá **nội dung**
`$HOME/Library/Developer/CoreSimulator/Devices/7CC9393C-88FC-4AE6-88D3-AC68A2E266B7/data/Library/Caches/com.apple.containermanagerd/Dead/`
— container app chết do mỗi lần cài lại app — rồi in một dòng số byte giải phóng. Chỉ đúng UDID
thiết bị test chung đó (không bao giờ `CF871F97…`, không theo `IOS_VERIFY_SIM`), chỉ thư mục `Dead/`
và chỉ khi nó tồn tại; dọn dẹp **không** đổi exit code của lần verify.

Server lane không nằm trong packet này: gate static duy nhất hiện có là
`npm --prefix web/services/pose-extract-server run lint` (`tsc --noEmit -p tsconfig.json`);
chưa có ESLint — follow-up riêng nếu cần, đừng thêm trong packet feature.

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

> Lưu ý lịch sử (retired 2026-09-13): các ràng buộc Kotlin/KMP — Koin 4.0.0,
> cinterop Firebase qua `pod()`, Gradle chỉ build target `ios*`, framework
> `ComposeApp` static — chỉ còn giá trị đọc tài liệu cũ; mobile lane hiện là
> Swift native trong `mobile/iosApp`.

1. **XcodeGen là nguồn sự thật cho iOS project** — tạo file mới (Assets, plist,
   source) phải vào `project.yml`, regenerate, kiểm tra `Package.resolved` không đổi
   vô cớ. Có 4 config `Debug/Release` × `Dev/Prod` ánh xạ native build type.
2. **Dependency iOS chỉ đi qua SwiftPM** — pin `exactVersion` trong `project.yml`;
   lane CocoaPods (`Podfile`, `Podfile.lock`, `Pods/`) đã bỏ, `pod install` sẽ chèn
   lại Pods build phase vào project generate và làm hỏng build.
3. **Swift 6 mode** (`SWIFT_VERSION = 6.0`) đặt trong `project.yml` settings;
   không còn override `SWIFT_STRICT_CONCURRENCY`/`-strict-concurrency` từ Podfile.
4. **Worker cần credential của provider được chọn** — Gemini dùng key pool;
   Higgsfield dùng CLI credentials. Thiếu credential Higgsfield làm job fail rõ mã
   lỗi theo DEC-001.
5. **Skeleton từ khóa chuẩn hóa** — theo
   [[pose-domain-glossary]], thuật ngữ extraction
   result là `skeleton`, không dùng `render`/`result image`/`extract`.
6. **Thủ tục khởi động (DB, R2, secret) không đổi** — bất kỳ thay đổi schema
    fetch/khởi tạo runtime phải coi là thay đổi hành vi (xem Feature workflow).

## Boundary & storage

- Mobile: photo bytes trong app-private storage; `Pose` local cache trong GRDB /
  SQLite (`mobile/iosApp/iosApp/Core/Database/`). Không lưu trữ extraction jobs trên thiết bị (server-authoritative).
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
npm --prefix web/services/pose-extract-server run lint   # tsc --noEmit (only server static gate)
npm run build
(cd mobile/iosApp && xcodegen generate)

# iOS: xem VERIFY RULE ở "iOS app architecture and conventions"
scripts/ios-verify.sh                 # build-for-testing + toàn bộ unit test, in 1 dòng summary
scripts/ios-verify.sh --check-env     # chỉ kiểm disk / build lock / simulator
swiftlint lint --quiet
swiftformat --lint mobile/iosApp/iosApp mobile/iosApp/iosAppTests

# fallback debug thủ công (khi cần -destination khác hoặc chạy UI test)
xcodebuild test -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev \
  -destination 'platform=iOS Simulator,name=<available iPhone>'

ckh validate --all --workspace .
ckh index check --workspace .
```

Build fail là bằng chứng health hiện tại — ghi lại, không lấy `error.log` cũ
thay cho lần chạy mới.
