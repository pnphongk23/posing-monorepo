# Browse and search poses (FEAT-003)

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-BRW-001 | P0 | Clean install, network | Launch app | Poses tab shows catalogue cards; search and Settings buttons visible | maestro:p0-01-launch-browse |
| TC-BRW-002 | P1 | Catalogue loaded | Scroll to the bottom | More poses load (pagination) without duplicate cards or jump to top | manual |
| TC-BRW-003 | P1 | Catalogue loaded | Pull to refresh | Spinner then list refreshed; scroll position sane | manual |
| TC-BRW-004 | P0 | Any | Tap search, type a nonsense term | Empty-results banner; back returns to catalogue | maestro:p0-02-search-empty |
| TC-BRW-005 | P1 | Any | Search a real pose name | Matching cards only; result count shown | manual |
| TC-BRW-006 | P1 | Searched before | Open search | Recent search chip shown; tapping it re-runs the search | manual |
| TC-BRW-007 | P1 | Airplane mode, no cache | Launch | Error state with retry; retry after reconnect loads list | manual |
| TC-BRW-008 | P2 | Airplane mode, cache exists | Launch | Cached catalogue still renders | manual |
