# Screenshots Runbook — posing 1.1

**Quy tắc #1: Chỉ dùng màn hình app native.** Chụp app `posing.camera.app` đang chạy trên iOS Simulator hoặc thiết bị thật. Marketing frame được phép thêm headline và viền thiết kế bên ngoài; ảnh màn hình bên trong phải lấy trực tiếp từ app.

**Quy tắc #2: Giữ nguyên ảnh màn hình native.** Không vẽ, ghép, thay hoặc xóa status bar. Không cắt phần status bar khỏi ảnh nguồn. Không dùng prototype HTML.

---

## 1. Kích thước & resolution

### iPhone (bắt buộc tối thiểu 1 bộ cỡ lớn nhất)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 6.9" Display | **1290 × 2796** (`1290x2796/`) | iPhone 15 Pro Max simulator (native 1290 × 2796) | Dùng nếu ASC hiển thị slot 6.9"; Apple also accepts 1320 × 2868 (iPhone 16/17 Pro Max) and 1260 × 2736 |
| 6.5" Display | **1284 × 2778** (`1284x2778/`) hoặc **1242 × 2688** (`1242x2688/`) | iPhone 14 Plus / 11 Pro Max | ASC slot requires one of these portrait sizes |
| 6.3" | 1179 × 2556 hoặc 1206 × 2622 | iPhone 17 Pro / 16 Pro | Optional |
| 6.1" | 1170 × 2532 | iPhone 14 / 13 | Optional |
| 5.5" | 1242 × 2208 (@3x) | iPhone 8 Plus | Optional (thiết bị cũ) |

### iPad (BẮT BUỘC — `TARGETED_DEVICE_FAMILY = "1,2"`)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 13" | **2048 × 2732** (`2048x2732/`) hoặc 2064 × 2752 | iPad Pro 12.9" (6th gen) simulator cho 2048 × 2732; iPad Pro 13" M4/M5 cho 2064 × 2752 | **Bắt buộc** (cỡ lớn nhất hỗ trợ) |
| 11" | 1668 × 2388 hoặc 1668 × 2420 | iPad Pro 11" | Khuyến nghị |

> Nếu không cung cấp bộ iPad, ASC sẽ báo lỗi khi app hỗ trợ iPad family → **bắt buộc chụp ít nhất 13"**.

**Format:** PNG không alpha hoặc JPEG, sRGB. Bộ hiện tại giữ thiết kế marketing frame; ảnh màn hình native bên trong không được sửa. Portrait cho iPhone; iPad cho phép cả 2 hướng (app hỗ trợ landscape trên iPad).

---

## 2. Nguồn chụp

Capture từ build Dev trên iPhone 15 Pro Max Simulator (1290 × 2796 native; iPhone 16/17 Pro Max cho 1320 × 2868, ASC cũng nhận). Dùng `xcrun simctl status_bar` để đặt status bar hệ thống ở 9:41, Wi-Fi 3 vạch, cellular 4 vạch và pin đầy. Maestro chỉ điều hướng giữa các màn hình; ảnh chụp bằng `xcrun simctl io <udid> screenshot` là nội dung app native, không phải ảnh prototype.

Marketing frame tool nhận các PNG này trong `public/native-screenshots/`. Chế độ native dùng `object-contain`, giữ nguyên toàn bộ ảnh app và status bar; tool chỉ scale đồng đều để đặt ảnh trong khung thiết kế. Chế độ prototype cũ vẫn dùng lệnh `npm run export` riêng.

Native export render mỗi frame một lần, sau đó dùng `sharp` resize bằng `contain` sang năm canvas: iPhone 6.5" slot (1242 × 2688), 6.7" size (1284 × 2778), 6.9" (1290 × 2796), iPad 13" (2048 × 2732) và iPad 11" (1668 × 2388). Nền letterbox native lấy màu nền từ pixel góc của frame để phần trống liền màu; prototype mode vẫn dùng nền cream. Các bộ iPad là bản resize từ cùng frame/screenshot nguồn, không phải ảnh chụp layout iPad riêng.

