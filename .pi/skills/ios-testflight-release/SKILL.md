---
name: ios-testflight-release
description: Archive, export, validate, upload, and verify this project's iOS build in TestFlight/App Store Connect via xcodebuild and altool, incl. the project's custom keychain fast-path auth, bounded auth preflight, and one-upload policy. Use whenever the user asks to release, upload, push, archive, export, validate, or check processing for the ai-pose iOS app.
---

# iOS TestFlight Release

CLI release path for `ai-pose`. TestFlight distribution only, never an App Store
public release. Does not fix product code, change signing/bundle IDs,
commit/push/tag, assign testers, publish metadata, alter phased release, submit
for review, or deploy the backend.

## Proven build-3 example (reference)

Real successful TestFlight upload for sanity-checking your own output (never
reuse as a value):

- iOS marketing `1.0`, build `3`, bundle `posing.camera.app` (keychain item names below are local and unchanged)
- `UPLOAD SUCCEEDED`; Delivery UUID: `1a7eb5d5-2b1b-46d8-b922-18c3b1a61749`
- Transfer: `10,012,231 bytes in 0.043s`
- IPA SHA-256: `f456318e1e20ee31e757acc598905bde835c8b31cd563441060eff74a2013c79`
- TestFlight only; no App Store release, no tester assignment.

A successful upload proves App Store delivery accepted the IPA, not that
processing completed; query delivery/status before claiming a processing state.

## Authority and lane safety

1. Confirm explicit release authorization and whether a Paseo release lane is
   active. If a release Lính is the executor, keep the coordinator read-only and
   send corrections only to that Lính. No second release worker, no
   self-operating against lane policy.
2. Wait for the Shared Element/mobile lane to report literal `APPROVED`; confirm
   the independent Code Vương go-ahead and a stable, quiescent worktree.
3. Never archive/export/upload or edit mobile/project files while that lane
   runs. Do not reset, clean, checkout, stash, commit, push, tag, or create
   another agent.
4. If a required test fails, stop `RELEASE_BLOCKED_TEST_FAILURE`. Do not waive or
   repair an unrelated product failure inside the release task.

## Read-only preflight

Record baseline:

```bash
git rev-parse HEAD
git branch --show-current
git status --porcelain=v1
git diff --stat
git diff --check
```

Run gates from repo root, after approval and again immediately before archive:

```bash
./gradlew :composeApp:allTests
./gradlew :composeApp:compileKotlinIosSimulatorArm64
git diff --check
```

Report test count and every failure; a known failure is still a failure (e.g.
do not waive `PosesViewModelTest.testPullToRefreshSingleFlightNoDuplicateLoad`).

Inspect release path without changing tracked files: Workspace
`mobile/iosApp/iosApp.xcworkspace`; Scheme `iosApp`; Configuration `Release`;
source `mobile/iosApp/project.yml`; bundle ID, team, marketing version, signing
identities, provisioning profiles, prior archives, prior build numbers; Xcode
and `xcrun altool --version`. Inspect and report current runtime endpoints
unmodified: `SERVER_BASE_URL` in
`mobile/composeApp/src/commonMain/kotlin/com/aipose/data/AppConfig.kt` and
`baseUrl` in
`mobile/shared/src/commonMain/kotlin/com/aipose/data/PoseServiceLocator.kt`. A
dev/ngrok endpoint is not a blocker for the requested TestFlight build.

## Version and build number

Discover the highest uploaded build; keep marketing version unchanged. The
latest known accepted upload is `1.0 (3)`, so the next candidate is `4` unless
App Store Connect reports a higher build. Use the next unique integer via
xcodebuild override and temp plist. This project historically hardcodes
`CFBundleVersion=1`; when `CURRENT_PROJECT_VERSION` is inert, use an ignored
temp plist under `/tmp` (never edit the tracked plist):

```bash
xcodebuild archive \
  -workspace mobile/iosApp/iosApp.xcworkspace \
  -scheme iosApp \
  -configuration Release \
  -archivePath /tmp/aipose-release/iosApp-<marketing>-<build>.xcarchive \
  CURRENT_PROJECT_VERSION=<build> \
  INFOPLIST_FILE=/tmp/aipose-release/Info.plist \
  -destination 'generic/platform=iOS'
```

Do not reuse a build number. Errors `-19232`/`-19241` with `previousBundleVersion`
mean ASC already has that build; query delivery status instead of re-uploading.

## Fast authenticated altool path (DEFAULT for this project)

Use the bundled wrapper from the repository root:

```bash
ALTOOL_FAST=.agents/skills/ios-testflight-release/scripts/altool-fast.sh
"$ALTOOL_FAST" providers
```

The wrapper reads the dedicated custom-keychain path from
`~/.config/camerapose/altool-keychain-path`, unlocks that project keychain,
captures service `camerapose-appstore` for account
`tolaphamnhuphong@gmail.com` directly into a child-only exported environment
variable, invokes altool with `@env:ALTOOL_APP_PASSWORD`, and unsets it on exit.
It never prints or writes the credential. The custom keychain's intentionally
permissive local policy was explicitly authorized for this project only.

Do **not** use `-p @keychain:camerapose-appstore` on this machine. Duplicate or
ACL-incompatible login-keychain entries previously blocked altool inside
`SecItemCopyMatching` before any network request. Do not ask for the password
again while the custom-keychain item remains present and authenticates.

`providers` is the mandatory bounded credential preflight and must finish before
archive/upload. It times out after 30 seconds. Failure means
`BLOCKED_CREDENTIALS`; do not start an upload. The wrapper also supports:

