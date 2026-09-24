# App Store Metadata — posing 1.0

Bộ nội dung metadata nộp App Store Connect cho ứng dụng **posing** (`posing.camera.app`).

- **Terms of Service:** https://sites.google.com/view/posingapp/terms-of-service
- **Privacy Policy:** https://sites.google.com/view/posingapp/privacy-policy

---

## Tóm tắt đề xuất (bảng quyết định nhanh)

| Field | Giá trị đề xuất | Giới hạn ASC | Chữ | PO chốt |
| --- | --- | --- | --- | --- |
| **App name** | `posing` | ≤30 | 6 | ☑ |
| **Subtitle** | `Pose camera & AI guides` | ≤30 | 23 | ☐ |
| **Primary language** | English (US) | — | — | ☐ |
| **Category (primary)** | `Lifestyle` | — | — | ☐ |
| **Category (secondary)** | `Photo & Video` | — | — | ☐ |
| **Keywords** | xem dưới | ≤100 | 91 | ☐ |
| **Description** | xem dưới | ≤4000 | xem §5 | ☐ |
| **What's New** | xem dưới | ≤4000 | 310 | ☐ |
| **Promotional text** (không bắt buộc) | xem dưới | ≤170 | ~110 | ☐ |

---

## 1. App name — `posing`

- Ngắn, mô tả đúng sản phẩm (pose-reference camera).
- Không trùng app đối thủ, không chứa từ chung chung bị từ chối ("Free", "Plus", "Pro" không được dùng làm tên).
- Tên App Store và tên hiển thị đã chốt: `posing`.

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

## 5. Description — English (giới hạn 4.000 ký tự)

```
posing is the pose-reference camera for your iPhone. Find a pose you love, turn any photo into a clean posing guide, and capture your own best version — all in one app.

THE COMMUNITY POSE LIBRARY
Browse a growing library of published poses, from standing and walking to jumping, dancing and arms-up. Search poses by title, open any card for a closer look, and keep your favorites close at hand. New poses are added regularly.

POSING GUIDE FROM YOUR PHOTO
See a pose you want to recreate? Pick a photo from your gallery and posing detects the body joints to build a clean stick-figure guide that shows exactly where your arms, legs and body should be. Follow it for your next capture.

CAPTURE WITH GUIDES
Use the built-in camera with a clean grid and alignment guides to line up your shot. Take as many takes as you like — every capture is saved to your personal gallery automatically.

YOUR PRIVATE GALLERY
Your captures are stored on your device, grouped by day, ready to browse in grid or list view. Delete or keep them anytime. If you request a pose guide, the selected image is uploaded securely for processing by our backend and AI provider. See the Privacy Policy for details.

A DESIGN YOU'LL ENJOY
A playful, high-contrast interface with clear feedback for every action. No clutter, no dark patterns — just a focused tool for your next great shot.

PREMIUM (AUTO-RENEWABLE SUBSCRIPTION)
posing offers two auto-renewable Premium plans: Monthly and Annual. Premium unlocks the paid pose workflow — using a community pose as your camera guide (Try Pose) and the capture flow it opens. The localized price of each plan is shown in the app before you buy, and on this product page under In-App Purchases. Payment is charged to your Apple ID account at confirmation of purchase. The subscription renews automatically for the same period unless you cancel at least 24 hours before the current period ends. Manage or cancel it anytime in your App Store account settings; cancellation takes effect at the end of the current period and unused time is not refunded. Deleting the app or your account does not cancel the subscription.

Terms of Use (EULA): https://sites.google.com/view/posingapp/terms-of-service
Privacy Policy: https://sites.google.com/view/posingapp/privacy-policy

Ready to strike a pose? Download posing and start your next photo project.
```

> Legal URLs Posing (Google Sites `posingapp`) đã publish và trả `200` khi truy cập.

**Đếm ký tự:** 2.358 / 4.000 (recounted with python len on text between code fences: 2.358 chars, ≤4.000).

```bash
awk '/^## 5\. Description/{f=1} f&&/^```$/{n++; next} f&&n==1' \
  docs/app-store-publish/app-store-metadata.md | wc -m
```

**Guardrails đã áp dụng (không claim khi chưa ship):**
- ✅ Community pose library — browse/search published poses (FEAT-003 + LiveCommunitySearchRepository; nội dung team publish).
- ✅ posing guide từ ảnh gallery — extraction qua provider (FEAT-004; mobile trigger từ gallery picker — tech-arch line 91).
- ✅ Camera + grid guides, gallery local day-grouped (FEAT-001/002).
- ⚠️ **KHÔNG claim**: live pose overlay trong camera ("Try Pose overlay" chưa transfer —
  README limitation). Copy dùng "keep your favorites close at hand" thay cho overlay.
- ⚠️ **KHÔNG claim**: UGC community (chưa bật — privacy-ugc-compliance Giai đoạn 1).
- ✅ **ĐÃ ship (từ build có FEAT-011)**: paywall + 2 gói auto-renewable
  (`premium_yearly`, `premium_monthly`). Vì vậy Description **phải** disclose
  subscription + link EULA/Privacy — đây không còn là mục "không claim" mà là mục
  **phải khai**. Phạm vi Premium thật trong build native: **Try Pose** là gate cứng
  (`PosesFeature.swift:657, 738-740`); camera + gallery chỉ mở paywall affordance
  (`PosesFeature.swift:393`, `GalleryFeature.swift:285`, `SupportScreens.swift:99, 284`).
  Copy trên chỉ hứa "dùng pose community làm camera guide (Try Pose) và capture flow
  nó mở ra" — không hứa thêm.

## 6. What's New — version 1.0 (≤4.000 ký tự)

```
Welcome to posing! This first release brings the complete pose-workflow to your iPhone:
• Browse the community pose library and search by title
• Turn any photo into a clean AI stick-figure pose guide
• Capture with camera grid guides into your private gallery
• Production networking and smoother transitions
```

## 7. Promotional text (không bắt buộc, ≤170)

```
New poses drop regularly. Follow your favorites and turn any photo into a posing guide — strike the pose.
```

## 8. Bản VI (phụ lục)

**Subtitle VI:** `Máy ảnh tư thế & hướng dẫn AI` (25 ký tự)

**Keywords VI:** `chụp ảnh pose,máy ảnh tư thế,hướng dẫn pose,pose mẫu,yoga,dance,tập luyện,giãn cơ,ảnh,overlay`

**Description VI:**

```
posing là máy ảnh chụp tư thế (pose-reference camera) dành cho iPhone. Tìm một tư thế bạn thích, biến bất kỳ bức ảnh nào thành hướng dẫn pose rõ ràng nhờ AI, và chụp phiên bản đẹp nhất của riêng bạn — tất cả trong một ứng dụng.

