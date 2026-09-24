# Screenshots Runbook — posing 1.0

**Quy tắc #1: KHÔNG chụp từ prototype HTML mock.** Screenshot nộp ASC phải là màn hình thật của app chạy trên simulator hoặc thiết bị thật.

**Quy tắc #2: Chụp từ build posing hiện tại.** Sử dụng build release/TestFlight hợp lệ của `posing.camera.app`.

---

## 1. Kích thước & resolution

### iPhone (bắt buộc tối thiểu 1 bộ cỡ lớn nhất)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 6.7" | **1290 × 2796** (@3x) | iPhone 15 Pro Max / 15 Plus | Khuyến nghị (bộ chính) |
| 6.5" | **1242 × 2688** (@3x) | iPhone 11 Pro Max / XS Max | Khuyến nghị (phủ thiết bị cũ) |
| 6.1" | 1179 × 2556 (@3x) | iPhone 15 / 14 Pro | Optional |
| 5.5" | 1242 × 2208 (@3x) | iPhone 8 Plus | Optional (thiết bị cũ) |

### iPad (BẮT BUỘC — `TARGETED_DEVICE_FAMILY = "1,2"`)

| Tên hiển thị | Kích thước (px) | Thiết bị gợi ý chụp | Bắt buộc? |
| --- | --- | --- | --- |
| 12.9" | **2048 × 2732** (@2x) | iPad Pro 12.9" | **Bắt buộc** (cỡ lớn nhất hỗ trợ) |
| 11" | 1668 × 2388 (@2x) | iPad Pro 11" | Khuyến nghị |

> Nếu không cung cấp bộ iPad, ASC sẽ báo lỗi khi app hỗ trợ iPad family → **bắt buộc chụp ít nhất 12.9"**.

**Format:** PNG (không alpha) hoặc JPEG, sRGB, không bo góc/chèn khung (Xcode/ASC tự xử lý). Portrait cho iPhone; iPad cho phép cả 2 hướng (app hỗ trợ landscape trên iPad).

---

## 2. Nguồn chụp

| | Simulator | Device thật |
| --- | --- | --- |
| Lệnh | `xcrun simctl io booted screenshot shot.png` (sau khi boot iPhone 15 Pro Max / iPad Pro 12.9) | Xcode Window → Devices → Take Screenshot, hoặc phím cứng |
| Ưu điểm | Lặp lại được, không cần build device, kiểm soát status bar (đặt time cố định qua tiện ích) | Quang học thật, khớp màu |
| Lưu ý | Simulator không hiển thị màu chính xác 100% nhưng đủ chuẩn ASC | Phải đảm bảo build đúng |

Sau khi chụp, **verify pixel** bằng `sips -g pixelWidth -g pixelHeight <file>` — phải khớp bảng kích thước chuẩn.

---

## 3. Danh sách màn hình cần chụp (tối đa 10 ảnh/thiết bị; đề xuất 5)

| # | Màn hình app | Nội dung thể hiện | Caption gợi ý (không bắt buộc) |
| --- | --- | --- | --- |
| 1 | **Poses list — tab Community** (`PosesScreen`, tab Community) | Thư viện pose cộng đồng: có pose thật (standing/walking/jumping/dancing...), ảnh + skeleton, badge Joints, nguồn "Community" | "Browse the community pose library" |
| 2 | **Pose detail + Try Pose** (`PoseDetailScreen`) | Card pose lớn: ảnh gốc + skeleton guide, nút **Try Pose** / Save, metadata (source, published) | "Open any pose for a closer look" |
| 3 | **Gallery** (`GalleryScreen`) | Lưới ảnh đã chụp/thư viện local, nhóm theo ngày, grid/list | "Your private gallery, by day" |
| 4 | **Camera live + guides** (`CameraScreen`) | Viewfinder có grid + guide line, nút chụp màu hồng chính (theme neo-brutalism) | "Capture with grid guides" |
| 5 | **posing guide** (kết quả extraction / pose preview có khung xương 17 joints) | Skeleton guide từ ảnh — minh họa "turn any photo into a pose guide" | "Any photo becomes a pose guide" |

> Tùy chọn: Màn hình Search (`SearchScreen`) có kết quả thật từ API live (`LiveCommunitySearchRepository`).

---

## 4. Checklist điều kiện đẹp

- [ ] **Dữ liệu thật**: community poses đã load; gallery có 4-6 ảnh chụp thật đẹp.
- [ ] **Không chứa thông tin cá nhân/riêng tư**: mặt người phải có consent; không ảnh chứa thẻ/địa chỉ/biển số.
- [ ] **Không đạo cụ không liên quan**: tránh giấy tờ, màn hình thông báo, banner lỗi.
- [ ] **Camera shot**: ánh sáng đủ, người mẫu tạo dáng đúng pose, background sạch.
- [ ] **Theme nhất quán**: đúng neo-brutalism (nền cream `#F6F1E8`, viền `#171717`, hồng `#E7A1B0`).
- [ ] **Status bar cố định**: đặt 9:41 + pin đầy trên simulator.
- [ ] **Chữ đề xuất không bị cắt**, không overlay chữ khác ngôn ngữ.
- [ ] **Tối đa 10 ảnh/thiết bị**; kích thước đúng chuẩn ASC (verify bằng `sips`).

---

## 5. Quy trình thực hiện & upload

1. Cài đặt build release/TestFlight của `posing.camera.app` trên thiết bị chụp.
2. Seed dữ liệu: đăng nhập vào app → load Community, chụp thử 1-2 pose, tạo 1 pose guide.
3. Chụp ảnh màn hình theo danh sách ở mục 3.
4. Verify kích thước bằng `sips` và kiểm tra chất lượng hình ảnh.
5. Upload vào App Store Connect → App Store tab → Media Manager / Screenshot slots tương ứng cho iPhone và iPad.

---

## 6. Ghi chú & nguyên tắc nội dung

- **Paywall / IAP**: Subscription đã tích hợp (`premium_yearly`/`premium_monthly`). Được phép chụp paywall app thật, không dùng mockup prototype và không hiển thị giá giả.
- **Không claim tính năng chưa có**: Chỉ chụp các tính năng và màn hình có sẵn trong app thật; không chụp overlay trực tiếp trong camera nếu chưa hỗ trợ.
