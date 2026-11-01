# RevenueCat implementation runbook

The app uses the native `RevenueCat` SPM package (`5.87.1`) as the sole StoreKit
owner. `RevenueCatAdapter` reads two build settings through `Info.plist`:

- `REVENUECAT_PUBLIC_SDK_KEY` → `RevenueCatPublicSDKKey` (the public SDK key);
- `REVENUECAT_ENTITLEMENT_ID` → `RevenueCatEntitlementID` (the entitlement that
  grants premium capture).

An unset, placeholder (`REPLACE_WITH_…`, `$(SETTING)`) or example value for
either key leaves RevenueCat unconfigured: `isConfigured == false`, no store
call is made, and the paywall reports `unavailable`. That fail-open path is the
state of every fresh clone: the committed configurations carry no real key, so
builds stay unconfigured on purpose until a local file supplies one.

## Where the key lives

`REVENUECAT_ENTITLEMENT_ID` is committed: all four `Config/*.xcconfig` files ship
`posing_pro`, which must be the entitlement identifier in the RevenueCat
dashboard, character for character.

`REVENUECAT_PUBLIC_SDK_KEY` is not committed either. The real App Store key
(`appl_…`) lives in `mobile/.env`, which is gitignored, and every
`Config/*.xcconfig` reads it with an optional include placed **after** its own
placeholder line:

```
#include? "../../.env"
```

- `mobile/.env.example` is the tracked template: copy it to `mobile/.env` and
  fill in the key. One `KEY=VALUE` per line and `//` comments only — the file is
  included by xcconfig, where a `#` line other than an `#include` is a parse
  error.
- The include is optional and last, so xcconfig's last-assignment-wins order
  makes the real key override the committed placeholder. Without the file the
  build resolves the placeholder, `isValidRevenueCatKey` rejects it, and the app
  stays unconfigured (capture fails open) — which is why `scripts/ios-verify.sh`
  is green on a tree without any local key file.
- `Release-Prod` refuses to build without it: the target's first build phase,
  "RevenueCat key provenance (Release-Prod)", fails with
  `error: Release-Prod needs the RevenueCat App Store public SDK key (appl_…)`
  when the resolved value is unset, a `REPLACE_WITH_…` placeholder, or a `test_…`
  key. Other configurations exit that phase immediately.
- The key is public and shippable — it is compiled into the app bundle — so
  keeping it out of the repository is tidiness and release hygiene, not secrecy.
  It is present in older commits; do not rewrite history for it.
- Release worktrees are clean checkouts and therefore have no `mobile/.env`:
  copy it in **before** archiving (e.g. `cp /path/to/main/checkout/mobile/.env
  mobile/.env` in `/tmp/rel-1.1`). `/tmp` is wiped on reboot, so the main
  checkout's copy is the one to keep, and a worktree's `.env` goes away with the
  worktree.

A RevenueCat **Test Store** key (`test_…`) is a different thing: it points at a
fake store, so it goes into `mobile/iosApp/Config/Secrets.local.xcconfig`
(gitignored via `mobile/iosApp/Config/*.local.xcconfig`), and only
`Config/Dev-Debug.xcconfig` includes it, as its **last** line:

```
#include? "Secrets.local.xcconfig"
```

- It sits after both the placeholder and the `mobile/.env` include because
  xcconfig settings resolve top-down and the last assignment wins; above them it
  would have no effect. That also means a `Debug-Dev` build with both files uses
  the Test Store key.
- `Dev-Release`, `Prod-Debug` and `Prod-Release` must never include it. A Test
  Store key points at a fake store, where purchases succeed and entitlements flip
  without money moving — so it belongs in a Debug-Dev build and nowhere else.
- `RevenueCatConfigReleaseGuardTests` in
  `mobile/iosApp/iosAppTests/Services/AppConfigTests.swift` fails the Dev test run
  if any other configuration can reach a `*.local.xcconfig`, if any committed
  `REVENUECAT_PUBLIC_SDK_KEY` starts with `test_`, if `Dev-Debug` stops including
  the file last, if a configuration stops including `mobile/.env` after its
  placeholder, if `mobile/.env.example` ever holds a usable key, or if a
  configuration stops shipping `posing_pro`. It reads the committed `.xcconfig`
  files, `.env.example` and `Info.plist` only, and never opens the local key
  files.
- The release gate repeats the key check on the archived bundle, because a
  `REVENUECAT_PUBLIC_SDK_KEY=…` on the `xcodebuild` line overrides the
  configurations and is invisible to any in-tree test. See
  `.agents/skills/ios-testflight-release/SKILL.md`.

