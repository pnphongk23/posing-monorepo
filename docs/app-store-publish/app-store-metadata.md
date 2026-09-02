# App Store Metadata — Snap Pose 1.0

> **Lane:** `app-store-publish-prep` · **Status:** DRAFT — chờ PO duyệt từng mục
> **Baseline:** HEAD `49a2eb3`, staged=0 · **Build:** 1.0 (6), TestFlight `VALID_BINARY`

Mọi copy dưới đây được scout từ production behavior (README, docs/harness/features,
docs/prototype, code audit release-prep) — **không** hứa hẹn tính năng chưa ship.

---

## Tóm tắt đề xuất (bảng quyết định nhanh)

| Field | Giá trị đề xuất | Giới hạn ASC | Chữ | PO chốt |
| --- | --- | --- | --- | --- |
| **App name** | `Snap Pose` | ≤30 | 9 | ☐ |
| **Subtitle** | `Pose camera & AI guides` | ≤30 | 23 | ☐ |
| **Primary language** | English (US) | — | — | ☐ |
| **Category (primary)** | `Lifestyle` | — | — | ☐ |
| **Category (secondary)** | `Photo & Video` | — | — | ☐ |
| **Keywords** | xem dưới | ≤100 | 91 | ☐ |
| **Description** | xem dưới | ≤4000 | 1.362 | ☐ |
| **What's New** | xem dưới | ≤4000 | 351 | ☐ |
| **Promotional text** (không bắt buộc) | xem dưới | ≤170 | ~110 | ☐ |

> Lưu ý: **Subtitle** được giới thiệu iOS 11+; nếu PO muốn ẩn thì bỏ trống (không hại gì).
> App name lúc publish dùng `Snap Pose`; bundle id giữ nguyên `camerapose.app`
> (không thể đổi sau khi phát hành — đổi = app mới).

---

## 1. App name — `Snap Pose`

- Ngắn, mô tả đúng sản phẩm (pose-reference camera).
- Không trùng app đối thủ, không chứa từ chung chung bị từ chối ("Free", "Plus", "Pro" không được dùng làm tên).
- Đề xuất thay thế nếu PO muốn rõ hơn: `Snap Pose Camera` (chưa tính giới hạn) — không khuyến nghị (dài hơn, trùng nhịp với đối thủ đặt tên "X Snap Pose Camera").

## 2. Subtitle (≤30) — `Pose camera & AI guides`

Ngắn gọn: camera pose + hướng dẫn tư thế từ AI.

## 3. Primary category — `Lifestyle` (+ secondary `Photo & Video`)

**Lý do:**
- App là **pose-reference camera** (sáng tạo ảnh), không thu thập dữ liệu sức khỏe
  (không HealthKit) → tránh khu vực review nghiêm ngặt của `Health & Fitness`.
- `Photo & Video` đúng tính chất camera nhưng ít đúng với "hướng dẫn tư thế";
  đặt secondary để cân bằng.
- PO có thể chọn `Health & Fitness` nếu muốn trúng audit tìm kiếm fitness — nhưng
  sẽ kéo theo kỳ vọng nội dung sức khỏe và checklist review cao hơn.

## 4. Keywords (≤100 ký tự; ASC tính ký tự, dấu phẩy phân tách)

```
pose camera,pose reference,pose guide,stick figure,yoga,dance,workout,stretch,photo,overlay
```

- Độ dài: **91/100 ký tự** (đã đếm thủ công — run `printf '...' | wc -m` để xác nhận).
- 10 token; không chứa tên app khác, không chứa từ bị cấm (chuẩn ASC: không tên thương hiệu app khác, không từ như "free"/"deal").
- Đang sửa `#keyword` không dùng cho iOS (đó là Google Play).

## 5. Description — English (≈1.650 ký tự; giới hạn 4.000)

```
Snap Pose is the pose-reference camera for your iPhone. Find a pose you love, turn any photo into a clean Snap Pose guide, and capture your own best version — all in one app.

THE COMMUNITY POSE LIBRARY
Browse a growing library of published poses, from standing and walking to jumping, dancing and arms-up. Search poses by title, open any card for a closer look, and keep your favorites close at hand. New poses are added regularly.

SNAP POSE GUIDE FROM YOUR PHOTO
See a pose you want to recreate? Pick a photo from your gallery and Snap Pose detects the body joints to build a clean stick-figure guide that shows exactly where your arms, legs and body should be. Follow it for your next capture.

CAPTURE WITH GUIDES
Use the built-in camera with a clean grid and alignment guides to line up your shot. Take as many takes as you like — every capture is saved to your personal gallery automatically.

YOUR PRIVATE GALLERY
Your photos live on your device, grouped by day, ready to browse in grid or list view. Delete or keep them anytime. Your captures stay in your own library — Snap Pose never sells or shares your data.

A DESIGN YOU'LL ENJOY
A playful, high-contrast interface with clear feedback for every action. No clutter, no dark patterns — just a focused tool for your next great shot.

Ready to strike a pose? Download Snap Pose and start your next photo project.
```

