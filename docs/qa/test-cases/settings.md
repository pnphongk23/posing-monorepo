# Settings (FEAT-015)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SET-001 | P0 | Clean install | 1. Launch. 2. Open Settings. 3. Tap About. 4. Close About | Settings shows Privacy and Replay onboarding; About sheet opens (close button visible); after close Settings is back | automated: TC-SET-001-settings-about.yaml |
| TC-SET-002 | P1 | Camera permission denied | Tap Camera access row | iOS Settings opens; status badge reflects state | manual |
| TC-SET-003 | P1 | Any | Tap Terms / Privacy | Opens in browser | manual |
| TC-SET-004 | P2 | Any | Replay onboarding | Stub only (onboarding deferred) | manual |