CỘNG ĐỒNG TƯ THẾ
Duyệt thư viện tư thế đang phát triển: từ đứng, đi bộ đến nhảy, khiêu vũ và giơ tay. Tìm kiếm theo tên, mở chi tiết từng pose và lưu tư thế yêu thích. Nội dung mới được đội ngũ cập nhật thường xuyên.

HƯỚNG DẪN POSE TỪ ẢNH CỦA BẠN
Muốn tái hiện một tư thế? Chọn ảnh từ thư viện, posing phát hiện khớp cơ thể và tạo hướng dẫn khung xương rõ ràng, chỉ chính xác vị trí tay, chân và thân bạn cần đặt theo.

CHỤP VỚI ĐƯỜNG CĂN CHỈNH
Máy ảnh tích hợp với lưới và đường căn chỉnh giúp bạn canh khung hình. Chụp bao nhiêu cũng được — mọi ảnh đều được lưu tự động vào thư viện cá nhân.

THƯ VIỆN RIÊNG TƯ
Ảnh chụp của bạn được lưu trên thiết bị, nhóm theo ngày, xem dạng lưới hoặc danh sách. Bạn có thể xóa hoặc giữ bất cứ lúc nào. Khi yêu cầu hướng dẫn pose, ảnh đã chọn được tải lên an toàn để backend và nhà cung cấp AI xử lý. Xem Chính sách Quyền riêng tư để biết chi tiết.

Sẵn sàng tạo dáng? Tải posing và bắt đầu dự án ảnh tiếp theo của bạn.
```

**What's New VI:**

```
Chào mừng đến với posing! Phiên bản đầu tiên mang trọn quy trình chụp pose đến iPhone:
• Duyệt thư viện tư thế cộng đồng và tìm kiếm theo tên
• Biến bất kỳ ảnh nào thành hướng dẫn khung xương rõ ràng nhờ AI
• Chụp ảnh với lưới camera vào thư viện riêng tư của bạn
• Mạng production ổn định và chuyển màn hình mượt hơn
```

---

## 9. EULA / Terms of Use trong metadata (Guideline 3.1.2)

App Store yêu cầu các ứng dụng có auto-renewable subscription phải cung cấp link hợp lệ đến Terms of Use (EULA) và Privacy Policy trong phần metadata hiển thị trên product page.

**Tùy chọn cấu hình Terms:**

| Cách | Thao tác ASC | Ghi chú |
| --- | --- | --- |
| **A** | Dán Description ở §5 (đã bao gồm link Terms & Privacy) | Terms và Privacy URL đều phải công khai, hoạt động |
| **B** | App Information → **License Agreement / Custom EULA** → dán nội dung `docs/legal/posing-terms-of-service.md` | Vẫn cần URL Privacy Policy công khai trên metadata |

**Kiểm tra URL (curl):**

```bash
for u in "https://sites.google.com/view/posingapp/terms-of-service" \
         "https://sites.google.com/view/posingapp/privacy-policy"; do
  printf '%s -> ' "$u"; curl -sSL -o /dev/null -w '%{http_code}\n' --max-time 20 "$u"
done
```

**Checklist kiểm tra trước khi submit:**

- [x] Legal URLs đã xuất bản công khai (`https://sites.google.com/view/posingapp/terms-of-service` và `/privacy-policy`).
- [ ] Cả 2 link mở được trong trình duyệt không cần đăng nhập và trả `200`.
- [ ] Description trong ASC chứa URL Posing ở hai dòng Terms/Privacy.
- [ ] Tên gói + chu kỳ (Monthly / Annual) + auto-renew + cancel xuất hiện trong Description.
- [ ] In-app: paywall hiển thị `Terms` + `Privacy` + `Restore purchases` (`SupportScreens.swift`).
- [ ] Custom EULA (nếu chọn cách B) đã Save ở cấp **App** — không chỉ cấp version.

---

## Nguồn tài liệu tham chiếu

- `README.md` — mô tả sản phẩm & limitations.
- `docs/harness/features/` — FEAT-001..FEAT-011.
- `mobile/iosApp/iosApp/RevenueCatAdapter.swift` — product IDs (`premium_yearly`, `premium_monthly`).
- `docs/app-store-publish/app-review-notes.md` — hồ sơ App Review Information (demo account).
