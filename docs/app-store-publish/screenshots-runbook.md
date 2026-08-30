# Screenshots Runbook — Snap Pose 1.0

> **Lane:** `app-store-publish-prep` · **Status:** PARTIAL — đã chụp preview trên simulator; bộ ASC chính thức vẫn chờ PO/executor.
> **Baseline:** HEAD `49a2eb3`, staged=0 · **Build trên máy chụp:** build 1.0 (4) — TestFlight hoặc local release

**Quy tắc #1: KHÔNG chụp từ `docs/prototype/` (HTML mock).** Screenshot nộp ASC phải
là **màn hình thật của app chạy** trên simulator/device, nếu không sẽ bị reject
("screenshots must show the actual app") và sai phạm với mô tả.

**Quy tắc #2: KHÔNG chụp sau khi thay đổi code.** Màn hình phải khớp build 1.0 (4)
mà TestFlight đã xác nhận `VALID_BINARY`.

## Preview assets đã capture (2026-08-27)

Simulator: **Snap Pose Screenshot**, iPhone 16, iOS 26.0, UDID
`4C621D71-971E-449D-A196-BEEBF12A9BBD`; app `camerapose.app`; build thường
Debug từ `/tmp/ai-pose-screenshot-derived/Build/Products/Debug-iphonesimulator/iosApp.app`.

| Asset | Kết quả | Ghi chú |
| --- | --- | --- |
| `assets/screenshots/iphone-16/01-poses-community.png` | ✅ 1179×2556, RGB/no-alpha | Community loaded, 39 poses |
| `assets/screenshots/iphone-16/02-pose-detail-try-pose.png` | ✅ 1179×2556, RGB/no-alpha | Pose detail + Try Pose |
| `assets/screenshots/iphone-16/03-gallery.png` | ✅ 1179×2556, RGB/no-alpha | Gallery empty state: `No photos yet`; **không marketing-ready** |
| `assets/screenshots/iphone-16/04-search.png` | ✅ 1179×2556, RGB/no-alpha | Search loaded, 20 poses |
| `assets/screenshots/iphone-16/03-gallery-prototype-reference.png` | ✅ 1179×2556, RGB/no-alpha | **Prototype reference only**; 5 sample photos; `PROTOTYPE_REFERENCE_NOT_ASC_FINAL` |

Đây là evidence/preview kích thước native iPhone 16, **không phải** bộ resolution
ASC yêu cầu. Vẫn cần capture lại trên 6.7\" (1290×2796), 6.5\" (1242×2688)
và iPad 12.9\" (2048×2732) theo mục 1. Gallery cần được seed bằng ảnh có
consent trước khi dùng làm screenshot marketing.

---

## 1. Kích thước & resolution (tối thiểu)

### iPhone (app chạy trên iPhone — bắt buộc tối thiểu 1 bộ cỡ lớn nhất)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 6.7" | **1290 × 2796** (@3x) | iPhone 15 Pro Max / 15 Plus | Khuyến nghị (bộ chính) |
| 6.5" | **1242 × 2688** (@3x) | iPhone 11 Pro Max / XS Max | Khuyến nghị (phủ thiết bị cũ) |
| 6.1" | 1179 × 2556 (@3x) | iPhone 15 / 14 Pro | Optional |
| 5.5" | 1242 × 2208 (@3x) | iPhone 8 Plus | Optional (thiết bị rất cũ) |

### iPad (BẮT BUỘC — `TARGETED_DEVICE_FAMILY = "1,2"` trong pbxproj:366/388, app chạy trên iPad)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 12.9" | **2048 × 2732** (@2x) | iPad Pro 12.9" | **Bắt buộc** (cỡ lớn nhất hỗ trợ) |
| 11" | 1668 × 2388 (@2x) | iPad Pro 11" | Khuyến nghị |

> Nếu không cung cấp bộ iPad, ASC sẽ báo lỗi khi app có family iPad → **bắt buộc
> chụp ít nhất 12.9"**. Nếu PO muốn iPhone-only để bỏ bộ iPad → đó là thay đổi code
> (TARGETED_DEVICE_FAMILY), nằm ngoài lane này, cần quyết định riêng.

