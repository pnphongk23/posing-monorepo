# Camera and pose guide (FEAT-005/012)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-CAM-001 | P0 | Pose chosen from detail | Tap "Use this pose" | Camera with line-art guide, grid toggle and pose picker controls | maestro:p0-04-camera-guide |
| TC-CAM-002 | P1 | Camera, guide on | Pinch and rotate the guide | Guide scales/rotates with the fingers; stays within sane bounds | manual (device; sim cannot pinch reliably) |
| TC-CAM-003 | P1 | Camera | Move opacity slider and change line color | Guide opacity/colour update live | manual |
| TC-CAM-004 | P0 | Camera permission allowed | Open camera from dock, toggle grid, open pose picker | Grid toggles; picker shows search field and grid | maestro:p0-05-camera-tools |
| TC-CAM-005 | P1 | Picker open | Search for a pose, pick it | Guide switches to that pose; no name card overlays the viewfinder | manual |
| TC-CAM-006 | P1 | Camera permission denied | Open camera | "Camera access is off" with path to iOS Settings | manual |
| TC-CAM-007 | P1 | Guide adjusted, then relaunch | Kill and reopen app | Last pose and camera settings restored | manual |
| TC-CAM-008 | P2 | Device with front camera | Tap switch camera | Preview flips; guide persists | manual |
