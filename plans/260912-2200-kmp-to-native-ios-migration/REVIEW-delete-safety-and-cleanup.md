# REVIEW — Delete Safety & Safe Cleanup (KMP → Native iOS)

Người rà soát: Hoàng Trung (Delete & Safety Cleanup Specialist) · Workspace `wks_2e69547344ec0a0b`
Branch: `feat/native-ios-migration` · Ngày chạy: 2026-09-13 · Người nhận: Code Vương

## 0. Verdict ngắn

| Hạng mục | Kết quả |
| --- | --- |
| Confirmation dialog trước khi xóa | **CÓ** (2 entry point, cả 2 đều có nút Cancel) |
| Xóa sạch file vật lý trên disk | **KHÔNG** — chỉ xóa row SQLite; file JPEG ở lại vĩnh viễn |
| Xóa record DB | **CÓ** (nhưng không kiểm tra row tồn tại, không dọn Pose mồ côi) |
| Xử lý khi xóa thất bại | **KHÔNG ĐẠT** — đóng dialog + đóng màn hình, báo sai thông báo |
| Test suite PASS | **CÓ** — 109 test, 0 failure (`** TEST SUCCEEDED **`) |
| Test bao phủ delete safety | **KHÔNG ĐỦ** — chỉ 1 test happy-path với stub in-memory; production path **không thể test được** |
| Dọn dẹp workspace | **ĐÃ DỌN** 79 MB + 142 `.DS_Store` + Xcode user state (chi tiết mục 3) |

**Kết luận: delete flow hiện tại KHÔNG đạt yêu cầu "xóa sạch file + record" và KHÔNG đạt yêu cầu "báo lỗi rõ ràng khi thất bại".** Đây là regression so với bản KMP đã bị xóa (bản KMP có `PhotoRepository.deletePhoto` xóa cả 3 file pose + ảnh, có rollback khi xóa file lỗi, có copy "Delete failed").

## 1. Bằng chứng (evidence)

Lệnh đã chạy:
- `srcwalk trace callers 'CaptureImageStorage.delete'`, `srcwalk deps .../GalleryFeature.swift`
- `rg -n "DELETE FROM|func delete|removeItem" mobile/iosApp/{iosApp,iosAppTests}`
- `git show HEAD:mobile/shared/.../PhotoRepository.kt` + `PhotoRepositoryDeletionTest.kt` (baseline KMP đã xóa)
- `xcodebuild test -project mobile/iosApp/iosApp.xcodeproj -scheme Dev -configuration Debug-Dev` → `** TEST SUCCEEDED **` (109 test, 0 failure)

## 2. Phần A — Delete Safety

### A1. [BLOCKER] Xóa chỉ xóa DB row, không xóa file vật lý

`mobile/iosApp/iosApp/ContentView.swift:60-63`
```swift
func delete(id: Int64) async throws {
    try await database.pool.write { db in
        try db.execute(sql: "DELETE FROM Photo WHERE id = ?", arguments: [id])
    }
}
```
- Ảnh được ghi xuống `Application Support/aipose/capture_<id>.jpg` và DB lưu **path tương đối** (`Core/Camera/CameraPorts.swift:82-90`, `Core/Camera/CaptureImageStorage.swift:19-29`).
- `CaptureImageStorage.delete(filename:)` (`Core/Camera/CaptureImageStorage.swift:37-41`) **tồn tại đúng cho việc này nhưng không có call site nào** (`srcwalk trace callers 'CaptureImageStorage.delete'` → *no call sites found*).
- Hệ quả: mỗi lần người dùng xóa ảnh, row biến mất nhưng JPEG vẫn nằm trên disk → **rò rỉ dung lượng vĩnh viễn**. Không có routine prune/orphan-sweep nào trong app (`rg -i "prune|sweep|orphan|cleanup"` → 0 hit).

**Fix đề xuất** (đặt ở tầng store, giữ nguyên chữ ký `GalleryStoring`):
1. Trước khi `DELETE`, `SELECT imagePath FROM Photo WHERE id = ?`; nếu không có row → `throw` (bản KMP throw `NoSuchElementException`, hiện tại xóa id không tồn tại vẫn "thành công" im lặng).
2. Xóa file **trước**, chỉ `DELETE` row khi file đã xóa xong (hoặc file vốn không tồn tại = idempotent). Nếu xóa file lỗi → giữ nguyên row và `throw` (đúng semantics `restoresPhotoWhenFileDeletionFails` của KMP).
3. **Bắt buộc** guard quyền sở hữu path trước khi `removeItem`: bản KMP có `storage.isOwned(path)` (chỉ xóa file nằm trong thư mục app sở hữu). Nếu không guard, một path tuyệt đối hỏng/từ DB legacy (ví dụ trỏ vào chính `aipose.db`) sẽ bị `removeItem` → phá dữ liệu. Đề xuất thêm `isOwned` vào `CaptureImageStorage` và chỉ xóa khi `fullPath(for:)` resolve nằm trong `directoryURL`.

