---
schema_version: 1
title: Restore Pose and Camera Settings Across Relaunch
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
    - "[[product-feature-inventory]]"
  decisions: []
  plans:
    - "[[260831-0000-feat-012-relaunch-restore/plan|260831-0000 current governing plan]]"
    - "[[260809-2241-selected-pose-camera-handoff/plan|260809-2241 historical superseded plan]]"
  reports:
    - "REP-012 (survey evidence xem docs/harness/specs hoặc plans/)"
  rules: []
  features:
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths:
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PreparedPoseReference.kt
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/ui/screens/poses/PoseDetailScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraState.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraScreen.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraLayoutModel.kt
    - docs/spec/data/entities/prepared-pose-reference.md
type: feature
id: FEAT-012
status: approved
created: 2026-08-30
approved: 2026-08-31
approved_by: Product Authority
---

# FEAT-012: Restore Pose and Camera Settings Across Relaunch

## Introduction

**Purpose:** Sau khi người dùng terminate app và mở lại (cold relaunch), Camera
khôi phục pose đã chọn (nếu còn hợp lệ) và các camera setting user-facing mà họ
đã dùng trong session trước — không bắt người dùng cấu hình lại từ đầu.

**In scope:**

- Khôi phục selection pose đã chọn qua relaunch khi identity + render asset còn
  hợp lệ trên thiết bị.
- Khôi phục độc lập với việc có pose hay không các setting:
  1. camera facing `FRONT` / `BACK`;
  2. flash `OFF` / `AUTO` / `ON`;
  3. grid on/off;
  4. pose guide visible/hidden;
  5. overlay opacity;
  6. pose line color `White` / `Black`;
  7. overlay pan/position + scale;
  8. camera zoom (1x–3x).
- Replace selection: pose mới thay pose cũ, **giữ** settings.
- Explicit clear: gỡ overlay/selection, **không** xóa settings và **không** thay
  đổi ownership/source Pose.
- Không auto-save, publish, hay chuyển quyền sở hữu pose.

**Out of scope:**

- Trạng thái transient: permission, in-flight capture, capture result, flash
  animation, popup/menu visibility.
- `frameRatio` — **Observed:** có trong `CameraUiState` nhưng không có user-facing
  entry point trên `main` @ `ca33cc2`; không claim restore.
- Account sync, multi-device history, cloud backup settings.
- Runtime contract mới thay `PreparedPoseReference` (ví dụ `ActivePoseReference`).
- Thay đổi semantics chụp ảnh / gallery persistence.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| App user | User | Tiếp tục chụp với pose và camera như session trước | Chọn pose, điều chỉnh camera, relaunch app |
| Product Authority | Business role | Chốt boundary hành vi | Approve Feature trước Cook |

### User needs

- Người dùng không muốn mất pose overlay và zoom/flash/grid sau khi OS kill app.
- Người dùng muốn đổi pose mà không reset toàn bộ camera preferences.
- Người dùng muốn clear overlay mà vẫn giữ zoom/flash đã chỉnh.

### Preconditions

- **Observed:** `PreparedPoseReference` là transport Try Pose → Camera hiện hữu
  (`PreparedPoseReference.kt:7-29`, `PoseServiceLocator.kt:12-21`).
- **Observed:** Overlay và settings tồn tại trong session qua `CameraUiState`
  (`CameraState.kt:14-27`) và `CameraZoomUiState` (`CameraLayoutModel.kt:14-25`).
- **Observed:** Try Pose verify trước handoff (`PoseDetailScreen.kt:317-351`).

### Trigger

App cold-starts hoặc user mở lại app sau terminate; Camera tab/screen được hiển
thị (trực tiếp hoặc sau navigation hợp lệ).

### Main flow

1. **Actor:** User đã chọn pose và điều chỉnh camera settings trong session trước.
   **System:** Persist một snapshot nhỏ gồm pose identity hợp lệ (khi có) và các
   setting in-scope khi settings hoặc selection thay đổi.
2. **Actor:** OS terminate app. **System:** Snapshot vẫn trên thiết bị (single-device).
3. **Actor:** User relaunch app và vào Camera. **System:** Restore settings; nếu
   pose snapshot hợp lệ thì rehydrate `PreparedPoseReference` và hiển thị overlay;
   nếu không có pose thì Camera mở với settings đã restore và không overlay.

### Alternative flows

- **A1 — Replace pose.** Source step: 1. Condition: user Try Pose pose khác.
  Behavior: thay selection; giữ settings. Ends with: overlay pose mới, settings
  không đổi.
- **A2 — Clear overlay.** Source step: 1. Condition: user explicit clear.
  Behavior: gỡ selection/overlay; giữ settings. Ends with: Camera không overlay;
  source Pose không bị xóa/save/publish.
- **A3 — No pose, có settings.** Source step: 3. Condition: snapshot không có
  pose hợp lệ. Behavior: restore settings only. Ends with: Camera usable, không
  overlay invalid.

### Exception flows

- **E1 — Corrupt hoặc missing pose asset.** Source step: 3. Failure: identity
  hoặc local render path không đọc được. Handling: clear selection snapshot;
  restore settings; hiển thị recoverable indication khi phù hợp. Prohibited:
  crash hoặc overlay broken. Failure postcondition: capture vẫn khả dụng.
- **E2 — Corrupt settings snapshot.** Source step: 3. Failure: persisted settings
  invalid. Handling: fallback defaults cho field lỗi hoặc toàn bộ snapshot;
  không crash. Prohibited: claim restore thành công khi data corrupt.

### Postconditions

