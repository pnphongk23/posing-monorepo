# Visual Prototype Specification — Plan 1: Camera & Pose Guide Picker

> **Nguồn chân lý hình ảnh:**
> - HTML Prototype: `docs/prototype/screens/camera-live.html` & `docs/prototype/screens/pose-guide.html`
> - Styles: `docs/prototype/styles/tokens.css`, `components/camera-viewport.css`, `components/camera-guide.css`
> - Screenshot kiểm chứng: `docs/prototype/screenshots/camera-live.png` & `docs/prototype/screenshots/pose-guide.png`

---

## 1. Camera Screen (`camera-live.html`)

### A. Tổng thể & Nền
- **Nền màn hình:** `#FBF6EF` (kem ấm).
- **Khung Preview Camera:**
  - Bo góc: `14dp` (`--nb-radius-large`).
  - Viền: `2px solid #000000` (`--nb-border-thick`).
  - Bọc quanh khung ngắm thực tế của camera.
  - Khung ngắm khuôn mặt (Center Crosshair): Bốn góc căn khung màu trắng `┌ ┐` và `└ ┘` (face framing brackets) thanh thoát.
  - Nút zoom pill: Đặt ở góc dưới giữa khung camera (`1x`), bo tròn viên thuốc, nền trắng mờ viền đen.

### B. Top Header Controls
- **Nút Đóng (Top-Left):**
  - Kích thước: `44dp x 44dp`.
  - Shape: Bo góc `10dp` (`RoundedCornerShape(10.dp)`).
  - Màu nền: Trắng `#FFFFFF`, viền `2px solid #000000`, shadow `3px 3px 0px #000000`.
  - Icon: "×" hoặc icon close nét đậm.
- **Nút Guide & Tools (Top-Right):**
  - Kích thước: `44dp x 44dp`.
  - Shape: Bo góc `10dp`, viền `2px solid #000000`, shadow `2px 2px 0px #000000`.
  - Nút Guide (`CameraGuideButton`): Màu xanh dương pastel (`#7FBBE6` / `AiPoseColors.AccentBlue`).
  - Nút Tools (`CameraMoreButton`): Màu trắng `#FFFFFF`.

### C. Bottom Shutter Dock (`.nb-shutter-bar--redesign`)
- **Vùng dock:** Chiều cao ~110dp, nền `#FBF6EF` hoặc đồng màu app background, padding đáy an toàn (safe-area).
- **Nút chụp chính (Shutter Button - BẮT BUỘC SỬA LẠI):**
  - **Shape:** `CircleShape` (HÌNH TRÒN TUYỆT ĐỐI, tuyệt đối không dùng hình vuông/bo góc).
  - **Kích thước:** `72dp x 72dp`.
  - **Màu nền:** Hồng pastel (`#E89CAE` / `AiPoseColors.Primary`).
  - **Viền:** `2px solid #000000`.
  - **Shadow:** `5px 5px 0px #000000` (`--nb-shadow-large`).
  - **Hiệu ứng nhấn (Active/Pressed):** Lún xuống `translate(5dp, 5dp)`, shadow về `0px`.
- **Nút Thumbnail Gallery (Bên trái):**
  - Kích thước: `48dp x 48dp`.
  - Shape: Bo góc `14dp`.
  - Viền: `2px solid #000000`, shadow `2px 2px 0px #000000`.
  - Hiển thị ảnh chụp gần nhất (crop center).
- **Nút Lật Camera (Bên phải):**
  - Kích thước: `48dp x 48dp`.
  - Shape: Bo góc `14dp`, nền trắng `#FFFFFF`.
  - Viền: `2px solid #000000`, shadow `2px 2px 0px #000000`.
  - Icon lật camera nét đậm.

---

## 2. Pose Guide Picker Screen (`pose-guide.html`)

### A. Header
- **Nền:** `#FBF6EF`.
- **Nút Back:** Nút vuông trắng `44dp x 44dp`, bo góc `10dp`, viền `2px solid #000`, shadow `3px 3px 0px #000`, icon chevron `<`.
- **Tiêu đề:** `"Choose a guide"` (Font lớn, bold, màu `#121212`).

### B. Guide Grid & Cards
- **Layout:** Grid 2 cột đều nhau (`GridCells.Fixed(2)`), khoảng cách `16dp` (`Spacing.md`), padding màn hình `16dp`.
- **Guide Card Structure:**
  - Khung thẻ bề mặt tỷ lệ 1:1 (`aspectRatio(1f)`).
  - Bo góc: `14dp` (`RoundedCornerShape(14.dp)`).
  - Viền: `2px solid #000000` (`if (isSelected) 3.dp else 2.dp`).
  - Shadow: `3px 3px 0px #000000`.
  - **Màu nền Surface (Xoay vòng 4 màu pastel chuẩn Neo-Brutalism):**
    1. Vàng (`#FED766` / `AiPoseColors.Warning`)
    2. Hồng (`#E89CAE` / `AiPoseColors.Primary`)
    3. Xanh lam (`#7FBBE6` / `AiPoseColors.AccentBlue`)
    4. Xanh lá (`#B5E2B9` / `AiPoseColors.Success`)
  - **Nội dung thẻ:**
    - Hình pose / stick figure nổi bật ở chính giữa (chiếm ~75-80% chiều rộng/cao của thẻ), nét đen đậm rõ ràng.
  - **Label bên dưới:**
    - Tên pose in đậm (`AiPoseTypography.Body` bold, 14px), căn trái ngay dưới thẻ, padding nhẹ.