An unconfigured build also **never blocks capture**: the client gate is
fail-open whenever it cannot confirm the purchase context (no key, no link,
offline, or a session change whose answer has not arrived), so only a confirmed
"no access" for the signed-in Account opens the paywall. For QA on a placeholder
build, pass `-AIPosePaywallEnabled YES` plus `-AIPosePurchasesConfigured YES`
(Debug only) to reach the paywall surface; that override states the precondition
— *configured, and the signed-in user holds no entitlement* — and fabricates no
plan, purchase or access.

The XcodeGen source of truth is `project.yml`. Use the `Dev` scheme for the
`Debug-Dev`/`Release-Dev` configurations and the `Prod` scheme for
`Debug-Prod`/`Release-Prod`. The four `.xcconfig` files under `Config/` carry
environment-specific public-key placeholders and legal URL placeholders; do
not commit real values.

External dependencies, supplied outside this repository:

- the public SDK key for each environment: the RevenueCat **Test Store** key for
  the local `Debug-Dev` lane, kept in `Config/Secrets.local.xcconfig` as described
  above, and the App Store key (`appl_…`) for the PROD configurations, kept in
  `mobile/.env` (template: `mobile/.env.example`) and never committed;
- the dashboard entitlement `posing_pro`, already pinned in all four
  `Config/*.xcconfig` files. Renaming it in the dashboard means editing those four
  lines in the same change, or the paywall reports `unavailable`;
- the `default` offering (`offerings.current`) with the store **yearly** product
  attached to an **Annual** (`.annual`) package and the **monthly** product
  attached to a **Monthly** (`.monthly`) package
  (`Offering.current ?? offerings["default"]` is resolved at runtime). The app
  selects packages by `packageType`, so it never embeds a store product id: the
  products themselves only exist in App Store Connect and the RevenueCat
  dashboard;
- RevenueCat Sandbox users and real Terms/Privacy URLs.

## Dashboard parity check (release gate)

1. `REVENUECAT_ENTITLEMENT_ID` in the shipped `.xcconfig` equals the entitlement
   identifier in the RevenueCat dashboard, character for character (spaces
   included — the dashboard value is authoritative). Today that value is
   `posing_pro` in all four configurations.
2. The `default` offering has exactly one `.annual` and one `.monthly` package,
   attached to the yearly and the monthly App Store product, each with a
   localized price.
3. The archived `Info.plist` value of `RevenueCatPublicSDKKey` does not start with
   `test_` (the check is in the TestFlight skill; a Test Store key is a
   Debug-Dev-only key), and the `Release-Prod` build did not have to be forced
   through the "RevenueCat key provenance" phase — that phase failing means
   `mobile/.env` was missing from the worktree.
4. A sandbox purchase shows the entitlement as active; a second account on the
   same device stays unentitled.
5. Sign out, sign in again: the entitlement returns without tapping Restore.

If any of these fail, the paywall stays truthful (`unavailable`) or unentitled
rather than granting access — but the release is blocked.

## Legal URLs

The app's current legal pages are:

- `LEGAL_TERMS_URL=https://sites.google.com/view/posingapp/terms-of-service`
- `LEGAL_PRIVACY_URL=https://sites.google.com/view/posingapp/privacy-policy`

When either value is unset or still marked as a placeholder, the runtime does
not open a legal URL.

The adapter never embeds prices, legal URLs, receipts, tokens, customer IDs, or
secret keys. StoreKit/RevenueCat localized metadata is authoritative for display.
RevenueCat owns purchase callbacks and transaction handling; no second StoreKit
listener or finish path is allowed.

## Deterministic local matrix

`AIPOSE_BYPASS_PREMIUM=1` is a local capability only when both conditions hold:
the binary is Debug and `AIPoseEnvironment` is `DEV`. It is disabled for all
PROD configurations, including `Debug-Prod`.

`PurchaseCoreTest` covers ready/default offering with annual highlighted and
monthly as anchor, confirmed entitlement, cancellation, failure, pending,
expiry, billing retry, grace, revocation, and no-offering. Only `ENTITLED`
enables the three approved capabilities.

## Sandbox matrix

Run only when the external key, products, offering, legal URLs, and sandbox user
are configured: load default offering, purchase annual and monthly, restore, cancel,
pending/error, expiry/revocation, billing retry/grace, and no-offering. Record
the observed RevenueCat state without storing receipts, tokens, or raw SDK errors.
