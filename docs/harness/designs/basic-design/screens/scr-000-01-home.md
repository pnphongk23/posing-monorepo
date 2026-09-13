---
screen_id: SCR-000-01
screen_name: Home
related_feature: FEAT-003
compose: App() → TabNavigator → PosesTab → PosesListScreen + PosesScreen + MainDock
status: draft
template_version: 2
canonical: false
---

# SCR-000-01 — Home

> **Canonical screen template (v2)** — `docs/harness/designs/basic-design/screens/TEMPLATE.md`. Home là screen contract cho app-entry shell hiện đang materialize bằng `PosesTab`; không phải một `HomeScreen` class mới.
>
> **Evidence boundary:** Harness Features/specs là contract hành vi và dữ liệu. Native Compose là implementation evidence. Prototype là visual/navigation exploration, không tự nâng thành production behavior.

<a id="scr-000-01-home-posestab-poseslistscreen-posesscreen"></a>

## 1. Screen identity

| Field | Value |
| --- | --- |
| Screen ID | SCR-000-01 |
| Screen name | Home |
| Related feature | FEAT-003 (content dependency); shell ownership chưa có Feature riêng (**Unresolved**) |
| Compose / Voyager | `App()` → `TabNavigator(tab = PosesTab)` → `PosesListScreen` → `PosesScreen` + `MainDock` |
| Stable anchor | `scr-000-01-home-posestab-poseslistscreen-posesscreen` |
| Template version | `2` |

## 2. Purpose

Home là điểm vào chính của ứng dụng mobile sau khi app được phép vào main navigation flow (sau khi vượt qua onboarding gate nếu có). Mục tiêu chính của người dùng là **nhìn thấy catalogue pose cộng đồng đã được xác nhận và chọn bước tiếp theo nhanh**: mở chi tiết một published pose, tìm kiếm pose, hoặc chuyển sang Gallery và Camera.

Trong repository hiện tại, Home không có route hay class riêng biệt. Ánh xạ hiện tại là `Home` → `PosesTab` → `PosesListScreen` → `PosesScreen`, trong đó nội dung đang là Community-only. [SCR-003-01 — Poses (Community Browse)](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen) vẫn là owner của published catalogue; tài liệu này chỉ sở hữu app-entry shell và không tạo một catalogue thứ hai.

`My poses` không thuộc Home contract hiện tại: code production đã loại bỏ pane/tab này, còn tab tương ứng trong `poses-list.html` chỉ là **Observed prototype exploration**. Không bổ sung local personal collection, `For You` feed, social feed hoặc personalization UI nếu chưa có evidence quy định.

## 3. Scope and ownership

Home shell sở hữu:

- Entry composition, root tab selection và ranh giới giữa root navigation stack với các màn hình được push.
- Thanh điều hướng nổi cố định `MainDock` trên root Poses/Gallery surfaces cùng shortcut Camera.
- Các navigation intent từ header, content slot và dock tới các owner screen khác.

Home không sở hữu nghiệp vụ của các màn hình đích:

- **FEAT-003 / SCR-003-01:** Danh sách published Community, pull-to-refresh, phân trang, xử lý empty/error recovery.
- **FEAT-003 / SCR-003-02:** Tìm kiếm poses theo tiêu đề (Search).
- **FEAT-003 / SCR-003-03:** Pose Detail — tài liệu hiện có, không duplicate.
- **FEAT-001:** Chụp ảnh Camera; **FEAT-002:** Thư viện ảnh local Gallery.
- **FEAT-013:** Saved poses (account-backed), đang ở trạng thái proposed và chưa claim shipped.
- **FEAT-015:** Settings & Preferences, đang ở trạng thái proposed.
- **FEAT-016:** Onboarding và cá nhân hóa sở thích người dùng, đang ở trạng thái proposed.

**Related feature status (evidence-backed):**

