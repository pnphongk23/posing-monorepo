# RevenueCat implementation runbook

The app uses the native `RevenueCat` SPM package (`5.87.1`) as the sole StoreKit
owner. `RevenueCatAdapter` reads two build settings through `Info.plist`:

- `REVENUECAT_PUBLIC_SDK_KEY` → `RevenueCatPublicSDKKey` (the public SDK key);
- `REVENUECAT_ENTITLEMENT_ID` → `RevenueCatEntitlementID` (the entitlement that
  grants premium capture).

An unset, placeholder (`REPLACE_WITH_…`, `$(SETTING)`) or example value for
either key leaves RevenueCat unconfigured: `isConfigured == false`, no store
call is made, and the paywall reports `unavailable`. Both values live in the
four `Config/*.xcconfig` files; until the user supplies them, builds stay
unconfigured on purpose.

The XcodeGen source of truth is `project.yml`. Use the `Dev` scheme for the
`Debug-Dev`/`Release-Dev` configurations and the `Prod` scheme for
`Debug-Prod`/`Release-Prod`. The four `.xcconfig` files under `Config/` carry
environment-specific public-key placeholders and legal URL placeholders; do
not commit real values.

External dependencies, supplied outside this repository:

- the real public SDK key for each environment;
- the entitlement id that is live in the RevenueCat dashboard; it must be copied
  verbatim into `REVENUECAT_ENTITLEMENT_ID` for the environment being released;
- the `default` offering (`offerings.current`) with an **annual** and a **monthly**
  package attached (`Offering.current ?? offerings["default"]` is resolved at
  runtime). The app selects packages by `packageType`, so it never embeds a store
  product id: the products themselves only exist in App Store Connect and the
  RevenueCat dashboard;
- RevenueCat Sandbox users and real Terms/Privacy URLs.

## Dashboard parity check (release gate)

1. `REVENUECAT_ENTITLEMENT_ID` in the shipped `.xcconfig` equals the entitlement
   identifier in the RevenueCat dashboard, character for character (spaces
   included — the dashboard value is authoritative).
2. The `default` offering has exactly one `.annual` and one `.monthly` package,
   both attached to a real App Store product with a localized price.
3. A sandbox purchase shows the entitlement as active; a second account on the
   same device stays unentitled.
4. Sign out, sign in again: the entitlement returns without tapping Restore.

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
