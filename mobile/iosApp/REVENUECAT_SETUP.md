# RevenueCat implementation runbook

The app uses the native `RevenueCat` CocoaPod (`~> 5.87`) as the sole StoreKit
owner. `RevenueCatAdapter` reads the public SDK key from the environment-specific
`REVENUECAT_PUBLIC_SDK_KEY` build setting through `Info.plist`; an unset,
placeholder, or example value leaves RevenueCat unconfigured.

External dependencies, supplied outside this repository:

- the real public SDK key for each environment;
- App Store Connect products and localized prices for `premium_annual` and
  `premium_monthly`;
- the `premium` entitlement and `default` offering in RevenueCat;
- RevenueCat Sandbox users and real Terms/Privacy URLs.

## Legal URL placeholders

The following values are documentation/build-configuration placeholders only;
they are never production values and must be replaced before App Review:

- `LEGAL_TERMS_URL=https://aipose.example.com/terms` — **PLACEHOLDER — replace-before-App-Review**
- `LEGAL_PRIVACY_URL=https://aipose.example.com/privacy` — **PLACEHOLDER — replace-before-App-Review**

When either value is unset or still marked as a placeholder, the runtime does
not open a legal URL.

The adapter never embeds prices, legal URLs, receipts, tokens, customer IDs, or
secret keys. StoreKit/RevenueCat localized metadata is authoritative for display.
RevenueCat owns purchase callbacks and transaction handling; no second StoreKit
listener or finish path is allowed.

## Deterministic local matrix

`PurchaseCoreTest` covers ready/default offering with annual highlighted and
monthly as anchor, confirmed entitlement, cancellation, failure, pending,
expiry, billing retry, grace, revocation, and no-offering. Only `ENTITLED`
enables the three approved capabilities.

## Sandbox matrix

Run only when the external key, products, offering, legal URLs, and sandbox user
are configured: load default offering, purchase annual and monthly, restore, cancel,
pending/error, expiry/revocation, billing retry/grace, and no-offering. Record
the observed RevenueCat state without storing receipts, tokens, or raw SDK errors.
