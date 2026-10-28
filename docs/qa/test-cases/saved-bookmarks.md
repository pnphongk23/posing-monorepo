# Saved poses (FEAT-013)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SAV-001 | P0 | account switch on (launch arg), signed out | 1. Launch with accounts on. 2. Tap Saved in the Poses header | Sign-in prompt shown | automated: TC-SAV-001-saved-signed-out.yaml |
| TC-SAV-002 | P1 | Signed in | Save a pose from detail, open Saved | Pose listed | pending |
| TC-SAV-003 | P1 | Signed in, saved pose | Unsave it from detail | Removed from Saved after refresh | pending |
| TC-SAV-004 | P1 | Signed in, empty Saved | Open Saved | Empty state with "browse community" action | pending |
| TC-SAV-005 | P1 | Signed in, saved pose | Tap pose in Saved, "Use this pose" | Camera opens with guide | pending |
| TC-SAV-006 | P1 | Offline | Open Saved | Error + retry; retry works online | manual |
| TC-SAV-007 | P1 | Account A saved poses; sign out; sign in B | Open Saved as B | B sees only B's poses (no leakage) | pending |
