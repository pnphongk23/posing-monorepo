# Pose detail (FEAT-003/008)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-DET-001 | P0 | Clean install, network | 1. Launch. 2. Open first card. 3. Go back | Detail shows "Use this pose"; back shows the catalogue | automated: TC-DET-001-open-detail.yaml |
| TC-DET-002 | P1 | Detail open | Observe hero image | Image fits its container (no crop of subject, no stretch); loading placeholder then image | manual |
| TC-DET-003 | P1 | Detail, image URL fails | Open pose with broken image | "Pose photo unavailable" state, no crash | manual |
| TC-DET-005 | P1 | account_feature on, signed in | Tap "Save pose" | Label changes to "Saved"; pose appears in Saved | pending (needs signed-in seam) |
| TC-DET-006 | P1 | Pose unpublished meanwhile | Open stale pose | "Pose unavailable" with Return to Poses | manual |