| Feature | Harness status | Screen evidence | Ghi chú |
| --- | --- | --- | --- |
| FEAT-003 | approved | **Normative** catalogue content & navigation hops | Content dependency chính; không own shell |
| FEAT-001 | approved | **Observed** dock Camera action → `CameraTab` | Capture leg do SCR-001-01 sở hữu |
| FEAT-002 | approved | **Observed** dock Gallery tab → `GalleryTab` | Local gallery do SCR-002-01 sở hữu |
| FEAT-013 | proposed | **Observed seam** header Saved icon button | Slice riêng `feat-013-saved-poses`; chưa shipped runtime |
| FEAT-015 | proposed | **Observed seam** header Settings icon button | Route/owner production còn **Unresolved** |
| FEAT-016 | proposed | **Normative target** onboarding first-run gate | Code Compose hiện tại mount trực tiếp `PosesTab` (**Unresolved**) |

## 4. Data contract and evidence

**Data in**

- App root mount `TabNavigator(tab = PosesTab)` — **Observed** (`App.kt`). Code hiện tại chưa kiểm tra cờ `has_completed_onboarding` trước khi mount tabs; first-run gate là **Normative FEAT-016 / Unresolved trong code**.
- `PosesListStateHolder` cung cấp `PosesViewModel` và `communityGridState`; state holder được hoist trên nested Voyager navigator để list và viewport sống sót qua các thao tác push/pop detail — **Observed**.
- Dữ liệu catalogue community là mảng `CommunityPose[]` kèm pagination envelope từ `GET /api/community/poses` — **Normative FEAT-003**, hiển thị thông qua [SCR-003-01](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen).
- Sở thích người dùng từ FEAT-016 có thể trở thành input/filter mặc định cho Pose Library trong target flow — **Normative feature intent / Unresolved**; không được giả định đã có trong runtime của Home hiện tại.
- Không có input nào do Home sở hữu đối với `My Pose`, Account, Saved collection hay `Photo` trong Gallery.

**Data out**

- Khi người dùng kích hoạt thẻ pose: phát sinh sự kiện `poseId` / `PosePreview` chuyển tiếp tới Pose Detail — **Normative** navigation intent; loading và metadata của detail thuộc SCR-003-03.
- Search intent: push SearchScreen; query `q` và title-search E2E status thuộc SCR-003-02 — API contract **Normative**, production/mock evidence còn **Unresolved** theo FEAT-003.
- `MainDock`: phát sinh intent chuyển tab Camera / Gallery — **Observed**; hành vi Camera/Gallery thuộc FEAT-001/FEAT-002.
- Saved và Settings là các navigation intent liên feature. Home không lưu trữ, thay đổi hoặc quản lý trạng thái của Account/Saved/Settings.

**Navigation and back contract**

- Root entry là `PosesTab`; Home không phải một route được push trên navigation stack và không có nút Back trên giao diện. Hành vi Back vật lý của hệ điều hành tại root chưa có evidence xác định — **Unresolved**.
- Search và Pose Detail được push trên Poses navigator. Nhấn Back sẽ pop về Home/Poses root; `PosesListStateHolder` bảo toàn ViewModel và viewport cuộn của grid — **Observed**.
- Từ Home, nhấn nút Camera chuyển sang `CameraTab`; khi đóng Camera sẽ quay lại tab non-Camera trước đó (`PosesTab`) — **Observed**.
- `MainDock` hiển thị nổi trên các root list surface; các màn hình được push (Search, Detail, Saved) không tự nhận thêm dock — **Observed**.

**Evidence labels:**

| Label | Ý nghĩa |
| --- | --- |
| **Normative** | Contract hành vi/dữ liệu/API từ harness feature + `docs/spec` — không suy từ code |
| **Observed** | Ghi nhận implementation hiện tại; không thay source of truth |
| **Unresolved** | Conflict hoặc chưa chứng minh E2E |
| **Non-evidence** | Placeholder template hoặc sub-surface mẫu chưa có evidence — **không** dùng làm acceptance |

## 5. Screen items (main surface)

<a id="scr-000-01-home-main"></a>

**Hierarchy:** `App` shell → `PosesTab` → `PosesListScreen` stack → `PosesScreen` column (safe-area header → Poses content slot) → `MainDock` floating at the bottom. Content slot ủy quyền danh sách cho SCR-003-01; không định nghĩa lại tại đây.