### A2. [BLOCKER] Xóa thất bại vẫn đóng dialog + đóng màn hình, báo sai thông báo

`mobile/iosApp/iosApp/Features/Gallery/GalleryFeature.swift:564-571`
```swift
.confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
    Button("Delete", role: .destructive) { onDelete(current); onDismiss() }   // ← fire-and-forget
    Button("Cancel", role: .cancel) {}
}
.confirmationDialog("Photo options", isPresented: $showOptions, ...) {
    Button("Delete Photo", role: .destructive) { onDelete(current); onDismiss() }  // ← y hệt
    Button("Cancel", role: .cancel) {}
}
```
`GalleryScreen` truyền `onDelete:` là `Task { await model.delete(item) }` (không có kênh trả kết quả), và `onDismiss()` chạy **đồng thời, ngay lập tức**, không chờ kết quả.

`mobile/iosApp/iosApp/Features/Gallery/GalleryFeature.swift:285-294`
```swift
func delete(_ item: GalleryItem) async {
    do {
        try await store.delete(id: item.id)
        ...
    } catch {
        state = .failed(error.localizedDescription)   // ← thay luôn state của cả Gallery
    }
}
```
Hệ quả khi xóa lỗi:
- Dialog đóng, màn hình detail đóng (vi phạm yêu cầu "không đóng dialog khi thất bại"); người dùng mất vị trí đang xem.
- State của cả Gallery bị ghi đè `.failed` → grid biến mất, hiện "Couldn't load gallery" + nút Retry gọi `load()`; thông báo lỗi không nói gì về thao tác xóa.
- Không có copy lỗi dạng "Delete failed" như bản KMP (`mobile/composeApp/.../platform/DeletePhotoConfirmation.kt`, đã xóa ở commit migration: `deletePhotoConfirmation(success) = if (success) "" else "Delete failed"`).

**Fix đề xuất:** cho `onDelete` trả kết quả (`(GalleryItem) async -> Bool` hoặc `@escaping (Result<Void, Error>) -> Void`); chỉ `onDismiss()` khi thành công; khi lỗi → giữ dialog/màn hình, hiện alert/inline "Delete failed" (đặt copy vào một helper thuần như `deletePhotoConfirmation(success:)` để test được không cần UI), giữ grid nguyên vẹn (`state` vẫn `.loaded`, chỉ flip item đó). Không dùng `state = .failed` cho lỗi của một item đơn lẻ.

### A3. [HIGH] Không dọn Pose mồ côi (regression so với KMP)

`Core/Database/AppDatabaseSchema.swift:130-137` — FK `Photo.poseId → Pose.poseId ON DELETE SET NULL`. `PhotoRepository`/`PoseRepository` (`Core/Database/DatabaseRepositories.swift`) **không có hàm delete nào cả**. Bản KMP `PhotoRepository.deletePhoto` xóa pose cuối cùng cùng 3 file (`originalPath`, `skeletonPath`, `thumbnailPath`) khi không còn photo nào tham chiếu, và **giữ pose nếu photo khác còn tham chiếu** (`deletingOnePhotoRetainsPoseReferencedByAnotherPhoto`) và **không đụng pose của path ngoài app** (`deletingPhotoDoesNotAffectUnrelatedNonOwnedPoseReference`). Trên DB đã migrate từ KMP, lịch sử này vẫn còn (Pose + path) nên orphan row + file vẫn phát sinh.

### A4. [HIGH] Fallback fixture "hồi sinh" ảnh đã xóa

- `ContentView.swift:30`: `GalleryStoreWithFallback(primary: databaseStore, fallback: fixtureStore)`; `GalleryFeature.swift:185-188`: khi primary rỗng thì trả về **6 fixture ảnh giả**.
- `GalleryFixtureStore.delete` (`GalleryFeature.swift:98-100`, comment "Fixtures are a stable baseline") là **no-op im lặng** (vẫn "thành công"), và `GalleryStoreWithFallback.delete` chỉ gọi primary.
- Kịch bản thật: người dùng xóa ảnh cuối cùng → UI `.empty` (đúng, trong session đó). Mở lại app / Retry → `photos()` primary rỗng → **6 ảnh fixture hiện lên như ảnh thật** (id âm −101…−106). Xóa một fixture: store no-op nhưng UI vẫn biến mất item → **false success**, mở lại app lại thấy "ảnh" đó. Đây là dạng lỗi "xóa nhưng không xóa" trực tiếp trong luồng delete.
- Fix: chỉ dùng fixture khi `#if DEBUG` + cờ rõ ràng (hoặc khi DB chưa từng có row nào), không dùng `isEmpty` làm điều kiện; và `GalleryFixtureStore.delete` nên mutate list / `throw` để không báo thành công giả.

