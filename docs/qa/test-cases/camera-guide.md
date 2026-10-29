# Camera and pose guide (FEAT-005/012)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Clean install, network, camera allowed | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap "Use this pose" | Camera shows the shutter and the pose picker button | automated: TC-CAM-001-use-pose-opens-camera.yaml |
| TC-CAM-002 | P1 | Camera, guide on | Pinch and rotate the guide | Guide scales/rotates with the fingers; stays within sane bounds | manual (device; sim cannot pinch reliably) |
| TC-CAM-003 | P1 | Camera | Move opacity slider and change line color | Guide opacity/colour update live | manual |
| TC-CAM-004 | P0 | Clean install, camera allowed | 1. Launch. 2. Tap dock camera. 3. Open camera tools, tap grid toggle. 4. Tap pose picker | Picker shows search field and grid | automated: TC-CAM-004-grid-and-picker.yaml |
| TC-CAM-005 | P1 | Picker open | Search for a pose, pick it | Guide switches to that pose; no name card overlays the viewfinder | manual |
| TC-CAM-006 | P1 | Camera permission denied | Open camera | "Camera access is off" with path to iOS Settings | manual |
| TC-CAM-007 | P1 | A pose was used or chosen in the camera, then app relaunched | 1. Relaunch. 2. Tap dock camera with no pose chosen | Camera opens with the LAST used pose guide and camera settings; an explicitly chosen pose wins over the remembered one | pending: the guide overlay has no accessibility id (QA-261029-ID `camera.poseGuide`); verified by hand on UI-261029 |
| TC-CAM-009 | P0 | Clean install | 1. Launch. 2. Tap dock camera. 3. Tap Close camera | Back on Home (catalogue), camera gone | automated: TC-CAM-009-camera-from-home-closes-to-home.yaml |
| TC-CAM-010 | P1 | Remembered pose was deleted, made private or unsaved | Tap dock camera | Camera opens with no pose and no error; paywall gate still runs for the remembered pose | manual (needs a pose removed behind the app's back) |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists | manual |


Known gap: TC-CAM-001 proves the camera opens with its controls, not that the chosen pose's guide is drawn (the overlay has no accessibility id). Tracked in QA-261029-ID; candidate assertion is the guide toggle label ("Hide pose guide") once verified on a run.
