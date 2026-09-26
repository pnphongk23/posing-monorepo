# Privacy Policy & App Privacy — posing 1.0

This release is free, has no in-app purchases, and does not require an account or
sign-in. The policy and App Privacy declarations below must match the submitted
build and the services enabled in its configuration.

- **Privacy Policy URL:** https://sites.google.com/view/posingapp/privacy-policy
- **Support URL:** PO to provide a public HTTPS page.
- **Support email:** PO to confirm the public contact address.

## 1. ASC setup checklist

| Item | Status | Action |
| --- | --- | --- |
| Privacy Policy URL | Published URL listed above | Recheck that it opens publicly and reflects this release |
| Support URL | Pending | Provide a public HTTPS page; a `mailto:` link is not accepted as a URL |
| Support email | Pending | Confirm the address shown in ASC and the policy |
| App Privacy nutrition labels | Pending final build/config check | Declare only data collected by the submitted build |

## 2. Privacy Policy summary (EN)

### Photos and pose guides

The app accesses the camera when you take a photo and the photo library when you
choose an image. Captures are stored in your on-device gallery. When you request a
pose guide, the selected image is sent over an encrypted connection to our backend
and AI processing provider to generate that guide. Images are used to provide the
requested feature and are retained only as described in the published Privacy Policy.

### Accounts and payments

All features in this release are free. No account or sign-in is required, and the
current app flows do not request sign-in credentials or collect account identifiers
to provide the features in this release. There are no subscriptions or in-app
purchases, and the app does not collect purchase history or payment information.

### Analytics and diagnostics

Firebase Analytics, Crashlytics, and Remote Config are configured for the iOS app.
Confirm which services are active in the submitted build and declare any collected
device identifiers, usage events, or crash data accordingly. Do not describe a
configured SDK as active data collection until runtime behavior is confirmed.

## 3. App Privacy (Privacy Nutrition Labels)

These are proposed declarations for the current free, no-sign-in release. Verify
each conditional Firebase row against the exact App Store build before submitting.

| ASC data type | Declaration | Purpose | Linked to identity |
| --- | --- | --- | --- |
| Photos or Videos | Yes — collected when a user requests a pose guide | App Functionality | No, based on anonymous feature requests |
| Identifiers — Device ID | Declare only if collected by enabled Firebase services; verify on build | Analytics | No, if enabled |
| Diagnostics — Crash Data | Declare only if collected by enabled Crashlytics; verify on build | App Functionality | No, if enabled |
| Other — Usage Data | Declare only if collected by enabled Analytics; verify on build | Analytics | No, if enabled |
| User ID / Account | No — no sign-in or account identifier is used by current app flows | — | — |
| Purchase History | No — no purchases or subscriptions are offered | — | — |
| Tracking | No — no tracking for advertising | — | — |

Before submitting, reconcile the declarations with Firebase configuration, SDK
behavior, backend request logs, and the exact release build. Update the public Privacy
Policy and these labels if the app's data practices change.

## 4. Support URL options

| Option | URL | Note |
| --- | --- | --- |
| Product site | `https://<domain>/support` | Recommended long-term |
| GitHub Pages | Public static support page | Can host support contact details |
| `mailto:` | Not accepted as the ASC Support URL | Provide an HTTPS page |