### A5. [MEDIUM] Pager dùng index — biên an toàn chưa được chặn

`GalleryFeature.swift:533` (`private var current: GalleryItem { items[page] }`) là truy cập index không kiểm tra. Khi một item bị xóa trong lúc cover đang mở, tính đúng đắn phụ thuộc vào thứ tự `selectedIndex = nil` **trước** `applyFilter()` trong `GalleryViewModel.delete`. Hiện tại thứ tự này đúng nên chưa thấy crash, nhưng đây là coupling ngầm, dễ vỡ khi refactor. Đề xuất guard `items.indices.contains(page) ? items[page] : nil` và dùng `item.id` làm selection thay vì index. *(Đây là suy luận tĩnh, chưa reproduce được crash — không nên coi như bug đã xác nhận.)*

## 3. Phần B — Kiểm kê test delete safety

Đã chạy: `xcodebuild test -scheme Dev -configuration Debug-Dev` → **`** TEST SUCCEEDED **`, 109 test, 0 failure** (bao gồm `GalleryFeatureTests` 13 test, `FeatureStateTests` 10 test). Test suite **PASS**, nhưng **không** bao phủ delete safety:

| Coverage cần có | Trạng thái | Bằng chứng |
| --- | --- | --- |
| Happy path xóa → item biến mất | CÓ (chỉ stub in-memory) | `iosAppTests/Features/FeatureStateTests.swift:39-46` `testGalleryDeleteReloadsItems` |
| Xóa row DB thật (GRDB) | **KHÔNG** | `DatabaseGalleryStore` là `private struct` trong `ContentView.swift:41` → test target không thể chạm tới |
| Xóa file vật lý trên disk | **KHÔNG** | không có test nào assert `FileManager.fileExists == false` sau delete |
| Xóa khi file không tồn tại (idempotent) | **KHÔNG** | — |
| Xóa thất bại → không mất record, báo lỗi | **KHÔNG** | `GalleryFeatureTests.swift:191` `FailingGalleryStore.delete` **không throw** → nếu viết test lỗi bằng stub này sẽ **false pass** |
| Dialog "Delete Photo" + nhánh Cancel | **KHÔNG** | không có UI test target (`project.yml` chỉ có `iosAppTests` unit target) |
| Copy "Delete failed" | **KHÔNG** | tương đương `DeletePhotoConfirmationTest` của KMP đã bị xóa, chưa có bản native |

So với baseline KMP đã bị xóa (5 test trong `PhotoRepositoryDeletionTest.kt` + 2 test `DeletePhotoConfirmationTest.kt`), native hiện có **1 test happy-path**. Muốn test được, cần đổi `DatabaseGalleryStore` từ `private` trong `ContentView.swift` thành type nội bộ (internal) trong `Features/Gallery/` hoặc `Core/Database/`, và inject một port xóa file (protocol) để test file-system thật trong tmp dir.

## 4. Phần C — Dọn dẹp workspace (đã thực hiện)

### Đã dọn (an toàn, không phải source code, đều thuộc lane KMP/Gradle đã bị xóa)

| Mục | Kích thước / số lượng | Lý do an toàn |
| --- | --- | --- |
| `.gradle/` | 76 MB | Cache Gradle của build KMP; `build.gradle.kts`, `settings.gradle.kts`, `gradlew`, `gradle/` đã bị xóa (staged) → không còn build nào dùng |
| `.kotlin/` | 3.2 MB | Cache metadata Kotlin daemon; không còn nguồn Kotlin |
| `mobile/docs/` | 8 KB | Chỉ còn `.DS_Store` (leftover dir rỗng sau migration) |
| `.DS_Store` toàn repo | 142 file (47 trước khi tính cả trong cache) | Rác macOS, đã nằm trong `.gitignore` |
| `mobile/iosApp/iosApp.xcodeproj/xcuserdata/`, `mobile/iosApp/iosApp.xcworkspace/xcuserdata/` | nhỏ | Xcode user state, gitignored, Xcode tự sinh lại |

Tổng thu hồi ~79 MB. Kiểm chứng sau khi dọn: `git status --short | rg '^ D'` **rỗng** (không có file tracked nào bị xóa ngoài ý muốn); 179 deletion staged vẫn nguyên; `.DS_Store` ngoài `node_modules` = 0.

### KHÔNG dọn — kèm lý do (cần Code Vương quyết định)

