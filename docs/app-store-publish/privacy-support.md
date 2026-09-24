# Privacy Policy & Support URL — posing 1.0

Privacy policy là **điều kiện bắt buộc** của App Store Connect vì app:
1. Dùng **camera** và thư viện ảnh để chụp ảnh và tạo pose guide.
2. Cấu hình **Firebase** (Analytics, Crashlytics, Remote Config) cho `posing.camera.app` (project `camerapose-a0877`).
3. Gửi ảnh lên **pose-extraction server** khi người dùng tạo pose guide.
4. Tích hợp **auto-renewable subscription (RevenueCat)** với 2 gói `premium_yearly` và `premium_monthly`.

---

## 1. Yêu cầu ASC trước khi submit

| Hạng mục | Trạng thái | Ai cung cấp |
| --- | --- | --- |
| Privacy Policy URL (https, công khai, không cần tải app để xem) | ✅ https://sites.google.com/view/posingapp/privacy-policy (verify `200`, 2026-09-24) | PO |
| Support URL (https, công khai) | **PO cấp URL** | PO |
| Support email (hiển thị trong ASC + policy) | **PO cấp email** | PO |
| Hoàn tất bảng App Privacy (Privacy Nutrition Labels) | PO/developer điền theo mục 4 | PO |

**Đề xuất hosting (nếu PO chưa có):**
- Nhanh & miễn phí: GitHub Pages từ repo này (branch `gh-pages` hoặc thư mục `privacy/`) — tạo trang tĩnh `privacy-policy.html` + mục Support.
- Lâu dài: đặt trên trang web sản phẩm chính thức chứa Privacy Policy + Support.

---

## 2. Privacy Policy (EN — bản gốc nộp ASC)

> Copy-paste sẵn, đúng hành vi app hiện tại (build 1.0/12, subscription đã ship).
> **Không được** thêm claim UGC khi chưa ship. PO bổ sung tên công ty, địa chỉ, email,
> ngày hiệu lực.

```
POSING — PRIVACY POLICY

Effective date: [PO to fill] · Last updated: [PO to fill]

1. WHO WE ARE
posing ("we", "our") is a pose-reference camera app for iPhone ("the App").
Contact: [support email] · [company name & address, if applicable].

2. DATA WE COLLECT

a) Photos and videos you create
The App uses your camera only when you capture a photo inside the App, and your
photo library only when you pick an existing image. Captured and picked images
are stored on your device in your personal gallery. When you create a "pose guide",
the selected image is sent to our pose-extraction service so its AI provider can
detect body joints and return a skeleton guide. The skeleton result is kept in the
App; your original image is used only to produce that guide.

b) Analytics and diagnostics
Firebase Analytics, Crashlytics, and Remote Config are configured for the posing
iOS app (`posing.camera.app`) in project `camerapose-a0877`:
- Firebase Analytics — app usage events (e.g. app start, endpoint resolution)
  to understand and improve the product;
- Firebase Crashlytics — crash reports and device/diagnostic information
  (model, OS version, memory) to fix bugs;
- Firebase Remote Config — runtime configuration (e.g. the backend endpoint).
These services run best-effort and only when a valid Firebase configuration is
present in the App. They are governed by Google's privacy policy.

c) Account and payment
The App offers account-based features (e.g. saving poses) and an auto-renewable
subscription (Posing Premium). Authentication and subscription identifiers are
processed to maintain your account and entitlement status.

3. HOW WE USE DATA
Data is used strictly to provide, maintain, and improve the App's features as
described in this policy.

4. SHARING — WE DO NOT SELL DATA
We do not sell or rent your personal data. We share information only with service
providers (such as Google Firebase for diagnostics/configuration and an AI extraction provider
for pose detection) to the extent needed to operate the service. We do not share photos for advertising.

5. STORAGE AND RETENTION
Your captures live on your device and stay there until you delete them. Pose guides
and related data are kept while needed to provide the feature. Analytics/crash data
is retained per Google's data-retention policies. We apply reasonable technical and
organizational safeguards, including TLS in transit.

6. SUBSCRIPTIONS
posing offers a paid "premium" auto-renewable subscription via RevenueCat on top
of Apple's In-App Purchase, in two plans: Monthly and Annual. Payments are processed
by Apple (StoreKit); we never see or store your payment card details. Subscriptions
auto-renew until cancelled; you can manage or cancel them in your App Store account
settings, and restore purchases in the App. Prices and terms are shown before
purchase. The subscription is tied to the account you sign in with, so we process an
account identifier and purchase/entitlement status to grant Premium. No free trial or
introductory offer is configured.

7. YOUR RIGHTS
Depending on your location (including Vietnam — Decree 13/2023/ND-CP and the
Personal Data Protection Law), you may request access, correction, deletion, or
withdrawal of consent for your data. Contact us at [support email]. You may also
delete photos from the App at any time.

8. CHILDREN
The App is not directed to children under 13 (or the minimum age in your country).
We do not knowingly collect personal data from children.

9. CHANGES TO THIS POLICY
We may update this policy and will post the new version at this URL with a new
effective date. Material changes will be notified in the App or by the updated date.

10. CONTACT
Questions or requests: [support email].
```

