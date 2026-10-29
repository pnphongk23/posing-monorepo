# Maestro E2E suite (iOS, Dev scheme)

Bundle id `posing.camera.app` (passed once as `APP_ID` by `run.sh`). Flows are P0 smoke; cases and IDs live in [docs/qa/test-cases](../../../docs/qa/test-cases/README.md).

Flow files must be named `<CASE-ID>-<slug>.yaml` with first line `# <CASE-ID> <title>`; the check enforces both.

## Run
1. Pick a simulator that is yours for the run (the lane uses `ai-pose-test`, coordinate the slot with the Feature lane). Never use a personal device-named sim.
2. Install the Dev build right before the run: `xcrun simctl install <UDID> <derived-data>/Build/Products/Debug-Dev-iphonesimulator/posing.app` (build: `xcodebuild -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev -destination 'id=<UDID>' -derivedDataPath /tmp/dd-shared build`; one build at a time, keep >1.5 GB disk free).
3. `mobile/iosApp/maestro/run.sh <UDID> [flow-file]` — checks traceability, then runs every flow (or the given one). Each flow starts with `subflows/launch.yaml` (clean state), so order does not matter.

Flows need network (server catalogue). Saved/Account cases stay pending until `account_feature` is on in the server config.

## Selectors
Prefer accessibility ids (`poses.first-card`, `search.field`, `gallery.empty.openCamera`, ...) and stable accessibility labels ("Open Camera", "Capture photo", "Open Settings").

## Identifier requests (ledger: QA-261029-ID)
Landed in f8a49cc and used by the flows: `poseDetail.use`, `poseDetail.back`, `dock.camera`, `camera.shutter`, `gallery.empty.openCameraButton`, `poses.open-settings`, `about.close`.

Still requested (flows keep a `TODO(QA-261029-ID)` text selector): `dock.gallery`, `settings.privacy.section`, `settings.replayOnboarding`, `settings.about`; paywall CTA, close and sign-in prompt; the camera guide overlay (or its toggle) so TC-CAM-001 can prove the guide is drawn; a capture seam on the simulator (fixture image) for TC-GAL-002 and TC-PAY-001.

## Traceability (case → flow → status)

| Case | Pri | Flow / status |
|---|---|---|
| TC-ACC-001 | P1 | automated — `flows/TC-ACC-001-account-signed-out.yaml` |
| TC-ACC-002 | P1 | pending (needs test credentials) |
| TC-ACC-003 | P1 | pending |
| TC-ACC-004 | P1 | pending |
| TC-ACC-005 | P1 | pending (server delete landing) |
| TC-ACC-006 | P1 | manual |
| TC-ACC-007 | P1 | automated — `flows/TC-ACC-007-email-form.yaml` |
| TC-ACC-008 | P1 | automated — `flows/TC-ACC-008-accounts-off.yaml` |
| TC-ACC-009 | P1 | automated — `flows/TC-ACC-009-apple-button-label.yaml` |
| TC-ACC-010 | P1 | automated — `flows/TC-ACC-010-fresh-install-copy.yaml` |
| TC-BRW-001 | P0 | automated — `flows/TC-BRW-001-launch-catalogue.yaml` |
| TC-BRW-002 | P1 | manual |
| TC-BRW-003 | P1 | manual |
| TC-BRW-004 | P0 | automated — `flows/TC-BRW-004-search-empty.yaml` |
| TC-BRW-005 | P1 | manual |
| TC-BRW-006 | P1 | manual |
| TC-BRW-007 | P1 | manual |
| TC-BRW-008 | P2 | manual |
| TC-CAM-001 | P0 | automated — `flows/TC-CAM-001-use-pose-opens-camera.yaml` |
| TC-CAM-002 | P1 | manual (device; sim cannot pinch reliably) |
| TC-CAM-003 | P1 | manual |
| TC-CAM-004 | P0 | automated — `flows/TC-CAM-004-grid-and-picker.yaml` |
| TC-CAM-005 | P1 | manual |
| TC-CAM-006 | P1 | manual |
| TC-CAM-007 | P1 | automated — `flows/TC-CAM-007-last-pose-after-relaunch.yaml` |
| TC-CAM-011 | P1 | automated — `flows/TC-CAM-011-explicit-pose-beats-remembered.yaml` |
| TC-CAM-008 | P2 | manual |
| TC-CAM-009 | P0 | automated — `flows/TC-CAM-009-camera-from-home-closes-to-home.yaml` |
| TC-CAM-010 | P1 | manual |
| TC-GAL-001 | P0 | automated — `flows/TC-GAL-001-empty-gallery.yaml` |
| TC-GAL-002 | P0 | manual (device) |
| TC-GAL-003 | P1 | manual |
| TC-GAL-004 | P1 | manual |
| TC-GAL-005 | P1 | manual |
| TC-GAL-006 | P1 | manual |
| TC-GAL-007 | P1 | manual |
| TC-PAY-001 | P0 | automated — `flows/TC-PAY-001-capture-gated.yaml` |
| TC-PAY-002 | P0 | automated — `flows/TC-PAY-002-capture-ungated.yaml` |
| TC-PAY-003 | P1 | automated — `flows/TC-PAY-003-paywall-signin-prompt.yaml` |
| TC-PAY-004 | P1 | pending (queued E2E, after M01 closes) |
| TC-PAY-005 | P1 | pending (queued E2E) |
| TC-PAY-006 | P1 | pending (queued E2E) |
| TC-PAY-007 | P1 | manual |
| TC-PAY-008 | P1 | automated — `flows/TC-PAY-008-close-paywall.yaml` |
| TC-DET-001 | P0 | automated — `flows/TC-DET-001-open-detail.yaml` |
| TC-DET-002 | P1 | manual |
| TC-DET-003 | P1 | manual |
| TC-DET-005 | P1 | pending (needs signed-in seam) |
| TC-DET-006 | P1 | manual |
| TC-DET-007 | P0 | automated — `flows/TC-DET-007-camera-back-returns-to-detail.yaml` |
| TC-DET-008 | P0 | automated — `flows/TC-DET-008-try-pose-visible-without-scroll.yaml` |
| TC-DET-009 | P1 | manual |
| TC-SAV-001 | P0 | automated — `flows/TC-SAV-001-saved-signed-out.yaml` |
| TC-SAV-002 | P1 | pending |
| TC-SAV-003 | P1 | pending |
| TC-SAV-004 | P1 | pending |
| TC-SAV-005 | P1 | pending |
| TC-SAV-006 | P1 | manual |
| TC-SAV-007 | P1 | pending |
| TC-SET-001 | P0 | automated — `flows/TC-SET-001-settings-about.yaml` |
| TC-SET-002 | P1 | manual |
| TC-SET-003 | P1 | manual |
| TC-SET-004 | P2 | manual |

Regenerate when a case changes; `check-traceability.sh` fails if an `automated:` case and its flow disagree.