**Format:** PNG (không alpha) hoặc JPEG, sRGB, không bo góc/chèn khung (Xcode/ASC
tự xử lý). Portrait cho iPhone; iPad cho phép cả 2 hướng (app hỗ trợ landscape trên iPad).

## 2. Nguồn chụp

| | Simulator | Device thật |
| --- | --- | --- |
| Lệnh | `xcrun simctl io booted screenshot shot.png` (sau khi boot iPhone 15 Pro Max / iPad Pro 12.9) | Xcode Window → Devices → Take Screenshot, hoặc phím cứng |
| Ưu điểm | Lặp lại được, không cần build device, kiểm soát status bar (đặt time cố định qua tiện ích) | Quang học thật, khớp màu |
| Lưu ý | Simulator không hiển thị màu chính xác 100% nhưng đủ chuẩn ASC | Phải đảm bảo build 4 đúng |

Sau khi chụp, **verify pixel** bằng `sips -g pixelWidth -g pixelHeight <file>` —
phải khớp bảng trên (1290×2796, 1242×2688, 2048×2732,...).

## 3. Danh sách màn hình cần chụp (tối đa 10 ảnh/thiết bị; đề xuất 5)

Số 1-5 là bộ chính phản ánh đúng mô tả; **không chụp màn hình tính năng chưa ship** (paywall — xem #6).

| # | Màn hình app | Nội dung thể hiện | Caption gợi ý (không bắt buộc) |
| --- | --- | --- | --- |
| 1 | **Poses list — tab Community** (`PosesScreen`, tab Community) | Thư viện pose cộng đồng: có pose thật (standing/walking/jumping/dancing...), ảnh + skeleton, badge Joints, nguồn "Community" | "Browse the community pose library" |
| 2 | **Pose detail + Try Pose** (`PoseDetailScreen`) | Card pose lớn: ảnh gốc + skeleton guide, nút **Try Pose** / Save, metadata (source, published) | "Open any pose for a closer look" |
| 3 | **Gallery** (`GalleryScreen`) | Lưới ảnh đã chụp/thư viện local, nhóm theo ngày, grid/list | "Your private gallery, by day" |
| 4 | **Camera live + guides** (`CameraScreen`) | Viewfinder có grid + guide line, nút chụp màu hồng chính (theme neo-brutalism) | "Capture with grid guides" |
| 5 | **Snap Pose guide** (kết quả extraction / pose preview có khung xương 17 joints) | Skeleton guide từ ảnh — minh họa "turn any photo into a pose guide" | "Any photo becomes a pose guide" |
| 6 | **Paywall** — ⛔ **KHÔNG chụp cho v1.0** | FEAT-011 `proposed`, chưa ở build 4; chụp = screenshots không đúng app → reject | — |

> Nếu PO muốn màn hình Search (FEAT-003/`SearchScreen`) trong bộ ảnh: chụp kèm 1 ảnh
> search có kết quả thật (trade: 1 trong 10 slot). Kiểm tra trước khi chụp rằng search
> trả kết quả live (LiveCommunitySearchRepository) chứ không phải mock.

## 4. Điều kiện "đẹp" (checklist trước khi bấm nút)

- [ ] **Dữ liệu thật**: community poses đã load (không empty/error/loading/skeleton placeholder); gallery có 4-6 ảnh đẹp.
- [ ] **Không chứa thông tin cá nhân/riêng tư**: mặt người được sử dụng phải có consent; không ảnh gia đình/bạn bè tùy tiện; không ảnh chứa thẻ/địa chỉ/biển số.
- [ ] **Không đạo cụ không liên quan**: tránh giấy tờ, màn hình thông báo, banner lỗi.
- [ ] **Camera shot**: ánh sáng đủ, người mẫu (người thật) tạo dáng đúng pose, background sạch.
- [ ] **Theme nhất quán**: đúng neo-brutalism (nền cream `#F6F1E8`, viền `#171717`, hồng `#E7A1B0`), không màn hình khác version.
- [ ] **Status bar/time giả cố định** (simulator: đặt 9:41 + ngày cố định) hoặc chấp nhận thật; không để pin sắp hết.
- [ ] **Chữ đề xuất không bị cắt**, không overlay chữ khác ngôn ngữ.
- [ ] **Tối đa 10 ảnh/thiết bị**; kích thước đúng bảng mục 1 (verify bằng `sips`).
- [ ] **Không upload ảnh có watermark "prototype"** hay bất kỳ dấu hiệu mock nào.

## 5. Quy trình đề xuất

> Preview iPhone 16 đã có ở mục trên; các bước dưới đây là cho bộ ASC chính thức.

1. Build 1.0 (4) lên iPhone 15 Pro Max simulator + iPad Pro 12.9 simulator (hoặc device).
2. Seed dữ liệu: đăng nhập vào app → load Community (nếu cần network), chụp thử 1-2 pose, tạo 1 pose guide.
3. Chụp theo bảng mục 3; lưu vào `docs/app-store-publish/assets/screenshots/<size>/`.
   (Thư mục asset — lane này chỉ chép runbook; executor tự tạo thư mục khi chụp.)
4. Verify `sips` kích thước + mở mắt xem chất lượng.
5. Đưa PO duyệt ảnh **trước khi** điền ASC.

## 6. Ghi chú cảnh báo

- **⛔ Paywall/IAP**: KHÔNG chụp paywall cho v1.0 (chưa ship). Khi FEAT-011 ship ở bản
  sau, lúc đó mới bổ sung screenshot paywall theo thiết kế prototype tương lai.
- **⛔ Không chụp màn hình "Try Pose overlay trên camera"** — tính năng chưa transfer
  overlay (README limitation). Chụp sẽ bị review "app không có tính năng này".
- Nếu chụp trên **device thật**, dùng build release/TestFlight build 4 — không chụp
  debug build có banner/log khác lạ.

---

## 7. Thực thi lại — Hoang Trung (replacement Linh) — TRẠNG THÁI: ⛔ BLOCKED_NEEDS_LEAD

> **Ngày:** 2026-08-2x · **Gói:** Replacement execution packet (Code Vuong) — KHÔNG recapture/build/simulator. Chỉ dùng asset có sẵn.
> **Escalation:** Chu Du (Tuong quan). Không liên hệ Code Vuong trực tiếp.

### 7.1 Đã làm (bounded, reversible)
- Đặt (fit/place) 4 ảnh real-app (01-poses-community, 02-pose-detail-try-pose, 03-gallery, 04-search) từ bộ iphone-16 (1179×2556) lên canvas ASC:
  - assets/screenshots/1242x2688/*.png — 1242×2688 (iPhone 6.5", size ASC chuẩn)
  - assets/screenshots/1284x2778/*.png — 1284×2778 (target phụ theo packet)
- Giữ tỉ lệ (scale theo chiều cao, letterbox ~1px mỗi cạnh, nền cream #F6F1E8) → không méo. Xuất PNG / sRGB / hasAlpha=no (verify sips + ImageMagick: Colorspace sRGB, color-type 2).
- LOẠI TRỪ 03-gallery-prototype-reference.png (đánh dấu PROTOTYPE_REFERENCE_NOT_ASC_FINAL).

### 7.2 App Preview
- KHÔNG có App Preview nào (không .mov/.mp4/.m4v trong docs/app-store-publish). Runbook §Status "đã chụp preview" chỉ ám chỉ PNG simulator. → báo: no preview; nothing transformed.

### 7.3 asc-mcp
- KHÔNG available/cấu hình: không binary asc-mcp, ASC_KEY_ID unset, không ~/.config/asc-mcp/companies.json. → không upload; giữ asset local; manual instructions bên dưới. Không invent credentials, không upload TestFlight, không đổi bundle ID.

### 7.4 Xung đột — invariant "represent current Snap Pose" KHÔNG thể thoả/verify (→ BLOCKED)
1. Môi trường không render được ảnh (Read tool: "model does not support images") → không thể verify trực quan branding/placeholder/status bar/debug bar. Không claim content compliance.
2. Branding mismatch: mobile/iosApp/iosApp/Info.plist (dòng 16,18) = "Snap Pose"; runbook + bộ ảnh thuộc kỷ nguyên branding cũ. Có tín hiệu rebrand → ảnh cũ có thể không khớp Snap Pose hiện tại. Không xác nhận là Snap Pose hiện tại.
3. Baseline mismatch: runbook baseline 49a2eb3 vs HEAD b061718 (product source đã đổi). Ảnh từ Debug simulator build tại /tmp/ai-pose-screenshot-derived, KHÔNG phải release/TestFlight VALID. Nội dung có thể không khớp Snap Pose hiện tại.
4. Gallery empty state: 03-gallery.png "No photos yet" — runbook ghi "không marketing-ready".

→ Ảnh 1242x2688/1284x2778 §7.1 chỉ là resize/letterbox của bộ ảnh cũ, CHƯA chứng nhận là current Snap Pose, KHÔNG upload ASC nếu không có quyết định Chu Du (cần recapture Snap Pose hiện tại).

### 7.5 Cảnh báo 1284×2778
- Bảng ASC chuẩn: 6.5"=1242×2688, 6.7"=1290×2796, 6.9"=1320×2868. 1284×2778 KHÔNG chuẩn → ASC exact-match-only có thể reject. Khuyến nghị Chu Du/PO xác nhận; 1242×2688 (6.5") an toàn. Giữ cả 2 thư mục.

### 7.6 sips evidence (derived)
| File | W | H | hasAlpha | space |
| --- | --- | --- | --- | --- |
| 1242x2688/01-poses-community.png | 1242 | 2688 | no | RGB (sRGB ICC) |
| 1242x2688/02-pose-detail-try-pose.png | 1242 | 2688 | no | RGB (sRGB ICC) |
| 1242x2688/03-gallery.png | 1242 | 2688 | no | RGB (sRGB ICC) |
| 1242x2688/04-search.png | 1242 | 2688 | no | RGB (sRGB ICC) |
| 1284x2778/01-poses-community.png | 1284 | 2778 | no | RGB (sRGB ICC) |
| 1284x2778/02-pose-detail-try-pose.png | 1284 | 2778 | no | RGB (sRGB ICC) |
| 1284x2778/03-gallery.png | 1284 | 2778 | no | RGB (sRGB ICC) |
| 1284x2778/04-search.png | 1284 | 2778 | no | RGB (sRGB ICC) |

### 7.7 Manual upload instructions (khi Chu Du duyệt + có ảnh Snap Pose verified)
1. Bắt buộc recapture Snap Pose hiện tại từ build release/TestFlight VALID (không Debug) tại size ASC chuẩn: 6.5" 1242×2688 (6.7" 1290×2796, 6.9" 1320×2868), + iPad 12.9" 2048×2732 (app có iPad family). Cần Chu Du gỡ lệnh no-recapture hoặc PO cung cấp ảnh mới.
2. Seed dữ liệu thật (community loaded; gallery 4-6 ảnh consent); tránh placeholder/debug/empty state.
3. Upload qua ASC web (App Store Connect → App Store tab → screenshot slots) HOẶC asc-mcp nếu cấu hình (credentials thật).
4. TUYỆT ĐỐI: không đổi bundle ID, không upload TestFlight, không invent credentials, không dùng prototype-reference làm ASC final.
5. App Preview: tạo video chuẩn ASC từ build thật nếu muốn; hiện tại không có để transform.

### 7.8 Scope & deviations
- Chỉ sửa docs/app-store-publish/assets (thêm 2 thư mục derived) + runbook này.
- KHÔNG sửa product source, KHÔNG file lane khác, KHÔNG /tmp/aipose-release, KHÔNG commit.
- Deviation: phát sinh 1284x2778 (size không chuẩn ASC) theo chữ packet — flagged §7.5.
- Escalation: không upload ASC + không claim current Snap Pose do xung đột §7.4 → BLOCKED_NEEDS_LEAD gửi Chu Du.
