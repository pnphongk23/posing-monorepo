# Capture and gallery (FEAT-001/002)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-GAL-001 | P0 | Clean install | Open Gallery | Empty state with "open camera" shortcut; shortcut opens camera | maestro:p0-06-gallery |
| TC-GAL-002 | P0 | Device camera, entitled or paywall off | Capture a photo | Photo appears at top of Gallery with timestamp | manual (device) |
| TC-GAL-003 | P1 | Photos in gallery | Open a photo, swipe between photos | Pager shows "Photo n of N" | manual |
| TC-GAL-004 | P1 | Photo open | Tap Share | Share sheet opens with the image | manual |
| TC-GAL-005 | P1 | Photo open | Delete photo, confirm | Row gone; file removed from disk (no orphan) | manual |
| TC-GAL-006 | P1 | Photo open | Favorite then filter by favorites | Only favorites listed | manual |
| TC-GAL-007 | P1 | Photos permission denied for export | Save to Photos | Clear message, app stays usable | manual |
