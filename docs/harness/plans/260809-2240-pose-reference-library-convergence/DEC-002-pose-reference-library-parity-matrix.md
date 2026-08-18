---
schema_version: 1
type: decision
id: DEC-002
title: Pose Reference Library Parity Matrix
status: approved
created: 2026-08-09
approved: 2026-08-09
approved_by: phongpn
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
  source_paths: []
---

# Pose Reference Library Parity Matrix

This parity matrix establishes the authority alignment between the business requirements (FEAT-003), the design prototype screens/scripts, and the production code target for the iOS-first slice of the Pose Reference Library.

## Parity Matrix Table

| Requirement / Scenario / Exception | Prototype Path / Interaction | Production Code / Path / Symbol | Status & Alignment |
| --- | --- | --- | --- |
| **FR-001** (Distinct Tabs) | `poses-list.html` (My Poses vs Community tabs) | `PosesScreen.kt` / `TabSwitcher` | Aligned. UI displays My Poses and Community. |
| **FR-002** (Published Community) | `poses-list.html` (Community tab item list) | `PoseApiService.kt` / `getCommunityPoses` | Aligned. Fetches public community poses from remote catalog. |
| **FR-003** (Pagination Deduplication) | N/A (Prototype uses static list) | `PosesViewModel.kt` / `loadMoreCommunityPoses` | Added. Closes gap where app had no deduplication. |
| **FR-004** (Detail Screen & Metadata) | `pose-detail.html` (Display name, optional metadata) | `PoseDetailScreen.kt` / `PoseDetailScreen` | Aligned. Nullable fields default to null; no fabrication. |
| **FR-005** (Try Pose Overlay) | `camera-pose-overlay.html` (Preview with active skeleton) | `CameraScreen.kt` & persistent selected pose cache | Aligned. Switches to camera and renders the active transparent overlay. |
| **FR-006** (Local-only Deletion) | `pose-detail.html` (Delete button & confirmation) | `PoseDetailScreen.kt` & `PoseRepository.kt` | Aligned. Deletion is local-only and asks for confirmation. |
| **FR-007** (Dedicated Search Screen) | `search.html` (Dedicated input + filter grid) | `SearchScreen.kt` (new voyager screen) | Added dedicated search screen with dynamic filtering. |
| **FR-008** (Pull-to-refresh / Reload) | `poses-list.html` (Refresh button) | `PosesScreen.kt` / `PullRefresh` or reload control | Aligned. Supports list updates and state reload. |
| **FR-009** (Network failure retry) | N/A (Prototype has no network simulation) | `PosesScreen.kt` / retry banner & button | Added. Retains existing items on network failure. |
| **FR-010** (Empty states navigation) | `poses-list.html` (Empty state tip & CTA) | `PosesScreen.kt` / empty states with callbacks | Aligned. Empty state buttons trigger extraction or show tips. |
| **FR-011** (Durable active reference) | N/A (Prototype does not persist state) | Persistent selected pose repository or key-value store | Added. Survives app relaunch without network dependency. |
| **BR-001** (No server deletion) | N/A (No delete on server) | `PoseRepository.kt` / `deletePose` | Aligned. Never mutates community catalog or remote server. |
| **BR-002** (Authority precedence) | `pose-detail.html` (Has likes & bookmarks) | `PoseDetailScreen.kt` (No social features) | Aligned. Documents win; social prototype controls excluded. |
| **BR-003** (Clear camera overlay) | `camera-pose-overlay.html` (Clear active pose) | `CameraScreen.kt` / active reference clear | Aligned. Clear overlay removes reference cache, not source pose. |
| **NFR-001** (Crash-free transition) | N/A | Production network/database flow error handling | Aligned. Gracefully captures database and network failure. |
| **Scenario 1** (Select Community Pose) | `pose-detail.html` ("Try Pose" click) | `PoseDetailScreen.kt` & `Navigation.kt` | Aligned. Navigates to Camera and shows transparent overlay. |
| **Scenario 2** (Restore After Relaunch) | N/A | App launch validation & Camera restore | Aligned. Restores selected pose at 50% opacity offline. |
| **Scenario 3** (Pagination network drop) | N/A | `PosesViewModel.kt` / pagination error state | Aligned. Keeps loaded items and shows bottom retry. |
| **Exception E1** (Community request fail) | N/A | `PosesScreen.kt` / error state with retry banner | Aligned. Exposes retry banner and preserves loaded list items. |
| **Exception E2** (Pose record missing) | N/A | `PoseDetailScreen.kt` / missing alert & return | Aligned. Shows missing item dialog and pops back. |
| **Exception E3** (Deletion fails) | N/A | `PoseDetailScreen.kt` / delete fail handling | Aligned. Exposes error and retains pose in list. |

## Material Decisions Resolved

1. **iOS-first Slice:** Android is explicitly deferred. Test targets compile and run on `:shared:iosSimulatorArm64Test` and `:composeApp`.
2. **Mock Community Search:** A source-neutral catalog-search port is defined. The initial implementation uses a mock search adapter, deferring a server title-search endpoint.
3. **No Social UI:** Likes, bookmarks, comments, and other community interaction controls visible in the prototype screens are excluded from production implementation.
4. **No Server Deletion:** Deletion of personal poses affects local metadata and storage only; it makes no DELETE request.
