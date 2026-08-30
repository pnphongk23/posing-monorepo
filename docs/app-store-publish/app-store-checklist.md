# App Store Connect Checklist — Snap Pose 1.0 (Submission)

> **Lane:** `app-store-publish-prep` · **Status:** DRAFT checklist — lane này KHÔNG submit; bàn giao cho lane submit khi PO duyệt.
> **Baseline:** HEAD `49a2eb3`, staged=0 · **Build:** 1.0 (6) — đã upload TestFlight, `VALID_BINARY`

Quy ước cột Status: ✅ READY (đã có) · ⏳ PO (PO phải cấp/duyệt) · 👷 UCP/executor (làm theo runbook) · 🚫 N/A (chưa áp dụng ở v1.0)

---

## A. App Information (App Store tab)

| # | Hạng mục ASC | Giá trị / gợi ý | Điều kiện ASC | Status |
| --- | --- | --- | --- | --- |
| A1 | **App name** | `Snap Pose` | ≤30 ký tự | ⏳ PO duyệt (`app-store-metadata.md` §1) |
| A2 | **Subtitle** | `Pose camera & AI guides` | ≤30 | ⏳ PO duyệt |
| A3 | **Primary language** | English (US) | — | ⏳ PO chốt (EN đề xuất; VI annex sẵn) |
| A4 | **Category (primary)** | `Lifestyle` | — | ⏳ PO chốt (alternative: Health & Fitness) |
| A5 | **Category (secondary)** | `Photo & Video` | optional | ⏳ PO chốt |
| A6 | **Description** | Bản EN trong metadata | ≤4000 ký tự | ⏳ PO duyệt copy |
| A7 | **What's New** (v1.0) | Bản EN trong metadata | ≤4000 | ⏳ PO duyệt copy |
| A8 | **Keywords** | `pose camera,pose reference,...` | ≤100 ký tự | ⏳ PO duyệt (91/100) |
| A9 | **Promotional text** | tùy chọn | ≤170 | 🚫 bỏ trống được |
| A10 | **App icon (1024)** | lấy từ binary; `AppIcon-1024.png` verified | no alpha | ✅ verified (kỹ thuật) + 👷 QA visual (
`app-icon-check.md`) |
| A11 | **Screenshots** | Đã có 4 ảnh app thật + 1 prototype Gallery reference ở 1179×2556; còn thiếu iPhone 6.7" + 6.5" + **iPad 12.9" (bắt buộc)** | xem runbook | ⚠️ PARTIAL — prototype Gallery **không dùng ASC**, Gallery thật hiện empty state |
| A12 | **Copyright / trademark** | PO cấp (tên công ty/người phát hành, năm) | — | ⏳ PO |
| A13 | **Support URL** | PO cấp https URL | bắt buộc | ⏳ PO (`privacy-support.md` §5) |
| A14 | **Privacy Policy URL** | PO cấp https URL + duyệt nội dung nháp | bắt buộc | ⏳ PO (`privacy-support.md` §2) |
| A15 | **Rating** (content) | Age 4+ đề xuất; questionnaire: None (không violence/sexual/tobacco...) | — | ⏳ PO duyệt |
| A16 | **App Privacy** (nutrition labels) | bảng khai trong `privacy-support.md` §4 | bắt buộc đúng thật | ⏳ PO/developer điền |

## B. Version / Build

| # | Hạng mục | Giá trị | Status |
| --- | --- | --- | --- |
| B1 | Version | `1.0` (ShortVersion, Info.plist:19) | ✅ |
| B2 | Build | `6` (CFBundleVersion, Info.plist:21 — **đã khớp** build 6 TestFlight; không cần bump) | ✅ — không re-upload |
| B3 | Build trên ASC | TestFlight build 6 `VALID_BINARY` | ✅ đã có |
| B4 | Signing / team | `DEVELOPMENT_TEAM = 878758XF68` (pbxproj:353/376) | ✅ (PO xác nhận đúng ASC team) |
| B5 | Export compliance | App chỉ dùng TLS/HTTPS (Firebase, Railway); không mã hóa tùy biến → khai "uses encryption only for standard HTTPS" | ⏳ PO/US xác nhận khi điền |
| B6 | Deployment target | iOS 15.0 | ✅ |

## C. Pricing & IAP

