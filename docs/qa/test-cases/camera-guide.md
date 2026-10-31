# Camera and pose guide (FEAT-005/012)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Clean install, network, camera allowed | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap "Use this pose" | Camera shows the shutter, the pose picker button and the pose guide | automated: TC-CAM-001-use-pose-opens-camera.yaml |
| TC-CAM-002 | P1 | Camera, guide on | Pinch and rotate the guide | Guide scales/rotates with the fingers; stays within sane bounds | manual (device; sim cannot pinch reliably) |
| TC-CAM-003 | P1 | Camera | Move opacity slider and change line color | Guide opacity/colour update live | manual |
| TC-CAM-004 | P0 | Clean install, camera allowed | 1. Launch. 2. Tap dock camera. 3. Open camera tools, tap grid toggle. 4. Tap pose picker | Picker shows search field and grid | automated: TC-CAM-004-grid-and-picker.yaml |
| TC-CAM-005 | P1 | Picker open | Search for a pose, pick it | Guide switches to that pose; no name card overlays the viewfinder | manual |
| TC-CAM-006 | P1 | Camera permission denied | Open camera | "Camera access is off" with path to iOS Settings | manual |
| TC-CAM-007 | P1 | Clean install, network | 1. Open first card, tap Use this pose. 2. Relaunch the app. 3. Tap dock camera with no pose chosen | Camera opens with the LAST used pose guide (`camera.poseGuide` text = pose id) | automated: TC-CAM-007-last-pose-after-relaunch.yaml |
| TC-CAM-011 | P1 | As CAM-007, camera open with the remembered pose | Open the pose picker, pick another pose | Guide switches to the picked pose, not the remembered one | automated: TC-CAM-011-explicit-pose-beats-remembered.yaml |
| TC-CAM-009 | P0 | Clean install | 1. Launch. 2. Tap dock camera. 3. Tap Close camera | Back on Home (catalogue), camera gone | automated: TC-CAM-009-camera-from-home-closes-to-home.yaml |
| TC-CAM-010 | P1 | Remembered pose was deleted, made private or unsaved | Tap dock camera | Camera opens with no pose and no error; paywall gate still runs for the remembered pose | manual (needs a pose removed behind the app's back) |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists | manual |
| TC-CAM-012 | P0 | Clean install, camera allowed | 1. Tap dock camera. 2. Collapse the pose picker strip. 3. Re-open it with the reopen control | Collapsed: strip hidden, only thumbnail · shutter · flip show. Reopened: strip back above the control bar | pending (S3 ids: collapse and reopen controls) |
| TC-CAM-013 | P1 | Camera collapsed with a pose guide drawn | Take no action; read the guide | Guide stays drawn (`camera.poseGuide` text unchanged) while collapsed and after reopening | pending (S3 ids) |


Note: since `camera.poseGuide` exists (absent when no guide is drawn), CAM-007/011 and DET-007 prove which pose is drawn. TC-CAM-001 asserts the guide is drawn.
