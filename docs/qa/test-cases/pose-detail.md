# Pose detail (FEAT-003/008)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-DET-001 | P0 | Clean install, network | 1. Launch. 2. Open first card, scroll until "Use this pose" is visible. 3. Tap Back | Detail shows "Use this pose"; back shows the catalogue | automated: TC-DET-001-open-detail.yaml |
| TC-DET-002 | P1 | Detail open | Observe hero image | Image fits its container (no crop of subject, no stretch); loading placeholder then image | manual |
| TC-DET-003 | P1 | Detail, image URL fails | Open pose with broken image | "Pose photo unavailable" state, no crash | manual |
| TC-DET-005 | P1 | account_feature on, signed in | Tap "Save pose" | Label changes to "Saved"; pose appears in Saved | pending (needs signed-in seam) |
| TC-DET-006 | P1 | Pose unpublished meanwhile | Open stale pose | "Pose unavailable" with Return to Poses | manual |
| TC-DET-007 | P0 | Clean install, network | 1. Open first card. 2. Tap Use this pose. 3. Tap Close camera | Back on the same pose detail (opens at top, scroll not restored), not Home; a private detail (Jobs/Add Pose) returns private | automated: TC-DET-007-camera-back-returns-to-detail.yaml (same pose proven via `poseDetail.title` text = pose id; private detail manual) |
| TC-DET-008 | P0 | Clean install, network | Open first card, do not scroll | "Use this pose" is visible immediately, pinned at the bottom | automated: TC-DET-008-try-pose-visible-without-scroll.yaml |
| TC-DET-009 | P1 | Dynamic Type Large and AXXXL, a long pose | Open the detail | "Use this pose" still visible without scrolling | manual (simctl ui content_size; Maestro cannot set text size) |