| Mục | Vì sao không xóa |
| --- | --- |
| `mobile/iosApp/Pods/` (75 MB) + `Podfile` + `Podfile.lock` | Đây là **tracked** + Podfile còn `pod 'composeApp', :path => '../composeApp'` nhưng `mobile/composeApp` **đã bị xóa** → `pod install` hiện **không thể chạy lại**. Xóa `Pods/` bây giờ là **không thể hoàn tác**. Phải xử lý nguyên gói: xóa Podfile/Podfile.lock/Pods + chuyển workspace sang SPM (`project.yml` đã dùng SPM cho Firebase/RevenueCat/GRDB) trong **một commit duy nhất** |
| `mobile/iosApp/gradlew`, `mobile/iosApp/gradle` | Là **symlink tracked đã gãy** (`→ ../../gradlew`, `→ ../../gradle` — target đã bị xóa ở commit migration). Nên xóa, nhưng nằm trong cùng commit với việc xóa KMP, không phải "cache rác" |
| `gradle.properties` (root, tracked) | Chỉ còn cấu hình `org.gradle.jvmargs` / `kotlin.native.cacheKind.*` — hoàn toàn là config KMP, nhưng là file tracked → thuộc quyết định của owner migration |
| `local.properties` (untracked, ignored) | Trỏ `sdk.dir=.../Android/sdk`. Chỉ dùng cho Gradle/AGP đã bị xóa → có thể xóa, nhưng 352 byte, tôi giữ lại cho owner xác nhận |
| `.idea/` (156 KB) | IDE state của người dùng, gitignored; xóa được nhưng có thể gây khó chịu, giá trị dọn dẹp thấp |
| `node_modules/` (14 MB), `.docker-data/`, `.docker-persist/` (11 MB), `web/services/pose-extract-server/data/` (204 MB) | Thuộc lane web/backend, **ngoài phạm vi migration mobile** — xóa có thể phá credential/volume dev local |
| `mobile/iosApp/iosApp/GoogleService-Info.plist` | Gitignored nhưng là **resource bắt buộc** trong `project.yml` |

### ⚠️ CẢNH BÁO AN TOÀN cho mọi worker

**KHÔNG chạy `git clean -xfd` hoặc `git clean -fdX` trong repo này.** `git clean -ndX` liệt kê những file sẽ bị xóa, trong đó có:
- `mobile/iosApp/iosApp/GoogleService-Info.plist` → **build sẽ fail ngay** (resource bắt buộc của target `iosApp`)
- `mobile/iosApp/Pods/` → **không regenerate được** vì Podfile trỏ `composeApp` đã xóa
- `local.properties`, `.docker-persist/` (credential + sqlite dev)

Nếu cần dọn rác, dùng đúng danh sách ở mục "Đã dọn" phía trên.

### Untracked còn lại (đều là source/artifact hợp lệ, giữ nguyên)

- `mobile/iosApp/iosApp/Core/`, `mobile/iosApp/iosApp/Features/`, `mobile/iosApp/iosAppTests/` → **source Native iOS mới, TUYỆT ĐỐI GIỮ** (đúng yêu cầu đề bài).
- `mobile/iosApp/iosApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` → theo PLAN.md phải **commit** (pin SPM Firebase 12.10.0 / RevenueCat 5.87.1 / GRDB 7.6.0).
- `mobile/iosApp/iosApp.xcworkspace/xcshareddata/swiftpm/Package.resolved` → artifact SPM của workspace CocoaPods; sẽ hết ý nghĩa khi bỏ Pods.
- `plans/260912-2200-kmp-to-native-ios-migration/PLAN.md` (+ file này) → tài liệu kế hoạch, nên commit.

## 5. Đề xuất hành động (theo ownership trong PLAN.md)

| # | Hành động | Owner theo PLAN.md |
| --- | --- | --- |
| 1 | Thêm xóa file vật lý (guard `isOwned`) + giữ row khi xóa file lỗi + throw khi row không tồn tại | W1 (`ContentView.swift`) / W2 (`Core/Database/**`) |
| 2 | Chỉ dismiss khi delete thành công; thêm copy "Delete failed" + alert/inline, không ghi đè `state` của Gallery | W5 (`Features/Gallery/**`) |
| 3 | Đưa `DatabaseGalleryStore` ra khỏi `private` (chuyển vào `Features/Gallery/`), inject port xóa file | W1 + W5 |
| 4 | Thêm test: xóa thành công xóa cả file + row; file thiếu → idempotent; file lỗi → row còn; fixture delete không false-success; copy delete-failure | W2 + W5 |
| 5 | Sửa `FailingGalleryStore.delete` để **thật sự throw** (tránh false pass) | W5 |
| 6 | Quyết định gói cleanup Pods/Podfile/gradle symlinks/gradle.properties như một commit atomic | Owner migration (W1) |
