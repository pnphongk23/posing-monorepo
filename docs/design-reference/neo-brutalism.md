---
title: Neo Brutalism Design Tokens and Components
description: Sử dụng khi tạo mới UI, component, nút bấm hoặc layout. Hướng dẫn sử dụng viền đậm, bóng cứng (hard shadow) và tương tác vật lý.
always: false
---

# Neo Brutalism Design Guidelines

## TỔNG QUAN
Mọi UI component trong ứng dụng phải tuân thủ triệt để ngôn ngữ thiết kế Neo-Brutalism: Hình khối rõ ràng, viền đậm, bóng cứng và phản hồi tương tác mang tính vật lý (ép xuống).

## DESIGN TOKENS (MUST)
- **Màu sắc**: Luôn dùng token từ `AiPoseColors` (`AiPoseColors.Background`, `AiPoseColors.Foreground`, `AiPoseColors.AccentBlue`,...). **Tuyệt đối không** dùng mã màu hardcode hoặc material default.
- **Bo góc (Border Radius)**: Dùng `CornerRadius` (ví dụ `10.dp` hoặc `16.dp`). Các bo góc phải đồng nhất giữa component, background, border và shadow.
- **Độ dày viền (Stroke/Border)**: Quy chuẩn mặc định là `2.dp` cho tất cả các line (hoặc nút bấm).

## COMPONENTS & MODIFIERS (MUST)
- **Border**: Sử dụng `Modifier.neoBorder(width = 2.dp, cornerRadius = ...)`.
- **Shadow**: Luôn dùng `Modifier.neoShadow(offsetX = ..., offsetY = ...)`. 
  - Thường dùng offset `2.dp` cho nút bấm nhỏ, `4.dp` cho các Card/Layout lớn.
  - Tuyệt đối **KHÔNG** dùng thuộc tính `elevation` hay `shadow()` mặc định của Material (vi phạm nguyên tắc bóng cứng).
- **Interactive Button (Nút bấm/Thẻ tương tác)**:
  - Phải sử dụng Component `NeoBrutalismContainer` để bao bọc các thành phần có tương tác click. Component này đóng gói sẵn trọn bộ: tịnh tiến offset tự động khi press, neoShadow, neoBorder, background, clip và loại bỏ hiệu ứng gợn sóng (ripple). Điều này giúp tự động tạo hiệu ứng thẻ/nút vật lý bị ép lún lõm xuống cực kỳ mượt mà.
  - Cấm gõ `Modifier.clickable()` chay để thay thế vì hành động này sinh ra Ripple effect ảo của Material làm mất tính Neo-Brutalism cứng cáp.

## ANTI-PATTERNS (MUST NOT)
- **Ripple Effect (Hiệu ứng mặt nước)**: Vật liệu Neo Brutalist mô phỏng đồ vật lý (nhựa cứng, giấy), không phải Material Design kỹ thuật số. Cấm dùng clickable sinh ra Ripple mặc định.
- **Bóng mờ (Soft Gradients/Shadows)**: Bóng phải có màu đặc cứng (`Solid Color`), không Blur. Cấm sử dụng các loại đổ bóng gradient toả dần.