## 3. Tóm tắt VI (để PO nắm nhanh — không thay bản EN nộp ASC)

- **Camera/Ảnh:** chỉ chụp khi bạn bấm; ảnh lưu trên thiết bị; khi tạo pose guide, ảnh
  được gửi lên dịch vụ extract (và AI provider) chỉ để phát hiện khung xương.
- **Firebase:** Analytics + Crashlytics + Remote Config đã cấu hình cho `posing.camera.app` (project `camerapose-a0877`); runtime telemetry cần quan sát trên build posing.
- **Không bán dữ liệu**; chia sẻ chỉ với nhà cung cấp dịch vụ (Firebase/Google, AI provider) theo nhu cầu vận hành.
- **Tài khoản:** bắt buộc cho save pose / mua Premium (Apple, Google, Email sign-in); browse + camera
  + gallery local chạy ẩn danh.
- **Subscription: LIVE** — Apple StoreKit xử lý thanh toán (qua RevenueCat), không lưu
  thẻ của bạn; tự gia hạn, hủy/restore qua Store settings; 2 gói Monthly/Annual.
- **Quyền người dùng:** truy cập/sửa/xóa/út consent theo PDPD & PDP Law VN.
- **Trẻ em:** không nhắm dưới 13 tuổi; không thu thập có chủ đích.

## 4. Bảng App Privacy (Privacy Nutrition Labels) — đối chiếu hành vi thật

ASC hỏi "data collected" theo danh mục. Reconcile every row with the exact Posing
build before declaring. Subscription is marked **LIVE** and Purchase History is
included; Firebase rows are configured and pending runtime observation on build:

| Danh mục ASC | Khai? | Loại | Mục đích | Liên kết danh tính |
| --- | --- | --- | --- | --- |
| Photos or Videos | Yes | Collected | App Functionality (pose guide/gallery) | Not linked |
| Identifiers — Device ID | Declare per Firebase config; confirm in DebugView/Crashlytics on a posing build | Collected (when Firebase active) | Analytics (Firebase) | Not linked |
| Diagnostics — Crash Data | Declare per Firebase config; confirm in DebugView/Crashlytics on a posing build | Collected (when Firebase active) | App Functionality (Crashlytics) | Not linked |
| Other — Usage Data (events) | Declare per Firebase config; confirm in DebugView/Crashlytics on a posing build | Collected (when Firebase active) | Analytics | Not linked |
| **Purchase History** | **Yes — bật khi có subscription** | Collected | App Functionality (cấp/thử lại entitlement Premium qua RevenueCat + backend) | **Linked to user** (entitlement gắn với account đăng nhập) |
| User ID / Account | Yes | Collected | App Functionality (save pose, entitlement) | Linked to user |
| Tracking (advertising) | **No — "Data Used to Track You: No"** | — | — | — |

> Apple yêu cầu khai đúng sự thật — nếu sau này đổi hành vi (thêm UGC đầy đủ) phải
> cập nhật lại bảng này + policy trước khi phát hành bản mới.
> Sai sót ở dòng **Purchase History** là lỗi bị hỏi lại phổ biến sau khi thêm IAP.

## 5. Support URL — đề xuất

| Lựa chọn | URL | Ghi chú |
| --- | --- | --- |
| Trang sản phẩm tương lai | `https://<tên-miền>/support` | PO mua domain (khuyến nghị dài hạn) |
| GitHub Pages tạm | trang tĩnh trong repo này | Nhanh, miễn phí; chứa email support |
| mailto (không hợp lệ cho ASC field) | ✗ | ASC yêu cầu **URL**, không phải email |

Support URL phải mở được trên web, không yêu cầu tải app.

---

## Việc PO cần cấp/duyệt (tóm tắt)

1. **Privacy Policy URL** — đã publish.
2. **Support URL** + **support email**.
3. Xác nhận bảng App Privacy (mục 4) — PO/US duyệt từng dòng trước khi điền ASC.
4. Quyết định khai công ty hay cá nhân phát hành (ảnh hưởng TAX/USD + contact info ASC).
