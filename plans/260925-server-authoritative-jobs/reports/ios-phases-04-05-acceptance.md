# iOS Phases 04-05 Acceptance & Verification Report

**Date:** 2026-09-26 (updated 2026-09-27)  
**Author:** Worker (Lữ Bố)  
**Parent Lead:** `ac337892-d365-4f5a-9ece-378ae846a8e7`  
**Workspace:** `wks_2e69547344ec0a0b`  
**Status:** Validated (Dev suite evidence checked; Phase 6 Jobs navigation E2E remains pending)  
**Candidate Manifest SHA-256:** `fe1bfef5fcccddd2b2bb9fa497b4a5a62f159ca6e6973ce644c136a13eb24ca5`  

---

## 1. Executive Summary

Phases 04 and 05 implementation and Reviewer 1 repair convergence have been completed for the server-authoritative pose extraction jobs system in the iOS client (`mobile/iosApp`).

- **Review Findings Addressed:**
  1. **Inline Offline Banner with Cached Rows:** In `JobsScreen.swift`, when offline with existing cached jobs, an inline offline banner is displayed at the top of the scroll list above the cached rows; the full-screen offline card is reserved exclusively for the empty cached state.
  2. **Truthful Screenshot 06:** Regenerated `06-jobs-offline.png` (96,023 B, 390x844) to truthfully reflect the inline offline banner above a cached job row.
  3. **Robust Polling & Watch Lifecycle Tests:** Added assertions in `JobsServiceTests.swift` proving duplicate `startPolling` is idempotent (single network request cycle), `stopPolling` halts further network requests, `watchJob` terminates on "failed" status with error payload, and early consumer termination of `watchJob` cancels the underlying polling loop.
  4. **Offline Recovery & Copy Verification:** Verified that successful refresh after offline error clears `isOffline` and transitions load state to `.loaded`. Verified exact `SignInIntent` prompt copy for `.addPose` (`"Add your own pose."`) and `.openJobs` (`"See your pose jobs."`).
  5. **Envelope Symmetry:** Added optional `success: Bool?` to `PoseExtractionJobStatus` in `APIModels.swift` with full decoding test coverage.
  6. **Future Pagination Note:** Cursor pagination >50 is deferred as FUTURE per contract plan; client currently queries `limit: 50`.

---

## 2. Frozen Candidate Identity & Covered Files

### Candidate Identity Manifest (SHA-256):
`0629308259bfae319e9ea8767a3a76b7576f9ada2a07fc80542e823571f17249`

### Manifest Items (Sorted):
1. `mobile/iosApp/iosApp.xcodeproj/project.pbxproj` (`5ddbedbc7182fbbaa65bc1ada2e4f736a1c350b669831c30cc06c04fe882d0dd`)
2. `mobile/iosApp/iosApp/Core/Network/APIModels.swift` (`97052677f0bfaf6000fbfa3a9ddf52092397bd55bf61fbd5735a5ff2db24cdd6`)
3. `mobile/iosApp/iosApp/Core/Network/PoseAPIService.swift` (`17d2a9e731dc42036d865aea76bc241f777ecfdcb92475187fa2ce42741466ff`)
4. `mobile/iosApp/iosApp/Core/Network/ServiceLocator.swift` (`678b446036a98ec7ec3a63a20794f3ae168250ac6521b5b8838516753db073c2`)
5. `mobile/iosApp/iosApp/Features/Jobs/AddPoseScreen.swift` (`13d2c798df5ab7dc448f67343f6c01818f0709ad2b44adc11e369ff42d990b39`)
6. `mobile/iosApp/iosApp/Features/Jobs/JobRowView.swift` (`62a2ed5e823163a116d5983a1bff3e28fee12e1d7beff2fe09a6e4a42f2de38f`)
7. `mobile/iosApp/iosApp/Features/Jobs/JobsScreen.swift` (`050f7e207946488fbd44e1dd793faa658c435b761f1637b990df613c88d8bce8`)
8. `mobile/iosApp/iosApp/Features/Jobs/JobsService.swift` (`62be654f22b01c54a60bac12a3a7645e1ca9ef6ed9d873a209a9b0a9662c6e01`)
9. `mobile/iosApp/iosApp/Features/Jobs/PhotoLibraryPicker.swift` (`4d4c29358b13cd3995301f114b63fbf43c29d49b807ffea498de6cb35b9deece`)
10. `mobile/iosApp/iosApp/Features/Poses/PoseServiceAdapter.swift` (`afe11973505d8a40b22fe6b136e47621d691442593ed41fb90ec8dc7770b669e`)
11. `mobile/iosApp/iosApp/Features/Poses/PosesFeature.swift` (`b654d485a258fa8c4e093781e1604cb7820b507491e9a685a2f0f3570f47ad19`)
12. `mobile/iosApp/iosApp/Features/Support/SignIn.swift` (`e98d09febf58d360638c25a331834344495b4ed2c6d91a515ad005874f320587`)
13. `mobile/iosApp/iosAppTests/Features/AddPoseFormTests.swift` (`bfce8298175f75bc798a337dbc9116f25adfb2455ecb34a2a3779d1bce4fc330`)
14. `mobile/iosApp/iosAppTests/Features/AddPoseProcessingTests.swift` (`402fc60abcf1477b514e473183ce1b817a8f709605644002b9433518aa40aba2`)
15. `mobile/iosApp/iosAppTests/Features/JobsFixtures.swift` (`2c7545233fc69fd06ce659ca8f64f4894c51e2521b753030b65d6e3ec940e651`)
16. `mobile/iosApp/iosAppTests/Features/JobsScreenModelTests.swift` (`a368074852c4d09be1afdf9e475518ff5416837b14d6bc8ff766fc8d47c17402`)
17. `mobile/iosApp/iosAppTests/Features/JobsServiceTests.swift` (`764fcd474051e2389e31307984b14a1973831e5e3b0b9b85efa747d536787598`)
18. `mobile/iosApp/iosAppTests/Features/JobsSnapshotTests.swift` (`21fe37b74753b43b942c8735ed55118927936f6c4791c9c4f41d030b001a269a`)
19. `mobile/iosApp/iosAppTests/Features/SignInTests.swift` (`4621ad6816eb94acd1bc5f59364265353f9bb1c6378d31eefe80eb084b152b4c`)
20. `mobile/iosApp/project.yml` (`617bfbd9254ffda9cb26412c2451e378edc85f44efaf6f2f4620e385d0076831`)
21. `plans/260925-server-authoritative-jobs/screens/01-add-pose-form.png` (`47113405afe814faf69f1f4acaaecdf6c54d2e6b637a2ebbb2610d1b915bf17b`)
22. `plans/260925-server-authoritative-jobs/screens/02-add-pose-processing.png` (`a2ba8d13384d3b355aa3d175f401f262e9af77281724a9920538065171be857d`)
23. `plans/260925-server-authoritative-jobs/screens/03-jobs-processing.png` (`f151a4cc831aafcb608ec561dcd9f0afb1364e360471f1ad0ffde47ba4a07dc8`)
24. `plans/260925-server-authoritative-jobs/screens/04-jobs-finish.png` (`5b1ab922583997c6ad43d839d71f60613dbcffc61edf8e3a90a620ffa6f5bd72`)
25. `plans/260925-server-authoritative-jobs/screens/05-jobs-empty.png` (`d8f89ca17f60d328f55f717de4aca05eb73ea8a4ceb368e86a75449804d573ff`)
26. `plans/260925-server-authoritative-jobs/screens/06-jobs-offline.png` (`a3965ff8d72c1c911808bc622d914547eb07f0f30f4322206cda1c26be7acaf2`)