```bash
"$ALTOOL_FAST" validate /tmp/aipose-release/export/iosApp.ipa
"$ALTOOL_FAST" upload   /tmp/aipose-release/export/iosApp.ipa
"$ALTOOL_FAST" status   <delivery-uuid>
```

Bounds are 120 seconds for validation/status and 300 seconds for upload. A timed
out upload is ambiguous: never retry until App Store status is checked.

For manual diagnosis, redact secrets and inspect only process metadata:

```bash
ps -o pid,etime,state,%cpu,%mem,command -p <pid>
lsof -nP -a -p <pid> -i
wc -c /tmp/aipose-release/altool.log
sample <pid> 1 1 | grep -m1 -E 'SecItemCopyMatching|CFNetwork|NSURLSession'
```

No sockets + zero output + `SecItemCopyMatching` proves a local credential hang,
not Apple upload latency. Once proven, stopping that pre-network process and
starting one upload with the verified wrapper is not a duplicate network upload.

## Failure mode: local keychain hang (not Apple latency)

9-20 minute `altool` hangs here are NOT Apple latency. Signs: ~0% CPU, no
network socket, zero log bytes, stack in `SecItemCopyMatching`. Duplicate or
ACL-incompatible `@keychain` items cause this locally. Do not wait 15-20 min.
On no-output + no-network + `SecItemCopyMatching`, classify as a local
keychain/credential hang, stop after gathering that evidence, fix auth (dedupe
items / use the custom path above), then make ONE fresh upload, never a
duplicate retry.

## Archive and export

CLI only. Archive must be generic iOS Release, no simulator slices, contain
dSYMs, no dev-only secrets/config. ExportOptions outside the repo (e.g.
`/tmp/aipose-release/ExportOptions.plist`) with the installed Xcode's accepted
method, normally `app-store-connect`, discovered team ID, and
`uploadSymbols=false` when symbol credentials are unavailable.

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/aipose-release/iosApp-<marketing>-<build>.xcarchive \
  -exportPath /tmp/aipose-release/export \
  -exportOptionsPlist /tmp/aipose-release/ExportOptions.plist
```

Inspect IPA bundle ID, marketing/build, distribution signature, embedded store
profile, `get-task-allow=false`, `beta-reports-active=true`, architecture,
SHA-256. Preserve archive, IPA, sanitized logs, ExportOptions, dSYMs unless the
user chooses cleanup.

## Remote validation and one-upload policy

Require local IPA inspection first (bundle ID, version/build, signing/profile,
architecture, hashes) before any remote call. Remote `altool --validate-app` may
hang; run only with proven `@env` auth and a bounded timeout. If it hangs before
network, stop and follow the one-upload policy; no blind validate retries.

After auth preflight and gates: archive the current dirty approved worktree
with the unique next build, export the `app-store-connect` IPA, run bounded
remote validation, and upload EXACTLY once using the wrapper. Remote validation
is useful but must not be retried blindly if Apple returns no response; local
IPA/signing inspection remains mandatory.

```bash
ALTOOL_FAST=.agents/skills/ios-testflight-release/scripts/altool-fast.sh
"$ALTOOL_FAST" validate /tmp/aipose-release/export/iosApp.ipa
"$ALTOOL_FAST" upload   /tmp/aipose-release/export/iosApp.ipa
"$ALTOOL_FAST" status   <delivery-uuid>
```

If upload is ambiguous (timeout/no Delivery UUID), do not retry. Query the
Delivery UUID if one exists; otherwise inspect App Store Connect/build-number
evidence before any newly authorized attempt.

Capture Delivery UUID, then query bounded statuses (`uploaded`, `processing`,
`valid`, `internal testing`). No release, tester assignment, metadata
publishing, phased release, commit/push/tag/PR, or backend deploy.

## Credential recovery

Do not recreate or modify credential items during a normal release. If either
`~/.config/camerapose/altool-keychain-path` or its `camerapose-appstore` item is
genuinely absent, expired, or revoked, stop `BLOCKED_CREDENTIALS` and request
fresh explicit authorization. Never fall back to plaintext argv, login-keychain
`@keychain:` lookup, or a silent credential-context switch.

## Verify acceptance and processing

Capture sanitized `VERIFY SUCCEEDED`, `UPLOAD SUCCEEDED`, and Delivery UUID. A
successful upload proves delivery accepted the IPA, not that processing
completed. With a delivery ID, query via `--build-status --delivery-id ...`
and record e.g. `BETA_INTERNAL_TESTING`, `PROCESSING`, or `FAILED`. Without a
delivery ID or API-capable query, report the exact boundary: upload accepted /
request ID known, later processing not verified.

## Final report

Include: executor/lane + status; approval & quiescence evidence; HEAD, branch,
porcelain count, staged changes, diff stat; exact gate commands/results, test
count; current runtime endpoint values (inspected, unmodified);
workspace/scheme/configuration, bundle ID, team, version/build; sanitized
archive/export/validate/upload/status commands/results; archive/IPA paths,
SHA-256, signing/profile/dSYM checks; Delivery UUID, App Store acceptance,
processing state/boundary; the proven build-3 example as reference; credential
source type only (never value); files changed (ideally none), temp files,
cleanup, deviations; and confirmation of no source/stage/commit/push/release/
tester changes.

If an app-specific password was pasted into chat or another insecure channel,
recommend revoking it and creating a replacement after the release.