# Browse and search poses (FEAT-003)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-BRW-001 | P0 | Clean install, network | 1. Launch app. 2. Wait for the first card. 3. Scroll once | First card, search button and Gallery tab visible; search button still visible after scroll | automated: TC-BRW-001-launch-catalogue.yaml |
| TC-BRW-002 | P1 | Catalogue loaded | Scroll to the bottom | More poses load (pagination) without duplicate cards or jump to top | manual |
| TC-BRW-003 | P1 | Catalogue loaded | Pull to refresh | Spinner then list refreshed; scroll position sane | manual |
| TC-BRW-004 | P0 | Clean install | 1. Launch. 2. Tap search. 3. Tap field, type `zzqqxx`. 4. Tap back | Empty-results banner shown; after back the search button is visible | automated: TC-BRW-004-search-empty.yaml |
| TC-BRW-005 | P1 | Any | Search a real pose name | Matching cards only; result count shown | manual |
| TC-BRW-006 | P1 | Searched before | Open search | Recent search chip shown; tapping it re-runs the search | manual |
| TC-BRW-007 | P1 | Airplane mode, no cache | Launch | Error state with retry; retry after reconnect loads list | manual |
| TC-BRW-008 | P2 | Airplane mode, cache exists | Launch | Cached catalogue still renders | manual |
