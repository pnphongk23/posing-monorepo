# Plan — SCR-002-01 Photo Detail rewrite

## Mục tiêu

Thay thế riêng sub-surface `Photo Detail` của SCR-002-01 bằng một screen Compose
mới, lấy `basic-design` làm nguồn hành vi và presentation duy nhất. Không dùng UI
của luồng cũ để suy ra layout hoặc interaction. Gallery list không thuộc phạm vi
rewrite.

## Contract giữ nguyên

- Input: `photos: List<Photo>`, `initialPhotoId: Long`.
- Output: `onBack: () -> Unit`, `onDelete: suspend (Long) -> Boolean`,
  `onSave: suspend (Photo) -> Boolean`, `onShare: (Photo) -> Unit`.
- Navigation: Gallery push detail; Back từ detail trả về đúng gallery context.

## Phạm vi screen mới

1. Tạo composable detail độc lập trong package gallery; không reuse composable
   hoặc state UI/presentation của luồng cũ. Có thể dùng model `Photo`, resolver
   ảnh và callback contract hiện hữu.
2. Header sticky gồm Back, date/time và photo options.
3. Image pager ngang: mỗi item rộng bằng pager, chiều cao theo intrinsic image
   ratio, giữ thứ tự, rounded corner thuộc image/item, không crop.
4. Counter active page dạng `n / total`.
5. Action row chỉ xuất hiện trong detail mode: Share, Save, Trash.
6. Focus mode khi tap ảnh active: nền tối, full-width giữ ratio, ẩn toàn bộ
   chrome và khóa swipe ngang; tap quay lại pager.
7. Vertical drag: detail kéo xuống để dismiss; focus kéo xuống để về pager;
   dưới threshold spring về vị trí cũ; Back ưu tiên thoát focus trước; header
   luôn sticky và không translate theo content.
8. Trạng thái: loading có geometry ổn định, ready, missing photo, deleted,
   save error/retry. Trash gọi callback và dùng Boolean result để chuyển sang
   Deleted hoặc giữ detail với lỗi; không tự thêm confirmation UI không có trong
   basic-design.
9. Shared-element: active image dùng `MatchedImageDestination` với key
   `photo:${photo.id}`, tương thích với capture/reverse navigation hiện hữu.
10. Motion/accessibility: reduced motion dùng crossfade/instant, bỏ translate
    phụ; hit target tối thiểu, content description cho pager/action/state; không
    để action phụ cạnh tranh với tap ảnh.

## Tích hợp

- Chỉ thay entry point mà `GalleryDetailVoyagerScreen` gọi; giữ nguyên data
  mapping từ Gallery và các callback nghiệp vụ, bao gồm suspend/Boolean.
- Không thay đổi API/model/repository.
- Không chỉnh các thay đổi không liên quan đang có trong workspace.

## Verification

- Unit-test các pure transition/threshold helpers, page selection/counter và
  callback contract; compile `commonMain` và `iosSimulatorArm64`; build
  framework iOS simulator; review diff bằng `srcwalk review` và `git diff
  --check`.

## Acceptance criteria (pass/fail)

Mỗi tiêu chí dưới đây phải có bằng chứng tương ứng; compile pass một mình không
được coi là pass cho behavior hoặc visual.

