# Purchase E2E — what blocks it (checked 2026-10-29, HEAD f8a49cc)

Target scenario: sign in → StoreKit test purchase → sign out → capture gated → sign in as another account → no entitlement (cases TC-PAY-003..006, TC-ACC-002/004).

| # | Blocker | Evidence | Who unblocks |
|---|---|---|---|
| 1 | RevenueCat is unconfigured in every Dev build: SDK key and entitlement id are placeholders, so the paywall reports `unavailable` and no store call is made | `mobile/iosApp/Config/Dev-Debug.xcconfig:4,8` (`REPLACE_WITH_…`); `RevenueCatAdapter.configureFromEnvironment` returns unconfigured; `REVENUECAT_SETUP.md` ("builds stay unconfigured on purpose"). Product ids are the open decision Q-261028-04 | user (real Dev SDK key + entitlement id + products) |
| 2 | No StoreKit configuration file in the repo or the Dev scheme, so a Simulator purchase has nothing to transact against | `find mobile -name "*.storekit"` is empty | Feature lane, once ids from #1 exist |
| 3 | No Debug override for `paywall_enabled`: it only comes from remote config (Firestore); only `-AIPoseAccountEnabled` exists locally | `AppConfig.swift` (`isPaywallEnabled` has no `#if DEBUG` override); production Firestore must not be touched | Feature lane: add `-AIPosePaywallEnabled` like the account switch |
| 4 | No test accounts or sign-in stub: the Dev build talks to the production server by default; `-AIPoseAPIBaseURL` can point it to a local stub, but none is in the repo | `AppConfig.debugBaseURLOverride` | Feature lane: local auth stub or two dedicated test accounts |
| 5 | The Simulator has no camera, so "capture gated" cannot be triggered by the shutter | `TC-PAY-001` pending | Feature lane: fixture image seam, or run on a device |

Not run: nothing in this scenario can execute until #1 and #3 are resolved; #2, #4 and #5 follow. What can run now: TC-PAY-003 (signed-out paywall) only after #3.
