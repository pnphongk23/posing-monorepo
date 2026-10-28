# Maestro E2E suite (iOS, Dev scheme)

Bundle id `posing.camera.app`. Flows are P0 smoke; cases and IDs live in [docs/qa/test-cases](../../../docs/qa/test-cases/README.md).

## Run
1. Pick a simulator that is yours for the run (the lane uses `ai-pose-test`, coordinate the slot with the Feature lane). Never use a personal device-named sim.
2. Install the Dev build right before the run: `xcrun simctl install <UDID> <derived-data>/Build/Products/Debug-Dev-iphonesimulator/posing.app` (build: `xcodebuild -workspace mobile/iosApp/iosApp.xcworkspace -scheme Dev -destination 'id=<UDID>' -derivedDataPath /tmp/dd-shared build`; one build at a time, keep >1.5 GB disk free).
3. `MAESTRO_CLI_NO_ANALYTICS=1 maestro --device <UDID> test mobile/iosApp/maestro/flows` (single flow: pass its file). `launch` clears app state each flow.

Flows tagged `pending`/`manual` are excluded by `config.yaml`. Flows need network (server catalogue). `needs-account-flag` flows need `account_feature` on in the server config.

## Selectors
Prefer accessibility ids (`poses.first-card`, `search.field`, `gallery.empty.openCamera`, ...) and stable accessibility labels ("Open Camera", "Capture photo", "Open Settings").

## Identifier requests for the Feature lane
- Dock tabs (Poses / Gallery): ids `dock.poses`, `dock.gallery` (currently matched by visible text).
- Settings rows: ids for About, Account, Saved (currently labels).
- Pose detail primary action "Use this pose" and "Save pose": ids `poseDetail.use`, `poseDetail.save`.
- Paywall: ids on CTA, close, sign-in prompt.
- A capture seam on simulator (fixture image source) so TC-GAL-002 and TC-PAY-001 can be automated.
