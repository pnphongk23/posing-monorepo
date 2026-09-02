---
work_item: 4
title: Verify IAP states, Sandbox, and iOS build
status: blocked
priority: P2
effort: TBD
dependencies:
  - 3
decision_dependencies:
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
  - "[[DEC-008-revenuecat-pricing-and-offerings|DEC-008]]"
status_reason: "chờ external config từ user: 2 IAP App Store Connect, RevenueCat offering/entitlement public key, sandbox tester, legal URLs; resume khi user cấp"
---

# Work Item 4: Verify IAP states, Sandbox, and iOS build

## Tasks

- Run KMP tests and the existing unsigned iosApp.xcworkspace build only after
  approval; preserve the known keychain-login limitation and do not archive or
  upload.
- Exercise offering/no-offering, purchase success/cancel/pending/failure,
  restore/no-match/success, expiry, billing retry/grace, revocation, and
  localized annual/monthly package display with annual highlighted and monthly
  as the comparison anchor.
- Verify Home Try Pose, Home Capture/Camera, and gated Gallery save/share, the
  absence of Splash/Premium-header triggers, and confirmed access only to those
  capabilities.
- Confirm the local product/type fixture is not treated as the authoritative
  RevenueCat flow; Sandbox is authoritative.
- Audit secrets, receipts/tokens, unexpected dependency upgrades, Android
  target changes, and PosesScreen.kt/Navigation.kt edits.

## Scope and affected files

Approved RevenueCat implementation files, tests, runbook/evidence, and existing
workspace only. No new workspace, archive, upload, signing/keychain repair,
commit, push, or tag.

## Success criteria

- Required checks pass with exact output recorded, or the concrete blocker is
  recorded as: Tôi không thể xác minh điều này hoạt động vì...
- No unconfirmed entitlement or free-core implication is shown.
- Conflict boundary and whole-plan consistency remain intact.

## Risks

- Real billing verification requires configured App Store Sandbox products and
  tester accounts; simulator/local fixture alone is insufficient.
- Existing dirty worktree can make attribution difficult.

## Required evidence

Exact commands/status, trigger/access matrix, purchase/restore state matrix,
Sandbox evidence, dependency/secret/conflict audit, and final consistency sweep.

## Remediation evidence and unresolved checks

- `./gradlew :composeApp:allTests` → `BUILD SUCCESSFUL in 1m 10s`.
- `./gradlew :composeApp:iosSimulatorArm64Test` → `BUILD SUCCESSFUL in 50s`.
- Material revision seam compile evidence: `CameraTab` now receives the
  App-root prior-context callback; Gallery detail receives a distinct share
  callback through Navigation; `PosesScreen.kt` remains untouched.
- `pod install` → `Pod installation complete! There are 7 dependencies from the Podfile and 22 total pods installed.`
- `git diff --check` passed with no output; dependency, secret, Android, and
  forbidden-file audits produced no violations.
- Minimal target-membership repair added `RevenueCatAdapter.swift` to the
  existing `iosApp.xcodeproj` group and Sources build phase; `plutil -lint`
  passed. Bounded unsigned `xcodebuild -workspace iosApp.xcworkspace
  -scheme iosApp -configuration Debug -sdk iphonesimulator
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build` completed with
  `IOS_RC=0` and `** BUILD SUCCEEDED **`. No archive or upload was attempted.
- Latest lead-bounded unsigned `xcodebuild` attempt was stopped by the
  180-second alarm with exit `142`; no completion result was produced:
  `Tôi không thể xác minh điều này hoạt động vì xcodebuild không hoàn tất trong
  giới hạn 180 giây và không cung cấp completion result.`
- `Tôi không thể xác minh điều này hoạt động vì RevenueCat Sandbox chưa được cấu hình public SDK key, products/offering và sandbox user.`

These unresolved checks keep WI4 and the Plan incomplete. Common fake/local
tests are not claimed as native or Sandbox evidence.
