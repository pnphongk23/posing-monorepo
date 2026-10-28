# Pose detail (FEAT-003/008)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-DET-001 | P0 | Catalogue loaded | Tap first card | Detail shows name, category, steps, "Use this pose"; back returns to list | maestro:p0-03-pose-detail |
| TC-DET-002 | P1 | Detail open | Observe hero image | Image fits its container (no crop of subject, no stretch); loading placeholder then image | manual |
| TC-DET-003 | P1 | Detail, image URL fails | Open pose with broken image | "Pose photo unavailable" state, no crash | manual |
| TC-DET-004 | P1 | Detail open | Tap "Use this pose" | Camera tab opens with this pose as guide | maestro:p0-04-camera-guide |
| TC-DET-005 | P1 | account_feature on, signed in | Tap "Save pose" | Label changes to "Saved"; pose appears in Saved | pending (needs signed-in seam) |
| TC-DET-006 | P1 | Pose unpublished meanwhile | Open stale pose | "Pose unavailable" with Return to Poses | manual |
