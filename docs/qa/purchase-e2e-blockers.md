# Purchase E2E — blockers (refreshed 2026-10-31, main + lane-2 tree)

Target scenario: sign in → Test Store purchase → entitled → sign out → capture gated → sign in as a
second account → nothing carried over (cases TC-PAY-004/005/006). No secret is reproduced here; the
RevenueCat key is reported by prefix/status only.

## Status at a glance

| # | Blocker | Status | Evidence | Who unblocks |
|---|---|---|---|---|
| 1 | RevenueCat unconfigured in Dev builds (key placeholder) | **RESOLVED** for local Debug-Dev: a gitignored `test_…` **Test Store** key is supplied. A clean clone still resolves to the committed placeholder on purpose | committed placeholder `Config/Dev-Debug.xcconfig:4`; local override `Config/Dev-Debug.xcconfig:13` (`#include? "Secrets.local.xcconfig"`, gitignored); fail-closed resolution `RevenueCatAdapter.swift:209-232` | — (local file only; never commit it) |
| 2 | No StoreKit configuration file for a simulator purchase | **OBSOLETE** — a `.storekit` file is not needed and is the wrong channel here. The Test Store key routes `Purchases.purchase` to RevenueCat's synthetic store: no StoreKit, no sandbox Apple ID | `RevenueCatAdapter.swift:706-731`; `mobile/iosApp/REVENUECAT_SETUP.md:22-42`; no `*.storekit` under `mobile/`, no StoreKit reference in `iosApp.xcodeproj/xcshareddata/xcschemes/*.xcscheme` | — |
| 3 | No Debug override for `paywall_enabled` | **RESOLVED**: `-AIPosePaywallEnabled YES\|NO` (plus `-AIPoseAccountsEnabled`, `-AIPosePurchasesConfigured`), Debug-only | `AppConfig.swift:55-60,85-99,187-192`; `DebugLaunchArgumentOverride` `AppConfig.swift:185-215`; QA override seam `PremiumGateModel.swift:37-49` | — |
| 4 | No capture gating (nothing presented `PaywallScreen`) | **RESOLVED**: the shutter consults `PremiumGate` before camera readiness and the app root presents the paywall sheet | `PremiumGate.swift:68-84` (G1–G8); `CameraFeature.swift:53-59,333-339`; `AppFeatureRoot.swift:125-134`; `PaywallScreen` `SupportScreens.swift:545` | — |
| 5 | Dashboard: entitlement + products | **RESOLVED** (user): entitlement `posing_pro`, Test Store yearly + monthly in the `default` offering. Parity check by worker `6551b726` pending | `Config/*.xcconfig` ship `posing_pro` (`Dev-Debug.xcconfig:8`); expected offering shape `REVENUECAT_SETUP.md:78-84` | — (verify once on the sim) |
| 6 | **No test accounts** — the only hard blocker left for TC-PAY-004/005/006 | **OPEN**: email sign-in is automated (`signin.email`/`signin.password`/`signin.submit`) but needs real credentials at run time; nothing credential-shaped is in the repo and the Dev build signs in against the default server | `SignIn.swift:467,480,489,562`; default base URL `AppConfig.swift:8`; `docs/qa/test-cases/account.md:6` (TC-ACC-002 "pending (needs test credentials)") | user: two accounts (A and B) able to sign in via email on that server, handed over out of band as `E2E_EMAIL`/`E2E_PASSWORD` and `E2E_EMAIL_B`/`E2E_PASSWORD_B` |
| 7 | One purchase confirmed on a simulator | **OPEN** until worker `6551b726` reports the entitlement flip | — | that worker |

## What a simulator can and cannot do here

- **Can:** complete a purchase and flip `posing_pro`. The Test Store shows the SDK's own in-process
  dialog — **Test valid purchase / Test failed purchase / Cancel** — so Maestro can drive it by
  stable label. It is not a SpringBoard or StoreKit sheet.
- **Cannot:** prove "the photo is captured". The simulator has no capture device, so an entitled
  shutter press legitimately does nothing (`PremiumGate.swift:102-118`). The flows assert the *gate*
  answer (paywall asked or not) plus the provider's "Premium access confirmed." banner on a reopen;
  the real photo path stays a device case (`TC-GAL-002`).
- **Not usable:** the Apple sandbox flow needs a sandbox tester signed in on the device plus a
  SpringBoard password sheet — first-run interactive, so it stays manual.

## What is still missing, exactly

1. Two sign-in-capable accounts (A and B) on the server the Dev build talks to, supplied as env vars —
   without them TC-PAY-004/005/006 cannot run, and TC-ACC-002/004 stay pending too.
2. A Debug-Dev build that contains the Test Store key (`Info.plist → RevenueCatPublicSDKKey` starting
   `test_`), installed by the Feature lane on the lane-2 simulator.
3. QA lead GO for the simulator, then the drafted flows in `docs/qa/purchase-e2e/` promoted to
   `mobile/iosApp/maestro/flows` + `subflows` once they pass.

## What can run today (no credentials)

Unchanged and already automated: TC-PAY-001/002/003/008 (paywall gate surface via
`subflows/launch-paywall.yaml` with `-AIPosePaywallEnabled` + `-AIPosePurchasesConfigured`).