---

## 3. Test & Verification Evidence

### 3.1 Full Test Suite Execution
```bash
set -o pipefail && xcodebuild test \
  -workspace mobile/iosApp/iosApp.xcworkspace \
  -scheme Dev \
  -destination 'platform=iOS Simulator,name=AIPose-Parity-iPhone13' 2>&1 | tee plans/260925-server-authoritative-jobs/reports/dev-test-output.txt
```
**Results:**
- Total Tests: **313**
- Executed: **313**
- Failures: **0**
- Status: **BUILD & TEST SUCCEEDED**
- xcresult Bundle: `/Users/phamnhuphong/Library/Developer/Xcode/DerivedData/iosApp-fvkzhyxvcnzqmnejjrkszeftdktb/Logs/Test/Test-Dev-2026.09.27_13-55-24-+0700.xcresult` (xcresult summary independently reports 313 passed, 0 failed; raw console output from this run was not handed back)

### 3.1.1 Phase 6 Route Handoff Repair
- Removed the competing `dismiss()` from Add Pose's `View jobs` action; the parent route now selects the Jobs destination and target tab.
- The Add Pose route deactivation binding only clears the route when Add Pose is still the active route, so its teardown cannot erase the new Jobs destination.
- Added route-state regression coverage for the `.addPose` → `.jobs(.finish)` transition.
- Focused suite: **3 passed, 0 failed**, result bundle `/Users/phamnhuphong/Library/Developer/Xcode/DerivedData/iosApp-fvkzhyxvcnzqmnejjrkszeftdktb/Logs/Test/Test-Dev-2026.09.27_13-54-57-+0700.xcresult`.
- Full Dev suite: **313 passed, 0 failed** on `AIPose-Parity-iPhone13`; xcresult summary was checked by the parent Lead. `git diff --check` for the three changed Swift files is clean.
- Review-cycle cap remains respected; no third Reviewer lane was opened. Jobs-row/detail/media E2E remains unverified until a new bounded Dev run.

### 3.2 Distinct Truthful Simulator UI Screenshots (390x844)
Stored in `plans/260925-server-authoritative-jobs/screens/`:
1. `01-add-pose-form.png` (130,079 bytes, 390x844) — Add Pose form with photo selector, tags, and description.
2. `02-add-pose-processing.png` (102,249 bytes, 390x844) — Active submission processing state with animated spinner.
3. `03-jobs-processing.png` (84,632 bytes, 390x844) — Jobs processing tab showing active and queued jobs.
4. `04-jobs-finish.png` (123,916 bytes, 390x844) — Jobs finish tab with filter chips, ready job with "View pose", and failed job with "Retry".
5. `05-jobs-empty.png` (64,226 bytes, 390x844) — Jobs empty state card ("No jobs yet").
6. `06-jobs-offline.png` (96,023 bytes, 390x844) — Offline state showing inline banner above cached job row.

### 3.3 Server-Authoritative Architecture Compliance
```bash
grep -rn "JobRecord\|localIntentId" mobile/iosApp
# Result: 0 matches
```

### 3.4 Scoped Diff Check
```bash
git diff --check mobile/iosApp
# Result: clean
```

---

## 4. Phase 6 Gate & Dependency

- **Status:** **Validated** (Parent Lead evidence checks passed; review-cycle cap respected; no third Reviewer).
- **Phase 6 Mobile Dev-E2E Blocker:** Mobile E2E verification remains strictly gated until Backend confirms healthy deployment order:
  1. Deploy `web/admin-ui` to dev.
  2. Deploy `web/services/pose-extract-server` to dev.
  3. Verify health endpoint and database migrations.