Sau khi export, **verify pixel** bằng `sips -g pixelWidth -g pixelHeight <file>` — bộ iPhone chính phải là 1290 × 2796. Kiểm tra alpha bằng `sharp` hoặc `sips` và mở từng PNG để duyệt nội dung/status bar.

---

## 3. Danh sách màn hình cần chụp (tối đa 10 ảnh/thiết bị; đề xuất 8)

Bộ 1.1 có nav mới: Saved và Settings nằm trong menu **More** ở header Poses; Jobs cũng trong More. Chụp đủ 8 màn hình dưới đây, giữ đúng thứ tự file `NN-name.png`.

| # | Màn hình app | Đường vào | Nội dung thể hiện | Caption gợi ý (không bắt buộc) |
| --- | --- | --- | --- | --- |
| 1 | **Poses / Community** (`PosesScreen`) | tab Poses | Grid pose cộng đồng thật từ catalog hiện tại | "Explore the community pose library" |
| 2 | **Pose detail** (`PoseDetailScreen`) | mở card đầu tiên | Ảnh guide thật, tag, How to pose, `Try this pose` | "Open a pose and try it in camera" |
| 3 | **Saved** (`SavedPosesScreen`) | More → Saved | Danh sách pose đã lưu thật của tài khoản demo | "Keep the poses you love in one place" |
| 4 | **Jobs — Finished** (`JobsScreen`) | More → Jobs → tab Finished | Job thật đã `Done · added to Poses`; filter **All**; ẩn các row QA cũ trước khi chụp | "Add your own pose and let us extract it" |
| 5 | **Add pose** (`AddPoseScreen`) | `+` ở header Poses | Form thật (photo picker, Name, Tags, Description, CTA) | "Add a pose to the library" |
| 6 | **Gallery** (`GalleryScreen`) | tab Gallery | Trạng thái gallery thật của máy chụp; simulator không có camera nên chỉ có empty state | "All your captures in one gallery" |
| 7 | **Settings** (`SettingsScreen`) | More → Settings | Tài khoản demo đang đăng nhập, Premium, Appearance, About/version | "Tune the app to your taste" |
| 8 | **Paywall** (`PaywallScreen`) | Settings → Premium | Bảng plan thật từ Test Store (Yearly/Monthly). **KHÔNG mua**, không chụp màn hình xác nhận thanh toán | "Unlock the full pose camera" |
| — | **Camera live + guides** (`CameraScreen`) | tab camera | Cần thiết bị thật để có camera feed. Simulator chỉ có viewfinder đen; **để trống slot này**, không dùng ảnh simulator cho marketing. | Chụp trên thiết bị thật trước khi thêm vào bộ chính |

---

## 4. Checklist điều kiện đẹp

- [ ] **Dữ liệu thật**: community poses đã load; Saved/Jobs là dữ liệu thật của tài khoản demo; ẩn các row QA cũ ("QA …") khỏi Jobs trước khi chụp.
- [ ] **Không chứa thông tin cá nhân/riêng tư**: mặt người phải có consent; không ảnh chứa thẻ/địa chỉ/biển số.
- [ ] **Không đạo cụ không liên quan**: tránh giấy tờ, màn hình thông báo, banner lỗi.
- [ ] **Camera shot**: ánh sáng đủ, người mẫu tạo dáng đúng pose, background sạch.
- [ ] **Theme nhất quán**: đúng neo-brutalism (nền cream `#F6F1E8`, viền `#171717`, hồng `#E7A1B0`).
- [ ] **Status bar hệ thống**: đặt 9:41 + Wi-Fi/cellular + pin đầy bằng `simctl status_bar`; không dựng status bar bằng HTML/ảnh.
- [ ] **Chữ đề xuất không bị cắt**, không overlay chữ khác ngôn ngữ.
- [ ] **Tối đa 10 ảnh/thiết bị**; kích thước đúng chuẩn ASC (verify bằng `sips`).

