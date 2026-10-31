# Purchase E2E (TC-PAY-004/005/006/009) — promoted and passing

**Status:** all four flows pass on the lane-2 simulator (CF871F97, iPhone 16 / iOS 26.1) against
`/tmp/ai-pose-lane2-app-1.2/dev/posing.app` (Debug-Dev 1.2 build 16, Test Store key, entitlement
`posing_pro`), purchases made only through the RevenueCat Test Store dialog. They now live in the
suite — see `mobile/iosApp/maestro/flows/TC-PAY-00{4,5,6,9}-*.yaml` and
`mobile/iosApp/maestro/subflows/pay-*.yaml` — and this directory keeps the rationale, the
account-provisioning facts and the run recipe.

Evidence the flows rest on lives in the tables below; `docs/qa/purchase-e2e-blockers.md` has the
blocker history.

## What a simulator can do here (evidence)

| Question | Answer | Evidence |
|---|---|---|
| Can a purchase complete without the App Store? | Yes. The Dev-Debug key is a RevenueCat **Test Store** key (`test_…`, gitignored `Config/Secrets.local.xcconfig`, included last by `Config/Dev-Debug.xcconfig:13`), so `Purchases.purchase` uses RevenueCat's synthetic store: no StoreKit, no sandbox Apple ID, entitlements flip immediately | `REVENUECAT_SETUP.md:22-42`, `RevenueCatAdapter.swift:209-232` |
| What UI does the Test Store show? | The SDK's own in-app dialog with three buttons: **Test valid purchase**, **Test failed purchase**, **Cancel**. It is app-process UI (not a SpringBoard/StoreKit sheet), so Maestro sees and taps it by label | RevenueCat testing docs (iOS) + `RevenueCatAdapter.swift:706-731` |
| Could we have used a `.storekit` file instead? | No. None exists in the repo, the Dev scheme has no StoreKit configuration, and a scheme-level configuration is applied by Xcode's *run* action — Maestro launches via `simctl`/XCTest, so it would not apply | `find mobile -name "*.storekit"` empty; no `StoreKitConfigurationFileReference` in `mobile/iosApp/iosApp.xcodeproj/xcshareddata/xcschemes/*.xcscheme` |
| Could we use the real Apple sandbox? | Not reliably: iOS shows a SpringBoard-level password sheet, and a sandbox tester would have to be signed in on the simulator by hand. Out of scope for an automated lane | — |
| Can "capture succeeds" be asserted? | No. The simulator has no capture device, so an entitled shutter press legitimately does nothing (`PremiumGate.swift:102-118`). The flows assert the *gate* instead: unentitled press opens the paywall, entitled press does not, plus the provider's own confirmation banner on a reopen | `CameraFeature.swift:53-59`, `PremiumGate.swift:68-84` |
| Can sign-in be automated? | Yes, through the email form (`signin.email` / `signin.password` / `signin.submit`), with the two throwaway accounts supplied at run time. Nothing is stored in the flows | `SignIn.swift:467,480,489,562`, `SupportScreens.swift:224` |


## Design facts the flows rely on

- **A confirmed entitlement closes the paywall by itself** (`PaywallPresentation.gateSettled`,
  `PremiumGate.swift:140-151`, wired at `AppFeatureRoot.swift:207-213`). So the "Premium access
  confirmed." banner must not be asserted right after the purchase — it can be gone first. The flows
  read entitlement where it is stable instead: reopening the paywall from Settings → Premium
  (`settings.premium.row`, `SupportScreens.swift:385`).
- **Every paywall element is addressed by id, never by a price-bearing label**: `paywall.close`,
  `paywall.signin.apple`, `paywall.signin` (Google), `signin.emailEntry`, `paywall.plan.annual`,
  `paywall.plan.monthly`, `paywall.status`, `paywall.cta` — one declaration each in
  `PaywallAccessibilityID` (`SupportScreens.swift:541-557`), pinned by
  `PaywallAppleSignInTests.testEveryPaywallIdentifierIsDeclaredOnceAndRenderedFromTheConstants`. The only
  labels a flow reads are the stable code-owned ones: `Continue with <plan>` (`PaywallModel.ctaTitle`)
  and the status banner text behind `paywall.status`.
- **The signed-out paywall orders its sign-in options Apple → Google → email**
  (`PaywallSignInOption.allCases`, `SupportScreens.swift:567-578`), so TC-PAY-009 asserts Google with a
  `below: { id: paywall.signin.apple }` selector instead of relying on render order.