**Guardrails đã áp dụng (không claim khi chưa ship):**
- ✅ Community pose library — browse/search published poses (FEAT-003 + LiveCommunitySearchRepository; nội dung team publish).
- ✅ Snap Pose guide từ ảnh gallery — extraction qua provider (FEAT-004; mobile trigger từ gallery picker — tech-arch line 91).
- ✅ Camera + grid guides, gallery local day-grouped (FEAT-001/002).
- ⚠️ **KHÔNG claim**: live pose overlay trong camera ("Try Pose overlay" chưa transfer —
  README limitation). Copy dùng "keep your favorites close at hand" thay cho overlay.
- ⚠️ **KHÔNG claim**: UGC community (chưa bật — privacy-ugc-compliance Giai đoạn 1).
- ⚠️ **KHÔNG claim**: IAP/subscription/paywall (FEAT-011 mới `proposed`, chưa ở build 6).

## 6. What's New — version 1.0 (≈340 ký tự)

```
Welcome to Snap Pose! This first release brings the complete pose-workflow to your iPhone:
• Browse the community pose library and search by title
• Turn any photo into a clean AI stick-figure pose guide
• Capture with camera grid guides into your private gallery
• Production networking, smoother transitions, and Firebase-powered stability monitoring
```

Đúng với build 4: FEAT-010 Firebase (Analytics/Crashlytics/Remote Config) + endpoint
production (railway — dirty tree đã revert khỏi ngrok, `AppConfig.kt:11`) + mượt hơn
ở list/transition (fix M1-M5 trong release-prep).

## 7. Promotional text (không bắt buộc, ≤170)

```
New poses drop regularly. Follow your favorites and turn any photo into a Snap Pose guide — strike the pose.
```

## 8. Bản VI (annex — dùng nếu PO chốt phát hành đa ngôn ngữ)

> PO chốt ngôn ngữ phát hành. Đề xuất: **EN primary** cho lần đầu (phủ thị trường
> lớn nhất), bổ sung VI sau khi app có xác nhận tăng trưởng (tránh dịch sai thuật
> ngữ trước khi chốt thương mại FEAT-011).

**Subtitle VI:** `Máy ảnh tư thế & hướng dẫn AI` (25 ký tự)

**Keywords VI:** `chụp ảnh pose,máy ảnh tư thế,hướng dẫn pose,pose mẫu,yoga,dance,tập luyện,giãn cơ,ảnh,overlay`

**Description VI (draft):**

```
Snap Pose là máy ảnh chụp tư thế (pose-reference camera) dành cho iPhone. Tìm một tư thế bạn thích, biến bất kỳ bức ảnh nào thành hướng dẫn pose rõ ràng nhờ AI, và chụp phiên bản đẹp nhất của riêng bạn — tất cả trong một ứng dụng.

CỘNG ĐỒNG TƯ THẾ
Duyệt thư viện tư thế đang phát triển: từ đứng, đi bộ đến nhảy, khiêu vũ và giơ tay. Tìm kiếm theo tên, mở chi tiết từng pose và lưu tư thế yêu thích. Nội dung mới được đội ngũ cập nhật thường xuyên.

HƯỚNG DẪN POSE TỪ ẢNH CỦA BẠN
Muốn tái hiện một tư thế? Chọn ảnh từ thư viện, Snap Pose phát hiện khớp cơ thể và tạo hướng dẫn khung xương rõ ràng, chỉ chính xác vị trí tay, chân và thân bạn cần đặt theo.

CHỤP VỚI ĐƯỜNG CĂN CHỈNH
Máy ảnh tích hợp với lưới và đường căn chỉnh giúp bạn canh khung hình. Chụp bao nhiêu cũng được — mọi ảnh đều được lưu tự động vào thư viện cá nhân.

THƯ VIỆN RIÊNG TƯ
Ảnh của bạn nằm ngay trên thiết bị, nhóm theo ngày, xem dạng lưới hoặc danh sách. Xóa hoặc giữ bất cứ lúc nào. Ảnh chụp chỉ nằm trong thư viện của bạn — Snap Pose không bao giờ bán hoặc chia sẻ dữ liệu của bạn.

Sẵn sàng tạo dáng? Tải Snap Pose và bắt đầu dự án ảnh tiếp theo của bạn.
```

**What's New VI (draft):**

```
Chào mừng đến với Snap Pose! Phiên bản đầu tiên mang trọn quy trình chụp pose đến iPhone:
• Duyệt thư viện tư thế cộng đồng và tìm kiếm theo tên
• Biến bất kỳ ảnh nào thành hướng dẫn khung xương rõ ràng nhờ AI
• Chụp ảnh với lưới camera vào thư viện riêng tư của bạn
• Mạng production ổn định, chuyển màn hình mượt hơn và theo dõi ổn định qua Firebase
```

---

## Nguồn bằng chứng (source of truth)

- README.md — mô tả sản phẩm & limitations (không claim overlay camera).
- docs/harness/features/FEAT-003 (browse/search), FEAT-004 (extract), FEAT-001/002 (camera/gallery).
- docs/evidence/260826-release-prep-checklist.md — V6 icon, V8 bundle, M1 endpoint prod (đã revert trong tree), M2 CFBundleVersion=4.
- docs/privacy-ugc-compliance.md — Giai đoạn 1: admin-only publish (chưa UGC).
- DEC-008 — pricing đề xuất (FEAT-011 pending — không claim trong copy).