---

## 5. Quy trình thực hiện & upload

1. Dùng build Dev sẵn có do Feature lead cung cấp — **không build lại** trên lane chụp:

   ```sh
   xcrun simctl install "$SIM_UDID" /tmp/<lane>/dev<NN>/posing.app
   ```

2. Tạo/boot simulator (iPhone 15 Pro Max → 1290 × 2796), bật light mode, đặt status bar và cài build:

   ```sh
   SIM_UDID="<iPhone 15 Pro Max UDID>"
   xcrun simctl boot "$SIM_UDID"
   xcrun simctl bootstatus "$SIM_UDID" -b
   xcrun simctl ui "$SIM_UDID" appearance light
   xcrun simctl status_bar "$SIM_UDID" override --time 9:41 --dataNetwork wifi \
     --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
   xcrun simctl privacy "$SIM_UDID" grant camera posing.camera.app
   xcrun simctl privacy "$SIM_UDID" grant photos posing.camera.app
   xcrun simctl addmedia "$SIM_UDID" <ảnh người mẫu hợp lệ>   # cho photo picker của Add pose
   xcrun simctl install "$SIM_UDID" <posing.app>
   ```

3. Dùng Maestro chỉ để điều hướng (flow tạm đặt ngoài repo, không commit) rồi chụp từng màn hình bằng
   `xcrun simctl io "$SIM_UDID" screenshot /tmp/shots-1.1/iphone-69/NN-name.png`. Mỗi bước kết thúc ở
   màn hình cần chụp, không để keyboard/alert/sheet che nội dung. Tài khoản demo lấy credential từ
   `mobile/iosApp/maestro/e2e.local.env` và truyền qua `maestro -e`, không in ra log.

   > Bộ nguồn 1.1 gồm 8 ảnh (mục 3). Các lệnh `cp` ở bước 4–5 bên dưới vẫn là bộ 4 ảnh của 1.0 —
   > cập nhật danh sách file khi export marketing frame cho 1.1.

4. Copy các ảnh nguồn không chỉnh sửa vào marketing-frame tool:

   ```sh
   MARKETING_FRAME_TOOL="/Users/phamnhuphong/Git/jazzcam/marketing-frame-png-export"
   mkdir -p "$MARKETING_FRAME_TOOL/public/native-screenshots"
   cp /tmp/posing-app-store/screenshots/01-poses-community.png "$MARKETING_FRAME_TOOL/public/native-screenshots/poses-list.png"
   cp /tmp/posing-app-store/screenshots/02-pose-detail.png "$MARKETING_FRAME_TOOL/public/native-screenshots/pose-detail.png"
   cp /tmp/posing-app-store/screenshots/03-search-results.png "$MARKETING_FRAME_TOOL/public/native-screenshots/search-results.png"
   cp /tmp/posing-app-store/screenshots/04-gallery-empty.png "$MARKETING_FRAME_TOOL/public/native-screenshots/gallery.png"
   ```