| ID | Tiêu chí pass | Bằng chứng bắt buộc |
| --- | --- | --- |
| AC-01 | Composable mới nhận đúng `photos: List<Photo>` và `initialPhotoId: Long`; route `GalleryDetailVoyagerScreen` gọi nó; không đổi model/repository/router data mapping. | `srcwalk show` declaration + route; `srcwalk review`; diff chỉ trong file screen mới và entry point/tests cần thiết. |
| AC-02 | Callback signatures đúng: `onBack: () -> Unit`, `onDelete: suspend (Long) -> Boolean`, `onSave: suspend (Photo) -> Boolean`, `onShare: (Photo) -> Unit`. | Compile + test callback contract; exact source citation. |
| AC-03 | Header có Back, date/time của ảnh active và options; header vẫn đứng yên khi content bị kéo dọc. | Simulator recording/screenshot trước và trong drag; manual assertion header bounds không đổi. |
| AC-04 | Pager khởi tạo tại `initialPhotoId`, vuốt ngang đổi đúng thứ tự; mỗi page rộng 100%, chiều cao theo intrinsic ratio, không crop; counter luôn là `current + 1 / total`. | UI test/manual flow với ít nhất 3 ảnh có ratio khác nhau; screenshot từng page; counter assertion. |
| AC-05 | Tap ảnh active chuyển Focus: nền tối, full-width, giữ ratio, ẩn header/counter/actions, khóa horizontal swipe; tap lại về pager. | Simulator flow checklist + screenshots của detail/focus + swipe attempt. |
| AC-06 | Back trong Focus chỉ thoát Focus; Back trong detail gọi `onBack()` đúng một lần và giữ Gallery context. | Unit test precedence + simulator Back flow; callback invocation count. |
| AC-07 | Vertical drag bám ngón tay và giảm opacity; dưới threshold hồi vị; vượt threshold dismiss detail; Focus drag vượt threshold về pager; header không translate. | Manual gesture test ở dưới/vượt threshold; test threshold helpers; screenshot/video intermediate state. |
| AC-08 | Loading giữ geometry ổn định và disable actions; Ready bật pager/actions; Missing hiển thị unavailable + Retry và không hiển thị ảnh lỗi; Missing ở một page không khóa các page khác. | Inject/fake image loader test hoặc deterministic UI fixture cho từng state; simulator screenshots. |
| AC-09 | Save trả `false` giữ detail, hiển thị Save error và `Try again`; retry gọi lại callback; Save thành công cập nhật success state. | Fake callback test với sequence `false → true`; verify callback count và visible labels. |
| AC-10 | Delete trả `false` giữ detail và feedback retry; Delete trả `true` chuyển sang Deleted, ẩn actions/ảnh thật và hiển thị CTA quay về Gallery; CTA Back gọi `onBack()` đúng một lần. | Fake callback test với `false`/`true`; simulator screenshots; callback count. |
| AC-11 | Active image dùng `MatchedImageDestination` với key chính xác `photo:${photo.id}`; forward/reverse transition không làm duplicate image. | Source citation + transition flow trên simulator khi có source bounds; no-source fallback test. |
| AC-12 | Reduce Motion bỏ translate/scale phụ, dùng instant/crossfade; interaction vẫn hoàn tất bằng tap/back. | Simulator/device accessibility setting bật Reduce Motion + before/after screenshots/recording. |
| AC-13 | Hit targets và content descriptions tồn tại cho Back/options/actions/pager/retry/Deleted CTA; text không bị cắt ở kích thước chữ lớn hỗ trợ. | Accessibility inspector/manual large-text pass; source semantics citations. |
| AC-14 | Build verification: `:composeApp:compileKotlinIosSimulatorArm64` và framework link pass; test suite liên quan pass hoặc failure được phân loại là baseline ngoài scope. | Exact Gradle command/output; failure log nếu có. |

## Completion gate

Chỉ đánh dấu hoàn thành khi AC-01..AC-14 đều `PASS`, hoặc từng AC không áp dụng
được ghi rõ lý do và có reviewer chấp thuận. Nếu không có simulator/runtime,
không được claim AC-03..AC-08, AC-10..AC-13 đã pass; phải ghi là
`UNVERIFIED_RUNTIME`.

## Điểm cần Paseo review

- Phạm vi thay thế route đã đủ hẹp chưa.
- Contract data in/out có bị thay đổi ngầm không.
- Các trạng thái và Back/drag transitions có phủ đủ basic-design không.
- Shared-element và reduced-motion có được ghi rõ mà không mở rộng phạm vi không.
- Có hạng mục nào đang suy diễn ngoài basic-design cần loại bỏ không.