- **TC-PAY-005 cannot prove the entitlement was dropped**: a signed-out shutter is gated by branch G4
  regardless of entitlement (`PremiumGate.swift:75`). TC-PAY-006 is the real carry-over check — it
  requires B to be signed in (so G4 does not apply) and to be gated with loaded plans.

## Running (after GO + credentials)

**Credentials live in a chmod 600, gitignored file inside the repo tree but never in git** —
`mobile/iosApp/maestro/e2e.local.env` (ignored by `.gitignore:76`, `mobile/iosApp/maestro/*.local.env`),
keys `E2E_EMAIL`, `E2E_PASSWORD`, `E2E_EMAIL_B`, `E2E_PASSWORD_B` — and are passed to Maestro with `-e`.
They never appear in a flow, a doc, a commit or a log line: no `cat`, no `echo`, no copy of a value.

```bash
# lane-2 simulator only, one flow at a time
set -a; . mobile/iosApp/maestro/e2e.local.env; set +a     # this shell only
[ -n "$E2E_PASSWORD" ] && [ -n "$E2E_PASSWORD_B" ] || { echo "credential file not filled"; exit 1; }
maestro --device CF871F97-... test -e APP_ID=posing.camera.app \
  -e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD" \
  -e E2E_EMAIL_B="$E2E_EMAIL_B" -e E2E_PASSWORD_B="$E2E_PASSWORD_B" \
  docs/qa/purchase-e2e/flows/TC-PAY-004-purchase-annual-entitles.yaml
```

A flow started without the credentials fails immediately at the `assertTrue` guard in
`subflows/pay-sign-in.yaml` instead of tapping empty fields. Purchases in these flows go through the
RevenueCat **Test Store** dialog only — never a real StoreKit purchase.

## Where the two throwaway accounts come from (not in-app)

A fresh account **cannot** be created inside the app: the email sheet is sign-in only, and the server
has no sign-up route.

| Layer | Evidence |
|---|---|
| App form is email + password + submit only — no "create account", no forgot-password, no verification-code field | `SignIn.swift:327-378` (`EmailSignInModel`), `:450-580` (fields + dock), ids `signin.email`/`signin.password`/`signin.submit` |
| Client call is sign-in only | `APIClient.swift:107-110` → `POST /api/auth/email/signin` |
| Server router has only Google start/callback, `/email/signin`, `/apple/signin`, `/session`, `/refresh` — no signup/register/invite route | `web/services/pose-extract-server/src/routes/accountAuthRoutes.ts:97,113,157,215,257,268`; mounted at `app.ts:205` |
| `/email/signin` is a Supabase **password grant** (`/auth/v1/token?grant_type=password`): an unknown email answers `401 INVALID_CREDENTIALS`, it does not create the user | `accountAuthRoutes.ts:175-190`, `:13` |
| An unconfirmed account answers `403 EMAIL_NOT_CONFIRMED` ("Confirm your email address.") | `accountAuthRoutes.ts:14,189-196`; copy `SignIn.swift:52-54` |
| The Account row is created lazily on the first successful sign-in, i.e. only *after* Supabase already knows the user | `accountAuthRoutes.ts:208` (`accountStore.upsert`) |

So `qa-e2e-a` / `qa-e2e-b` must be created **outside** the app — Supabase dashboard *Add user* (or the
Admin API `POST /auth/v1/admin/users`) on the project behind the production server — with the email
already confirmed (auto-confirm, or "email confirm" ticked), otherwise every sign-in returns the
`EMAIL_NOT_CONFIRMED` copy above. Then hand the four values over via
`mobile/iosApp/maestro/e2e.local.env`.

## Re-running and repeatability

- Run them the normal way: `mobile/iosApp/maestro/run.sh <udid> flows/TC-PAY-004-…yaml` (the suite
  runner passes `APP_ID`), or `maestro test` directly with the same `-e` values.
- **TC-PAY-004 needs a first-run state**: it proves a purchase *grants* access, so its negative
  control expects the account to hold nothing yet. A Test Store subscription persists on the
  account's RevenueCat customer, so after one successful run that control sees an entitled account.
  Reset the subscription in the dashboard (or use a fresh account) before treating a 004 red as a
  regression. TC-PAY-005/006 tolerate both states: their A-side purchase only runs when the shutter
  still gates, and their assertions are about sign-out / second-account behaviour.
