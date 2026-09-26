# App Icon Check — posing 1.0

File gốc: `mobile/iosApp/iosApp/Assets.xcassets/AppIcon.appiconset/`

## 1. Kết quả verify tự động (`sips`/`ls`/`plutil`)

| Kiểm tra | Kết quả | Bằng chứng |
| --- | --- | --- |
| File đủ cỡ 20/29/40/60/76/83.5/1024 + @1x/@2x/@3x, đủ idiom iphone/ipad/ios-marketing | ✅ PASS | 19 file PNG trong appiconset; `Contents.json` đủ 18 entry + info |
| **1024 marketing không alpha** (yêu cầu cứng của ASC) | ✅ PASS | `sips -g hasAlpha AppIcon-1024.png` → `hasAlpha: no` |
| Toàn bộ file còn lại không alpha | ✅ PASS | 19/19 `hasAlpha: no` |
| 1024 đúng **1024×1024 px** | ✅ PASS | `sips -g pixelWidth/pixelHeight` → 1024×1024 |
| Các cỡ khác đúng px (20→20, 29→29, 40→40, 60→60/120/180, 76→76/152, 83.5→167) | ✅ PASS | sips từng file (xem bảng dưới) |
| `Contents.json` khớp đúng filename/idiom/scale | ✅ PASS | đọc trực tiếp, mapping 1-1 |

### Bảng pixel đã xác nhận

| File | px | | File | px |
| --- | --- | --- | --- | --- |
| AppIcon-20@1x | 20 | | AppIcon-60@2x | 120 |
| AppIcon-20@2x (iphone) | 40 | | AppIcon-60@3x | 180 |
| AppIcon-20@2x-ipad | 40 | | AppIcon-76@1x | 76 |
| AppIcon-20@3x | 60 | | AppIcon-76@2x | 152 |
| AppIcon-29@1x | 29 | | AppIcon-83.5@2x | 167 |
| AppIcon-29@2x (iphone) | 58 | | AppIcon-1024 | **1024** |
| AppIcon-29@2x-ipad | 58 | | | |
| AppIcon-29@3x | 87 | | | |
| AppIcon-40@1x | 40 | | | |
| AppIcon-40@2x (iphone) | 80 | | | |
| AppIcon-40@2x-ipad | 80 | | | |
| AppIcon-40@3x | 120 | | | |

## 2. Không cần sửa — chỉ còn QA thị giác (PO/UCP)

Kỹ thuật: PASS — **không cần UCP sửa icon vì lỗi kỹ thuật**. ASC hiện tại lấy
App Store icon từ 1024 marketing trong binary (không phải upload riêng — nếu ASC
show ô trống thì upload chính file `AppIcon-1024.png` đó).

### Checklist QA thị giác (con người nhìn — PO hoặc UCP mở file)

- [ ] **Không chứa chữ/từ** (Apple cấm text trong icon — ngay cả tên app).
- [ ] **Không bo góc sẵn** (App Store tự bo; icon gốc phải vuông, alpha chỉ ở
  vùng ngoài cùng nếu thiết kế bo sẵn — nhưng boost verified no-alpha).
- [ ] **Không viền/khung bao quanh** diện tích lớn (sẽ bị "scaled down" khi render).
- [ ] Nhìn rõ ở **29px** (folder nhỏ) và không mất chi tiết ở 180px.
- [ ] Màu khớp theme: viền `#171717`, nền cream, hồng `#E7A1B0` (đúng neo-brutalism).
- [ ] Không giống/trùng logo app khác (pose/fitness category).
- [ ] Thử nghiệm trên Home screen tối/sáng đều đọc được.

## 3. Quyết định xử lý

- Nếu QA thị giác **PASS** → không làm gì thêm, icon sẵn sàng cho submission.
- Nếu QA **FAIL** (chữ trong icon, bo góc lỗi, alpha mép) → **UCP sửa file gốc trong
  appiconset** (chỉ cần sửa file ảnh + regen, không phải đổi code), tạo build mới
  (CFBundleVersion 5) — **báo PO trước khi làm** vì sẽ đụng mobile assets + cần upload lại.
- Lưu ý: sửa icon = build mới = phải up TestFlight lại — nên ưu tiên giữ icon hiện
  tại nếu QA chấp nhận được, tránh tốn một vòng build cho release đầu.
