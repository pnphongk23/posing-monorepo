# App Store Connect Checklist — posing 1.0 (Submission)

Checklist tổng hợp các hạng mục cần chuẩn bị và điền trên App Store Connect cho ứng dụng **posing** (`posing.camera.app`).

Quy ước: ✅ READY (đã có/sẵn sàng) · ⏳ Cần kiểm tra/duyệt · 🚫 N/A

---

## A. App Information (App Store tab)

| # | Hạng mục ASC | Giá trị / gợi ý | Điều kiện ASC | Status |
| --- | --- | --- | --- | --- |
| A1 | **App name** | `posing` | ≤30 ký tự | ✅ Đã chốt |
| A2 | **Subtitle** | `Pose camera & AI guides` | ≤30 | ⏳ Duyệt copy |
| A3 | **Primary language** | English (US) | — | ⏳ Chốt ngôn ngữ chính |
| A4 | **Category (primary)** | `Lifestyle` | — | ⏳ Chốt category |
| A5 | **Category (secondary)** | `Photo & Video` | optional | ⏳ Chốt category |
| A6 | **Description** | Bản EN trong `app-store-metadata.md` §5 | ≤4000 ký tự | ⏳ Duyệt copy |
| A7 | **What's New** (v1.0) | Bản EN trong `app-store-metadata.md` §6 | ≤4000 | ⏳ Duyệt copy |
| A8 | **Keywords** | `pose camera,pose reference,...` | ≤100 ký tự | ⏳ Duyệt (91/100) |
| A9 | **Promotional text** | tùy chọn | ≤170 | 🚫 Bỏ trống được |
| A10 | **App icon (1024)** | Lấy từ binary (`AppIcon-1024.png`) | No alpha | ✅ Verified |
| A11 | **Screenshots** | iPhone 6.7", 6.5" và iPad 12.9" (bắt buộc) | Theo `screenshots-runbook.md` | ⏳ Capture từ build mới |
| A12 | **Copyright / trademark** | Tên công ty/người phát hành, năm | — | ⏳ Điền thông tin |
| A13 | **Support URL** | URL trang hỗ trợ công khai | Bắt buộc | ⏳ Điền URL |
| A14 | **Privacy Policy URL** | `https://sites.google.com/view/posingapp/privacy-policy` | Bắt buộc | ✅ Đã publish |
| A15 | **Rating** (content) | Questionnaire: Age 4+ (không violence/sexual/tobacco) | — | ⏳ Điền questionnaire |
| A16 | **App Privacy** (nutrition labels) | Bảng khai trong `privacy-support.md` §4 | Bắt buộc chính xác | ⏳ Khai báo theo config & telemetry |
| A17 | **Terms of Use (EULA) link** | `https://sites.google.com/view/posingapp/terms-of-service` ở cuối Description | **Bắt buộc** (Guideline 3.1.2) | ✅ Đã có trong Description |
| A18 | **Subscription disclosure** | Tên gói + chu kỳ + auto-renew + cancel trong Description | Bắt buộc (Guideline 3.1.2) | ✅ Đã có trong Description |
| A19 | **App Review Information** | Sign-in required = Yes; credential demo account (`app-review-notes.md`) | Bắt buộc (Guideline 2.1) | ⏳ Điền credential demo |

## B. Version & Build

| # | Hạng mục | Giá trị | Status |
| --- | --- | --- | --- |
| B1 | Version | `1.0` (CFBundleShortVersionString) | ✅ |
| B2 | Build number | CFBundleVersion tương ứng | ⏳ Xác nhận theo build upload |
| B3 | Build trên ASC | Chọn build release/TestFlight hợp lệ | ⏳ Upload và chọn build |
| B4 | Signing / team | `DEVELOPMENT_TEAM = 878758XF68` | ✅ |
| B5 | Export compliance | Standard TLS/HTTPS encryption | ⏳ Khai báo |
| B6 | Deployment target | iOS 15.0 | ✅ |

## C. Pricing & In-App Purchases

| # | Hạng mục | Giá trị | Status |
| --- | --- | --- | --- |
| C1 | Price (app) | **Free** (tải miễn phí) + IAP subscription | ⏳ Xác nhận |
| C2 | Auto-renewable subscriptions | 2 gói: `premium_yearly` và `premium_monthly` trong 1 subscription group | ⏳ Tạo product IDs trên ASC |
| C3 | Non-consumable / lifetime | Không có | 🚫 |
| C4 | Paid-access gate | Gate cứng trong build: **Try Pose** | ✅ Đã tích hợp |

## D. Cấu hình hệ thống

| # | Hạng mục | Trạng thái | Ghi chú |
| --- | --- | --- | --- |
| D1 | Default API endpoint | Prod endpoint: `https://pose-extract-server-production.up.railway.app` | ✅ Đã cấu hình |
| D2 | Firebase iOS app | Đã cấu hình cho `posing.camera.app` trong project `camerapose-a0877` | ✅ Đã cấu hình |
| D3 | Remote Config `api_baseurl` | Cấu hình trên Firebase Console | ⏳ Kiểm tra trên console |
| D4 | Runtime Telemetry check | Quan sát Analytics/Crashlytics/Remote Config trên build posing | ⏳ Xác nhận qua DebugView |
| D5 | Sign in with Apple | Enablement trên Apple Developer Portal & entitlements | ⏳ Portal pending (entitlements local đã có) |

## E. Quy trình submit

1. Hoàn thiện toàn bộ metadata và URL trên App Store Connect.
2. Chụp và upload bộ screenshot (iPhone 6.7", 6.5" và iPad 12.9") theo `screenshots-runbook.md`.
3. Điền thông tin App Privacy (Nutrition Labels) theo `privacy-support.md` §4.
4. Tạo 2 subscription products (`premium_yearly`, `premium_monthly`) trong Subscriptions group.
5. Điền App Review Information: Sign-in required = Yes, điền username/password demo account và Notes theo `app-review-notes.md`.
6. Chọn build release/TestFlight đã verify và bấm Submit for Review.

## F. Checklist các điều kiện bắt buộc

1. **Terms of Use (EULA) & Privacy Policy URL** có mặt đầy đủ trong Description và truy cập công khai không cần login (Guideline 3.1.2).
2. **App Review demo account** hoạt động được và đăng nhập thành công vào backend (Guideline 2.1).
3. **iPad screenshots** đầy đủ kích thước 12.9" (app hỗ trợ iPad family).
4. **App Privacy nutrition labels** khớp đúng các dịch vụ dữ liệu thật (Purchase History, Firebase telemetry).