| No. | Item ID | Tên item | Loại UI | Req/Opt | Ràng buộc / hành vi |
| --- | --- | --- | --- | --- | --- |
| 1 | SCR-000-01-SHL-001 | Home root host | Voyager `Tab` + `Screen` stack | Req | Mount `PosesTab` làm app root, sau đó compose `PosesListScreen`; không tạo `HomeScreen` route riêng — **Observed**, đặt tên sản phẩm **Unresolved** |
| 2 | SCR-000-01-HDR-001 | Current screen title | `NavigationTitle` text | Req | Tiêu đề hiển thị trên prototype/basic-design là `"Poses"`; native code hiện còn hiển thị `"Community"`. Đây là copy discrepancy cần xử lý trước khi đạt native parity — **Observed / Unresolved** |
| 3 | SCR-000-01-HDR-002 | Search poses | Icon button, 44dp target | Opt | Gọi `onSearchClick` → push [SCR-003-02 Search](./scr-003-02-search.md#scr-003-02-search-searchscreen); accessible label `"Search poses"`; `testTag=poses-search-button` — **Observed** |
| 4 | SCR-000-01-HDR-004 | Open Saved | Icon button, 44dp target | Opt | Luồng đăng nhập có thể push [FEAT-013 Saved](../../feat-013-saved-poses/saved-list.md); khách chưa đăng nhập phải qua sign-in gate trước route/API. Trạng thái Saved và auth không thuộc Home — **Normative FEAT-013 / Observed seam / Unresolved** |
| 5 | SCR-000-01-HDR-005 | Open Settings | Icon button, 44dp target | Opt | Kích hoạt callback mở Settings; contract hàng/trạng thái thuộc [FEAT-015](../../../features/FEAT-015-manage-app-settings-and-preferences.md). Route production còn mâu thuẫn với feature doc — **Observed seam / Unresolved** |
| 6 | SCR-000-01-CNT-001 | Poses catalogue slot | `CommunityContent` + 2-column staggered grid | Req | Chỉ render `CommunityPose` công khai đã xác nhận; ủy quyền toàn bộ card, refresh, phân trang và empty/error cho [SCR-003-01](./scr-003-01-community-browse.md#scr-003-01-community-browse-poseslistscreen-posesscreen); bộ sưu tập là `Poses`, không có pane `My poses` — **Normative FEAT-003 / Observed** |
| 7 | SCR-000-01-CNT-003 | Published pose card activation | Card / grid item | Req | Chọn một `poseId` ổn định, đóng gói `PosePreview`, push sang [SCR-003-03 Pose Detail](./scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen); không duplicate màn hình chi tiết — **Normative FEAT-003 / Observed** |
| 8 | SCR-000-01-NAV-001 | MainDock — Poses/Gallery | Floating navigation pill | Req | Tab Poses đang active; tap tab Gallery chuyển sang `GalleryTab` mà không thay đổi catalogue ownership; áp dụng `MainDockContentInset` cho bottom padding để dock không che khuất dòng card cuối cùng — **Observed** |
| 9 | SCR-000-01-NAV-002 | MainDock — Camera | Standalone action button | Req | Chuyển sang `CameraTab` ([SCR-001-01 Camera](./mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen)); không push route Camera thứ hai — **Observed**, handoff sang FEAT-001 |
| 10 | SCR-000-01-ST-001 | First-run onboarding gate | Navigation gate / interceptor | Req | Kiểm tra cờ onboarding (FEAT-016); nếu chưa hoàn thành điều hướng vào onboarding flow trước khi mount Home. Code hiện tại mount trực tiếp `PosesTab` — **Normative FEAT-016 target / Observed gap / Unresolved** |
| 11 | SCR-000-01-ST-002 | Initial loading state | `CircularProgressIndicator` | — | Giữ nguyên header và MainDock; content slot hiển thị loading có thể hồi phục; ủy quyền request trang 1 cho SCR-003-01 — **Normative FEAT-003 / Observed** |
| 12 | SCR-000-01-ST-003 | Empty catalogue state | Text / Empty state | — | Hiển thị `"No poses found."` khi API trả về `200` + `data: []`; giữ nguyên shell và dock; không hiển thị tab hay CTA cá nhân "No My poses" — **Normative / Observed** |
| 13 | SCR-000-01-ST-004 | Initial error & Retry | State message + Retry | — | Khi tải dữ liệu catalogue thất bại ban đầu; hiển thị thông báo lỗi kèm nút Retry; không bịa đặt hoặc hiển thị dữ liệu chưa xác nhận — **Normative FEAT-003 E1 / Observed** |
| 14 | SCR-000-01-ST-005 | Refresh & load-more states | Inline feedback / indicator | — | Pull-to-refresh giữ nguyên danh sách thẻ đã có cho đến khi tải xong; load-more hiển thị spinner cuối grid hoặc lỗi inline + Retry; không thay thế danh sách bằng màn hình rỗng khi lỗi — **Normative / Observed** |

## 6. Screen flow and feature links

| Transition | Target |
| --- | --- |
| Khởi chạy app / hoàn thành onboarding | Ánh xạ Home: `PosesTab` → `PosesListScreen` → `PosesScreen` |
| Tap SCR-000-01-HDR-002 | [SCR-003-02 Search](./scr-003-02-search.md#scr-003-02-search-searchscreen) |
| Tap SCR-000-01-CNT-003 | [SCR-003-03 Pose Detail](./scr-003-03-pose-detail.md#scr-003-03-pose-detail-posedetailscreen) |
| Tap SCR-000-01-NAV-002 | [SCR-001-01 Camera](./mobile/scr-001-01-camera.md#scr-001-01-camera-camerascreen) (`CameraTab`) |
| Tap SCR-000-01-NAV-001 (Gallery slot) | [SCR-002-01 Gallery](./mobile/scr-002-01-gallery.md#scr-002-01-gallery-galleryscreen) (`GalleryTab`) |
| Tap SCR-000-01-HDR-004 | [FEAT-013 Saved list design](../../feat-013-saved-poses/saved-list.md) — proposed, account-gated |
| Tap SCR-000-01-HDR-005 | [FEAT-015 Settings](../../../features/FEAT-015-manage-app-settings-and-preferences.md) — proposed; route và handoff **Unresolved** |

**Main flow — Khởi chạy và khám phá:**

1. Khi khởi chạy ứng dụng (cold launch), hợp đồng mục tiêu kiểm tra trạng thái onboarding của FEAT-016. Nếu người dùng được phép vào ứng dụng, root mở `PosesTab` — **Normative FEAT-016 target / Observed direct mount trong code hiện tại**.
2. `PosesListScreen` compose `PosesScreen` và `MainDock`; catalogue owner của FEAT-003 gửi request lấy danh sách published poses — **Normative / Observed**.
3. Người dùng có thể mở thẻ pose đã xác nhận, mở Search, Camera, Gallery, Saved hoặc Settings thông qua handoff tương ứng. Home không tự triển khai hành vi của các màn hình đích đó.

**Continuation and recovery flows:**

- Card → Pose Detail → Back sẽ quay lại đúng ngữ cảnh danh sách Home/Poses; state holder và vị trí cuộn được bảo toàn — **Observed**, chi tiết thuộc [SCR-003-03](./scr-003-03-pose-detail.md).
- Search → Back quay lại Home/Poses root; việc khôi phục query/kết quả tuân theo contract của Search.
- Home → Camera → Close quay lại tab gọi trước đó (`PosesTab`); pose picker nội bộ của Camera là bottom sheet, không phải route của Home — **Observed** / xem [Camera §8](./mobile/scr-001-01-camera.md#scr-001-01-camera-bs-pose-picker).
- Phục hồi khi refresh, rỗng, lỗi ban đầu và lỗi load-more diễn ra ngay trong content slot của Poses theo SCR-003-01; Home không bao giờ hiển thị thẻ giả định.

**Feature flow links:**

- Main flow: [[FEAT-003-browse-and-search-published-poses#main-flow|FEAT-003 Main flow]] · [FEAT-003 Main flow](../../../features/FEAT-003-browse-and-search-published-poses.md#main-flow)
- Alternative A1 — Empty result: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A1 — Empty result]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-000-01-ST-003)
- Alternative A2 — Refresh: [[FEAT-003-browse-and-search-published-poses#alternative-flows|FEAT-003 Alternative A2 — Refresh]] · [FEAT-003 Alternative flows](../../../features/FEAT-003-browse-and-search-published-poses.md#alternative-flows) (SCR-000-01-ST-005)
- Exception E1 — Catalogue unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E1 — Catalogue unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) (SCR-000-01-ST-004)
- Exception E2 — Detail unavailable: [[FEAT-003-browse-and-search-published-poses#exception-flows|FEAT-003 Exception E2 — Detail unavailable]] · [FEAT-003 Exception flows](../../../features/FEAT-003-browse-and-search-published-poses.md#exception-flows) — xử lý tại SCR-003-03, không lặp lại tại đây.

**Cross-feature handoff links:**

- FEAT-016 sở hữu luồng first-run onboarding và phân phối catalogue cá nhân hóa: [[FEAT-016-user-onboarding-and-interest-personalization#main-flow|FEAT-016 Main flow]] · [FEAT-016 Main flow](../../../features/FEAT-016-user-onboarding-and-interest-personalization.md#main-flow).
- FEAT-001 sở hữu Camera sau khi kích hoạt từ dock: [[FEAT-001-capture-a-photo-on-mobile#main-flow|FEAT-001 Main flow]] · [FEAT-001 Main flow](../../../features/FEAT-001-capture-a-photo-on-mobile.md#main-flow).
- FEAT-002 sở hữu Gallery sau khi kích hoạt từ dock: [[FEAT-002-manage-a-local-photo-gallery#main-flow|FEAT-002 Main flow]] · [FEAT-002 Main flow](../../../features/FEAT-002-manage-a-local-photo-gallery.md#main-flow).
- FEAT-004 nằm ngoài Home surface; hiện không có nút tạo/trích xuất pose trên Home. Entry point cần quyết định product riêng trước khi tích hợp vào contract.
- FEAT-013 và FEAT-015 sở hữu hành vi Saved và Settings khi các đề xuất được phê duyệt và có runtime evidence.

## 7. Traceability and unresolved items

| Item | API / owner | Model / evidence |
| --- | --- | --- |
| SCR-000-01-SHL-001 | Không có; `App.kt` + `Navigation.kt` | `PosesTab`, `PosesListScreen`, `PosesListStateHolder` — **Observed** |
| SCR-000-01-CNT-001 | `GET /api/community/poses` qua FEAT-003 / SCR-003-01 | `CommunityPose`, pagination envelope; tổng số là internal và không hiển thị thành bộ đếm — **Normative** |
| SCR-000-01-CNT-003 | Không có API riêng của Home | `poseId` → `PosePreview` → [SCR-003-03](./scr-003-03-pose-detail.md) — **Normative/Observed** |
| SCR-000-01-HDR-002 | Search owner: FEAT-003 | Query `q`; trạng thái live/mock E2E **Unresolved** |
| SCR-000-01-NAV-002 | Camera owner: FEAT-001 | Chuyển tab Camera; không sở hữu kết quả chụp/trích xuất |
| SCR-000-01-NAV-001 | Gallery owner: FEAT-002 | Dữ liệu `Photo` nằm ngoài Home |
| SCR-000-01-HDR-004 | FEAT-013 Saved proposal | `Account` / `SavedEntry`; runtime auth và UI Saved **Unresolved** |
| SCR-000-01-HDR-005 | FEAT-015 Settings contract | Route và handoff Settings **Unresolved** |
| SCR-000-01-ST-001 | FEAT-016 Onboarding | `has_completed_onboarding`; Compose code trực tiếp mount `PosesTab` (**Unresolved**) |

HTTP contract: [../apis.md](../apis.md). Model: [../models.md](../models.md). Tổng flow: [./README.md](./README.md#overall-screen-flow).

**Unresolved items:**

1. **Class và route của Home:** Không tồn tại class `HomeScreen`, `HomeTab` hay Home route riêng trong production code. Mã `SCR-000-01` đại diện cho shell container chưa có Feature riêng để tài liệu hóa Home mà không gán sai ownership cho FEAT-003. Tiêu đề hiển thị hiện tại trên prototype/basic-design là `Poses`, trong khi native code vẫn hiển thị `Community`.
2. **Loại bỏ My Poses:** Production code chỉ có feed Community và đã gỡ bỏ hoàn toàn pane/tab `My poses`. Tab `My poses` trên prototype chỉ là visual exploration và không được phục hồi vào contract này.
3. **Feed riêng và cá nhân hóa:** Chưa có bằng chứng thực tế trong codebase về feed Home riêng, phân loại "For You", xếp hạng cá nhân hóa hay việc áp dụng sở thích từ FEAT-016 trên mobile runtime.
4. **Hành vi Offline và Platform Back:** Chưa có giao diện offline riêng biệt hay chính sách cache freshness cho Home; tuân thủ quy tắc xử lý lỗi của FEAT-003 E1. Hành vi của nút Back vật lý của hệ điều hành tại root entry chưa có test xác thực.
5. **Nút Premium trên Header:** Prototype có hiển thị biểu tượng vương miện (Crown) trên thanh công cụ. Tuy nhiên, FEAT-011 quy định Home là bề mặt miễn phí và nghiêm cấm đặt trigger Paywall trên header Home; do đó affordance này không thuộc Home contract.

## 8. Rationale

| Quyết định | Lý do |
| --- | --- |
| Ánh xạ Home vào `PosesTab` thay vì tạo route mới | Tránh tạo ra class `HomeScreen` ảo khi production Compose đang dùng `PosesTab` làm root host chứa catalogue và MainDock |
| Không duplicate catalogue với SCR-003-01 | SCR-003-01 là owner chính thức của published catalogue; Home chỉ đóng vai trò app-entry shell bọc ngoài |
| Bỏ tab `My poses` và CTA tạo pose | Đồng bộ với production code hiện tại (đã gỡ My Poses) và tuân thủ nguyên tắc FEAT-004 là out-of-slice |
| Tích hợp các trạng thái (ST) vào bảng item 6 cột | Tuân thủ nghiêm ngặt quy ước bảng của `TEMPLATE.md`, không dùng bảng 3 cột tùy tiện |
| Giữ `MainDock` nổi với `MainDockContentInset` | Cho phép điều hướng tức thì giữa Poses, Gallery và Camera mà không che khuất phần tử cuối cùng của grid |
| Không đặt trigger Paywall trên header | Tuân thủ chính sách freemium của FEAT-011: Home là không gian duyệt pose công khai tự do |

### Accessibility và kiểm tra xác thực

- **Giao diện Light Neo-Brutalist:** Sử dụng token màu và kiểu dáng chung: nền `AiPoseColors.Background`, viền đen 2dp, bóng đổ cứng (hard shadow), tuân thủ safe-area theo [UI/UX System](../../../specs/ui-ux-system.md).
- **Kích thước vùng chạm:** Tất cả các icon button điều hướng trên header và dock đều đảm bảo kích thước tối thiểu 44dp (`poses-search-button`, `main-dock`, `main-dock-poses`, `main-dock-gallery`, `main-dock-camera`).
- **Accessible labels:** Các nút dạng biểu tượng phải có nhãn cho trình đọc màn hình: `"Search poses"`, `"Open Saved poses"`, `"Open Settings"`, `"Open Camera"`.
- **Ranh giới xác minh (Verification boundary):** Xác thực tài liệu bằng markdown links và frontmatter; đối chiếu hành vi runtime với `App.kt`, `Navigation.kt`, `PosesScreen.kt` và bộ test FEAT-003. Các tương tác trên prototype chỉ dùng để kiểm tra trực quan, không dùng để chứng minh ownership hay backend contract.