5. Export native frames và copy bốn file từ ba canvas output vào `assets/screenshots/`:

   ```sh
   cd "$MARKETING_FRAME_TOOL"
   VITE_SCREENSHOT_SOURCE=native npm run export:native
   cd /Users/phamnhuphong/Git/ai-pose
   mkdir -p docs/app-store-publish/assets/screenshots/1242x2688 docs/app-store-publish/assets/screenshots/1284x2778 docs/app-store-publish/assets/screenshots/1290x2796
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_5-portrait/01-pose-library_1242x2688.png" docs/app-store-publish/assets/screenshots/1242x2688/01-poses-community.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_5-portrait/02-pose-detail_1242x2688.png" docs/app-store-publish/assets/screenshots/1242x2688/02-pose-detail-try-pose.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_5-portrait/03-search-discovery_1242x2688.png" docs/app-store-publish/assets/screenshots/1242x2688/03-search-results.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_5-portrait/04-your-gallery_1242x2688.png" docs/app-store-publish/assets/screenshots/1242x2688/04-gallery.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_7-portrait/01-pose-library_1284x2778.png" docs/app-store-publish/assets/screenshots/1284x2778/01-poses-community.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_7-portrait/02-pose-detail_1284x2778.png" docs/app-store-publish/assets/screenshots/1284x2778/02-pose-detail-try-pose.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_7-portrait/03-search-discovery_1284x2778.png" docs/app-store-publish/assets/screenshots/1284x2778/03-search-results.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_7-portrait/04-your-gallery_1284x2778.png" docs/app-store-publish/assets/screenshots/1284x2778/04-gallery.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_9-portrait/01-pose-library_1290x2796.png" docs/app-store-publish/assets/screenshots/1290x2796/01-poses-community.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_9-portrait/02-pose-detail_1290x2796.png" docs/app-store-publish/assets/screenshots/1290x2796/02-pose-detail-try-pose.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_9-portrait/03-search-discovery_1290x2796.png" docs/app-store-publish/assets/screenshots/1290x2796/03-search-results.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/iphone-6_9-portrait/04-your-gallery_1290x2796.png" docs/app-store-publish/assets/screenshots/1290x2796/04-gallery.png
   mkdir -p docs/app-store-publish/assets/screenshots/2048x2732 docs/app-store-publish/assets/screenshots/1668x2388
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-12_9-portrait/01-pose-library_2048x2732.png" docs/app-store-publish/assets/screenshots/2048x2732/01-poses-community.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-12_9-portrait/02-pose-detail_2048x2732.png" docs/app-store-publish/assets/screenshots/2048x2732/02-pose-detail-try-pose.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-12_9-portrait/03-search-discovery_2048x2732.png" docs/app-store-publish/assets/screenshots/2048x2732/03-search-results.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-12_9-portrait/04-your-gallery_2048x2732.png" docs/app-store-publish/assets/screenshots/2048x2732/04-gallery.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-11-portrait/01-pose-library_1668x2388.png" docs/app-store-publish/assets/screenshots/1668x2388/01-poses-community.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-11-portrait/02-pose-detail_1668x2388.png" docs/app-store-publish/assets/screenshots/1668x2388/02-pose-detail-try-pose.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-11-portrait/03-search-discovery_1668x2388.png" docs/app-store-publish/assets/screenshots/1668x2388/03-search-results.png
   cp "$MARKETING_FRAME_TOOL/output/app-store/ipad-11-portrait/04-your-gallery_1668x2388.png" docs/app-store-publish/assets/screenshots/1668x2388/04-gallery.png
   ```

6. Verify kích thước bằng `sips -g pixelWidth -g pixelHeight`, rồi mở và kiểm tra từng PNG. Không upload camera simulator shot có viewfinder đen.
7. Chọn folder theo slot ASC: 6.5" Display → `1242x2688/` hoặc `1284x2778/`; 6.9" Display → `1290x2796/` nếu slot này hiển thị; iPad 13" → `2048x2732/`. Upload thủ công sau khi bộ ảnh được duyệt. Các canvas iPad hiện tại là bản resize từ cùng frame nguồn; chúng không xác nhận layout native trên thiết bị iPad.

---

## 6. Ghi chú & nguyên tắc nội dung

- **Pricing**: 1.1 có Premium (paywall thật, plan lấy từ RevenueCat Test Store trên build Dev). Được chụp màn hình paywall với giá thật của Test Store, nhưng **không mua**, không chụp sheet xác nhận thanh toán/hoá đơn, và bộ cuối phải chụp lại khi giá store thật đã sẵn sàng.
- **Camera simulator**: iOS Simulator không cung cấp camera feed cho build hiện tại, nên không có ảnh camera trong bộ simulator. Chụp camera trên thiết bị thật nếu cần giới thiệu viewfinder/pose overlay.
- **Không claim tính năng chưa có**: Chỉ chụp các tính năng và màn hình có sẵn trong app thật; không ghép camera feed hoặc overlay vào ảnh simulator.