- **Success:** Settings in-scope khớp snapshot hợp lệ; pose overlay chỉ hiện khi
  reference rehydrate thành công.
- **Failure:** Không crash; capture semantics không đổi; không claim success sai.

### Current evidence

| Claim | Label |
| --- | --- |
| Session-only `preparedReference` + `remember(preparedReference)` UI init | **Observed** — `CameraScreen.kt:104-114` |
| Overlay render opacity/toggle/pan-zoom/tint | **Observed** — `CameraScreen.kt:248-287`, `310-337` |
| Zoom 1x–3x | **Observed** — `CameraLayoutModel.kt:23-25`, `CameraScreen.kt:358-380` |
| Handoff sets locator then Camera tab | **Observed** — `Navigation.kt:285-291` |
| Không persist qua relaunch | **Observed** — `BR-PREPREF-002`, `PreparedPoseReference.kt:13-14` |
| Durable restore behavior | **Unresolved** — chờ implementation Plan `260831-0000-feat-012-relaunch-restore` |

## Requirements

- **FR-001:** Khi app cold relaunch, hệ thống shall restore các camera setting
  in-scope (facing, flash, grid, guide visibility, opacity, line color, pan/scale,
  zoom) từ persisted snapshot, kể cả khi không có pose hợp lệ.
- **FR-002:** Khi snapshot pose hợp lệ sau relaunch, hệ thống shall rehydrate
  `PreparedPoseReference` (giữ contract hiện hữu) và hiển thị overlay tương ứng.
- **FR-003:** Khi snapshot pose invalid/corrupt/missing asset, hệ thống shall mở
  Camera với settings restored, không overlay invalid, và recoverable indication
  khi phù hợp.
- **FR-004:** Khi user chọn pose mới (replace), hệ thống shall cập nhật selection
  và giữ nguyên camera settings in-scope.
- **FR-005:** Khi user explicit clear overlay/selection, hệ thống shall gỡ pose
  overlay/selection snapshot mà không reset camera settings và không thay đổi
  ownership/source Pose.
- **FR-006:** Persist và restore shall là single-device snapshot; không account
  sync hay history cloud.
- **FR-007:** Shutter/capture, preview lifecycle, và gallery write semantics
  shall không thay đổi so với behavior hiện có trên `main`.
- **BR-001:** Try Pose vẫn verify asset trước khi emit `PreparedPoseReference`
  (không mở Camera với pose chưa verify).
- **BR-002:** Clear selection không được auto-save, publish, hoặc transfer
  ownership pose.
- **BR-003:** Transient UI/capture state (permission, in-flight capture, capture
  result, flash animation, popup visibility) không thuộc restore scope.
- **BR-004:** `frameRatio` không thuộc restore scope cho đến khi có user-facing
  control được Product Authority approve.
- **NFR-001:** Cold relaunch restore shall không gây crash khi snapshot rỗng,
  partial, hoặc corrupt.

## Acceptance

- [ ] Cold relaunch sau session có pose + settings: Camera restore đủ 8 settings
  và overlay pose hợp lệ.
- [ ] Cold relaunch không có pose nhưng có settings: Camera restore settings;
  không overlay; capture hoạt động.
- [ ] Invalid/corrupt pose snapshot: không crash; không overlay broken; settings
  vẫn restore khi snapshot settings hợp lệ.
- [ ] Replace pose: pose overlay đổi; settings giữ nguyên.
- [ ] Explicit clear: overlay/selection gỡ; settings giữ; source Pose không
  bị delete/save/publish.
- [ ] Capture sau restore: chụp và lưu gallery thành công như baseline session.
- [ ] Không regression crash trên cold relaunch matrix (no pose / valid / invalid).

**Scenario: cold relaunch with valid pose and settings**
Given user đã Try Pose thành công và chỉnh flash, grid, opacity, zoom, line color
When app bị terminate và user mở lại vào Camera
Then settings khớp session trước và overlay pose hiển thị từ `PreparedPoseReference`
rehydrated.

**Scenario: cold relaunch settings only**
Given user đã mở Camera và chỉnh settings nhưng không có pose selection
When app relaunch và user vào Camera
Then settings được restore và không có overlay.

**Scenario: corrupt pose snapshot**
Given persisted pose identity không resolve được local asset
When user relaunch vào Camera
Then app không crash; overlay không hiển thị invalid; settings restore nếu hợp lệ;
user có thể chụp bình thường.

**Scenario: replace keeps settings**
Given user đã có pose A và zoom 2x trên Camera
When user Try Pose pose B
Then overlay là pose B và zoom vẫn 2x.

**Scenario: clear keeps settings**
Given user có pose overlay và flash ON
When user explicit clear overlay
Then không còn overlay; flash vẫn ON; pose nguồn không bị save/publish.

## Relationships

- Governing plan: [[260831-0000-feat-012-relaunch-restore/plan|260831-0000]]
- Historical superseded plan: [[260809-2241-selected-pose-camera-handoff/plan|260809-2241]] (cancelled)
- Related features: [[FEAT-008-use-published-poses|FEAT-008]] (Try Pose handoff),
  [[FEAT-001-capture-a-photo-on-mobile|FEAT-001]] (capture semantics),
  [[FEAT-003-browse-and-search-published-poses|FEAT-003]] (community Try Pose entry)
- Specs: [[technical-architecture]], [[ui-ux-system]], [[product-feature-inventory]]
- Data contract: `docs/spec/data/entities/prepared-pose-reference.md` (transport;
  BR-PREPREF-002 sẽ cần align khi durable restore ship)
- Survey evidence: REP-012 BL-GAP-01
- Source paths: listed in frontmatter `source_paths`
