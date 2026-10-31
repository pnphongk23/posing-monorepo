# Capture and gallery (FEAT-001/002)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-GAL-001 | P0 | Clean install | 1. Launch. 2. Tap Gallery. 3. Tap the camera shortcut | Empty-state shortcut visible; tapping it opens the camera | automated: TC-GAL-001-empty-gallery.yaml |
| TC-GAL-002 | P0 | Device camera, entitled or paywall off | Capture a photo | Photo appears at top of Gallery with timestamp | manual (device) |
| TC-GAL-003 | P1 | Photos in gallery | Open a photo, swipe between photos | Pager shows "Photo n of N" | manual |
| TC-GAL-004 | P1 | Photo open | Tap Share | Share sheet opens with the image | manual |
| TC-GAL-005 | P1 | Photo open | Delete photo, confirm | Row gone; file removed from disk (no orphan) | manual |
| TC-GAL-006 | P1 | Photo open | Favorite then filter by favorites | Only favorites listed | manual |
| TC-GAL-007 | P1 | Photos permission denied for export | Save to Photos | Clear message, app stays usable | manual |
| TC-GAL-008 | P0 | At least one photo in Gallery | 1. Open Gallery. 2. Inspect the header. 3. Inspect the photo layout | Header carries exactly two elements: the title (`gallery.title`) and the Add pose control (`gallery.add-pose`) — no list / dense / view-mode toggle anywhere on the screen. Photos render as the 3-column grid, and it stays 3-up at accessibility text sizes. | pending (needs a seeded photo; ids: gallery.title, gallery.add-pose — no toggle id exists because no toggle exists, single 3-column grid) |
| TC-GAL-009 | P1 | Photos in Gallery | Read the section headers above the rows | Each date group has a header above its rows; the label is relative for the recent days (`Today`, `Yesterday`) and `MMM d` otherwise. No "n photos" count text appears in any header or next to the title. | pending (needs a seeded photo; date headers carry the header trait but no accessibility id — asserted by text, so `Today` is the stable one to check) |
