# Visual Prototype Specification — Plan 2: Search & Gallery List Refresh

> **Nguồn chân lý hình ảnh:**
> - HTML Prototype: `docs/prototype/screens/search.html` & `docs/prototype/screens/gallery.html`
> - Styles: `docs/prototype/styles/tokens.css`, `search.css`, `components/grid.css`
> - Screenshot kiểm chứng: `docs/prototype/screenshots/search.png` & `docs/prototype/screenshots/gallery.png`

---

## 1. Search Screen (`search.html`)

### A. Header & Search Input
- **Nền màn hình:** `#FBF6EF` (kem ấm).
- **Header:**
  - Nút Back: Vuông trắng `44dp x 44dp`, bo góc `10dp`, viền `2px solid #000`, shadow `3px 3px 0px #000`.
  - Tiêu đề: `"Search"` (Bold, căn giữa hoặc cạnh nút back).
- **Ô Search Bar (`.nb-search-field`):**
  - Chiều cao tối thiểu: `56dp`.
  - Màu nền: Trắng `#FFFFFF`.
  - Bo góc: `14dp` (`RoundedCornerShape(14.dp)`).
  - Viền: `2px solid #000000`.
  - Shadow: `3px 3px 0px #000000`.
  - Leading Icon: Kính lúp màu đen `#121212`, nét `2.4dp`.
  - Placeholder: **`"Search poses"`** (BẮT BUỘC SỬA: Không dùng `"Type a title"`).
  - Trailing Icon: Nút xóa "×" tròn/vuông nhẹ khi có chữ.

### B. Màn hình Khám phá (Search Discovery / Khi chưa gõ query)
- **Tiêu đề:** `"Recent searches"` (`AiPoseTypography.Heading3`, bold, 16-18px).
- **Hàng Chip Gợi ý (`.nb-search-chip-row`):**
  - Các chip: `"Dancing"`, `"Stretching"`, `"Warrior"`.
  - Kích thước: Chiều cao tối thiểu `44dp`, padding ngang `12dp`, dọc `8dp`.
  - Nền: Trắng `#FFFFFF`, viền `1.5px solid #000`, shadow `1.5px 1.5px 0px #000`, bo góc `10dp`.
  - Text: Đen bold `14px`.
  - Khi click vào chip: Điền từ khóa vào ô search và thực hiện tìm kiếm.

### C. Kết quả Tìm kiếm (Search Results Panel)
- **Header kết quả:** Text `"YOUR MATCHES"` (kicker) và `"Results"` (`Heading2`), bên phải là số lượng `"X poses"`.
- **Hàng Filter nguồn (`.nb-search-filter-row`):**
  - Các nút: `"All poses"`, `"My poses"`, `"Community"`.
  - Nút active (`All poses`): Highlight màu hồng pastel (`#E89CAE`) hoặc vàng pastel (`#FED766`), viền đen `2px`, shadow `1.5px`.
- **Lưới kết quả (Grid):**
  - Thẻ pose Neo-Brutalist: Bo góc `14dp`, viền đen `2px`, shadow `3px 3px 0px #000`.
  - Ảnh pose hiển thị rõ nét, tag danh mục, icon tim yêu thích.

---

## 2. Gallery Screen (`gallery.html`)

### A. CÁC QUY TẮC CỐT LÕI (BẮT BUỘC)
1. **HOÀN TOÀN KHÔNG CÓ Ô SEARCH TEXT FIELD:**
   - Gỡ bỏ vĩnh viễn `OutlinedTextField` ("Search by pose name") khỏi `GalleryScreen.kt`.
   - Gallery là giao diện Date-first Navigation duyệt theo thời gian.
2. **Nút Nâng cấp / Crown (Top-Right):**
   - Nút vuông `44dp x 44dp`, nền vàng accent `#FED766`, viền đen `2px`, shadow `2px`, icon vương miện Crown (dẫn tới Paywall).

### B. Thanh Lọc Theo Ngày (Date Filter Chips - BẮT BUỘC THÊM)
- Nằm ngay dưới thanh tiêu đề "Gallery".
- Hàng chip cuộn ngang mượt mà:
  1. **`All`**: Nền hồng pastel (`#E89CAE`) khi active, viền đen `2px`, shadow `1.5px`, bo góc `6-8dp`.
  2. **`Today`**: Nền trắng `#FFFFFF`, viền đen `1.5px`, bo góc `6-8dp`.
  3. **`7 days`**: Nền trắng `#FFFFFF`, viền đen `1.5px`, bo góc `6-8dp`.
  4. **`30 days`**: Nền trắng `#FFFFFF`, viền đen `1.5px`, bo góc `6-8dp`.
  5. **`Date`**: Nền trắng `#FFFFFF`, viền đen `1.5px`, bo góc `6-8dp`.
- Text trong chip: Đen bold `12-13px`.

### C. Lưới Ảnh Gallery (Photo Grid)
- **Lưới ảnh:** Dense 3 cột (`GalleryGridDefaults.DENSE_COLUMN_COUNT = 3`), gap `3dp`.
- **Thẻ ảnh (PhotoCard):** Vuông vức, tỉ lệ 1:1, bo góc `6-8dp`, hiển thị ảnh chụp sắc nét, có trạng thái loading/error chuẩn mực.
- **Tiêu đề nhóm ngày:** `SectionHeader` phân định rõ `TODAY`, `YESTERDAY`, ngày tháng cụ thể.
