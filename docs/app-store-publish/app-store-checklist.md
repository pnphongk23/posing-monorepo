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
| A11 | **Screenshots** | 6.5" Display → `1242x2688/` or `1284x2778/`; 6.9" → `1290x2796/` if shown; iPad 13" → `2048x2732/` | Theo `screenshots-runbook.md` | ⏳ iPad canvas exports resized from shared frames; native iPad layout not captured |
| A12 | **Copyright / trademark** | Tên công ty/người phát hành, năm | — | ⏳ Điền thông tin |
| A13 | **Support URL** | URL trang hỗ trợ công khai | Bắt buộc | ⏳ Điền URL |
| A14 | **Privacy Policy URL** | `https://sites.google.com/view/posingapp/privacy-policy` | Bắt buộc | ⏳ URL exists; publish updated policy text |
| A15 | **Rating** (content) | Questionnaire: Age 4+ (không violence/sexual/tobacco) | — | ⏳ Điền questionnaire |
| A16 | **App Privacy** (nutrition labels) | Bảng khai trong `privacy-support.md` §4 | Bắt buộc chính xác | ⏳ Khai báo theo config & telemetry |
| A17 | **Terms of Use link** | Optional public Terms URL | Không có paid IAP | ⏳ Xác nhận URL nếu hiển thị |
| A18 | **Pricing disclosure** | All features are free; no in-app purchases | Khớp build 1.0 | ⏳ Xác nhận metadata và build |
| A19 | **App Review Information** | Sign-in required = No; no demo credentials | Bắt buộc điền trạng thái đúng | ⏳ Chọn No và dán Notes |

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
| C1 | Price (app) | **Free**; every feature is free | ⏳ Xác nhận |
| C2 | In-App Purchases | None | 🚫 N/A |
| C3 | Subscription products | None | 🚫 N/A |
| C4 | Paid-access gate | None; all features work without sign-in | ⏳ Xác nhận trên build |

## D. Cấu hình hệ thống

| # | Hạng mục | Trạng thái | Ghi chú |
| --- | --- | --- | --- |
| D1 | Default API endpoint | Prod endpoint: `https://pose-extract-server-production.up.railway.app` | ✅ Đã cấu hình |
| D2 | Firebase iOS app | Đã cấu hình cho `posing.camera.app` trong project `camerapose-a0877` | ✅ Đã cấu hình |
| D3 | Remote Config `api_baseurl` | Cấu hình trên Firebase Console | ⏳ Kiểm tra trên console |
| D4 | Runtime Telemetry check | Quan sát Analytics/Crashlytics/Remote Config trên build posing | ⏳ Xác nhận qua DebugView |
| D5 | Sign in with Apple signing capability | Target retains `iosApp/iosApp.entitlements`; before signing, verify the `posing.camera.app` App ID and selected provisioning profile both enable Sign in with Apple | ⏳ Pre-submit signing preflight |
| D6 | Remote Config `account_enabled` | Production parameter must be unset or explicitly `false`; publish if changed and verify the fetched production value before submission | ⏳ Pre-submit config check |

## E. Quy trình submit

1. Hoàn thiện toàn bộ metadata và URL trên App Store Connect.
2. Chụp và upload bộ screenshot iPhone 6.9" và iPad 13" theo `screenshots-runbook.md`.
3. Điền thông tin App Privacy (Nutrition Labels) theo `privacy-support.md` §4.
4. Xác nhận không có IAP/subscription products hoặc paid-access gate trong build và ASC.
5. Firebase Remote Config production preflight: `account_enabled` phải unset hoặc `false`; publish config nếu có thay đổi và xác nhận app nhận giá trị production trước khi submit.
6. Signing preflight: kiểm tra Sign in with Apple capability trên App ID `posing.camera.app` và provisioning profile khớp entitlement của target.
7. Điền App Review Information: Sign-in required = No; không nhập demo credentials; dùng Notes trong `app-review-notes.md`.
8. Chọn build release/TestFlight đã verify và bấm Submit for Review.

## F. Checklist các điều kiện bắt buộc

1. **Privacy Policy URL** is public and opens without sign-in; Terms URL is optional for this free release.
2. **Sign-in required = No**; mọi tính năng đều miễn phí và có thể kiểm tra không cần tài khoản.
3. **iPad screenshots** đầy đủ kích thước 13" (app hỗ trợ iPad family).
4. **App Privacy nutrition labels** khớp đúng các dịch vụ dữ liệu thật; không khai Purchase History hoặc account identifiers nếu build 1.0 không thu thập chúng.