| # | Hạng mục | Giá trị | Status |
| --- | --- | --- | --- |
| C1 | Price (app) | **Free** — v1.0 không có IAP | ⏳ PO xác nhận |
| C2 | Auto-renewable subscriptions | **Chưa có** — FEAT-011 & DEC-008 `proposed` (annual $39.99 etc.), paywall chưa ship | 🚫 chờ PO quyết khi deploy FEAT-011 |
| C3 | Non-consumable / lifetime | Chưa có | 🚫 |
| C4 | Paid-access gate | N/A ở v1.0 (app free, full tính năng hiện tại) | 🚫 |

> Khi FEAT-011 ship: phải tạo product IDs trong ASC trước (`premium_weekly/monthly/
> annual/lifetime` theo DEC-008), khai IAP mục C, cập nhật App Privacy (Purchase
> History), và copy mới đúng paywall — là **bản 1.0.x sau**, không nằm ở release này.

## D. Cấu hình liên quan từ release-prep (liên hệ, KHÔNG phải việc lane này)

| # | Nhắc nhở | Trạng thái | Ghi chú |
| --- | --- | --- | --- |
| D1 | M1 — default endpoint ngrok | **Đã xử lý trong dirty tree**: `AppConfig.kt:11` + `PoseServiceLocator.kt` = `https://pose-extract-server-production.up.railway.app` (prod) | ✅ (diff xác nhận) |
| D2 | P1 — GoogleService-Info.plist chính chủ | PO xác nhận file firebase thuộc team (bundle `camerapose.app`) | ⏳ PO |
| D3 | P2 — Remote Config `api_baseurl` = prod | PO set trên Firebase project | ⏳ PO |
| D4 | M3 — xcodegen với real plist cho **archive tương lai** | Build 6 đã ok; các bản sau phải chạy xcodegen để bundle plist | 👷 UCP (bản sau) |
| D5 | M5 — dSYM upload Crashlytics | Chưa có CI; cần step vào lúc archive release | 👷 CI owner (bản sau) |
| D6 | D1 cũ — UGC không bật (privacy-ugc Giai đoạn 1) → policy không claim UGC | giữ nguyên như policy nháp | ✅ |

## E. Runbook submit (cho lane submit — KHÔNG chạy bởi lane này)

Thứ tự đề xuất khi PO bấm nút "đủ điều kiện":

1. PO duyệt toàn bộ metadata + supply URL/email (A1-A16, C1, D2, D3).
2. Executor chụp screenshots theo runbook → PO duyệt ảnh → lưu ASC `Media Manager`.
3. Developer/PO điền App Information (A), Privacy questionnaire (A16), Pricing (C).
4. Chọn build 6 từ TestFlight → **Complete Submission** (hoặc "Add for Review" - ASO
   phím này thuộc người có quyền ASC; PO quyết định).
5. Theo dõi review; chuẩn bị sẵn metadata `What's New` bản sau (IAP) khi FEAT-011 ship.

> **Giới hạn lane này:** tất cả action ASC (điền form, upload ảnh, submit, upload
> build, archive) thuộc lane submit sau khi PO duyệt — lane `app-store-publish-prep`
> dừng ở việc "chuẩn bị + runbook".

## F. Checklist tổng theo trạng thái

| Trạng thái | Mục |
| --- | --- |
| ✅ READY (không cần làm gì) | B1, B2, B3, B6, A10 (kỹ thuật), D1 |
| 👷 UCP/executor | A11 (capture lại đúng 6.7"/6.5"/iPad + seed Gallery), A10 (QA visual), D4, D5 (bản sau) |
| ⏳ PO cấp/duyệt | A1-A9, A12-A16, C1, D2, D3 |
| 🚫 N/A v1.0 | C2, C3, C4 |

## G. Rủi ro chặn submit (chốt trước khi review)

1. **Thiếu Privacy Policy URL hoặc Support URL** → ASC không cho submit (A13/A14).
2. **Thiếu iPad screenshots** (family 1,2) → ASC reject (A11).
3. Screenshots chứa UI chưa ship (paywall/overlay) → review reject (runbook §6).
4. App Privacy khai sai (thiếu Firebase device ID/crash) → review hỏi lại (A16).
5. Nếu QA visual icon FAIL → cần build mới (CFBundleVersion 5) + upload lại — báo PO sớm.
